namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class OutputFormatterTextBuilders {
    public static func DiagnosticsToText(results: List<DiagnosticResult>): string {
        if results.Count == 0 {
            return OutputFormatterDiagnosticKernels.GetNoDiagnosticsText()
        }

        builder := new StringBuilder()
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)

        AppendDiagnosticClusterSummary(builder, OutputFormatterDiagnosticClusterBuilder.BuildDiagnosticClusters(results))

        foreach diagnostic in results {
            builder.AppendLine(FormatSingleDiagnosticText(diagnostic))
        }

        builder.AppendLine()
        builder.AppendLine(OutputFormatterDiagnosticKernels.GetFoundSummaryText(summary))

        return builder.ToString()
    }

    public static func SymbolsToText(results: List<SymbolResult>): string {
        if results.Count == 0 {
            return OutputFormatterTextKernels.GetNoSymbolsText()
        }

        builder := new StringBuilder()
        foreach symbol in results {
            AppendSymbolText(builder, symbol, 0)
        }

        return builder.ToString()
    }

    public static func OutlineToText(result: OutlineResult): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetOutlineFileLineText(result.File))

        if result.Imports.Length > 0 {
            builder.AppendLine(OutputFormatterTextKernels.GetOutlineImportsLineText(result.Imports))
        }

        builder.AppendLine()

        index := 0
        while index < result.Outline.Length {
            AppendOutlineEntryText(builder, result.Outline[index], 0)
            index = index + 1
        }

        return builder.ToString()
    }

    public static func TypeToText(result: TypeResult, fileName: string, line: int, column: int): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetTypeLocationHeaderText(fileName, line, column))
        builder.AppendLine(OutputFormatterTextKernels.GetTypeResultLineText(result))

        nullability := result.Nullability ?? ""
        if !String.IsNullOrWhiteSpace(nullability) {
            builder.AppendLine(OutputFormatterTextKernels.GetTypeNullabilityLineText(nullability))
        }

        if result.Definition != null {
            definition := (LocationResult)result.Definition
            builder.AppendLine(OutputFormatterTextKernels.GetTypeDefinedAtLineText(definition))
        }

        return builder.ToString()
    }

    public static func DefinitionToText(result: DefinitionResult): string {
        return OutputFormatterTextKernels.GetDefinitionLineText(result)
    }

    public static func ReferencesToText(symbolName: string, results: List<ReferenceResult>): string {
        if results.Count == 0 {
            return OutputFormatterTextKernels.GetNoReferencesText(symbolName)
        }

        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetReferencesHeaderText(symbolName, results.Count))
        foreach reference in results {
            builder.AppendLine(OutputFormatterTextKernels.GetReferenceLineText(reference))
        }

        return builder.ToString()
    }

    public static func DocToText(result: DocResult): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetDocHeaderText(result))

        if result.Namespace != null {
            namespaceName := result.Namespace ?? ""
            builder.AppendLine(OutputFormatterTextKernels.GetDocNamespaceLineText(namespaceName))
        }

        summary := result.Summary ?? ""
        if !String.IsNullOrWhiteSpace(summary) {
            builder.AppendLine()
            builder.AppendLine(OutputFormatterTextKernels.GetDocSummaryLineText(summary))
        }

        if result.BaseTypes != null {
            baseTypes := result.BaseTypes ?? new string[](0)
            if baseTypes.Length > 0 {
                builder.AppendLine()
                builder.AppendLine(OutputFormatterTextKernels.GetDocImplementsLineText(baseTypes))
            }
        }

        if result.Parameters != null {
            parameters := result.Parameters ?? new DocParameterResult[](0)
            if parameters.Length > 0 {
                builder.AppendLine()
                builder.AppendLine(OutputFormatterTextKernels.GetDocParametersHeaderText())
                index := 0
                while index < parameters.Length {
                    builder.AppendLine(OutputFormatterTextKernels.GetDocParameterLineText(parameters[index]))
                    index = index + 1
                }
            }
        }

        if result.ReturnType != null {
            returnType := result.ReturnType ?? ""
            if returnType != "void" {
                builder.AppendLine()
                builder.AppendLine(OutputFormatterTextKernels.GetDocReturnsLineText(returnType, result.ReturnDoc))
            }
        }

        if result.Members != null {
            members := result.Members ?? new DocMemberResult[](0)
            if members.Length > 0 {
                builder.AppendLine()
                builder.AppendLine(OutputFormatterTextKernels.GetDocMembersHeaderText(result.Kind))

                count := members.Length
                if count > 30 {
                    count = 30
                }

                index := 0
                while index < count {
                    builder.AppendLine(OutputFormatterTextKernels.GetDocMemberLineText(members[index]))
                    index = index + 1
                }

                if members.Length > 30 {
                    builder.AppendLine(OutputFormatterTextKernels.GetDocOverflowLineText(members.Length - 30))
                }
            }
        }

        return builder.ToString()
    }

    public static func CompletionsToText(result: CompletionResult, fileName: string, line: int, column: int): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetCompletionsHeaderText(
            fileName,
            line,
            column,
            CompletionContextText(result.Context)))

        if result.Receiver != null {
            receiver := result.Receiver ?? ""
            builder.AppendLine(OutputFormatterTextKernels.GetCompletionReceiverLineText(
                receiver,
                result.ReceiverType))
        }

        builder.AppendLine()

        foreach entry in result.Completions {
            category := entry.Key
            items := entry.Value
            builder.AppendLine(OutputFormatterTextKernels.GetCompletionCategoryLineText(category, items.Count))

            count := items.Count
            if count > 50 {
                count = 50
            }

            index := 0
            while index < count {
                builder.AppendLine(OutputFormatterTextKernels.GetCompletionItemLineText(items[index]))
                index = index + 1
            }

            if items.Count > 50 {
                builder.AppendLine(OutputFormatterTextKernels.GetCompletionOverflowLineText(items.Count - 50))
            }
        }

        return builder.ToString()
    }

    public static func HoverToText(result: HoverResult, fileName: string, line: int, column: int): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetHoverHeaderText(fileName, line, column))
        builder.AppendLine()
        builder.AppendLine(OutputFormatterTextKernels.GetHoverSignatureLineText(result.Signature))
        builder.AppendLine(OutputFormatterTextKernels.GetHoverKindLineText(result.Kind))

        if result.DefinedIn != null {
            definedIn := result.DefinedIn ?? ""
            builder.AppendLine(OutputFormatterTextKernels.GetHoverDefinedInLineText(definedIn))
        }

        documentation := result.Documentation ?? ""
        if !String.IsNullOrWhiteSpace(documentation) {
            builder.AppendLine()
            builder.AppendLine(OutputFormatterTextKernels.GetHoverDocumentationHeaderText())
            lines := documentation.Split('\n')
            index := 0
            while index < lines.Length {
                builder.AppendLine(OutputFormatterTextKernels.GetHoverDocumentationLineText(lines[index]))
                index = index + 1
            }
        }

        return builder.ToString()
    }

    public static func CallGraphToText(result: CallGraphResult): string {
        builder := new StringBuilder()
        if result.Function != null {
            functionName := result.Function ?? ""
            builder.AppendLine(OutputFormatterTextKernels.GetCallGraphFunctionHeaderText(functionName))
        } else {
            builder.AppendLine(OutputFormatterTextKernels.GetCallGraphFullHeaderText())
        }

        builder.AppendLine()
        builder.AppendLine(OutputFormatterTextKernels.GetCallGraphSectionHeaderText("Callers", result.Callers.Count))
        foreach caller in result.Callers {
            builder.AppendLine(OutputFormatterTextKernels.GetCallGraphEdgeLineText(caller))
        }

        builder.AppendLine()
        builder.AppendLine(OutputFormatterTextKernels.GetCallGraphSectionHeaderText("Callees", result.Callees.Count))
        foreach callee in result.Callees {
            builder.AppendLine(OutputFormatterTextKernels.GetCallGraphEdgeLineText(callee))
        }

        if result.Truncated {
            builder.AppendLine(OutputFormatterTextKernels.GetCallGraphTruncatedLineText())
        }

        return builder.ToString()
    }

    public static func ImplementorsToText(result: ImplementorsResult): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetImplementorsHeaderText(
            result.Interface,
            result.Results.Count))
        builder.AppendLine()

        foreach implementor in result.Results {
            builder.AppendLine(OutputFormatterTextKernels.GetImplementorLineText(implementor))
        }

        return builder.ToString()
    }

    public static func InspectToText(result: InspectResult, fileName: string, line: int, column: int): string {
        builder := new StringBuilder()
        builder.AppendLine(OutputFormatterTextKernels.GetInspectHeaderText(fileName, line, column))
        builder.AppendLine()

        if result.Symbol != null {
            symbol := (InspectSymbolResult)result.Symbol
            builder.AppendLine(OutputFormatterTextKernels.GetInspectSymbolLineText(symbol))
            if symbol.Definition != null {
                definition := (LocationResult)symbol.Definition
                builder.AppendLine(OutputFormatterTextKernels.GetTypeDefinedAtLineText(definition))
            }
        } else {
            builder.AppendLine(OutputFormatterTextKernels.GetInspectNoSymbolText())
        }

        builder.AppendLine()

        if result.Type != null {
            typeResult := (TypeResult)result.Type
            builder.AppendLine(OutputFormatterTextKernels.GetInspectTypeLineText(typeResult))
            nullability := typeResult.Nullability ?? ""
            if !String.IsNullOrWhiteSpace(nullability) {
                builder.AppendLine(OutputFormatterTextKernels.GetTypeNullabilityLineText(nullability))
            }
        } else {
            builder.AppendLine(OutputFormatterTextKernels.GetInspectUnknownTypeText())
        }

        builder.AppendLine()

        if result.Definition != null {
            definitionResult := (DefinitionResult)result.Definition
            builder.AppendLine(OutputFormatterTextKernels.GetInspectDefinitionLineText(definitionResult))
        } else {
            builder.AppendLine(OutputFormatterTextKernels.GetInspectNoDefinitionText())
        }

        builder.AppendLine()
        builder.AppendLine(OutputFormatterTextKernels.GetInspectReferencesHeaderText(
            result.References.Count,
            result.References.DefinitionCount))

        referenceCount := result.References.Results.Length
        if referenceCount > 10 {
            referenceCount = 10
        }

        referenceIndex := 0
        while referenceIndex < referenceCount {
            builder.AppendLine(OutputFormatterTextKernels.GetReferenceLineText(result.References.Results[referenceIndex]))
            referenceIndex = referenceIndex + 1
        }

        if result.References.Count > 10 {
            builder.AppendLine(OutputFormatterTextKernels.GetInspectReferencesOverflowLineText(result.References.Count - 10))
        }

        builder.AppendLine()
        builder.Append(CompletionsToText(result.Completions, fileName, line, column))
        return builder.ToString()
    }

    static func AppendDiagnosticClusterSummary(builder: StringBuilder, clusters: List<DiagnosticCluster>) {
        if clusters.Count == 0 {
            return
        }

        diagnosticCount := 0
        foreach cluster in clusters {
            diagnosticCount = diagnosticCount + cluster.Count
        }

        builder.AppendLine(
            "Diagnostic clusters (" +
            clusters.Count.ToString() +
            " group" +
            PluralSuffix(clusters.Count) +
            ", " +
            diagnosticCount.ToString() +
            " diagnostic" +
            PluralSuffix(diagnosticCount) +
            ")")

        count := clusters.Count
        if count > 10 {
            count = 10
        }

        index := 0
        while index < count {
            cluster := clusters[index]
            builder.AppendLine(
                "  [" +
                cluster.Count.ToString() +
                "x] " +
                cluster.Category +
                " / " +
                cluster.SourceConstruct +
                " / risk: " +
                cluster.Risk)
            builder.AppendLine("       recipe: " + cluster.Recipe)
            builder.AppendLine(
                "       root: " +
                cluster.RootLocation.File +
                ":" +
                cluster.RootLocation.Line.ToString() +
                ":" +
                cluster.RootLocation.Column.ToString())
            builder.AppendLine("       next command: " + cluster.NextCommand)
            builder.AppendLine("       example: " + cluster.Examples[0].Message)

            actionCount := cluster.SuggestedNextActions.Length
            if actionCount > 2 {
                actionCount = 2
            }

            actionIndex := 0
            while actionIndex < actionCount {
                builder.AppendLine("       next: " + cluster.SuggestedNextActions[actionIndex])
                actionIndex = actionIndex + 1
            }

            index = index + 1
        }

        if clusters.Count > 10 {
            omitted := clusters.Count - 10
            builder.AppendLine(
                "  ... " +
                omitted.ToString() +
                " more cluster" +
                PluralSuffix(omitted) +
                " omitted; use --json for the full AI-consumable cluster list.")
        }

        builder.AppendLine()
    }

    static func FormatSingleDiagnosticText(diagnostic: DiagnosticResult): string {
        builder := new StringBuilder()

        title := OutputFormatterDiagnosticKernels.GetDiagnosticTitle(diagnostic.Code, diagnostic.Severity)
        builder.AppendLine(OutputFormatterDiagnosticKernels.GetHeaderLineText(
            title,
            diagnostic.File,
            diagnostic.Line,
            diagnostic.Column))
        builder.AppendLine()

        sourceSnippet := diagnostic.SourceSnippet ?? ""
        if !String.IsNullOrWhiteSpace(sourceSnippet) {
            builder.AppendLine(OutputFormatterDiagnosticKernels.GetSourceLineText(
                diagnostic.Line,
                sourceSnippet.TrimEnd()))
            builder.AppendLine(OutputFormatterDiagnosticKernels.GetCaretLineText(
                diagnostic.Line,
                diagnostic.Column,
                diagnostic.Length))
        }

        builder.AppendLine()
        builder.AppendLine(diagnostic.Message)

        explanation := diagnostic.Explanation ?? ""
        if !String.IsNullOrWhiteSpace(explanation) {
            builder.AppendLine()
            builder.AppendLine(explanation)
        }

        expectedType := diagnostic.ExpectedType ?? ""
        actualType := diagnostic.ActualType ?? ""
        if !String.IsNullOrWhiteSpace(expectedType) || !String.IsNullOrWhiteSpace(actualType) {
            builder.AppendLine()
            if !String.IsNullOrWhiteSpace(expectedType) {
                builder.AppendLine(OutputFormatterDiagnosticKernels.GetExpectedTypeText(expectedType))
            }

            if !String.IsNullOrWhiteSpace(actualType) {
                builder.AppendLine(OutputFormatterDiagnosticKernels.GetActualTypeText(actualType))
            }
        }

        hint := diagnostic.Hint ?? ""
        if !String.IsNullOrWhiteSpace(hint) {
            builder.AppendLine()
            builder.AppendLine(OutputFormatterDiagnosticKernels.GetHintText(hint))
        }

        suggestion := diagnostic.Suggestion ?? ""
        if !String.IsNullOrWhiteSpace(suggestion) {
            builder.AppendLine()
            builder.AppendLine(OutputFormatterDiagnosticKernels.GetSuggestionText(suggestion))
        }

        docsUrl := diagnostic.DocsUrl ?? ""
        if !String.IsNullOrWhiteSpace(docsUrl) {
            builder.AppendLine()
            builder.AppendLine(OutputFormatterDiagnosticKernels.GetDocsUrlText(docsUrl))
        }

        return builder.ToString()
    }

    static func PluralSuffix(count: int): string {
        if count == 1 {
            return ""
        }

        return "s"
    }

    static func AppendSymbolText(builder: StringBuilder, symbol: SymbolResult, indent: int) {
        builder.AppendLine(OutputFormatterTextKernels.GetSymbolLineText(symbol, indent))

        if symbol.Parameters != null {
            parameters := symbol.Parameters ?? new ParameterResult[](0)
            if parameters.Length > 0 {
                builder.AppendLine(OutputFormatterTextKernels.GetSymbolParametersLineText(parameters, indent))
            }
        }

        if symbol.Members != null {
            members := symbol.Members ?? new SymbolResult[](0)
            if members.Length > 0 {
                index := 0
                while index < members.Length {
                    AppendSymbolText(builder, members[index], indent + 1)
                    index = index + 1
                }
            }
        }
    }

    static func AppendOutlineEntryText(builder: StringBuilder, entry: OutlineEntry, indent: int) {
        builder.AppendLine(OutputFormatterTextKernels.GetOutlineEntryLineText(entry, indent))

        if entry.Children != null {
            children := entry.Children ?? new OutlineEntry[](0)
            if children.Length > 0 {
                index := 0
                while index < children.Length {
                    AppendOutlineEntryText(builder, children[index], indent + 1)
                    index = index + 1
                }
            }
        }
    }

    static func CompletionContextText(context: CompletionContext): string {
        if context == CompletionContext.MemberAccess {
            return "memberaccess"
        }

        if context == CompletionContext.Identifier {
            return "identifier"
        }

        if context == CompletionContext.Namespace {
            return "namespace"
        }

        return "unknown"
    }
}
