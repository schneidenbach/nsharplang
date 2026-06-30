namespace NSharpLang.Compiler.CodeIntelligence

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
