namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE ROW OF THE IDENTIFIER COMPLETION MENU — the list a reader sees on Ctrl+Space, as opposed to
// the member list after a dot, which `CompletionReceiverFacts` and `EditorCompletionFacts` already
// own between them.
//
// THE KIND IS THE PROTOCOL'S OWN NUMBER, for the same reason it is there: `CompletionItemKind` is
// fixed by the specification's table and no N# owner may reinvent it. WHICH slot each N# thing
// lands in is a judgement about N#, and that judgement is here.
//
// THE KEY IS WHAT MAKES THE MENU A SET. The menu is assembled in four passes over three different
// sources and the same name can arrive from more than one of them, so every row carries the key its
// pass would dedupe it under. Rows within one pass never collide; the key exists so that passes
// cannot.
class EditorCompletionMenuRow {
    labelValue: string
    kindValue: int
    detailValue: string
    insertTextValue: string
    isSnippetValue: bool
    sortTextValue: string
    documentationValue: string?
    keyValue: string

    Label: string => labelValue
    Kind: int => kindValue
    Detail: string => detailValue
    InsertText: string => insertTextValue
    IsSnippet: bool => isSnippetValue
    SortText: string => sortTextValue
    Documentation: string? => documentationValue
    Key: string => keyValue

    constructor(Label: string, Kind: int, Detail: string, InsertText: string, IsSnippet: bool, SortText: string, Documentation: string?, Key: string) {
        labelValue = Label
        kindValue = Kind
        detailValue = Detail
        insertTextValue = InsertText
        isSnippetValue = IsSnippet
        sortTextValue = SortText
        documentationValue = Documentation
        keyValue = Key
    }
}

// WHAT THE EDITOR OFFERS WHEN THE READER IS TYPING A NAME.
//
// Four things, and they were four hundred lines of `CompletionHandler.cs`:
//
//   * THE LANGUAGE ITSELF — every keyword, every primitive type name and the five snippets. A table
//     of what N# is, which belongs with the compiler rather than beside an LSP handler.
//   * THE FILE'S OWN DECLARATIONS, each with the grey signature line the reader reads to tell two
//     same-named things apart.
//   * WHERE THE CARET IS: how much of a name has been typed, and whether the line is an `import`
//     and how much of a namespace it names.
//   * THE ORDER THE WHOLE LIST APPEARS IN.
//
// THE SIX RANKS ARE THE MENU'S SPINE. What is local outranks what the project offers, which
// outranks the language's own words, which outrank what is merely importable — so a reader's own
// name is never buried under sixty keywords, and an auto-import is never offered above something
// already in scope. They are strings rather than numbers because an LSP `sortText` is compared as
// TEXT, and four fixed digits compare as the numbers they spell.
class EditorCompletionMenuFacts {
    static SortLocal: string => "0000"
    static SortProjectInScope: string => "0100"
    static SortLanguage: string => "0500"
    static SortExternalInScope: string => "0600"
    static SortProjectImportable: string => "0800"
    static SortExternalImportable: string => "0900"

    // THE SORT KEY: rank, then the label folded to lower case so that `Box` and `box` interleave the
    // way a reader expects rather than by their code points, then a qualifier that keeps two rows of
    // the same rank and label — a keyword and a snippet both called `func` — apart and stable.
    static func SortText(rank: string, label: string, qualifier: string): string {
        return rank + "_" + label.ToLowerInvariant() + "_" + qualifier.ToLowerInvariant()
    }

    // The rank an importable external type takes: already in scope, or needing the import edit.
    static func ExternalSortText(isInScope: bool, name: string, namespaceName: string): string {
        if isInScope {
            return SortText(SortExternalInScope, name, namespaceName)
        }

        return SortText(SortExternalImportable, name, namespaceName)
    }

    // EVERY WORD THE LANGUAGE ITSELF OFFERS, in the order the menu carries them: keywords, then the
    // snippets, then the primitive type names.
    //
    // A NAME CAN APPEAR TWICE AND THAT IS THE POINT — `func` is both a keyword and a snippet, and
    // the reader who wants the skeleton and the reader who wants the word are both served, which is
    // why the two rows carry different keys.
    static func LanguageRows(): List<EditorCompletionMenuRow> {
        rows := new List<EditorCompletionMenuRow>()

        for keyword in Keywords() {
            rows.Add(new EditorCompletionMenuRow(keyword, KeywordKind, "keyword", keyword, false, SortText(SortLanguage, keyword, "keyword"), null, "keyword:" + keyword))
        }

        snippetLabels := SnippetLabels()
        snippetDetails := SnippetDetails()
        snippetBodies := SnippetBodies()
        index := 0
        while index < snippetLabels.Length {
            rows.Add(new EditorCompletionMenuRow(snippetLabels[index], SnippetKind, snippetDetails[index], snippetBodies[index], true, SortText(SortLanguage, snippetLabels[index], "snippet"), null, "snippet:" + snippetLabels[index]))
            index = index + 1
        }

        for primitive in PrimitiveTypes() {
            rows.Add(new EditorCompletionMenuRow(primitive, KeywordKind, "primitive type", primitive, false, SortText(SortLanguage, primitive, "primitive"), null, "primitive:" + primitive))
        }

        return rows
    }

    // THE FILE'S OWN DECLARATIONS AS MENU ROWS, one per name, in the order the symbol table holds
    // them — first declaration's position, last declaration's meaning, which is what a table keyed
    // by name does.
    static func DocumentSymbolRows(unit: CompilationUnit?, text: string?): List<EditorCompletionMenuRow> {
        rows := new List<EditorCompletionMenuRow>()

        for symbol in MenuSymbols(unit, text) {
            documentation: string? = null
            if !String.IsNullOrEmpty(symbol.Documentation) {
                documentation = symbol.Documentation
            }

            rows.Add(new EditorCompletionMenuRow(symbol.Name, CompletionKind(symbol.Kind), SymbolDetailText(symbol), symbol.Name, false, SortText(SortLocal, symbol.Name, "document"), documentation, "scope:" + symbol.Name))
        }

        return rows
    }

    // WHAT THE ANALYZER RESOLVED AT THE CARET, as menu rows: every variable visible from this
    // position and every function the bound model knows.
    //
    // THE VISIBLE SET IS WIDENED, NEVER NARROWED. A model with scopes answers for the position; a
    // model without them offers everything it bound. Either way every variable the model knows is
    // added afterwards if the position did not already offer it, because a name the reader can
    // legally write and the menu omits is worse than a name offered one scope too early.
    //
    // A NAME THAT IS ALSO A FUNCTION IS NOT OFFERED AS A VARIABLE, and a function whose name a
    // type already carries is not offered at all — it is a member, reachable after a dot, and
    // `TypeMemberNames` is the same table the member list reads.
    static func SemanticRows(semanticModel: SemanticModel?, unit: CompilationUnit?, text: string?, line: int, character: int): List<EditorCompletionMenuRow> {
        rows := new List<EditorCompletionMenuRow>()
        if semanticModel == null {
            return rows
        }

        visibleVariables := new Dictionary<string, TypeInfo>()
        if semanticModel.Scopes.Count > 0 {
            visibleVariables = semanticModel.GetVisibleVariablesAtPosition(line + 1, character + 1)
        } else {
            for declared in semanticModel.Variables {
                visibleVariables[declared.Key] = declared.Value
            }
        }

        for declared in semanticModel.Variables {
            if !visibleVariables.ContainsKey(declared.Key) {
                visibleVariables[declared.Key] = declared.Value
            }
        }

        for visible in visibleVariables {
            if semanticModel.Functions.ContainsKey(visible.Key) {
                continue
            }

            detail := "variable: " + TypeText(visible.Value)
            rows.Add(new EditorCompletionMenuRow(visible.Key, VariableKind, detail, visible.Key, false, SortText(SortLocal, visible.Key, "variable"), null, "scope:" + visible.Key))
        }

        memberNames := new HashSet<string>()
        for memberName in TypeMemberNames(unit, text) {
            memberNames.Add(memberName)
        }

        for bound in semanticModel.Functions {
            if memberNames.Contains(bound.Key) {
                continue
            }

            detail := "func: " + TypeText(bound.Value)
            rows.Add(new EditorCompletionMenuRow(bound.Key, FunctionKind, detail, bound.Key, false, SortText(SortLocal, bound.Key, "function"), null, "scope:" + bound.Key))
        }

        return rows
    }

    // The grey line beside a resolved name is the type the analyzer printed, whatever that is.
    static func TypeText(typeInfo: TypeInfo?): string {
        if typeInfo == null {
            return ""
        }

        return typeInfo.ToString() ?? ""
    }

    // THE NAMES THAT BELONG TO A TYPE RATHER THAN TO THE FILE. A method is offered after a dot, not
    // on its own, so the identifier menu drops a function whose name a type already carries.
    static func TypeMemberNames(unit: CompilationUnit?, text: string?): List<string> {
        names := new List<string>()

        for symbol in MenuSymbols(unit, text) {
            if symbol.Kind == EditorSymbolTableKind.Class || symbol.Kind == EditorSymbolTableKind.Struct || symbol.Kind == EditorSymbolTableKind.Record || symbol.Kind == EditorSymbolTableKind.Interface {
                for member in symbol.Members {
                    names.Add(member.Name)
                }
            }
        }

        return names
    }

    // THE SYMBOL TABLE AS THE MENU READS IT: one row per name, keeping each name's FIRST position
    // and its LAST meaning. Both halves matter — the position is what makes the menu stable while a
    // file is being edited, and the meaning is what makes it agree with hover.
    static func MenuSymbols(unit: CompilationUnit?, text: string?): List<EditorSymbolInfoRow> {
        order := new List<string>()
        byName := new Dictionary<string, EditorSymbolInfoRow>()

        for row in EditorSymbolTableFacts.SymbolInfoRows(unit, text) {
            if !byName.ContainsKey(row.Name) {
                order.Add(row.Name)
            }

            byName[row.Name] = row
        }

        symbols := new List<EditorSymbolInfoRow>()
        for name in order {
            symbols.Add(byName[name])
        }

        return symbols
    }

    // THE GREY LINE BESIDE A DECLARATION'S NAME: its modifiers, what kind of thing it is, its name,
    // and — for anything callable — its parameter list and return type.
    //
    // THE MODIFIER ORDER IS FIXED AND IS NOT THE SOURCE'S. `public static` and `static public` are
    // the same declaration, and a menu that echoed each reader's own order would make two identical
    // things look different. Accessibility first, then lifetime, then the inheritance words.
    static func SymbolDetailText(symbol: EditorSymbolInfoRow): string {
        builder := new StringBuilder()
        modifierText := ModifierWords(symbol.Modifiers)
        if modifierText.Length > 0 {
            builder.Append(modifierText)
            builder.Append(" ")
        }

        builder.Append(KindWord(symbol.Kind))
        builder.Append(" ")
        builder.Append(symbol.Name)

        if symbol.Kind == EditorSymbolTableKind.Function || symbol.Kind == EditorSymbolTableKind.Method || symbol.Kind == EditorSymbolTableKind.Constructor {
            builder.Append(" (")
            builder.Append(ParameterListText(symbol.Parameters))
            builder.Append(")")

            if !String.IsNullOrEmpty(symbol.TypeName) {
                builder.Append(" : ")
                builder.Append(symbol.TypeName ?? "")
            }

            return builder.ToString()
        }

        if !String.IsNullOrEmpty(symbol.TypeName) {
            builder.Append(" : ")
            builder.Append(symbol.TypeName ?? "")
        }

        return builder.ToString()
    }

    static func ParameterListText(parameters: List<EditorSymbolParameterRow>): string {
        builder := new StringBuilder()
        index := 0
        while index < parameters.Count {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(parameters[index].Name)
            builder.Append(": ")
            builder.Append(parameters[index].TypeName ?? "")
            index = index + 1
        }

        return builder.ToString()
    }

    static func ModifierWords(modifiers: Modifiers): string {
        builder := new StringBuilder()
        AppendModifier(builder, modifiers, Modifiers.Public, "public")
        AppendModifier(builder, modifiers, Modifiers.Private, "private")
        AppendModifier(builder, modifiers, Modifiers.Protected, "protected")
        AppendModifier(builder, modifiers, Modifiers.Internal, "internal")
        AppendModifier(builder, modifiers, Modifiers.Static, "static")
        AppendModifier(builder, modifiers, Modifiers.Abstract, "abstract")
        AppendModifier(builder, modifiers, Modifiers.Virtual, "virtual")
        AppendModifier(builder, modifiers, Modifiers.Override, "override")
        AppendModifier(builder, modifiers, Modifiers.Sealed, "sealed")
        AppendModifier(builder, modifiers, Modifiers.Async, "async")
        return builder.ToString()
    }

    static func AppendModifier(builder: StringBuilder, modifiers: Modifiers, flag: Modifiers, word: string) {
        if (modifiers & flag) != flag {
            return
        }

        if builder.Length > 0 {
            builder.Append(" ")
        }

        builder.Append(word)
    }

    // The kind as the grey line says it, which is the kind's own name in lower case.
    static func KindWord(kind: EditorSymbolTableKind): string {
        return kind.ToString().ToLower()
    }

    // WHICH PROTOCOL SLOT A DECLARED NAME TAKES. A record and a union both draw as classes here —
    // the icon says "a type you can name", and that is true of both — while the member list after a
    // dot draws a union as an enum, because there the question is what you may write next.
    static func CompletionKind(kind: EditorSymbolTableKind): int {
        if kind == EditorSymbolTableKind.Class || kind == EditorSymbolTableKind.Record || kind == EditorSymbolTableKind.Union {
            return 7
        }
        if kind == EditorSymbolTableKind.Struct {
            return 22
        }
        if kind == EditorSymbolTableKind.Interface {
            return 8
        }
        if kind == EditorSymbolTableKind.Enum {
            return 13
        }
        if kind == EditorSymbolTableKind.Function {
            return 3
        }
        if kind == EditorSymbolTableKind.Method {
            return 2
        }
        if kind == EditorSymbolTableKind.Property {
            return 10
        }
        if kind == EditorSymbolTableKind.Field {
            return 5
        }
        if kind == EditorSymbolTableKind.EnumMember {
            return 20
        }
        if kind == EditorSymbolTableKind.Constructor {
            return 4
        }

        // A parameter and a local are both variables, and so is anything this table has not been
        // taught — a name in the menu is a thing you can write, and Variable is that icon.
        return 6
    }

    // HOW MUCH OF A NAME THE READER HAS TYPED, which is what decides which importable types are
    // worth offering at all. The scan runs BACKWARDS from the caret over identifier characters, so
    // a caret in the middle of a word answers the half before it.
    static func IdentifierPrefix(text: string?, line: int, character: int): string {
        lines := EditorSymbolTableFacts.SourceLines(text)
        if line < 0 || line >= lines.Length {
            return ""
        }

        lineText := lines[line]
        end := character
        if end < 0 {
            end = 0
        }

        if end > lineText.Length {
            end = lineText.Length
        }

        start := end
        while start > 0 && IdentifierText.IsPart(lineText[start - 1]) {
            start = start - 1
        }

        return lineText.Substring(start, end - start)
    }

    // THE TEXT OF THE CARET'S OWN LINE UP TO THE CARET, which is all three of the questions below
    // ever look at. A caret past the end of its line sees the whole line, and a caret on a line the
    // file does not have sees nothing.
    static func TextBeforeCaret(text: string?, line: int, character: int): string {
        lines := EditorSymbolTableFacts.SourceLines(text)
        if line < 0 || line >= lines.Length {
            return ""
        }

        lineText := lines[line]
        end := character
        if end < 0 {
            end = 0
        }

        if end > lineText.Length {
            end = lineText.Length
        }

        return lineText.Substring(0, end)
    }

    // WHETHER THE CARET SITS AFTER A DOT, and so is asking what a receiver offers rather than what
    // is in scope. The same question `nlc query completions` asks, asked of the same owner.
    static func IsMemberAccessAt(text: string?, line: int, character: int): bool {
        lines := EditorSymbolTableFacts.SourceLines(text)
        if line < 0 || line >= lines.Length {
            return false
        }

        return CompletionEngineKernels.IsCompletionMemberAccessContext(TextBeforeCaret(text, line, character))
    }

    // The import prefix at a caret, or null when the caret is not on an `import` line.
    static func ImportPrefixAt(text: string?, line: int, character: int): string? {
        lines := EditorSymbolTableFacts.SourceLines(text)
        if line >= lines.Length {
            return null
        }

        return ImportPrefix(TextBeforeCaret(text, line, character))
    }

    // WHETHER THE CARET IS NAMING A NAMESPACE ON AN `import` LINE, and how much of one.
    //
    // NULL MEANS "NOT AN IMPORT", WHICH IS NOT THE SAME AS THE EMPTY PREFIX: `import ` with nothing
    // after it offers every root namespace, while an ordinary line offers none. A QUOTED import is a
    // package reference rather than a namespace and is left alone, and an `as` alias is cut off
    // because the namespace ends where the alias begins.
    static func ImportPrefix(beforeCursor: string): string? {
        trimmed := beforeCursor.TrimStart()
        if !trimmed.StartsWith("import", StringComparison.Ordinal) {
            return null
        }

        remainder := trimmed.Substring("import".Length)
        if remainder.Length == 0 || !Char.IsWhiteSpace(remainder[0]) {
            return null
        }

        importTarget := remainder.TrimStart()
        if importTarget.StartsWith("\"", StringComparison.Ordinal) {
            return null
        }

        aliasIndex := importTarget.IndexOf(" as ", StringComparison.Ordinal)
        if aliasIndex >= 0 {
            importTarget = importTarget.Substring(0, aliasIndex)
        }

        return importTarget.Trim()
    }

    // THE GREY TEXT BESIDE A NAMESPACE SUGGESTION: the namespace the reader would end up with, not
    // the segment being offered. Typing `System.Col` and choosing `Collections` says
    // `namespace System.Collections`, because the LAST segment is the one being replaced.
    static func ImportSuggestionDetail(importPrefix: string, segment: string): string {
        if String.IsNullOrWhiteSpace(importPrefix) {
            return "namespace " + segment
        }

        if importPrefix.EndsWith(".", StringComparison.Ordinal) {
            return "namespace " + importPrefix + segment
        }

        lastDot := importPrefix.LastIndexOf('.')
        if lastDot < 0 {
            return "namespace " + segment
        }

        return "namespace " + importPrefix.Substring(0, lastDot + 1) + segment
    }

    // LSP CompletionItemKind.Keyword, which primitive type names share: `int` is a word of the
    // language and not a type the project declares.
    static KeywordKind: int => 14

    // LSP CompletionItemKind.Snippet.
    static SnippetKind: int => 15

    // LSP CompletionItemKind.Variable and CompletionItemKind.Function, for the names the bound
    // model resolved rather than the ones the syntax tree declared.
    static VariableKind: int => 6
    static FunctionKind: int => 3

    // EVERY WORD N# RESERVES, in the order the menu offers them — declaration words first, then
    // control flow, then the modifiers, then the operators and the literals, then the words that
    // belong to tests.
    static func Keywords(): string[] {
        return [
            "func",
            "class",
            "struct",
            "record",
            "interface",
            "enum",
            "union",
            "namespace",
            "using",
            "import",
            "if",
            "else",
            "for",
            "foreach",
            "while",
            "return",
            "break",
            "continue",
            "match",
            "switch",
            "case",
            "when",
            "yield",
            "await",
            "async",
            "throw",
            "try",
            "catch",
            "finally",
            "lock",
            "new",
            "this",
            "base",
            "static",
            "virtual",
            "override",
            "abstract",
            "sealed",
            "partial",
            "readonly",
            "const",
            "file",
            "duck",
            "public",
            "private",
            "internal",
            "protected",
            "required",
            "init",
            "let",
            "type",
            "out",
            "ref",
            "in",
            "params",
            "true",
            "false",
            "null",
            "is",
            "as",
            "typeof",
            "nameof",
            "checked",
            "unchecked",
            "and",
            "or",
            "not",
            "with",
            "immutable",
            "print",
            "test",
            "assert",
            "implicit",
            "explicit",
            "setup",
            "teardown"
        ]
    }

    // THE TYPE NAMES THAT ARE PART OF THE LANGUAGE rather than of any assembly.
    static func PrimitiveTypes(): string[] {
        return [
            "int",
            "long",
            "float",
            "double",
            "bool",
            "string",
            "void",
            "object",
            "byte",
            "short",
            "char",
            "decimal",
            "uint",
            "ulong",
            "ushort",
            "sbyte"
        ]
    }

    // THE FIVE SKELETONS, as three parallel tables: what the reader types, what the grey line says,
    // and the body with its tab stops. `$1` through `$0` are the client's own placeholder syntax.
    static func SnippetLabels(): string[] {
        return ["func", "if", "match", "for", "type"]
    }

    static func SnippetDetails(): string[] {
        return ["func declaration", "if statement", "match expression", "for-in loop", "type alias"]
    }

    static func SnippetBodies(): string[] {
        return [
            "func ${1:name}(${2:params}): ${3:void} {\n\t$0\n}",
            "if ${1:condition} {\n\t$0\n}",
            "match ${1:value} {\n\t${2:pattern} => ${3:result},\n\t_ => ${0:default}\n}",
            "for ${1:item} in ${2:collection} {\n\t$0\n}",
            "type ${1:Name} = ${0:Type}"
        ]
    }
}
