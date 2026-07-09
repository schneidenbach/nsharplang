using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.Columnar;

internal static class ColumnarProgramInputBuilder
{
    private static bool Decline(string siteId, string message, int spanStart = -1, int spanLength = 0, string memberName = "")
    {
        ColumnarDeclineTrace.Record(siteId, message, spanStart, spanLength, memberName);
        return false;
    }

    private static bool DeclineAtToken(
        string siteId,
        string message,
        int[] tokenStarts,
        int[] tokenValueLengths,
        int tokenIndex,
        string memberName = "")
    {
        if (tokenIndex >= 0 && tokenIndex < tokenStarts.Length)
        {
            return Decline(siteId, message, tokenStarts[tokenIndex], tokenValueLengths[tokenIndex], memberName);
        }

        return Decline(siteId, message, memberName: memberName);
    }

    // Body node tables are parsed into worst-case scratch arrays sized by the file's token count,
    // but the program retains them for the whole compile. Copy down to the actual node count
    // (keeping the kernel's count+1 sentinel row) so retained memory tracks tree size, not file size.
    private static ColumnarNodeTable BuildTrimmedNodeTable(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStarts, int[] childCounts, int[] childIndices,
        int[] spanStarts, int[] spanLengths, int nodeCount)
    {
        var rowCount = Math.Min(nodeCount + 1, kinds.Length);
        var childLimit = 0;
        for (var i = 0; i < nodeCount; i++)
        {
            var childEnd = childStarts[i] + childCounts[i];
            if (childEnd > childLimit)
                childLimit = childEnd;
        }
        childLimit = Math.Clamp(childLimit, 0, childIndices.Length);
        return new ColumnarNodeTable(
            kinds[..rowCount], valueStarts[..rowCount], valueLengths[..rowCount],
            childStarts[..rowCount], childCounts[..rowCount], childIndices[..childLimit],
            spanStarts[..rowCount], spanLengths[..rowCount]);
    }

    internal static bool TryBuild(string source, out ColumnarProgramInput program)
    {
        program = null!;
        if (!TryTokenizeColumnarSource(source, out var tokens))
        {
            return Decline("parse.tokenize", "columnar tokenization failed");
        }

        var n = tokens.Count;
        var funcIndices = new int[n + 1];
        var funcAsyncFlags = new int[n + 1];
        var enumIndices = new int[n + 1];
        var unionIndices = new int[n + 1];
        var interfaceIndices = new int[n + 1];
        var structIndices = new int[n + 1];
        var structReferenceFlags = new int[n + 1];
        var structRecordFlags = new int[n + 1];
        var declarationResult = new int[6];
        var declarationRowCount = global::Program.TopLevelColumnarProgramDeclarationIndicesInto(
            source,
            tokens.RawKinds,
            tokens.RawStarts,
            tokens.RawValueLengths,
            tokens.RawCount,
            tokens.Kinds,
            n,
            funcIndices,
            funcAsyncFlags,
            enumIndices,
            unionIndices,
            interfaceIndices,
            structIndices,
            structReferenceFlags,
            structRecordFlags,
            declarationResult);
        if (declarationRowCount < 0)
        {
            var scanStage = declarationRowCount switch
            {
                -2 => "function scan",
                -3 => "declaration name spans mismatched the declaration count",
                -4 => "duplicate top-level type names",
                -5 => "nominal (enum/union/interface) scan",
                -6 => "struct-like scan",
                _ => "declaration scan",
            };
            return DeclineAtToken(
                "parse.declaration-scan",
                "top-level declaration scan failed at " + scanStage + "; the source may contain an unmodeled declaration shape such as setup or teardown",
                tokens.Starts,
                tokens.ValueLengths,
                0);
        }

        if (!TryGetColumnarFunctionInputs(source, tokens, funcIndices, funcAsyncFlags, declarationResult[1], out var inputs))
        {
            return Decline("parse.function", "function declaration materialization failed");
        }
        if (!TryGetColumnarEnumInputs(source, tokens, enumIndices, declarationResult[2], out var enums))
        {
            return Decline("parse.enum", "enum declaration materialization failed");
        }
        if (!TryGetColumnarStructInputs(source, tokens, structIndices, structReferenceFlags, structRecordFlags, declarationResult[5], out var structs))
        {
            return Decline("parse.struct", "struct/class/record declaration materialization failed");
        }
        if (!TryGetColumnarUnionInputs(source, tokens, unionIndices, declarationResult[3], out var unions))
        {
            return Decline("parse.union", "union declaration materialization failed");
        }
        if (!TryGetColumnarInterfaceInputs(source, tokens, interfaceIndices, declarationResult[4], out var interfaceInputs))
        {
            return Decline("parse.interface", "interface declaration materialization failed");
        }

        if (!TryGetColumnarTestInputs(source, tokens, out var testInputs))
        {
            return Decline("parse.test", "test declaration materialization failed");
        }

        if (!TryGetColumnarNewtypeInputs(source, tokens, structs))
        {
            return Decline("parse.newtype", "newtype declaration materialization failed");
        }

        program = ColumnarProgramInput.CreateSingleSource(source, inputs, enums, structs, unions, interfaceInputs, testInputs);
        return true;
    }

    internal static bool TryBuildMultiFile(
        IReadOnlyList<string> sources,
        IReadOnlyList<string> fileNames,
        out ColumnarProgramInput program)
    {
        program = null!;
        var sourceFiles = ColumnarEmissionPlanner.BuildSourceFilesFromLists(sources, fileNames);
        var programs = new ColumnarProgramInput[sources.Count];
        for (var i = 0; i < sources.Count; i++)
        {
            var sourceFileId = sourceFiles[i].FileId;
            ColumnarDeclineTrace.SetSourceFileId(sourceFileId);
            try
            {
                if (!TryBuild(sources[i], out var fileProgram))
                    return false;
                ColumnarProgramInput.AssignSourceFileId(fileProgram, sourceFileId);
                programs[i] = fileProgram;
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
        }

        program = ColumnarProgramInput.MergeSourceFiles(sourceFiles, programs);
        return true;
    }

    // A NEWTYPE (`type X = newtype T`) is the legacy emitter's CreateSyntheticNewtypeRecord: a
    // readonly record STRUCT with one primary-constructor parameter `Value: T` — synthesized here
    // as a struct input so declaration, construction, equality, and `.Value` reads ride the
    // record-struct machinery. Call-style construction (`X(42)`) is gated on IsNewtype downstream.
    private static bool TryGetColumnarNewtypeInputs(
        string source, ColumnarTokenizedSource tokens, List<ColumnarStructInput> structs)
    {
        var n = tokens.Count;
        var indices = new int[n + 1];
        var nameStarts = new int[n + 1];
        var nameLengths = new int[n + 1];
        var typeStarts = new int[n + 1];
        var typeLengths = new int[n + 1];
        var scan = new int[1];
        var newtypeCount = global::Program.TopLevelColumnarNewtypeDeclarationIndicesInto(
            source, tokens.Kinds, tokens.Starts, tokens.ValueLengths, n,
            indices, nameStarts, nameLengths, typeStarts, typeLengths, scan);
        if (newtypeCount < 0)
            return Decline("parse.newtype-scan", "newtype declaration scan failed (composed underlying types are not modeled)");

        for (var t = 0; t < newtypeCount; t++)
        {
            var name = source.Substring(nameStarts[t], nameLengths[t]);
            var underlying = source.Substring(typeStarts[t], typeLengths[t]);
            var emptyBlock = new ColumnarNodeTable(
                new[] { 25 }, new[] { -1 }, new[] { 0 },
                new[] { 0 }, new[] { 0 }, Array.Empty<int>(),
                new[] { 0 }, new[] { 0 });
            var ctorBody = new ColumnarFunctionInput(
                "constructor", "void", new[] { "Value" }, new[] { underlying },
                emptyBlock, 0);
            var ctor = new ColumnarConstructorInput(
                ctorBody, 0, Array.Empty<int>(), Array.Empty<string>(),
                new[] { -1 }, new[] { "" }, isSynthesizedInitializer: true);
            structs.Add(new ColumnarStructInput(
                name,
                new[] { "Value" }, new[] { underlying },
                Array.Empty<ColumnarFunctionInput>(),
                new[] { ctor },
                Array.Empty<ColumnarPropertyInput>(),
                isReference: false,
                fieldReadonlyFlags: new[] { true },
                isRecord: true,
                isNewtype: true));
        }
        return true;
    }

    private static bool TryGetColumnarTestInputs(
        string source, ColumnarTokenizedSource tokens, out List<ColumnarTestInput>? tests)
    {
        tests = null;
        var ck = tokens.Kinds;
        var cs = tokens.Starts;
        var cv = tokens.ValueLengths;
        var n = tokens.Count;

        var testIndices = new int[n + 1];
        var testScan = new int[1];
        var testCount = global::Program.TopLevelColumnarTestDeclarationIndicesInto(
            source, ck, cs, cv, n, testIndices, testScan);
        if (testCount < 0)
            return Decline("parse.test-scan", "test declaration scan failed");

        for (var t = 0; t < testCount; t++)
        {
            if (!TryParseColumnarTestAt(ck, cs, cv, n, testIndices[t], source, out var testInput))
                return DeclineAtToken("parse.test", "test declaration could not be parsed into columnar input", cs, cv, testIndices[t]);
            (tests ??= []).Add(testInput);
        }
        return true;
    }

    private static bool TryParseColumnarTestAt(
        int[] ck, int[] cs, int[] cv, int n, int testIndex, string source,
        out ColumnarTestInput input)
    {
        input = null!;
        var cap = n + 1;
        var bk = new int[cap];
        var bvs = new int[cap];
        var bvl = new int[cap];
        var bcs = new int[cap];
        var bcc = new int[cap];
        var bci = new int[cap];
        var bss = new int[cap];
        var bsl = new int[cap];
        var result = new int[4];
        var bodyNodeCount = global::Program.ParseColumnarTestInfoInto(
            source, ck, cs, cv, n, testIndex, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, result);
        if (bodyNodeCount <= 0)
            return false;

        var bodyRoot = result[2];
        if (bodyRoot < 0 || bodyRoot >= bodyNodeCount || result[0] < 0 || result[1] <= 0 || result[0] + result[1] > source.Length)
            return false;

        var description = NSharpLang.Compiler.StringLiteralDecoder.Decode(source.Substring(result[0], result[1]));
        var bodyNodes = BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount);
        var body = new ColumnarFunctionInput(
            "test " + description, "void", Array.Empty<string>(), Array.Empty<string>(),
            bodyNodes, bodyRoot);
        input = new ColumnarTestInput(description, body);
        return true;
    }

    private static bool TryTokenizeColumnarSource(string source, out ColumnarTokenizedSource tokens)
    {
        tokens = null!;
        {
            var capacity = 3 * (source.Length + 1) + 8;
            var rawKinds = new int[capacity];
            var rawStarts = new int[capacity];
            var rawValueLengths = new int[capacity];
            var kinds = new int[capacity];
            var starts = new int[capacity];
            var valueLengths = new int[capacity];
            var resultCounts = new int[2];
            var count = global::Program.TokenizeColumnarSourceInto(
                source,
                rawKinds,
                rawStarts,
                rawValueLengths,
                kinds,
                starts,
                valueLengths,
                resultCounts);
            var rawCount = resultCounts[0];
            if (rawCount < 0 || rawCount > capacity || count < 0 || count > rawCount || count != resultCounts[1])
                return Decline("parse.tokenize.invalid-result", "columnar tokenizer returned invalid token counts");

            tokens = new ColumnarTokenizedSource(
                rawKinds, rawStarts, rawValueLengths, rawCount,
                kinds, starts, valueLengths, count);
            return true;
        }
    }

    private static bool TryGetColumnarFunctionInputs(
        string source, ColumnarTokenizedSource tokens, int[] funcIndices, int[] funcAsyncFlags, int funcIndexCount,
        out List<ColumnarFunctionInput> inputs)
    {
        inputs = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            for (var fi = 0; fi < funcIndexCount; fi++)
            {
                if (!TryParseColumnarFunctionAt(ck, cs, cv, n, funcIndices[fi], source, out var input, isAsync: funcAsyncFlags[fi] == 1))
                    return DeclineAtToken("parse.function", "function declaration could not be parsed into columnar input", cs, cv, funcIndices[fi]);
                inputs.Add(input);
            }
            return true;
        }
    }

    private static bool TryGetColumnarEnumInputs(
        string source, ColumnarTokenizedSource tokens, int[] enumIndices, int enumIndexCount,
        out List<ColumnarEnumInput> enums)
    {
        enums = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            for (var enumSlot = 0; enumSlot < enumIndexCount; enumSlot++)
            {
                var enumIndex = enumIndices[enumSlot];
                var cap = n + 1;
                var outNameTexts = new string[cap];
                var outMemberValues = new int[cap];
                var outMemberStringValues = new string[cap];
                var outEnumNameTexts = new string[1];
                var outResult = new int[3];
                var memberCount = global::Program.ParseColumnarEnumInfoInto(
                    source, ck, cs, cv, n, enumIndex, outNameTexts, outMemberValues, outMemberStringValues, outEnumNameTexts, outResult);
                if (memberCount < 0 || outResult[1] <= 0)
                {
                    return DeclineAtToken("parse.enum", "enum declaration could not be parsed into columnar input", cs, cv, enumIndex);
                }

                var enumName = outEnumNameTexts[0];
                var isStringBacked = outResult[2] == 1;
                var memberNames = new string[memberCount];
                var memberValues = new int[memberCount];
                var memberStringValues = isStringBacked ? new string[memberCount] : Array.Empty<string>();
                for (var m = 0; m < memberCount; m++)
                {
                    var memberName = outNameTexts[m];
                    memberNames[m] = memberName;
                    memberValues[m] = outMemberValues[m];
                    if (isStringBacked)
                    {
                        var rawValue = outMemberStringValues[m];
                        memberStringValues[m] = NSharpLang.Compiler.StringLiteralDecoder.Decode(rawValue ?? memberName);
                    }
                }
                enums.Add(new ColumnarEnumInput(enumName, memberNames, memberValues, isStringBacked, memberStringValues));
            }
            return true;
        }
    }

    private static bool TryGetColumnarStructInputs(
        string source, ColumnarTokenizedSource tokens,
        int[] declIndices, int[] declReferenceFlags, int[] declRecordFlags, int declCount,
        out List<ColumnarStructInput> structs)
    {
        structs = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            if (declCount < 0)
                return Decline("parse.struct.invalid-count", "struct/class/record declaration count was invalid");
            for (var declSlot = 0; declSlot < declCount; declSlot++)
            {
                var structIndex = declIndices[declSlot];
                var isReference = declReferenceFlags[declSlot] == 1;
                var isRecord = declRecordFlags[declSlot] == 1;
                var cap = n + 1;
                var outFieldNameTexts = new string[cap];
                var outFieldTypeTexts = new string[cap];
                var outFieldStaticFlags = new int[cap];
                var outFieldInitKinds = new int[cap];
                var outFieldInitTexts = new string[cap];
                var outMethodFuncIndices = new int[cap];
                var outMethodStaticFlags = new int[cap];
                var outCtorIndices = new int[cap];
                var outPropIndices = new int[cap];
                var outPropStaticFlags = new int[cap];
                var outTypeParamTexts = new string[cap];
                var outBaseNameTexts = new string[cap];
                var outStructNameTexts = new string[1];
                var outResult = new int[10];
                var fieldCount = global::Program.ParseColumnarStructInfoInto(
                    source, ck, cs, cv, n, structIndex, isReference ? 1 : 0, isRecord ? 1 : 0, outFieldNameTexts, outFieldTypeTexts,
                    outFieldStaticFlags, outFieldInitKinds, outFieldInitTexts,
                    outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
                    outTypeParamTexts, outBaseNameTexts, outStructNameTexts, outResult);
                if (fieldCount < 0 || outResult[1] <= 0)
                {
                    return DeclineAtToken("parse.struct", "struct/class/record declaration could not be parsed into columnar input", cs, cv, structIndex);
                }

                var structName = outStructNameTexts[0];

                var baseNameCount = outResult[8];
                var baseNames = new string[baseNameCount];
                for (var b = 0; b < baseNameCount; b++)
                {
                    var baseName = outBaseNameTexts[b];
                    baseNames[b] = baseName;
                }

                var typeParamCount = outResult[7];
                var typeParamNames = new string[typeParamCount];
                for (var tp = 0; tp < typeParamCount; tp++)
                {
                    var typeParamName = outTypeParamTexts[tp];
                    typeParamNames[tp] = typeParamName;
                }

                var fieldNames = new string[fieldCount];
                var fieldTypes = new string[fieldCount];
                var fieldStatics = new bool[fieldCount];
                var fieldReadonlyFlags = new bool[fieldCount];
                var fieldInitKinds = new int[fieldCount];
                var fieldInitTexts = new string[fieldCount];
                for (var f = 0; f < fieldCount; f++)
                {
                    var fieldName = outFieldNameTexts[f];
                    fieldNames[f] = fieldName;
                    var fieldType = outFieldTypeTexts[f];
                    fieldTypes[f] = fieldType;
                    var fieldModifierFlags = outFieldStaticFlags[f];
                    fieldStatics[f] = (fieldModifierFlags & 1) != 0;
                    fieldReadonlyFlags[f] = (fieldModifierFlags & 2) != 0;
                    fieldInitKinds[f] = outFieldInitKinds[f];
                    if (outFieldInitKinds[f] >= 0)
                    {
                        var fieldInitText = outFieldInitTexts[f];
                        fieldInitTexts[f] = fieldInitText;
                    }
                    else
                    {
                        fieldInitTexts[f] = "";
                    }
                }

                var methodCount = outResult[2];
                var methods = new List<ColumnarFunctionInput>(methodCount);
                for (var m = 0; m < methodCount; m++)
                {
                    var methodModifierFlags = outMethodStaticFlags[m];
                    if (!TryParseColumnarFunctionAt(ck, cs, cv, n, outMethodFuncIndices[m], source, out var methodInput, isStatic: (methodModifierFlags & 16) != 0, modifierFlags: methodModifierFlags))
                    {
                        return DeclineAtToken("parse.struct.method", "struct/class/record method could not be parsed into columnar input", cs, cv, outMethodFuncIndices[m], structName);
                    }
                    methods.Add(methodInput);
                }

                var ctorCount = outResult[3];
                var constructors = new List<ColumnarConstructorInput>(ctorCount);
                for (var c = 0; c < ctorCount; c++)
                {
                    if (!TryParseColumnarConstructorAt(ck, cs, cv, n, outCtorIndices[c], source, out var ctorInput))
                    {
                        return DeclineAtToken("parse.struct.constructor", "constructor could not be parsed into columnar input", cs, cv, outCtorIndices[c], structName);
                    }
                    constructors.Add(ctorInput);
                }

                var propCount = outResult[4];
                var properties = new List<ColumnarPropertyInput>(propCount);
                for (var pr = 0; pr < propCount; pr++)
                {
                    if (!TryParseColumnarPropertyAt(ck, cs, cv, n, outPropIndices[pr], source, out var propInput, isStatic: outPropStaticFlags[pr] == 1))
                    {
                        return DeclineAtToken("parse.struct.property", "property could not be parsed into columnar input", cs, cv, outPropIndices[pr], structName);
                    }
                    properties.Add(propInput);
                }

                structs.Add(new ColumnarStructInput(structName, fieldNames, fieldTypes, methods, constructors, properties, isReference, baseNames, fieldStatics, fieldInitKinds, fieldInitTexts, isRecord, typeParamNames, fieldReadonlyFlags));
            }
            return true;
        }
    }

    private static bool TryGetColumnarUnionInputs(
        string source, ColumnarTokenizedSource tokens, int[] unionIndices, int unionIndexCount,
        out List<ColumnarUnionInput> unions)
    {
        unions = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            for (var unionSlot = 0; unionSlot < unionIndexCount; unionSlot++)
            {
                var unionIndex = unionIndices[unionSlot];
                var cap = n + 1;
                var outCaseNameTexts = new string[cap];
                var outCaseFieldCounts = new int[cap];
                var outFieldNameTexts = new string[cap];
                var outFieldTypeTexts = new string[cap];
                var outTypeParamTexts = new string[cap];
                var outUnionNameTexts = new string[1];
                var outResult = new int[4];
                var caseCount = global::Program.ParseColumnarUnionInfoInto(
                    source, ck, cs, cv, n, unionIndex, outCaseNameTexts, outCaseFieldCounts,
                    outFieldNameTexts, outFieldTypeTexts, outTypeParamTexts, outUnionNameTexts, outResult);
                if (caseCount <= 0 || outResult[1] <= 0)
                {
                    return DeclineAtToken("parse.union", "union declaration could not be parsed into columnar input", cs, cv, unionIndex);
                }

                var unionName = outUnionNameTexts[0];

                var typeParamCount = outResult[2];

                // Stage 6 union-ABI ownership: a small, closed, payload-free, non-generic union is the public
                // allocation-free readonly tag struct (UnionValueLayout.IsValueStructEmittable). The
                // columnar emitter now OWNS this layout (ColumnarIlEmitter emits the tag
                // struct directly), so this flag selects the value-struct emit path instead of the class-hierarchy
                // one — preserving the public value-struct ABI on the columnar-routed build. The eligibility
                // decision is owned by N# (ColumnarUnionIsValueStructEmittable in ParserColumnarUnions.nl).
                var isValueStruct = global::Program.ColumnarUnionIsValueStructEmittable(outCaseFieldCounts, caseCount, typeParamCount) == 1;
                string[]? typeParamNames = null;
                if (typeParamCount > 0)
                {
                    typeParamNames = new string[typeParamCount];
                    for (var tp = 0; tp < typeParamCount; tp++)
                    {
                        var typeParamName = outTypeParamTexts[tp];
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
                    caseNames[c] = caseName;
                    var fc = outCaseFieldCounts[c];
                    var names = new string[fc];
                    var types = new string[fc];
                    for (var f = 0; f < fc; f++)
                    {
                        var fieldName = outFieldNameTexts[fieldCursor];
                        names[f] = fieldName;
                        var fieldType = outFieldTypeTexts[fieldCursor];
                        types[f] = fieldType;
                        fieldCursor++;
                    }
                    caseFieldNames[c] = names;
                    caseFieldTypes[c] = types;
                }

                unions.Add(new ColumnarUnionInput(unionName, caseNames, caseFieldNames, caseFieldTypes, typeParamNames, isValueStruct));
            }
            return true;
        }
    }

    private static bool TryParseColumnarFunctionAt(
        int[] ck, int[] cs, int[] cv, int n, int funcIndex, string source,
        out ColumnarFunctionInput input, bool isStatic = false, bool isAsync = false, bool isLocalFunction = false, int modifierFlags = 0)
    {
        input = null!;
        var cap = n + 1;

        var functionNameTexts = new string[1];
        var returnTypeTexts = new string[1];
        var paramNameTexts = new string[cap];
        var paramTypeTexts = new string[cap];
        var paramModifierKinds = new int[cap];
        var paramDefaultKinds = new int[cap];
        var paramDefaultTexts = new string[cap];
        Array.Fill(paramDefaultKinds, -1);
        var paramTupleNameCounts = new int[cap];
        var paramTupleNameTexts = new string[cap];
        var returnTupleNameTexts = new string[cap];
        var typeParamTexts = new string[cap];
        var typeParamSpecials = new int[cap];
        var typeParamConstraintCounts = new int[cap];
        var typeParamConstraintTypeTexts = new string[cap];
        var bk = new int[cap];
        var bvs = new int[cap];
        var bvl = new int[cap];
        var bcs = new int[cap];
        var bcc = new int[cap];
        var bci = new int[cap];
        var bss = new int[cap];
        var bsl = new int[cap];
        var localFunctionNodeIndices = new int[cap];
        var localFunctionTokenIndices = new int[cap];
        var result = new int[9];
        var paramCount = global::Program.ParseColumnarProductFunctionInfoInto(
            source, ck, cs, cv, n, funcIndex, isLocalFunction ? 1 : 0, functionNameTexts, returnTypeTexts,
            paramNameTexts, paramTypeTexts, paramModifierKinds, paramDefaultKinds, paramDefaultTexts,
            paramTupleNameCounts, paramTupleNameTexts, returnTupleNameTexts,
            typeParamTexts, typeParamSpecials, typeParamConstraintCounts, typeParamConstraintTypeTexts,
            bk, bvs, bvl, bcs, bcc, bci, bss, bsl, localFunctionNodeIndices, localFunctionTokenIndices, result);
        if (paramCount < 0)
        {
            return DeclineAtToken("parse.function", "function body or signature could not be parsed into columnar input", cs, cv, funcIndex);
        }

        var functionName = functionNameTexts[0];
        var returnCanonical = returnTypeTexts[0];

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        var parsedParamModifierKinds = new int[paramCount];
        var parsedParamDefaultKinds = new int[paramCount];
        var parsedParamDefaultTexts = new string[paramCount];
        string[]?[]? paramTupleNames = null;
        var flatParamTupleNameIndex = 0;
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = paramNameTexts[p];
            var paramType = paramTypeTexts[p];
            paramNames[p] = paramName;
            paramCanonicals[p] = paramType;
            parsedParamModifierKinds[p] = paramModifierKinds[p];
            parsedParamDefaultKinds[p] = paramDefaultKinds[p];
            parsedParamDefaultTexts[p] = paramDefaultKinds[p] >= 0 ? paramDefaultTexts[p] : "";
            var tupleNameCount = paramTupleNameCounts[p];
            if (tupleNameCount < 0 || flatParamTupleNameIndex + tupleNameCount > paramTupleNameTexts.Length)
                return DeclineAtToken("parse.function.param-tuple-names", "function parameter tuple-name metadata was invalid", cs, cv, funcIndex, functionName);
            if (tupleNameCount > 0)
            {
                var tupleNames = new string[tupleNameCount];
                Array.Copy(paramTupleNameTexts, flatParamTupleNameIndex, tupleNames, 0, tupleNameCount);
                (paramTupleNames ??= new string[paramCount][])[p] = tupleNames;
            }
            flatParamTupleNameIndex += tupleNameCount;
        }

        string[]? returnTupleNames = null;
        var returnTupleNameCount = result[0];
        if (returnTupleNameCount < 0 || returnTupleNameCount > returnTupleNameTexts.Length)
            return DeclineAtToken("parse.function.return-tuple-names", "function return tuple-name metadata was invalid", cs, cv, funcIndex, functionName);
        if (returnTupleNameCount > 0)
        {
            returnTupleNames = new string[returnTupleNameCount];
            Array.Copy(returnTupleNameTexts, returnTupleNames, returnTupleNameCount);
        }

        var bodyBrace = result[1];
        if (bodyBrace < 0 || bodyBrace >= n || (ck[bodyBrace] != 129 && ck[bodyBrace] != 120))
            return DeclineAtToken("parse.function.body", "function body was not materialized as a supported block or expression body", cs, cv, funcIndex, functionName);

        var typeParamNames = Array.Empty<string>();
        var typeParamCount = result[2];
        if (typeParamCount > 0)
        {
            typeParamNames = new string[typeParamCount];
            for (var t = 0; t < typeParamCount; t++)
            {
                var typeParamName = typeParamTexts[t];
                typeParamNames[t] = typeParamName;
            }
        }

        var whereItemCount = result[5];
        int[]? parsedTypeParamSpecials = null;
        string[][]? typeParamTypeConstraints = null;
        if (whereItemCount > 0)
        {
            if (typeParamNames.Length == 0)
                return DeclineAtToken("parse.function.constraints", "function constraints were present without type parameters", cs, cv, funcIndex, functionName);
            parsedTypeParamSpecials = new int[typeParamCount];
            typeParamTypeConstraints = new string[typeParamNames.Length][];
            var flatTypeConstraintIndex = 0;
            for (var t = 0; t < typeParamNames.Length; t++)
            {
                parsedTypeParamSpecials[t] = typeParamSpecials[t];
                var constraintCount = typeParamConstraintCounts[t];
                if (constraintCount < 0 || flatTypeConstraintIndex + constraintCount > typeParamConstraintTypeTexts.Length)
                    return DeclineAtToken("parse.function.constraints", "function constraint metadata was invalid", cs, cv, funcIndex, functionName);
                var constraints = new string[constraintCount];
                for (var c = 0; c < constraintCount; c++)
                {
                    var constraint = typeParamConstraintTypeTexts[flatTypeConstraintIndex + c];
                    constraints[c] = constraint;
                }
                typeParamTypeConstraints[t] = constraints;
                flatTypeConstraintIndex += constraintCount;
            }
        }

        var rootBlock = result[6];
        var bodyNodeCount = result[7];
        if (bodyNodeCount <= 0 || rootBlock < 0 || rootBlock >= bodyNodeCount)
        {
            return DeclineAtToken("parse.function.body-nodes", "function body node table was invalid", cs, cv, funcIndex, functionName);
        }

        var bodyNodes = BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount);
        input = new ColumnarFunctionInput(
            functionName, returnCanonical, paramNames, paramCanonicals,
            bodyNodes, rootBlock, isStatic, typeParamNames,
            parsedTypeParamSpecials, typeParamTypeConstraints,
            returnTupleElementNames: returnTupleNames, paramTupleElementNames: paramTupleNames,
            paramModifierKinds: parsedParamModifierKinds,
            paramDefaultKinds: parsedParamDefaultKinds, paramDefaultTexts: parsedParamDefaultTexts,
            isAsync: isAsync,
            modifierFlags: modifierFlags);

        var localFunctionCount = result[8];
        if (localFunctionCount < 0 || localFunctionCount > localFunctionNodeIndices.Length)
        {
            return DeclineAtToken("parse.function.local-functions", "local-function metadata was invalid", cs, cv, funcIndex, functionName);
        }
        for (var lf = 0; lf < localFunctionCount; lf++)
        {
            if (!TryParseColumnarFunctionAt(ck, cs, cv, n, localFunctionTokenIndices[lf], source, out var localFn, isLocalFunction: true))
            {
                return DeclineAtToken("parse.local-function", "local function could not be parsed into columnar input", cs, cv, localFunctionTokenIndices[lf], functionName);
            }
            (input.LocalFunctions ??= []).Add(new ColumnarLocalFunctionInput(localFunctionNodeIndices[lf], localFn));
        }
        return true;
    }

    private static bool TryParseColumnarConstructorAt(
        int[] ck, int[] cs, int[] cv, int n, int ctorIndex, string source,
        out ColumnarConstructorInput input)
    {
        input = null!;
        var cap = (n + 1) * 4;
        var paramNameTexts = new string[cap];
        var paramTypeTexts = new string[cap];
        var caKinds = new int[cap];
        var caStarts = new int[cap];
        var caLengths = new int[cap];
        var caTexts = new string[cap];
        var bk = new int[cap];
        var bvs = new int[cap];
        var bvl = new int[cap];
        var bcs = new int[cap];
        var bcc = new int[cap];
        var bci = new int[cap];
        var bss = new int[cap];
        var bsl = new int[cap];
        var ctorResult = new int[6];
        var paramCount = global::Program.ParseColumnarConstructorInfoInto(
            source, ck, cs, cv, n, ctorIndex,
            paramNameTexts, paramTypeTexts, caKinds, caStarts, caLengths, caTexts,
            bk, bvs, bvl, bcs, bcc, bci, bss, bsl, ctorResult);
        if (paramCount < 0)
        {
            return DeclineAtToken("parse.constructor", "constructor body or signature could not be parsed into columnar input", cs, cv, ctorIndex, "constructor");
        }

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        var parsedParamDefaultKinds = new int[paramCount];
        var parsedParamDefaultTexts = new string[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = paramNameTexts[p];
            paramNames[p] = paramName;
            var paramCanonical = paramTypeTexts[p];
            paramCanonicals[p] = paramCanonical;
            parsedParamDefaultKinds[p] = caKinds[p];
            parsedParamDefaultTexts[p] = caKinds[p] >= 0 ? caTexts[p] : "";
        }

        var bodyBrace = ctorResult[1];
        if (bodyBrace < 0 || bodyBrace >= n || ck[bodyBrace] != 129)
        {
            return DeclineAtToken("parse.constructor.body", "constructor body was not materialized as a supported block", cs, cv, ctorIndex, "constructor");
        }
        var chainArgCount = ctorResult[3];
        if (chainArgCount < 0)
        {
            return DeclineAtToken("parse.constructor.chain", "constructor chain-argument metadata was invalid", cs, cv, ctorIndex, "constructor");
        }

        var bodyRoot = ctorResult[4];
        var bodyNodeCount = ctorResult[5];
        if (bodyNodeCount <= 0 || bodyRoot < 0 || bodyRoot >= bodyNodeCount)
        {
            return DeclineAtToken("parse.constructor.body-nodes", "constructor body node table was invalid", cs, cv, ctorIndex, "constructor");
        }

        var chainArgKinds = new int[chainArgCount];
        var chainArgTexts = new string[chainArgCount];
        for (var a = 0; a < chainArgCount; a++)
        {
            var chainArgIndex = paramCount + a;
            chainArgKinds[a] = caKinds[chainArgIndex];
            var chainArgText = caTexts[chainArgIndex];
            chainArgTexts[a] = chainArgText;
        }

        var bodyNodes = BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount);
        var body = new ColumnarFunctionInput(
            "constructor", "void", paramNames, paramCanonicals,
            bodyNodes, bodyRoot);
        var isSynthesizedInitializer = ctorIndex >= 0
            && ctorIndex < n
            && (ck[ctorIndex] == 8 || ck[ctorIndex] == 9 || ck[ctorIndex] == 13);
        input = new ColumnarConstructorInput(
            body,
            ctorResult[0],
            chainArgKinds,
            chainArgTexts,
            parsedParamDefaultKinds,
            parsedParamDefaultTexts,
            isSynthesizedInitializer);
        return true;
    }

    private static bool TryParseColumnarPropertyAt(
        int[] ck, int[] cs, int[] cv, int n, int propIndex, string source,
        out ColumnarPropertyInput input, bool isStatic = false)
    {
        input = null!;
        var cap = n + 1;
        var gk = new int[cap];
        var gvs = new int[cap];
        var gvl = new int[cap];
        var gcs = new int[cap];
        var gcc = new int[cap];
        var gci = new int[cap];
        var gss = new int[cap];
        var gsl = new int[cap];
        var stk = new int[cap];
        var stvs = new int[cap];
        var stvl = new int[cap];
        var stcs = new int[cap];
        var stcc = new int[cap];
        var stci = new int[cap];
        var stss = new int[cap];
        var stsl = new int[cap];
        var propInfo = new int[10];
        var propNameTexts = new string[1];
        var propTypeTexts = new string[1];
        var accessorKind = global::Program.ParseColumnarPropertyInfoInto(
            source, ck, cs, cv, n, propIndex, propNameTexts, propTypeTexts,
            gk, gvs, gvl, gcs, gcc, gci, gss, gsl,
            stk, stvs, stvl, stcs, stcc, stci, stss, stsl,
            propInfo);
        if (accessorKind < 0)
        {
            return DeclineAtToken("parse.property", "property declaration could not be parsed into columnar input", cs, cv, propIndex);
        }

        var propName = propNameTexts[0];
        var propType = propTypeTexts[0];

        var getBodyBrace = propInfo[4];
        if (getBodyBrace < 0 || getBodyBrace >= n || (ck[getBodyBrace] != 129 && ck[getBodyBrace] != 120))
        {
            return DeclineAtToken("parse.property.getter", "property getter body was not materialized as a supported body", cs, cv, propIndex, propName);
        }
        var getBodyRoot = propInfo[6];
        var getBodyNodeCount = propInfo[7];
        if (getBodyNodeCount <= 0 || getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount)
        {
            return DeclineAtToken("parse.property.getter-nodes", "property getter node table was invalid", cs, cv, propIndex, propName);
        }
        var getterNodes = BuildTrimmedNodeTable(gk, gvs, gvl, gcs, gcc, gci, gss, gsl, getBodyNodeCount);
        var getter = new ColumnarFunctionInput(
            "get_" + propName, propType, Array.Empty<string>(), Array.Empty<string>(),
            getterNodes, getBodyRoot);

        ColumnarFunctionInput? setter = null;
        if (accessorKind == 1)
        {
            var setBodyBrace = propInfo[5];
            if (setBodyBrace < 0 || setBodyBrace >= n || ck[setBodyBrace] != 129)
            {
                return DeclineAtToken("parse.property.setter", "property setter body was not materialized as a supported block", cs, cv, propIndex, propName);
            }
            var setBodyRoot = propInfo[8];
            var setBodyNodeCount = propInfo[9];
            if (setBodyNodeCount <= 0 || setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount)
            {
                return DeclineAtToken("parse.property.setter-nodes", "property setter node table was invalid", cs, cv, propIndex, propName);
            }
            var setterNodes = BuildTrimmedNodeTable(stk, stvs, stvl, stcs, stcc, stci, stss, stsl, setBodyNodeCount);
            setter = new ColumnarFunctionInput(
                "set_" + propName, "void", ["value"], [propType],
                setterNodes, setBodyRoot);
        }
        else if (accessorKind != 0)
        {
            return DeclineAtToken("parse.property.accessor-kind", "property accessor kind was invalid", cs, cv, propIndex, propName);
        }

        input = new ColumnarPropertyInput(propName, propType, getter, setter, isStatic);
        return true;
    }

    private static bool TryGetColumnarInterfaceInputs(
        string source, ColumnarTokenizedSource tokens, int[] interfaceIndices, int interfaceIndexCount,
        out List<ColumnarInterfaceInput> interfaceInputs)
    {
        interfaceInputs = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            for (var interfaceSlot = 0; interfaceSlot < interfaceIndexCount; interfaceSlot++)
            {
                var interfaceIndex = interfaceIndices[interfaceSlot];
                var cap = n + 1;
                var outMethodFuncIndices = new int[cap];
                var outBaseNameTexts = new string[cap];
                var outInterfaceNameTexts = new string[1];
                var outMethodNameTexts = new string[cap];
                var outMethodReturnTexts = new string[cap];
                var outMethodParamCounts = new int[cap];
                var outMethodBodyFlags = new int[cap];
                var outMethodParamNameTexts = new string[cap];
                var outMethodParamTypeTexts = new string[cap];
                var outResult = new int[8];
                var methodCount = global::Program.ParseColumnarInterfaceInfoInto(source, ck, cs, cv, n, interfaceIndex,
                    outMethodFuncIndices, outBaseNameTexts, outInterfaceNameTexts,
                    outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags,
                    outMethodParamNameTexts, outMethodParamTypeTexts, outResult);
                if (methodCount < 0)
                    return DeclineAtToken("parse.interface", "interface declaration could not be parsed into columnar input", cs, cv, interfaceIndex);
                var interfaceName = outInterfaceNameTexts[0];
                var baseInterfaceCount = outResult[2];
                var baseInterfaceNames = new string[baseInterfaceCount];
                for (var b = 0; b < baseInterfaceCount; b++)
                {
                    var baseInterfaceName = outBaseNameTexts[b];
                    baseInterfaceNames[b] = baseInterfaceName;
                }
                var methodNames = new string[methodCount];
                var methodReturns = new string[methodCount];
                var methodParamNames = new string[methodCount][];
                var methodParamCanonicals = new string[methodCount][];
                var methodBodies = new ColumnarFunctionInput?[methodCount];
                var flatParamCount = outResult[3];
                if (flatParamCount < 0)
                    return DeclineAtToken("parse.interface.params", "interface flat parameter metadata was invalid", cs, cv, interfaceIndex, interfaceName);
                var paramCursor = 0;
                for (var m = 0; m < methodCount; m++)
                {
                    var methodName = outMethodNameTexts[m];
                    methodNames[m] = methodName;
                    var methodReturn = outMethodReturnTexts[m];
                    methodReturns[m] = methodReturn;
                    var paramCount = outMethodParamCounts[m];
                    if (paramCount < 0 || paramCursor + paramCount > flatParamCount)
                        return DeclineAtToken("parse.interface.method-params", "interface method parameter metadata was invalid", cs, cv, interfaceIndex, interfaceName + "." + methodName);
                    methodParamNames[m] = new string[paramCount];
                    methodParamCanonicals[m] = new string[paramCount];
                    for (var p = 0; p < paramCount; p++)
                    {
                        var flatSlot = paramCursor + p;
                        var paramName = outMethodParamNameTexts[flatSlot];
                        methodParamNames[m][p] = paramName;
                        var paramCanonical = outMethodParamTypeTexts[flatSlot];
                        methodParamCanonicals[m][p] = paramCanonical;
                    }
                    paramCursor += paramCount;
                    if (outMethodBodyFlags[m] == 1)
                    {
                        if (!TryParseColumnarFunctionAt(ck, cs, cv, n, outMethodFuncIndices[m], source, out var bodyInput))
                            return DeclineAtToken("parse.interface.method-body", "default interface method body could not be parsed into columnar input", cs, cv, outMethodFuncIndices[m], interfaceName + "." + methodName);
                        methodBodies[m] = bodyInput;
                    }
                    else if (outMethodBodyFlags[m] != 0)
                    {
                        return DeclineAtToken("parse.interface.method-body-flag", "interface method body flag was invalid", cs, cv, interfaceIndex, interfaceName + "." + methodName);
                    }
                }
                if (paramCursor != flatParamCount)
                    return DeclineAtToken("parse.interface.params", "interface parameter metadata did not consume the expected count", cs, cv, interfaceIndex, interfaceName);
                interfaceInputs.Add(new ColumnarInterfaceInput(
                    interfaceName, baseInterfaceNames, methodNames, methodReturns, methodParamNames, methodParamCanonicals, methodBodies));
            }
            return true;
        }
    }

}
