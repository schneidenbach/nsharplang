namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class DiagnosticCluster {
    idValue: string
    categoryValue: string
    recipeValue: string
    riskValue: string
    countValue: int
    severityValue: string
    filesValue: string[]
    relatedDiagnosticsValue: DiagnosticClusterRelatedDiagnostic[]
    nextCommandValue: string
    rootLocationValue: DiagnosticClusterLocation
    messagePatternValue: string
    sourceConstructValue: string
    suggestedNextActionsValue: string[]
    examplesValue: DiagnosticClusterExample[]

    Id: string {
        get {
            return idValue
        }
        set {
            idValue = value
        }
    }

    Category: string {
        get {
            return categoryValue
        }
        set {
            categoryValue = value
        }
    }

    Recipe: string {
        get {
            return recipeValue
        }
        set {
            recipeValue = value
        }
    }

    Risk: string {
        get {
            return riskValue
        }
        set {
            riskValue = value
        }
    }

    Count: int {
        get {
            return countValue
        }
        set {
            countValue = value
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

    Files: string[] {
        get {
            return filesValue
        }
        set {
            filesValue = value
        }
    }

    RelatedDiagnostics: DiagnosticClusterRelatedDiagnostic[] {
        get {
            return relatedDiagnosticsValue
        }
        set {
            relatedDiagnosticsValue = value
        }
    }

    NextCommand: string {
        get {
            return nextCommandValue
        }
        set {
            nextCommandValue = value
        }
    }

    RootLocation: DiagnosticClusterLocation {
        get {
            return rootLocationValue
        }
        set {
            rootLocationValue = value
        }
    }

    MessagePattern: string {
        get {
            return messagePatternValue
        }
        set {
            messagePatternValue = value
        }
    }

    SourceConstruct: string {
        get {
            return sourceConstructValue
        }
        set {
            sourceConstructValue = value
        }
    }

    SuggestedNextActions: string[] {
        get {
            return suggestedNextActionsValue
        }
        set {
            suggestedNextActionsValue = value
        }
    }

    Examples: DiagnosticClusterExample[] {
        get {
            return examplesValue
        }
        set {
            examplesValue = value
        }
    }

    constructor(Id: string, Category: string, Recipe: string, Risk: string, Count: int, Severity: string, Files: string[], RelatedDiagnostics: DiagnosticClusterRelatedDiagnostic[], NextCommand: string, RootLocation: DiagnosticClusterLocation, MessagePattern: string, SourceConstruct: string, SuggestedNextActions: string[], Examples: DiagnosticClusterExample[]) {
        idValue = Id
        categoryValue = Category
        recipeValue = Recipe
        riskValue = Risk
        countValue = Count
        severityValue = Severity
        filesValue = Files
        relatedDiagnosticsValue = RelatedDiagnostics
        nextCommandValue = NextCommand
        rootLocationValue = RootLocation
        messagePatternValue = MessagePattern
        sourceConstructValue = SourceConstruct
        suggestedNextActionsValue = SuggestedNextActions
        examplesValue = Examples
    }
}

class DiagnosticClusterLocation {
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

class DiagnosticClusterRelatedDiagnostic {
    codeValue: string
    severityValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    messageValue: string

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

    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
        }
    }

    constructor(Code: string, Severity: string, File: string, Line: int, Column: int, Message: string) {
        codeValue = Code
        severityValue = Severity
        fileValue = File
        lineValue = Line
        columnValue = Column
        messageValue = Message
    }
}

class DiagnosticClusterExample {
    fileValue: string
    lineValue: int
    columnValue: int
    messageValue: string
    sourceSnippetValue: string?
    suggestionValue: string?

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

    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
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

    Suggestion: string? {
        get {
            return suggestionValue
        }
        set {
            suggestionValue = value
        }
    }

    constructor(File: string, Line: int, Column: int, Message: string, SourceSnippet: string?, Suggestion: string?) {
        fileValue = File
        lineValue = Line
        columnValue = Column
        messageValue = Message
        sourceSnippetValue = SourceSnippet
        suggestionValue = Suggestion
    }
}

class ClassifiedDiagnostic {
    diagnosticValue: DiagnosticResult
    traitsValue: DiagnosticClusterTraits

    Diagnostic: DiagnosticResult {
        get {
            return diagnosticValue
        }
        set {
            diagnosticValue = value
        }
    }

    Traits: DiagnosticClusterTraits {
        get {
            return traitsValue
        }
        set {
            traitsValue = value
        }
    }

    constructor(Diagnostic: DiagnosticResult, Traits: DiagnosticClusterTraits) {
        diagnosticValue = Diagnostic
        traitsValue = Traits
    }
}

class ClassifiedDiagnosticSet {
    itemsValue: List<ClassifiedDiagnostic>
    diagnosticsValue: DiagnosticResult[]
    categoryIdsValue: int[]
    sourceConstructIdsValue: int[]
    messagePatternsValue: string[]

    Items: List<ClassifiedDiagnostic> {
        get {
            return itemsValue
        }
        set {
            itemsValue = value
        }
    }

    Diagnostics: DiagnosticResult[] {
        get {
            return diagnosticsValue
        }
        set {
            diagnosticsValue = value
        }
    }

    CategoryIds: int[] {
        get {
            return categoryIdsValue
        }
        set {
            categoryIdsValue = value
        }
    }

    SourceConstructIds: int[] {
        get {
            return sourceConstructIdsValue
        }
        set {
            sourceConstructIdsValue = value
        }
    }

    MessagePatterns: string[] {
        get {
            return messagePatternsValue
        }
        set {
            messagePatternsValue = value
        }
    }

    constructor(Items: List<ClassifiedDiagnostic>, Diagnostics: DiagnosticResult[], CategoryIds: int[], SourceConstructIds: int[], MessagePatterns: string[]) {
        itemsValue = Items
        diagnosticsValue = Diagnostics
        categoryIdsValue = CategoryIds
        sourceConstructIdsValue = SourceConstructIds
        messagePatternsValue = MessagePatterns
    }
}

class DiagnosticClusterTraits {
    categoryValue: string
    sourceConstructValue: string
    recipeValue: string
    riskValue: string
    messagePatternValue: string
    suggestedNextActionsValue: string[]

    Category: string {
        get {
            return categoryValue
        }
        set {
            categoryValue = value
        }
    }

    SourceConstruct: string {
        get {
            return sourceConstructValue
        }
        set {
            sourceConstructValue = value
        }
    }

    Recipe: string {
        get {
            return recipeValue
        }
        set {
            recipeValue = value
        }
    }

    Risk: string {
        get {
            return riskValue
        }
        set {
            riskValue = value
        }
    }

    MessagePattern: string {
        get {
            return messagePatternValue
        }
        set {
            messagePatternValue = value
        }
    }

    SuggestedNextActions: string[] {
        get {
            return suggestedNextActionsValue
        }
        set {
            suggestedNextActionsValue = value
        }
    }

    constructor(Category: string, SourceConstruct: string, Recipe: string, Risk: string, MessagePattern: string, SuggestedNextActions: string[]) {
        categoryValue = Category
        sourceConstructValue = SourceConstruct
        recipeValue = Recipe
        riskValue = Risk
        messagePatternValue = MessagePattern
        suggestedNextActionsValue = SuggestedNextActions
    }
}

class OutputFormatterDiagnosticClusterBuilder {
    static func BuildDiagnosticClusters(results: IReadOnlyList<DiagnosticResult>): List<DiagnosticCluster> {
        classified := BuildClassifiedDiagnostics(results)
        return BuildDiagnosticClustersFromDogfoodGroups(classified)
    }

    static func BuildDiagnosticClustersFromDogfoodGroups(classified: ClassifiedDiagnosticSet): List<DiagnosticCluster> {
        grouping := OutputFormatterDiagnosticClusterKernels.GroupDiagnosticClusters(classified.Diagnostics, classified.CategoryIds, classified.SourceConstructIds, classified.MessagePatterns)

        clusters := new List<DiagnosticCluster>(grouping.GroupCount)
        ordered := new List<DiagnosticResult>()
        groupIndex := 0
        while groupIndex < grouping.GroupCount {
            rootIndex := grouping.RootIndices[groupIndex]
            memberStart := grouping.MemberStarts[groupIndex]
            memberCount := grouping.Counts[groupIndex]

            ordered.Clear()
            memberOffset := 0
            while memberOffset < memberCount {
                diagnosticIndex := grouping.MemberIndices[memberStart + memberOffset]
                ordered.Add(classified.Items[diagnosticIndex].Diagnostic)
                memberOffset = memberOffset + 1
            }

            traits := classified.Items[rootIndex].Traits
            clusters.Add(CreateDiagnosticCluster(ordered, traits))
            groupIndex = groupIndex + 1
        }

        return clusters
    }

    static func CreateDiagnosticCluster(ordered: List<DiagnosticResult>, traits: DiagnosticClusterTraits): DiagnosticCluster {
        root := ordered[0]
        files := BuildDiagnosticClusterFiles(ordered)

        return new DiagnosticCluster(OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId(root.Code, root.Severity, traits.Category, traits.SourceConstruct, traits.Recipe, traits.MessagePattern), traits.Category, traits.Recipe, traits.Risk, ordered.Count, root.Severity, files, BuildRelatedDiagnostics(ordered), OutputFormatterDiagnosticClusterKernels.BuildDiagnosticClusterNextCommand(root), new DiagnosticClusterLocation(root.File, root.Line, root.Column), traits.MessagePattern, traits.SourceConstruct, traits.SuggestedNextActions, BuildExamples(ordered))
    }

    static func BuildClassifiedDiagnostics(results: IReadOnlyList<DiagnosticResult>): ClassifiedDiagnosticSet {
        items := DiagnosticList(results)
        classified := new List<ClassifiedDiagnostic>(items.Count)
        diagnostics := new DiagnosticResult[](items.Count)
        classification := OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticClusterTraits(items)
        categories := classification.Categories
        sourceConstructs := classification.SourceConstructs
        messagePatterns := new string[](items.Count)

        i := 0
        while i < items.Count {
            diagnostic := items[i]
            messagePattern := OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern(diagnostic.Message ?? "")
            normalized := OutputFormatterNormalizationKernels.NormalizeDiagnostic(diagnostic)
            messagePatterns[i] = messagePattern
            diagnostics[i] = normalized
            classified.Add(new ClassifiedDiagnostic(normalized, CreateDiagnosticClusterTraits(categories[i], sourceConstructs[i], messagePattern)))
            i = i + 1
        }

        return new ClassifiedDiagnosticSet(classified, diagnostics, categories, sourceConstructs, messagePatterns)
    }

    static func BuildRelatedDiagnostics(ordered: List<DiagnosticResult>): DiagnosticClusterRelatedDiagnostic[] {
        related := new DiagnosticClusterRelatedDiagnostic[](ordered.Count)
        i := 0
        while i < ordered.Count {
            diagnostic := ordered[i]
            related[i] = new DiagnosticClusterRelatedDiagnostic(diagnostic.Code, diagnostic.Severity, diagnostic.File, diagnostic.Line, diagnostic.Column, diagnostic.Message)
            i = i + 1
        }

        return related
    }

    static func BuildExamples(ordered: List<DiagnosticResult>): DiagnosticClusterExample[] {
        count := ordered.Count
        if count > 3 {
            count = 3
        }

        examples := new DiagnosticClusterExample[](count)
        i := 0
        while i < count {
            diagnostic := ordered[i]
            examples[i] = new DiagnosticClusterExample(diagnostic.File, diagnostic.Line, diagnostic.Column, diagnostic.Message, TrimOptional(diagnostic.SourceSnippet), TrimOptional(diagnostic.Suggestion))
            i = i + 1
        }

        return examples
    }

    static func BuildDiagnosticClusterFiles(ordered: List<DiagnosticResult>): string[] {
        values := new List<object>(ordered.Count)
        i := 0
        while i < ordered.Count {
            values.Add(ordered[i])
            i = i + 1
        }

        return OutputFormatterReferenceFileKernels.BuildDiagnosticClusterFiles(values)
    }

    static func CreateDiagnosticClusterTraits(category: int, sourceConstruct: int, messagePattern: string): DiagnosticClusterTraits {
        sourceConstructText := DiagnosticSourceConstructName(sourceConstruct)

        if category == 0 {
            return new DiagnosticClusterTraits("syntax-missing-terminator", sourceConstructText, "syntax:statement-boundary", "high", messagePattern, SyntaxDelimiterActions())
        }

        if category == 1 {
            return new DiagnosticClusterTraits("syntax-missing-delimiter", sourceConstructText, "syntax:delimiter-balancing", "high", messagePattern, SyntaxDelimiterActions())
        }

        if category == 2 {
            return new DiagnosticClusterTraits("import-cycle", "import", "architecture:extract-shared-module-or-invert-dependency", "high", messagePattern, ImportCycleActions())
        }

        if category == 3 {
            return new DiagnosticClusterTraits("identifier-resolution", sourceConstructText, "symbols:missing-import-or-qualification", "medium", messagePattern, IdentifierResolutionActions())
        }

        if category == 4 {
            return new DiagnosticClusterTraits("type-resolution", sourceConstructText, "types:resolve-type-or-import", "medium", messagePattern, TypeResolutionActions())
        }

        if category == 5 {
            return new DiagnosticClusterTraits("type-mismatch", sourceConstructText, "refactor:signature-or-expression-shape", "medium", messagePattern, TypeMismatchActions())
        }

        if category == 6 {
            return new DiagnosticClusterTraits("member-resolution", sourceConstructText, "members:api-rename-or-extension-import", "medium", messagePattern, MemberResolutionActions())
        }

        return new DiagnosticClusterTraits("diagnostic-message-shape", sourceConstructText, "manual-triage:inspect-root-diagnostic", "low", messagePattern, ManualTriageActions())
    }

    static func DiagnosticSourceConstructName(sourceConstruct: int): string {
        if sourceConstruct == 0 {
            return "variable-declaration"
        }

        if sourceConstruct == 1 {
            return "function-declaration"
        }

        if sourceConstruct == 2 {
            return "class-declaration"
        }

        if sourceConstruct == 3 {
            return "interface-declaration"
        }

        if sourceConstruct == 4 {
            return "import"
        }

        if sourceConstruct == 5 {
            return "return-statement"
        }

        if sourceConstruct == 6 {
            return "control-flow"
        }

        if sourceConstruct == 7 {
            return "call-or-construction"
        }

        return "unknown-construct"
    }

    static func SyntaxDelimiterActions(): string[] {
        actions := new string[](2)
        actions[0] = "Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades."
        actions[1] = "Inspect the refactor or code-generation path that emitted this construct and add a delimiter/terminator regression test."
        return actions
    }

    static func ImportCycleActions(): string[] {
        actions := new string[](2)
        actions[0] = "Break the cycle at the reported import path by moving shared declarations into a third file/package or inverting one dependency."
        actions[1] = "Rerun `nlc check` after removing the cycle; unused-import warnings in the same files may be cascades."
        return actions
    }

    static func IdentifierResolutionActions(): string[] {
        actions := new string[](2)
        actions[0] = "Resolve the first missing identifier by adding the import/qualification or correcting the declaration name."
        actions[1] = "Rerun diagnostics after the root symbol is resolved; dependent member/type errors may disappear."
        return actions
    }

    static func TypeResolutionActions(): string[] {
        actions := new string[](2)
        actions[0] = "Resolve the type/import at the earliest root location before chasing downstream uses."
        actions[1] = "Check whether the source construct needs full qualification or a project reference."
        return actions
    }

    static func TypeMismatchActions(): string[] {
        actions := new string[](2)
        actions[0] = "Compare the expected and actual types at the root example and update the refactor recipe that changed the expression/signature shape."
        actions[1] = "Prefer fixing the producer expression over adding casts to each cascaded consumer."
        return actions
    }

    static func MemberResolutionActions(): string[] {
        actions := new string[](2)
        actions[0] = "Verify the API/member name for the root receiver before fixing repeated call sites."
        actions[1] = "Check whether an extension-method import or receiver type conversion was dropped."
        return actions
    }

    static func ManualTriageActions(): string[] {
        actions := new string[](2)
        actions[0] = "Start at the root example and decide whether this is a source, refactor, or compiler diagnostic issue."
        actions[1] = "After fixing the root cause, rerun diagnostics and compare the remaining cluster counts."
        return actions
    }

    static func TrimOptional(value: string?): string? {
        if string.IsNullOrWhiteSpace(value ?? "") {
            return null
        }

        text := value ?? ""
        return text.Trim()
    }

    static func DiagnosticList(diagnostics: IReadOnlyList<DiagnosticResult>): List<DiagnosticResult> {
        items := new List<DiagnosticResult>()
        for diagnosticValue in diagnostics {
            items.Add((DiagnosticResult)diagnosticValue)
        }

        return items
    }
}
