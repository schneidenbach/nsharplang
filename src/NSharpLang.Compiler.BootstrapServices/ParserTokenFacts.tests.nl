namespace NSharpLang.Compiler


// THE CANONICAL CONTRACTS FOR `ParserTokenFacts`, IN N#.
//
// These replace `tests/ParserTokenFactsTests.cs`, the last canonical C# assertion layer over
// `ParserTokenFacts.nl`. The subject is the parser's token-classification table: ten predicates
// that decide where an expression may begin, which keyword opens a declaration, what closes an
// expression, and which tokens the error-recovery walk may resynchronise on.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every argument is a `TokenType` member, and a
// dependency-assembly ENUM MEMBER declines at `emit.typed-local.initializer` from a `tests/native`
// project — in a table row it is refused earlier still, by NL310.
//
// THE COVERAGE IS THE DELETED FILE'S OWN SHAPE, EXHAUSTIVE AND CARRIED OVER. The C# swept
// `Enum.GetValues<TokenType>()` against a `HashSet` of the expected members, asserting BOTH
// directions for every token; it did that by passing each predicate as a `Func<TokenType, bool>`
// VALUE, which this estate does not express. The sweep is therefore written out once per predicate
// over an explicit 148-member table — the same 148 members `Enum.GetValues<TokenType>()` yields —
// so every predicate still answers for EVERY token, and a new `TokenType` member that a predicate
// wrongly admits is still caught.
//
// THE THREE THINGS IT IS EASY TO GET WRONG:
//
// (1) THE TWO EXPRESSION-START TABLES ARE NOT THE SAME TABLE, AND THE DIFFERENCE IS EXACTLY ONE
// TOKEN. `CanStartExpression` (the STATEMENT operand start) admits `...`; `IsExpressionStart` (the
// CAST operand start) does not, because a spread is not a cast operand. Folding them would break
// spread arguments, and nothing else would notice.
//
// THE SECOND DIFFERENCE WAS A DEFECT, NOT A FACT, AND IT IS GONE. This file used to say that
// `CanStartExpression` REFUSES a triple-quote string and that the refusal was one of the two things
// making these two tables. It was a MISSING ROW wearing a rationale. `ParseReturnStatement` asks
// this predicate whether a `return` carries a value, so `return """abc"""` parsed as a bare `return`
// followed by a stray expression statement and `nlc check` reported NL305 + NL312 + NL006 on correct
// source; `ParseAdditive`'s missing-operand boundary asked it too, so `"a" + """b"""` was refused the
// same way. A predicate that admits two of the three string forms is the SHAPE of that defect, which
// is why the sweep below now names all three together.
//
// (2) `IsCastOperandStart` IS `IsExpressionStart` MINUS `[`, AND THE CARVE-OUT IS AMBIGUITY, NOT
// TASTE. `(T)[1, 2]` would otherwise parse as a cast of a collection literal instead of an index.
//
// (3) THE RECOVERY TABLES OVERLAP AND MUST STILL DIFFER. `IsDeclarationKeyword` is
// `IsTypeDeclarationKeyword` plus six; `readonly` is BOTH a modifier and a statement start;
// `throw`, `func` and `match` each appear in more than one table. Each predicate is swept over all
// 148 tokens rather than spot-checked, so an arm added to the wrong table is caught by the OTHER
// table's sweep.
func ParserTokenContains(candidates: TokenType[], tokenType: TokenType): bool {
    index := 0
    while index < candidates.Length {
        if candidates[index] == tokenType {
            return true
        }

        index = index + 1
    }

    return false
}

// Every member of `TokenType`, in declaration order -- the estate's spelling of the deleted file's
// `Enum.GetValues<TokenType>()`.
func ParserTokenAllTokenTypes(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.Func,
        TokenType.Class,
        TokenType.Struct,
        TokenType.Interface,
        TokenType.Duck,
        TokenType.Union,
        TokenType.Record,
        TokenType.Enum,
        TokenType.Namespace,
        TokenType.Using,
        TokenType.Import,
        TokenType.Package,
        TokenType.Let,
        TokenType.Must,
        TokenType.Const,
        TokenType.Readonly,
        TokenType.If,
        TokenType.Else,
        TokenType.For,
        TokenType.Foreach,
        TokenType.While,
        TokenType.In,
        TokenType.Return,
        TokenType.Yield,
        TokenType.Match,
        TokenType.Switch,
        TokenType.Case,
        TokenType.Default,
        TokenType.Break,
        TokenType.Continue,
        TokenType.Throw,
        TokenType.Try,
        TokenType.Catch,
        TokenType.Finally,
        TokenType.New,
        TokenType.This,
        TokenType.Base,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.Is,
        TokenType.As,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Print,
        TokenType.Where,
        TokenType.When,
        TokenType.AndKeyword,
        TokenType.OrKeyword,
        TokenType.NotKeyword,
        TokenType.Virtual,
        TokenType.Override,
        TokenType.Abstract,
        TokenType.Sealed,
        TokenType.Partial,
        TokenType.Static,
        TokenType.Public,
        TokenType.Private,
        TokenType.Internal,
        TokenType.Protected,
        TokenType.Async,
        TokenType.Await,
        TokenType.Immutable,
        TokenType.With,
        TokenType.Type,
        TokenType.Test,
        TokenType.Assert,
        TokenType.Operator,
        TokenType.Required,
        TokenType.Init,
        TokenType.Ref,
        TokenType.Out,
        TokenType.Lock,
        TokenType.File,
        TokenType.Params,
        TokenType.Checked,
        TokenType.Unchecked,
        TokenType.Implicit,
        TokenType.Explicit,
        TokenType.Newtype,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Star,
        TokenType.Slash,
        TokenType.Percent,
        TokenType.Assign,
        TokenType.PlusAssign,
        TokenType.MinusAssign,
        TokenType.StarAssign,
        TokenType.SlashAssign,
        TokenType.Equal,
        TokenType.NotEqual,
        TokenType.Less,
        TokenType.LessEqual,
        TokenType.Greater,
        TokenType.GreaterEqual,
        TokenType.And,
        TokenType.Or,
        TokenType.Not,
        TokenType.BitwiseAnd,
        TokenType.BitwiseOr,
        TokenType.BitwiseXor,
        TokenType.BitwiseNot,
        TokenType.LeftShift,
        TokenType.RightShift,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Question,
        TokenType.QuestionQuestion,
        TokenType.QuestionQuestionAssign,
        TokenType.QuestionDot,
        TokenType.QuestionBracket,
        TokenType.Arrow,
        TokenType.ColonAssign,
        TokenType.Colon,
        TokenType.DoubleColon,
        TokenType.Dot,
        TokenType.DotDot,
        TokenType.DotDotDot,
        TokenType.LeftParen,
        TokenType.RightParen,
        TokenType.LeftBrace,
        TokenType.RightBrace,
        TokenType.LeftBracket,
        TokenType.RightBracket,
        TokenType.Semicolon,
        TokenType.Comma,
        TokenType.Eof,
        TokenType.Newline,
        TokenType.Unknown,
        TokenType.PreprocessorDirective,
        TokenType.Comment,
        TokenType.MultiLineComment,
        TokenType.XmlDocComment,
        TokenType.Lifetime,
        TokenType.Alloc,
        TokenType.Allow,
        TokenType.Stackalloc,
        TokenType.Unsafe,
        TokenType.Scoped
    ]
}

// The ten expected sets, transcribed from the deleted file's ten `AssertTokenSet` calls.

func ParserTokenCanStartExpressionSet(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.New,
        TokenType.Alloc,
        TokenType.Stackalloc,
        TokenType.Match,
        TokenType.This,
        TokenType.Base,
        TokenType.LeftParen,
        TokenType.LeftBracket,
        TokenType.Immutable,
        TokenType.DotDotDot,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Not,
        TokenType.BitwiseNot,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Must,
        TokenType.Await,
        TokenType.Throw,
        TokenType.Checked,
        TokenType.Unchecked,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Default
    ]
}

func ParserTokenIsExpressionStartSet(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.Default,
        TokenType.New,
        TokenType.Alloc,
        TokenType.Stackalloc,
        TokenType.This,
        TokenType.Base,
        TokenType.LeftParen,
        TokenType.LeftBracket,
        TokenType.Immutable,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Not,
        TokenType.BitwiseNot,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Must,
        TokenType.Await,
        TokenType.Throw,
        TokenType.Match,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Checked,
        TokenType.Unchecked
    ]
}

func ParserTokenIsCastOperandStartSet(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.True,
        TokenType.False,
        TokenType.Null,
        TokenType.Default,
        TokenType.New,
        TokenType.Alloc,
        TokenType.Stackalloc,
        TokenType.This,
        TokenType.Base,
        TokenType.LeftParen,
        TokenType.Immutable,
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Not,
        TokenType.BitwiseNot,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Must,
        TokenType.Await,
        TokenType.Throw,
        TokenType.Match,
        TokenType.Typeof,
        TokenType.Nameof,
        TokenType.Sizeof,
        TokenType.Checked,
        TokenType.Unchecked
    ]
}

func ParserTokenIsTypeDeclarationKeywordSet(): TokenType[] {
    return [
        TokenType.Class,
        TokenType.Struct,
        TokenType.Record,
        TokenType.Interface,
        TokenType.Union,
        TokenType.Enum,
        TokenType.Type
    ]
}

func ParserTokenIsDeclarationKeywordSet(): TokenType[] {
    return [
        TokenType.Func,
        TokenType.Class,
        TokenType.Struct,
        TokenType.Record,
        TokenType.Interface,
        TokenType.Union,
        TokenType.Enum,
        TokenType.Type,
        TokenType.Test,
        TokenType.Implicit,
        TokenType.Explicit,
        TokenType.Duck,
        TokenType.Ref
    ]
}

func ParserTokenIsModifierKeywordSet(): TokenType[] {
    return [
        TokenType.Static,
        TokenType.Internal,
        TokenType.Protected,
        TokenType.Virtual,
        TokenType.Override,
        TokenType.Abstract,
        TokenType.Sealed,
        TokenType.Readonly,
        TokenType.Partial,
        TokenType.Async,
        TokenType.File
    ]
}

func ParserTokenIsStatementStartKeywordSet(): TokenType[] {
    return [
        TokenType.Let,
        TokenType.Const,
        TokenType.Readonly,
        TokenType.If,
        TokenType.For,
        TokenType.Foreach,
        TokenType.While,
        TokenType.Return,
        TokenType.Yield,
        TokenType.Break,
        TokenType.Continue,
        TokenType.Throw,
        TokenType.Try,
        TokenType.Using,
        TokenType.Lock,
        TokenType.Switch,
        TokenType.Print,
        TokenType.Assert,
        TokenType.Unsafe,
        TokenType.Allow,
        TokenType.Func,
        TokenType.Semicolon,
        TokenType.LeftBrace
    ]
}

func ParserTokenIsAssignmentOperatorSet(): TokenType[] {
    return [
        TokenType.Assign,
        TokenType.PlusAssign,
        TokenType.MinusAssign,
        TokenType.StarAssign,
        TokenType.SlashAssign,
        TokenType.QuestionQuestionAssign
    ]
}

func ParserTokenIsExpressionTerminatorSet(): TokenType[] {
    return [
        TokenType.RightBrace,
        TokenType.RightParen,
        TokenType.RightBracket,
        TokenType.Comma,
        TokenType.Semicolon,
        TokenType.Eof
    ]
}

func ParserTokenIsTypeReferenceStartSet(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.LeftParen,
        TokenType.BitwiseAnd
    ]
}

// The guard the sweep test uses: every member of an expected set must appear in the swept table.
func ParserTokenAssertSetIsSwept(expected: TokenType[], all: TokenType[]) {
    index := 0
    while index < expected.Length {
        assert ParserTokenContains(all, expected[index])
        index = index + 1
    }
}

// ---- the sweep is over the WHOLE enum ------------------------------------------------------------

// NOT IN THE DELETED FILE, and it is what makes every sweep below non-vacuous: the table swept is
// the whole enum, and every expected member is IN it, so a mistyped expectation cannot quietly
// exclude itself from its own sweep.
test "parser token facts sweep every declared token type" {
    all := ParserTokenAllTokenTypes()

    assert all.Length == 148
    assert all[0] == TokenType.Identifier
    assert all[all.Length - 1] == TokenType.Scoped

    assert ParserTokenContains(all, TokenType.Eof)
    assert ParserTokenContains(all, TokenType.Type)
    assert ParserTokenContains(all, TokenType.Newtype)
    assert !ParserTokenContains(ParserTokenIsTypeReferenceStartSet(), TokenType.Eof)

    ParserTokenAssertSetIsSwept(ParserTokenCanStartExpressionSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsExpressionStartSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsCastOperandStartSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsTypeDeclarationKeywordSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsDeclarationKeywordSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsModifierKeywordSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsStatementStartKeywordSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsAssignmentOperatorSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsExpressionTerminatorSet(), all)
    ParserTokenAssertSetIsSwept(ParserTokenIsTypeReferenceStartSet(), all)
}

// ---- the ten sweeps -------------------------------------------------------------------------------

// Successor to ParserTokenFacts_CanStartExpressionOwnsStatementOperandStarts, over all 148 tokens.
test "parser token facts own the statement operand starts" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenCanStartExpressionSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.CanStartExpression(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to ParserTokenFacts_IsExpressionStartOwnsCastOperandStarts, over all 148 tokens.
test "parser token facts own the cast operand starts" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsExpressionStartSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsExpressionStart(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to ParserTokenFacts_CastOperandStartExcludesCollectionLiteralAmbiguity. The deleted
// file spot-checked FOUR tokens; this sweeps all 148 against `IsExpressionStart` minus `[`.
test "parser token facts exclude the collection literal from cast operands" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsCastOperandStartSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsCastOperandStart(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the first `AssertTokenSet` of ParserTokenFacts_OwnsParserRecoveryTokenSets.
test "parser token facts own the type declaration keywords" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsTypeDeclarationKeywordSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsTypeDeclarationKeyword(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the second `AssertTokenSet` of ParserTokenFacts_OwnsParserRecoveryTokenSets.
test "parser token facts own the declaration keywords" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsDeclarationKeywordSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsDeclarationKeyword(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the third `AssertTokenSet` of ParserTokenFacts_OwnsParserRecoveryTokenSets.
test "parser token facts own the modifier keywords" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsModifierKeywordSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsModifierKeyword(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the fourth `AssertTokenSet` of ParserTokenFacts_OwnsParserRecoveryTokenSets.
test "parser token facts own the statement start keywords" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsStatementStartKeywordSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsStatementStartKeyword(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the first `AssertTokenSet` of ParserTokenFacts_OwnsOperatorAndTerminatorTokenSets.
test "parser token facts own the assignment operators" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsAssignmentOperatorSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsAssignmentOperator(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the second `AssertTokenSet` of ParserTokenFacts_OwnsOperatorAndTerminatorTokenSets.
test "parser token facts own the expression terminators" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsExpressionTerminatorSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsExpressionTerminator(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// Successor to the third `AssertTokenSet` of ParserTokenFacts_OwnsOperatorAndTerminatorTokenSets.
test "parser token facts own the type reference starts" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsTypeReferenceStartSet()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsTypeReferenceStart(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// ---- the named rows the sweeps encode -------------------------------------------------------------

// Successor to ParserTokenFacts_CastOperandStartExcludesCollectionLiteralAmbiguity' four direct
// assertions, kept verbatim alongside the sweep that generalises them.
test "parser token facts refuse a collection literal as a cast operand" {
    assert !ParserTokenFacts.IsCastOperandStart(TokenType.LeftBracket)
    assert ParserTokenFacts.IsCastOperandStart(TokenType.Identifier)
    assert ParserTokenFacts.IsCastOperandStart(TokenType.TripleQuoteStringLiteral)
    assert !ParserTokenFacts.IsCastOperandStart(TokenType.RightParen)

    // Not in the deleted file: `[` is the ONLY token the cast carve-out removes.
    assert ParserTokenFacts.IsExpressionStart(TokenType.LeftBracket)
    assert ParserTokenFacts.IsCastOperandStart(TokenType.LeftParen)
}

// NOT IN THE DELETED FILE. The two expression tables differ by exactly ONE token — the single fact
// that makes them two tables rather than one. It used to be two; the second was the raw-literal
// defect, and this contract is what would have caught it had it named the three string forms as a
// family instead of pinning the odd one out.
test "parser token facts keep the two expression start tables distinct" {
    assert ParserTokenFacts.CanStartExpression(TokenType.DotDotDot)
    assert !ParserTokenFacts.IsExpressionStart(TokenType.DotDotDot)

    // THE THREE STRING FORMS ARE ONE FAMILY IN BOTH TABLES. A predicate that admits two of them is
    // not expressing a grammar rule, it is missing a row.
    assert ParserTokenFacts.CanStartExpression(TokenType.StringLiteral)
    assert ParserTokenFacts.CanStartExpression(TokenType.TripleQuoteStringLiteral)
    assert ParserTokenFacts.CanStartExpression(TokenType.InterpolatedRawStringLiteral)
    assert ParserTokenFacts.IsExpressionStart(TokenType.StringLiteral)
    assert ParserTokenFacts.IsExpressionStart(TokenType.TripleQuoteStringLiteral)
    assert ParserTokenFacts.IsExpressionStart(TokenType.InterpolatedRawStringLiteral)

    // Everything else they agree on, member for member, over all 148 tokens.
    all := ParserTokenAllTokenTypes()
    index := 0
    while index < all.Length {
        tokenType := all[index]
        if tokenType != TokenType.DotDotDot {
            assert ParserTokenFacts.CanStartExpression(tokenType) == ParserTokenFacts.IsExpressionStart(tokenType)
        }

        index = index + 1
    }
}

// NOT IN THE DELETED FILE. The recovery tables overlap deliberately, and each overlap is a rule a
// resynchronising parser depends on.
test "parser token facts overlap the recovery tables deliberately" {
    // Every type-declaration keyword is a declaration keyword; the reverse does not hold.
    typeKeywords := ParserTokenIsTypeDeclarationKeywordSet()
    index := 0
    while index < typeKeywords.Length {
        assert ParserTokenFacts.IsDeclarationKeyword(typeKeywords[index])
        index = index + 1
    }

    assert ParserTokenFacts.IsDeclarationKeyword(TokenType.Func)
    assert !ParserTokenFacts.IsTypeDeclarationKeyword(TokenType.Func)
    assert ParserTokenFacts.IsDeclarationKeyword(TokenType.Test)
    assert !ParserTokenFacts.IsTypeDeclarationKeyword(TokenType.Test)

    // `readonly` opens a statement AND modifies a declaration.
    assert ParserTokenFacts.IsModifierKeyword(TokenType.Readonly)
    assert ParserTokenFacts.IsStatementStartKeyword(TokenType.Readonly)

    // `func` opens a declaration AND a statement (a local function).
    assert ParserTokenFacts.IsDeclarationKeyword(TokenType.Func)
    assert ParserTokenFacts.IsStatementStartKeyword(TokenType.Func)

    // `throw` starts a statement AND an expression.
    assert ParserTokenFacts.IsStatementStartKeyword(TokenType.Throw)
    assert ParserTokenFacts.CanStartExpression(TokenType.Throw)
    assert ParserTokenFacts.IsExpressionStart(TokenType.Throw)

    // `;` both terminates an expression and starts (an empty) statement.
    assert ParserTokenFacts.IsExpressionTerminator(TokenType.Semicolon)
    assert ParserTokenFacts.IsStatementStartKeyword(TokenType.Semicolon)

    // A modifier is never a declaration keyword on its own.
    modifiers := ParserTokenIsModifierKeywordSet()
    index = 0
    while index < modifiers.Length {
        assert !ParserTokenFacts.IsDeclarationKeyword(modifiers[index])
        index = index + 1
    }
}

// NOT IN THE DELETED FILE. `Eof` is the one token every table must agree about, because recovery
// walks stop on it: it terminates an expression and starts nothing at all.
test "parser token facts stop everything at the end of file" {
    assert ParserTokenFacts.IsExpressionTerminator(TokenType.Eof)
    assert !ParserTokenFacts.CanStartExpression(TokenType.Eof)
    assert !ParserTokenFacts.IsExpressionStart(TokenType.Eof)
    assert !ParserTokenFacts.IsCastOperandStart(TokenType.Eof)
    assert !ParserTokenFacts.IsDeclarationKeyword(TokenType.Eof)
    assert !ParserTokenFacts.IsTypeDeclarationKeyword(TokenType.Eof)
    assert !ParserTokenFacts.IsModifierKeyword(TokenType.Eof)
    assert !ParserTokenFacts.IsStatementStartKeyword(TokenType.Eof)
    assert !ParserTokenFacts.IsAssignmentOperator(TokenType.Eof)
    assert !ParserTokenFacts.IsTypeReferenceStart(TokenType.Eof)
}

// ---- the symbolic operators, and the partition they complete ---------------------------------

// The 36 tokens `IsOperator` admits. Written out in full rather than derived, so that the sweep
// below compares the owner's answer against a table a reader can check against the enum by eye.
func ParserTokenIsOperatorSet(): TokenType[] {
    return [
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Star,
        TokenType.Slash,
        TokenType.Percent,
        TokenType.Assign,
        TokenType.PlusAssign,
        TokenType.MinusAssign,
        TokenType.StarAssign,
        TokenType.SlashAssign,
        TokenType.Equal,
        TokenType.NotEqual,
        TokenType.Less,
        TokenType.LessEqual,
        TokenType.Greater,
        TokenType.GreaterEqual,
        TokenType.And,
        TokenType.Or,
        TokenType.Not,
        TokenType.BitwiseAnd,
        TokenType.BitwiseOr,
        TokenType.BitwiseXor,
        TokenType.BitwiseNot,
        TokenType.LeftShift,
        TokenType.RightShift,
        TokenType.Increment,
        TokenType.Decrement,
        TokenType.Question,
        TokenType.QuestionQuestion,
        TokenType.QuestionQuestionAssign,
        TokenType.QuestionDot,
        TokenType.QuestionBracket,
        TokenType.Arrow,
        TokenType.ColonAssign,
        TokenType.DotDot,
        TokenType.DotDotDot
    ]
}

// The 27 that are neither: the seven literal kinds, the eleven delimiters, and the nine tokens the
// lexer produces that are not code at all. `Test` is here because no lexer arm produces it.
func ParserTokenNonCodeSet(): TokenType[] {
    return [
        TokenType.Identifier,
        TokenType.IntLiteral,
        TokenType.FloatLiteral,
        TokenType.CharLiteral,
        TokenType.StringLiteral,
        TokenType.TripleQuoteStringLiteral,
        TokenType.InterpolatedRawStringLiteral,
        TokenType.Test,
        TokenType.Colon,
        TokenType.DoubleColon,
        TokenType.Dot,
        TokenType.LeftParen,
        TokenType.RightParen,
        TokenType.LeftBrace,
        TokenType.RightBrace,
        TokenType.LeftBracket,
        TokenType.RightBracket,
        TokenType.Semicolon,
        TokenType.Comma,
        TokenType.Eof,
        TokenType.Newline,
        TokenType.Unknown,
        TokenType.PreprocessorDirective,
        TokenType.Comment,
        TokenType.MultiLineComment,
        TokenType.XmlDocComment,
        TokenType.Lifetime
    ]
}

// The sweep. Every one of the 148 tokens is asked, so an arm added to `IsOperator` that the table
// does not name fails here, and a table entry the owner does not admit fails here too.
test "parser token facts own the symbolic operators" {
    all := ParserTokenAllTokenTypes()
    expected := ParserTokenIsOperatorSet()
    ParserTokenAssertSetIsSwept(expected, all)

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert ParserTokenFacts.IsOperator(tokenType) == ParserTokenContains(expected, tokenType)
        index = index + 1
    }
}

// THE DISJOINTNESS, ASSERTED RATHER THAN ASSUMED. `is`, `as`, `and`, `or`, `not` are operators
// spelled as words; they belong to the lexer's keyword table and must not also be here, or a
// classifier that asks both questions would get two answers for one token.
test "parser token facts keep the symbolic operators out of the keyword table" {
    all := ParserTokenAllTokenTypes()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        assert !(ParserTokenFacts.IsOperator(tokenType) && Lexer.IsReservedKeyword(tokenType))
        index = index + 1
    }
}

// THE PARTITION. 85 keywords + 36 symbolic operators + 27 non-code = 148, and every token lands in
// exactly one bucket. A `TokenType` member added to the enum and forgotten by all three fails here
// before any consumer notices it going unclassified.
test "parser token facts partition every token type" {
    all := ParserTokenAllTokenTypes()
    operators := ParserTokenIsOperatorSet()
    nonCode := ParserTokenNonCodeSet()

    assert all.Length == 148
    assert operators.Length == 36
    assert nonCode.Length == 27

    keywordCount := 0
    index := 0
    while index < all.Length {
        tokenType := all[index]
        isKeyword := Lexer.IsReservedKeyword(tokenType)
        isOperator := ParserTokenFacts.IsOperator(tokenType)
        isNonCode := ParserTokenContains(nonCode, tokenType)

        buckets := 0
        if isKeyword {
            buckets = buckets + 1
            keywordCount = keywordCount + 1
        }
        if isOperator {
            buckets = buckets + 1
        }
        if isNonCode {
            buckets = buckets + 1
        }

        assert buckets == 1
        index = index + 1
    }

    assert keywordCount == 85
}

// THE CONTAINMENT, WHICH THE OWNER GUARANTEES BY CONSTRUCTION RATHER THAN BY COPYING. `IsOperator`
// ends by delegating to `IsAssignmentOperator`, so the six assignment forms cannot drift out of the
// larger set. This asserts the relation anyway, because the delegation is an implementation choice
// and the relation is the contract.
test "parser token facts make every assignment operator an operator" {
    all := ParserTokenAllTokenTypes()

    index := 0
    while index < all.Length {
        tokenType := all[index]
        if ParserTokenFacts.IsAssignmentOperator(tokenType) {
            assert ParserTokenFacts.IsOperator(tokenType)
        }

        index = index + 1
    }
}
