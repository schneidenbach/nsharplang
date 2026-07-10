namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic

public class ColumnarEnumInput {
    nameValue: string
    memberNamesValue: string[]
    memberValuesValue: int[]
    isStringBackedValue: bool
    memberStringValuesValue: string[]
    SourceFileId: int

    Name: string => nameValue
    MemberNames: string[] => memberNamesValue
    MemberValues: int[] => memberValuesValue
    IsStringBacked: bool => isStringBackedValue
    MemberStringValues: string[] => memberStringValuesValue

    constructor(
        name: string,
        memberNames: string[],
        memberValues: int[],
        isStringBacked: bool = false,
        memberStringValues: string[]? = null,
        sourceFileId: int = 0) {
        nameValue = name
        memberNamesValue = memberNames
        memberValuesValue = memberValues
        isStringBackedValue = isStringBacked
        memberStringValuesValue = memberStringValues ?? new string[](0)
        SourceFileId = sourceFileId
    }
}

public class ColumnarUnionInput {
    nameValue: string
    caseNamesValue: string[]
    caseFieldNamesValue: string[][]
    caseFieldTypeCanonicalsValue: string[][]
    typeParamNamesValue: string[]
    isValueStructValue: bool
    SourceFileId: int

    Name: string => nameValue
    CaseNames: string[] => caseNamesValue
    CaseFieldNames: string[][] => caseFieldNamesValue
    CaseFieldTypeCanonicals: string[][] => caseFieldTypeCanonicalsValue
    TypeParamNames: string[] => typeParamNamesValue
    IsValueStruct: bool => isValueStructValue

    constructor(
        name: string,
        caseNames: string[],
        caseFieldNames: string[][],
        caseFieldTypeCanonicals: string[][],
        typeParamNames: string[]? = null,
        isValueStruct: bool = false,
        sourceFileId: int = 0) {
        nameValue = name
        caseNamesValue = caseNames
        caseFieldNamesValue = caseFieldNames
        caseFieldTypeCanonicalsValue = caseFieldTypeCanonicals
        typeParamNamesValue = typeParamNames ?? new string[](0)
        isValueStructValue = isValueStruct
        SourceFileId = sourceFileId
    }
}

public class ColumnarFunctionInput {
    Name: string
    ReturnCanonical: string
    ParamNames: string[]
    ParamCanonicals: string[]
    ParamModifierKinds: int[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    BodyNodes: ColumnarNodeTable
    BodyRoot: int
    IsStatic: bool
    IsAsync: bool
    ReturnTupleElementNames: string[]?
    ParamTupleElementNames: string[][]?
    TypeParamNames: string[]
    TypeParamSpecialConstraints: int[]
    TypeParamTypeConstraints: string[][]
    ModifierFlags: int
    SourceFileId: int
    IsBodylessNativeImport: bool
    NativeImportLibraryName: string
    NativeImportEntryPoint: string
    public LocalFunctions: List<ColumnarLocalFunctionInput>?

    constructor(
        name: string,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        bodyNodes: ColumnarNodeTable,
        bodyRoot: int,
        isStatic: bool = false,
        typeParamNames: string[]? = null,
        typeParamSpecialConstraints: int[]? = null,
        typeParamTypeConstraints: string[][]? = null,
        returnTupleElementNames: string[]? = null,
        paramTupleElementNames: string[][]? = null,
        paramModifierKinds: int[]? = null,
        paramDefaultKinds: int[]? = null,
        paramDefaultTexts: string[]? = null,
        isAsync: bool = false,
        modifierFlags: int = 0,
        sourceFileId: int = 0,
        isBodylessNativeImport: bool = false,
        nativeImportLibraryName: string = "",
        nativeImportEntryPoint: string = "") {
        Name = name
        ReturnCanonical = returnCanonical
        IsAsync = isAsync
        ModifierFlags = modifierFlags
        SourceFileId = sourceFileId
        IsBodylessNativeImport = isBodylessNativeImport
        NativeImportLibraryName = nativeImportLibraryName
        NativeImportEntryPoint = nativeImportEntryPoint
        ParamNames = paramNames
        ParamCanonicals = paramCanonicals
        ParamModifierKinds = paramModifierKinds ?? new int[](0)
        ParamDefaultKinds = paramDefaultKinds ?? new int[](0)
        ParamDefaultTexts = paramDefaultTexts ?? new string[](0)
        BodyNodes = bodyNodes
        BodyRoot = bodyRoot
        IsStatic = isStatic
        ReturnTupleElementNames = returnTupleElementNames
        ParamTupleElementNames = paramTupleElementNames
        TypeParamNames = typeParamNames ?? new string[](0)
        TypeParamSpecialConstraints = typeParamSpecialConstraints ?? new int[](TypeParamNames.Length)
        if typeParamTypeConstraints == null {
            typeParamTypeConstraints = new string[][](TypeParamNames.Length)
            t := 0
            while t < typeParamTypeConstraints.Length {
                typeParamTypeConstraints[t] = new string[](0)
                t = t + 1
            }
        }
        TypeParamTypeConstraints = typeParamTypeConstraints
    }
}

public class ColumnarLocalFunctionInput {
    NodeIndex: int
    Function: ColumnarFunctionInput

    constructor(nodeIndex: int, function: ColumnarFunctionInput) {
        NodeIndex = nodeIndex
        Function = function
    }
}

public class ColumnarConstructorInput {
    Body: ColumnarFunctionInput
    ChainInitKind: int
    ChainArgKinds: int[]
    ChainArgTexts: string[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    IsSynthesizedInitializer: bool
    SourceFileId: int

    constructor(
        body: ColumnarFunctionInput,
        chainInitKind: int,
        chainArgKinds: int[],
        chainArgTexts: string[],
        paramDefaultKinds: int[]? = null,
        paramDefaultTexts: string[]? = null,
        isSynthesizedInitializer: bool = false,
        sourceFileId: int = 0) {
        Body = body
        ChainInitKind = chainInitKind
        ChainArgKinds = chainArgKinds
        ChainArgTexts = chainArgTexts
        ParamDefaultKinds = paramDefaultKinds ?? new int[](0)
        ParamDefaultTexts = paramDefaultTexts ?? new string[](0)
        IsSynthesizedInitializer = isSynthesizedInitializer
        SourceFileId = sourceFileId
    }
}

public class ColumnarPropertyInput {
    IsStatic: bool
    Name: string
    TypeCanonical: string
    Getter: ColumnarFunctionInput
    Setter: ColumnarFunctionInput?
    SourceFileId: int

    constructor(
        name: string,
        typeCanonical: string,
        getter: ColumnarFunctionInput,
        setter: ColumnarFunctionInput?,
        isStatic: bool = false,
        sourceFileId: int = 0) {
        IsStatic = isStatic
        Name = name
        TypeCanonical = typeCanonical
        Getter = getter
        Setter = setter
        SourceFileId = sourceFileId
    }
}

public class ColumnarStructInput {
    Name: string
    FieldNames: string[]
    FieldTypeCanonicals: string[]
    Methods: IReadOnlyList<ColumnarFunctionInput>
    Constructors: IReadOnlyList<ColumnarConstructorInput>
    Properties: IReadOnlyList<ColumnarPropertyInput>
    IsReference: bool
    IsRefStruct: bool
    BaseNames: string[]
    FieldStaticFlags: bool[]
    FieldReadonlyFlags: bool[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    IsRecord: bool
    IsNewtype: bool
    TypeParamNames: string[]
    SourceFileId: int

    constructor(
        name: string,
        fieldNames: string[],
        fieldTypeCanonicals: string[],
        methods: IReadOnlyList<ColumnarFunctionInput>,
        constructors: IReadOnlyList<ColumnarConstructorInput>,
        properties: IReadOnlyList<ColumnarPropertyInput>,
        isReference: bool,
        baseNames: string[]? = null,
        fieldStaticFlags: bool[]? = null,
        fieldInitKinds: int[]? = null,
        fieldInitTexts: string[]? = null,
        isRecord: bool = false,
        typeParamNames: string[]? = null,
        fieldReadonlyFlags: bool[]? = null,
        sourceFileId: int = 0,
        isNewtype: bool = false,
        isRefStruct: bool = false) {
        Name = name
        FieldNames = fieldNames
        FieldTypeCanonicals = fieldTypeCanonicals
        Methods = methods
        Constructors = constructors
        Properties = properties
        IsReference = isReference
        IsRefStruct = isRefStruct
        BaseNames = baseNames ?? new string[](0)
        FieldStaticFlags = fieldStaticFlags ?? new bool[](fieldNames.Length)
        FieldReadonlyFlags = fieldReadonlyFlags ?? new bool[](fieldNames.Length)
        if fieldInitKinds == null {
            fieldInitKinds = new int[](fieldNames.Length)
            i := 0
            while i < fieldInitKinds.Length {
                fieldInitKinds[i] = -1
                i = i + 1
            }
        }
        FieldInitKinds = fieldInitKinds
        FieldInitTexts = fieldInitTexts ?? new string[](fieldNames.Length)
        IsRecord = isRecord
        IsNewtype = isNewtype
        TypeParamNames = typeParamNames ?? new string[](0)
        SourceFileId = sourceFileId
    }
}

public class ColumnarInterfaceInput {
    Name: string
    BaseInterfaceNames: string[]
    TypeParamNames: string[]
    MethodNames: string[]
    MethodReturnCanonicals: string[]
    MethodParamNames: string[][]
    MethodParamCanonicals: string[][]
    MethodBodies: ColumnarFunctionInput?[]
    SourceFileId: int

    constructor(
        name: string,
        baseInterfaceNames: string[],
        methodNames: string[],
        methodReturnCanonicals: string[],
        methodParamNames: string[][],
        methodParamCanonicals: string[][],
        methodBodies: ColumnarFunctionInput?[]? = null,
        typeParamNames: string[]? = null,
        sourceFileId: int = 0) {
        Name = name
        BaseInterfaceNames = baseInterfaceNames
        TypeParamNames = typeParamNames ?? new string[](0)
        MethodNames = methodNames
        MethodReturnCanonicals = methodReturnCanonicals
        MethodParamNames = methodParamNames
        MethodParamCanonicals = methodParamCanonicals
        MethodBodies = methodBodies ?? new ColumnarFunctionInput?[](methodNames.Length)
        SourceFileId = sourceFileId
    }
}

// One PLAIN top-level test declaration (`test "<description>" { body }`). The body reuses the
// function-input shape so node tables, source-file stamping, and body emission share machinery.
public class ColumnarTestInput {
    descriptionValue: string
    bodyValue: ColumnarFunctionInput

    Description: string => descriptionValue
    Body: ColumnarFunctionInput => bodyValue

    constructor(description: string, body: ColumnarFunctionInput) {
        descriptionValue = description
        bodyValue = body
    }
}

public class ColumnarProgramInput {
    bindingScope: ColumnarBindingScopeFacts
    ProjectRoot: string
    Source: string
    Sources: ColumnarSourceFile[]
    Functions: IReadOnlyList<ColumnarFunctionInput>
    Enums: IReadOnlyList<ColumnarEnumInput>
    Structs: IReadOnlyList<ColumnarStructInput>
    Unions: IReadOnlyList<ColumnarUnionInput>
    Interfaces: IReadOnlyList<ColumnarInterfaceInput>
    Tests: IReadOnlyList<ColumnarTestInput>?

    public static func CreateSingleSource(
        source: string,
        functions: IReadOnlyList<ColumnarFunctionInput>,
        enums: IReadOnlyList<ColumnarEnumInput>,
        structs: IReadOnlyList<ColumnarStructInput>,
        unions: IReadOnlyList<ColumnarUnionInput>,
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        tests: IReadOnlyList<ColumnarTestInput>? = null): ColumnarProgramInput {
        return new ColumnarProgramInput(
            source,
            functions,
            enums,
            structs,
            unions,
            interfaces,
            BuildSingleSourceFiles(source),
            tests,
            null)
    }

    public static func CreateFromSourceFiles(
        sourceFiles: ColumnarSourceFile[],
        functions: IReadOnlyList<ColumnarFunctionInput>,
        enums: IReadOnlyList<ColumnarEnumInput>,
        structs: IReadOnlyList<ColumnarStructInput>,
        unions: IReadOnlyList<ColumnarUnionInput>,
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        tests: IReadOnlyList<ColumnarTestInput>? = null): ColumnarProgramInput {
        return new ColumnarProgramInput(
            GetFirstSource(sourceFiles),
            functions,
            enums,
            structs,
            unions,
            interfaces,
            sourceFiles,
            tests,
            null)
    }

    public static func MergeSourceFiles(
        sourceFiles: ColumnarSourceFile[],
        programs: ColumnarProgramInput[]): ColumnarProgramInput {
        return MergeSourceFilesAtProjectRoot(sourceFiles, programs, "")
    }

    public static func MergeSourceFilesAtProjectRoot(
        sourceFiles: ColumnarSourceFile[],
        programs: ColumnarProgramInput[],
        projectRoot: string): ColumnarProgramInput {
        functions := new List<ColumnarFunctionInput>()
        enums := new List<ColumnarEnumInput>()
        structs := new List<ColumnarStructInput>()
        unions := new List<ColumnarUnionInput>()
        interfaces := new List<ColumnarInterfaceInput>()
        tests := new List<ColumnarTestInput>()

        index := 0
        while index < programs.Length {
            AddFunctions(functions, programs[index].Functions)
            AddEnums(enums, programs[index].Enums)
            AddStructs(structs, programs[index].Structs)
            AddUnions(unions, programs[index].Unions)
            AddInterfaces(interfaces, programs[index].Interfaces)
            programTests := programs[index].Tests
            if programTests != null {
                AddTests(tests, programTests)
            }
            index = index + 1
        }

        return new ColumnarProgramInput(
            GetFirstSource(sourceFiles),
            functions,
            enums,
            structs,
            unions,
            interfaces,
            sourceFiles,
            tests,
            projectRoot)
    }

    public static func AssignSourceFileId(program: ColumnarProgramInput, sourceFileId: int) {
        AssignFunctionListSourceFileId(program.Functions, sourceFileId)
        AssignEnumListSourceFileId(program.Enums, sourceFileId)
        AssignStructListSourceFileId(program.Structs, sourceFileId)
        AssignUnionListSourceFileId(program.Unions, sourceFileId)
        AssignInterfaceListSourceFileId(program.Interfaces, sourceFileId)
        programTests := program.Tests
        if programTests != null {
            testIndex := 0
            while testIndex < programTests.Count {
                AssignFunctionSourceFileId(programTests[testIndex].Body, sourceFileId)
                testIndex = testIndex + 1
            }
        }
    }

    constructor(
        source: string,
        functions: IReadOnlyList<ColumnarFunctionInput>,
        enums: IReadOnlyList<ColumnarEnumInput>,
        structs: IReadOnlyList<ColumnarStructInput>,
        unions: IReadOnlyList<ColumnarUnionInput>,
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        sourceFiles: ColumnarSourceFile[]? = null,
        tests: IReadOnlyList<ColumnarTestInput>? = null,
        projectRoot: string? = null) {
        Source = source
        Sources = sourceFiles ?? BuildSingleSourceFiles(source)
        ProjectRoot = projectRoot ?? ""
        Functions = functions
        Enums = enums
        Structs = structs
        Unions = unions
        Interfaces = interfaces
        Tests = tests
        bindingScope = ColumnarBindingScopeFacts.Create(
            Sources, Enums, Structs, Unions, Interfaces, ProjectRoot)
        StampBindingContexts(bindingScope)
    }

    public func PrepareExternalTypeBindings(
        referenceAssemblyPaths: IReadOnlyList<string>?) {
        bindingScope.PrepareExternalTypeBindings(referenceAssemblyPaths)
    }

    public func GetSourceForFileId(fileId: int): string {
        if fileId >= 0 && fileId < Sources.Length {
            return Sources[fileId].Source
        }

        return Source
    }

    static func BuildSingleSourceFiles(source: string): ColumnarSourceFile[] {
        sources := new string[](1)
        fileNames := new string[](1)
        sources[0] = source
        fileNames[0] = ""
        return ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames)
    }

    func StampBindingContexts(scope: ColumnarBindingScopeFacts) {
        noTypeParameters := new string[](0)
        functionIndex := 0
        while functionIndex < Functions.Count {
            StampFunctionBindingContext(
                Functions[functionIndex], scope, "", noTypeParameters, null)
            functionIndex = functionIndex + 1
        }

        structIndex := 0
        while structIndex < Structs.Count {
            structInput := Structs[structIndex]
            methodIndex := 0
            while methodIndex < structInput.Methods.Count {
                StampFunctionBindingContext(
                    structInput.Methods[methodIndex],
                    scope,
                    scope.ExactTypeNameForFile(
                        structInput.Name, structInput.SourceFileId),
                    structInput.TypeParamNames,
                    null)
                methodIndex = methodIndex + 1
            }
            constructorIndex := 0
            while constructorIndex < structInput.Constructors.Count {
                StampFunctionBindingContext(
                    structInput.Constructors[constructorIndex].Body,
                    scope,
                    scope.ExactTypeNameForFile(
                        structInput.Name, structInput.SourceFileId),
                    structInput.TypeParamNames,
                    null)
                constructorIndex = constructorIndex + 1
            }
            propertyIndex := 0
            while propertyIndex < structInput.Properties.Count {
                propertyInput := structInput.Properties[propertyIndex]
                StampFunctionBindingContext(
                    propertyInput.Getter,
                    scope,
                    scope.ExactTypeNameForFile(
                        structInput.Name, structInput.SourceFileId),
                    structInput.TypeParamNames,
                    null)
                if propertyInput.Setter != null {
                    StampFunctionBindingContext(
                        propertyInput.Setter,
                        scope,
                        scope.ExactTypeNameForFile(
                            structInput.Name, structInput.SourceFileId),
                        structInput.TypeParamNames,
                        null)
                }
                propertyIndex = propertyIndex + 1
            }
            structIndex = structIndex + 1
        }

        interfaceIndex := 0
        while interfaceIndex < Interfaces.Count {
            interfaceInput := Interfaces[interfaceIndex]
            if interfaceInput.MethodNames.Length
                != interfaceInput.MethodBodies.Length {
                throw new InvalidOperationException(
                    "Columnar interface method names and bodies must have identical lengths.")
            }
            visibleInterfaceMethodNames := new List<string>()
            methodIndex := 0
            while methodIndex < interfaceInput.MethodBodies.Length {
                // The analyzer has no implicit `this` in an interface and analyzes methods
                // sequentially. The current method declares itself before its body; later and
                // base-interface methods are not lexical bindings in this body.
                visibleInterfaceMethodNames.Add(
                    interfaceInput.MethodNames[methodIndex])
                body := interfaceInput.MethodBodies[methodIndex]
                if body != null {
                    StampFunctionBindingContext(
                        body,
                        scope,
                        "",
                        interfaceInput.TypeParamNames,
                        visibleInterfaceMethodNames.ToArray())
                }
                methodIndex = methodIndex + 1
            }
            interfaceIndex = interfaceIndex + 1
        }

        if Tests != null {
            testIndex := 0
            while testIndex < Tests.Count {
                StampFunctionBindingContext(
                    Tests[testIndex].Body, scope, "", noTypeParameters, null)
                testIndex = testIndex + 1
            }
        }
    }

    static func StampFunctionBindingContext(
        function: ColumnarFunctionInput,
        scope: ColumnarBindingScopeFacts,
        enclosingTypeName: string,
        inheritedTypeParameterNames: string[],
        additionalRootBindingNames: string[]?) {
        visibleTypeParameters := MergeNames(
            inheritedTypeParameterNames,
            function.TypeParamNames)
        function.BodyNodes.SetBindingContext(
            scope.ForSourceFile(function.SourceFileId),
            enclosingTypeName,
            visibleTypeParameters,
            additionalRootBindingNames)
        localFunctions := function.LocalFunctions
        if localFunctions != null {
            localIndex := 0
            while localIndex < localFunctions.Count {
                StampFunctionBindingContext(
                    localFunctions[localIndex].Function,
                    scope,
                    enclosingTypeName,
                    visibleTypeParameters,
                    additionalRootBindingNames)
                localIndex = localIndex + 1
            }
        }
    }

    static func MergeNames(first: string[], second: string[]): string[] {
        result := new string[](first.Length + second.Length)
        index := 0
        while index < first.Length {
            result[index] = first[index]
            index = index + 1
        }
        secondIndex := 0
        while secondIndex < second.Length {
            result[index] = second[secondIndex]
            index = index + 1
            secondIndex = secondIndex + 1
        }
        return result
    }

    static func AssignFunctionSourceFileId(function: ColumnarFunctionInput, sourceFileId: int) {
        function.SourceFileId = sourceFileId
        localFunctions := function.LocalFunctions
        if localFunctions != null {
            index := 0
            while index < localFunctions.Count {
                AssignFunctionSourceFileId(localFunctions[index].Function, sourceFileId)
                index = index + 1
            }
        }
    }

    static func AssignFunctionListSourceFileId(functions: IReadOnlyList<ColumnarFunctionInput>, sourceFileId: int) {
        index := 0
        while index < functions.Count {
            AssignFunctionSourceFileId(functions[index], sourceFileId)
            index = index + 1
        }
    }

    static func AssignEnumListSourceFileId(enums: IReadOnlyList<ColumnarEnumInput>, sourceFileId: int) {
        index := 0
        while index < enums.Count {
            enumInput := enums[index]
            enumInput.SourceFileId = sourceFileId
            index = index + 1
        }
    }

    static func AssignStructListSourceFileId(structs: IReadOnlyList<ColumnarStructInput>, sourceFileId: int) {
        index := 0
        while index < structs.Count {
            AssignStructSourceFileId(structs[index], sourceFileId)
            index = index + 1
        }
    }

    static func AssignUnionListSourceFileId(unions: IReadOnlyList<ColumnarUnionInput>, sourceFileId: int) {
        index := 0
        while index < unions.Count {
            unionInput := unions[index]
            unionInput.SourceFileId = sourceFileId
            index = index + 1
        }
    }

    static func AssignInterfaceListSourceFileId(interfaces: IReadOnlyList<ColumnarInterfaceInput>, sourceFileId: int) {
        index := 0
        while index < interfaces.Count {
            AssignInterfaceSourceFileId(interfaces[index], sourceFileId)
            index = index + 1
        }
    }

    static func AssignStructSourceFileId(structInput: ColumnarStructInput, sourceFileId: int) {
        structInput.SourceFileId = sourceFileId

        methodIndex := 0
        while methodIndex < structInput.Methods.Count {
            AssignFunctionSourceFileId(structInput.Methods[methodIndex], sourceFileId)
            methodIndex = methodIndex + 1
        }

        constructorIndex := 0
        while constructorIndex < structInput.Constructors.Count {
            constructorInput := structInput.Constructors[constructorIndex]
            constructorInput.SourceFileId = sourceFileId
            AssignFunctionSourceFileId(constructorInput.Body, sourceFileId)
            constructorIndex = constructorIndex + 1
        }

        propertyIndex := 0
        while propertyIndex < structInput.Properties.Count {
            AssignPropertySourceFileId(structInput.Properties[propertyIndex], sourceFileId)
            propertyIndex = propertyIndex + 1
        }
    }

    static func AssignPropertySourceFileId(propertyInput: ColumnarPropertyInput, sourceFileId: int) {
        propertyInput.SourceFileId = sourceFileId
        AssignFunctionSourceFileId(propertyInput.Getter, sourceFileId)

        setter := propertyInput.Setter
        if setter != null {
            AssignFunctionSourceFileId(setter, sourceFileId)
        }
    }

    static func AssignInterfaceSourceFileId(interfaceInput: ColumnarInterfaceInput, sourceFileId: int) {
        interfaceInput.SourceFileId = sourceFileId

        methodIndex := 0
        while methodIndex < interfaceInput.MethodBodies.Length {
            methodBody := interfaceInput.MethodBodies[methodIndex]
            if methodBody != null {
                AssignFunctionSourceFileId(methodBody, sourceFileId)
            }
            methodIndex = methodIndex + 1
        }
    }

    static func GetFirstSource(sourceFiles: ColumnarSourceFile[]): string {
        if sourceFiles.Length == 0 {
            return ""
        }

        return sourceFiles[0].Source
    }

    static func AddFunctions(target: List<ColumnarFunctionInput>, source: IReadOnlyList<ColumnarFunctionInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }

    static func AddTests(target: List<ColumnarTestInput>, source: IReadOnlyList<ColumnarTestInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }

    static func AddEnums(target: List<ColumnarEnumInput>, source: IReadOnlyList<ColumnarEnumInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }

    static func AddStructs(target: List<ColumnarStructInput>, source: IReadOnlyList<ColumnarStructInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }

    static func AddUnions(target: List<ColumnarUnionInput>, source: IReadOnlyList<ColumnarUnionInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }

    static func AddInterfaces(target: List<ColumnarInterfaceInput>, source: IReadOnlyList<ColumnarInterfaceInput>) {
        index := 0
        while index < source.Count {
            target.Add(source[index])
            index = index + 1
        }
    }
}
