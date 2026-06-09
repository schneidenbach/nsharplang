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
/// One top-level <c>enum</c> declaration's parsed members, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. <see cref="MemberValues"/> are the resolved underlying
/// ints (auto-incremented and/or explicit), positionally aligned with <see cref="MemberNames"/>. The parser kernel
/// <c>ParseEnumDeclarationInto</c> produces the member spans; the adapter materializes the names and values.
/// </summary>
public sealed class ColumnarEnumInput
{
    public ColumnarEnumInput(string name, string[] memberNames, int[] memberValues)
    {
        Name = name;
        MemberNames = memberNames;
        MemberValues = memberValues;
    }

    public string Name { get; }
    public string[] MemberNames { get; }
    public int[] MemberValues { get; }
}

/// <summary>
/// A user-defined enum being emitted: its <see cref="EnumBuilder"/> (its CLR <see cref="Type"/> — an i4-underlying
/// value type) plus its member-name → constant-int map (for <c>Enum.Member</c> value and pattern resolution). Built
/// in PASS 0 of <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/> and threaded into type resolution + emit.
/// </summary>
internal sealed class ColumnarEnumDef
{
    public ColumnarEnumDef(EnumBuilder builder, Dictionary<string, int> constants)
    {
        Builder = builder;
        Constants = constants;
    }

    public EnumBuilder Builder { get; }
    public Dictionary<string, int> Constants { get; }
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
    // User-defined enums in this program, by name -> (EnumBuilder, member->value). Lets member access `Enum.Member`
    // and enum match patterns resolve their underlying-int constant, and types resolve `Color` to its EnumBuilder.
    private readonly IReadOnlyDictionary<string, ColumnarEnumDef> _enumRegistry;
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
        IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType)> siblings,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry)
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
        _enumRegistry = enumRegistry;
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
        || t is EnumBuilder                       // a user-defined enum — its own i4-underlying value type
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!))
        || IsSupportedValueTuple(t);

    // A positional System.ValueTuple of arity 2-7 whose every element is itself a supported type. (1-tuples and
    // the >7 nested-TRest form are not modelled.) Admits a tuple as a `:=` local / value, NOT as an array element.
    private static bool IsSupportedValueTuple(Type t)
    {
        if (!t.IsGenericType)
            return false;
        var def = t.GetGenericTypeDefinition();
        if (def != typeof(ValueTuple<,>) && def != typeof(ValueTuple<,,>) && def != typeof(ValueTuple<,,,>)
            && def != typeof(ValueTuple<,,,,>) && def != typeof(ValueTuple<,,,,,>) && def != typeof(ValueTuple<,,,,,,>))
            return false;
        foreach (var arg in t.GetGenericArguments())
        {
            // Exclude an EnumBuilder element: a ValueTuple<…> instantiated over a TypeBuilder cannot resolve its
            // ctor/ItemN fields via plain reflection (GetConstructor/GetField throw NotSupportedException at emit),
            // so enum-in-tuple must DECLINE here (→ C# fallback) — consistent with the enum-array decline
            // (IsSupportedElementType excludes EnumBuilder). Enums are modelled as scalars only in this slice.
            if (arg is EnumBuilder || !IsSupportedType(arg))
                return false;
        }

        return true;
    }

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
    private static bool TryResolveType(string canonical, IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry, out Type type)
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
        // Tuple `(e0,e1,...)` -> System.ValueTuple<...> (positional, arity 2-7). The canonical (from the kernel's
        // ColumnarTypeCanon / the C# ColumnarFunctionSymbol.CanonicalType) is parens + comma-joined element canons;
        // split at the TOP level (respecting nested ()/<>/[]), resolve each element recursively, then
        // MakeGenericType the matching open ValueTuple. (Only Tuple type nodes produce a `(...)` canonical.)
        if (canonical.Length >= 2 && canonical[0] == '(' && canonical[^1] == ')')
        {
            var elements = SplitTopLevelCommas(canonical.Substring(1, canonical.Length - 2));
            Type? openTuple = elements.Count switch
            {
                2 => typeof(ValueTuple<,>),
                3 => typeof(ValueTuple<,,>),
                4 => typeof(ValueTuple<,,,>),
                5 => typeof(ValueTuple<,,,,>),
                6 => typeof(ValueTuple<,,,,,>),
                7 => typeof(ValueTuple<,,,,,,>),
                _ => null,
            };
            if (openTuple != null)
            {
                var elementTypes = new Type[elements.Count];
                var resolved = true;
                for (var i = 0; i < elements.Count; i++)
                {
                    if (!TryResolveType(elements[i], enumRegistry, out elementTypes[i]))
                    {
                        resolved = false;
                        break;
                    }
                }

                if (resolved)
                {
                    type = openTuple.MakeGenericType(elementTypes);
                    return true;
                }
            }

            type = null!;
            return false;
        }
        // A bare name matching a user-defined enum resolves to its EnumBuilder (so `Color` is a valid param/return/
        // local type). Checked before the builtins so a user enum never collides with a builtin name (it cannot —
        // builtin names are reserved keywords the parser would not accept as an enum name).
        if (enumRegistry != null && enumRegistry.TryGetValue(canonical, out var enumDef))
        {
            type = enumDef.Builder;
            return true;
        }
        return TryResolveBuiltin(canonical, out type);
    }

    // Split `s` on commas at bracket depth 0 (parens, angle brackets, and square brackets all nest), so a tuple
    // canonical `(int,int),string` splits into its top-level element canons without breaking nested tuples/generics.
    private static List<string> SplitTopLevelCommas(string s)
    {
        var parts = new List<string>();
        var depth = 0;
        var start = 0;
        for (var i = 0; i < s.Length; i++)
        {
            switch (s[i])
            {
                case '(': case '<': case '[': depth++; break;
                case ')': case '>': case ']': depth--; break;
                case ',' when depth == 0:
                    parts.Add(s.Substring(start, i - start));
                    start = i + 1;
                    break;
            }
        }

        parts.Add(s.Substring(start));
        return parts;
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
        return TryEmitColumnarAssembly("ColumnarSpike", "ColumnarSpike", new[] { input }, Array.Empty<ColumnarEnumInput>(), source, out assembly);
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
        string assemblyName, string typeName, IReadOnlyList<ColumnarFunctionInput> funcs,
        IReadOnlyList<ColumnarEnumInput> enums, string source, out byte[] assembly)
    {
        assembly = Array.Empty<byte>();
        if (funcs.Count == 0)
            return false;

        var builder = new PersistedAssemblyBuilder(new AssemblyName(assemblyName), typeof(object).Assembly);
        var module = builder.DefineDynamicModule(assemblyName);

        // PASS 0: define every user enum as a module-level i4-underlying enum type, BEFORE the Program type and the
        // function signatures (pass 1) so a function can use an enum as a param/return/local type and resolve its
        // members. The EnumBuilder is its own CLR Type; it is referenced (un-finalized) throughout passes 1-2 and
        // finalized (CreateType) just before the Program type — the same ordering proven by the de-risking spike.
        var enumRegistry = new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal);
        var enumBuilders = new EnumBuilder[enums.Count];
        for (var e = 0; e < enums.Count; e++)
        {
            var en = enums[e];
            var eb = module.DefineEnum(en.Name, TypeAttributes.Public, typeof(int));
            var constants = new Dictionary<string, int>(StringComparer.Ordinal);
            for (var m = 0; m < en.MemberNames.Length; m++)
            {
                eb.DefineLiteral(en.MemberNames[m], en.MemberValues[m]);
                // A duplicate member name within one enum is malformed — decline the whole program.
                if (!constants.TryAdd(en.MemberNames[m], en.MemberValues[m]))
                    return false;
            }
            enumBuilders[e] = eb;
            // A duplicate enum name is an ambiguous type — decline rather than silently pick one.
            if (!enumRegistry.TryAdd(en.Name, new ColumnarEnumDef(eb, constants)))
                return false;
        }

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
            else if (!TryResolveType(fn.ReturnCanonical, enumRegistry, out returnType) || !IsSupportedType(returnType))
                return false;
            var paramTypes = new Type[fn.ParamNames.Length];
            var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
            var paramTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
            for (var i = 0; i < fn.ParamNames.Length; i++)
            {
                if (!TryResolveType(fn.ParamCanonicals[i], enumRegistry, out var pt) || !IsSupportedType(pt))
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
                source, ordinalsByFunc[f], paramTypesByFunc[f], returnTypeByFunc[f], il, siblings, enumRegistry);
            if (!emitter.EmitBody(fn.BodyRoot, returnTypeByFunc[f] == typeof(void)))
                return false;
        }

        // Finalize the enum types before the Program type (the spike's ordering). Each member literal is already
        // defined, so CreateType bakes the enum's fields/metadata; the methods that reference the EnumBuilder
        // resolve to the finalized type at Save.
        foreach (var eb in enumBuilders)
            eb.CreateType();

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

            case 28: // For [init, cond, incr, body] — C-style: emit `init; check: cond; brfalse end; body;
            {        // cont: incr; br check; end:`. `break` -> end, `continue` -> cont (the increment, THEN the
                     // re-test), matching C# for-loop semantics. The loop's own locals (the `init` declaration's
                     // variable + any body `:=` locals) are scoped to the loop and removed at its end.
                var init = Child(idx, 0);
                var cond = Child(idx, 1);
                var incr = Child(idx, 2);
                var body = Child(idx, 3);

                // A for-body that always transfers on every path (never falls through) would make the increment +
                // back-edge unreachable (a `continue` aside) — a degenerate shape; decline it to the C# path. A
                // normal counting loop falls through, and a `continue` body still falls through on its other path.
                if (AlwaysReturns(body))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(init)) // runs once before the loop; declares the loop variable.
                    return false;

                var checkLabel = _il.DefineLabel();
                var contLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                if (!EmitCondition(cond))
                    return false;
                _il.Emit(OpCodes.Brfalse, endLabel);

                _loopLabels.Push((endLabel, contLabel));
                var forBodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!forBodyEmitted)
                    return false;

                _il.MarkLabel(contLabel);     // `continue` lands here -> run the increment, then re-test.
                if (!EmitStatement(incr))
                    return false;
                _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);

                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!outerLocals.Contains(name))
                        _locals.Remove(name);
                }
                return true;
            }

            case 29: // Foreach [collection, body] — `foreach <var> in <array> { body }` lowered to an index loop
            {        // over the array, mirroring the C# ILCompiler's EmitForeachForArray: arr := collection; i := 0;
                     // check: if i >= arr.Length goto end; <var> := arr[i]; body; cont: i = i+1; br check; end:.
                     // ARRAY collections only (others decline -> C# fallback). The var name is in the value span.
                var collectionNode = Child(idx, 0);
                var body = Child(idx, 1);
                var varName = Text(idx);

                // A body that always transfers on every path makes the increment unreachable -> decline (as for/while).
                if (AlwaysReturns(body))
                    return false;
                // The loop variable must not shadow an existing local/param (shadowing is not modelled).
                if (_locals.ContainsKey(varName) || _paramOrdinals.ContainsKey(varName))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);

                // Evaluate the collection; require a single-dim array of a supported element type.
                if (!EmitExpression(collectionNode, out var collectionType) || !collectionType.IsSZArray)
                    return false;
                var elementType = collectionType.GetElementType()!;
                if (!IsSupportedElementType(elementType))
                    return false;
                var arrayLocal = _il.DeclareLocal(collectionType);
                _il.Emit(OpCodes.Stloc, arrayLocal);
                var indexLocal = _il.DeclareLocal(typeof(int));
                _il.Emit(OpCodes.Ldc_I4_0);
                _il.Emit(OpCodes.Stloc, indexLocal);

                var checkLabel = _il.DefineLabel();
                var contLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                _il.Emit(OpCodes.Ldloc, indexLocal);
                _il.Emit(OpCodes.Ldloc, arrayLocal);
                _il.Emit(OpCodes.Ldlen);
                _il.Emit(OpCodes.Conv_I4);
                _il.Emit(OpCodes.Bge, endLabel); // index >= length -> exit

                // <var> := arr[index]  (declare the loop variable of the element type, store the current element).
                _il.Emit(OpCodes.Ldloc, arrayLocal);
                _il.Emit(OpCodes.Ldloc, indexLocal);
                if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                else return false;
                var loopVar = _il.DeclareLocal(elementType);
                _il.Emit(OpCodes.Stloc, loopVar);
                _locals[varName] = loopVar;

                _loopLabels.Push((endLabel, contLabel));
                var foreachBodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!foreachBodyEmitted)
                    return false;

                _il.MarkLabel(contLabel);   // `continue` lands here -> increment the index, then re-test.
                _il.Emit(OpCodes.Ldloc, indexLocal);
                _il.Emit(OpCodes.Ldc_I4_1);
                _il.Emit(OpCodes.Add);
                _il.Emit(OpCodes.Stloc, indexLocal);
                _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);

                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!outerLocals.Contains(name))
                        _locals.Remove(name);
                }
                return true;
            }

            case 30: // TupleDeconstruction [name0, ..., nameN-1, value] — `n0, n1, ... := <tuple>`. Emit the value
            {        // (a ValueTuple), store to a temp, then for each non-`_` name declare a local of the element
                     // type and store the matching ItemN. Mirrors the C# EmitTupleDeconstruction (plain path).
                var childCount = _childCount[idx];
                if (childCount < 3) // at least 2 names + the value.
                    return false;
                var nameCount = childCount - 1;
                var valueNode = Child(idx, nameCount);

                // The Go-style `name, err := ...` error path is handled specially by the C# ILCompiler
                // (EmitErrorTupleDeconstruction); decline it so the columnar backend never diverges from that path.
                if (nameCount == 2 && Text(Child(idx, 1)) == "err")
                    return false;

                if (!EmitExpression(valueNode, out var tupleType) || !IsSupportedValueTuple(tupleType))
                    return false;
                var tupleArgs = tupleType.GetGenericArguments();
                if (tupleArgs.Length != nameCount) // the tuple arity must match the number of targets.
                    return false;

                var tupleLocal = _il.DeclareLocal(tupleType);
                _il.Emit(OpCodes.Stloc, tupleLocal);

                for (var i = 0; i < nameCount; i++)
                {
                    var name = Text(Child(idx, i));
                    if (name == "_") // discard — the element is not bound.
                        continue;
                    if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name))
                        return false; // redeclaration / shadow is not modelled (keep the C# analyzer authoritative).
                    var field = tupleType.GetField("Item" + (i + 1), BindingFlags.Public | BindingFlags.Instance);
                    if (field == null)
                        return false;
                    var nameLocal = _il.DeclareLocal(field.FieldType);
                    _il.Emit(OpCodes.Ldloca, tupleLocal); // value-type field load: address of the tuple, then ldfld.
                    _il.Emit(OpCodes.Ldfld, field);
                    _il.Emit(OpCodes.Stloc, nameLocal);
                    _locals[name] = nameLocal;
                }

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
                    // A USER-DEFINED enum constant: the receiver names a registered enum TYPE (not shadowed by a
                    // local/param/sibling) and the member is one of its constants -> load the underlying int. The
                    // reported type is the enum's EnumBuilder (the same instance used for its param/return types, so
                    // `return Color.Green` reference-matches the declared `Color` return).
                    if (_enumRegistry.TryGetValue(receiverIdent, out var userEnum)
                        && !_locals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (!userEnum.Constants.TryGetValue(Text(idx), out var memberValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, memberValue);
                        type = userEnum.Builder;
                        return true;
                    }
                }
                // Instance member access: `.Length` (array/string/StringBuilder -> int) or `.ItemN` (a tuple
                // element). Anything else declines BEFORE the receiver is emitted (no wasted side effects).
                var member = Text(idx);
                // `.ItemN` is a tuple element accessor only if a DIGIT follows "Item" (so `.Items`/`.ItemFoo`
                // decline early without emitting the receiver); the actual element is still gated by GetField below.
                var isTupleItem = member.Length > 4 && member.StartsWith("Item", StringComparison.Ordinal) && char.IsDigit(member[4]);
                if (member != "Length" && !isTupleItem)
                    return false;
                if (!EmitExpression(Child(idx, 0), out var receiverType))
                    return false;
                if (member == "Length")
                {
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
                // `t.ItemN` on a ValueTuple -> ldfld the element (ItemN is a public instance FIELD of ValueTuple).
                // The receiver value (a value type) is already on the stack; ldfld reads the field from it.
                if (IsSupportedValueTuple(receiverType))
                {
                    var itemField = receiverType.GetField(member, BindingFlags.Public | BindingFlags.Instance);
                    if (itemField == null)
                        return false;
                    _il.Emit(OpCodes.Ldfld, itemField);
                    type = itemField.FieldType;
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

            case 17: // Tuple [e0, e1, ...] — construct a positional System.ValueTuple<...>: emit each element value
            {        // (left-to-right, the ctor's argument order), then `newobj` the matching ValueTuple ctor.
                     // Arity 2-7 (a 1-tuple is not a tuple; >7 needs the nested TRest form — both decline).
                var arity = _childCount[idx];
                Type? openTuple = arity switch
                {
                    2 => typeof(ValueTuple<,>),
                    3 => typeof(ValueTuple<,,>),
                    4 => typeof(ValueTuple<,,,>),
                    5 => typeof(ValueTuple<,,,,>),
                    6 => typeof(ValueTuple<,,,,,>),
                    7 => typeof(ValueTuple<,,,,,,>),
                    _ => null,
                };
                if (openTuple == null)
                    return false;
                var elementTypes = new Type[arity];
                for (var i = 0; i < arity; i++)
                {
                    if (!EmitExpression(Child(idx, i), out var elemType) || !IsSupportedType(elemType))
                        return false;
                    elementTypes[i] = elemType;
                }
                var tupleType = openTuple.MakeGenericType(elementTypes);
                var tupleCtor = tupleType.GetConstructor(elementTypes);
                if (tupleCtor == null)
                    return false;
                _il.Emit(OpCodes.Newobj, tupleCtor);
                type = tupleType;
                return true;
            }

            case 18: // Match [value, pat0, res0, pat1, res1, ...] — `match value { p => r, ... }`, lowered to a
            {        // linear chain mirroring the C# EmitMatchExpression: eval value -> temp; per case test the
                     // pattern, on match eval the result + br end; no match -> throw. An EXPRESSION: leaves one
                     // result on the stack. Patterns: a LITERAL (equality test) or an identifier (`_` discard or a
                     // binding that always matches and binds the matched value); a pattern may carry a `when` guard
                     // (kind 19 [pattern, guard]) tested after the pattern; richer patterns decline.
                var childCount = _childCount[idx];
                if (childCount < 3 || (childCount % 2) == 0) // value + >=1 (pattern, result) pair.
                    return false;
                var caseCount = (childCount - 1) / 2;

                if (!EmitExpression(Child(idx, 0), out var matchValueType) || !IsSupportedMatchValueType(matchValueType))
                    return false;
                var matchLocal = _il.DeclareLocal(matchValueType);
                _il.Emit(OpCodes.Stloc, matchLocal);

                // ENUM EXHAUSTIVENESS: C# requires an enum match to cover EVERY member or carry a catch-all (the
                // analyzer's NL501 NonExhaustiveMatch). The columnar emit would otherwise compile a PARTIAL enum
                // match (with a runtime throw for the missing members), ACCEPTING a program C# REJECTS. Decline such
                // a match so the columnar path never accepts what C# refuses (→ C# fallback, which reports NL501).
                // This is a DECLINE (route to the analyzer-backed C# path), not a diagnostic — consistent with how
                // the emitter declines everything outside its faithfully-modelled subset. Coverage counts only
                // TOP-LEVEL UNGUARDED arms: an unguarded `_`/binding is a catch-all; an unguarded `Enum.Member`
                // (kind 8) covers that member. Guarded and combinator/relational arms do not count (conservative — a
                // richer-but-exhaustive form simply declines to C#, still correct).
                ColumnarEnumDef? matchEnumDef = null;
                foreach (var def in _enumRegistry.Values)
                {
                    if (def.Builder == matchValueType) { matchEnumDef = def; break; }
                }
                if (matchEnumDef != null)
                {
                    var covered = new HashSet<string>(StringComparer.Ordinal);
                    var hasCatchAll = false;
                    for (var c = 0; c < caseCount; c++)
                    {
                        var rawP = Child(idx, 1 + (2 * c));
                        if (_kinds[rawP] == 19) // a `when`-guarded arm does not contribute to coverage.
                            continue;
                        if (_kinds[rawP] == 6) // `_` discard or an unguarded binding -> a catch-all.
                            hasCatchAll = true;
                        else if (_kinds[rawP] == 8) // `Enum.Member` -> covers that member (if it is THIS enum's).
                        {
                            var recv = Child(rawP, 0);
                            if (_kinds[recv] == 6 && _enumRegistry.TryGetValue(Text(recv), out var rd)
                                && rd.Builder == matchValueType && matchEnumDef.Constants.ContainsKey(Text(rawP)))
                                covered.Add(Text(rawP));
                        }
                    }
                    if (!hasCatchAll && !covered.SetEquals(matchEnumDef.Constants.Keys))
                        return false;
                }

                var matchEnd = _il.DefineLabel();
                Type? matchResultType = null;
                for (var c = 0; c < caseCount; c++)
                {
                    var rawPattern = Child(idx, 1 + (2 * c));
                    var resultNode = Child(idx, 2 + (2 * c));
                    var nextCase = _il.DefineLabel();
                    var armLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);

                    // A `when` guard wraps the pattern in a GuardedPattern (kind 19 [pattern, guard]). Unwrap it:
                    // the inner pattern is tested exactly as a bare pattern, then the guard (a bool expression with
                    // the pattern's binding in scope) gates the arm. A guarded catch-all is NOT exhaustive, so the
                    // trailing no-match throw remains correct.
                    int patternNode;
                    int guardNode;
                    if (_kinds[rawPattern] == 19)
                    {
                        if (_childCount[rawPattern] != 2)
                            return false;
                        patternNode = Child(rawPattern, 0);
                        guardNode = Child(rawPattern, 1);
                    }
                    else
                    {
                        patternNode = rawPattern;
                        guardNode = -1;
                    }

                    if (_kinds[patternNode] == 6) // top-level identifier: `_` discard or a binding -> always matches.
                    {
                        var patName = Text(patternNode);
                        if (patName != "_")
                        {
                            if (_locals.ContainsKey(patName) || _paramOrdinals.ContainsKey(patName))
                                return false; // a binding that shadows is not modelled.
                            var bindLocal = _il.DeclareLocal(matchValueType);
                            _il.Emit(OpCodes.Ldloc, matchLocal);
                            _il.Emit(OpCodes.Stloc, bindLocal);
                            _locals[patName] = bindLocal;
                        }
                        // Always matches -> fall through to the guard / result.
                    }
                    else // literal / relational / and-or-not combinator -> recursive pattern test.
                    {
                        // On MATCH fall through to the guard/result (armBody); on NO-MATCH branch to nextCase. The
                        // recursive helper models literals, relational patterns, and `and`/`or`/`not` combinators,
                        // declining (whole match -> C# fallback) anything it cannot emit with exact C# parity.
                        var armBody = _il.DefineLabel();
                        if (!EmitPatternMatch(patternNode, matchValueType, matchLocal, armBody, nextCase))
                            return false;
                        _il.MarkLabel(armBody);
                    }

                    // `when` guard: the pattern matched; now require the guard (a bool) to hold. The pattern's
                    // binding (if any) is already in _locals, so the guard may reference it. False -> next case.
                    if (guardNode >= 0)
                    {
                        if (!EmitExpression(guardNode, out var guardType) || guardType != typeof(bool))
                            return false;
                        _il.Emit(OpCodes.Brfalse, nextCase);
                    }

                    if (!EmitExpression(resultNode, out var armResultType))
                        return false;
                    if (matchResultType == null)
                        matchResultType = armResultType;
                    else if (armResultType != matchResultType) // every arm's result must share the match's type.
                        return false;
                    _il.Emit(OpCodes.Br, matchEnd);

                    _il.MarkLabel(nextCase);
                    foreach (var name in new List<string>(_locals.Keys)) // drop this arm's binding (if any).
                    {
                        if (!armLocals.Contains(name))
                            _locals.Remove(name);
                    }
                }

                // No case matched -> throw (mirrors the C# path). Unreachable if a catch-all arm is present.
                _il.Emit(OpCodes.Ldstr, "No matching case in match expression");
                _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                _il.Emit(OpCodes.Throw);
                _il.MarkLabel(matchEnd);
                type = matchResultType!;
                return true;
            }

            default:
                return false;
        }
    }

    // Recursive match-pattern test mirroring the C# EmitPatternTest structure (success/fail labels), but reading the
    // matched value from `matchLocal` instead of a stack dup. On MATCH it branches to successLabel; on NO-MATCH to
    // failLabel. Models literal patterns (kinds 0-4), relational patterns (32), and `and`/`or`/`not` combinators
    // (33/34/35) over those. It does NOT model bindings: an identifier (kind 6) is only handled at the TOP LEVEL of
    // an arm, so an identifier inside a combinator declines (returns false) and the whole match falls back to the C#
    // pipeline. A `false` return discards the entire emitted assembly, so a partially-emitted test is harmless.
    private bool EmitPatternMatch(int patternNode, Type matchValueType, LocalBuilder matchLocal, Label successLabel, Label failLabel)
    {
        switch (_kinds[patternNode])
        {
            case 34: // OrPattern [left, right]: left matches -> success; else fall through and try right.
            {
                if (_childCount[patternNode] != 2)
                    return false;
                var orNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, successLabel, orNext))
                    return false;
                _il.MarkLabel(orNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 33: // AndPattern [left, right]: left must match (else fail), then right decides.
            {
                if (_childCount[patternNode] != 2)
                    return false;
                var andNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, andNext, failLabel))
                    return false;
                _il.MarkLabel(andNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 35: // NotPattern [inner]: inner matches -> fail, inner fails -> success (just swap the labels).
            {
                if (_childCount[patternNode] != 1)
                    return false;
                return EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, failLabel, successLabel);
            }
            case 32: // RelationalPattern `<op> <constant>` -> ordered comparison (the C# EmitPatternTest mirror).
            {
                if (_childCount[patternNode] != 1 || !IsOrderedMatchType(matchValueType))
                    return false;
                var operandNode = Child(patternNode, 0);
                if (!IsLiteralPatternKind(_kinds[operandNode]))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                if (!EmitExpression(operandNode, out var relType) || relType != matchValueType)
                    return false;
                // Plain ordered Clt/Cgt for ALL types (matches C# exactly, incl. NaN/large ulong). `<`/`>` take the
                // arm when the compare is TRUE; `<=`/`>=` are the negations — take when FALSE. Branch to successLabel
                // when taken, else fall to the `Br failLabel`.
                switch (Text(patternNode))
                {
                    case "<": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Brtrue, successLabel); break;
                    case ">": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Brtrue, successLabel); break;
                    case "<=": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Brfalse, successLabel); break;
                    case ">=": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Brfalse, successLabel); break;
                    default: return false;
                }
                _il.Emit(OpCodes.Br, failLabel);
                return true;
            }
            case 8: // MemberAccess pattern `Enum.Member` -> an enum-constant equality test on the underlying int.
            {
                // The receiver must be a bare identifier naming a REGISTERED enum (not shadowed by a local/param/
                // sibling), the member one of its constants, and the match value must be THAT enum's type (the same
                // EnumBuilder instance). Otherwise decline (a non-enum member access is not a constant pattern).
                var recv = Child(patternNode, 0);
                if (_kinds[recv] != 6)
                    return false;
                var recvName = Text(recv);
                if (!_enumRegistry.TryGetValue(recvName, out var enumDef)
                    || _locals.ContainsKey(recvName) || _paramOrdinals.ContainsKey(recvName) || _siblings.ContainsKey(recvName))
                    return false;
                if (matchValueType != enumDef.Builder)
                    return false;
                if (!enumDef.Constants.TryGetValue(Text(patternNode), out var memberValue))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                _il.Emit(OpCodes.Ldc_I4, memberValue);
                _il.Emit(OpCodes.Ceq);                 // underlying-int equality (matches C#'s Beq-on-underlying-int).
                _il.Emit(OpCodes.Brtrue, successLabel);
                _il.Emit(OpCodes.Br, failLabel);
                return true;
            }
            default: // literal pattern (kinds 0-4) -> equality test; any other primary (null/paren/call/index/…) declines.
            {
                if (!IsLiteralPatternKind(_kinds[patternNode]))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                if (!EmitExpression(patternNode, out var patType) || patType != matchValueType)
                    return false;
                if (matchValueType == typeof(string))
                    _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                else
                    _il.Emit(OpCodes.Ceq);
                _il.Emit(OpCodes.Brtrue, successLabel);
                _il.Emit(OpCodes.Br, failLabel);
                return true;
            }
        }
    }

    // Node kinds that are LITERAL match patterns (constant-equality): int(0)/float(1)/char(2)/string(3)/bool(4).
    // A non-literal primary in pattern position (null/parenthesized/member/call/index/…) is not a constant pattern,
    // so the match declines to the C# path rather than emitting a misleading equality test. Identifier patterns
    // (kind 6 — `_` discard / binding) are handled separately, before this is consulted.
    private static bool IsLiteralPatternKind(int kind) => kind >= 0 && kind <= 4;

    // Ordered scalar types a RELATIONAL match pattern (`< c`, `>= c`, …) may test — numeric + char. bool and string
    // have no `<`/`>` ordering in the modelled set, so a relational pattern over them declines to the C# path.
    private static bool IsOrderedMatchType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
        || t == typeof(double) || t == typeof(float);

    // Types a `match` value may be tested against in the modelled pattern set: the scalars (Ceq equality), string
    // (op_Equality), and a user-defined enum (its underlying-int Ceq, via the MemberAccess pattern case). Unions/
    // records/etc. are not modelled, so a match over them declines to the C# path.
    private static bool IsSupportedMatchValueType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
        || t == typeof(bool) || t == typeof(double) || t == typeof(float) || t == typeof(string)
        || t is EnumBuilder;

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
