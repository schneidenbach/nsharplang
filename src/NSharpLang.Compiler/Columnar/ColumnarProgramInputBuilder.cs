using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler.Columnar;

internal static class ColumnarProgramInputBuilder
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryBuild(string source, out ColumnarProgramInput program)
    {
        program = null!;
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;
        if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
            return false;

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
        var declarationRowCount = bindings.TopLevelColumnarProgramDeclarationIndices(
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
            return false;

        if (!TryGetColumnarFunctionInputs(bindings, source, tokens, funcIndices, funcAsyncFlags, declarationResult[1], out var inputs) || inputs.Count == 0)
            return false;
        if (!TryGetColumnarEnumInputs(bindings, source, tokens, enumIndices, declarationResult[2], out var enums))
            return false;
        if (!TryGetColumnarStructInputs(bindings, source, tokens, structIndices, structReferenceFlags, structRecordFlags, declarationResult[5], out var structs))
            return false;
        if (!TryGetColumnarUnionInputs(bindings, source, tokens, unionIndices, declarationResult[3], out var unions))
            return false;
        if (!TryGetColumnarInterfaceInputs(bindings, source, tokens, interfaceIndices, declarationResult[4], out var interfaceInputs))
            return false;

        program = new ColumnarProgramInput(source, inputs, enums, structs, unions, interfaceInputs);
        return true;
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
            var kinds = new int[capacity];
            var starts = new int[capacity];
            var valueLengths = new int[capacity];
            var resultCounts = new int[2];
            var count = bindings.TokenizeColumnarSource(
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
                return false;

            tokens = new ColumnarTokenizedSource(
                rawKinds, rawStarts, rawValueLengths, rawCount,
                kinds, starts, valueLengths, count);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryGetColumnarFunctionInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens, int[] funcIndices, int[] funcAsyncFlags, int funcIndexCount,
        out List<ColumnarFunctionInput> inputs)
    {
        inputs = [];
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            if (funcIndexCount <= 0)
                return false;
            for (var fi = 0; fi < funcIndexCount; fi++)
            {
                if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, funcIndices[fi], source, out var input, isAsync: funcAsyncFlags[fi] == 1))
                    return false;
                inputs.Add(input);
            }
            return true;
        }
        catch
        {
            inputs = [];
            return false;
        }
    }

    private static bool TryGetColumnarEnumInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens, int[] enumIndices, int enumIndexCount,
        out List<ColumnarEnumInput> enums)
    {
        enums = [];
        try
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
                var outEnumNameTexts = new string[1];
                var outResult = new int[2];
                var memberCount = bindings.ParseColumnarEnumInfo(
                    source, ck, cs, cv, n, enumIndex, outNameTexts, outMemberValues, outEnumNameTexts, outResult);
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
                enums.Add(new ColumnarEnumInput(enumName, memberNames, memberValues));
            }
            return true;
        }
        catch
        {
            enums = [];
            return false;
        }
    }

    private static bool TryGetColumnarStructInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens,
        int[] declIndices, int[] declReferenceFlags, int[] declRecordFlags, int declCount,
        out List<ColumnarStructInput> structs)
    {
        structs = [];
        try
        {
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            if (declCount < 0)
                return false;
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
                var outResult = new int[12];
                var fieldCount = bindings.ParseColumnarStructInfo(
                    source, ck, cs, cv, n, structIndex, isReference ? 1 : 0, isRecord ? 1 : 0, outFieldNameTexts, outFieldTypeTexts,
                    outFieldStaticFlags, outFieldInitKinds, outFieldInitTexts,
                    outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
                    outTypeParamTexts, outBaseNameTexts, outStructNameTexts, outResult);
                if (fieldCount < 0 || outResult[1] <= 0)
                    return false;

                var structName = outStructNameTexts[0];
                if (string.IsNullOrEmpty(structName))
                    return false;

                var baseNameCount = outResult[8];
                var baseNames = new string[baseNameCount];
                for (var b = 0; b < baseNameCount; b++)
                {
                    var baseName = outBaseNameTexts[b];
                    if (string.IsNullOrEmpty(baseName))
                        return false;
                    baseNames[b] = baseName;
                }

                var typeParamCount = outResult[7];
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

                var methodCount = outResult[2];
                var methods = new List<ColumnarFunctionInput>(methodCount);
                for (var m = 0; m < methodCount; m++)
                {
                    if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, outMethodFuncIndices[m], source, out var methodInput, isStatic: outMethodStaticFlags[m] == 1))
                        return false;
                    methods.Add(methodInput);
                }

                var ctorCount = outResult[3];
                var constructors = new List<ColumnarConstructorInput>(ctorCount);
                for (var c = 0; c < ctorCount; c++)
                {
                    if (!TryParseColumnarConstructorAt(bindings, ck, cs, cv, n, outCtorIndices[c], source, out var ctorInput))
                        return false;
                    constructors.Add(ctorInput);
                }

                var propCount = outResult[4];
                var properties = new List<ColumnarPropertyInput>(propCount);
                for (var pr = 0; pr < propCount; pr++)
                {
                    if (!TryParseColumnarPropertyAt(bindings, ck, cs, cv, n, outPropIndices[pr], source, out var propInput, isStatic: outPropStaticFlags[pr] == 1))
                        return false;
                    properties.Add(propInput);
                }

                structs.Add(new ColumnarStructInput(structName, fieldNames, fieldTypes, methods, constructors, properties, isReference, baseNames, fieldStatics, fieldInitKinds, fieldInitTexts, isRecord, typeParamNames));
            }
            return true;
        }
        catch
        {
            structs = [];
            return false;
        }
    }

    private static bool TryGetColumnarUnionInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens, int[] unionIndices, int unionIndexCount,
        out List<ColumnarUnionInput> unions)
    {
        unions = [];
        try
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
                var caseCount = bindings.ParseColumnarUnionInfo(
                    source, ck, cs, cv, n, unionIndex, outCaseNameTexts, outCaseFieldCounts,
                    outFieldNameTexts, outFieldTypeTexts, outTypeParamTexts, outUnionNameTexts, outResult);
                if (caseCount <= 0 || outResult[1] <= 0)
                    return false;

                var unionName = outUnionNameTexts[0];
                if (string.IsNullOrEmpty(unionName))
                    return false;

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

                unions.Add(new ColumnarUnionInput(unionName, caseNames, caseFieldNames, caseFieldTypes, typeParamNames));
            }
            return true;
        }
        catch
        {
            unions = [];
            return false;
        }
    }

    private static bool TryParseColumnarFunctionAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int funcIndex, string source,
        out ColumnarFunctionInput input, bool isStatic = false, bool isAsync = false, bool isLocalFunction = false)
    {
        input = null!;
        var cap = n + 1;

        var functionNameTexts = new string[1];
        var returnTypeTexts = new string[1];
        var paramNameTexts = new string[cap];
        var paramTypeTexts = new string[cap];
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
        var paramCount = bindings.ParseColumnarProductFunctionInfo(
            source, ck, cs, cv, n, funcIndex, isLocalFunction ? 1 : 0, functionNameTexts, returnTypeTexts,
            paramNameTexts, paramTypeTexts, paramTupleNameCounts, paramTupleNameTexts, returnTupleNameTexts,
            typeParamTexts, typeParamSpecials, typeParamConstraintCounts, typeParamConstraintTypeTexts,
            bk, bvs, bvl, bcs, bcc, bci, bss, bsl, localFunctionNodeIndices, localFunctionTokenIndices, result);
        if (paramCount < 0)
            return false;

        var functionName = functionNameTexts[0];
        if (string.IsNullOrEmpty(functionName))
            return false;
        var returnCanonical = returnTypeTexts[0];
        if (string.IsNullOrEmpty(returnCanonical))
            return false;

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        string[]?[]? paramTupleNames = null;
        var flatParamTupleNameIndex = 0;
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = paramNameTexts[p];
            var paramType = paramTypeTexts[p];
            if (string.IsNullOrEmpty(paramName) || string.IsNullOrEmpty(paramType))
                return false;
            paramNames[p] = paramName;
            paramCanonicals[p] = paramType;
            var tupleNameCount = paramTupleNameCounts[p];
            if (tupleNameCount < 0 || flatParamTupleNameIndex + tupleNameCount > paramTupleNameTexts.Length)
                return false;
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
            return false;
        if (returnTupleNameCount > 0)
        {
            returnTupleNames = new string[returnTupleNameCount];
            Array.Copy(returnTupleNameTexts, returnTupleNames, returnTupleNameCount);
        }

        var bodyBrace = result[1];
        if (bodyBrace < 0 || bodyBrace >= n || ck[bodyBrace] != 129)
            return false;

        var typeParamNames = Array.Empty<string>();
        var typeParamCount = result[2];
        if (typeParamCount > 0)
        {
            typeParamNames = new string[typeParamCount];
            for (var t = 0; t < typeParamCount; t++)
            {
                var typeParamName = typeParamTexts[t];
                if (string.IsNullOrEmpty(typeParamName))
                    return false;
                typeParamNames[t] = typeParamName;
            }
        }

        var whereItemCount = result[5];
        int[]? parsedTypeParamSpecials = null;
        string[][]? typeParamTypeConstraints = null;
        if (whereItemCount > 0)
        {
            if (typeParamNames.Length == 0)
                return false;
            parsedTypeParamSpecials = new int[typeParamCount];
            typeParamTypeConstraints = new string[typeParamNames.Length][];
            var flatTypeConstraintIndex = 0;
            for (var t = 0; t < typeParamNames.Length; t++)
            {
                parsedTypeParamSpecials[t] = typeParamSpecials[t];
                var constraintCount = typeParamConstraintCounts[t];
                if (constraintCount < 0 || flatTypeConstraintIndex + constraintCount > typeParamConstraintTypeTexts.Length)
                    return false;
                var constraints = new string[constraintCount];
                for (var c = 0; c < constraintCount; c++)
                {
                    var constraint = typeParamConstraintTypeTexts[flatTypeConstraintIndex + c];
                    if (string.IsNullOrEmpty(constraint))
                        return false;
                    constraints[c] = constraint;
                }
                typeParamTypeConstraints[t] = constraints;
                flatTypeConstraintIndex += constraintCount;
            }
        }

        var rootBlock = result[6];
        var bodyNodeCount = result[7];
        if (bodyNodeCount <= 0 || rootBlock < 0 || rootBlock >= bodyNodeCount)
            return false;

        var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
        input = new ColumnarFunctionInput(
            functionName, returnCanonical, paramNames, paramCanonicals,
            bodyNodes, rootBlock, isStatic, typeParamNames,
            parsedTypeParamSpecials, typeParamTypeConstraints,
            returnTupleElementNames: returnTupleNames, paramTupleElementNames: paramTupleNames,
            isAsync: isAsync);

        var localFunctionCount = result[8];
        if (localFunctionCount < 0 || localFunctionCount > localFunctionNodeIndices.Length)
            return false;
        for (var lf = 0; lf < localFunctionCount; lf++)
        {
            if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, localFunctionTokenIndices[lf], source, out var localFn, isLocalFunction: true))
                return false;
            (input.LocalFunctions ??= []).Add((localFunctionNodeIndices[lf], localFn));
        }
        return true;
    }

    private static bool TryParseColumnarConstructorAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int ctorIndex, string source,
        out ColumnarConstructorInput input)
    {
        input = null!;
        var cap = n + 1;
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
        var paramCount = bindings.ParseColumnarConstructorInfo(
            source, ck, cs, cv, n, ctorIndex,
            paramNameTexts, paramTypeTexts, caKinds, caStarts, caLengths, caTexts,
            bk, bvs, bvl, bcs, bcc, bci, bss, bsl, ctorResult);
        if (paramCount < 0)
            return false;

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            var paramName = paramNameTexts[p];
            if (string.IsNullOrEmpty(paramName))
                return false;
            paramNames[p] = paramName;
            var paramCanonical = paramTypeTexts[p];
            if (string.IsNullOrEmpty(paramCanonical))
                return false;
            paramCanonicals[p] = paramCanonical;
        }

        var bodyBrace = ctorResult[1];
        if (bodyBrace < 0 || bodyBrace >= n || ck[bodyBrace] != 129)
            return false;
        var chainArgCount = ctorResult[3];
        if (chainArgCount < 0)
            return false;

        var bodyRoot = ctorResult[4];
        var bodyNodeCount = ctorResult[5];
        if (bodyNodeCount <= 0 || bodyRoot < 0 || bodyRoot >= bodyNodeCount)
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

        var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
        var body = new ColumnarFunctionInput(
            "constructor", "void", paramNames, paramCanonicals,
            bodyNodes, bodyRoot);
        input = new ColumnarConstructorInput(body, ctorResult[0], chainArgKinds, chainArgTexts);
        return true;
    }

    private static bool TryParseColumnarPropertyAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int propIndex, string source,
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
        var accessorKind = bindings.ParseColumnarPropertyInfo(
            source, ck, cs, cv, n, propIndex, propNameTexts, propTypeTexts,
            gk, gvs, gvl, gcs, gcc, gci, gss, gsl,
            stk, stvs, stvl, stcs, stcc, stci, stss, stsl,
            propInfo);
        if (accessorKind < 0)
            return false;

        var propName = propNameTexts[0];
        if (string.IsNullOrEmpty(propName))
            return false;
        var propType = propTypeTexts[0];
        if (string.IsNullOrEmpty(propType))
            return false;

        var getBodyBrace = propInfo[4];
        if (getBodyBrace < 0 || getBodyBrace >= n || ck[getBodyBrace] != 129)
            return false;
        var getBodyRoot = propInfo[6];
        var getBodyNodeCount = propInfo[7];
        if (getBodyNodeCount <= 0 || getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount)
            return false;
        var getterNodes = new ColumnarNodeTable(gk, gvs, gvl, gcs, gcc, gci);
        var getter = new ColumnarFunctionInput(
            "get_" + propName, propType, Array.Empty<string>(), Array.Empty<string>(),
            getterNodes, getBodyRoot);

        ColumnarFunctionInput? setter = null;
        if (accessorKind == 1)
        {
            var setBodyBrace = propInfo[5];
            if (setBodyBrace < 0 || setBodyBrace >= n || ck[setBodyBrace] != 129)
                return false;
            var setBodyRoot = propInfo[8];
            var setBodyNodeCount = propInfo[9];
            if (setBodyNodeCount <= 0 || setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount)
                return false;
            var setterNodes = new ColumnarNodeTable(stk, stvs, stvl, stcs, stcc, stci);
            setter = new ColumnarFunctionInput(
                "set_" + propName, "void", ["value"], [propType],
                setterNodes, setBodyRoot);
        }
        else if (accessorKind != 0)
        {
            return false;
        }

        input = new ColumnarPropertyInput(propName, propType, getter, setter, isStatic);
        return true;
    }

    private static bool TryGetColumnarInterfaceInputs(
        Bindings bindings, string source, ColumnarTokenizedSource tokens, int[] interfaceIndices, int interfaceIndexCount,
        out List<ColumnarInterfaceInput> interfaceInputs)
    {
        interfaceInputs = [];
        try
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
                var methodCount = bindings.ParseColumnarInterfaceInfo(source, ck, cs, cv, n, interfaceIndex,
                    outMethodFuncIndices, outBaseNameTexts, outInterfaceNameTexts,
                    outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags,
                    outMethodParamNameTexts, outMethodParamTypeTexts, outResult);
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
                var methodBodies = new ColumnarFunctionInput?[methodCount];
                var flatParamCount = outResult[3];
                if (flatParamCount < 0)
                    return false;
                var paramCursor = 0;
                for (var m = 0; m < methodCount; m++)
                {
                    var methodName = outMethodNameTexts[m];
                    if (string.IsNullOrEmpty(methodName))
                        return false;
                    methodNames[m] = methodName;
                    var methodReturn = outMethodReturnTexts[m];
                    if (string.IsNullOrEmpty(methodReturn))
                        return false;
                    methodReturns[m] = methodReturn;
                    var paramCount = outMethodParamCounts[m];
                    if (paramCount < 0 || paramCursor + paramCount > flatParamCount)
                        return false;
                    methodParamNames[m] = new string[paramCount];
                    methodParamCanonicals[m] = new string[paramCount];
                    for (var p = 0; p < paramCount; p++)
                    {
                        var flatSlot = paramCursor + p;
                        var paramName = outMethodParamNameTexts[flatSlot];
                        if (string.IsNullOrEmpty(paramName))
                            return false;
                        methodParamNames[m][p] = paramName;
                        var paramCanonical = outMethodParamTypeTexts[flatSlot];
                        if (string.IsNullOrEmpty(paramCanonical))
                            return false;
                        methodParamCanonicals[m][p] = paramCanonical;
                    }
                    paramCursor += paramCount;
                    if (outMethodBodyFlags[m] == 1)
                    {
                        if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, outMethodFuncIndices[m], source, out var bodyInput))
                            return false;
                        methodBodies[m] = bodyInput;
                    }
                    else if (outMethodBodyFlags[m] != 0)
                    {
                        return false;
                    }
                }
                if (paramCursor != flatParamCount)
                    return false;
                interfaceInputs.Add(new ColumnarInterfaceInput(
                    interfaceName, baseInterfaceNames, methodNames, methodReturns, methodParamNames, methodParamCanonicals, methodBodies));
            }
            return true;
        }
        catch
        {
            interfaceInputs = [];
            return false;
        }
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
                CreateDelegate<TokenizeColumnarSourceInto>(
                    programType,
                    "TokenizeColumnarSourceInto"),
                CreateDelegate<TopLevelColumnarProgramDeclarationIndicesInto>(
                    programType,
                    "TopLevelColumnarProgramDeclarationIndicesInto"),
                CreateDelegate<ParseColumnarProductFunctionInfoInto>(
                    programType,
                    "ParseColumnarProductFunctionInfoInto"),
                CreateDelegate<ParseColumnarPropertyInfoInto>(
                    programType,
                    "ParseColumnarPropertyInfoInto"),
                CreateDelegate<ParseColumnarInterfaceInfoInto>(
                    programType,
                    "ParseColumnarInterfaceInfoInto"),
                CreateDelegate<ParseColumnarEnumInfoInto>(
                    programType,
                    "ParseColumnarEnumInfoInto"),
                CreateDelegate<ParseColumnarStructInfoInto>(
                    programType,
                    "ParseColumnarStructInfoInto"),
                CreateDelegate<ParseColumnarUnionInfoInto>(
                    programType,
                    "ParseColumnarUnionInfoInto"),
                CreateDelegate<ParseColumnarConstructorInfoInto>(
                    programType,
                    "ParseColumnarConstructorInfoInto"));
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

    private delegate int TokenizeColumnarSourceInto(
        string source,
        int[] rawKinds,
        int[] rawStarts,
        int[] rawValueLengths,
        int[] compactKinds,
        int[] compactStarts,
        int[] compactValueLengths,
        int[] resultCounts);

    private delegate int TopLevelColumnarProgramDeclarationIndicesInto(
        string source,
        int[] rawTokenKinds, int[] rawTokenStarts, int[] rawTokenValueLengths, int rawCount,
        int[] compactTokenKinds, int compactCount,
        int[] outFuncIndices, int[] outFuncAsyncFlags,
        int[] outEnumIndices, int[] outUnionIndices, int[] outInterfaceIndices,
        int[] outStructIndices, int[] outStructReferenceFlags, int[] outStructRecordFlags,
        int[] outResult);

    private delegate int ParseColumnarProductFunctionInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int funcIndex, int isLocalFunction,
        string[] outFunctionNameTexts, string[] outReturnTypeTexts,
        string[] outParamNameTexts, string[] outParamTypeTexts, int[] outParamTupleNameCounts, string[] outParamTupleNameTexts,
        string[] outReturnTupleNameTexts, string[] outTypeParamTexts, int[] outTypeParamSpecials,
        int[] outTypeParamConstraintCounts, string[] outTypeParamConstraintTypeTexts,
        int[] outNodeKinds, int[] outValueStarts, int[] outValueLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths,
        int[] outLocalFunctionNodeIndices, int[] outLocalFunctionTokenIndices, int[] outResult);

    private delegate int ParseColumnarPropertyInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int propIndex,
        string[] outNameTexts, string[] outTypeTexts,
        int[] outGetNodeKinds, int[] outGetValueStarts, int[] outGetValueLengths, int[] outGetChildStart, int[] outGetChildCount,
        int[] outGetChildIndices, int[] outGetSpanStarts, int[] outGetSpanLengths,
        int[] outSetNodeKinds, int[] outSetValueStarts, int[] outSetValueLengths, int[] outSetChildStart, int[] outSetChildCount,
        int[] outSetChildIndices, int[] outSetSpanStarts, int[] outSetSpanLengths, int[] outResult);

    private delegate int ParseColumnarInterfaceInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int interfaceIndex,
        int[] outMethodFuncIndices, string[] outBaseNameTexts, string[] outInterfaceNameTexts,
        string[] outMethodNameTexts, string[] outMethodReturnTexts,
        int[] outMethodParamCounts, int[] outMethodBodyFlags,
        string[] outMethodParamNameTexts, string[] outMethodParamTypeTexts, int[] outResult);

    private delegate int ParseColumnarEnumInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int enumIndex,
        string[] outNameTexts, int[] outMemberValues, string[] outEnumNameTexts, int[] outResult);

    private delegate int ParseColumnarStructInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int structIndex,
        int isReference,
        int isRecord,
        string[] outFieldNameTexts, string[] outFieldTypeTexts,
        int[] outFieldStaticFlags, int[] outFieldInitKinds, string[] outFieldInitTexts,
        int[] outMethodFuncIndices, int[] outMethodStaticFlags, int[] outCtorIndices, int[] outPropIndices, int[] outPropStaticFlags,
        string[] outTypeParamTexts, string[] outBaseNameTexts,
        string[] outStructNameTexts, int[] outResult);

    private delegate int ParseColumnarUnionInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int unionIndex,
        string[] outCaseNameTexts, int[] outCaseFieldCounts,
        string[] outFieldNameTexts, string[] outFieldTypeTexts, string[] outTypeParamTexts,
        string[] outUnionNameTexts, int[] outResult);

    private delegate int ParseColumnarConstructorInfoInto(
        string source,
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int ctorIndex,
        string[] outParamNameTexts, string[] outParamTypeTexts,
        int[] outArgKinds, int[] outArgStarts, int[] outArgLengths, string[] outArgTexts,
        int[] outNodeKinds, int[] outValueStarts, int[] outValueLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths, int[] outResult);

    private sealed record Bindings(
        TokenizeColumnarSourceInto TokenizeColumnarSource,
        TopLevelColumnarProgramDeclarationIndicesInto TopLevelColumnarProgramDeclarationIndices,
        ParseColumnarProductFunctionInfoInto ParseColumnarProductFunctionInfo,
        ParseColumnarPropertyInfoInto ParseColumnarPropertyInfo,
        ParseColumnarInterfaceInfoInto ParseColumnarInterfaceInfo,
        ParseColumnarEnumInfoInto ParseColumnarEnumInfo,
        ParseColumnarStructInfoInto ParseColumnarStructInfo,
        ParseColumnarUnionInfoInto ParseColumnarUnionInfo,
        ParseColumnarConstructorInfoInto ParseColumnarConstructorInfo);

    private sealed class ColumnarTokenizedSource
    {
        internal ColumnarTokenizedSource(
            int[] rawKinds,
            int[] rawStarts,
            int[] rawValueLengths,
            int rawCount,
            int[] kinds,
            int[] starts,
            int[] valueLengths,
            int count)
        {
            RawKinds = rawKinds;
            RawStarts = rawStarts;
            RawValueLengths = rawValueLengths;
            RawCount = rawCount;
            Kinds = kinds;
            Starts = starts;
            ValueLengths = valueLengths;
            Count = count;
        }

        internal int[] RawKinds { get; }
        internal int[] RawStarts { get; }
        internal int[] RawValueLengths { get; }
        internal int RawCount { get; }
        internal int[] Kinds { get; }
        internal int[] Starts { get; }
        internal int[] ValueLengths { get; }
        internal int Count { get; }
    }
}
