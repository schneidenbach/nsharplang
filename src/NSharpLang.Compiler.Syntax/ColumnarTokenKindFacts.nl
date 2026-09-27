namespace NSharpLang.Compiler


// THE COLUMNAR TOKEN-KIND ORDINALS, AND THE FOUR SHAPE DECISIONS THAT READ THEM.
//
// The columnar pipeline does not carry `TokenType` values; it carries their ORDINALS as bare `int`
// columns. The columnar lexer writes them (`KeywordKind` and `TokenizeMetadataCore` in
// `CompilerServices/ColumnarLexerKernels.nl`) and every kernel reads them back out of `ck[]`.
// There are therefore TWO tables that must agree: `Token.nl`'s `enum TokenType`, whose member
// ORDER defines the ordinals, and the columnar lexer, which hand-writes them.
//
// Before this owner existed there was a THIRD copy, in a third language:
// `ColumnarProgramInputBuilder.cs` decided what a `ref struct` is, which constructor is the
// synthesized primary constructor, and which token may open a function, constructor, getter or
// setter body, by comparing `ck[...]` to integer literals in C#. Inserting one case into
// `TokenType` moved every one of those literals' meanings and nothing failed. That is the
// TokenType-ordinal hazard this file exists to close: the ordinals are named HERE, once, beside the
// table they index, and `ColumnarTokenKindFacts.tests.nl` pins every name/ordinal pair against BOTH
// tables — the `TokenType` the tree lexer answers for a spelling, and the ordinal the columnar
// lexer writes for the same spelling.
//
// Callers ask the DECISION, never the ordinal. The ordinals are public only so the contracts can
// name them in a failure message; a caller that reaches for one instead of a decision is
// reintroducing exactly the copy this file removed.
class ColumnarTokenKindFacts {

    // `TokenType.Class` — the `class` of `class C { … }`.
    static ClassKind: int => 8

    // `TokenType.Struct` — the `struct` of `struct S { … }`.
    static StructKind: int => 9

    // `TokenType.Duck` — the `duck` of `duck interface I { … }`.
    static DuckKind: int => 11

    // `TokenType.Record` — the `record` of `record R(…)` and `record struct R(…)`.
    static RecordKind: int => 13

    // `TokenType.Ref` — the `ref` of `ref struct S { … }`.
    static RefKind: int => 78

    // `TokenType.Arrow` — the `=>` that opens an expression body.
    static ArrowKind: int => 120

    // `TokenType.LeftBrace` — the `{` that opens a block body.
    static LeftBraceKind: int => 129

    // `TokenType.Func` — the `func` that opens a function, method or local-function declaration.
    static FuncKind: int => 7

    // `TokenType.LeftParen`/`RightParen`, `RightBrace` and `LeftBracket`/`RightBracket` — the other
    // five halves of the three bracket pairs a declaration's extent is balanced over.
    static LeftParenKind: int => 127
    static RightParenKind: int => 128
    static RightBraceKind: int => 130
    static LeftBracketKind: int => 131
    static RightBracketKind: int => 132

    // `TokenType.QuestionBracket` — the `?[` of `items?[0]`, ONE token that opens a `[`…`]` pair.
    static QuestionBracketKind: int => 119

    // A `ref struct` is a VALUE declaration whose declaration keyword is immediately preceded by
    // `ref`. The caller has already established that the declaration is not a reference type; this
    // answers the remaining half.
    static func IsRefStructModifierKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.RefKind
    }

    // A `duck interface` is an interface declaration whose `interface` keyword is immediately
    // preceded by `duck`. It is the ONLY interface the backend may attach to a type structurally; a
    // plain `interface` is nominal, and a type implements it only by naming it in its base list.
    static func IsDuckInterfaceModifierKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.DuckKind
    }

    // A constructor whose "constructor token" is a TYPE DECLARATION KEYWORD is not a constructor
    // the source wrote — it is the primary constructor synthesized from the declaration header, and
    // the field initializers it carries belong to the declaration, not to a body.
    static func IsSynthesizedPrimaryConstructorKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.ClassKind || kind == ColumnarTokenKindFacts.StructKind || kind == ColumnarTokenKindFacts.RecordKind
    }

    // Functions and property getters accept either form of body: a block or an expression body.
    static func IsSupportedBodyStartKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.LeftBraceKind || kind == ColumnarTokenKindFacts.ArrowKind
    }

    // Constructors and property setters accept a block body only. An expression body would have to
    // produce a value, and neither of these returns one.
    static func IsSupportedBlockBodyStartKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.LeftBraceKind
    }

    // `(`, `{`, `[` and `?[` open a nesting level; `)`, `}` and `]` close one. A declaration's extent
    // is measured by balancing them (`ColumnarDeclarationTokenEnd`), so an opener missing here closes
    // a level early and cuts the extent short.
    static func IsOpeningBracketKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.LeftParenKind || kind == ColumnarTokenKindFacts.LeftBraceKind || kind == ColumnarTokenKindFacts.LeftBracketKind || kind == ColumnarTokenKindFacts.QuestionBracketKind
    }

    static func IsClosingBracketKind(kind: int): bool {
        return kind == ColumnarTokenKindFacts.RightParenKind || kind == ColumnarTokenKindFacts.RightBraceKind || kind == ColumnarTokenKindFacts.RightBracketKind
    }
}
