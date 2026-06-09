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

    // The types the type-aware emitter currently handles: int/bool/long/ulong scalars (double is a later
    // slice), plus a single-dimension ARRAY of a supported element type (e.g. int[], long[], ulong[]). (Mixed
    // arithmetic — implicit widening — is not modelled; an expression's operands must share one type.) ulong is
    // u8 on the stack like long (i8), but its arithmetic uses the UNSIGNED opcodes (Shr_Un/Div_Un/Rem_Un and
    // unsigned compares) — see the binary/comparison cases.
    private static bool IsSupportedType(Type t) =>
        t == typeof(int) || t == typeof(bool) || t == typeof(long) || t == typeof(ulong)
        || t == typeof(string) || t == typeof(char) || t == typeof(double) || t == typeof(float)
        || t == typeof(System.Text.StringBuilder)
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!));

    // Element types the array read/write/alloc paths can emit ldelem/stelem/newarr for: int/long/ulong (i4/i8),
    // char (u2), double (r8) / float (r4), and string (a reference element). bool is excluded until its element
    // opcodes land. ulong shares long's 8-byte slot (Ldelem_I8/Stelem_I8 move the bit pattern; the unsignedness is
    // purely in how the VALUE is operated on, not how it is stored/loaded).
    private static bool IsSupportedElementType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char) || t == typeof(string)
        || t == typeof(double) || t == typeof(float);

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
        // StringBuilder — the modelled mutable reference type — is a valid param/return/local type (a builder is
        // commonly passed IN to an append helper, e.g. AppendQuotedDiagnosticCommandArgument(builder, value)). It
        // is resolved here (param/return/local), NOT in TryResolveBuiltin, so `StringBuilder[]` stays unsupported
        // (array elements resolve through TryResolveBuiltin / IsSupportedElementType, which exclude it).
        if (canonical == "StringBuilder")
        {
            type = typeof(System.Text.StringBuilder);
            return true;
        }
        return TryResolveBuiltin(canonical, out type);
    }

    /// <summary>
    /// Decode the (quote-stripped) body of a char/string literal, resolving the common C-style escape sequences
    /// (<c>\n \r \t \\ \" \' \0 \a \b \f \v</c>) to their characters. Returns false for an unknown/unsupported
    /// escape (e.g. <c>\u</c>/<c>\x</c> or a trailing backslash) so that literal declines — keeping the C# path
    /// authoritative rather than mis-decoding. A body with no backslash is returned verbatim.
    /// </summary>
    private static bool TryDecodeLiteralBody(string body, out string decoded)
    {
        decoded = string.Empty;
        if (!body.Contains('\\'))
        {
            decoded = body;
            return true;
        }
        var sb = new System.Text.StringBuilder(body.Length);
        for (var i = 0; i < body.Length; i++)
        {
            var ch = body[i];
            if (ch != '\\')
            {
                sb.Append(ch);
                continue;
            }
            if (i + 1 >= body.Length)
                return false; // trailing backslash.
            i++;
            switch (body[i])
            {
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case '\\': sb.Append('\\'); break;
                case '"': sb.Append('"'); break;
                case '\'': sb.Append('\''); break;
                case '0': sb.Append('\0'); break;
                case 'a': sb.Append('\a'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'v': sb.Append('\v'); break;
                default: return false; // \u, \x, or unknown escape — decline.
            }
        }
        decoded = sb.ToString();
        return true;
    }

    // Parse a floating-point literal's body (type suffix already stripped by the caller) to its double value,
    // mirroring the C# path's ParseFloatLiteralValue: drop `_` digit separators, then parse invariant-culture.
    // An f-literal narrows the result to float at the call site; a double-literal uses it directly.
    private static bool TryParseFloatingLiteralBody(string body, out double value)
    {
        value = 0;
        var s = body.Trim().Replace("_", string.Empty);
        return double.TryParse(
            s,
            System.Globalization.NumberStyles.Float | System.Globalization.NumberStyles.AllowThousands,
            System.Globalization.CultureInfo.InvariantCulture,
            out value);
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
        return TryEmitColumnarAssembly("ColumnarSpike", "ColumnarSpike", new[] { input }, source, out assembly);
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
        string assemblyName, string typeName, IReadOnlyList<ColumnarFunctionInput> funcs, string source, out byte[] assembly)
    {
        assembly = Array.Empty<byte>();
        if (funcs.Count == 0)
            return false;

        var builder = new PersistedAssemblyBuilder(new AssemblyName(assemblyName), typeof(object).Assembly);
        var module = builder.DefineDynamicModule(assemblyName);
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
            // The return type may be `void` (a procedure — its body need not always-return and `return` takes
            // no value); otherwise it must be a supported VALUE type. `void` is valid ONLY as a return type, so
            // it is handled here and NOT admitted by IsSupportedType (which gates params/locals/arrays/values).
            Type returnType;
            if (fn.ReturnCanonical == "void")
                returnType = typeof(void);
            else if (!TryResolveType(fn.ReturnCanonical, out returnType) || !IsSupportedType(returnType))
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
            if (!emitter.EmitBody(fn.BodyRoot, returnTypeByFunc[f] == typeof(void)))
                return false;
        }

        type.CreateType();
        using var stream = new MemoryStream();
        builder.Save(stream);
        assembly = stream.ToArray();
        return true;
    }

    // Emit a function body. A VALUE function (non-void) must always-return on every path (NL305) — else the IL
    // would fall off the end with no `ret`; decline it to the C# analyzer. A VOID function (procedure) need not
    // always-return: emit the body, then a trailing `ret` IFF control can fall through to the method end (when
    // the body already always-returns via value-less `return`s, no trailing `ret` is emitted, so there is no
    // unreachable code).
    private bool EmitBody(int bodyRoot, bool isVoid)
    {
        if (!isVoid)
            return AlwaysReturns(bodyRoot) && EmitStatement(bodyRoot);
        var fallsThrough = !AlwaysReturns(bodyRoot);
        if (!EmitStatement(bodyRoot))
            return false;
        if (fallsThrough)
            _il.Emit(OpCodes.Ret);
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

            case 20: // Return [value?] — in a VOID function a value-less `return` emits a bare `ret`; in a VALUE
                     // function a value is REQUIRED (a value-less `ret` with an empty stack is invalid IL) and its
                     // type must match the declared return type. A value-bearing `return` in a void function, or a
                     // value-less one in a value function, declines (mismatched arity).
                if (_returnType == typeof(void))
                {
                    if (_childCount[idx] != 0)
                        return false;
                    _il.Emit(OpCodes.Ret);
                    return true;
                }
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
            {        // element `a[i] = value`, OR a bare CALL statement (a void BCL call such as `Array.Fill(...)`,
                     // or a sibling/BCL call whose non-void result is discarded). Compound ops (`+=`) decline.
                var expr = Child(idx, 0);

                if (_kinds[expr] == 9) // a bare call statement.
                {
                    // Emit the call. A void call (e.g. Array.Fill) leaves nothing on the stack; a NON-void call
                    // leaves its result, which is unused in statement position — discard it with `pop` (exactly
                    // what the C# path emits for a discarded call result, so the side effects + result are
                    // identical). This is the `helper(args)`-as-statement idiom (e.g. LinterImports.nl clearing
                    // flags for its side effect and ignoring the returned count).
                    if (!EmitExpression(expr, out var callType))
                        return false;
                    if (callType != typeof(void))
                        _il.Emit(OpCodes.Pop);
                    return true;
                }

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
                    else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Stelem_I8);
                    else if (elementType == typeof(char)) _il.Emit(OpCodes.Stelem_I2);
                    else if (elementType == typeof(double)) _il.Emit(OpCodes.Stelem_R8);
                    else if (elementType == typeof(float)) _il.Emit(OpCodes.Stelem_R4);
                    else if (elementType == typeof(string)) _il.Emit(OpCodes.Stelem_Ref);
                    else return false; // other element types arrive with their type slices.
                    return true;
                }

                if (_kinds[target] != 6)
                    return false;
                var targetName = Text(target);
                if (_locals.TryGetValue(targetName, out var assignTarget))
                {
                    // `local = expr` — store into the `:=` local (value type must match the local's type).
                    if (!EmitExpression(Child(expr, 1), out var valueType) || valueType != assignTarget.LocalType)
                        return false;
                    _il.Emit(OpCodes.Stloc, assignTarget);
                    return true;
                }
                if (_paramOrdinals.TryGetValue(targetName, out var paramOrdinal))
                {
                    // `param = expr` — store into the argument slot (`starg`). N# permits mutating a parameter
                    // (value params have value semantics, so the mutation is method-local, matching the C# path).
                    // The value's type must match the parameter's declared type.
                    if (!EmitExpression(Child(expr, 1), out var paramValueType) || paramValueType != _paramTypes[targetName])
                        return false;
                    EmitStoreArgument(paramOrdinal);
                    return true;
                }
                return false;
            }

            case 26: // While [condition, body] — emit `check: cond; brfalse end; body; [br check]; end:`. The
            {        // stack is empty at both merge labels (cond pushes a bool, brfalse pops it; the body is
                     // net-zero), so it is stack-consistent.
                var body = Child(idx, 1);
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
                // The bottom back-edge is reachable ONLY if the body can FALL THROUGH to it. If the body always
                // transfers on every path (a scan loop that `continue`s otherwise + `return`s, or a degenerate
                // run-once `{ return X }` body), it never falls through, so the bottom `br check` would be dead
                // code — skip it (the `continue`s already branch to checkLabel directly, so the loop still
                // iterates). This both AVOIDS unreachable IL and ADMITS the common scan-loop pattern that the
                // old blanket `AlwaysReturns(body)` decline wrongly rejected.
                if (!AlwaysReturns(body))
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

            case 0: // IntLiteral — decimal `int`, a signed `long` (L/l), or a `ulong` (a u/U AND an l/L suffix in
            {       // any order: UL/LU/ul/...). The lexer keeps the suffix in the token text. A BARE u/U (uint) is
                    // not in the supported set. Strip the trailing [uUlL] run and classify by which letters appear.
                var text = Text(idx);
                var end = text.Length;
                var sawU = false;
                var sawL = false;
                while (end > 0 && (text[end - 1] is 'u' or 'U' or 'l' or 'L'))
                {
                    if (text[end - 1] is 'u' or 'U') sawU = true; else sawL = true;
                    end--;
                }
                var digits = text.Substring(0, end);
                if (sawU && sawL) // ulong (u8): load the bit pattern via Ldc_I8.
                {
                    if (ulong.TryParse(digits, out var ulongValue))
                    {
                        _il.Emit(OpCodes.Ldc_I8, unchecked((long)ulongValue));
                        type = typeof(ulong);
                        return true;
                    }
                    return false;
                }
                if (sawU) // bare uint, not modelled.
                    return false;
                if (sawL) // signed long.
                {
                    if (long.TryParse(digits, out var longValue))
                    {
                        _il.Emit(OpCodes.Ldc_I8, longValue);
                        type = typeof(long);
                        return true;
                    }
                    return false;
                }
                if (int.TryParse(text, out var value))
                {
                    _il.Emit(OpCodes.Ldc_I4, value);
                    type = typeof(int);
                    return true;
                }

                return false;
            }

            case 1: // FloatLiteral — `3.5` / `3.5d` (double, r8 Ldc_R8) or `3.5f` (float, r4 Ldc_R4). An `m`/`M`
            {       // (decimal) suffix is a different type -> decline. The value is parsed identically to the C#
                    // path's ParseFloatLiteralValue (strip the type suffix, drop `_` separators, invariant parse),
                    // then narrowed to float for an f-literal (matching `Ldc_R4, (float)ParseFloatLiteralValue`).
                var raw = Text(idx);
                var last = raw.Length > 0 ? raw[raw.Length - 1] : '\0';
                if (last == 'm' || last == 'M')
                    return false; // decimal — not modelled.
                var isFloatLiteral = last == 'f' || last == 'F';
                var body = (isFloatLiteral || last == 'd' || last == 'D') ? raw.Substring(0, raw.Length - 1) : raw;
                if (!TryParseFloatingLiteralBody(body, out var doubleValue))
                    return false;
                if (isFloatLiteral)
                {
                    _il.Emit(OpCodes.Ldc_R4, (float)doubleValue);
                    type = typeof(float);
                }
                else
                {
                    _il.Emit(OpCodes.Ldc_R8, doubleValue);
                    type = typeof(double);
                }
                return true;
            }

            case 4: // BoolLiteral — true/false (i4 1/0).
                switch (Text(idx))
                {
                    case "true": _il.Emit(OpCodes.Ldc_I4_1); type = typeof(bool); return true;
                    case "false": _il.Emit(OpCodes.Ldc_I4_0); type = typeof(bool); return true;
                    default: return false;
                }

            case 2: // CharLiteral — `'x'` (or an escape like `'\n'`) -> ldc.i4 of the code point (type char).
            {
                var raw = Text(idx);
                if (raw.Length >= 2 && raw[0] == '\'' && raw[raw.Length - 1] == '\'')
                    raw = raw.Substring(1, raw.Length - 2);
                if (!TryDecodeLiteralBody(raw, out var charValue) || charValue.Length != 1)
                    return false;
                _il.Emit(OpCodes.Ldc_I4, (int)charValue[0]);
                type = typeof(char);
                return true;
            }

            case 3: // StringLiteral — N# string literals are RAW: the C# path emits `value.Trim('"')` with NO
            {       // escape processing (ILCompiler.GetStringLiteralRuntimeValue), so a backslash stays literal.
                    // Match that EXACTLY (Trim('"') over the source substring) — do NOT decode escapes here.
                _il.Emit(OpCodes.Ldstr, Text(idx).Trim('"'));
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
                    case "-": // negate — Neg works on i4/i8/r8/r4; result is the operand's numeric type. NOT valid on
                              // ulong (C# forbids unary minus on an unsigned type) — decline it. On double/float, Neg
                              // is the IEEE negate (-NaN stays NaN, -0.0 is distinct from 0.0), matching the C# path.
                        if (operandType != typeof(int) && operandType != typeof(long) && operandType != typeof(double) && operandType != typeof(float)) return false;
                        _il.Emit(OpCodes.Neg); type = operandType; return true;
                    case "~": // bitwise not — Not works on i4 and i8 (and on ulong's u8 bit pattern).
                        if (operandType != typeof(int) && operandType != typeof(long) && operandType != typeof(ulong)) return false;
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
                    if ((leftType != typeof(int) && leftType != typeof(long) && leftType != typeof(ulong)) || rightType != typeof(int))
                        return false;
                    // Shl is the same for signed/unsigned. `>>` is the SIGNED (arithmetic) Shr for int/long, but
                    // the UNSIGNED (logical, zero-fill) Shr_Un for ulong — matching C#'s ulong `>>`. A wrong Shr
                    // here would sign-extend a high-bit-set ulong.
                    _il.Emit(op == "<<" ? OpCodes.Shl : (leftType == typeof(ulong) ? OpCodes.Shr_Un : OpCodes.Shr));
                    type = leftType;
                    return true;
                }

                // NUMERIC PROMOTION (ECMA §12.4.7) for the modelled int-like types: int and char are BOTH i4 on
                // the stack, so a char/int mix promotes both to int with NO conversion IL (e.g. `c * (i + 1)` is
                // int). long/ulong/bool/string do NOT auto-promote (an int/long mix would need a conv) — they must
                // match exactly. `opType` is the type the operation runs as.
                Type opType;
                if (leftType == rightType)
                    opType = leftType;
                else if ((leftType == typeof(int) || leftType == typeof(char)) && (rightType == typeof(int) || rightType == typeof(char)))
                    opType = typeof(int);
                else
                    return false;

                // String CONCATENATION: `s1 + s2` -> String.Concat(string, string) (VALUE concat, matching the C#
                // path's result). Both operands are already on the stack. Only string+string is modelled (the
                // corpus' shape, e.g. `"diag-" + Math.Abs(hash).ToString("x")`); string+int etc. decline.
                if (op == "+" && opType == typeof(string))
                {
                    _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                    type = typeof(string);
                    return true;
                }
                switch (op)
                {
                    case "+": case "-": case "*": case "/": case "%":
                        // Add/Sub/Mul/Div/Rem work on i4, i8, and r8 (double); the result is `opType`'s numeric type.
                        // Div/Rem are SIGNED for int/long (UNSIGNED Div_Un/Rem_Un for ulong); on DOUBLE the same
                        // `div`/`rem` opcodes do IEEE FP division/remainder (x/0.0 -> ±Inf, 0.0/0.0 -> NaN — no
                        // throw, matching the C# path), so double is NOT unsignedDivRem. Integer divide-by-zero /
                        // INT_MIN÷-1 still throw exactly as the C# path does. A CHAR result promotes to INT (a char
                        // never survives an arithmetic op — `c - 'A'` is int; matches Analyzer.cs:12820's GetWiderType).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
                        var unsignedDivRem = opType == typeof(ulong);
                        _il.Emit(
                            op == "+" ? OpCodes.Add :
                            op == "-" ? OpCodes.Sub :
                            op == "*" ? OpCodes.Mul :
                            op == "/" ? (unsignedDivRem ? OpCodes.Div_Un : OpCodes.Div) :
                            (unsignedDivRem ? OpCodes.Rem_Un : OpCodes.Rem));
                        type = opType == typeof(char) ? typeof(int) : opType;
                        return true;
                    case "&": case "|": case "^":
                        // Bitwise on int/long/ulong (And/Or/Xor work on i4 and i8); result is `opType` (a char/int
                        // mix is opType=int, so `c & mask` works; a pure char&char declines as i4-but-not-int).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong)) return false;
                        _il.Emit(op == "&" ? OpCodes.And : op == "|" ? OpCodes.Or : OpCodes.Xor);
                        type = opType;
                        return true;
                    case "<": case ">": case "<=": case ">=":
                        // Ordering on int, long, char (signed Clt/Cgt; a char is a non-negative i4 so signed is
                        // correct), ulong (UNSIGNED Clt_Un/Cgt_Un — a ulong > long.MaxValue must compare as a large
                        // positive, not a negative i8), or double (ORDERED Clt/Cgt for `<`/`>`; the UNORDERED
                        // complement for `<=`/`>=` so a NaN operand yields false — see EmitComparison's isFloat path).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
                        EmitComparison(op, opType == typeof(ulong), opType == typeof(double) || opType == typeof(float));
                        type = typeof(bool);
                        return true;
                    case "==": case "!=":
                        if (opType == typeof(string))
                        {
                            // String equality is VALUE equality (String.op_Equality), NOT `ceq` (which compares
                            // references). `!=` negates the result.
                            _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                            if (op == "!=") { _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); }
                            type = typeof(bool);
                            return true;
                        }
                        // Equality on int, long, ulong, bool, char, double, or float (Ceq is bit-identical
                        // signed/unsigned; on double/float it is the IEEE ordered equal — NaN == NaN is false and
                        // NaN != NaN is true, which the `!=` negation of Ceq produces correctly).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(bool) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
                        EmitComparison(op);
                        type = typeof(bool);
                        return true;
                    default: return false;
                }
            }

            case 9: // Call [callee, args...] — a sibling top-level function (bare-identifier callee, incl.
            {       // self/recursion), or a BCL method call (instance on a string, or static on a type like Char)
                    // whose callee is a MemberAccess [receiver, method-name].
                var callee = Child(idx, 0);
                if (_kinds[callee] == 6) // bare identifier -> sibling function.
                {
                    var name = Text(callee);
                    // A local/param of the same name is a delegate/closure invocation the spike does not model.
                    if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name))
                        return false;
                    if (!_siblings.TryGetValue(name, out var target))
                        return false;
                    var argCount = _childCount[idx] - 1;
                    if (argCount != target.ParamTypes.Length) // arity must match (no overloads / defaults / params).
                        return false;
                    // Each argument's type must match the callee's declared parameter type. int and bool are both
                    // i4 on the CLR stack, so without this check a mismatch (e.g. an int passed to a bool
                    // parameter) would emit verifiable-but-semantically-wrong IL instead of declining.
                    for (var a = 1; a <= argCount; a++)
                    {
                        if (!EmitExpression(Child(idx, a), out var argType) || argType != target.ParamTypes[a - 1])
                            return false;
                    }
                    _il.Emit(OpCodes.Call, target.Method);
                    type = target.ReturnType;
                    return true;
                }
                if (_kinds[callee] == 8) // MemberAccess callee -> a BCL instance/static method call.
                    return TryEmitBclMethodCall(idx, callee, out type);
                return false;
            }

            case 8: // MemberAccess [receiver] — an ENUM CONSTANT (e.g. StringComparison.Ordinal), or `.Length` on
            {       // an array/string/StringBuilder (-> int). The member name is the value span.
                // An enum constant: a bare-identifier receiver naming the enum TYPE (not a value) + a member that
                // is one of its named constants -> load the constant's underlying int (an enum is its underlying
                // value on the stack). Only StringComparison is modelled (the corpus' only enum).
                var memberAccessReceiver = Child(idx, 0);
                if (_kinds[memberAccessReceiver] == 6)
                {
                    var receiverIdent = Text(memberAccessReceiver);
                    if (receiverIdent == "StringComparison"
                        && !_locals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (!TryGetStringComparisonValue(Text(idx), out var enumValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, enumValue);
                        type = typeof(StringComparison);
                        return true;
                    }
                }
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
                if (receiverType == typeof(System.Text.StringBuilder))
                {
                    _il.Emit(OpCodes.Callvirt, typeof(System.Text.StringBuilder).GetProperty(nameof(System.Text.StringBuilder.Length))!.GetGetMethod()!);
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
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                else return false; // other element types arrive with their type slices.
                type = elementType;
                return true;
            }

            case 15: // New [type, args...] — `new T[](size)` array allocation, OR `new string(char[], int, int)`
            {        // (the String(char[],int,int) constructor). child[0] is a TYPE subtree (2 = Array, 0 = Simple).
                var typeNode = Child(idx, 0);
                if (_kinds[typeNode] == 0) // a Simple type -> a constructor call (string or StringBuilder).
                {
                    var newTypeName = Text(typeNode);
                    if (newTypeName == "string")
                    {
                        // `new string(char[] value, int startIndex, int length)` — copy a char[] slice into a
                        // string. Emit the char[] then the two int args, then `newobj` the String ctor.
                        if (_childCount[idx] != 4)
                            return false;
                        if (!EmitExpression(Child(idx, 1), out var charArrType)
                            || !charArrType.IsSZArray || charArrType.GetElementType() != typeof(char))
                            return false;
                        if (!EmitArg(idx, 2, typeof(int)) || !EmitArg(idx, 3, typeof(int)))
                            return false;
                        var stringCtor = typeof(string).GetConstructor(new[] { typeof(char[]), typeof(int), typeof(int) });
                        if (stringCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, stringCtor);
                        type = typeof(string);
                        return true;
                    }
                    if (newTypeName == "StringBuilder")
                    {
                        // `new StringBuilder()` or `new StringBuilder(int capacity)`. (Other ctor overloads
                        // decline.)
                        var ctorArgCount = _childCount[idx] - 1;
                        System.Reflection.ConstructorInfo? sbCtor;
                        if (ctorArgCount == 0)
                            sbCtor = typeof(System.Text.StringBuilder).GetConstructor(Type.EmptyTypes);
                        else if (ctorArgCount == 1)
                            sbCtor = EmitArg(idx, 1, typeof(int))
                                ? typeof(System.Text.StringBuilder).GetConstructor(new[] { typeof(int) })
                                : null;
                        else
                            return false;
                        if (sbCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, sbCtor);
                        type = typeof(System.Text.StringBuilder);
                        return true;
                    }
                    return false; // other Simple-type constructors are a host boundary; decline.
                }
                if (_childCount[idx] != 2 || _kinds[typeNode] != 2) // array alloc: exactly one ctor arg; type must be Array.
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

            case 16: // Cast [type, operand] — explicit numeric conversion among int/long/char. child[0] is a
            {        // TYPE subtree (Simple); child[1] is the operand. Other casts (to/from string, bool, etc.)
                     // decline (the C# path stays authoritative).
                var castTypeNode = Child(idx, 0);
                if (_kinds[castTypeNode] != 0 || !TryResolveBuiltin(Text(castTypeNode), out var targetType))
                    return false;
                if (!IsCastableScalar(targetType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sourceType) || !IsCastableScalar(sourceType))
                    return false;
                // Emit the conversion only when the stack representation differs (char->int and same-type casts
                // are no-ops). The opcode is TARGET-driven, matching the C# path (TryGetNumericConversionOpcode):
                // -> double = conv.r8, -> float = conv.r4, -> long = conv.i8, -> char = conv.u2, -> int = conv.i4.
                // float/double->int truncates toward zero exactly as the C# path's conv.i4 does (same opcode).
                if (sourceType != targetType)
                {
                    if (targetType == typeof(double)) _il.Emit(OpCodes.Conv_R8);      // int/long/char/float -> double (widen)
                    else if (targetType == typeof(float)) _il.Emit(OpCodes.Conv_R4);  // int/long/char/double -> float
                    else if (targetType == typeof(long)) _il.Emit(OpCodes.Conv_I8);   // int/char/double/float -> long
                    else if (targetType == typeof(char)) _il.Emit(OpCodes.Conv_U2);   // int/long/double/float -> char (truncate)
                    else if (sourceType == typeof(long) || sourceType == typeof(double) || sourceType == typeof(float)) _il.Emit(OpCodes.Conv_I4); // long/double/float -> int
                    // char -> int is identity (the char is already an i4 code point): no opcode.
                }
                type = targetType;
                return true;
            }

            default:
                return false;
        }
    }

    // Scalars that participate in explicit numeric casts (int/long/char on the i4/i8 slots; double on r8, float on r4).
    private static bool IsCastableScalar(Type t) => t == typeof(int) || t == typeof(long) || t == typeof(char) || t == typeof(double) || t == typeof(float);

    // The underlying int value of a System.StringComparison named constant (the enum's documented stable values).
    // An enum on the CLR stack is just its underlying int, so an enum constant emits `ldc.i4 <value>`.
    private static bool TryGetStringComparisonValue(string name, out int value)
    {
        value = name switch
        {
            nameof(StringComparison.CurrentCulture) => 0,
            nameof(StringComparison.CurrentCultureIgnoreCase) => 1,
            nameof(StringComparison.InvariantCulture) => 2,
            nameof(StringComparison.InvariantCultureIgnoreCase) => 3,
            nameof(StringComparison.Ordinal) => 4,
            nameof(StringComparison.OrdinalIgnoreCase) => 5,
            _ => -1,
        };
        return value >= 0;
    }

    // Emit the comparison opcode(s) for `op` over two like-typed values already on the stack, leaving an i4 bool.
    // `unsigned` selects the unsigned ordering opcodes (Clt_Un/Cgt_Un) for ulong — equality (Ceq) is identical.
    // `isFloat` (double) uses the ORDERED Clt/Cgt for `<`/`>` (a NaN operand yields false), but `<=`/`>=` must
    // negate the UNORDERED complement (Cgt_Un/Clt_Un) so a NaN operand yields false too — matching C#'s float
    // comparison lowering (`a <= b` is `!(a cgt.un b)`). For int/ulong (no NaN) the complement equals the ordering.
    private void EmitComparison(string op, bool unsigned = false, bool isFloat = false)
    {
        var lt = unsigned ? OpCodes.Clt_Un : OpCodes.Clt;
        var gt = unsigned ? OpCodes.Cgt_Un : OpCodes.Cgt;
        var ltComplement = isFloat ? OpCodes.Clt_Un : lt;
        var gtComplement = isFloat ? OpCodes.Cgt_Un : gt;
        switch (op)
        {
            case "<": _il.Emit(lt); break;
            case ">": _il.Emit(gt); break;
            case "==": _il.Emit(OpCodes.Ceq); break;
            case "!=": _il.Emit(OpCodes.Ceq); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break;
            case "<=": _il.Emit(gtComplement); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a > b)
            case ">=": _il.Emit(ltComplement); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a < b)
        }
    }

    // A BCL method call whose callee is a MemberAccess [receiver, method-name]. A STATIC call (receiver is a
    // bare identifier naming a known type, e.g. `Char`) must be detected BEFORE the receiver is emitted (the
    // type name is not a value); an INSTANCE call emits the receiver value then dispatches on its type.
    private bool TryEmitBclMethodCall(int callIdx, int callee, out Type type)
    {
        type = null!;
        var memberName = Text(callee);
        var receiver = Child(callee, 0);
        var argCount = _childCount[callIdx] - 1;

        if (_kinds[receiver] == 6) // a bare identifier receiver that is NOT a value (local/param/sibling) is a type name.
        {
            var receiverName = Text(receiver);
            if (!_locals.ContainsKey(receiverName) && !_paramOrdinals.ContainsKey(receiverName) && !_siblings.ContainsKey(receiverName))
                return TryEmitStaticCall(callIdx, receiverName, memberName, argCount, out type);
        }

        if (!EmitExpression(receiver, out var receiverType)) // instance: receiver value goes on the stack first.
            return false;
        return TryEmitInstanceCall(callIdx, receiverType, memberName, argCount, out type);
    }

    // Static BCL calls (no receiver on the stack): a small whitelist. Char.IsLetterOrDigit/IsWhiteSpace(char) -> bool.
    private bool TryEmitStaticCall(int callIdx, string typeName, string member, int argCount, out Type type)
    {
        type = null!;
        // The receiver may be the type NAME `Char` (via `using System`) or the builtin alias `char` (the
        // lowercase keyword) — both bind to System.Char in N#/C#, so accept either.
        if ((typeName == "Char" || typeName == "char") && argCount == 1)
        {
            // Static System.Char methods taking a single char: classifiers (-> bool) and invariant case
            // transforms (-> char). The result type comes from the resolved method.
            MethodInfo? method = member switch
            {
                "IsLetterOrDigit" => typeof(char).GetMethod(nameof(char.IsLetterOrDigit), new[] { typeof(char) }),
                "IsLetter" => typeof(char).GetMethod(nameof(char.IsLetter), new[] { typeof(char) }),
                "IsDigit" => typeof(char).GetMethod(nameof(char.IsDigit), new[] { typeof(char) }),
                "IsWhiteSpace" => typeof(char).GetMethod(nameof(char.IsWhiteSpace), new[] { typeof(char) }),
                "ToLowerInvariant" => typeof(char).GetMethod(nameof(char.ToLowerInvariant), new[] { typeof(char) }),
                "ToUpperInvariant" => typeof(char).GetMethod(nameof(char.ToUpperInvariant), new[] { typeof(char) }),
                _ => null,
            };
            if (method == null || !EmitArg(callIdx, 1, typeof(char)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = method.ReturnType;
            return true;
        }
        if (typeName == "BitOperations" && member == "PopCount" && argCount == 1)
        {
            // System.Numerics.BitOperations.PopCount(ulong) -> int (population count / set-bit count). The arg
            // is a ulong; emit `call` (static). CliQueryParsing.nl uses it to count packed success bits.
            var method = typeof(System.Numerics.BitOperations).GetMethod(nameof(System.Numerics.BitOperations.PopCount), new[] { typeof(ulong) });
            if (method == null || !EmitArg(callIdx, 1, typeof(ulong)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Math" && member == "Abs" && argCount == 1)
        {
            // System.Math.Abs(int) -> int (absolute value). The arg is an int; emit `call` (static). Negative
            // inputs return the magnitude; int.MinValue throws OverflowException — identical to the C# path,
            // which binds the same overload, so parity holds (the columnar and C# results match, throw included).
            var method = typeof(Math).GetMethod(nameof(Math.Abs), new[] { typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == "Compare")
        {
            // String.Compare overloads -> int (ordinal/culture comparison sign). Two shapes are modelled:
            //   3-arg: Compare(string, string, StringComparison)
            //   6-arg: Compare(string, int, string, int, int, StringComparison)
            // Both take a StringComparison enum constant as the LAST arg (emitted as its underlying int). The
            // return is the comparison sign (<0 / 0 / >0), matching the C# binder's pick of the same overload.
            if (argCount == 3)
            {
                var method = typeof(string).GetMethod(nameof(string.Compare),
                    new[] { typeof(string), typeof(string), typeof(StringComparison) });
                if (method == null
                    || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string))
                    || !EmitArg(callIdx, 3, typeof(StringComparison)))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(int);
                return true;
            }
            if (argCount == 6)
            {
                var method = typeof(string).GetMethod(nameof(string.Compare),
                    new[] { typeof(string), typeof(int), typeof(string), typeof(int), typeof(int), typeof(StringComparison) });
                if (method == null
                    || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(int))
                    || !EmitArg(callIdx, 3, typeof(string)) || !EmitArg(callIdx, 4, typeof(int))
                    || !EmitArg(callIdx, 5, typeof(int)) || !EmitArg(callIdx, 6, typeof(StringComparison)))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(int);
                return true;
            }
            return false;
        }
        if (typeName == "Array" && member == "Fill" && argCount == 4)
        {
            // Array.Fill<T>(T[] array, T value, int startIndex, int count) -> void. The array's element type
            // drives the generic instantiation; the value must match the element type; startIndex/count are int.
            // (The 2-arg Fill<T>(T[], T) is a separate overload — only the 4-arg span-fill is modelled here.)
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (!EmitArg(callIdx, 2, elementType) || !EmitArg(callIdx, 3, typeof(int)) || !EmitArg(callIdx, 4, typeof(int)))
                return false;
            var fill = ResolveArrayFill4();
            if (fill == null)
                return false;
            _il.Emit(OpCodes.Call, fill.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        return false;
    }

    // System.Array.Fill&lt;T&gt;(T[] array, T value, int startIndex, int count) — the 4-arg overload as a generic
    // method DEFINITION (the 2-arg Fill&lt;T&gt;(T[], T) is excluded by the parameter count). The caller binds T via
    // MakeGenericMethod(elementType). Returns null if the method is unexpectedly absent (then the call declines).
    private static MethodInfo? ResolveArrayFill4()
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name == "Fill" && m.IsGenericMethodDefinition && m.GetParameters().Length == 4)
                return m;
        }
        return null;
    }

    // Instance BCL calls (the receiver value is already on the stack): a small whitelist of string methods.
    // string.IndexOf(char, int) -> int ; string.Substring(int, int) -> string.
    private bool TryEmitInstanceCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;
        if (receiverType == typeof(string) && member == "IndexOf")
        {
            // string.IndexOf overloads -> int. 1-arg: IndexOf(char). 2-arg: distinguished by the FIRST arg's
            // type — IndexOf(char, int) vs IndexOf(string, StringComparison) — so emit arg1, read its type, then
            // bind the matching overload + arg2.
            if (argCount == 1)
            {
                var method1 = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(char) });
                if (method1 == null || !EmitArg(callIdx, 1, typeof(char)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method1);
                type = typeof(int);
                return true;
            }
            if (argCount == 2)
            {
                if (!EmitExpression(Child(callIdx, 1), out var arg1Type))
                    return false;
                if (arg1Type == typeof(char))
                {
                    var m = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(char), typeof(int) });
                    if (m == null || !EmitArg(callIdx, 2, typeof(int)))
                        return false;
                    _il.Emit(OpCodes.Callvirt, m);
                    type = typeof(int);
                    return true;
                }
                if (arg1Type == typeof(string))
                {
                    var m = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(string), typeof(StringComparison) });
                    if (m == null || !EmitArg(callIdx, 2, typeof(StringComparison)))
                        return false;
                    _il.Emit(OpCodes.Callvirt, m);
                    type = typeof(int);
                    return true;
                }
                return false;
            }
            return false;
        }
        if (receiverType == typeof(string) && member == "Trim" && argCount == 0)
        {
            // string.Trim() -> string (strip leading/trailing whitespace). The receiver string is on the stack;
            // `callvirt` the parameterless overload. DiagnosticClusters.nl: `builder.ToString().Trim()`.
            var method = typeof(string).GetMethod(nameof(string.Trim), Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(int) && member == "ToString" && argCount == 1)
        {
            // int.ToString(string format) -> string (e.g. .ToString("x") for lowercase hex). Int32.ToString is a
            // VALUE-TYPE instance method, so `this` must be a managed pointer: spill the receiver int (already on
            // the stack) to a temp local and `ldloca` its address, then push the format string and `call`. The
            // C# path binds the same Int32.ToString(string) overload, so the formatted text matches exactly.
            var method = typeof(int).GetMethod(nameof(int.ToString), new[] { typeof(string) });
            if (method == null)
                return false;
            var temp = _il.DeclareLocal(typeof(int));
            _il.Emit(OpCodes.Stloc, temp);
            _il.Emit(OpCodes.Ldloca, temp);
            if (!EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(string) && member == "Substring" && argCount == 2)
        {
            var method = typeof(string).GetMethod(nameof(string.Substring), new[] { typeof(int), typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)) || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(System.Text.StringBuilder))
        {
            // Mutating-builder instance methods (the receiver builder is already on the stack):
            //   .Append(char|string|int) -> StringBuilder (fluent; result usually discarded as a statement)
            //   .Clear()                 -> StringBuilder
            //   .ToString()              -> string
            var sb = typeof(System.Text.StringBuilder);
            if (member == "ToString" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(object.ToString), Type.EmptyTypes)!);
                type = typeof(string);
                return true;
            }
            if (member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(System.Text.StringBuilder.Clear), Type.EmptyTypes)!);
                type = sb;
                return true;
            }
            if (member == "Append" && argCount == 1)
            {
                // Resolve the overload by the ARGUMENT'S type (char/string/int): emit the arg, then bind
                // Append(thatType). (The receiver is already on the stack, so the arg goes on top — correct order.)
                if (!EmitExpression(Child(callIdx, 1), out var appendArgType)
                    || (appendArgType != typeof(char) && appendArgType != typeof(string) && appendArgType != typeof(int)))
                    return false;
                var append = sb.GetMethod(nameof(System.Text.StringBuilder.Append), new[] { appendArgType });
                if (append == null)
                    return false;
                _il.Emit(OpCodes.Callvirt, append);
                type = sb;
                return true;
            }
            return false;
        }
        return false;
    }

    // Emit the argument at child position `argPosition` of the call and require its type to equal `expected`.
    private bool EmitArg(int callIdx, int argPosition, Type expected)
        => EmitExpression(Child(callIdx, argPosition), out var argType) && argType == expected;

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

    // Store the value on the stack into argument slot `index` (`starg`/`starg.s`). N# parameters are ordinary
    // argument slots, so a `param = expr` assignment mutates the slot directly (method-local value semantics).
    private void EmitStoreArgument(int index)
    {
        if (index <= 255)
            _il.Emit(OpCodes.Starg_S, (byte)index);
        else
            _il.Emit(OpCodes.Starg, index);
    }

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);
}
