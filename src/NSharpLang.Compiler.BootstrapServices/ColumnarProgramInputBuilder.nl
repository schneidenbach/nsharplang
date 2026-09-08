namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// Materializes the parser kernels' flat output columns into the durable program-input model used by
// the columnar emitter. The kernels own syntax decisions; this owner preserves declaration order,
// partial failure state, source-file attribution, and the retained node-table shape.
sealed class ColumnarProgramInputBuilder {
    private constructor() {
    }

    private static func Decline(decline: ColumnarParseDecline, spanStart: int, spanLength: int, memberName: string): bool {
        ColumnarDeclineTrace.Record(decline.SiteId, decline.Message, spanStart, spanLength, memberName)
        return false
    }

    private static func DeclineAtToken(decline: ColumnarParseDecline, tokenStarts: int[], tokenValueLengths: int[], tokenIndex: int, memberName: string): bool {
        if tokenIndex >= 0 && tokenIndex < tokenStarts.Length {
            return Decline(decline, tokenStarts[tokenIndex], tokenValueLengths[tokenIndex], memberName)
        }

        return Decline(decline, -1, 0, memberName)
    }

    // Body parsers use token-count-sized scratch columns. Retain only the populated node rows plus
    // one sentinel row, and only the reachable prefix of the flat child-index column.
    private static func BuildTrimmedNodeTable(kinds: int[], valueStarts: int[], valueLengths: int[], childStarts: int[], childCounts: int[], childIndices: int[], spanStarts: int[], spanLengths: int[], nodeCount: int): ColumnarNodeTable {
        rowCount := Math.Min(nodeCount + 1, kinds.Length)
        childLimit := 0
        i := 0
        while i < nodeCount {
            childEnd := childStarts[i] + childCounts[i]
            if childEnd > childLimit {
                childLimit = childEnd
            }
            i = i + 1
        }
        childLimit = Math.Clamp(childLimit, 0, childIndices.Length)

        trimmedKinds := kinds[..rowCount]
        trimmedValueStarts := valueStarts[..rowCount]
        trimmedValueLengths := valueLengths[..rowCount]
        trimmedChildStarts := childStarts[..rowCount]
        trimmedChildCounts := childCounts[..rowCount]
        trimmedChildIndices := childIndices[..childLimit]
        trimmedSpanStarts := spanStarts[..rowCount]
        trimmedSpanLengths := spanLengths[..rowCount]
        return new ColumnarNodeTable(
            trimmedKinds,
            trimmedValueStarts,
            trimmedValueLengths,
            trimmedChildStarts,
            trimmedChildCounts,
            trimmedChildIndices,
            trimmedSpanStarts,
            trimmedSpanLengths
        )
    }

    private static func TryBuild(source: string, out program: ColumnarProgramInput): bool {
        program = null
        tokens: ColumnarTokenizedSource = null
        if !TryTokenizeColumnarSource(source, out tokens) {
            return Decline(ColumnarParseDeclines.Tokenize, -1, 0, "")
        }

        n := tokens.Count
        funcIndices := new int[](n + 1)
        funcAsyncFlags := new int[](n + 1)
        funcGeneratorFlags := new int[](n + 1)
        enumIndices := new int[](n + 1)
        unionIndices := new int[](n + 1)
        interfaceIndices := new int[](n + 1)
        structIndices := new int[](n + 1)
        structReferenceFlags := new int[](n + 1)
        structRecordFlags := new int[](n + 1)
        structVisibilityFlags := new int[](n + 1)
        structEnclosingTypeNames := new string[](n + 1)
        declarationResult := new int[](6)
        declarationRowCount := ColumnarProgramDeclarationIndicesInto(
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
            structIndices,
            structReferenceFlags,
            structRecordFlags,
            structVisibilityFlags,
            structEnclosingTypeNames,
            declarationResult
        )
        if declarationRowCount < 0 {
            return DeclineAtToken(
                ColumnarParseDeclines.DeclarationScan(declarationRowCount),
                tokens.Starts,
                tokens.ValueLengths,
                0,
                ""
            )
        }

        inputs: List<ColumnarFunctionInput> = null
        if !TryGetColumnarFunctionInputs(
            source,
            tokens,
            funcIndices,
            funcAsyncFlags,
            funcGeneratorFlags,
            declarationResult[1],
            out inputs
        ) {
            return Decline(ColumnarParseDeclines.FunctionMaterialization, -1, 0, "")
        }

        enums: List<ColumnarEnumInput> = null
        if !TryGetColumnarEnumInputs(source, tokens, enumIndices, declarationResult[2], out enums) {
            return Decline(ColumnarParseDeclines.EnumMaterialization, -1, 0, "")
        }

        structs: List<ColumnarStructInput> = null
        if !TryGetColumnarStructInputs(
            source,
            tokens,
            structIndices,
            structReferenceFlags,
            structRecordFlags,
            structVisibilityFlags,
            structEnclosingTypeNames,
            declarationResult[5],
            out structs
        ) {
            return Decline(ColumnarParseDeclines.StructMaterialization, -1, 0, "")
        }

        unions: List<ColumnarUnionInput> = null
        if !TryGetColumnarUnionInputs(source, tokens, unionIndices, declarationResult[3], out unions) {
            return Decline(ColumnarParseDeclines.UnionMaterialization, -1, 0, "")
        }

        interfaceInputs: List<ColumnarInterfaceInput> = null
        if !TryGetColumnarInterfaceInputs(source, tokens, interfaceIndices, declarationResult[4], out interfaceInputs) {
            return Decline(ColumnarParseDeclines.InterfaceMaterialization, -1, 0, "")
        }

        testInputs: List<ColumnarTestInput>? = null
        if !TryGetColumnarTestInputs(source, tokens, out testInputs) {
            return Decline(ColumnarParseDeclines.TestMaterialization, -1, 0, "")
        }

        if !TryGetColumnarNewtypeInputs(source, tokens, structs) {
            return Decline(ColumnarParseDeclines.NewtypeMaterialization, -1, 0, "")
        }

        program = ColumnarProgramInput.CreateSingleSource(
            source,
            inputs,
            enums,
            structs,
            unions,
            interfaceInputs,
            testInputs
        )
        return true
    }

    static func TryBuildMultiFile(sources: IReadOnlyList<string>, fileNames: IReadOnlyList<string>, projectRoot: string, out program: ColumnarProgramInput): bool {
        program = null
        sourceFiles := ColumnarEmissionPlanner.BuildSourceFilesFromLists(sources, fileNames)
        programs := new ColumnarProgramInput[](sources.Count)
        i := 0
        while i < sources.Count {
            sourceFileId := sourceFiles[i].FileId
            ColumnarDeclineTrace.SetSourceFileId(sourceFileId)
            try {
                fileProgram: ColumnarProgramInput = null
                if !TryBuild(sources[i], out fileProgram) {
                    return false
                }
                ColumnarProgramInput.AssignSourceFileId(fileProgram, sourceFileId)
                programs[i] = fileProgram
            } finally {
                ColumnarDeclineTrace.ClearSourceFileId()
            }
            i = i + 1
        }

        program = ColumnarProgramInput.MergeSourceFilesAtProjectRoot(sourceFiles, programs, projectRoot)
        return true
    }

    // A newtype is represented by the same readonly record-struct shape the emitter already owns:
    // one `Value` field and one synthesized primary-constructor initializer.
    private static func TryGetColumnarNewtypeInputs(source: string, tokens: ColumnarTokenizedSource, structs: List<ColumnarStructInput>): bool {
        n := tokens.Count
        indices := new int[](n + 1)
        nameStarts := new int[](n + 1)
        nameLengths := new int[](n + 1)
        typeStarts := new int[](n + 1)
        typeLengths := new int[](n + 1)
        scan := new int[](1)
        newtypeCount := TopLevelColumnarNewtypeDeclarationIndicesInto(
            source,
            tokens.Kinds,
            tokens.Starts,
            tokens.ValueLengths,
            n,
            indices,
            nameStarts,
            nameLengths,
            typeStarts,
            typeLengths,
            scan
        )
        if newtypeCount < 0 {
            return Decline(ColumnarParseDeclines.NewtypeScan, -1, 0, "")
        }

        t := 0
        while t < newtypeCount {
            name := source.Substring(nameStarts[t], nameLengths[t])
            underlying := source.Substring(typeStarts[t], typeLengths[t])
            emptyBlockKinds := [25]
            emptyBlockValueStarts := [-1]
            emptyBlockValueLengths := [0]
            emptyBlockChildStarts := [0]
            emptyBlockChildCounts := [0]
            emptyBlockChildIndices: int[] = System.Array.Empty<int>()
            emptyBlockSpanStarts := [0]
            emptyBlockSpanLengths := [0]
            emptyBlock := new ColumnarNodeTable(
                emptyBlockKinds,
                emptyBlockValueStarts,
                emptyBlockValueLengths,
                emptyBlockChildStarts,
                emptyBlockChildCounts,
                emptyBlockChildIndices,
                emptyBlockSpanStarts,
                emptyBlockSpanLengths
            )
            ctorBody := new ColumnarFunctionInput(
                "constructor",
                "void",
                ["Value"],
                [underlying],
                emptyBlock,
                0,
                false,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                false,
                0,
                0,
                false,
                "",
                ""
            )
            ctor := new ColumnarConstructorInput(
                ctorBody,
                0,
                System.Array.Empty<int>(),
                System.Array.Empty<string>(),
                [-1],
                [""],
                true,
                0
            )
            structs.Add(new ColumnarStructInput(
                name,
                ["Value"],
                [underlying],
                System.Array.Empty<ColumnarFunctionInput>(),
                [ctor],
                System.Array.Empty<ColumnarPropertyInput>(),
                false,
                null,
                null,
                null,
                null,
                true,
                null,
                [true],
                0,
                true,
                false,
                null,
                0,
                null,
                null,
                null,
                null
            ))
            t = t + 1
        }
        return true
    }

    private static func TryGetColumnarTestInputs(source: string, tokens: ColumnarTokenizedSource, out tests: List<ColumnarTestInput>?): bool {
        tests = null
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        testIndices := new int[](n + 1)
        testScan := new int[](1)
        testCount := TopLevelColumnarTestDeclarationIndicesInto(source, ck, cs, cv, n, testIndices, testScan)
        if testCount < 0 {
            return Decline(ColumnarParseDeclines.TestScan, -1, 0, "")
        }

        t := 0
        while t < testCount {
            testInput: ColumnarTestInput = null
            if !TryParseColumnarTestAt(ck, cs, cv, n, testIndices[t], source, out testInput) {
                return DeclineAtToken(ColumnarParseDeclines.TestDeclaration, cs, cv, testIndices[t], "")
            }
            if tests == null {
                tests = new List<ColumnarTestInput>()
            }
            tests.Add(testInput)
            t = t + 1
        }
        return true
    }

    private static func TryParseColumnarTestAt(ck: int[], cs: int[], cv: int[], n: int, testIndex: int, source: string, out input: ColumnarTestInput): bool {
        input = null
        cap := n + 1
        bk := new int[](cap)
        bvs := new int[](cap)
        bvl := new int[](cap)
        bcs := new int[](cap)
        bcc := new int[](cap)
        bci := new int[](cap)
        bss := new int[](cap)
        bsl := new int[](cap)
        result := new int[](6)
        bodyNodeCount := ParseColumnarTestInfoInto(
            source,
            ck,
            cs,
            cv,
            n,
            testIndex,
            bk,
            bvs,
            bvl,
            bcs,
            bcc,
            bci,
            bss,
            bsl,
            result
        )
        if bodyNodeCount <= 0 {
            return false
        }

        bodyRoot := result[2]
        if bodyRoot < 0 || bodyRoot >= bodyNodeCount || result[0] < 0 || result[1] <= 0 || result[0] + result[1] > source.Length {
            return false
        }

        description := ColumnarTestCaseLabel(source, result)
        bodyNodes := BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount)
        body := new ColumnarFunctionInput(
            "test " + description,
            "void",
            System.Array.Empty<string>(),
            System.Array.Empty<string>(),
            bodyNodes,
            bodyRoot,
            false,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            false,
            0,
            0,
            false,
            "",
            ""
        )
        input = new ColumnarTestInput(description, body)
        return true
    }

    private static func TryTokenizeColumnarSource(source: string, out tokens: ColumnarTokenizedSource): bool {
        tokens = null
        capacity := 3 * (source.Length + 1) + 8
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        kinds := new int[](capacity)
        starts := new int[](capacity)
        valueLengths := new int[](capacity)
        resultCounts := new int[](2)
        count := TokenizeColumnarSourceInto(
            source,
            rawKinds,
            rawStarts,
            rawValueLengths,
            kinds,
            starts,
            valueLengths,
            resultCounts
        )
        rawCount := resultCounts[0]
        if rawCount < 0 || rawCount > capacity || count < 0 || count > rawCount || count != resultCounts[1] {
            return Decline(ColumnarParseDeclines.TokenizeInvalidResult, -1, 0, "")
        }

        tokens = new ColumnarTokenizedSource(
            rawKinds,
            rawStarts,
            rawValueLengths,
            rawCount,
            kinds,
            starts,
            valueLengths,
            count
        )
        return true
    }

    private static func TryGetColumnarFunctionInputs(source: string, tokens: ColumnarTokenizedSource, funcIndices: int[], funcAsyncFlags: int[], funcGeneratorFlags: int[], funcIndexCount: int, out inputs: List<ColumnarFunctionInput>): bool {
        inputs = new List<ColumnarFunctionInput>()
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        fi := 0
        while fi < funcIndexCount {
            modifierFlags := ColumnarFunctionModifierFlagsForGenerator(funcGeneratorFlags[fi])
            input: ColumnarFunctionInput = null
            if !TryParseColumnarFunctionAt(
                ck,
                cs,
                cv,
                n,
                funcIndices[fi],
                source,
                out input,
                false,
                funcAsyncFlags[fi] == 1,
                false,
                modifierFlags,
                false
            ) {
                return DeclineAtToken(ColumnarParseDeclines.FunctionDeclaration, cs, cv, funcIndices[fi], "")
            }
            inputs.Add(input)
            fi = fi + 1
        }
        return true
    }

    private static func TryGetColumnarEnumInputs(source: string, tokens: ColumnarTokenizedSource, enumIndices: int[], enumIndexCount: int, out enums: List<ColumnarEnumInput>): bool {
        enums = new List<ColumnarEnumInput>()
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        enumSlot := 0
        while enumSlot < enumIndexCount {
            enumIndex := enumIndices[enumSlot]
            cap := n + 1
            outNameTexts := new string[](cap)
            outMemberValues := new int[](cap)
            outMemberStringValues := new string[](cap)
            outEnumNameTexts := new string[](1)
            outResult := new int[](3)
            memberCount := ParseColumnarEnumInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                enumIndex,
                outNameTexts,
                outMemberValues,
                outMemberStringValues,
                outEnumNameTexts,
                outResult
            )
            if memberCount < 0 || outResult[1] <= 0 {
                return DeclineAtToken(ColumnarParseDeclines.EnumDeclaration, cs, cv, enumIndex, "")
            }

            enumName := outEnumNameTexts[0]
            isStringBacked := outResult[2] == 1
            memberNames := new string[](memberCount)
            memberValues := new int[](memberCount)
            memberStringValues := isStringBacked ? new string[](memberCount) : System.Array.Empty<string>()
            m := 0
            while m < memberCount {
                memberName := outNameTexts[m]
                memberNames[m] = memberName
                memberValues[m] = outMemberValues[m]
                if isStringBacked {
                    rawValue := outMemberStringValues[m]
                    memberStringValues[m] = StringLiteralDecoder.Decode(rawValue ?? memberName, false)
                }
                m = m + 1
            }
            enums.Add(new ColumnarEnumInput(
                enumName,
                memberNames,
                memberValues,
                isStringBacked,
                memberStringValues,
                0
            ))
            enumSlot = enumSlot + 1
        }
        return true
    }

    private static func TryGetColumnarStructInputs(source: string, tokens: ColumnarTokenizedSource, declIndices: int[], declReferenceFlags: int[], declRecordFlags: int[], declVisibilityFlags: int[], declEnclosingTypeNames: string[], declCount: int, out structs: List<ColumnarStructInput>): bool {
        structs = new List<ColumnarStructInput>()
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        if declCount < 0 {
            return Decline(ColumnarParseDeclines.StructInvalidCount, -1, 0, "")
        }
        declSlot := 0
        while declSlot < declCount {
            structIndex := declIndices[declSlot]
            isReference := declReferenceFlags[declSlot] == 1
            isRecord := declRecordFlags[declSlot] == 1
            isRefStruct := !isReference && structIndex > 0 && ColumnarTokenKindFacts.IsRefStructModifierKind(ck[structIndex - 1])
            cap := n + 1
            outFieldNameTexts := new string[](cap)
            outFieldTypeTexts := new string[](cap)
            outFieldStaticFlags := new int[](cap)
            outFieldInitKinds := new int[](cap)
            outFieldInitTexts := new string[](cap)
            outMethodFuncIndices := new int[](cap)
            outMethodStaticFlags := new int[](cap)
            outCtorIndices := new int[](cap)
            outPropIndices := new int[](cap)
            outPropStaticFlags := new int[](cap)
            outTypeParamTexts := new string[](cap)
            outBaseNameTexts := new string[](cap)
            outStructNameTexts := new string[](1)
            outWhereOwnerTexts := new string[](cap)
            outWhereItemCodes := new int[](cap)
            outWhereTypeTexts := new string[](cap)
            outResult := new int[](11)
            fieldCount := ParseColumnarStructInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                structIndex,
                isReference ? 1 : 0,
                isRecord ? 1 : 0,
                outFieldNameTexts,
                outFieldTypeTexts,
                outFieldStaticFlags,
                outFieldInitKinds,
                outFieldInitTexts,
                outMethodFuncIndices,
                outMethodStaticFlags,
                outCtorIndices,
                outPropIndices,
                outPropStaticFlags,
                outTypeParamTexts,
                outBaseNameTexts,
                outStructNameTexts,
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                outResult
            )
            if fieldCount < 0 || outResult[1] <= 0 {
                return DeclineAtToken(ColumnarParseDeclines.StructDeclaration, cs, cv, structIndex, "")
            }

            structName := outStructNameTexts[0]
            baseNames := ColumnarConstraintColumns.TrimTexts(outBaseNameTexts, outResult[8])
            typeParamCount := outResult[7]
            typeParamNames := ColumnarConstraintColumns.TrimTexts(outTypeParamTexts, typeParamCount)
            whereRowCount := outResult[10]
            typeParamSpecials := ColumnarConstraintColumns.BuildSpecials(
                outWhereOwnerTexts,
                outWhereItemCodes,
                typeParamNames,
                whereRowCount
            )
            typeParamTypeConstraints := ColumnarConstraintColumns.BuildTypeConstraints(
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                typeParamNames,
                whereRowCount
            )

            fieldColumns := ColumnarStructFieldColumns.Build(
                outFieldNameTexts,
                outFieldTypeTexts,
                outFieldStaticFlags,
                outFieldInitKinds,
                outFieldInitTexts,
                fieldCount
            )
            fieldNames := fieldColumns.FieldNames
            fieldTypes := fieldColumns.FieldTypeCanonicals
            fieldStatics := fieldColumns.FieldStaticFlags
            fieldReadonlyFlags := fieldColumns.FieldReadonlyFlags
            fieldPrivateFlags := fieldColumns.FieldPrivateFlags
            fieldThreadStaticFlags := fieldColumns.FieldThreadStaticFlags
            fieldInitKinds := fieldColumns.FieldInitKinds
            fieldInitTexts := fieldColumns.FieldInitTexts

            methodCount := outResult[2]
            methods := new List<ColumnarFunctionInput>(methodCount)
            m := 0
            while m < methodCount {
                methodModifierFlags := outMethodStaticFlags[m]
                methodInput: ColumnarFunctionInput = null
                if !TryParseColumnarFunctionAt(
                    ck,
                    cs,
                    cv,
                    n,
                    outMethodFuncIndices[m],
                    source,
                    out methodInput,
                    ColumnarStructMethodFlagIsStatic(methodModifierFlags),
                    ColumnarStructMethodFlagIsAsync(methodModifierFlags),
                    false,
                    methodModifierFlags,
                    ColumnarFunctionInput.HasNativeImportModifier(methodModifierFlags)
                ) {
                    return DeclineAtToken(
                        ColumnarParseDeclines.StructMethod,
                        cs,
                        cv,
                        outMethodFuncIndices[m],
                        structName
                    )
                }
                methods.Add(methodInput)
                m = m + 1
            }

            ctorCount := outResult[3]
            constructors := new List<ColumnarConstructorInput>(ctorCount)
            c := 0
            while c < ctorCount {
                ctorInput: ColumnarConstructorInput = null
                if !TryParseColumnarConstructorAt(ck, cs, cv, n, outCtorIndices[c], source, out ctorInput) {
                    return DeclineAtToken(
                        ColumnarParseDeclines.StructConstructor,
                        cs,
                        cv,
                        outCtorIndices[c],
                        structName
                    )
                }
                constructors.Add(ctorInput)
                c = c + 1
            }

            propCount := outResult[4]
            properties := new List<ColumnarPropertyInput>(propCount)
            pr := 0
            while pr < propCount {
                propInput: ColumnarPropertyInput = null
                if !TryParseColumnarPropertyAt(
                    ck,
                    cs,
                    cv,
                    n,
                    outPropIndices[pr],
                    source,
                    out propInput,
                    outPropStaticFlags[pr] == 1
                ) {
                    return DeclineAtToken(
                        ColumnarParseDeclines.StructProperty,
                        cs,
                        cv,
                        outPropIndices[pr],
                        structName
                    )
                }
                properties.Add(propInput)
                pr = pr + 1
            }

            structs.Add(new ColumnarStructInput(
                structName,
                fieldNames,
                fieldTypes,
                methods,
                constructors,
                properties,
                isReference,
                baseNames,
                fieldStatics,
                fieldInitKinds,
                fieldInitTexts,
                isRecord,
                typeParamNames,
                fieldReadonlyFlags,
                0,
                false,
                isRefStruct,
                declEnclosingTypeNames[declSlot] ?? "",
                declVisibilityFlags[declSlot],
                typeParamSpecials,
                typeParamTypeConstraints,
                fieldPrivateFlags,
                fieldThreadStaticFlags
            ))
            declSlot = declSlot + 1
        }
        return true
    }

    private static func TryGetColumnarUnionInputs(source: string, tokens: ColumnarTokenizedSource, unionIndices: int[], unionIndexCount: int, out unions: List<ColumnarUnionInput>): bool {
        unions = new List<ColumnarUnionInput>()
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        unionSlot := 0
        while unionSlot < unionIndexCount {
            unionIndex := unionIndices[unionSlot]
            cap := n + 1
            outCaseNameTexts := new string[](cap)
            outCaseFieldCounts := new int[](cap)
            outFieldNameTexts := new string[](cap)
            outFieldTypeTexts := new string[](cap)
            outTypeParamTexts := new string[](cap)
            outUnionNameTexts := new string[](1)
            outWhereOwnerTexts := new string[](cap)
            outWhereItemCodes := new int[](cap)
            outWhereTypeTexts := new string[](cap)
            outResult := new int[](6)
            caseCount := ParseColumnarUnionInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                unionIndex,
                outCaseNameTexts,
                outCaseFieldCounts,
                outFieldNameTexts,
                outFieldTypeTexts,
                outTypeParamTexts,
                outUnionNameTexts,
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                outResult
            )
            if caseCount <= 0 || outResult[1] <= 0 {
                return DeclineAtToken(ColumnarParseDeclines.UnionDeclaration, cs, cv, unionIndex, "")
            }

            unionName := outUnionNameTexts[0]
            typeParamCount := outResult[2]
            isValueStruct := ColumnarUnionIsValueStructEmittable(outCaseFieldCounts, caseCount, typeParamCount) == 1
            typeParamNames: string[]? = null
            if typeParamCount > 0 {
                typeParamNames = ColumnarConstraintColumns.TrimTexts(outTypeParamTexts, typeParamCount)
            }

            caseNames := new string[](caseCount)
            caseFieldNames := new string[][](caseCount)
            caseFieldTypes := new string[][](caseCount)
            fieldCursor := 0
            c := 0
            while c < caseCount {
                caseName := outCaseNameTexts[c]
                caseNames[c] = caseName
                fc := outCaseFieldCounts[c]
                names := new string[](fc)
                types := new string[](fc)
                f := 0
                while f < fc {
                    fieldName := outFieldNameTexts[fieldCursor]
                    names[f] = fieldName
                    fieldType := outFieldTypeTexts[fieldCursor]
                    types[f] = fieldType
                    fieldCursor = fieldCursor + 1
                    f = f + 1
                }
                caseFieldNames[c] = names
                caseFieldTypes[c] = types
                c = c + 1
            }

            unionTypeParams := typeParamNames ?? System.Array.Empty<string>()
            unionSpecials := ColumnarConstraintColumns.BuildSpecials(
                outWhereOwnerTexts,
                outWhereItemCodes,
                unionTypeParams,
                outResult[5]
            )
            unionConstraints := ColumnarConstraintColumns.BuildTypeConstraints(
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                unionTypeParams,
                outResult[5]
            )
            unions.Add(new ColumnarUnionInput(
                unionName,
                caseNames,
                caseFieldNames,
                caseFieldTypes,
                typeParamNames,
                isValueStruct,
                0,
                unionSpecials,
                unionConstraints
            ))
            unionSlot = unionSlot + 1
        }
        return true
    }

    private static func TryParseColumnarFunctionAt(ck: int[], cs: int[], cv: int[], n: int, funcIndex: int, source: string, out input: ColumnarFunctionInput, isStatic: bool = false, isAsync: bool = false, isLocalFunction: bool = false, modifierFlags: int = 0, isBodylessNativeImport: bool = false): bool {
        input = null
        cap := n + 1

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](cap)
        paramTypeTexts := new string[](cap)
        paramModifierKinds := new int[](cap)
        paramDefaultKinds := new int[](cap)
        paramDefaultTexts := new string[](cap)
        Array.Fill(paramDefaultKinds, -1)
        paramTupleNameCounts := new int[](cap)
        paramTupleNameTexts := new string[](cap)
        returnTupleNameTexts := new string[](cap)
        typeParamTexts := new string[](cap)
        typeParamSpecials := new int[](cap)
        typeParamConstraintCounts := new int[](cap)
        typeParamConstraintTypeTexts := new string[](cap)
        bk := new int[](cap)
        bvs := new int[](cap)
        bvl := new int[](cap)
        bcs := new int[](cap)
        bcc := new int[](cap)
        bci := new int[](cap)
        bss := new int[](cap)
        bsl := new int[](cap)
        localFunctionNodeIndices := new int[](cap)
        localFunctionTokenIndices := new int[](cap)
        result := new int[](9)

        paramCount := 0
        if isBodylessNativeImport {
            paramCount = ParseColumnarProductFunctionSignatureInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                funcIndex,
                functionNameTexts,
                returnTypeTexts,
                paramNameTexts,
                paramTypeTexts,
                paramModifierKinds,
                paramDefaultKinds,
                paramDefaultTexts,
                paramTupleNameCounts,
                paramTupleNameTexts,
                returnTupleNameTexts,
                typeParamTexts,
                typeParamSpecials,
                typeParamConstraintCounts,
                typeParamConstraintTypeTexts,
                result
            )
        } else {
            paramCount = ParseColumnarProductFunctionInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                funcIndex,
                isLocalFunction ? 1 : 0,
                functionNameTexts,
                returnTypeTexts,
                paramNameTexts,
                paramTypeTexts,
                paramModifierKinds,
                paramDefaultKinds,
                paramDefaultTexts,
                paramTupleNameCounts,
                paramTupleNameTexts,
                returnTupleNameTexts,
                typeParamTexts,
                typeParamSpecials,
                typeParamConstraintCounts,
                typeParamConstraintTypeTexts,
                bk,
                bvs,
                bvl,
                bcs,
                bcc,
                bci,
                bss,
                bsl,
                localFunctionNodeIndices,
                localFunctionTokenIndices,
                result
            )
        }
        if paramCount < 0 {
            return DeclineAtToken(ColumnarParseDeclines.FunctionBodyOrSignature, cs, cv, funcIndex, "")
        }

        functionName := functionNameTexts[0]
        returnCanonical := returnTypeTexts[0]
        paramNames := new string[](paramCount)
        paramCanonicals := new string[](paramCount)
        parsedParamModifierKinds := new int[](paramCount)
        parsedParamDefaultKinds := new int[](paramCount)
        parsedParamDefaultTexts := new string[](paramCount)
        paramTupleNames: string[][]? = null
        flatParamTupleNameIndex := 0
        p := 0
        while p < paramCount {
            paramName := paramNameTexts[p]
            paramType := paramTypeTexts[p]
            paramNames[p] = paramName
            paramCanonicals[p] = paramType
            parsedParamModifierKinds[p] = paramModifierKinds[p]
            parsedParamDefaultKinds[p] = paramDefaultKinds[p]
            parsedParamDefaultTexts[p] = paramDefaultKinds[p] >= 0 ? paramDefaultTexts[p] : ""
            tupleNameCount := paramTupleNameCounts[p]
            if tupleNameCount < 0 || flatParamTupleNameIndex + tupleNameCount > paramTupleNameTexts.Length {
                return DeclineAtToken(
                    ColumnarParseDeclines.FunctionParameterTupleNames,
                    cs,
                    cv,
                    funcIndex,
                    functionName
                )
            }
            if tupleNameCount > 0 {
                tupleNames := new string[](tupleNameCount)
                Array.Copy(paramTupleNameTexts, flatParamTupleNameIndex, tupleNames, 0, tupleNameCount)
                if paramTupleNames == null {
                    paramTupleNames = new string[][](paramCount)
                }
                paramTupleNames[p] = tupleNames
            }
            flatParamTupleNameIndex = flatParamTupleNameIndex + tupleNameCount
            p = p + 1
        }

        returnTupleNames: string[]? = null
        returnTupleNameCount := result[0]
        if returnTupleNameCount < 0 || returnTupleNameCount > returnTupleNameTexts.Length {
            return DeclineAtToken(
                ColumnarParseDeclines.FunctionReturnTupleNames,
                cs,
                cv,
                funcIndex,
                functionName
            )
        }
        if returnTupleNameCount > 0 {
            returnTupleNames = new string[](returnTupleNameCount)
            Array.Copy(returnTupleNameTexts, returnTupleNames, returnTupleNameCount)
        }

        bodyBrace := result[1]
        if !isBodylessNativeImport && (bodyBrace < 0 || bodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBodyStartKind(ck[bodyBrace])) {
            return DeclineAtToken(ColumnarParseDeclines.FunctionBody, cs, cv, funcIndex, functionName)
        }

        typeParamNames := System.Array.Empty<string>()
        typeParamCount := result[2]
        if typeParamCount > 0 {
            typeParamNames = new string[](typeParamCount)
            t := 0
            while t < typeParamCount {
                typeParamName := typeParamTexts[t]
                typeParamNames[t] = typeParamName
                t = t + 1
            }
        }

        whereItemCount := result[5]
        parsedTypeParamSpecials: int[]? = null
        typeParamTypeConstraints: string[][]? = null
        if whereItemCount > 0 {
            if typeParamNames.Length == 0 {
                return DeclineAtToken(
                    ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters,
                    cs,
                    cv,
                    funcIndex,
                    functionName
                )
            }
            parsedTypeParamSpecials = new int[](typeParamCount)
            typeParamTypeConstraints = new string[][](typeParamNames.Length)
            flatTypeConstraintIndex := 0
            t := 0
            while t < typeParamNames.Length {
                parsedTypeParamSpecials[t] = typeParamSpecials[t]
                constraintCount := typeParamConstraintCounts[t]
                if constraintCount < 0 || flatTypeConstraintIndex + constraintCount > typeParamConstraintTypeTexts.Length {
                    return DeclineAtToken(
                        ColumnarParseDeclines.FunctionConstraintMetadata,
                        cs,
                        cv,
                        funcIndex,
                        functionName
                    )
                }
                constraints := new string[](constraintCount)
                c := 0
                while c < constraintCount {
                    constraint := typeParamConstraintTypeTexts[flatTypeConstraintIndex + c]
                    constraints[c] = constraint
                    c = c + 1
                }
                typeParamTypeConstraints[t] = constraints
                flatTypeConstraintIndex = flatTypeConstraintIndex + constraintCount
                t = t + 1
            }
        }

        rootBlock := result[6]
        bodyNodeCount := result[7]
        if !isBodylessNativeImport && (bodyNodeCount <= 0 || rootBlock < 0 || rootBlock >= bodyNodeCount) {
            return DeclineAtToken(ColumnarParseDeclines.FunctionBodyNodes, cs, cv, funcIndex, functionName)
        }

        bodyNodes: ColumnarNodeTable = null
        if isBodylessNativeImport {
            bodyNodes = new ColumnarNodeTable(
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>(),
                System.Array.Empty<int>()
            )
        } else {
            bodyNodes = BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount)
        }

        nativeImportLibraryName := ""
        nativeImportEntryPoint := ""
        if isBodylessNativeImport {
            nativeImportTexts := new string[](2)
            if ParseColumnarNativeImportInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                funcIndex,
                functionName,
                nativeImportTexts
            ) != 1 {
                return DeclineAtToken(ColumnarParseDeclines.FunctionNativeImport, cs, cv, funcIndex, functionName)
            }
            nativeImportLibraryName = nativeImportTexts[0]
            nativeImportEntryPoint = nativeImportTexts[1]
            rootBlock = -1
            bodyNodeCount = 0
        }

        parsedInput := new ColumnarFunctionInput(
            functionName,
            returnCanonical,
            paramNames,
            paramCanonicals,
            bodyNodes,
            rootBlock,
            isStatic,
            typeParamNames,
            parsedTypeParamSpecials,
            typeParamTypeConstraints,
            returnTupleNames,
            paramTupleNames,
            parsedParamModifierKinds,
            parsedParamDefaultKinds,
            parsedParamDefaultTexts,
            isAsync,
            modifierFlags,
            0,
            isBodylessNativeImport,
            nativeImportLibraryName,
            nativeImportEntryPoint
        )
        input = parsedInput

        localFunctionCount := result[8]
        if localFunctionCount < 0 || localFunctionCount > localFunctionNodeIndices.Length {
            return DeclineAtToken(
                ColumnarParseDeclines.FunctionLocalFunctionMetadata,
                cs,
                cv,
                funcIndex,
                functionName
            )
        }
        lf := 0
        while lf < localFunctionCount {
            localFn: ColumnarFunctionInput = null
            if !TryParseColumnarFunctionAt(
                ck,
                cs,
                cv,
                n,
                localFunctionTokenIndices[lf],
                source,
                out localFn,
                false,
                false,
                true,
                0,
                false
            ) {
                return DeclineAtToken(
                    ColumnarParseDeclines.LocalFunction,
                    cs,
                    cv,
                    localFunctionTokenIndices[lf],
                    functionName
                )
            }
            if parsedInput.LocalFunctions == null {
                parsedInput.LocalFunctions = new List<ColumnarLocalFunctionInput>()
            }
            parsedInput.LocalFunctions.Add(new ColumnarLocalFunctionInput(localFunctionNodeIndices[lf], localFn))
            lf = lf + 1
        }
        return true
    }

    private static func TryParseColumnarConstructorAt(ck: int[], cs: int[], cv: int[], n: int, ctorIndex: int, source: string, out input: ColumnarConstructorInput): bool {
        input = null
        cap := (n + 1) * 4
        paramNameTexts := new string[](cap)
        paramTypeTexts := new string[](cap)
        caKinds := new int[](cap)
        caStarts := new int[](cap)
        caLengths := new int[](cap)
        caTexts := new string[](cap)
        bk := new int[](cap)
        bvs := new int[](cap)
        bvl := new int[](cap)
        bcs := new int[](cap)
        bcc := new int[](cap)
        bci := new int[](cap)
        bss := new int[](cap)
        bsl := new int[](cap)
        ctorResult := new int[](6)
        paramCount := ParseColumnarConstructorInfoInto(
            source,
            ck,
            cs,
            cv,
            n,
            ctorIndex,
            paramNameTexts,
            paramTypeTexts,
            caKinds,
            caStarts,
            caLengths,
            caTexts,
            bk,
            bvs,
            bvl,
            bcs,
            bcc,
            bci,
            bss,
            bsl,
            ctorResult
        )
        if paramCount < 0 {
            return DeclineAtToken(ColumnarParseDeclines.Constructor, cs, cv, ctorIndex, "constructor")
        }

        paramNames := new string[](paramCount)
        paramCanonicals := new string[](paramCount)
        parsedParamDefaultKinds := new int[](paramCount)
        parsedParamDefaultTexts := new string[](paramCount)
        p := 0
        while p < paramCount {
            paramName := paramNameTexts[p]
            paramNames[p] = paramName
            paramCanonical := paramTypeTexts[p]
            paramCanonicals[p] = paramCanonical
            parsedParamDefaultKinds[p] = caKinds[p]
            parsedParamDefaultTexts[p] = caKinds[p] >= 0 ? caTexts[p] : ""
            p = p + 1
        }

        bodyBrace := ctorResult[1]
        if bodyBrace < 0 || bodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(ck[bodyBrace]) {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorBody, cs, cv, ctorIndex, "constructor")
        }
        chainArgCount := ctorResult[3]
        if chainArgCount < 0 {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorChain, cs, cv, ctorIndex, "constructor")
        }

        bodyRoot := ctorResult[4]
        bodyNodeCount := ctorResult[5]
        if bodyNodeCount <= 0 || bodyRoot < 0 || bodyRoot >= bodyNodeCount {
            return DeclineAtToken(ColumnarParseDeclines.ConstructorBodyNodes, cs, cv, ctorIndex, "constructor")
        }

        chainArgKinds := new int[](chainArgCount)
        chainArgTexts := new string[](chainArgCount)
        a := 0
        while a < chainArgCount {
            chainArgIndex := paramCount + a
            chainArgKinds[a] = caKinds[chainArgIndex]
            chainArgText := caTexts[chainArgIndex]
            chainArgTexts[a] = chainArgText
            a = a + 1
        }

        bodyNodes := BuildTrimmedNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bodyNodeCount)
        body := new ColumnarFunctionInput(
            "constructor",
            "void",
            paramNames,
            paramCanonicals,
            bodyNodes,
            bodyRoot,
            false,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            false,
            0,
            0,
            false,
            "",
            ""
        )
        isSynthesizedInitializer := ctorIndex >= 0 && ctorIndex < n && ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(ck[ctorIndex])
        parsedInput := new ColumnarConstructorInput(
            body,
            ctorResult[0],
            chainArgKinds,
            chainArgTexts,
            parsedParamDefaultKinds,
            parsedParamDefaultTexts,
            isSynthesizedInitializer,
            0
        )
        input = parsedInput
        parsedInput.VisibilityModifierFlags = ColumnarConstructorDeclarationMetadataModifierFlagsAt(ck, ctorIndex)
        return true
    }

    private static func TryParseColumnarPropertyAt(ck: int[], cs: int[], cv: int[], n: int, propIndex: int, source: string, out input: ColumnarPropertyInput, isStatic: bool = false): bool {
        input = null
        cap := n + 1
        gk := new int[](cap)
        gvs := new int[](cap)
        gvl := new int[](cap)
        gcs := new int[](cap)
        gcc := new int[](cap)
        gci := new int[](cap)
        gss := new int[](cap)
        gsl := new int[](cap)
        stk := new int[](cap)
        stvs := new int[](cap)
        stvl := new int[](cap)
        stcs := new int[](cap)
        stcc := new int[](cap)
        stci := new int[](cap)
        stss := new int[](cap)
        stsl := new int[](cap)
        propInfo := new int[](10)
        propNameTexts := new string[](1)
        propTypeTexts := new string[](1)
        accessorKind := ParseColumnarPropertyInfoInto(
            source,
            ck,
            cs,
            cv,
            n,
            propIndex,
            propNameTexts,
            propTypeTexts,
            gk,
            gvs,
            gvl,
            gcs,
            gcc,
            gci,
            gss,
            gsl,
            stk,
            stvs,
            stvl,
            stcs,
            stcc,
            stci,
            stss,
            stsl,
            propInfo
        )
        if accessorKind < 0 {
            return DeclineAtToken(ColumnarParseDeclines.PropertyDeclaration, cs, cv, propIndex, "")
        }

        propName := propNameTexts[0]
        propType := propTypeTexts[0]
        getBodyBrace := propInfo[4]
        if getBodyBrace < 0 || getBodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBodyStartKind(ck[getBodyBrace]) {
            return DeclineAtToken(ColumnarParseDeclines.PropertyGetter, cs, cv, propIndex, propName)
        }
        getBodyRoot := propInfo[6]
        getBodyNodeCount := propInfo[7]
        if getBodyNodeCount <= 0 || getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount {
            return DeclineAtToken(ColumnarParseDeclines.PropertyGetterNodes, cs, cv, propIndex, propName)
        }
        getterNodes := BuildTrimmedNodeTable(gk, gvs, gvl, gcs, gcc, gci, gss, gsl, getBodyNodeCount)
        getter := new ColumnarFunctionInput(
            "get_" + propName,
            propType,
            System.Array.Empty<string>(),
            System.Array.Empty<string>(),
            getterNodes,
            getBodyRoot,
            false,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            false,
            0,
            0,
            false,
            "",
            ""
        )

        setter: ColumnarFunctionInput? = null
        if accessorKind == 1 {
            setBodyBrace := propInfo[5]
            if setBodyBrace < 0 || setBodyBrace >= n || !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(ck[setBodyBrace]) {
                return DeclineAtToken(ColumnarParseDeclines.PropertySetter, cs, cv, propIndex, propName)
            }
            setBodyRoot := propInfo[8]
            setBodyNodeCount := propInfo[9]
            if setBodyNodeCount <= 0 || setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount {
                return DeclineAtToken(ColumnarParseDeclines.PropertySetterNodes, cs, cv, propIndex, propName)
            }
            setterNodes := BuildTrimmedNodeTable(stk, stvs, stvl, stcs, stcc, stci, stss, stsl, setBodyNodeCount)
            setter = new ColumnarFunctionInput(
                "set_" + propName,
                "void",
                ["value"],
                [propType],
                setterNodes,
                setBodyRoot,
                false,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                false,
                0,
                0,
                false,
                "",
                ""
            )
        } else if accessorKind != 0 {
            return DeclineAtToken(ColumnarParseDeclines.PropertyAccessorKind, cs, cv, propIndex, propName)
        }

        input = new ColumnarPropertyInput(propName, propType, getter, setter, isStatic, 0)
        return true
    }

    private static func TryGetColumnarInterfaceInputs(source: string, tokens: ColumnarTokenizedSource, interfaceIndices: int[], interfaceIndexCount: int, out interfaceInputs: List<ColumnarInterfaceInput>): bool {
        interfaceInputs = new List<ColumnarInterfaceInput>()
        ck := tokens.Kinds
        cs := tokens.Starts
        cv := tokens.ValueLengths
        n := tokens.Count

        interfaceSlot := 0
        while interfaceSlot < interfaceIndexCount {
            interfaceIndex := interfaceIndices[interfaceSlot]
            cap := n + 1
            outMethodFuncIndices := new int[](cap)
            outBaseNameTexts := new string[](cap)
            outInterfaceNameTexts := new string[](1)
            outMethodNameTexts := new string[](cap)
            outMethodReturnTexts := new string[](cap)
            outMethodParamCounts := new int[](cap)
            outMethodBodyFlags := new int[](cap)
            outMethodParamNameTexts := new string[](cap)
            outMethodParamTypeTexts := new string[](cap)
            outMethodParamModifierKinds := new int[](cap)
            outTypeParamTexts := new string[](cap)
            outWhereOwnerTexts := new string[](cap)
            outWhereItemCodes := new int[](cap)
            outWhereTypeTexts := new string[](cap)
            outResult := new int[](8)
            methodCount := ParseColumnarInterfaceInfoInto(
                source,
                ck,
                cs,
                cv,
                n,
                interfaceIndex,
                outMethodFuncIndices,
                outBaseNameTexts,
                outInterfaceNameTexts,
                outMethodNameTexts,
                outMethodReturnTexts,
                outMethodParamCounts,
                outMethodBodyFlags,
                outMethodParamNameTexts,
                outMethodParamTypeTexts,
                outMethodParamModifierKinds,
                outTypeParamTexts,
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                outResult
            )
            if methodCount < 0 {
                return DeclineAtToken(ColumnarParseDeclines.InterfaceDeclaration, cs, cv, interfaceIndex, "")
            }

            interfaceName := outInterfaceNameTexts[0]
            baseInterfaceNames := ColumnarConstraintColumns.TrimTexts(outBaseNameTexts, outResult[2])
            typeParamCount := outResult[4]
            if typeParamCount < 0 || typeParamCount > outTypeParamTexts.Length {
                return DeclineAtToken(
                    ColumnarParseDeclines.InterfaceTypeParameterMetadata,
                    cs,
                    cv,
                    interfaceIndex,
                    interfaceName
                )
            }
            typeParamNames := new string[](typeParamCount)
            tp := 0
            while tp < typeParamCount {
                if string.IsNullOrWhiteSpace(outTypeParamTexts[tp]) {
                    return DeclineAtToken(
                        ColumnarParseDeclines.InterfaceTypeParameterName,
                        cs,
                        cv,
                        interfaceIndex,
                        interfaceName
                    )
                }
                typeParamNames[tp] = outTypeParamTexts[tp]
                tp = tp + 1
            }

            methodNames := new string[](methodCount)
            methodReturns := new string[](methodCount)
            methodParamNames := new string[][](methodCount)
            methodParamCanonicals := new string[][](methodCount)
            methodParamModifierKinds := new int[][](methodCount)
            methodBodies := new ColumnarFunctionInput?[](methodCount)
            flatParamCount := outResult[3]
            if flatParamCount < 0 {
                return DeclineAtToken(
                    ColumnarParseDeclines.InterfaceFlatParameterMetadata,
                    cs,
                    cv,
                    interfaceIndex,
                    interfaceName
                )
            }
            paramCursor := 0
            m := 0
            while m < methodCount {
                methodName := outMethodNameTexts[m]
                methodNames[m] = methodName
                methodReturns[m] = outMethodReturnTexts[m]
                paramCount := outMethodParamCounts[m]
                if paramCount < 0 || paramCursor + paramCount > flatParamCount {
                    return DeclineAtToken(
                        ColumnarParseDeclines.InterfaceMethodParameterMetadata,
                        cs,
                        cv,
                        interfaceIndex,
                        interfaceName + "." + methodName
                    )
                }
                methodParamNames[m] = new string[](paramCount)
                methodParamCanonicals[m] = new string[](paramCount)
                methodParamModifierKinds[m] = new int[](paramCount)
                p := 0
                while p < paramCount {
                    flatSlot := paramCursor + p
                    methodParamNames[m][p] = outMethodParamNameTexts[flatSlot]
                    methodParamCanonicals[m][p] = outMethodParamTypeTexts[flatSlot]
                    methodParamModifierKinds[m][p] = outMethodParamModifierKinds[flatSlot]
                    p = p + 1
                }
                paramCursor = paramCursor + paramCount
                if outMethodBodyFlags[m] == 1 {
                    bodyInput: ColumnarFunctionInput = null
                    if !TryParseColumnarFunctionAt(
                        ck,
                        cs,
                        cv,
                        n,
                        outMethodFuncIndices[m],
                        source,
                        out bodyInput,
                        false,
                        false,
                        false,
                        0,
                        false
                    ) {
                        return DeclineAtToken(
                            ColumnarParseDeclines.InterfaceMethodBody,
                            cs,
                            cv,
                            outMethodFuncIndices[m],
                            interfaceName + "." + methodName
                        )
                    }
                    methodBodies[m] = bodyInput
                } else if outMethodBodyFlags[m] != 0 {
                    return DeclineAtToken(
                        ColumnarParseDeclines.InterfaceMethodBodyFlag,
                        cs,
                        cv,
                        interfaceIndex,
                        interfaceName + "." + methodName
                    )
                }
                m = m + 1
            }
            if paramCursor != flatParamCount {
                return DeclineAtToken(
                    ColumnarParseDeclines.InterfaceParameterCount,
                    cs,
                    cv,
                    interfaceIndex,
                    interfaceName
                )
            }

            interfaceSpecials := ColumnarConstraintColumns.BuildSpecials(
                outWhereOwnerTexts,
                outWhereItemCodes,
                typeParamNames,
                outResult[6]
            )
            interfaceConstraints := ColumnarConstraintColumns.BuildTypeConstraints(
                outWhereOwnerTexts,
                outWhereItemCodes,
                outWhereTypeTexts,
                typeParamNames,
                outResult[6]
            )
            interfaceInputs.Add(new ColumnarInterfaceInput(
                interfaceName,
                baseInterfaceNames,
                methodNames,
                methodReturns,
                methodParamNames,
                methodParamCanonicals,
                methodBodies,
                typeParamNames,
                0,
                methodParamModifierKinds,
                interfaceSpecials,
                interfaceConstraints
            ))
            interfaceSlot = interfaceSlot + 1
        }
        return true
    }
}
