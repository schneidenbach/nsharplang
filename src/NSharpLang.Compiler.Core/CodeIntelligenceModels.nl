namespace NSharpLang.Compiler.CodeIntelligence

enum SymbolKind {
    Function,
    Class,
    Struct,
    Record,
    Interface,
    Enum,
    Union,
    Property,
    Field,
    Method,
    Variable,
    Parameter,
    Constructor,
    EnumMember,
    TypeAlias,
    Test
}

class SymbolResult {
    nameValue: string
    kindValue: SymbolKind
    fileValue: string
    lineValue: int
    columnValue: int
    typeNameValue: string?
    modifiersValue: string[]?
    membersValue: SymbolResult[]?
    parametersValue: ParameterResult[]?

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Kind: SymbolKind {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    TypeName: string? {
        get {
            return typeNameValue
        }
        set {
            typeNameValue = value
        }
    }

    Modifiers: string[]? {
        get {
            return modifiersValue
        }
        set {
            modifiersValue = value
        }
    }

    Members: SymbolResult[]? {
        get {
            return membersValue
        }
        set {
            membersValue = value
        }
    }

    Parameters: ParameterResult[]? {
        get {
            return parametersValue
        }
        set {
            parametersValue = value
        }
    }

    constructor(Name: string, Kind: SymbolKind, File: string, Line: int, Column: int, TypeName: string?, Modifiers: string[]?, Members: SymbolResult[]?, Parameters: ParameterResult[]?) {
        nameValue = Name
        kindValue = Kind
        fileValue = File
        lineValue = Line
        columnValue = Column
        typeNameValue = TypeName
        modifiersValue = Modifiers
        membersValue = Members
        parametersValue = Parameters
    }
}

class OutlineResult {
    fileValue: string
    importsValue: string[]
    outlineValue: OutlineEntry[]

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Imports: string[] {
        get {
            return importsValue
        }
        set {
            importsValue = value
        }
    }

    Outline: OutlineEntry[] {
        get {
            return outlineValue
        }
        set {
            outlineValue = value
        }
    }

    constructor(File: string, Imports: string[], Outline: OutlineEntry[]) {
        fileValue = File
        importsValue = Imports
        outlineValue = Outline
    }
}

class OutlineEntry {
    nameValue: string
    kindValue: SymbolKind
    lineValue: int
    endLineValue: int
    returnTypeValue: string?
    typeNameValue: string?
    childrenValue: OutlineEntry[]?

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Kind: SymbolKind {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    EndLine: int {
        get {
            return endLineValue
        }
        set {
            endLineValue = value
        }
    }

    ReturnType: string? {
        get {
            return returnTypeValue
        }
        set {
            returnTypeValue = value
        }
    }

    TypeName: string? {
        get {
            return typeNameValue
        }
        set {
            typeNameValue = value
        }
    }

    Children: OutlineEntry[]? {
        get {
            return childrenValue
        }
        set {
            childrenValue = value
        }
    }

    constructor(Name: string, Kind: SymbolKind, Line: int, EndLine: int, ReturnType: string?, TypeName: string?, Children: OutlineEntry[]?) {
        nameValue = Name
        kindValue = Kind
        lineValue = Line
        endLineValue = EndLine
        returnTypeValue = ReturnType
        typeNameValue = TypeName
        childrenValue = Children
    }
}

class DiagnosticResult {
    codeValue: string
    severityValue: string
    messageValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    lengthValue: int
    sourceSnippetValue: string?
    explanationValue: string?
    suggestionValue: string?
    hintValue: string?
    expectedTypeValue: string?
    actualTypeValue: string?
    docsUrlValue: string?

    Code: string {
        get {
            return codeValue
        }
        set {
            codeValue = value
        }
    }

    Severity: string {
        get {
            return severityValue
        }
        set {
            severityValue = value
        }
    }

    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Length: int {
        get {
            return lengthValue
        }
        set {
            lengthValue = value
        }
    }

    SourceSnippet: string? {
        get {
            return sourceSnippetValue
        }
        set {
            sourceSnippetValue = value
        }
    }

    Explanation: string? {
        get {
            return explanationValue
        }
        set {
            explanationValue = value
        }
    }

    Suggestion: string? {
        get {
            return suggestionValue
        }
        set {
            suggestionValue = value
        }
    }

    Hint: string? {
        get {
            return hintValue
        }
        set {
            hintValue = value
        }
    }

    ExpectedType: string? {
        get {
            return expectedTypeValue
        }
        set {
            expectedTypeValue = value
        }
    }

    ActualType: string? {
        get {
            return actualTypeValue
        }
        set {
            actualTypeValue = value
        }
    }

    DocsUrl: string? {
        get {
            return docsUrlValue
        }
        set {
            docsUrlValue = value
        }
    }

    constructor(Code: string, Severity: string, Message: string, File: string, Line: int, Column: int, Length: int, SourceSnippet: string?, Explanation: string?, Suggestion: string?, Hint: string?, ExpectedType: string?, ActualType: string?, DocsUrl: string?) {
        codeValue = Code
        severityValue = Severity
        messageValue = Message
        fileValue = File
        lineValue = Line
        columnValue = Column
        lengthValue = Length
        sourceSnippetValue = SourceSnippet
        explanationValue = Explanation
        suggestionValue = Suggestion
        hintValue = Hint
        expectedTypeValue = ExpectedType
        actualTypeValue = ActualType
        docsUrlValue = DocsUrl
    }
}

class TypeResult {
    nameValue: string
    resolvedTypeValue: string
    kindValue: string
    definitionValue: LocationResult?
    nullabilityValue: string?

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    ResolvedType: string {
        get {
            return resolvedTypeValue
        }
        set {
            resolvedTypeValue = value
        }
    }

    Kind: string {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    Definition: LocationResult? {
        get {
            return definitionValue
        }
        set {
            definitionValue = value
        }
    }

    Nullability: string? {
        get {
            return nullabilityValue
        }
        set {
            nullabilityValue = value
        }
    }

    constructor(Name: string, ResolvedType: string, Kind: string, Definition: LocationResult?, Nullability: string? = null) {
        nameValue = Name
        resolvedTypeValue = ResolvedType
        kindValue = Kind
        definitionValue = Definition
        nullabilityValue = Nullability
    }
}

class DefinitionResult {
    nameValue: string
    kindValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    lengthValue: int

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Kind: string {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Length: int {
        get {
            return lengthValue
        }
        set {
            lengthValue = value
        }
    }

    constructor(Name: string, Kind: string, File: string, Line: int, Column: int, Length: int) {
        nameValue = Name
        kindValue = Kind
        fileValue = File
        lineValue = Line
        columnValue = Column
        lengthValue = Length
    }
}

class ReferenceResult {
    fileValue: string
    lineValue: int
    columnValue: int
    lengthValue: int
    contextValue: string?
    isDefinitionValue: bool

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Length: int {
        get {
            return lengthValue
        }
        set {
            lengthValue = value
        }
    }

    Context: string? {
        get {
            return contextValue
        }
        set {
            contextValue = value
        }
    }

    IsDefinition: bool {
        get {
            return isDefinitionValue
        }
        set {
            isDefinitionValue = value
        }
    }

    constructor(File: string, Line: int, Column: int, Length: int, Context: string?, IsDefinition: bool) {
        fileValue = File
        lineValue = Line
        columnValue = Column
        lengthValue = Length
        contextValue = Context
        isDefinitionValue = IsDefinition
    }
}

class LocationResult {
    fileValue: string
    lineValue: int
    columnValue: int

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    constructor(File: string, Line: int, Column: int) {
        fileValue = File
        lineValue = Line
        columnValue = Column
    }
}

class InspectSymbolResult {
    nameValue: string
    kindValue: string
    definitionValue: LocationResult?

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Kind: string {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    Definition: LocationResult? {
        get {
            return definitionValue
        }
        set {
            definitionValue = value
        }
    }

    constructor(Name: string, Kind: string, Definition: LocationResult?) {
        nameValue = Name
        kindValue = Kind
        definitionValue = Definition
    }
}

class InspectReferencesResult {
    countValue: int
    definitionCountValue: int
    resultsValue: ReferenceResult[]

    Count: int {
        get {
            return countValue
        }
        set {
            countValue = value
        }
    }

    DefinitionCount: int {
        get {
            return definitionCountValue
        }
        set {
            definitionCountValue = value
        }
    }

    Results: ReferenceResult[] {
        get {
            return resultsValue
        }
        set {
            resultsValue = value
        }
    }

    constructor(Count: int, DefinitionCount: int, Results: ReferenceResult[]) {
        countValue = Count
        definitionCountValue = DefinitionCount
        resultsValue = Results
    }
}

class InspectResult {
    symbolValue: InspectSymbolResult?
    typeValue: TypeResult?
    definitionValue: DefinitionResult?
    referencesValue: InspectReferencesResult
    completionsValue: CompletionResult

    Symbol: InspectSymbolResult? {
        get {
            return symbolValue
        }
        set {
            symbolValue = value
        }
    }

    Type: TypeResult? {
        get {
            return typeValue
        }
        set {
            typeValue = value
        }
    }

    Definition: DefinitionResult? {
        get {
            return definitionValue
        }
        set {
            definitionValue = value
        }
    }

    References: InspectReferencesResult {
        get {
            return referencesValue
        }
        set {
            referencesValue = value
        }
    }

    Completions: CompletionResult {
        get {
            return completionsValue
        }
        set {
            completionsValue = value
        }
    }

    constructor(Symbol: InspectSymbolResult?, Type: TypeResult?, Definition: DefinitionResult?, References: InspectReferencesResult, Completions: CompletionResult) {
        symbolValue = Symbol
        typeValue = Type
        definitionValue = Definition
        referencesValue = References
        completionsValue = Completions
    }
}

class InspectSummaryResult {
    symbolValue: InspectSummarySymbolResult?
    typeValue: InspectSummaryTypeResult?
    definitionValue: LocationResult?
    referencesValue: InspectSummaryReferencesResult
    completionsValue: InspectSummaryCompletionsResult

    Symbol: InspectSummarySymbolResult? {
        get {
            return symbolValue
        }
        set {
            symbolValue = value
        }
    }

    Type: InspectSummaryTypeResult? {
        get {
            return typeValue
        }
        set {
            typeValue = value
        }
    }

    Definition: LocationResult? {
        get {
            return definitionValue
        }
        set {
            definitionValue = value
        }
    }

    References: InspectSummaryReferencesResult {
        get {
            return referencesValue
        }
        set {
            referencesValue = value
        }
    }

    Completions: InspectSummaryCompletionsResult {
        get {
            return completionsValue
        }
        set {
            completionsValue = value
        }
    }

    constructor(Symbol: InspectSummarySymbolResult?, Type: InspectSummaryTypeResult?, Definition: LocationResult?, References: InspectSummaryReferencesResult, Completions: InspectSummaryCompletionsResult) {
        symbolValue = Symbol
        typeValue = Type
        definitionValue = Definition
        referencesValue = References
        completionsValue = Completions
    }
}

class InspectReferenceSummaryResult {
    fileValue: string
    lineValue: int
    columnValue: int
    isDefinitionValue: bool

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    IsDefinition: bool {
        get {
            return isDefinitionValue
        }
        set {
            isDefinitionValue = value
        }
    }

    constructor(File: string, Line: int, Column: int, IsDefinition: bool) {
        fileValue = File
        lineValue = Line
        columnValue = Column
        isDefinitionValue = IsDefinition
    }
}

class InspectSummaryReferencesResult {
    countValue: int
    definitionCountValue: int
    filesValue: string[]
    sampleValue: InspectReferenceSummaryResult[]

    Count: int {
        get {
            return countValue
        }
        set {
            countValue = value
        }
    }

    DefinitionCount: int {
        get {
            return definitionCountValue
        }
        set {
            definitionCountValue = value
        }
    }

    Files: string[] {
        get {
            return filesValue
        }
        set {
            filesValue = value
        }
    }

    Sample: InspectReferenceSummaryResult[] {
        get {
            return sampleValue
        }
        set {
            sampleValue = value
        }
    }

    constructor(Count: int, DefinitionCount: int, Files: string[], Sample: InspectReferenceSummaryResult[]) {
        countValue = Count
        definitionCountValue = DefinitionCount
        filesValue = Files
        sampleValue = Sample
    }
}
