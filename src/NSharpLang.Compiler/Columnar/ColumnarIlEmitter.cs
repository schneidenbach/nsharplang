using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// One top-level function's parsed signature plus its columnar body node tables, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. The body table arrays are produced per-function by
/// the parser kernel <c>ParseStatementNodes</c>; <see cref="BodyRoot"/> is that body's root statement index.
/// </summary>
public sealed class ColumnarFunctionInput
{
    public ColumnarFunctionInput(
        string name, string returnCanonical, string[] paramNames, string[] paramCanonicals,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        int bodyRoot)
    {
        Name = name;
        ReturnCanonical = returnCanonical;
        ParamNames = paramNames;
        ParamCanonicals = paramCanonicals;
        Kinds = kinds;
        ValueStarts = valueStarts;
        ValueLengths = valueLengths;
        ChildStart = childStart;
        ChildCount = childCount;
        ChildIndices = childIndices;
        BodyRoot = bodyRoot;
    }

    public string Name { get; }
    public string ReturnCanonical { get; }
    public string[] ParamNames { get; }
    public string[] ParamCanonicals { get; }
    public int[] Kinds { get; }
    public int[] ValueStarts { get; }
    public int[] ValueLengths { get; }
    public int[] ChildStart { get; }
    public int[] ChildCount { get; }
    public int[] ChildIndices { get; }
    public int BodyRoot { get; }
}

/// <summary>
/// COLUMNAR PIPELINE — stage 4 SPIKE (docs/design/roadmap-to-done.md). Proof that the columnar node tables can
/// drive IL emission END-TO-END with no C# AST: for a single trivial function it emits a real .NET assembly
/// (one static method) whose body IL is generated DIRECTLY from the columnar statement/expression tables, then
/// returns the assembly bytes so a caller can load + invoke it. This is the de-risking spike for Stage 4 — the
/// emit primitives (<c>ldarg</c> / <c>ldc.i4</c> / arithmetic / <c>ret</c>) are exactly what the full columnar
/// codegen will emit; later slices grow the supported surface and route through <c>ILCompiler</c> proper.
///
/// Deliberately narrow: top-level <c>func</c> with INT params/return only (mixed-type arithmetic would need
/// conversions this spike does not emit). Statements: <c>:=</c> int locals, a simple <c>local = expr</c>
/// assignment, Return (value required), an <c>if</c>/<c>else</c> where BOTH branches always return (no
/// fall-through), and a <c>while</c> loop whose body does not always return. Value expressions: a parameter, a
/// <c>:=</c> local, an int literal, a parenthesized expr, an int unary <c>-</c>/<c>~</c>, or an int +/-/* binary.
/// <c>if</c> conditions are an
/// int comparison (<c>&lt; &gt; &lt;= &gt;= == !=</c>) only. Anything else returns false (the adapter declines
/// → the C# path is unaffected).
/// </summary>
public sealed class ColumnarIlEmitter
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStart;
    private readonly int[] _childCount;
    private readonly int[] _childIndices;
    private readonly string _source;
    private readonly Dictionary<string, int> _paramOrdinals;
    private readonly IReadOnlyDictionary<string, Type> _paramTypes;
    private readonly Type _returnType;
    private readonly ILGenerator _il;
    // Sibling top-level functions callable from this body, by name -> (declared method, param types, return
    // type). All are declared (pass 1) before any body is emitted (pass 2), so a forward/self call resolves to
    // a MethodBuilder whose body is not yet emitted — the token is baked at CreateType/Save. Includes this
    // function itself, so direct recursion works. Param/return types are carried (rather than reflected) because
    // MethodBuilder.GetParameters()/ReturnType is unsupported before the type is created — and a Call checks each
    // argument's type against the callee's param types (int and bool are both i4, so a mismatch would otherwise
    // produce verifiable-but-wrong IL rather than declining).
    private readonly IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType)> _siblings;
    // `:=` locals declared so far, by name. Each local's type is its LocalBuilder.LocalType (inferred from the
    // initializer), so the type-aware emitter checks assignments and reads against it.
    private readonly Dictionary<string, LocalBuilder> _locals = new(StringComparer.Ordinal);
    // Enclosing loops' break/continue targets (innermost on top). `break` branches to the loop's end label,
    // `continue` to its condition-check label. A break/continue outside any loop declines.
    private readonly Stack<(Label Break, Label Continue)> _loopLabels = new();

    private ColumnarIlEmitter(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStart, int[] childCount, int[] childIndices, string source,
        Dictionary<string, int> paramOrdinals, IReadOnlyDictionary<string, Type> paramTypes, Type returnType,
        ILGenerator il,
        IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType)> siblings)
    {
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStart = childStart;
        _childCount = childCount;
        _childIndices = childIndices;
        _source = source;
        _paramOrdinals = paramOrdinals;
        _paramTypes = paramTypes;
        _returnType = returnType;
        _il = il;
        _siblings = siblings;
    }

    // The types the type-aware emitter currently handles: int/bool/long scalars (double/string are later
    // slices), plus a single-dimension ARRAY of a supported element type (e.g. int[], long[]). (Mixed int/long
    // arithmetic — implicit widening — is not modelled; an all-long or all-int expression is required.)
    private static bool IsSupportedType(Type t) =>
        t == typeof(int) || t == typeof(bool) || t == typeof(long) || t == typeof(string) || t == typeof(char)
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!));

    // Element types the array read/write paths can emit ldelem/stelem for (int/long today; string/bool/char
    // arrive with those types). bool/double are intentionally excluded until their element opcodes are added.
    private static bool IsSupportedElementType(Type t) => t == typeof(int) || t == typeof(long);

    /// <summary>
    /// Resolve a canonical N# type string (e.g. "int", "int[]") to its CLR <see cref="Type"/>. Handles a single
    /// trailing "[]" as a single-dimension array of a builtin element; non-builtins/unsupported shapes fail.
    /// </summary>
    private static bool TryResolveType(string canonical, out Type type)
    {
        if (canonical.EndsWith("[]", StringComparison.Ordinal))
        {
            if (TryResolveBuiltin(canonical.Substring(0, canonical.Length - 2), out var elementType))
            {
                type = elementType.MakeArrayType();
                return true;
            }
            type = null!;
            return false;
        }
        return TryResolveBuiltin(canonical, out type);
    }

    /// <summary>Canonical N# primitive type name → its CLR <see cref="Type"/>. Non-builtins are unsupported.</summary>
    public static bool TryResolveBuiltin(string canonical, out Type type)
    {
        type = canonical switch
        {
            "int" => typeof(int),
            "long" => typeof(long),
            "uint" => typeof(uint),
            "ulong" => typeof(ulong),
            "short" => typeof(short),
            "ushort" => typeof(ushort),
            "byte" => typeof(byte),
            "sbyte" => typeof(sbyte),
            "bool" => typeof(bool),
            "char" => typeof(char),
            "double" => typeof(double),
            "float" => typeof(float),
            "string" => typeof(string),
            _ => null!,
        };
        return type != null;
    }

    /// <summary>
    /// Build a one-method assembly for <paramref name="funcName"/> whose body IL is emitted from the columnar
    /// tables. Returns false (no assembly) for any unsupported type or body shape. The emitted type is
    /// <c>ColumnarSpike</c> and the method is static. Thin wrapper over <see cref="TryEmitColumnarAssembly"/>.
    /// </summary>
    public static bool TryEmitSingleFunctionAssembly(
        string funcName, string returnCanonical, string[] paramNames, string[] paramCanonicals,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, int bodyRoot, out byte[] assembly)
    {
        var input = new ColumnarFunctionInput(
            funcName, returnCanonical, paramNames, paramCanonicals,
            kinds, valueStarts, valueLengths, childStart, childCount, childIndices, bodyRoot);
        return TryEmitColumnarAssembly("ColumnarSpike", new[] { input }, source, out assembly);
    }

    /// <summary>
    /// Build a single assembly containing ALL of <paramref name="funcs"/> as static methods on one type
    /// (<paramref name="typeName"/>), each body's IL emitted from its columnar tables. This is the standalone
    /// columnar backend's assembly seam (the chosen Stage 4j routing — a columnar-first pipeline that owns
    /// emission, not a re-parse hook into the C# ILCompiler). Two-pass: pass 1 resolves types and DECLARES every
    /// method (so a body can later resolve a call to a sibling method that is declared but not yet emitted —
    /// the foundation for slice 4i); pass 2 emits each body. Returns false (no assembly) if ANY function is
    /// ineligible (non-int type or an unsupported body shape) — the whole program declines, keeping the C# path
    /// authoritative. INT-ONLY for now (untyped <c>add</c>/<c>ldc.i4</c>); later slices add type-aware emission.
    /// </summary>
    public static bool TryEmitColumnarAssembly(
        string typeName, IReadOnlyList<ColumnarFunctionInput> funcs, string source, out byte[] assembly)
    {
        assembly = Array.Empty<byte>();
        if (funcs.Count == 0)
            return false;

        var builder = new PersistedAssemblyBuilder(new AssemblyName(typeName), typeof(object).Assembly);
        var module = builder.DefineDynamicModule(typeName);
        var type = module.DefineType(typeName, TypeAttributes.Public | TypeAttributes.Class);

        // Pass 1: resolve every signature (int-only) and declare all methods up front. Build the sibling map
        // (name -> declared method + param count) so pass-2 bodies can `call` any function — including forward
        // references and self-recursion — resolving to a MethodBuilder whose body is not yet emitted.
        var methods = new MethodBuilder[funcs.Count];
        var ordinalsByFunc = new Dictionary<string, int>[funcs.Count];
        var paramTypesByFunc = new Dictionary<string, Type>[funcs.Count];
        var returnTypeByFunc = new Type[funcs.Count];
        var siblings = new Dictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType)>(StringComparer.Ordinal);
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            if (!TryResolveType(fn.ReturnCanonical, out var returnType) || !IsSupportedType(returnType))
                return false;
            var paramTypes = new Type[fn.ParamNames.Length];
            var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
            var paramTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
            for (var i = 0; i < fn.ParamNames.Length; i++)
            {
                if (!TryResolveType(fn.ParamCanonicals[i], out var pt) || !IsSupportedType(pt))
                    return false;
                paramTypes[i] = pt;
                ordinals[fn.ParamNames[i]] = i;
                paramTypeMap[fn.ParamNames[i]] = pt;
            }
            methods[f] = type.DefineMethod(
                fn.Name, MethodAttributes.Public | MethodAttributes.Static, returnType, paramTypes);
            ordinalsByFunc[f] = ordinals;
            paramTypesByFunc[f] = paramTypeMap;
            returnTypeByFunc[f] = returnType;
            // A duplicate top-level function name is an overload set the spike does not model — decline the
            // whole program rather than silently pick one (a real call would be ambiguous).
            if (!siblings.TryAdd(fn.Name, (methods[f], paramTypes, returnType)))
                return false;
        }

        // Pass 2: emit each body into its declared method's IL stream.
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            var il = methods[f].GetILGenerator();
            var emitter = new ColumnarIlEmitter(
                fn.Kinds, fn.ValueStarts, fn.ValueLengths, fn.ChildStart, fn.ChildCount, fn.ChildIndices,
                source, ordinalsByFunc[f], paramTypesByFunc[f], returnTypeByFunc[f], il, siblings);
            // An int function must return on every path (NL305): the body must always return, else the emitted
            // IL would fall off the end with no `ret` (invalid). Decline a non-returning body to the C# analyzer.
            if (!emitter.AlwaysReturns(fn.BodyRoot) || !emitter.EmitStatement(fn.BodyRoot))
                return false;
        }

        type.CreateType();
        using var stream = new MemoryStream();
        builder.Save(stream);
        assembly = stream.ToArray();
        return true;
    }

    private bool EmitStatement(int idx)
    {
        switch (_kinds[idx])
        {
            case 25: // Block — emit each statement in order.
            {
                // Block scoping: a `:=` local declared in this block leaves scope when the block ends, so a
                // later reference (e.g. a loop-body local read after the loop) correctly resolves to nothing
                // and declines, rather than reading a method-level slot that may be unassigned (invalid IL).
                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    var child = Child(idx, n);
                    if (!EmitStatement(child))
                        return false;
                    // A statement that unconditionally transfers control — always-returns, or a direct
                    // `break`/`continue` — must be the LAST in its block; anything after it is unreachable (an
                    // NL312 diagnostic). Decline rather than emit code after the transfer `ret`/`br`, keeping the
                    // C# analyzer/codegen authoritative. (A break/continue nested inside an `if` is conditional,
                    // so only a DIRECT break/continue child counts here.)
                    var transfers = AlwaysReturns(child) || _kinds[child] == 21 || _kinds[child] == 22;
                    if (transfers && n != _childCount[idx] - 1)
                        return false;
                }

                var blockLocals = new List<string>();
                foreach (var name in _locals.Keys)
                {
                    if (!outerLocals.Contains(name))
                        blockLocals.Add(name);
                }

                foreach (var name in blockLocals)
                    _locals.Remove(name);
                return true;
            }

            case 20: // Return [value] — a value is REQUIRED (a value-less `return` would emit `ret` with an empty
                     // stack = invalid IL); decline it. The value's type must match the declared return type.
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0), out var retType) || retType != _returnType)
                    return false;
                _il.Emit(OpCodes.Ret);
                return true;

            case 24: // VariableDeclaration (`:=`): emit the initializer, declare a local of the initializer's
            {        // type (inferred), store into it.
                var name = Text(idx);
                // Decline a local that shadows a parameter or redeclares a local: N# treats shadowing as a
                // diagnostic (and a same-`:=` redeclaration as an error), which the spike does not model —
                // declining keeps the C# analyzer authoritative rather than silently compiling it.
                if (_paramOrdinals.ContainsKey(name) || _locals.ContainsKey(name))
                    return false;
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0), out var initType) || !IsSupportedType(initType))
                    return false;
                var local = _il.DeclareLocal(initType);
                _il.Emit(OpCodes.Stloc, local);
                _locals[name] = local;
                return true;
            }

            case 27: // If [condition, then, else?] — general form covering all four then/else
            {        // fall-through-vs-return combinations, with a fall-through merge label.
                var childCount = _childCount[idx];
                if (childCount != 2 && childCount != 3)
                    return false;
                if (!EmitCondition(Child(idx, 0)))
                    return false;

                var thenStmt = Child(idx, 1);
                var elseLabel = _il.DefineLabel();
                _il.Emit(OpCodes.Brfalse, elseLabel);   // condition false -> else branch (or the merge end if no else)

                // then-branch. Scope its `:=` locals so a BRACELESS `:=` does not leak past the if (a Block
                // then-branch already self-scopes; this also covers the braceless single-statement form).
                var beforeThen = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(thenStmt))
                    return false;
                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!beforeThen.Contains(name))
                        _locals.Remove(name);
                }

                if (childCount == 2)
                {
                    // if-WITHOUT-else (a guard clause): the brfalse already targets the merge. Both edges
                    // reach it with an empty stack (a fall-through then-branch is net-zero; a returning
                    // then-branch ends in `ret` and never reaches it).
                    _il.MarkLabel(elseLabel);
                    return true;
                }

                // if-WITH-else. The unconditional branch over the else-block (and the end label it targets)
                // are emitted ONLY when the then-branch can FALL THROUGH to them — exactly the EmitIf fix.
                // If the then-branch always returns, that `br` is dead and would mark a label that could
                // land at the bare method end (the EmitIf/EmitSwitch hazard). The function-level
                // always-returns gate guarantees that when the if itself falls through (both branches
                // fall, or one falls), a later statement follows, so the merge is never the bare method end.
                var thenFallsThrough = !AlwaysReturns(thenStmt);
                var endLabel = _il.DefineLabel();
                if (thenFallsThrough)
                    _il.Emit(OpCodes.Br, endLabel);
                _il.MarkLabel(elseLabel);

                var elseStmt = Child(idx, 2);
                var beforeElse = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(elseStmt))
                    return false;
                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!beforeElse.Contains(name))
                        _locals.Remove(name);
                }

                if (thenFallsThrough)
                    _il.MarkLabel(endLabel);
                return true;
            }

            case 23: // ExpressionStatement — a SIMPLE `=` assignment (kind 14) to a `:=` local OR an array
            {        // element `a[i] = value`. Compound ops (`+=`), param/field targets, and bare side-effecting
                     // calls decline.
                var expr = Child(idx, 0);
                if (_kinds[expr] != 14 || Text(expr) != "=")
                    return false;
                var target = Child(expr, 0);

                if (_kinds[target] == 10) // array element write: a[i] = value
                {
                    // Stelem order is (array, index, value): emit the array ref, the int index, the value, store.
                    if (!EmitExpression(Child(target, 0), out var arrayType) || !arrayType.IsSZArray)
                        return false;
                    var elementType = arrayType.GetElementType()!;
                    if (!EmitExpression(Child(target, 1), out var indexType) || indexType != typeof(int))
                        return false;
                    if (!EmitExpression(Child(expr, 1), out var elementValueType) || elementValueType != elementType)
                        return false;
                    if (elementType == typeof(int)) _il.Emit(OpCodes.Stelem_I4);
                    else if (elementType == typeof(long)) _il.Emit(OpCodes.Stelem_I8);
                    else return false; // other element types arrive with their type slices.
                    return true;
                }

                if (_kinds[target] != 6 || !_locals.TryGetValue(Text(target), out var assignTarget))
                    return false;
                if (!EmitExpression(Child(expr, 1), out var valueType) || valueType != assignTarget.LocalType)
                    return false;
                _il.Emit(OpCodes.Stloc, assignTarget);
                return true;
            }

            case 26: // While [condition, body] — emit `check: cond; brfalse end; body; br check; end:`. The
            {        // stack is empty at both merge labels (cond pushes a bool, brfalse pops it; the body is
                     // net-zero), so it is stack-consistent. The body must NOT always return (a degenerate
                     // loop that exits on the first iteration) — decline that rather than emit a dead back-edge.
                var body = Child(idx, 1);
                if (AlwaysReturns(body))
                    return false;
                var checkLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                if (!EmitCondition(Child(idx, 0)))
                    return false;
                _il.Emit(OpCodes.Brfalse, endLabel);
                // Scope the body's `:=` locals so they leave scope at the loop end. A Block body self-scopes;
                // this also covers a BRACELESS single-statement body (e.g. a bare `:=`), which is not a Block.
                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                // `break` exits to endLabel, `continue` re-tests at checkLabel; both reach their target with an
                // empty stack (the body up to the transfer is net-zero), so they are stack-consistent.
                _loopLabels.Push((endLabel, checkLabel));
                var bodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!bodyEmitted)
                    return false;
                var bodyLocals = new List<string>();
                foreach (var name in _locals.Keys)
                {
                    if (!outerLocals.Contains(name))
                        bodyLocals.Add(name);
                }

                foreach (var name in bodyLocals)
                    _locals.Remove(name);
                _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);
                return true;
            }

            case 21: // Break — branch to the innermost loop's end label.
                if (_loopLabels.Count == 0)
                    return false;
                _il.Emit(OpCodes.Br, _loopLabels.Peek().Break);
                return true;

            case 22: // Continue — branch to the innermost loop's condition-check label.
                if (_loopLabels.Count == 0)
                    return false;
                _il.Emit(OpCodes.Br, _loopLabels.Peek().Continue);
                return true;

            default: // spike: Block / Return / `:=` / assignment / if-else / while / break / continue.
                return false;
        }
    }

    /// <summary>
    /// Emit an `if`/`while` CONDITION as a bool (i4 0/1) on the stack for a following <c>brfalse</c>/<c>brtrue</c>.
    /// Now that the expression emitter is type-aware, a condition is ANY bool expression — a comparison, a bool
    /// literal/local/param, a bool-returning call, or a logical-not — verified by its reported type, so a
    /// non-bool (e.g. an int) can never reach a branch. Anything that is not statically bool declines.
    /// </summary>
    private bool EmitCondition(int idx)
    {
        return EmitExpression(idx, out var type) && type == typeof(bool);
    }

    /// <summary>
    /// Whether this statement always exits via a return — the same columnar subset as the diagnostics pass
    /// (Return; a Block whose any statement returns; an If with an else where both branches return). Used to
    /// guarantee the emitted `if` has no fall-through.
    /// </summary>
    private bool AlwaysReturns(int idx)
    {
        switch (_kinds[idx])
        {
            case 20: // Return
                return true;
            case 25: // Block
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    if (AlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;
            case 27: // If [cond, then, else?]
                return _childCount[idx] == 3 && AlwaysReturns(Child(idx, 1)) && AlwaysReturns(Child(idx, 2));
            default:
                return false;
        }
    }

    // Emit `idx` as a value on the stack and report its CLR type via `type`. Returns false (declining the whole
    // function) on any unsupported form or a type mismatch the spike does not model. The reported type drives
    // correct opcode selection and prevents cross-type mixing (e.g. a bool leaking into int arithmetic) that
    // would diverge from N#'s type rules.
    private bool EmitExpression(int idx, out Type type)
    {
        type = null!;
        switch (_kinds[idx])
        {
            case 6: // Identifier — a `:=` local (ldloc, type = LocalType) or a parameter (ldarg, type from the
                    // signature); the two name sets are disjoint (a local shadowing a param is declined at decl).
            {
                var name = Text(idx);
                if (_locals.TryGetValue(name, out var local))
                {
                    _il.Emit(OpCodes.Ldloc, local);
                    type = local.LocalType;
                    return true;
                }

                if (_paramOrdinals.TryGetValue(name, out var ordinal))
                {
                    EmitLoadArgument(ordinal);
                    type = _paramTypes[name];
                    return true;
                }

                return false;
            }

            case 0: // IntLiteral — plain decimal `int`, or a signed `long` literal (digits + L/l). The lexer keeps
            {       // the suffix in the token text. Unsigned suffixes (u/U, UL/LU) are not in the supported set.
                var text = Text(idx);
                var last = text.Length > 0 ? text[text.Length - 1] : '\0';
                if (last == 'L' || last == 'l')
                {
                    var digits = text.Substring(0, text.Length - 1);
                    if (digits.Length > 0 && (digits[digits.Length - 1] == 'u' || digits[digits.Length - 1] == 'U'))
                        return false; // UL/LU = ulong, unsupported.
                    if (long.TryParse(digits, out var longValue))
                    {
                        _il.Emit(OpCodes.Ldc_I8, longValue);
                        type = typeof(long);
                        return true;
                    }
                    return false;
                }
                if (last == 'u' || last == 'U') // uint/ulong, unsupported.
                    return false;
                if (int.TryParse(text, out var value))
                {
                    _il.Emit(OpCodes.Ldc_I4, value);
                    type = typeof(int);
                    return true;
                }

                return false;
            }

            case 4: // BoolLiteral — true/false (i4 1/0).
                switch (Text(idx))
                {
                    case "true": _il.Emit(OpCodes.Ldc_I4_1); type = typeof(bool); return true;
                    case "false": _il.Emit(OpCodes.Ldc_I4_0); type = typeof(bool); return true;
                    default: return false;
                }

            case 2: // CharLiteral — `'x'` -> ldc.i4 of the code point (type char). Escaped/multi-char literals
            {       // (e.g. '\n') are not yet processed -> decline (the C# path stays authoritative).
                var raw = Text(idx);
                if (raw.Length >= 2 && raw[0] == '\'' && raw[raw.Length - 1] == '\'')
                    raw = raw.Substring(1, raw.Length - 2);
                if (raw.Length != 1)
                    return false;
                _il.Emit(OpCodes.Ldc_I4, (int)raw[0]);
                type = typeof(char);
                return true;
            }

            case 3: // StringLiteral — emit Ldstr with the literal value. The token text is the source substring;
            {       // strip surrounding quotes if present. Escape sequences are NOT yet processed, so a literal
                    // containing a backslash declines (keeping the C# path authoritative for escapes).
                var raw = Text(idx);
                if (raw.Length >= 2 && raw[0] == '"' && raw[raw.Length - 1] == '"')
                    raw = raw.Substring(1, raw.Length - 2);
                if (raw.Contains('\\'))
                    return false;
                _il.Emit(OpCodes.Ldstr, raw);
                type = typeof(string);
                return true;
            }

            case 7: // Parenthesized — emit the inner expression, propagating its type.
                return EmitExpression(Child(idx, 0), out type);

            case 11: // Unary [operand] — int/long prefix `-`/`~`, or bool `!`. `++`/`--` decline.
            {
                if (!EmitExpression(Child(idx, 0), out var operandType))
                    return false;
                switch (Text(idx))
                {
                    case "-": // negate — Neg works on i4 and i8; result is the operand's numeric type.
                        if (operandType != typeof(int) && operandType != typeof(long)) return false;
                        _il.Emit(OpCodes.Neg); type = operandType; return true;
                    case "~": // bitwise not — Not works on i4 and i8.
                        if (operandType != typeof(int) && operandType != typeof(long)) return false;
                        _il.Emit(OpCodes.Not); type = operandType; return true;
                    case "!": // logical not on a bool: x == false.
                        if (operandType != typeof(bool)) return false;
                        _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); type = typeof(bool); return true;
                    default: return false;
                }
            }

            case 12: // Binary [left, right] — int/long arithmetic & bitwise, shifts, short-circuit `&&`/`||`, or a
            {        // comparison producing bool. Most operators need both operands the SAME type.
                var op = Text(idx);

                // Short-circuit `&&`/`||` MUST conditionally evaluate the right operand — both for C# semantics
                // and for safety (e.g. `i < n && a[i] == x` must not index a[i] when i >= n). So handle these
                // BEFORE evaluating either operand: emit left, branch on it, evaluate right only on the
                // non-short-circuiting path. Both operands and the result are bool.
                if (op == "&&" || op == "||")
                {
                    if (!EmitExpression(Child(idx, 0), out var shortLeftType) || shortLeftType != typeof(bool))
                        return false;
                    var shortLabel = _il.DefineLabel();
                    var endLabel = _il.DefineLabel();
                    // `&&` short-circuits to false when left is false; `||` to true when left is true.
                    _il.Emit(op == "&&" ? OpCodes.Brfalse : OpCodes.Brtrue, shortLabel);
                    if (!EmitExpression(Child(idx, 1), out var shortRightType) || shortRightType != typeof(bool))
                        return false;
                    _il.Emit(OpCodes.Br, endLabel);
                    _il.MarkLabel(shortLabel);
                    _il.Emit(op == "&&" ? OpCodes.Ldc_I4_0 : OpCodes.Ldc_I4_1);
                    _il.MarkLabel(endLabel);
                    type = typeof(bool);
                    return true;
                }

                if (!EmitExpression(Child(idx, 0), out var leftType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var rightType))
                    return false;

                // Shifts are special: the value is int/long, the shift COUNT is always int (not necessarily the
                // value's type), and the result is the value's type. Shr is the SIGNED (arithmetic) right shift,
                // matching C# for int/long; the columnar `>>` is a single binary operator here (the `>>` token
                // split only applies inside generic type arguments, not expression context).
                if (op == "<<" || op == ">>")
                {
                    if ((leftType != typeof(int) && leftType != typeof(long)) || rightType != typeof(int))
                        return false;
                    _il.Emit(op == "<<" ? OpCodes.Shl : OpCodes.Shr);
                    type = leftType;
                    return true;
                }

                // Every other binary operator requires both operands to be the SAME type (no implicit conversions).
                if (leftType != rightType)
                    return false;
                switch (op)
                {
                    case "+": case "-": case "*": case "/": case "%":
                        // Add/Sub/Mul/Div/Rem work on i4 and i8; the result is the operands' (shared) numeric
                        // type. Div/Rem are the SIGNED forms (matching C# for int/long); divide-by-zero and
                        // INT_MIN/-1 throw at runtime exactly as the C# path does.
                        if (leftType != typeof(int) && leftType != typeof(long)) return false;
                        _il.Emit(
                            op == "+" ? OpCodes.Add :
                            op == "-" ? OpCodes.Sub :
                            op == "*" ? OpCodes.Mul :
                            op == "/" ? OpCodes.Div :
                            OpCodes.Rem);
                        type = leftType;
                        return true;
                    case "&": case "|": case "^":
                        // Bitwise on int/long (And/Or/Xor work on i4 and i8); result is the shared numeric type.
                        if (leftType != typeof(int) && leftType != typeof(long)) return false;
                        _il.Emit(op == "&" ? OpCodes.And : op == "|" ? OpCodes.Or : OpCodes.Xor);
                        type = leftType;
                        return true;
                    case "<": case ">": case "<=": case ">=":
                        // Ordering on int, long, or char (Clt/Cgt work on i4 and i8; a char is a non-negative i4
                        // so signed compares are correct).
                        if (leftType != typeof(int) && leftType != typeof(long) && leftType != typeof(char)) return false;
                        EmitComparison(op);
                        type = typeof(bool);
                        return true;
                    case "==": case "!=":
                        if (leftType == typeof(string))
                        {
                            // String equality is VALUE equality (String.op_Equality), NOT `ceq` (which compares
                            // references). `!=` negates the result.
                            _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                            if (op == "!=") { _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); }
                            type = typeof(bool);
                            return true;
                        }
                        // Equality on int, long, bool, or char (Ceq works on i4 and i8).
                        if (leftType != typeof(int) && leftType != typeof(long) && leftType != typeof(bool) && leftType != typeof(char)) return false;
                        EmitComparison(op);
                        type = typeof(bool);
                        return true;
                    default: return false;
                }
            }

            case 9: // Call [callee, args...] — a DIRECT call to a sibling top-level function only (incl. self).
            {
                var callee = Child(idx, 0);
                if (_kinds[callee] != 6) // callee must be a bare identifier — no member access / delegate expr.
                    return false;
                var name = Text(callee);
                // A local/param of the same name is a delegate/closure invocation the spike does not model.
                if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name))
                    return false;
                if (!_siblings.TryGetValue(name, out var target))
                    return false;
                var argCount = _childCount[idx] - 1;
                if (argCount != target.ParamTypes.Length) // arity must match (no overloads / defaults / params).
                    return false;
                // Each argument's type must match the callee's declared parameter type. int and bool are both i4
                // on the CLR stack, so without this check a mismatch (e.g. an int passed to a bool parameter)
                // would emit verifiable-but-semantically-wrong IL instead of declining to the C# path.
                for (var a = 1; a <= argCount; a++)
                {
                    if (!EmitExpression(Child(idx, a), out var argType) || argType != target.ParamTypes[a - 1])
                        return false;
                }
                _il.Emit(OpCodes.Call, target.Method);
                type = target.ReturnType;
                return true;
            }

            case 8: // MemberAccess [receiver] — `.Length` on an array or a string (-> int). The member name is
            {       // the value span. (Other member/property/field access is a host boundary; decline it.)
                if (Text(idx) != "Length")
                    return false;
                if (!EmitExpression(Child(idx, 0), out var receiverType))
                    return false;
                if (receiverType.IsSZArray)
                {
                    _il.Emit(OpCodes.Ldlen);     // pushes the array length as a native int...
                    _il.Emit(OpCodes.Conv_I4);   // ...narrowed to int (N# array length is int).
                    type = typeof(int);
                    return true;
                }
                if (receiverType == typeof(string))
                {
                    _il.Emit(OpCodes.Callvirt, typeof(string).GetProperty(nameof(string.Length))!.GetGetMethod()!);
                    type = typeof(int);
                    return true;
                }
                return false;
            }

            case 10: // IndexAccess [object, index] — array element READ (ldelem) or string char READ (get_Chars).
            {        // The index is int; the result type is the element type (array) or char (string).
                if (!EmitExpression(Child(idx, 0), out var indexedType))
                    return false;
                if (indexedType == typeof(string))
                {
                    if (!EmitExpression(Child(idx, 1), out var stringIndexType) || stringIndexType != typeof(int))
                        return false;
                    _il.Emit(OpCodes.Callvirt, typeof(string).GetMethod("get_Chars", new[] { typeof(int) })!);
                    type = typeof(char);
                    return true;
                }
                if (!indexedType.IsSZArray)
                    return false;
                var elementType = indexedType.GetElementType()!;
                if (!EmitExpression(Child(idx, 1), out var indexType) || indexType != typeof(int))
                    return false;
                if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(long)) _il.Emit(OpCodes.Ldelem_I8);
                else return false; // other element types arrive with their type slices.
                type = elementType;
                return true;
            }

            case 15: // New [type, args...] — only `new T[](size)` array allocation. child[0] is a TYPE subtree
            {        // (TYPE-kind semantics: 2 = Array, 0 = Simple); the single arg is the int length.
                var typeNode = Child(idx, 0);
                if (_childCount[idx] != 2 || _kinds[typeNode] != 2) // exactly one ctor arg; type must be Array.
                    return false;
                var elementNode = Child(typeNode, 0); // the array's element type subtree.
                if (_kinds[elementNode] != 0) // element must be a Simple builtin (not jagged/generic).
                    return false;
                if (!TryResolveBuiltin(Text(elementNode), out var newElementType) || !IsSupportedElementType(newElementType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sizeType) || sizeType != typeof(int)) // length: int.
                    return false;
                _il.Emit(OpCodes.Newarr, newElementType);
                type = newElementType.MakeArrayType();
                return true;
            }

            default:
                return false;
        }
    }

    // Emit the comparison opcode(s) for `op` over two like-typed values already on the stack, leaving an i4 bool.
    private void EmitComparison(string op)
    {
        switch (op)
        {
            case "<": _il.Emit(OpCodes.Clt); break;
            case ">": _il.Emit(OpCodes.Cgt); break;
            case "==": _il.Emit(OpCodes.Ceq); break;
            case "!=": _il.Emit(OpCodes.Ceq); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break;
            case "<=": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a > b)
            case ">=": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a < b)
        }
    }

    private void EmitLoadArgument(int index)
    {
        switch (index)
        {
            case 0: _il.Emit(OpCodes.Ldarg_0); break;
            case 1: _il.Emit(OpCodes.Ldarg_1); break;
            case 2: _il.Emit(OpCodes.Ldarg_2); break;
            case 3: _il.Emit(OpCodes.Ldarg_3); break;
            default:
                if (index <= 255)
                    _il.Emit(OpCodes.Ldarg_S, (byte)index);
                else
                    _il.Emit(OpCodes.Ldarg, index);
                break;
        }
    }

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);
}
