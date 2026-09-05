using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler.Columnar;

internal static class ColumnarProgramInputBuilder
{
    // Site ids and sentences are ColumnarParseDeclines (ColumnarDeclineReasons.nl); token-kind and
    // modifier-bit meanings are ColumnarTokenKindFacts and the parser kernels. Nothing here spells
    // either — this type marshals arrays and asks.
    private static bool Decline(ColumnarParseDecline decline, int spanStart = -1, int spanLength = 0, string memberName = "")
    {
        ColumnarDeclineTrace.Record(decline.SiteId, decline.Message, spanStart, spanLength, memberName);
        return false;
    }

    private static bool DeclineAtToken(
        ColumnarParseDecline decline,
        int[] tokenStarts,
        int[] tokenValueLengths,
        int tokenIndex,
        string memberName = "")
    {
        if (tokenIndex >= 0 && tokenIndex < tokenStarts.Length)
        {
            return Decline(decline, tokenStarts[tokenIndex], tokenValueLengths[tokenIndex], memberName);
        }

        return Decline(decline, memberName: memberName);
    }

    // Body node tables parse into worst-case scratch arrays (token-count sized) but are retained all
    // compile; copy down to node count (+1 sentinel row) so retained memory tracks tree, not file, size.
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
            return Decline(ColumnarParseDeclines.Tokenize);
        }

        var n = tokens.Count;
        var funcIndices = new int[n + 1];
        var funcAsyncFlags = new int[n + 1];
        var funcGeneratorFlags = new int[n + 1];
        var enumIndices = new int[n + 1];
        var unionIndices = new int[n + 1];
        var interfaceIndices = new int[n + 1];
        var structIndices = new int[n + 1];
        var structReferenceFlags = new int[n + 1];
        var structRecordFlags = new int[n + 1];
        var structVisibilityFlags = new int[n + 1];
        var structEnclosingTypeNames = new string[n + 1];
        var declarationResult = new int[6];
        var declarationRowCount = global::Program.ColumnarProgramDeclarationIndicesInto(
            source,
            tokens.RawKinds,
            tokens.RawStarts,
            tokens.RawValueLengths,
            tokens.RawCount,
            tokens.Kinds,
            tokens.Starts,
            tokens.ValueLengths,
            n,
            funcIndices,
            funcAsyncFlags,
            funcGeneratorFlags,
            enumIndices,
            unionIndices,
            interfaceIndices,
            structIndices, structReferenceFlags, structRecordFlags,
            structVisibilityFlags, structEnclosingTypeNames, declarationResult);
        if (declarationRowCount < 0)
        {
            return DeclineAtToken(
                ColumnarParseDeclines.DeclarationScan(declarationRowCount),
                tokens.Starts,
                tokens.ValueLengths,
                0);
        }

        if (!TryGetColumnarFunctionInputs(source, tokens, funcIndices, funcAsyncFlags, funcGeneratorFlags, declarationResult[1], out var inputs))
        {
            return Decline(ColumnarParseDeclines.FunctionMaterialization);
        }
        if (!TryGetColumnarEnumInputs(source, tokens, enumIndices, declarationResult[2], out var enums))
        {
            return Decline(ColumnarParseDeclines.EnumMaterialization);
        }
        if (!TryGetColumnarStructInputs(source, tokens, structIndices, structReferenceFlags, structRecordFlags, structVisibilityFlags, structEnclosingTypeNames, declarationResult[5], out var structs))
        {
            return Decline(ColumnarParseDeclines.StructMaterialization);
        }
        if (!TryGetColumnarUnionInputs(source, tokens, unionIndices, declarationResult[3], out var unions))
        {
            return Decline(ColumnarParseDeclines.UnionMaterialization);
        }
        if (!TryGetColumnarInterfaceInputs(source, tokens, interfaceIndices, declarationResult[4], out var interfaceInputs))
        {
            return Decline(ColumnarParseDeclines.InterfaceMaterialization);
        }

        if (!TryGetColumnarTestInputs(source, tokens, out var testInputs))
        {
            return Decline(ColumnarParseDeclines.TestMaterialization);
        }

        if (!TryGetColumnarNewtypeInputs(source, tokens, structs))
        {
            return Decline(ColumnarParseDeclines.NewtypeMaterialization);
        }

        program = ColumnarProgramInput.CreateSingleSource(source, inputs, enums, structs, unions, interfaceInputs, testInputs);
        return true;
    }

    internal static bool TryBuildMultiFile(
        IReadOnlyList<string> sources,
        IReadOnlyList<string> fileNames, string projectRoot,
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

        program = ColumnarProgramInput.MergeSourceFilesAtProjectRoot(sourceFiles, programs, projectRoot);
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
            return Decline(ColumnarParseDeclines.NewtypeScan);

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
            return Decline(ColumnarParseDeclines.TestScan);

        for (var t = 0; t < testCount; t++)
        {
            if (!TryParseColumnarTestAt(ck, cs, cv, n, testIndices[t], source, out var testInput))
                return DeclineAtToken(ColumnarParseDeclines.TestDeclaration, cs, cv, testIndices[t]);
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
        var result = new int[6];
        var bodyNodeCount = global::Program.ParseColumnarTestInfoInto(
            source, ck, cs, cv, n, testIndex, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, result);
        if (bodyNodeCount <= 0)
            return false;

        var bodyRoot = result[2];
        if (bodyRoot < 0 || bodyRoot >= bodyNodeCount || result[0] < 0 || result[1] <= 0 || result[0] + result[1] > source.Length)
            return false;

        var description = global::Program.ColumnarTestCaseLabel(source, result);
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
                return Decline(ColumnarParseDeclines.TokenizeInvalidResult);

            tokens = new ColumnarTokenizedSource(
                rawKinds, rawStarts, rawValueLengths, rawCount,
                kinds, starts, valueLengths, count);
            return true;
        }
    }

    private static bool TryGetColumnarFunctionInputs(
        string source, ColumnarTokenizedSource tokens, int[] funcIndices, int[] funcAsyncFlags, int[] funcGeneratorFlags, int funcIndexCount,
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
                var modifierFlags = global::Program.ColumnarFunctionModifierFlagsForGenerator(funcGeneratorFlags[fi]);
                if (!TryParseColumnarFunctionAt(ck, cs, cv, n, funcIndices[fi], source, out var input, isAsync: funcAsyncFlags[fi] == 1, modifierFlags: modifierFlags))
                    return DeclineAtToken(ColumnarParseDeclines.FunctionDeclaration, cs, cv, funcIndices[fi]);
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
                    return DeclineAtToken(ColumnarParseDeclines.EnumDeclaration, cs, cv, enumIndex);
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
        int[] declIndices, int[] declReferenceFlags, int[] declRecordFlags, int[] declVisibilityFlags, string[] declEnclosingTypeNames, int declCount,
        out List<ColumnarStructInput> structs)
    {
        structs = [];
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            if (declCount < 0)
                return Decline(ColumnarParseDeclines.StructInvalidCount);
            for (var declSlot = 0; declSlot < declCount; declSlot++)
            {
                var structIndex = declIndices[declSlot];
                var isReference = declReferenceFlags[declSlot] == 1;
                var isRecord = declRecordFlags[declSlot] == 1;
                var isRefStruct = !isReference && structIndex > 0 && ColumnarTokenKindFacts.IsRefStructModifierKind(ck[structIndex - 1]);
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
                var outWhereOwnerTexts = new string[cap];
                var outWhereItemCodes = new int[cap];
                var outWhereTypeTexts = new string[cap];
                var outResult = new int[11];
                var fieldCount = global::Program.ParseColumnarStructInfoInto(
                    source, ck, cs, cv, n, structIndex, isReference ? 1 : 0, isRecord ? 1 : 0, outFieldNameTexts, outFieldTypeTexts,
                    outFieldStaticFlags, outFieldInitKinds, outFieldInitTexts,
                    outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
                    outTypeParamTexts, outBaseNameTexts, outStructNameTexts,
                    outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, outResult);
                if (fieldCount < 0 || outResult[1] <= 0)
                {
                    return DeclineAtToken(ColumnarParseDeclines.StructDeclaration, cs, cv, structIndex);
                }

                var structName = outStructNameTexts[0];

                var baseNames = ColumnarConstraintColumns.TrimTexts(outBaseNameTexts, outResult[8]);
                var typeParamCount = outResult[7];
                var typeParamNames = ColumnarConstraintColumns.TrimTexts(outTypeParamTexts, typeParamCount);
                var whereRowCount = outResult[10];
                var typeParamSpecials = ColumnarConstraintColumns.BuildSpecials(outWhereOwnerTexts, outWhereItemCodes, typeParamNames, whereRowCount);
                var typeParamTypeConstraints = ColumnarConstraintColumns.BuildTypeConstraints(outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, typeParamNames, whereRowCount);

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
                    fieldStatics[f] = global::Program.ColumnarStructFieldFlagIsStatic(fieldModifierFlags);
                    fieldReadonlyFlags[f] = global::Program.ColumnarStructFieldFlagIsReadonly(fieldModifierFlags);
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
                    if (!TryParseColumnarFunctionAt(
                            ck, cs, cv, n, outMethodFuncIndices[m], source, out var methodInput,
                            isStatic: global::Program.ColumnarStructMethodFlagIsStatic(methodModifierFlags),
                            isAsync: global::Program.ColumnarStructMethodFlagIsAsync(methodModifierFlags),
                            modifierFlags: methodModifierFlags,
                            isBodylessNativeImport: ColumnarFunctionInput.HasNativeImportModifier(methodModifierFlags)))
                    {
                        return DeclineAtToken(ColumnarParseDeclines.StructMethod, cs, cv, outMethodFuncIndices[m], structName);
                    }
                    methods.Add(methodInput);
                }

                var ctorCount = outResult[3];
                var constructors = new List<ColumnarConstructorInput>(ctorCount);
                for (var c = 0; c < ctorCount; c++)
                {
                    if (!TryParseColumnarConstructorAt(ck, cs, cv, n, outCtorIndices[c], source, out var ctorInput))
                    {
                        return DeclineAtToken(ColumnarParseDeclines.StructConstructor, cs, cv, outCtorIndices[c], structName);
                    }
                    constructors.Add(ctorInput);
                }

                var propCount = outResult[4];
                var properties = new List<ColumnarPropertyInput>(propCount);
                for (var pr = 0; pr < propCount; pr++)
                {
                    if (!TryParseColumnarPropertyAt(ck, cs, cv, n, outPropIndices[pr], source, out var propInput, isStatic: outPropStaticFlags[pr] == 1))
                    {
                        return DeclineAtToken(ColumnarParseDeclines.StructProperty, cs, cv, outPropIndices[pr], structName);
                    }
                    properties.Add(propInput);
                }

                structs.Add(new ColumnarStructInput(structName, fieldNames, fieldTypes, methods, constructors, properties, isReference, baseNames, fieldStatics, fieldInitKinds, fieldInitTexts, isRecord, typeParamNames, fieldReadonlyFlags, isRefStruct: isRefStruct, enclosingTypeName: declEnclosingTypeNames[declSlot] ?? "", visibilityModifierFlags: declVisibilityFlags[declSlot], typeParamSpecialConstraints: typeParamSpecials, typeParamTypeConstraints: typeParamTypeConstraints));
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
                var outWhereOwnerTexts = new string[cap];
                var outWhereItemCodes = new int[cap];
                var outWhereTypeTexts = new string[cap];
                var outResult = new int[6];
                var caseCount = global::Program.ParseColumnarUnionInfoInto(
                    source, ck, cs, cv, n, unionIndex, outCaseNameTexts, outCaseFieldCounts,
                    outFieldNameTexts, outFieldTypeTexts, outTypeParamTexts, outUnionNameTexts,
                    outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, outResult);
                if (caseCount <= 0 || outResult[1] <= 0)
                {
                    return DeclineAtToken(ColumnarParseDeclines.UnionDeclaration, cs, cv, unionIndex);
                }

                var unionName = outUnionNameTexts[0];

                var typeParamCount = outResult[2];

                // A small, closed, payload-free, non-generic union is the public allocation-free readonly
                // tag struct (matching UnionValueLayout.IsValueStructEmittable); this flag selects that emit
                // path over the class hierarchy. Eligibility is N#-owned (ParserColumnarUnions.nl).
                var isValueStruct = global::Program.ColumnarUnionIsValueStructEmittable(outCaseFieldCounts, caseCount, typeParamCount) == 1;
                string[]? typeParamNames = typeParamCount > 0 ? ColumnarConstraintColumns.TrimTexts(outTypeParamTexts, typeParamCount) : null;

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

                var unionTypeParams = typeParamNames ?? System.Array.Empty<string>();
                unions.Add(new ColumnarUnionInput(unionName, caseNames, caseFieldNames, caseFieldTypes, typeParamNames, isValueStruct,
                    typeParamSpecialConstraints: ColumnarConstraintColumns.BuildSpecials(outWhereOwnerTexts, outWhereItemCodes, unionTypeParams, outResult[5]),
                    typeParamTypeConstraints: ColumnarConstraintColumns.BuildTypeConstraints(outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, unionTypeParams, outResult[5])));
            }
            return true;
        }
    }

    private static bool TryParseColumnarFunctionAt(
        int[] ck, int[] cs, int[] cv, int n, int funcIndex, string source,
        out ColumnarFunctionInput input, bool isStatic = false, bool isAsync = false, bool isLocalFunction = false, int modifierFlags = 0,
        bool isBodylessNativeImport = false)
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
        var paramCount = isBodylessNativeImport
            ? global::Program.ParseColumnarProductFunctionSignatureInfoInto(
                source, ck, cs, cv, n, funcIndex, functionNameTexts, returnTypeTexts,
                paramNameTexts, paramTypeTexts, paramModifierKinds, paramDefaultKinds, paramDefaultTexts,
                paramTupleNameCounts, paramTupleNameTexts, returnTupleNameTexts,
                typeParamTexts, typeParamSpecials, typeParamConstraintCounts, typeParamConstraintTypeTexts, result)
            : global::Program.ParseColumnarProductFunctionInfoInto(
                source, ck, cs, cv, n, funcIndex, isLocalFunction ? 1 : 0, functionNameTexts, returnTypeTexts,
                paramNameTexts, paramTypeTexts, paramModifierKinds, paramDefaultKinds, paramDefaultTexts,
                paramTupleNameCounts, paramTupleNameTexts, returnTupleNameTexts,
                typeParamTexts, typeParamSpecials, typeParamConstraintCounts, typeParamConstraintTypeTexts,
                bk, bvs, bvl, bcs, bcc, bci, bss, bsl, localFunctionNodeIndices, localFunctionTokenIndices, result);
        if (paramCount < 0)
        {
            return DeclineAtToken(ColumnarParseDeclines.FunctionBodyOrSignature, cs, cv, funcIndex);
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
                return DeclineAtToken(ColumnarParseDeclines.FunctionParameterTupleNames, cs, cv, funcIndex, functionName);
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
            return DeclineAtToken(ColumnarParseDeclines.FunctionReturnTupleNames, cs, cv, funcIndex, functionName);
        if (returnTupleNameCount > 0)
        {
            returnTupleNames = new string[returnTupleNameCount];
            Array.Copy(returnTupleNameTexts, returnTupleNames, returnTupleNameCount);
        }

        var bodyBrace = result[1];
        if (!isBodylessNativeImport && (bodyBrace < 0 || bodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBodyStartKind(ck[bodyBrace])))
            return DeclineAtToken(ColumnarParseDeclines.FunctionBody, cs, cv, funcIndex, functionName);

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
                return DeclineAtToken(ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters, cs, cv, funcIndex, functionName);
            parsedTypeParamSpecials = new int[typeParamCount];
            typeParamTypeConstraints = new string[typeParamNames.Length][];
            var flatTypeConstraintIndex = 0;
            for (var t = 0; t < typeParamNames.Length; t++)
            {
                parsedTypeParamSpecials[t] = typeParamSpecials[t];
                var constraintCount = typeParamConstraintCounts[t];
                if (constraintCount < 0 || flatTypeConstraintIndex + constraintCount > typeParamConstraintTypeTexts.Length)
                    return DeclineAtToken(ColumnarParseDeclines.FunctionConstraintMetadata, cs, cv, funcIndex, functionName);
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
        if (!isBodylessNativeImport && (bodyNodeCount <= 0 || rootBlock < 0 || rootBlock >= bodyNodeCount))
        {
            return DeclineAtToken(ColumnarParseDeclines.FunctionBodyNodes, cs, cv, funcIndex, functionName);
        }

        var bodyNodes = isBodylessNativeImport
            ? new ColumnarNodeTable(
                Array.Empty<int>(), Array.Empty<int>(), Array.Empty<int>(),
                Array.Empty<int>(), Array.Empty<int>(), Array.Empty<int>(),
                Array.Empty<int>(), Array.Empty<int>())
            : BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount);
        var nativeImportLibraryName = "";
        var nativeImportEntryPoint = "";
        if (isBodylessNativeImport)
        {
            var nativeImportTexts = new string[2];
            if (global::Program.ParseColumnarNativeImportInfoInto(source, ck, cs, cv, n, funcIndex, functionName, nativeImportTexts) != 1)
                return DeclineAtToken(ColumnarParseDeclines.FunctionNativeImport, cs, cv, funcIndex, functionName);
            nativeImportLibraryName = nativeImportTexts[0];
            nativeImportEntryPoint = nativeImportTexts[1];
            rootBlock = -1;
            bodyNodeCount = 0;
        }
        input = new ColumnarFunctionInput(
            functionName, returnCanonical, paramNames, paramCanonicals,
            bodyNodes, rootBlock, isStatic, typeParamNames,
            parsedTypeParamSpecials, typeParamTypeConstraints,
            returnTupleElementNames: returnTupleNames, paramTupleElementNames: paramTupleNames,
            paramModifierKinds: parsedParamModifierKinds,
            paramDefaultKinds: parsedParamDefaultKinds, paramDefaultTexts: parsedParamDefaultTexts,
            isAsync: isAsync,
            modifierFlags: modifierFlags,
            isBodylessNativeImport: isBodylessNativeImport,
            nativeImportLibraryName: nativeImportLibraryName,
            nativeImportEntryPoint: nativeImportEntryPoint);

        var localFunctionCount = result[8];
        if (localFunctionCount < 0 || localFunctionCount > localFunctionNodeIndices.Length)
        {
            return DeclineAtToken(ColumnarParseDeclines.FunctionLocalFunctionMetadata, cs, cv, funcIndex, functionName);
        }
        for (var lf = 0; lf < localFunctionCount; lf++)
        {
            if (!TryParseColumnarFunctionAt(ck, cs, cv, n, localFunctionTokenIndices[lf], source, out var localFn, isLocalFunction: true))
            {
                return DeclineAtToken(ColumnarParseDeclines.LocalFunction, cs, cv, localFunctionTokenIndices[lf], functionName);
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
            return DeclineAtToken(ColumnarParseDeclines.Constructor, cs, cv, ctorIndex, "constructor");
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
        if (bodyBrace < 0 || bodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(ck[bodyBrace]))
        {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorBody, cs, cv, ctorIndex, "constructor");
        }
        var chainArgCount = ctorResult[3];
        if (chainArgCount < 0)
        {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorChain, cs, cv, ctorIndex, "constructor");
        }

        var bodyRoot = ctorResult[4];
        var bodyNodeCount = ctorResult[5];
        if (bodyNodeCount <= 0 || bodyRoot < 0 || bodyRoot >= bodyNodeCount)
        {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorBodyNodes, cs, cv, ctorIndex, "constructor");
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
            && ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(ck[ctorIndex]);
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
            return DeclineAtToken(ColumnarParseDeclines.PropertyDeclaration, cs, cv, propIndex);
        }

        var propName = propNameTexts[0];
        var propType = propTypeTexts[0];

        var getBodyBrace = propInfo[4];
        if (getBodyBrace < 0 || getBodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBodyStartKind(ck[getBodyBrace]))
        {
            return DeclineAtToken(ColumnarParseDeclines.PropertyGetter, cs, cv, propIndex, propName);
        }
        var getBodyRoot = propInfo[6];
        var getBodyNodeCount = propInfo[7];
        if (getBodyNodeCount <= 0 || getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount)
        {
            return DeclineAtToken(ColumnarParseDeclines.PropertyGetterNodes, cs, cv, propIndex, propName);
        }
        var getterNodes = BuildTrimmedNodeTable(gk, gvs, gvl, gcs, gcc, gci, gss, gsl, getBodyNodeCount);
        var getter = new ColumnarFunctionInput(
            "get_" + propName, propType, Array.Empty<string>(), Array.Empty<string>(),
            getterNodes, getBodyRoot);

        ColumnarFunctionInput? setter = null;
        if (accessorKind == 1)
        {
            var setBodyBrace = propInfo[5];
            if (setBodyBrace < 0 || setBodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(ck[setBodyBrace]))
            {
                return DeclineAtToken(ColumnarParseDeclines.PropertySetter, cs, cv, propIndex, propName);
            }
            var setBodyRoot = propInfo[8];
            var setBodyNodeCount = propInfo[9];
            if (setBodyNodeCount <= 0 || setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount)
            {
                return DeclineAtToken(ColumnarParseDeclines.PropertySetterNodes, cs, cv, propIndex, propName);
            }
            var setterNodes = BuildTrimmedNodeTable(stk, stvs, stvl, stcs, stcc, stci, stss, stsl, setBodyNodeCount);
            setter = new ColumnarFunctionInput(
                "set_" + propName, "void", ["value"], [propType],
                setterNodes, setBodyRoot);
        }
        else if (accessorKind != 0)
        {
            return DeclineAtToken(ColumnarParseDeclines.PropertyAccessorKind, cs, cv, propIndex, propName);
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
                var outMethodParamModifierKinds = new int[cap];
                var outTypeParamTexts = new string[cap];
                var outWhereOwnerTexts = new string[cap];
                var outWhereItemCodes = new int[cap];
                var outWhereTypeTexts = new string[cap];
                var outResult = new int[8];
                var methodCount = global::Program.ParseColumnarInterfaceInfoInto(source, ck, cs, cv, n, interfaceIndex,
                    outMethodFuncIndices, outBaseNameTexts, outInterfaceNameTexts,
                    outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags,
                    outMethodParamNameTexts, outMethodParamTypeTexts, outMethodParamModifierKinds,
                    outTypeParamTexts, outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, outResult);
                if (methodCount < 0)
                    return DeclineAtToken(ColumnarParseDeclines.InterfaceDeclaration, cs, cv, interfaceIndex);
                var interfaceName = outInterfaceNameTexts[0];
                var baseInterfaceNames = ColumnarConstraintColumns.TrimTexts(outBaseNameTexts, outResult[2]);
                var typeParamCount = outResult[4];
                if (typeParamCount < 0 || typeParamCount > outTypeParamTexts.Length)
                    return DeclineAtToken(ColumnarParseDeclines.InterfaceTypeParameterMetadata, cs, cv, interfaceIndex, interfaceName);
                var typeParamNames = new string[typeParamCount];
                for (var tp = 0; tp < typeParamCount; tp++)
                {
                    if (string.IsNullOrWhiteSpace(outTypeParamTexts[tp]))
                        return DeclineAtToken(ColumnarParseDeclines.InterfaceTypeParameterName, cs, cv, interfaceIndex, interfaceName);
                    typeParamNames[tp] = outTypeParamTexts[tp];
                }
                var methodNames = new string[methodCount];
                var methodReturns = new string[methodCount];
                var methodParamNames = new string[methodCount][];
                var methodParamCanonicals = new string[methodCount][];
                var methodParamModifierKinds = new int[methodCount][];
                var methodBodies = new ColumnarFunctionInput?[methodCount];
                var flatParamCount = outResult[3];
                if (flatParamCount < 0)
                    return DeclineAtToken(ColumnarParseDeclines.InterfaceFlatParameterMetadata, cs, cv, interfaceIndex, interfaceName);
                var paramCursor = 0;
                for (var m = 0; m < methodCount; m++)
                {
                    var methodName = outMethodNameTexts[m];
                    methodNames[m] = methodName;
                    methodReturns[m] = outMethodReturnTexts[m];
                    var paramCount = outMethodParamCounts[m];
                    if (paramCount < 0 || paramCursor + paramCount > flatParamCount)
                        return DeclineAtToken(ColumnarParseDeclines.InterfaceMethodParameterMetadata, cs, cv, interfaceIndex, interfaceName + "." + methodName);
                    methodParamNames[m] = new string[paramCount];
                    methodParamCanonicals[m] = new string[paramCount];
                    methodParamModifierKinds[m] = new int[paramCount];
                    for (var p = 0; p < paramCount; p++)
                    {
                        var flatSlot = paramCursor + p;
                        methodParamNames[m][p] = outMethodParamNameTexts[flatSlot];
                        methodParamCanonicals[m][p] = outMethodParamTypeTexts[flatSlot];
                        methodParamModifierKinds[m][p] = outMethodParamModifierKinds[flatSlot];
                    }
                    paramCursor += paramCount;
                    if (outMethodBodyFlags[m] == 1)
                    {
                        if (!TryParseColumnarFunctionAt(ck, cs, cv, n, outMethodFuncIndices[m], source, out var bodyInput))
                            return DeclineAtToken(ColumnarParseDeclines.InterfaceMethodBody, cs, cv, outMethodFuncIndices[m], interfaceName + "." + methodName);
                        methodBodies[m] = bodyInput;
                    }
                    else if (outMethodBodyFlags[m] != 0)
                    {
                        return DeclineAtToken(ColumnarParseDeclines.InterfaceMethodBodyFlag, cs, cv, interfaceIndex, interfaceName + "." + methodName);
                    }
                }
                if (paramCursor != flatParamCount)
                    return DeclineAtToken(ColumnarParseDeclines.InterfaceParameterCount, cs, cv, interfaceIndex, interfaceName);
                interfaceInputs.Add(new ColumnarInterfaceInput(
                    interfaceName, baseInterfaceNames, methodNames, methodReturns, methodParamNames, methodParamCanonicals, methodBodies,
                    typeParamNames: typeParamNames, methodParamModifierKinds: methodParamModifierKinds,
                    typeParamSpecialConstraints: ColumnarConstraintColumns.BuildSpecials(outWhereOwnerTexts, outWhereItemCodes, typeParamNames, outResult[6]),
                    typeParamTypeConstraints: ColumnarConstraintColumns.BuildTypeConstraints(outWhereOwnerTexts, outWhereItemCodes, outWhereTypeTexts, typeParamNames, outResult[6])));
            }
            return true;
        }
    }

}
