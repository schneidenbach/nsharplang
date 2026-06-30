namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Text

public class OutputFormatterTextBuilders {
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
