namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Text
import NSharpLang.Compiler


// THE EDITOR'S HALF OF A HOVER ANSWER: THE SAME FACTS THE CLI ALREADY COMPUTED, SAID IN MARKDOWN.
//
// Nothing here resolves anything. `CodeIntelligenceQueries.HoverInfo` decided WHAT is under the
// cursor and `CodeIntelligenceSignatureKernels` decided how its signature reads; what is left is the
// presentation a language-server client renders, and that is a product decision like any other, so
// it belongs in N# beside `EditorCompletionFacts` rather than in the handler.
//
// THE MARKDOWN IS PRESERVED EXACTLY, DOWN TO THE BACKTICKS. These strings are what the VS Code suite
// reads back out of a hover, so they are a CONTRACT with the editor tests and not a style choice.
// The one addition is the declaring-type line, which is what defect D2 was missing.
//
// WHY THE HANDLER STILL EXISTS. Everything the protocol owns — `Hover`, `MarkupContent`, `Range`,
// the registration options — stays in C#, because those are OmniSharp types this language cannot
// name. The split is exactly "what to say" here and "how to hand it to the client" there.
class EditorHoverFacts {

    // THE WORDS THAT ANSWER FOR THEMSELVES. A keyword and a primitive have no declaration to find,
    // so they are answered from a table rather than from the project — which is also why this is the
    // FIRST thing a hover asks: it is the only answer that cannot be wrong.
    static func KeywordOrPrimitiveMarkdown(word: string): string? {
        if String.IsNullOrWhiteSpace(word) {
            return null
        }

        if IsHoverKeyword(word) {
            return "**" + word + "** *(keyword)*"
        }

        if IsHoverPrimitiveType(word) {
            return "**" + word + "** *(primitive type)*"
        }

        return null
    }

    static func IsHoverKeyword(word: string): bool {
        return word == "func" || word == "class" || word == "struct" || word == "record" || word == "interface" || word == "enum" || word == "union" || word == "match" || word == "async" || word == "await" || word == "yield" || word == "lock" || word == "using" || word == "import" || word == "let"
    }

    static func IsHoverPrimitiveType(word: string): bool {
        return word == "int" || word == "long" || word == "float" || word == "double" || word == "bool" || word == "string" || word == "void" || word == "object"
    }

    // THE PROJECT ANSWER, WHICH IS THE ONE THAT CARRIES A SIGNATURE. The four sections are ordered
    // widest-to-narrowest — what it is, what it does, what declares it, where it lives — and an
    // absent section is OMITTED rather than blanked, which is the same rule the CLI's text builder
    // follows.
    static func ProjectHoverMarkdown(result: HoverResult): string {
        builder := new StringBuilder()
        builder.AppendLine("```nsharp")
        builder.AppendLine(result.Signature)
        builder.AppendLine("```")

        documentation := result.Documentation
        if documentation != null && !String.IsNullOrWhiteSpace(documentation ?? "") {
            builder.AppendLine()
            builder.AppendLine(documentation ?? "")
        }

        // A metadata member has no file, so this line is the whole of "where is this from" for it.
        declaringType := result.DeclaringType
        if declaringType != null && !String.IsNullOrWhiteSpace(declaringType ?? "") {
            builder.AppendLine()
            builder.AppendLine("*Declaring Type:* `" + (declaringType ?? "") + "`")
        }

        definedIn := result.DefinedIn
        if definedIn != null && !String.IsNullOrWhiteSpace(definedIn ?? "") {
            builder.AppendLine()
            builder.AppendLine("*Defined in:* `" + (definedIn ?? "") + "`")
        }

        return builder.ToString().TrimEnd()
    }

    // A TYPE DECLARATION FOUND IN THE OPEN FILE'S OWN SYMBOL TABLE.
    static func TypeDeclarationMarkdown(name: string, typeInfo: TypeInfo): string {
        kind := TypeDeclarationKindWord(typeInfo)
        return "**" + name + "** *(" + kind + ")*\n\n```nsharp\n" + kind + " " + name + "\n```"
    }

    // The six shapes a declaration hover names, and `type` for anything else. This is DELIBERATELY
    // narrower than `CodeIntelligenceDisplayText.TypeInfoToKind`: that one answers for every type
    // the compiler has, including reflected ones, and a symbol-table entry is only ever one of these.
    static func TypeDeclarationKindWord(typeInfo: TypeInfo): string {
        if typeInfo as ClassTypeInfo != null {
            return "class"
        }

        if typeInfo as StructTypeInfo != null {
            return "struct"
        }

        if typeInfo as RecordTypeInfo != null {
            return "record"
        }

        if typeInfo as InterfaceTypeInfo != null {
            return "interface"
        }

        if typeInfo as EnumTypeInfo != null {
            return "enum"
        }

        if typeInfo as UnionTypeInfo != null {
            return "union"
        }

        return "type"
    }

    // A LOCAL, WITH THE TWO METADATA LINES WHEN THE TYPE RESOLVER COULD PLACE ITS TYPE. The handler
    // passes null for both when it could not, which is the same answer as a type with no namespace.
    static func VariableMarkdown(name: string, typeName: string, namespaceText: string?, assemblyText: string?): string {
        if namespaceText == null && assemblyText == null {
            return "**(variable)** `" + name + "`\n\n```nsharp\n" + name + ": " + typeName + "\n```"
        }

        builder := new StringBuilder()
        builder.AppendLine("**(variable)** `" + name + ": " + typeName + "`")
        builder.AppendLine()
        builder.AppendLine("```nsharp")
        builder.AppendLine(name + ": " + typeName)
        builder.AppendLine("```")

        if namespaceText != null && !String.IsNullOrEmpty(namespaceText ?? "") {
            builder.AppendLine()
            builder.AppendLine("*Namespace:* `" + (namespaceText ?? "") + "`")
        }

        if assemblyText != null {
            builder.AppendLine()
            builder.AppendLine("*Assembly:* `" + (assemblyText ?? "") + "`")
        }

        return builder.ToString()
    }

    // WHERE THE HIGHLIGHTED WORD STARTS. The search begins one word-width back from the cursor so a
    // word that occurs earlier on the same line cannot capture the range, and a word the line does
    // not contain at all falls back to the cursor itself rather than to -1.
    static func WordRangeStartColumn(lineText: string, character: int, word: string): int {
        searchFrom := Math.Max(0, Math.Min(lineText.Length, character) - word.Length)
        startColumn := lineText.IndexOf(word, searchFrom, StringComparison.Ordinal)
        if startColumn < 0 {
            return character
        }

        return startColumn
    }
}
