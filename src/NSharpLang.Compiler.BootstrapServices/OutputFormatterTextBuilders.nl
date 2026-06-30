namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class OutputFormatterTextBuilders {
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
