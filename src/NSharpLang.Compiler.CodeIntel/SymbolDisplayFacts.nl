namespace NSharpLang.Compiler.CodeIntelligence

// HOW A SYMBOL KIND AND A COMPLETION CONTEXT ARE SPELLED, OWNED ONCE.
//
// There were four tables over `SymbolKind` and two over `CompletionContext`. Two of the four were
// identical to the character — `DefinitionSearchKernels.SymbolKindText` and
// `OutputFormatterJsonKernels.SymbolKindToJsonText`, the lower-case spelling `nlc query --json`
// writes. The other two, `OutputFormatterTextKernels.SymbolKindText` and
// `DocCommandKernels.SymbolKindDisplay`, listed the SAME sixteen PascalCase spellings and then
// disagreed only about a kind the table does not name: the first answers the kind's ordinal, the
// second an empty string. `SymbolKind.Event` is such a kind for both.
//
// That disagreement is why the PascalCase table answers the EMPTY STRING for a kind it does not
// name: the doc page's answer is the table's answer, and the text formatter adds its own on top. The
// committed output of both is unchanged, and a kind added to the enum now reaches all of them at
// once instead of three of four.
static class SymbolDisplayFacts {

    // The JSON spelling: lower-case, `camelCase` where the name is two words, `"unknown"` for a kind
    // this table does not name.
    static func SymbolKindJsonText(kind: SymbolKind): string {
        return match kind {
            SymbolKind.Function => "function",
            SymbolKind.Class => "class",
            SymbolKind.Struct => "struct",
            SymbolKind.Record => "record",
            SymbolKind.Interface => "interface",
            SymbolKind.Enum => "enum",
            SymbolKind.Union => "union",
            SymbolKind.Property => "property",
            SymbolKind.Field => "field",
            SymbolKind.Method => "method",
            SymbolKind.Variable => "variable",
            SymbolKind.Parameter => "parameter",
            SymbolKind.Constructor => "constructor",
            SymbolKind.EnumMember => "enumMember",
            SymbolKind.TypeAlias => "typeAlias",
            SymbolKind.Test => "test",
            SymbolKind.Event => "event",
            _ => "unknown"
        }
    }

    // The human spelling. THE EMPTY STRING MEANS THIS TABLE DOES NOT NAME THAT KIND, which is
    // `SymbolKind.Event` today — and is also exactly what the doc page has always printed for it, so
    // `DocCommandKernels` calls this directly. The text formatter wraps it with its own answer.
    //
    // COMPILER: the arm would read `_ => null` and the function would return `string?`, which says
    // "absent" rather than overloading a value. A `null` literal as a `match` arm result declines at
    // `emit.expression.unhandled-kind` (node kind 5) — measured at the TIP compiler, not only under
    // the pinned seed, so this is a backend gap and not a reseed away. It is not one of the audit's
    // D1-D10 language gaps.
    static func SymbolKindPascalText(kind: SymbolKind): string {
        return match kind {
            SymbolKind.Function => "Function",
            SymbolKind.Class => "Class",
            SymbolKind.Struct => "Struct",
            SymbolKind.Record => "Record",
            SymbolKind.Interface => "Interface",
            SymbolKind.Enum => "Enum",
            SymbolKind.Union => "Union",
            SymbolKind.Property => "Property",
            SymbolKind.Field => "Field",
            SymbolKind.Method => "Method",
            SymbolKind.Variable => "Variable",
            SymbolKind.Parameter => "Parameter",
            SymbolKind.Constructor => "Constructor",
            SymbolKind.EnumMember => "EnumMember",
            SymbolKind.TypeAlias => "TypeAlias",
            SymbolKind.Test => "Test",
            _ => ""
        }
    }

    static func CompletionContextText(context: CompletionContext): string {
        return match context {
            CompletionContext.MemberAccess => "memberaccess",
            CompletionContext.Identifier => "identifier",
            CompletionContext.Namespace => "namespace",
            _ => "unknown"
        }
    }
}
