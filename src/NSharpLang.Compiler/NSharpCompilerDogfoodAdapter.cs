using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class NSharpCompilerDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static ParserTokenCompactionScratch? t_parserTokenCompactionScratch;
    [ThreadStatic]
    private static FirstDistinctTypeKeyScratch? t_firstDistinctTypeKeyScratch;
    [ThreadStatic]
    private static FirstDistinctStringScratch? t_firstDistinctStringScratch;
    [ThreadStatic]
    private static DistinctOrderedStringScratch? t_distinctOrderedStringScratch;
    [ThreadStatic]
    private static DeclaredTypeSuffixLookupScratch? t_declaredTypeSuffixLookupScratch;
    [ThreadStatic]
    private static DeclaredTypeNameCandidateScratch? t_declaredTypeNameCandidateScratch;
    [ThreadStatic]
    private static TypeCreationOrderScratch? t_typeCreationOrderScratch;
    [ThreadStatic]
    private static AnonymousUnionShimScratch? t_anonymousUnionShimScratch;
    [ThreadStatic]
    private static MissingEnumMemberScratch? t_missingEnumMemberScratch;
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;
    [ThreadStatic]
    private static FormatterImportOrderingScratch? t_formatterImportOrderingScratch;
    [ThreadStatic]
    private static ProjectSourceFilterScratch? t_projectSourceFilterScratch;
    [ThreadStatic]
    private static OverloadCandidateScratch? t_overloadCandidateScratch;

    internal static bool TryGetColumnarProgramInput(string source, out Columnar.ColumnarProgramInput program)
    {
        program = null!;
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;
        if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
            return false;

        if (!TryGetColumnarFunctionInputs(bindings, source, tokens, out var inputs) || inputs.Count == 0)
            return false;
        if (!TryGetColumnarEnumInputs(bindings, source, tokens, out var enums))
            return false;
        if (!TryGetColumnarStructInputs(bindings, source, tokens, out var structs))
            return false;
        if (!TryGetColumnarUnionInputs(bindings, source, tokens, out var unions))
            return false;
        if (!TryGetColumnarInterfaceInputs(bindings, source, tokens, out var interfaceInputs))
            return false;

        program = new Columnar.ColumnarProgramInput(source, inputs, enums, structs, unions, interfaceInputs);
        return true;
    }

    private sealed class ColumnarTokenizedSource
    {
        internal ColumnarTokenizedSource(
            int[] rawKinds,
            int[] rawStarts,
            int[] rawValueLengths,
            int[] rawLines,
            int[] rawColumns,
            int rawCount,
            int[] kinds, int[] starts, int[] valueLengths, int count,
            int[] declarationKinds, int declarationCount)
        {
            RawKinds = rawKinds;
            RawStarts = rawStarts;
            RawValueLengths = rawValueLengths;
            RawLines = rawLines;
            RawColumns = rawColumns;
            RawCount = rawCount;
            Kinds = kinds;
            Starts = starts;
            ValueLengths = valueLengths;
            Count = count;
            DeclarationKinds = declarationKinds;
            DeclarationCount = declarationCount;
        }

        internal int[] RawKinds { get; }
        internal int[] RawStarts { get; }
        internal int[] RawValueLengths { get; }
        internal int[] RawLines { get; }
        internal int[] RawColumns { get; }
        internal int RawCount { get; }
        internal int[] Kinds { get; }
        internal int[] Starts { get; }
        internal int[] ValueLengths { get; }
        internal int Count { get; }
        internal int[] DeclarationKinds { get; }
        internal int DeclarationCount { get; }
    }

    private static bool TryTokenizeColumnarSource(Bindings bindings, string source, out ColumnarTokenizedSource tokens)
    {
        tokens = null!;
        try
        {
            var capacity = 3 * (source.Length + 1) + 8;
            var rawKinds = new int[capacity];
            var rawStarts = new int[capacity];
            var rawValueLengths = new int[capacity];
            var rawLines = new int[capacity];
            var rawColumns = new int[capacity];
            var rawCount = bindings.TokenizeMetadataWithIndentation(
                source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);
            if (rawCount < 0 || rawCount > capacity)
                return false;

            var declarationKinds = new int[rawCount + 1];
            var declarationCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declarationKinds);
            if (declarationCount < 0)
                return false;

            var kinds = new int[rawCount];
            var starts = new int[rawCount];
            var valueLengths = new int[rawCount];
            var keptIndices = new int[rawCount];
            var count = bindings.ParserTokenCompactionCounted(rawKinds, rawCount, keptIndices);
            if (count < 0 || count > rawCount)
                return false;

            for (var i = 0; i < count; i++)
            {
                var sourceIndex = keptIndices[i];
                if (sourceIndex < 0 || sourceIndex >= rawCount)
                    return false;

                kinds[i] = rawKinds[sourceIndex];
                starts[i] = rawStarts[sourceIndex];
                valueLengths[i] = rawValueLengths[sourceIndex];
            }

            tokens = new ColumnarTokenizedSource(
                rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns, rawCount,
                kinds, starts, valueLengths, count,
                declarationKinds, declarationCount);
            return true;
        }
        catch
        {
            return false;
        }
    }

    // Consume the shared token bundle and parse every top-level `func` into a ColumnarFunctionInput (signature +
    // body node tables). Returns false on any parse failure or unsupported top-level declaration, so the
    // columnar backend declines and the C# path stays authoritative.
    private static bool TryGetColumnarFunctionInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        out System.Collections.Generic.List<Columnar.ColumnarFunctionInput> inputs)
    {
        inputs = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>();
        try
        {
            var rawKinds = tokens.RawKinds;
            var rawStarts = tokens.RawStarts;
            var rawValueLengths = tokens.RawValueLengths;
            var rawCount = tokens.RawCount;
            if (bindings.TopLevelContextualTestDeclarationExists(source, rawKinds, rawStarts, rawValueLengths, rawCount) != 0)
                return false;

            var declKinds = tokens.DeclarationKinds;
            var declCount = tokens.DeclarationCount;
            if (declCount <= 0)
                return false;
            for (var d = 0; d < declCount; d++)
            {
                // 7 = func, 14 = enum, 9 = struct, 13 = record, 12 = union, 8 = class; any other top-level declaration
                // kind is unsupported and declines the whole program. Enum/struct/record/class/union decls are
                // collected separately (TryGetColumnarEnumInputs / TryGetColumnarStructInputs /
                // TryGetColumnarUnionInputs); the func scan below only picks `func` tokens, so
                // type decls are skipped here rather than mis-parsed as functions.
                if (declKinds[d] != 7 && declKinds[d] != 14 && declKinds[d] != 9 && declKinds[d] != 13 && declKinds[d] != 12 && declKinds[d] != 8 && declKinds[d] != 10)
                    return false;
            }

            // ASYNC modifiers (async-arc rung A; rung 0 was a blanket decline after the probe-found
            // divergence where the modifier was silently DROPPED and columnar emitted an un-wrapped
            // method surface). The kernel scans per-declaration modifier flags ((int)Modifiers;
            // Async = 1 << 11). The i-th kind-7 declaration is the i-th top-level function index
            // (both walk the token stream in order), so each function input carries its own flag.
            var funcAsyncFlags = new System.Collections.Generic.List<bool>();
            {
                var asyncModKinds = new int[rawCount + 1];
                var asyncModFlags = new int[rawCount + 1];
                var asyncModCount = bindings.TopLevelDeclarationModifiers(rawKinds, rawCount, asyncModKinds, asyncModFlags);
                if (asyncModCount != declCount)
                    return false;
                for (var d = 0; d < declCount; d++)
                {
                    if (declKinds[d] == 7)
                        funcAsyncFlags.Add((asyncModFlags[d] & (1 << 11)) != 0);
                }
            }

            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = new int[n + 1];
            var funcIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 7, 0, funcIndices);
            if (funcIndexCount < 0)
                return false;
            if (funcIndexCount == 0)
                return false;
            if (funcIndexCount != funcAsyncFlags.Count)
                return false; // the modifier scan and the func scan must agree on the function count.
            if (bindings.TopLevelFunctionPreamblesAreValid(ck, n, funcIndices, funcIndexCount) == 0)
                return false;
            for (var fi = 0; fi < funcIndexCount; fi++)
            {
                if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, funcIndices[fi], source, out var input, isAsync: funcAsyncFlags[fi]))
                    return false;
                inputs.Add(input);
            }
            return true;
        }
        catch
        {
            inputs = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>();
            return false;
        }
    }

    // Collect every top-level `enum` declaration into a ColumnarEnumInput (name + member names + resolved underlying
    // int values). Consumes the shared token bundle, finds each enum keyword, and parses its body via the checked
    // ParseEnumDeclarationTextInfo kernel. Returns true (possibly an empty list) for a program with no enums, or
    // false to decline the whole program to the C# path on any unsupported enum shape.
    private static bool TryGetColumnarEnumInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        out System.Collections.Generic.List<Columnar.ColumnarEnumInput> enums)
    {
        enums = new System.Collections.Generic.List<Columnar.ColumnarEnumInput>();
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var enumIndices = new int[n + 1];
            var enumIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 14, 0, enumIndices);
            if (enumIndexCount < 0)
                return false;
            for (var enumSlot = 0; enumSlot < enumIndexCount; enumSlot++)
            {
                var enumIndex = enumIndices[enumSlot];
                var cap = n + 1;
                var outNameStarts = new int[cap];
                var outNameLengths = new int[cap];
                var outNameTexts = new string[cap];
                var outValueStarts = new int[cap];
                var outValueLengths = new int[cap];
                var outHasValue = new int[cap];
                var outMemberValues = new int[cap];
                var outEnumNameTexts = new string[1];
                var outResult = new int[2];
                var memberCount = bindings.ParseEnumDeclarationTextInfo(
                    source, ck, cs, cv, n, enumIndex, outNameStarts, outNameLengths, outNameTexts, outValueStarts, outValueLengths,
                    outHasValue, outMemberValues, outEnumNameTexts, outResult);
                if (memberCount < 0 || outResult[1] <= 0)
                    return false;

                var enumName = outEnumNameTexts[0];
                if (string.IsNullOrEmpty(enumName))
                    return false;
                var memberNames = new string[memberCount];
                var memberValues = new int[memberCount];
                for (var m = 0; m < memberCount; m++)
                {
                    var memberName = outNameTexts[m];
                    if (string.IsNullOrEmpty(memberName))
                        return false;
                    memberNames[m] = memberName;
                    memberValues[m] = outMemberValues[m];
                }
                enums.Add(new Columnar.ColumnarEnumInput(enumName, memberNames, memberValues));
            }
            return true;
        }
        catch
        {
            enums = new System.Collections.Generic.List<Columnar.ColumnarEnumInput>();
            return false;
        }
    }

    // Collect every top-level struct/class/record declaration into a ColumnarStructInput (name + field names + field
    // TYPE canonical strings + optional static-field initializer text). Consumes the shared token bundle, finds each
    // declaration keyword, and parses its body via the ParseStructDeclarationInfo kernel. Returns true (possibly an
    // empty list) for a program with no supported declarations. Returns FALSE — declining the whole program to C# —
    // on any parse failure (a primary-ctor struct, unsupported member shape, composed base type, etc.).
    private static bool TryGetColumnarStructInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        out System.Collections.Generic.List<Columnar.ColumnarStructInput> structs)
    {
        structs = new System.Collections.Generic.List<Columnar.ColumnarStructInput>();
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            // Collect value-type structs (keyword 9, IsReference=false) AND reference-type records (keyword 13) and
            // classes (keyword 8), both IsReference=true — all three share the identical decl kernel + body syntax.
            // Records carry IsRecord=true: the oracle emits records SEALED, so a record can never be a BASE type
            // (and record inheritance itself is unmodelled) — the emitter declines those shapes by this flag.
            var decls = new System.Collections.Generic.List<(int Index, bool IsReference, bool IsRecord)>();
            var structIndices = new int[n + 1];
            var structIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 9, 1, structIndices);
            if (structIndexCount < 0)
                return false;
            for (var i = 0; i < structIndexCount; i++) decls.Add((structIndices[i], false, false));
            var recordIndices = new int[n + 1];
            var recordIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 13, 0, recordIndices);
            if (recordIndexCount < 0)
                return false;
            for (var i = 0; i < recordIndexCount; i++) decls.Add((recordIndices[i], true, true));
            var classIndices = new int[n + 1];
            var classIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 8, 1, classIndices);
            if (classIndexCount < 0)
                return false;
            for (var i = 0; i < classIndexCount; i++) decls.Add((classIndices[i], true, false));
            foreach (var (structIndex, isReference, isRecord) in decls)
            {
                var cap = n + 1;
                var outFieldNameStarts = new int[cap];
                var outFieldNameLengths = new int[cap];
                var outFieldNameTexts = new string[cap];
                var outFieldTypeStarts = new int[cap];
                var outFieldTypeLengths = new int[cap];
                var outFieldTypeTexts = new string[cap];
                var outFieldStaticFlags = new int[cap];
                var outFieldInitKinds = new int[cap];
                var outFieldInitStarts = new int[cap];
                var outFieldInitLengths = new int[cap];
                var outFieldInitTexts = new string[cap];
                var outMethodFuncIndices = new int[cap];
                var outMethodStaticFlags = new int[cap];
                var outCtorIndices = new int[cap];
                var outPropIndices = new int[cap];
                var outPropStaticFlags = new int[cap];
                var outTypeParamStarts = new int[cap];
                var outTypeParamLengths = new int[cap];
                var outTypeParamTexts = new string[cap];
                var outBaseNameStarts = new int[cap];
                var outBaseNameLengths = new int[cap];
                var outBaseNameTexts = new string[cap];
                var outStructNameTexts = new string[1];
                var outResult = new int[12];
                var fieldCount = bindings.ParseStructDeclarationInfo(
                    source, ck, cs, cv, n, structIndex, outFieldNameStarts, outFieldNameLengths, outFieldNameTexts, outFieldTypeStarts,
                    outFieldTypeLengths, outFieldTypeTexts, outFieldStaticFlags, outFieldInitKinds, outFieldInitStarts, outFieldInitLengths,
                    outFieldInitTexts, outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
                    outTypeParamStarts, outTypeParamLengths, outTypeParamTexts, outBaseNameStarts, outBaseNameLengths, outBaseNameTexts,
                    outStructNameTexts, outResult);
                // The kernel returns -1 on a parse failure; 0 is a legitimate FIELDLESS type. A zero-field
                // REFERENCE type (a pure-behavior class — e.g. an inheritance base with only methods) is modelled;
                // a zero-field VALUE struct keeps declining (a zero-size value type is a CLR layout edge case).
                if (fieldCount < 0 || (fieldCount == 0 && !isReference) || outResult[1] <= 0)
                    return false;

                var structName = outStructNameTexts[0];
                if (string.IsNullOrEmpty(structName))
                    return false;
                // The optional `: Base[, IFace...]` list. The emitter resolves it against the declared types and
                // validates: at most one class base on a class, otherwise interfaces only.
                var baseNameCount = outResult[8];
                var baseNames = new string[baseNameCount];
                for (var b = 0; b < baseNameCount; b++)
                {
                    var baseName = outBaseNameTexts[b];
                    if (string.IsNullOrEmpty(baseName))
                        return false;
                    baseNames[b] = baseName;
                }

                // Optional generic type parameters `<T, U>` (outResult[7] = count). Generic RECORDS are
                // modelled (columnar's record fields are plain public fields — the oracle's backing-field
                // lowering for init-only members is an oracle-internal concern, no modreq to lose here); a
                // generic type with a BASE declines (generic base chains are unsupported in the oracle's
                // closed-member machinery too).
                var typeParamCount = outResult[7];
                string[]? typeParamNames = null;
                if (typeParamCount > 0)
                {
                    if (baseNames.Length > 0)
                        return false;

                    typeParamNames = new string[typeParamCount];
                    for (var tp = 0; tp < typeParamCount; tp++)
                    {
                        var typeParamName = outTypeParamTexts[tp];
                        if (string.IsNullOrEmpty(typeParamName))
                            return false;
                        typeParamNames[tp] = typeParamName;
                    }
                }
                var fieldNames = new string[fieldCount];
                var fieldTypes = new string[fieldCount];
                var fieldStatics = new bool[fieldCount];
                var fieldInitKinds = new int[fieldCount];
                var fieldInitTexts = new string?[fieldCount];
                for (var f = 0; f < fieldCount; f++)
                {
                    var fieldName = outFieldNameTexts[f];
                    if (string.IsNullOrEmpty(fieldName))
                        return false;
                    fieldNames[f] = fieldName;
                    var fieldType = outFieldTypeTexts[f];
                    if (string.IsNullOrEmpty(fieldType))
                        return false;
                    fieldTypes[f] = fieldType;
                    fieldStatics[f] = outFieldStaticFlags[f] == 1;
                    fieldInitKinds[f] = outFieldInitKinds[f];
                    if (outFieldInitKinds[f] >= 0)
                    {
                        var fieldInitText = outFieldInitTexts[f];
                        if (string.IsNullOrEmpty(fieldInitText))
                            return false;
                        fieldInitTexts[f] = fieldInitText;
                    }
                }

                // Each method (its `func` token index recorded by the kernel) is parsed with the SAME signature +
                // statement-body kernels as a top-level function — so a struct method's body is just a
                // ColumnarFunctionInput. The kernel's static flag (a `static` keyword before the `func`) is carried
                // onto the input; the emitter declares an instance method or a STATIC method on the TypeBuilder
                // accordingly.
                var methodCount = outResult[2];
                var methods = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>(methodCount);
                for (var m = 0; m < methodCount; m++)
                {
                    if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, outMethodFuncIndices[m], source, out var methodInput, isStatic: outMethodStaticFlags[m] == 1))
                        return false;
                    methods.Add(methodInput);
                }

                // Each user CONSTRUCTOR (its `constructor`-identifier token index recorded by the kernel) is parsed
                // like a nameless, void-returning function — the adapter verifies the identifier text is literally
                // "constructor" and that there is no return type / chaining initializer (decline otherwise).
                var ctorCount = outResult[3];
                // A RECORD with a USER CONSTRUCTOR declines (generic or not): the pipeline silently DROPS the
                // ctor body's field assignments (a record ctor emits only the base call — `new R(5)` yields
                // x==0 where columnar's faithful emit yields 5; adversarial-review finding, probe-confirmed
                // BOTH builds). Until the oracle defect is fixed, accepting would emit DIFFERENT-behavior IL.
                if (isRecord && ctorCount > 0)
                    return false;
                var constructors = new System.Collections.Generic.List<Columnar.ColumnarConstructorInput>(ctorCount);
                for (var c = 0; c < ctorCount; c++)
                {
                    if (!TryParseColumnarConstructorAt(bindings, ck, cs, cv, n, outCtorIndices[c], source, out var ctorInput))
                        return false;
                    constructors.Add(ctorInput);
                }

                // Each get-only PROPERTY (its name token index recorded by the kernel) parses to a get_Name accessor
                // function. A property with a `set` (or any non-`get` accessor) declines (get-only this slice).
                var propCount = outResult[4];
                var properties = new System.Collections.Generic.List<Columnar.ColumnarPropertyInput>(propCount);
                for (var pr = 0; pr < propCount; pr++)
                {
                    if (!TryParseColumnarPropertyAt(bindings, ck, cs, cv, n, outPropIndices[pr], source, out var propInput, isStatic: outPropStaticFlags[pr] == 1))
                        return false;
                    properties.Add(propInput);
                }

                if (typeParamNames != null)
                {
                    // Pipeline NL306 parity: a MEMBER name colliding with a TYPE-PARAMETER name is "already
                    // declared in this scope" — decline (adversarial-review finding: columnar accepted
                    // `record W<T> { T: int }` shapes the pipeline rejects).
                    var typeParamSet = new System.Collections.Generic.HashSet<string>(typeParamNames, System.StringComparer.Ordinal);
                    foreach (var fn in fieldNames)
                    {
                        if (typeParamSet.Contains(fn))
                            return false;
                    }
                    foreach (var m in methods)
                    {
                        if (typeParamSet.Contains(m.Name))
                            return false;
                    }
                    foreach (var p in properties)
                    {
                        if (typeParamSet.Contains(p.Name))
                            return false;
                    }
                    // STATIC fields on a generic type: both pipelines today emit a static-field token against
                    // the OPEN generic (BadImageFormatException at JIT — oracle defect bundle). Decline so
                    // columnar never ships invalid IL; the program routes to the analyzer-backed C# path.
                    foreach (var isStaticField in fieldStatics)
                    {
                        if (isStaticField)
                            return false;
                    }
                }

                structs.Add(new Columnar.ColumnarStructInput(structName, fieldNames, fieldTypes, methods, constructors, properties, isReference, baseNames, fieldStatics, fieldInitKinds, fieldInitTexts, isRecord, typeParamNames));
            }
            return true;
        }
        catch
        {
            structs = new System.Collections.Generic.List<Columnar.ColumnarStructInput>();
            return false;
        }
    }

    // Collect every top-level `union` declaration into a ColumnarUnionInput (name + optional generic type-parameter
    // names + per-case name + per-case field names + per-case field TYPE canonical strings). Consumes the shared
    // token bundle, finds each union keyword (TopLevelUnionIndices), and parses its body via the
    // ParseUnionDeclarationInfo kernel — which flattens fields across cases, with outCaseFieldCounts re-segmenting
    // them per case, and returns name/type text so C# does not own union text materialization. Returns true
    // (possibly an empty list) for a program with no unions. Returns FALSE — declining the
    // whole program to C# — on any parse failure (a bare case without a `{ }` body, a composed field type, an empty
    // union). The emitter further gates each field type to a supported CLR type (or one of the union's own type
    // parameters) and models the slice scope (reference-type cases).
    private static bool TryGetColumnarUnionInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        out System.Collections.Generic.List<Columnar.ColumnarUnionInput> unions)
    {
        unions = new System.Collections.Generic.List<Columnar.ColumnarUnionInput>();
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var unionIndices = new int[n + 1];
            var unionIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 12, 0, unionIndices);
            if (unionIndexCount < 0)
                return false;
            for (var unionSlot = 0; unionSlot < unionIndexCount; unionSlot++)
            {
                var unionIndex = unionIndices[unionSlot];
                var cap = n + 1;
                var outCaseNameStarts = new int[cap];
                var outCaseNameLengths = new int[cap];
                var outCaseNameTexts = new string[cap];
                var outCaseFieldCounts = new int[cap];
                var outFieldNameStarts = new int[cap];
                var outFieldNameLengths = new int[cap];
                var outFieldNameTexts = new string[cap];
                var outFieldTypeStarts = new int[cap];
                var outFieldTypeLengths = new int[cap];
                var outFieldTypeTexts = new string[cap];
                var outTypeParamStarts = new int[cap];
                var outTypeParamLengths = new int[cap];
                var outTypeParamTexts = new string[cap];
                var outUnionNameTexts = new string[1];
                var outResult = new int[4];
                var caseCount = bindings.ParseUnionDeclarationInfo(
                    source, ck, cs, cv, n, unionIndex, outCaseNameStarts, outCaseNameLengths, outCaseNameTexts, outCaseFieldCounts,
                    outFieldNameStarts, outFieldNameLengths, outFieldNameTexts, outFieldTypeStarts, outFieldTypeLengths, outFieldTypeTexts,
                    outTypeParamStarts, outTypeParamLengths, outTypeParamTexts, outUnionNameTexts, outResult);
                if (caseCount <= 0 || outResult[1] <= 0)
                    return false;

                var unionName = outUnionNameTexts[0];
                if (string.IsNullOrEmpty(unionName))
                    return false;
                // Optional generic type parameters `<T, U>` after the union name (outResult[2] = count).
                var typeParamCount = outResult[2];
                string[]? typeParamNames = null;
                if (typeParamCount > 0)
                {
                    typeParamNames = new string[typeParamCount];
                    for (var tp = 0; tp < typeParamCount; tp++)
                    {
                        var typeParamName = outTypeParamTexts[tp];
                        if (string.IsNullOrEmpty(typeParamName))
                            return false;
                        typeParamNames[tp] = typeParamName;
                    }
                }
                var caseNames = new string[caseCount];
                var caseFieldNames = new string[caseCount][];
                var caseFieldTypes = new string[caseCount][];
                var fieldCursor = 0;
                for (var c = 0; c < caseCount; c++)
                {
                    var caseName = outCaseNameTexts[c];
                    if (string.IsNullOrEmpty(caseName))
                        return false;
                    caseNames[c] = caseName;
                    var fc = outCaseFieldCounts[c];
                    var names = new string[fc];
                    var types = new string[fc];
                    for (var f = 0; f < fc; f++)
                    {
                        var fieldName = outFieldNameTexts[fieldCursor];
                        if (string.IsNullOrEmpty(fieldName))
                            return false;
                        names[f] = fieldName;
                        var fieldType = outFieldTypeTexts[fieldCursor];
                        if (string.IsNullOrEmpty(fieldType))
                            return false;
                        types[f] = fieldType;
                        fieldCursor++;
                    }
                    caseFieldNames[c] = names;
                    caseFieldTypes[c] = types;
                }

                unions.Add(new Columnar.ColumnarUnionInput(unionName, caseNames, caseFieldNames, caseFieldTypes, typeParamNames));
            }
            return true;
        }
        catch
        {
            unions = new System.Collections.Generic.List<Columnar.ColumnarUnionInput>();
            return false;
        }
    }

    // Parse ONE top-level function (at compacted token index `funcIndex`) into its signature + columnar body
    // node tables. Returns false on any parse failure or a missing body brace.
    private static bool TryParseColumnarFunctionAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int funcIndex, string source,
        out Columnar.ColumnarFunctionInput input, bool isStatic = false, bool isAsync = false)
    {
        input = null!;
        var cap = n + 1;

        var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
        var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
        var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
        var pNameTexts = new string[cap];
        var sres = new int[8];
        var sTypeParamStarts = new int[cap];
        var sTypeParamLengths = new int[cap];
        var sTypeParamTexts = new string[cap];
        var sWhereNameStarts = new int[cap];
        var sWhereNameLengths = new int[cap];
        var sWhereNameTexts = new string[cap];
        var sWhereItemCodes = new int[cap];
        var sWhereOwnerIndices = new int[cap];
        var sFunctionNameTexts = new string[1];
        var paramCount = bindings.ParseFunctionSignatureTextInfo(
            source, ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
            pNameStart, pNameLen, pNameTexts, pTypeRoot, sTypeParamStarts, sTypeParamLengths, sTypeParamTexts,
            sWhereNameStarts, sWhereNameLengths, sWhereNameTexts, sWhereItemCodes, sFunctionNameTexts, sres);
        if (paramCount < 0 || sres[3] < 0)
            return false;

        var fname = sFunctionNameTexts[0];
        if (string.IsNullOrEmpty(fname))
            return false;
        // sres[1] is the return-type tree root, or -1 when the function OMITS its return type (`func f(...) {`,
        // implicit void — the kernel sets returnRoot = -1, a valid signature, not a parse error). Canonicalize to
        // "void" in that case (the emitter's pass 1 maps "void" -> typeof(void)), matching the columnar
        // type-inference parity harness. Without this,
        // SemanticScopes' implicit-void procedures (SortIdsByStart, ClearTouched) declined the whole file at parse.
        var returnCanonical = sres[1] >= 0
            ? bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, sres[1])
            : "void";
        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        string[]?[]? paramTupleNames = null;
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = pNameTexts[p];
            if (string.IsNullOrEmpty(paramName))
                return false;
            paramNames[p] = paramName;
            paramCanonicals[p] = bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, pTypeRoot[p]);
            if (!TryGetTypeReferenceTupleElementNames(bindings, source, sk, sns, snl, scs, scc, sci, pTypeRoot[p], out var paramElementNames))
                return false;
            if (paramElementNames is { })
                (paramTupleNames ??= new string[paramCount][])[p] = paramElementNames;
        }
        string[]? returnTupleNames = null;
        if (sres[1] >= 0 && !TryGetTypeReferenceTupleElementNames(bindings, source, sk, sns, snl, scs, scc, sci, sres[1], out returnTupleNames))
            return false;

        // Generic TYPE PARAMETERS (`func Identity<T>(...)`): sres[5] names parsed by the kernel. The token at
        // sres[6] (immediately after the signature, PAST any `where` clauses) must be the body `{` — anything
        // else is an unmodelled trailer (an `=>` expression body) and declines to the C# path.
        var bodyBrace = sres[6];
        if (bodyBrace >= n || ck[bodyBrace] != 129)
            return false;
        var typeParamNames = System.Array.Empty<string>();
        if (sres[5] > 0)
        {
            typeParamNames = new string[sres[5]];
            for (var t = 0; t < sres[5]; t++)
            {
                var typeParamName = sTypeParamTexts[t];
                if (string.IsNullOrEmpty(typeParamName))
                    return false;
                typeParamNames[t] = typeParamName;
            }
        }

        // Generic CONSTRAINTS (`where T: Base, new()` — D-17b): the kernel reports flat rows (owner-name span +
        // code); group them by declared type-parameter position. Constraints CANNOT be silently dropped (the
        // pipeline enforces NL208 at call sites, so ignoring them would over-accept constraint-violating
        // programs) — every row either lands on its parameter or the whole function declines: an owner naming
        // no declared type parameter declines, and the combos the production parser ERRORS on (`class` with
        // `struct`, `struct` with `new()`) decline so the C# path surfaces its diagnostics. Special flags
        // mirror SpecialConstraintKind (Class=1, Struct=2, New=4).
        var whereItemCount = sres[7];
        int[]? typeParamSpecials = null;
        string[][]? typeParamTypeConstraints = null;
        if (whereItemCount > 0)
        {
            if (typeParamNames.Length == 0)
                return false;
            typeParamSpecials = new int[typeParamNames.Length];
            var constraintLists = new List<string>[typeParamNames.Length];
            var ownerIndexCount = bindings.FunctionSignatureWhereOwnerIndices(
                source, sTypeParamStarts, sTypeParamLengths, typeParamNames.Length,
                sWhereNameStarts, sWhereNameLengths, whereItemCount, sWhereOwnerIndices);
            if (ownerIndexCount != whereItemCount)
                return false;
            for (var w = 0; w < whereItemCount; w++)
            {
                var ownerIndex = sWhereOwnerIndices[w];
                if ((uint)ownerIndex >= (uint)typeParamNames.Length)
                    return false;
                var code = sWhereItemCodes[w];
                if (code >= 0)
                    (constraintLists[ownerIndex] ??= new List<string>()).Add(
                        bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, code));
                else if (code == -2)
                    typeParamSpecials[ownerIndex] |= 1;
                else if (code == -3)
                    typeParamSpecials[ownerIndex] |= 2;
                else if (code == -4)
                    typeParamSpecials[ownerIndex] |= 4;
                else
                    return false;
            }
            typeParamTypeConstraints = new string[typeParamNames.Length][];
            for (var t = 0; t < typeParamNames.Length; t++)
            {
                if ((typeParamSpecials[t] & 3) == 3 || (typeParamSpecials[t] & 6) == 6)
                    return false;
                typeParamTypeConstraints[t] = constraintLists[t]?.ToArray() ?? System.Array.Empty<string>();
            }
        }

        var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
        var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
        var bres = new int[2];
        var bodyNodeCount = bindings.ParseStatementNodes(
            ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
        if (bodyNodeCount <= 0)
            return false;

        var bodyNodes = new Columnar.ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
        input = new Columnar.ColumnarFunctionInput(
            fname, returnCanonical, paramNames, paramCanonicals,
            bodyNodes, bres[0], isStatic, typeParamNames,
            typeParamSpecials, typeParamTypeConstraints,
            returnTupleElementNames: returnTupleNames, paramTupleElementNames: paramTupleNames,
            isAsync: isAsync);

        // LOCAL FUNCTIONS (kind-41 statements that are DIRECT children of the root block): each node's
        // value span is the `func` keyword's byte span — re-locate the token and parse the nested
        // declaration through the same kernels (recursively: a local function may declare its own).
        // Nested-BLOCK declarations are deliberately NOT collected — their kind-41 nodes stay undeclared
        // and the emitter declines them (scope-precise under-acceptance).
        var rootBlock = bres[0];
        if (bk[rootBlock] == 25)
        {
            for (var rc = 0; rc < bcc[rootBlock]; rc++)
            {
                var stmtNode = bci[bcs[rootBlock] + rc];
                if (bk[stmtNode] != 41)
                    continue;
                var funcTokenIndex = bindings.TokenIndexByKindStart(ck, cs, n, 7, bvs[stmtNode]);
                if (funcTokenIndex < 0)
                    return false;
                if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, funcTokenIndex, source, out var localFn))
                    return false;
                (input.LocalFunctions ??= new List<(int, Columnar.ColumnarFunctionInput)>()).Add((stmtNode, localFn));
            }
        }
        return true;
    }

    // Parse ONE user CONSTRUCTOR (at compacted token index `ctorIndex`, the "constructor" identifier) into a
    // ColumnarFunctionInput whose name is "constructor" and whose return is "void". Reuses the function-signature
    // kernel (a constructor has no name token and no `: ret`, so it yields funcNameStart = -1 and returnRoot = -1)
    // and the statement kernel for the body. Declines if the signature has a return type (a
    // `: this(...)`/`base(...)` chaining initializer makes the kernel's return-type parse fail →
    // paramCount < 0), or the body is missing.
    private static bool TryParseColumnarConstructorAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int ctorIndex, string source,
        out Columnar.ColumnarConstructorInput input)
    {
        input = null!;
        var cap = n + 1;
        var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
        var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
        var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
        var pNameTexts = new string[cap];
        var sres = new int[8];
        var sTypeParamStarts = new int[cap];
        var sTypeParamLengths = new int[cap];
        var sTypeParamTexts = new string[cap];
        var sWhereNameStarts = new int[cap];
        var sWhereNameLengths = new int[cap];
        var sWhereNameTexts = new string[cap];
        var sWhereItemCodes = new int[cap];
        var sFunctionNameTexts = new string[1];
        var paramCount = bindings.ParseFunctionSignatureTextInfo(
            source, ck, cs, cv, n, ctorIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
            pNameStart, pNameLen, pNameTexts, pTypeRoot, sTypeParamStarts, sTypeParamLengths, sTypeParamTexts,
            sWhereNameStarts, sWhereNameLengths, sWhereNameTexts, sWhereItemCodes, sFunctionNameTexts, sres);
        // A constructor must have NO return type (sres[1] = -1), NO generic type parameters (sres[5] = 0), and
        // NO `where` constraint rows (sres[7] = 0). A non-negative return root means a `: <type>` was parsed —
        // for a constructor that is malformed (or a chaining initializer the kernel rejected differently).
        if (paramCount < 0 || sres[1] >= 0 || sres[5] != 0 || sres[7] != 0)
            return false;

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = pNameTexts[p];
            if (string.IsNullOrEmpty(paramName))
                return false;
            paramNames[p] = paramName;
            paramCanonicals[p] = bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, pTypeRoot[p]);
        }

        // Parse the optional `: this(args)` / `: base(args)` chaining initializer (chained args restricted to a param
        // identifier or an int literal; a complex/other-literal arg returns -1 -> decline the whole ctor). The same
        // dogfood kernel reports the body `{` after the optional initializer, keeping constructor body delimiting out
        // of the C# adapter.
        var caKinds = new int[cap];
        var caStarts = new int[cap];
        var caLengths = new int[cap];
        var caTexts = new string[cap];
        var caRes = new int[2];
        var chainArgCount = bindings.ParseConstructorTextInfo(source, ck, cs, cv, n, ctorIndex, caKinds, caStarts, caLengths, caTexts, caRes);
        if (chainArgCount < 0)
            return false;
        var bodyBrace = caRes[1];
        if (bodyBrace < 0 || bodyBrace >= n || ck[bodyBrace] != 129)
            return false;

        var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
        var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
        var bres = new int[2];
        var bodyNodeCount = bindings.ParseStatementNodes(
            ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
        if (bodyNodeCount <= 0)
            return false;

        var chainArgKinds = new int[chainArgCount];
        var chainArgTexts = new string[chainArgCount];
        for (var a = 0; a < chainArgCount; a++)
        {
            chainArgKinds[a] = caKinds[a];
            var chainArgText = caTexts[a];
            if (string.IsNullOrEmpty(chainArgText))
                return false;
            chainArgTexts[a] = chainArgText;
        }

        var bodyNodes = new Columnar.ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
        var body = new Columnar.ColumnarFunctionInput(
            "constructor", "void", paramNames, paramCanonicals,
            bodyNodes, bres[0]);
        input = new Columnar.ColumnarConstructorInput(body, caRes[0], chainArgKinds, chainArgTexts);
        return true;
    }

    // Parse ONE computed PROPERTY (at compacted token index `propIndex`, the property NAME). The kernel recorded it
    // as `Name : Type { … }`; the layout is name(propIndex) `:`(+1) Type(+2) `{`(+3, property block) `get`(+4,
    // identifier "get") `{`(+5, get body). The getter body parses into a ColumnarFunctionInput named "get_Name"
    // (no params, returning the property type). After the get body's `}`, an OPTIONAL `set { … }` accessor parses
    // into "set_Name" (one param "value": Type, returning void); else the property block must close with `}`. A
    // set-first ordering, an expression-bodied accessor, or a third accessor declines (get / get-set this slice).
    private static bool TryParseColumnarPropertyAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int propIndex, string source,
        out Columnar.ColumnarPropertyInput input, bool isStatic = false)
    {
        input = null!;
        var propInfo = new int[6];
        var propNameTexts = new string[1];
        var propTypeTexts = new string[1];
        var accessorKind = bindings.ParsePropertyAccessorTypeInfo(source, ck, cs, cv, n, propIndex, propNameTexts, propTypeTexts, propInfo);
        if (accessorKind < 0)
            return false;

        var propName = propNameTexts[0];
        if (string.IsNullOrEmpty(propName))
            return false;
        var propType = propTypeTexts[0];
        if (string.IsNullOrEmpty(propType))
            return false;
        var cap = n + 1;

        var getBodyBrace = propInfo[4];
        if (getBodyBrace < 0 || getBodyBrace >= n || ck[getBodyBrace] != 129)
            return false;
        var gk = new int[cap]; var gvs = new int[cap]; var gvl = new int[cap]; var gcs = new int[cap];
        var gcc = new int[cap]; var gci = new int[cap]; var gss = new int[cap]; var gsl = new int[cap];
        var gres = new int[2];
        if (bindings.ParseStatementNodes(ck, cs, cv, n, getBodyBrace, gk, gvs, gvl, gcs, gcc, gci, gss, gsl, gres) <= 0)
            return false;
        var getterNodes = new Columnar.ColumnarNodeTable(gk, gvs, gvl, gcs, gcc, gci);
        var getter = new Columnar.ColumnarFunctionInput(
            "get_" + propName, propType, System.Array.Empty<string>(), System.Array.Empty<string>(),
            getterNodes, gres[0]);

        Columnar.ColumnarFunctionInput? setter = null;
        if (accessorKind == 0)
        {
            // get-only.
        }
        else if (accessorKind == 1)
        {
            // `set { setBody }` — implicit `value` parameter of the property type, void return.
            var setBodyBrace = propInfo[5];
            if (setBodyBrace < 0 || setBodyBrace >= n || ck[setBodyBrace] != 129)
                return false;
            var stk = new int[cap]; var stvs = new int[cap]; var stvl = new int[cap]; var stcs = new int[cap];
            var stcc = new int[cap]; var stci = new int[cap]; var stss = new int[cap]; var stsl = new int[cap];
            var stres = new int[2];
            if (bindings.ParseStatementNodes(ck, cs, cv, n, setBodyBrace, stk, stvs, stvl, stcs, stcc, stci, stss, stsl, stres) <= 0)
                return false;
            var setterNodes = new Columnar.ColumnarNodeTable(stk, stvs, stvl, stcs, stcc, stci);
            setter = new Columnar.ColumnarFunctionInput(
                "set_" + propName, "void", new[] { "value" }, new[] { propType },
                setterNodes, stres[0]);
        }
        else
        {
            return false;
        }

        input = new Columnar.ColumnarPropertyInput(propName, propType, getter, setter, isStatic);
        return true;
    }

    private static bool TryGetTypeReferenceTupleElementNames(
        Bindings bindings, string source,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        int root, out string[]? names)
    {
        names = null;
        if (root < 0)
            return true;

        var buffer = new string[Math.Max(1, childCount[root])];
        var count = bindings.TypeReferenceTupleElementNames(source, kinds, valueStarts, valueLengths, childStart, childCount, childIndices, root, buffer);
        if (count < 0)
            return false;
        if (count == 0)
            return true;

        names = new string[count];
        Array.Copy(buffer, names, count);
        return true;
    }

    // Collect every top-level `interface` declaration into a ColumnarInterfaceInput (name + abstract
    // method SIGNATURES — names, return canonicals, param names/canonicals). Consumes the shared
    // token bundle, finds each interface keyword through the N# declaration-index kernel, parses the member layout via the
    // ParseInterfaceDeclarationInfo kernel (method signatures ONLY — default bodies, bare members, properties, and
    // generics return -1 there; base-interface names are carried as text), then each member's signature via the
    // shared ParseFunctionSignature kernel.
    // Returns true (possibly empty) for a program with no interfaces; FALSE declines the program.
    // IF-1 declines: generic members, where-clauses, tuple element names on member types.
    private static bool TryGetColumnarInterfaceInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        out System.Collections.Generic.List<Columnar.ColumnarInterfaceInput> interfaceInputs)
    {
        interfaceInputs = new System.Collections.Generic.List<Columnar.ColumnarInterfaceInput>();
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var interfaceIndices = new int[n + 1];
            var interfaceIndexCount = bindings.TopLevelDeclarationIndices(ck, n, 10, 0, interfaceIndices);
            if (interfaceIndexCount < 0)
                return false;
            for (var interfaceSlot = 0; interfaceSlot < interfaceIndexCount; interfaceSlot++)
            {
                var interfaceIndex = interfaceIndices[interfaceSlot];
                var cap = n + 1;
                var outMethodFuncIndices = new int[cap];
                var outBaseNameStarts = new int[cap];
                var outBaseNameLengths = new int[cap];
                var outBaseNameTexts = new string[cap];
                var outInterfaceNameTexts = new string[1];
                var outResult = new int[8];
                var methodCount = bindings.ParseInterfaceDeclarationInfo(source, ck, cs, cv, n, interfaceIndex,
                    outMethodFuncIndices, outBaseNameStarts, outBaseNameLengths, outBaseNameTexts, outInterfaceNameTexts, outResult);
                if (methodCount < 0)
                    return false;
                var interfaceName = outInterfaceNameTexts[0];
                if (string.IsNullOrEmpty(interfaceName))
                    return false;
                var baseInterfaceCount = outResult[2];
                var baseInterfaceNames = new string[baseInterfaceCount];
                for (var b = 0; b < baseInterfaceCount; b++)
                {
                    var baseInterfaceName = outBaseNameTexts[b];
                    if (string.IsNullOrEmpty(baseInterfaceName))
                        return false;
                    baseInterfaceNames[b] = baseInterfaceName;
                }
                var methodNames = new string[methodCount];
                var methodReturns = new string[methodCount];
                var methodParamNames = new string[methodCount][];
                var methodParamCanonicals = new string[methodCount][];
                var methodBodies = new Columnar.ColumnarFunctionInput?[methodCount];
                for (var m = 0; m < methodCount; m++)
                {
                    var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                    var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                    var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                    var pNameTexts = new string[cap];
                    var sres = new int[8];
                    var sTypeParamStarts = new int[cap];
                    var sTypeParamLengths = new int[cap];
                    var sTypeParamTexts = new string[cap];
                    var sWhereNameStarts = new int[cap];
                    var sWhereNameLengths = new int[cap];
                    var sWhereNameTexts = new string[cap];
                    var sWhereItemCodes = new int[cap];
                    var sFunctionNameTexts = new string[1];
                    var paramCount = bindings.ParseFunctionSignatureTextInfo(
                        source, ck, cs, cv, n, outMethodFuncIndices[m], sk, sns, snl, scs, scc, sci, sss, ssl,
                        pNameStart, pNameLen, pNameTexts, pTypeRoot, sTypeParamStarts, sTypeParamLengths, sTypeParamTexts,
                        sWhereNameStarts, sWhereNameLengths, sWhereNameTexts, sWhereItemCodes, sFunctionNameTexts, sres);
                    if (paramCount < 0 || sres[3] < 0)
                        return false;
                    if (sres[5] > 0 || sres[7] > 0)
                        return false; // generic interface members / where-clauses are unmodeled.
                    var afterSignature = sres[6];
                    if (afterSignature >= n)
                        return false;
                    var methodName = sFunctionNameTexts[0];
                    if (string.IsNullOrEmpty(methodName))
                        return false;
                    methodNames[m] = methodName;
                    methodReturns[m] = sres[1] >= 0
                        ? bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, sres[1])
                        : "void";
                    string[]? returnTupleNames = null;
                    if (sres[1] >= 0)
                    {
                        if (!TryGetTypeReferenceTupleElementNames(bindings, source, sk, sns, snl, scs, scc, sci, sres[1], out returnTupleNames))
                            return false;
                    }
                    if (returnTupleNames != null)
                        return false; // named-tuple member returns are unmodeled.
                    methodParamNames[m] = new string[paramCount];
                    methodParamCanonicals[m] = new string[paramCount];
                    for (var p = 0; p < paramCount; p++)
                    {
                        var paramName = pNameTexts[p];
                        if (string.IsNullOrEmpty(paramName))
                            return false;
                        methodParamNames[m][p] = paramName;
                        methodParamCanonicals[m][p] = bindings.TypeReferenceCanonicalText(source, sk, sns, snl, scs, scc, sci, pTypeRoot[p]);
                        if (!TryGetTypeReferenceTupleElementNames(bindings, source, sk, sns, snl, scs, scc, sci, pTypeRoot[p], out var paramTupleNames))
                            return false;
                        if (paramTupleNames != null)
                            return false;
                    }
                    if (ck[afterSignature] == 129)
                    {
                        if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, outMethodFuncIndices[m], source, out var bodyInput))
                            return false;
                        if (bodyInput.LocalFunctions != null)
                            return false;
                        methodBodies[m] = bodyInput;
                    }
                    else if (ck[afterSignature] != 7 && ck[afterSignature] != 130)
                    {
                        return false;
                    }
                }
                interfaceInputs.Add(new Columnar.ColumnarInterfaceInput(
                    interfaceName, baseInterfaceNames, methodNames, methodReturns, methodParamNames, methodParamCanonicals, methodBodies));
            }
            return true;
        }
        catch
        {
            interfaceInputs = new System.Collections.Generic.List<Columnar.ColumnarInterfaceInput>();
            return false;
        }
    }

    /// <summary>
    /// Single-pass replacement for ProjectConfig.GetSourceFiles' post-enumeration filtering
    /// (test-file filter + exclude-glob filter). Materializes the kept files preserving enumeration
    /// order. Returns false (so callers keep the C# path) when the dogfood assembly is unavailable
    /// or any input is unexpected.
    /// </summary>
    internal static bool TryFilterSourceFiles(
        string[] files,
        string projectRoot,
        Func<string, string, string> getRelativePath,
        string[] excludePatterns,
        bool includeTests,
        out string[] filteredFiles)
    {
        filteredFiles = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fileCount = files.Length;
        if (fileCount == 0)
            return true;

        var scratch = t_projectSourceFilterScratch ??= new ProjectSourceFilterScratch();
        scratch.EnsureCapacity(fileCount);

        try
        {
            for (var i = 0; i < fileCount; i++)
            {
                var file = files[i];
                if (file == null)
                    return false;

                var relativePath = getRelativePath(projectRoot, file);

                // The production glob uses .NET regex, where '.' (and '.*') does not match '\n' and
                // the trailing '$' anchor matches before a final '\n'. The N# kernel treats '\n' as
                // an ordinary character, so fall back to the exact C# regex path for the (extremely
                // rare) case of a newline in an on-disk file path to preserve exact parity.
                if (relativePath.Contains('\n'))
                    return false;

                scratch.RelativePaths[i] = relativePath;
            }

            var keptCount = bindings.ProjectSourceFilterKeptIndices(
                scratch.RelativePaths,
                excludePatterns,
                includeTests ? 1 : 0,
                scratch.ResultIndices);

            if (keptCount < 0 || keptCount > fileCount)
                return false;

            var result = new string[keptCount];
            for (var i = 0; i < keptCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fileCount)
                    return false;

                result[i] = files[sourceIndex];
            }

            filteredFiles = result;
            return true;
        }
        catch
        {
            filteredFiles = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearRelativePaths(fileCount);
        }
    }

    internal static bool TryCompactParserTokens(IReadOnlyList<Token> tokens, out List<Token> compactedTokens)
    {
        compactedTokens = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var tokenCount = tokens.Count;
        if (tokenCount == 0)
            return true;

        var scratch = t_parserTokenCompactionScratch ??= new ParserTokenCompactionScratch();
        scratch.EnsureCapacity(tokenCount);

        try
        {
            for (var i = 0; i < tokenCount; i++)
            {
                scratch.TokenKinds[i] = (int)tokens[i].Type;
            }

            var compactedCount = bindings.ParserTokenCompaction(
                scratch.TokenKinds,
                scratch.ResultIndices);

            if (compactedCount < 0 || compactedCount > tokenCount)
            {
                compactedTokens = [];
                return false;
            }

            var result = new List<Token>(compactedCount);
            for (var i = 0; i < compactedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= tokenCount)
                {
                    compactedTokens = [];
                    return false;
                }

                result.Add(tokens[sourceIndex]);
            }

            compactedTokens = result;
            return true;
        }
        catch
        {
            compactedTokens = [];
            return false;
        }
    }

    internal static bool TryOrderImportsBySystemThenNamespace(
        IReadOnlyList<ImportDirective> imports,
        out List<ImportDirective> orderedImports)
    {
        orderedImports = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = imports.Count;
        if (count == 0)
            return true;

        var scratch = t_formatterImportOrderingScratch ??= new FormatterImportOrderingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetRanks();
            for (var i = 0; i < count; i++)
            {
                var ns = imports[i].Namespace;
                if (ns == null)
                {
                    orderedImports = [];
                    return false;
                }

                // Match the production LINQ shape exactly: OrderByDescending uses the
                // default (current-culture) StartsWith, ThenBy uses Comparer<string>.Default.
                scratch.SystemFlags[i] = ns.StartsWith("System") ? 1 : 0;
                scratch.AddNamespace(ns);
            }

            scratch.BuildRanks();
            for (var i = 0; i < count; i++)
            {
                scratch.NameRanks[i] = scratch.GetRank(imports[i].Namespace);
            }

            var orderedCount = bindings.FormatterImportOrderIndices(
                scratch.SystemFlags,
                scratch.NameRanks,
                scratch.UniqueNamespaceCount,
                scratch.BucketCounts,
                scratch.BucketOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount != count)
            {
                orderedImports = [];
                return false;
            }

            var result = new List<ImportDirective>(count);
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    orderedImports = [];
                    return false;
                }

                result.Add(imports[sourceIndex]);
            }

            orderedImports = result;
            return true;
        }
        catch
        {
            orderedImports = [];
            return false;
        }
        finally
        {
            scratch.ResetRanks();
        }
    }

    internal static bool TryDeduplicateFirstTypeKeys(
        IReadOnlyList<Type> types,
        Func<Type, string> getTypeKey,
        out List<Type> deduplicatedTypes)
    {
        deduplicatedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var typeCount = types.Count;
        if (typeCount == 0)
            return true;

        var scratch = t_firstDistinctTypeKeyScratch ??= new FirstDistinctTypeKeyScratch();
        scratch.EnsureCapacity(typeCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < typeCount; i++)
            {
                scratch.TypeRanks[i] = scratch.AddKey(getTypeKey(types[i]));
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.TypeRanks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > typeCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedTypes = [];
                return false;
            }

            var result = new List<Type>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= typeCount)
                {
                    deduplicatedTypes = [];
                    return false;
                }

                result.Add(types[sourceIndex]);
            }

            deduplicatedTypes = result;
            return true;
        }
        catch
        {
            deduplicatedTypes = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDeduplicateFirstStringsOrdinalIgnoreCase(
        IReadOnlyList<string> values,
        out List<string> deduplicatedValues)
    {
        deduplicatedValues = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_firstDistinctStringScratch ??= new FirstDistinctStringScratch(StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    deduplicatedValues = [];
                    return false;
                }

                scratch.Ranks[i] = scratch.AddKey(value);
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > valueCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = [];
                return false;
            }

            var result = new List<string>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = [];
                    return false;
                }

                result.Add(values[sourceIndex]);
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDistinctOrderStringsOrdinal(
        IReadOnlyList<string> values,
        out string[] orderedValues)
    {
        orderedValues = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_distinctOrderedStringScratch ??= new DistinctOrderedStringScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetValues();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                scratch.Values[i] = value;
                scratch.AddValue(value);
            }

            scratch.BuildRanks();
            for (var i = 0; i < valueCount; i++)
            {
                scratch.ValueRanks[i] = scratch.GetRank(scratch.Values[i]);
            }

            var orderedCount = bindings.ReferenceFileSummaryRanks(
                scratch.ValueRanks,
                scratch.UniqueValueCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (orderedCount < 0 || orderedCount > scratch.UniqueValueCount || orderedCount > scratch.ResultRanks.Length)
            {
                orderedValues = Array.Empty<string>();
                return false;
            }

            var result = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueValueCount)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                result[i] = scratch.UniqueValues[rank - 1];
            }

            orderedValues = result;
            return true;
        }
        catch
        {
            orderedValues = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearValues(valueCount);
            scratch.ResetValues();
        }
    }

    internal static bool TryLookupUniqueDeclaredTypeBySuffix<TType>(
        IReadOnlyDictionary<string, TType> types,
        string typeName,
        out TType type,
        out bool found)
        where TType : Type
    {
        type = null!;
        found = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_declaredTypeSuffixLookupScratch ??= new DeclaredTypeSuffixLookupScratch();

        try
        {
            if (!scratch.Load(types))
                return false;

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var rank = bindings.DeclaredTypeUniqueSuffixValueRank(
                scratch.Keys,
                scratch.ValueRanks,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (rank == -2)
                return false;

            if (rank <= 0)
                return true;

            if (rank >= scratch.Values.Length || scratch.Values[rank] is not TType result)
                return false;

            type = result;
            found = true;
            return true;
        }
        catch
        {
            type = null!;
            found = false;
            return false;
        }
    }

    internal static bool TrySelectDeclaredTypeNameCandidate(
        CompilationUnit compilationUnit,
        string typeName,
        out string? candidate)
    {
        candidate = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (string.IsNullOrWhiteSpace(typeName))
            return true;

        var scratch = t_declaredTypeNameCandidateScratch ??= new DeclaredTypeNameCandidateScratch();

        try
        {
            scratch.Load(compilationUnit);

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var index = bindings.DeclaredTypeNameCandidateIndex(
                scratch.Names,
                scratch.ImportedNamespaceFlags,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (index == -2)
                return false;

            if (index <= 0)
                return true;

            var candidateIndex = index - 1;
            if (candidateIndex >= scratch.Count)
                return false;

            candidate = scratch.Names[candidateIndex];
            return true;
        }
        catch
        {
            candidate = null;
            return false;
        }
    }

    internal static bool TryOrderTypesByDescendingKeyDotCount<TType>(
        IEnumerable<TType> types,
        Func<TType, string> getTypeKey,
        out List<TType> orderedTypes)
        where TType : Type
    {
        orderedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_typeCreationOrderScratch ??= new TypeCreationOrderScratch();

        try
        {
            if (!scratch.Load(types, getTypeKey))
                return false;

            if (scratch.Count == 0)
                return true;

            var orderedCount = bindings.TypeCreationOrderIndices(
                scratch.Keys,
                scratch.Count,
                scratch.DotCounts,
                scratch.DepthCounts,
                scratch.DepthOffsets,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > scratch.Count || orderedCount > scratch.ResultIndices.Length)
            {
                orderedTypes = [];
                return false;
            }

            var result = new List<TType>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= scratch.Count || scratch.Values[sourceIndex] is not TType type)
                {
                    orderedTypes = [];
                    return false;
                }

                result.Add(type);
            }

            orderedTypes = result;
            return true;
        }
        catch
        {
            orderedTypes = [];
            return false;
        }
        finally
        {
            scratch.ClearValues();
        }
    }

    internal static bool TryDeclaresAnonymousUnionShims(
        IReadOnlyList<Parameter> parameters,
        Func<TypeReference, bool> isTwoArmAnonymousUnion,
        out bool declaresShims)
    {
        declaresShims = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var parameterCount = parameters.Count;
        if (parameterCount == 0)
            return true;

        var scratch = t_anonymousUnionShimScratch ??= new AnonymousUnionShimScratch();
        scratch.EnsureCapacity(parameterCount);

        try
        {
            var unionParameterCount = 0;
            for (var i = 0; i < parameterCount; i++)
            {
                var parameter = parameters[i];
                if (!isTwoArmAnonymousUnion(parameter.Type))
                {
                    continue;
                }

                var hasDisallowedModifier =
                    parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out or Ast.ParameterModifier.Params;
                scratch.ParameterFlags[unionParameterCount] = hasDisallowedModifier ? 2 : 1;
                unionParameterCount++;
            }

            var result = bindings.AnonymousUnionDeclaresPublicShim(
                scratch.ParameterFlags,
                unionParameterCount);
            if (result is not 0 and not 1)
                return false;

            declaresShims = result != 0;
            return true;
        }
        catch
        {
            declaresShims = false;
            return false;
        }
    }

    /// <summary>
    /// Selects the winning declared-method overload index from a compact candidate table using the
    /// N# ranking kernel. The caller fills the rank columns for each surviving candidate through
    /// <paramref name="fillColumns"/> (writing one entry per candidate into the supplied buffers and
    /// returning the candidate count), and this routine runs the exact four-level tie-break
    /// (score &gt; non-generic &gt; non-params &gt; fewer-defaults, first-wins-on-tie) over those
    /// columns. <paramref name="selectedIndex"/> is the zero-based index of the winning candidate in
    /// fill order, or -1 when no candidate is valid.
    /// </summary>
    internal static bool TrySelectOverloadCandidate(
        int candidateCapacity,
        OverloadColumnFiller fillColumns,
        out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (candidateCapacity < 0)
            return false;

        var scratch = t_overloadCandidateScratch ??= new OverloadCandidateScratch();
        scratch.EnsureCapacity(candidateCapacity);

        try
        {
            var count = fillColumns(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed);

            if (count < 0 || count > candidateCapacity)
                return false;

            var index = bindings.OverloadSelectBestCandidate(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed,
                count);

            if (index < -1 || index >= count)
                return false;

            selectedIndex = index;
            return true;
        }
        catch
        {
            selectedIndex = -1;
            return false;
        }
    }

    /// <summary>
    /// Fills the compact overload-candidate rank columns for surviving candidates and returns the
    /// candidate count.
    /// </summary>
    internal delegate int OverloadColumnFiller(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed);

    internal static bool TrySelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers,
        out List<string> missingMembers)
    {
        missingMembers = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var memberCount = members.Count;
        if (memberCount == 0)
            return true;

        var scratch = t_missingEnumMemberScratch ??= new MissingEnumMemberScratch();
        scratch.EnsureCapacity(memberCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < memberCount; i++)
            {
                var memberName = members[i].Name;
                if (!scratch.AddName(memberName))
                    return false;

                scratch.CoveredFlags[i] = coveredMembers.Contains(memberName) ? 1 : 0;
            }

            var missingCount = bindings.AnalyzerMissingMemberIndices(
                scratch.CoveredFlags,
                memberCount,
                scratch.ResultIndices);

            if (missingCount < 0 || missingCount > memberCount || missingCount > scratch.ResultIndices.Length)
            {
                missingMembers = [];
                return false;
            }

            var result = new List<string>(missingCount);
            for (var i = 0; i < missingCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= memberCount)
                {
                    missingMembers = [];
                    return false;
                }

                result.Add(members[sourceIndex].Name);
            }

            missingMembers = result;
            return true;
        }
        catch
        {
            missingMembers = [];
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static bool TrySelectMissingUnionCasesFromFlags(
        IReadOnlyList<UnionCase> cases,
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        out List<string> missingCases,
        out List<string> partialMissingCases,
        out List<string> neverCoveredCases)
    {
        missingCases = [];
        partialMissingCases = [];
        neverCoveredCases = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (count < 0 || count > cases.Count || count > coveredFlags.Length || count > partialFlags.Length)
            return false;

        if (count == 0)
            return true;

        var scratch = t_missingUnionCaseScratch ??= new MissingUnionCaseScratch();
        scratch.EnsureCapacity(count);

        try
        {
            var missingCount = bindings.AnalyzerUnionMissingCaseIndices(
                coveredFlags,
                partialFlags,
                count,
                scratch.MissingIndices,
                scratch.PartialMissingIndices,
                scratch.NeverCoveredIndices,
                scratch.ResultCounts);

            var partialMissingCount = scratch.ResultCounts[1];
            var neverCoveredCount = scratch.ResultCounts[2];
            if (missingCount < 0 ||
                missingCount > count ||
                partialMissingCount < 0 ||
                partialMissingCount > missingCount ||
                neverCoveredCount < 0 ||
                neverCoveredCount > missingCount ||
                partialMissingCount + neverCoveredCount != missingCount)
            {
                missingCases = [];
                partialMissingCases = [];
                neverCoveredCases = [];
                return false;
            }

            missingCases = MaterializeCaseNames(cases, scratch.MissingIndices, missingCount);
            partialMissingCases = MaterializeCaseNames(cases, scratch.PartialMissingIndices, partialMissingCount);
            neverCoveredCases = MaterializeCaseNames(cases, scratch.NeverCoveredIndices, neverCoveredCount);
            return true;
        }
        catch
        {
            missingCases = [];
            partialMissingCases = [];
            neverCoveredCases = [];
            return false;
        }
    }

    private static List<string> MaterializeCaseNames(
        IReadOnlyList<UnionCase> cases,
        int[] indices,
        int count)
    {
        var result = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            if (sourceIndex < 0 || sourceIndex >= cases.Count)
                throw new InvalidOperationException("Dogfood union missing-case selection returned an invalid source index.");

            result.Add(cases[sourceIndex].Name);
        }

        return result;
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<ParserTokenCompactionIndicesInto>(
                    programType,
                    "ParserTokenCompactionIndicesInto"),
                CreateDelegate<ParserTokenCompactionIndicesCountedInto>(
                    programType,
                    "ParserTokenCompactionIndicesCountedInto"),
                CreateDelegate<FormatterImportOrderIndicesInto>(
                    programType,
                    "FormatterImportOrderIndicesInto"),
                CreateDelegate<FirstDistinctRankIndicesInto>(
                    programType,
                    "FirstDistinctRankIndicesInto"),
                CreateDelegate<DeclaredTypeUniqueSuffixValueRank>(
                    programType,
                    "DeclaredTypeUniqueSuffixValueRank"),
                CreateDelegate<DeclaredTypeNameCandidateIndex>(
                    programType,
                    "DeclaredTypeNameCandidateIndex"),
                CreateDelegate<TypeCreationOrderIndicesInto>(
                    programType,
                    "TypeCreationOrderIndicesInto"),
                CreateDelegate<ReferenceFileSummaryRanksInto>(
                    programType,
                    "ReferenceFileSummaryRanksInto"),
                CreateDelegate<ProjectSourceFilterKeptIndicesInto>(
                    programType,
                    "ProjectSourceFilterKeptIndicesInto"),
                CreateDelegate<AnonymousUnionDeclaresPublicShim>(
                    programType,
                    "AnonymousUnionDeclaresPublicShim"),
                CreateDelegate<AnalyzerMissingMemberIndicesInto>(
                    programType,
                    "AnalyzerMissingMemberIndicesInto"),
                CreateDelegate<AnalyzerUnionMissingCaseIndicesInto>(
                    programType,
                    "AnalyzerUnionMissingCaseIndicesInto"),
                CreateDelegate<OverloadSelectBestCandidate>(
                    programType,
                    "OverloadSelectBestCandidate"),
                CreateDelegate<TokenizeMetadataWithIndentationInto>(
                    programType,
                    "TokenizeMetadataWithIndentationInto"),
                CreateDelegate<TopLevelDeclarationKindsInto>(
                    programType,
                    "TopLevelDeclarationKindsInto"),
                CreateDelegate<TopLevelContextualTestDeclarationExistsInto>(
                    programType,
                    "TopLevelContextualTestDeclarationExistsInto"),
                CreateDelegate<TopLevelDeclarationIndicesInto>(
                    programType,
                    "TopLevelDeclarationIndicesInto"),
                CreateDelegate<TopLevelFunctionPreamblesAreValidInto>(
                    programType,
                    "TopLevelFunctionPreamblesAreValidInto"),
                CreateDelegate<TokenIndexByKindStartInto>(
                    programType,
                    "TokenIndexByKindStartInto"),
                CreateDelegate<ParsePropertyAccessorTypeInfoInto>(
                    programType,
                    "ParsePropertyAccessorTypeInfoInto"),
                CreateDelegate<TopLevelDeclarationModifiersInto>(
                    programType,
                    "TopLevelDeclarationModifiersInto"),
                CreateDelegate<TopLevelDeclarationNameSpansInto>(
                    programType,
                    "TopLevelDeclarationNameSpansInto"),
                CreateDelegate<NamespaceImportSpansInto>(
                    programType,
                    "NamespaceImportSpansInto"),
                CreateDelegate<PackageNameSpanInto>(
                    programType,
                    "PackageNameSpanInto"),
                CreateDelegate<ParseFunctionSignatureTextInfoInto>(
                    programType,
                    "ParseFunctionSignatureTextInfoInto"),
                CreateDelegate<TypeReferenceCanonicalTextInto>(
                    programType,
                    "TypeReferenceCanonicalTextInto"),
                CreateDelegate<TypeReferenceTupleElementNamesInto>(
                    programType,
                    "TypeReferenceTupleElementNamesInto"),
                CreateDelegate<FunctionSignatureWhereOwnerIndicesInto>(
                    programType,
                    "FunctionSignatureWhereOwnerIndicesInto"),
                CreateDelegate<ParseStatementNodesInto>(
                    programType,
                    "ParseStatementNodesInto"),
                CreateDelegate<ParseInterfaceDeclarationInfoInto>(
                    programType,
                    "ParseInterfaceDeclarationInfoInto"),
                CreateDelegate<ParseEnumDeclarationTextInfoInto>(
                    programType,
                    "ParseEnumDeclarationTextInfoInto"),
                CreateDelegate<ParseStructDeclarationInfoInto>(
                    programType,
                    "ParseStructDeclarationInfoInto"),
                CreateDelegate<ParseUnionDeclarationInfoInto>(
                    programType,
                    "ParseUnionDeclarationInfoInto"),
                CreateDelegate<ParseConstructorTextInfoInto>(
                    programType,
                    "ParseConstructorTextInfoInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int ParserTokenCompactionIndicesInto(int[] tokenKinds, int[] resultIndices);
    private delegate int ParserTokenCompactionIndicesCountedInto(int[] tokenKinds, int tokenCount, int[] resultIndices);
    private delegate int FormatterImportOrderIndicesInto(
        int[] systemFlags,
        int[] nameRanks,
        int nameRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);
    private delegate int FirstDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);
    private delegate int DeclaredTypeUniqueSuffixValueRank(
        string[] keys,
        int[] valueRanks,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int DeclaredTypeNameCandidateIndex(
        string[] names,
        int[] importedNamespaceFlags,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int TypeCreationOrderIndicesInto(
        string[] keys,
        int count,
        int[] dotCounts,
        int[] depthCounts,
        int[] depthOffsets,
        int[] resultIndices);
    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);
    private delegate int ProjectSourceFilterKeptIndicesInto(
        string[] relativePaths,
        string[] excludePatterns,
        int includeTests,
        int[] resultIndices);
    private delegate int AnonymousUnionDeclaresPublicShim(int[] parameterFlags, int count);
    private delegate int OverloadSelectBestCandidate(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed,
        int count);
    private delegate int AnalyzerMissingMemberIndicesInto(int[] coveredFlags, int count, int[] resultIndices);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);
    // Parser front-end kernels (slices 1-23): the N#-native columnar parser, loaded from the dogfood assembly.
    // These feed the columnar symbol/name/type/diagnostic services and the standalone columnar emit backend
    // (TryGetColumnarFunctionInputs -> ColumnarIlEmitter), consuming the columnar node tables directly.
    private delegate int TokenizeMetadataWithIndentationInto(
        string source, int[] kinds, int[] starts, int[] valueLengths, int[] lines, int[] columns);
    private delegate int TopLevelDeclarationKindsInto(int[] tokenKinds, int count, int[] outKinds);
    private delegate int TopLevelContextualTestDeclarationExistsInto(
        string source, int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count);
    private delegate int TopLevelDeclarationIndicesInto(
        int[] tokenKinds, int count, int targetKind, int suppressWhereClause, int[] outIndices);
    private delegate int TopLevelFunctionPreamblesAreValidInto(
        int[] tokenKinds, int count, int[] funcIndices, int funcCount);
    private delegate int TokenIndexByKindStartInto(
        int[] tokenKinds, int[] tokenStarts, int count, int targetKind, int targetStart);
    private delegate int ParsePropertyAccessorTypeInfoInto(
        string source, int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths,
        int count, int propIndex, string[] outNameTexts, string[] outTypeTexts, int[] outResult);
    private delegate int TopLevelDeclarationModifiersInto(int[] tokenKinds, int count, int[] outKinds, int[] outModifiers);
    private delegate int TopLevelDeclarationNameSpansInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
        int[] outKinds, int[] outNameStarts, int[] outNameLengths);
    private delegate int NamespaceImportSpansInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
        int[] outNsStarts, int[] outNsLengths, int[] outAliasStarts, int[] outAliasLengths);
    private delegate int PackageNameSpanInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int[] outResult);
    private delegate int ParseFunctionSignatureTextInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int funcIndex,
        int[] outNodeKinds, int[] outNameStarts, int[] outNameLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths,
        int[] outParamNameStarts, int[] outParamNameLengths, string[] outParamNameTexts, int[] outParamTypeRoots,
        int[] outTypeParamStarts, int[] outTypeParamLengths, string[] outTypeParamTexts,
        int[] outWhereNameStarts, int[] outWhereNameLengths, string[] outWhereNameTexts,
        int[] outWhereItemCodes, string[] outFunctionNameTexts, int[] outResult);
    private delegate string TypeReferenceCanonicalTextInto(
        string source,
        int[] nodeKinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount,
        int[] childIndices, int root);
    private delegate int TypeReferenceTupleElementNamesInto(
        string source,
        int[] nodeKinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount,
        int[] childIndices, int root, string[] outNames);
    private delegate int FunctionSignatureWhereOwnerIndicesInto(
        string source,
        int[] typeParamStarts, int[] typeParamLengths, int typeParamCount,
        int[] whereNameStarts, int[] whereNameLengths, int whereItemCount, int[] outOwnerIndices);
    private delegate int ParseStatementNodesInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int start,
        int[] outNodeKinds, int[] outValueStarts, int[] outValueLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths, int[] outResult);
    private delegate int ParseInterfaceDeclarationInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int interfaceIndex,
        int[] outMethodFuncIndices, int[] outBaseNameStarts, int[] outBaseNameLengths,
        string[] outBaseNameTexts, string[] outInterfaceNameTexts, int[] outResult);
    private delegate int ParseEnumDeclarationTextInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int enumIndex,
        int[] outNameStarts, int[] outNameLengths, string[] outNameTexts,
        int[] outValueStarts, int[] outValueLengths, int[] outHasValue, int[] outMemberValues,
        string[] outEnumNameTexts, int[] outResult);
    private delegate int ParseStructDeclarationInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int structIndex,
        int[] outFieldNameStarts, int[] outFieldNameLengths, string[] outFieldNameTexts,
        int[] outFieldTypeStarts, int[] outFieldTypeLengths,
        string[] outFieldTypeTexts, int[] outFieldStaticFlags, int[] outFieldInitKinds, int[] outFieldInitStarts, int[] outFieldInitLengths, string[] outFieldInitTexts,
        int[] outMethodFuncIndices, int[] outMethodStaticFlags, int[] outCtorIndices, int[] outPropIndices, int[] outPropStaticFlags,
        int[] outTypeParamStarts, int[] outTypeParamLengths, string[] outTypeParamTexts,
        int[] outBaseNameStarts, int[] outBaseNameLengths, string[] outBaseNameTexts,
        string[] outStructNameTexts, int[] outResult);
    private delegate int ParseUnionDeclarationInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int unionIndex,
        int[] outCaseNameStarts, int[] outCaseNameLengths, string[] outCaseNameTexts, int[] outCaseFieldCounts,
        int[] outFieldNameStarts, int[] outFieldNameLengths, string[] outFieldNameTexts,
        int[] outFieldTypeStarts, int[] outFieldTypeLengths,
        string[] outFieldTypeTexts,
        int[] outTypeParamStarts, int[] outTypeParamLengths, string[] outTypeParamTexts,
        string[] outUnionNameTexts, int[] outResult);
    private delegate int ParseConstructorTextInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int ctorIndex,
        int[] outArgKinds, int[] outArgStarts, int[] outArgLengths, string[] outArgTexts, int[] outResult);

    private sealed record Bindings(
        ParserTokenCompactionIndicesInto ParserTokenCompaction,
        ParserTokenCompactionIndicesCountedInto ParserTokenCompactionCounted,
        FormatterImportOrderIndicesInto FormatterImportOrderIndices,
        FirstDistinctRankIndicesInto FirstDistinctRankIndices,
        DeclaredTypeUniqueSuffixValueRank DeclaredTypeUniqueSuffixValueRank,
        DeclaredTypeNameCandidateIndex DeclaredTypeNameCandidateIndex,
        TypeCreationOrderIndicesInto TypeCreationOrderIndices,
        ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks,
        ProjectSourceFilterKeptIndicesInto ProjectSourceFilterKeptIndices,
        AnonymousUnionDeclaresPublicShim AnonymousUnionDeclaresPublicShim,
        AnalyzerMissingMemberIndicesInto AnalyzerMissingMemberIndices,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices,
        OverloadSelectBestCandidate OverloadSelectBestCandidate,
        TokenizeMetadataWithIndentationInto TokenizeMetadataWithIndentation,
        TopLevelDeclarationKindsInto TopLevelDeclarationKinds,
        TopLevelContextualTestDeclarationExistsInto TopLevelContextualTestDeclarationExists,
        TopLevelDeclarationIndicesInto TopLevelDeclarationIndices,
        TopLevelFunctionPreamblesAreValidInto TopLevelFunctionPreamblesAreValid,
        TokenIndexByKindStartInto TokenIndexByKindStart,
        ParsePropertyAccessorTypeInfoInto ParsePropertyAccessorTypeInfo,
        TopLevelDeclarationModifiersInto TopLevelDeclarationModifiers,
        TopLevelDeclarationNameSpansInto TopLevelDeclarationNameSpans,
        NamespaceImportSpansInto NamespaceImportSpans,
        PackageNameSpanInto PackageNameSpan,
        ParseFunctionSignatureTextInfoInto ParseFunctionSignatureTextInfo,
        TypeReferenceCanonicalTextInto TypeReferenceCanonicalText,
        TypeReferenceTupleElementNamesInto TypeReferenceTupleElementNames,
        FunctionSignatureWhereOwnerIndicesInto FunctionSignatureWhereOwnerIndices,
        ParseStatementNodesInto ParseStatementNodes,
        ParseInterfaceDeclarationInfoInto ParseInterfaceDeclarationInfo,
        ParseEnumDeclarationTextInfoInto ParseEnumDeclarationTextInfo,
        ParseStructDeclarationInfoInto ParseStructDeclarationInfo,
        ParseUnionDeclarationInfoInto ParseUnionDeclarationInfo,
        ParseConstructorTextInfoInto ParseConstructorTextInfo);

    private sealed class ParserTokenCompactionScratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] TokenKinds = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (TokenKinds.Length != count)
            {
                TokenKinds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class FormatterImportOrderingScratch
    {
        // Distinct namespace strings keyed ordinally (so distinct strings stay distinct
        // entries), each mapped to a rank that reflects Comparer<string>.Default ordering.
        // Namespaces that compare EQUAL under that comparer share a rank, exactly mirroring
        // LINQ ThenBy(i => i.Namespace), whose ties are broken by original input order.
        private readonly Dictionary<string, int> _namespaceRanks = new(StringComparer.Ordinal);

        internal int[] BucketCounts = Array.Empty<int>();
        internal int[] BucketOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SystemFlags = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueNamespaces = Array.Empty<string>();
        internal int UniqueNamespaceCount;

        internal void EnsureCapacity(int count)
        {
            // Size the per-item arrays exactly to the logical import count: the kernel
            // derives its working count from systemFlags.Length, so these arrays must not
            // retain extra (stale) tail slots from a larger prior call on this thread.
            if (SystemFlags.Length != count)
            {
                SystemFlags = new int[count];
                NameRanks = new int[count];
                TempIndices = new int[count];
                ResultIndices = new int[count];
                UniqueNamespaces = new string[count];
            }

            // The name-pass counting sort uses ranks 1..uniqueRankCount; capacity must
            // cover the worst case where every namespace is distinct (uniqueRankCount == count).
            var bucketCapacity = count + 1;
            if (BucketCounts.Length != bucketCapacity)
            {
                BucketCounts = new int[bucketCapacity];
                BucketOffsets = new int[bucketCapacity];
            }
        }

        internal void AddNamespace(string ns)
        {
            if (_namespaceRanks.ContainsKey(ns))
                return;

            _namespaceRanks.Add(ns, 0);
            UniqueNamespaces[UniqueNamespaceCount] = ns;
            UniqueNamespaceCount++;
        }

        internal void BuildRanks()
        {
            Array.Sort(UniqueNamespaces, 0, UniqueNamespaceCount, Comparer<string>.Default);

            // Assign 1-based ranks; consecutive entries that compare equal under the
            // sort comparer share a rank so the kernel treats them as a stable tie.
            var rank = 0;
            for (var i = 0; i < UniqueNamespaceCount; i++)
            {
                if (i == 0 || Comparer<string>.Default.Compare(UniqueNamespaces[i], UniqueNamespaces[i - 1]) != 0)
                {
                    rank++;
                }

                _namespaceRanks[UniqueNamespaces[i]] = rank;
            }
        }

        internal int GetRank(string ns) => _namespaceRanks[ns];

        internal void ResetRanks()
        {
            _namespaceRanks.Clear();
            if (UniqueNamespaceCount > 0)
            {
                Array.Clear(UniqueNamespaces, 0, UniqueNamespaceCount);
                UniqueNamespaceCount = 0;
            }
        }
    }

    private sealed class ProjectSourceFilterScratch
    {
        internal string[] RelativePaths = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            // The kernel iterates relativePaths.Length, so this buffer must be sized exactly.
            if (RelativePaths.Length != count)
            {
                RelativePaths = new string[count];
                ResultIndices = new int[count];
            }
        }

        internal void ClearRelativePaths(int count) => Array.Clear(RelativePaths, 0, count);
    }

    private sealed class AnonymousUnionShimScratch
    {
        internal int[] ParameterFlags = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ParameterFlags.Length < count)
            {
                ParameterFlags = new int[count];
            }
        }
    }

    private sealed class OverloadCandidateScratch
    {
        internal int[] ValidFlags = Array.Empty<int>();
        internal int[] Scores = Array.Empty<int>();
        internal int[] GenericFlags = Array.Empty<int>();
        internal int[] ParamsFlags = Array.Empty<int>();
        internal int[] DefaultsUsed = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ValidFlags.Length < count)
            {
                ValidFlags = new int[count];
                Scores = new int[count];
                GenericFlags = new int[count];
                ParamsFlags = new int[count];
                DefaultsUsed = new int[count];
            }
        }
    }

    private sealed class MissingEnumMemberScratch
    {
        private readonly HashSet<string> _seenNames = new(StringComparer.Ordinal);

        internal int[] CoveredFlags = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal bool AddName(string name) => _seenNames.Add(name);

        internal void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }

        internal void ResetNames()
        {
            _seenNames.Clear();
        }
    }

    private sealed class MissingUnionCaseScratch
    {
        internal int[] MissingIndices = Array.Empty<int>();
        internal int[] NeverCoveredIndices = Array.Empty<int>();
        internal int[] PartialMissingIndices = Array.Empty<int>();
        internal int[] ResultCounts = new int[3];

        internal void EnsureCapacity(int count)
        {
            if (MissingIndices.Length < count)
            {
                MissingIndices = new int[count];
                NeverCoveredIndices = new int[count];
                PartialMissingIndices = new int[count];
            }

            if (ResultCounts.Length != 3)
            {
                ResultCounts = new int[3];
            }
        }
    }

    private sealed class FirstDistinctTypeKeyScratch
    {
        private readonly Dictionary<string, int> _keyRanks = new(StringComparer.Ordinal);

        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int[] TypeRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
        {
            if (TypeRanks.Length != count)
            {
                TypeRanks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class FirstDistinctStringScratch(IEqualityComparer<string> comparer)
    {
        private readonly Dictionary<string, int> _keyRanks = new(comparer);

        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class DistinctOrderedStringScratch
    {
        private readonly Dictionary<string, int> _valueRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal string[] UniqueValues = Array.Empty<string>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal string[] Values = Array.Empty<string>();
        internal int UniqueValueCount;

        internal void EnsureCapacity(int count)
        {
            if (ValueRanks.Length != count)
            {
                ValueRanks = new int[count];
                Values = new string[count];
                ResultRanks = new int[count];
                UniqueValues = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        internal void AddValue(string value)
        {
            if (_valueRanks.ContainsKey(value))
                return;

            _valueRanks.Add(value, 0);
            UniqueValues[UniqueValueCount] = value;
            UniqueValueCount++;
        }

        internal void BuildRanks()
        {
            Array.Sort(UniqueValues, 0, UniqueValueCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueValueCount; i++)
            {
                _valueRanks[UniqueValues[i]] = i + 1;
            }
        }

        internal int GetRank(string value) => _valueRanks[value];

        internal void ClearValues(int count) => Array.Clear(Values, 0, count);

        internal void ResetValues()
        {
            _valueRanks.Clear();
            if (UniqueValueCount > 0)
            {
                Array.Clear(UniqueValues, 0, UniqueValueCount);
                UniqueValueCount = 0;
            }
        }
    }

    private sealed class DeclaredTypeSuffixLookupScratch
    {
        private readonly Dictionary<Type, int> _valueRanks = new();
        private object? _source;
        private int _sourceCount;
        private int _tailHashWidth = -1;

        internal int Count;
        internal string[] Keys = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IReadOnlyDictionary<string, TType> types)
            where TType : Type
        {
            var count = types.Count;
            if (ReferenceEquals(_source, types) && _sourceCount == count && !CachedValuesContainUnbakedBuilder())
                return true;

            EnsureCapacity(count);
            _valueRanks.Clear();

            var index = 0;
            var uniqueValueCount = 0;
            foreach (var entry in types)
            {
                var value = entry.Value;
                if (value == null)
                    return false;

                if (!_valueRanks.TryGetValue(value, out var rank))
                {
                    rank = ++uniqueValueCount;
                    _valueRanks.Add(value, rank);
                    Values[rank] = value;
                }

                Keys[index] = entry.Key;
                ValueRanks[index] = rank;
                index++;
            }

            Count = count;
            _source = types;
            _sourceCount = count;
            _tailHashWidth = -1;
            return true;
        }

        // A cache hit keyed on (same dictionary instance, same count) is unsafe when the
        // dictionary's VALUES were replaced in place since we cached — e.g. ILCompiler's
        // FinalizeTopLevelEnumTypes swaps each EnumBuilder value for its baked Type while keeping
        // the same keys and count. If any cached value is still an unbaked reflection-emit builder,
        // force a reload so we don't hand back a stale EnumBuilder/TypeBuilder (M9).
        private bool CachedValuesContainUnbakedBuilder()
        {
            foreach (var value in _valueRanks.Keys)
            {
                if (value is System.Reflection.Emit.TypeBuilder or System.Reflection.Emit.EnumBuilder)
                {
                    return true;
                }
            }

            return false;
        }

        internal void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = GetTailHash(Keys[i], width);
            }

            _tailHashWidth = width;
        }

        internal static int GetTailHashWidth(string text) => Math.Min(4, text.Length);

        internal static int GetTailHash(string text, int width)
        {
            var hash = 0;
            for (var offset = 0; offset < width && offset < text.Length; offset++)
            {
                hash = hash * 31 + text[text.Length - 1 - offset];
            }

            return hash;
        }

        private void EnsureCapacity(int count)
        {
            if (Keys.Length < count)
            {
                Keys = new string[count];
                ValueRanks = new int[count];
                TailHashes = new int[count];
            }

            var valueCapacity = count + 1;
            if (Values.Length < valueCapacity)
            {
                Values = new Type[valueCapacity];
            }
        }
    }

    private sealed class DeclaredTypeNameCandidateScratch
    {
        private readonly HashSet<string> _importedNamespaces = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _nameIndices = new(StringComparer.Ordinal);
        private CompilationUnit? _source;
        private int _sourceDeclarationCount;
        private int _sourceImportCount;
        private int _tailHashWidth = -1;

        internal int Count;
        internal int[] ImportedNamespaceFlags = Array.Empty<int>();
        internal string[] Names = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();

        internal void Load(CompilationUnit compilationUnit)
        {
            var declarationCount = compilationUnit.Declarations.Count;
            var importCount = compilationUnit.Imports.Count;
            if (ReferenceEquals(_source, compilationUnit)
                && _sourceDeclarationCount == declarationCount
                && _sourceImportCount == importCount)
            {
                return;
            }

            Count = 0;
            _tailHashWidth = -1;
            _nameIndices.Clear();
            _importedNamespaces.Clear();

            for (var i = 0; i < importCount; i++)
            {
                var import = compilationUnit.Imports[i];
                if (import.Alias == null)
                {
                    _importedNamespaces.Add(import.Namespace);
                }
            }

            for (var i = 0; i < declarationCount; i++)
            {
                AddDeclaration(compilationUnit.Declarations[i], containingTypeName: null);
            }

            for (var i = 0; i < Count; i++)
            {
                var namespaceName = GetNamespaceFromTypeName(Names[i]);
                ImportedNamespaceFlags[i] = string.IsNullOrEmpty(namespaceName) || _importedNamespaces.Contains(namespaceName)
                    ? 1
                    : 0;
            }

            _source = compilationUnit;
            _sourceDeclarationCount = declarationCount;
            _sourceImportCount = importCount;
        }

        internal void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = DeclaredTypeSuffixLookupScratch.GetTailHash(Names[i], width);
            }

            _tailHashWidth = width;
        }

        private void AddDeclaration(Declaration declaration, string? containingTypeName)
        {
            var name = GetDeclaredTypeName(declaration);
            if (string.IsNullOrWhiteSpace(name))
                return;

            var typeName = containingTypeName == null ? name : $"{containingTypeName}.{name}";
            if (!_nameIndices.ContainsKey(typeName))
            {
                EnsureCapacity(Count + 1);
                _nameIndices.Add(typeName, Count);
                Names[Count] = typeName;
                Count++;
            }

            AddNestedTypeDeclarations(declaration, typeName);
        }

        private void AddNestedTypeDeclarations(Declaration declaration, string containingTypeName)
        {
            switch (declaration)
            {
                case ClassDeclaration classDeclaration:
                    AddNestedTypeDeclarations(classDeclaration.Members, containingTypeName);
                    break;
                case StructDeclaration structDeclaration:
                    AddNestedTypeDeclarations(structDeclaration.Members, containingTypeName);
                    break;
                case RecordDeclaration recordDeclaration:
                    AddNestedTypeDeclarations(recordDeclaration.Members, containingTypeName);
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    AddNestedTypeDeclarations(interfaceDeclaration.Members, containingTypeName);
                    break;
            }
        }

        private void AddNestedTypeDeclarations(List<Declaration> members, string containingTypeName)
        {
            for (var i = 0; i < members.Count; i++)
            {
                var member = members[i];
                if (IsTypeDeclaration(member))
                {
                    AddDeclaration(member, containingTypeName);
                }
            }
        }

        private static string? GetDeclaredTypeName(Declaration declaration)
        {
            return declaration switch
            {
                ClassDeclaration classDeclaration => classDeclaration.Name,
                StructDeclaration structDeclaration => structDeclaration.Name,
                RecordDeclaration recordDeclaration => recordDeclaration.Name,
                SoaRecordDeclaration soaRecordDeclaration => soaRecordDeclaration.Name,
                InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Name,
                EnumDeclaration enumDeclaration => enumDeclaration.Name,
                UnionDeclaration unionDeclaration => unionDeclaration.Name,
                NewtypeDeclaration newtypeDeclaration => newtypeDeclaration.Name,
                _ => null
            };
        }

        private static bool IsTypeDeclaration(Declaration declaration)
        {
            return declaration is ClassDeclaration
                or StructDeclaration
                or RecordDeclaration
                or SoaRecordDeclaration
                or InterfaceDeclaration
                or EnumDeclaration
                or UnionDeclaration
                or NewtypeDeclaration;
        }

        private static string GetNamespaceFromTypeName(string typeName)
        {
            var separatorIndex = typeName.LastIndexOf('.');
            return separatorIndex >= 0 ? typeName[..separatorIndex] : string.Empty;
        }

        private void EnsureCapacity(int count)
        {
            if (Names.Length >= count)
                return;

            var newCapacity = Names.Length == 0 ? 8 : Names.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Names, newCapacity);
            Array.Resize(ref ImportedNamespaceFlags, newCapacity);
            Array.Resize(ref TailHashes, newCapacity);
        }
    }

    private sealed class TypeCreationOrderScratch
    {
        internal int Count;
        internal int[] DepthCounts = Array.Empty<int>();
        internal int[] DepthOffsets = Array.Empty<int>();
        internal int[] DotCounts = Array.Empty<int>();
        internal string[] Keys = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IEnumerable<TType> types, Func<TType, string> getTypeKey)
            where TType : Type
        {
            Count = 0;
            var maxKeyLength = 0;
            foreach (var type in types)
            {
                if (type == null)
                    return false;

                var key = getTypeKey(type);
                if (key == null)
                    return false;

                EnsureTypeCapacity(Count + 1);
                Values[Count] = type;
                Keys[Count] = key;
                if (key.Length > maxKeyLength)
                {
                    maxKeyLength = key.Length;
                }

                Count++;
            }

            EnsureDepthCapacity(maxKeyLength + 1);
            return true;
        }

        internal void ClearValues()
        {
            for (var i = 0; i < Count; i++)
            {
                Values[i] = null!;
                Keys[i] = null!;
            }

            Count = 0;
        }

        private void EnsureTypeCapacity(int count)
        {
            if (Values.Length >= count)
                return;

            var newCapacity = Values.Length == 0 ? 8 : Values.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Values, newCapacity);
            Array.Resize(ref Keys, newCapacity);
            Array.Resize(ref DotCounts, newCapacity);
            Array.Resize(ref ResultIndices, newCapacity);
        }

        private void EnsureDepthCapacity(int count)
        {
            if (DepthCounts.Length >= count)
                return;

            var newCapacity = DepthCounts.Length == 0 ? 8 : DepthCounts.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref DepthCounts, newCapacity);
            Array.Resize(ref DepthOffsets, newCapacity);
        }
    }
}
