namespace NSharpLang.Compiler.CodeIntelligence

// WHAT MAY BE RENAMED, AND WHAT A REFUSAL SAYS.
//
// Two tables and four sentences that used to sit in `PrepareRenameHandler`, `RenameHandler` and
// `ReferencesHandler` — the last two holding their own copies of the same words.
//
// THE TABLES ARE THE LANGUAGE'S OWN WORDS, which is why they belong with the compiler: renaming
// `func` or `int` is not a refactor, it is a syntax error waiting to happen, so the rename dialog
// never opens on one. This list is NOT the completion menu's keyword list and the two must not be
// merged: the menu offers what a reader may usefully type, and this one refuses what a reader may
// not rebind. It includes words the menu leaves out (`file`, `duck`, `implicit`) and spellings the
// language accepts from C# habit (`using`, `foreach`, `switch`).
//
// THE SENTENCES ARE A PROMISE, not a message. Each one says what was refused, WHY, and that
// nothing was edited — because the alternative a reader imagines is a text-only rename, and a
// text-only rename silently edits unrelated symbols that happen to share a name.
class EditorRenameGuardFacts {
    static func IsKeyword(word: string): bool {
        if word == "func" || word == "class" || word == "struct" || word == "record" || word == "interface" {
            return true
        }

        if word == "enum" || word == "union" || word == "namespace" || word == "using" || word == "import" {
            return true
        }

        if word == "if" || word == "else" || word == "for" || word == "foreach" || word == "while" {
            return true
        }

        if word == "return" || word == "break" || word == "continue" || word == "match" || word == "switch" {
            return true
        }

        if word == "case" || word == "when" || word == "yield" || word == "await" || word == "async" {
            return true
        }

        if word == "throw" || word == "try" || word == "catch" || word == "finally" || word == "lock" {
            return true
        }

        if word == "new" || word == "this" || word == "base" || word == "static" || word == "virtual" {
            return true
        }

        if word == "override" || word == "abstract" || word == "sealed" || word == "partial" || word == "readonly" {
            return true
        }

        if word == "const" || word == "duck" || word == "public" || word == "private" {
            return true
        }

        if word == "internal" || word == "protected" || word == "required" || word == "init" || word == "let" {
            return true
        }

        if word == "type" || word == "out" || word == "ref" || word == "params" || word == "true" {
            return true
        }

        // `in` is the `for x in xs` keyword AND the read-only by-reference parameter modifier. It was
        // missing from this guard while it was only the former, which was already wrong: a rename to a
        // reserved word cannot be applied.
        if word == "in" {
            return true
        }

        if word == "false" || word == "null" || word == "is" || word == "as" || word == "typeof" {
            return true
        }

        if word == "nameof" || word == "and" || word == "or" || word == "not" || word == "with" {
            return true
        }

        if word == "immutable" || word == "print" || word == "test" || word == "assert" || word == "implicit" {
            return true
        }

        return word == "explicit"
    }

    static func IsPrimitiveTypeName(word: string): bool {
        if word == "int" || word == "long" || word == "float" || word == "double" {
            return true
        }

        if word == "bool" || word == "string" || word == "void" || word == "object" {
            return true
        }

        if word == "byte" || word == "short" || word == "char" || word == "decimal" {
            return true
        }

        return word == "uint" || word == "ulong" || word == "ushort" || word == "sbyte"
    }

    // The buffer HAS a synchronized project and the strict search still could not say which symbol
    // the caret is on. Falling back to a name search here would rename every unrelated match.
    static func RenameUnresolvedMessage(word: string): string {
        return "Rename for '" + word + "' is unavailable because semantic resolution could not safely identify the selected symbol. No edits were applied; refusing fallback rename to avoid editing unrelated symbols."
    }

    // The same refusal reached from the OTHER side: the symbol is known to the editor's own tables
    // but there is no synchronized project to rename across.
    static func RenameTextOnlyMessage(word: string): string {
        return "Rename for '" + word + "' is unavailable because semantic resolution could not safely identify the selected symbol. No edits were applied; refusing text-only rename to avoid editing unrelated symbols."
    }

    // There IS a project and it did not load. Saving or fixing it is something the reader can
    // actually do, so the sentence says so.
    static func RenameDegradedMessage(word: string): string {
        return "Rename for '" + word + "' is unavailable because semantic project analysis is degraded. Save or fix the project files and retry; refusing text-only rename to avoid editing unrelated symbols."
    }

    static func ReferencesDegradedMessage(word: string): string {
        return "References for '" + word + "' are unavailable because semantic project analysis is degraded. Save or fix the project files and retry; refusing text-only references to avoid showing unrelated symbols."
    }
}
