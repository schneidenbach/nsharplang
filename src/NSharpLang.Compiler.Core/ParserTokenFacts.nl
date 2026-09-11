namespace NSharpLang.Compiler

class ParserTokenFacts {
    static func CanStartExpression(tokenType: TokenType): bool {
        if tokenType == TokenType.Identifier {
            return true
        }
        if tokenType == TokenType.IntLiteral {
            return true
        }
        if tokenType == TokenType.FloatLiteral {
            return true
        }
        if tokenType == TokenType.CharLiteral {
            return true
        }
        if tokenType == TokenType.StringLiteral {
            return true
        }
        // A PLAIN RAW LITERAL STARTS AN EXPRESSION EXACTLY AS THE OTHER TWO STRING FORMS DO, and its
        // absence here was a LANGUAGE defect, not a formatting one. `ParseReturnStatement` asks this
        // predicate whether the `return` carries a value at all, so `return """abc"""` parsed as a
        // BARE `return` followed by a stray expression statement and `nlc check` reported NL305 +
        // NL312 + NL006 on correct source. `ParseAdditive`'s missing-operand boundary asks it too, so
        // `"a" + """b"""` was refused the same way. `IsExpressionStart` — the CAST operand table —
        // had the row all along; this table did not.
        if tokenType == TokenType.TripleQuoteStringLiteral {
            return true
        }
        if tokenType == TokenType.InterpolatedRawStringLiteral {
            return true
        }
        if tokenType == TokenType.True {
            return true
        }
        if tokenType == TokenType.False {
            return true
        }
        if tokenType == TokenType.Null {
            return true
        }
        if tokenType == TokenType.New {
            return true
        }
        if tokenType == TokenType.Alloc {
            return true
        }
        if tokenType == TokenType.Stackalloc {
            return true
        }
        if tokenType == TokenType.Match {
            return true
        }
        if tokenType == TokenType.This {
            return true
        }
        if tokenType == TokenType.Base {
            return true
        }
        if tokenType == TokenType.LeftParen {
            return true
        }
        if tokenType == TokenType.LeftBracket {
            return true
        }
        if tokenType == TokenType.Immutable {
            return true
        }
        if tokenType == TokenType.DotDotDot {
            return true
        }
        if tokenType == TokenType.Plus {
            return true
        }
        if tokenType == TokenType.Minus {
            return true
        }
        if tokenType == TokenType.Not {
            return true
        }
        if tokenType == TokenType.BitwiseNot {
            return true
        }
        if tokenType == TokenType.Increment {
            return true
        }
        if tokenType == TokenType.Decrement {
            return true
        }
        if tokenType == TokenType.Must {
            return true
        }
        if tokenType == TokenType.Await {
            return true
        }
        if tokenType == TokenType.Throw {
            return true
        }
        if tokenType == TokenType.Checked {
            return true
        }
        if tokenType == TokenType.Unchecked {
            return true
        }
        if tokenType == TokenType.Typeof {
            return true
        }
        if tokenType == TokenType.Nameof {
            return true
        }
        if tokenType == TokenType.Sizeof {
            return true
        }
        if tokenType == TokenType.Default {
            return true
        }
        return false
    }

    // THE SYMBOLIC OPERATORS — the tokens spelled in punctuation that combine or transform
    // operands, as opposed to the ones spelled as words.
    //
    // The language's operators are written two ways and this predicate owns exactly one of them.
    // `is`, `as`, `and`, `or`, `not` are operators too, but they are spelled as WORDS and are
    // therefore reserved keywords, which `Lexer.IsReservedKeyword` already owns. The two answers are
    // DISJOINT by construction and the contracts assert it: no token type is both.
    //
    // WHAT IS DELIBERATELY OUT. The grouping and separating punctuation — `( ) { } [ ] , ; : :: .`
    // — is not here. Those tokens delimit; they do not compute. `.` is the closest call and it stays
    // out: member access is resolved by the binder against a name, not applied to two operands, and
    // an editor that painted every `.` as an operator would paint every qualified name.
    //
    // THE THREE ANSWERS PARTITION THE ENUM. Every one of the 148 `TokenType` members is a reserved
    // keyword (85), a symbolic operator (36), or neither (27: the seven literal kinds, eleven
    // delimiters, `Eof`, `Newline`, `Unknown`, `Lifetime`, `Test`, the preprocessor directive and
    // the three comment kinds). The contracts sweep that arithmetic, so a token type added to the
    // enum and forgotten here is caught by the partition rather than by a consumer noticing later.
    static func IsOperator(tokenType: TokenType): bool {
        if tokenType == TokenType.Plus {
            return true
        }
        if tokenType == TokenType.Minus {
            return true
        }
        if tokenType == TokenType.Star {
            return true
        }
        if tokenType == TokenType.Slash {
            return true
        }
        if tokenType == TokenType.Percent {
            return true
        }
        if tokenType == TokenType.Equal {
            return true
        }
        if tokenType == TokenType.NotEqual {
            return true
        }
        if tokenType == TokenType.Less {
            return true
        }
        if tokenType == TokenType.LessEqual {
            return true
        }
        if tokenType == TokenType.Greater {
            return true
        }
        if tokenType == TokenType.GreaterEqual {
            return true
        }
        if tokenType == TokenType.And {
            return true
        }
        if tokenType == TokenType.Or {
            return true
        }
        if tokenType == TokenType.Not {
            return true
        }
        if tokenType == TokenType.BitwiseAnd {
            return true
        }
        if tokenType == TokenType.BitwiseOr {
            return true
        }
        if tokenType == TokenType.BitwiseXor {
            return true
        }
        if tokenType == TokenType.BitwiseNot {
            return true
        }
        if tokenType == TokenType.LeftShift {
            return true
        }
        if tokenType == TokenType.RightShift {
            return true
        }
        if tokenType == TokenType.Increment {
            return true
        }
        if tokenType == TokenType.Decrement {
            return true
        }
        if tokenType == TokenType.Question {
            return true
        }
        if tokenType == TokenType.QuestionQuestion {
            return true
        }
        if tokenType == TokenType.QuestionDot {
            return true
        }
        if tokenType == TokenType.QuestionBracket {
            return true
        }
        if tokenType == TokenType.Arrow {
            return true
        }
        if tokenType == TokenType.ColonAssign {
            return true
        }
        if tokenType == TokenType.DotDot {
            return true
        }
        if tokenType == TokenType.DotDotDot {
            return true
        }
        return IsAssignmentOperator(tokenType)
    }

    static func IsAssignmentOperator(tokenType: TokenType): bool {
        if tokenType == TokenType.Assign {
            return true
        }
        if tokenType == TokenType.PlusAssign {
            return true
        }
        if tokenType == TokenType.MinusAssign {
            return true
        }
        if tokenType == TokenType.StarAssign {
            return true
        }
        if tokenType == TokenType.SlashAssign {
            return true
        }
        if tokenType == TokenType.QuestionQuestionAssign {
            return true
        }
        return false
    }

    static func IsCastOperandStart(tokenType: TokenType): bool {
        return tokenType != TokenType.LeftBracket && IsExpressionStart(tokenType)
    }

    static func IsExpressionStart(tokenType: TokenType): bool {
        if tokenType == TokenType.Identifier {
            return true
        }
        if tokenType == TokenType.IntLiteral {
            return true
        }
        if tokenType == TokenType.FloatLiteral {
            return true
        }
        if tokenType == TokenType.CharLiteral {
            return true
        }
        if tokenType == TokenType.StringLiteral {
            return true
        }
        if tokenType == TokenType.TripleQuoteStringLiteral {
            return true
        }
        if tokenType == TokenType.InterpolatedRawStringLiteral {
            return true
        }
        if tokenType == TokenType.True {
            return true
        }
        if tokenType == TokenType.False {
            return true
        }
        if tokenType == TokenType.Null {
            return true
        }
        if tokenType == TokenType.Default {
            return true
        }
        if tokenType == TokenType.New {
            return true
        }
        if tokenType == TokenType.Alloc {
            return true
        }
        if tokenType == TokenType.Stackalloc {
            return true
        }
        if tokenType == TokenType.This {
            return true
        }
        if tokenType == TokenType.Base {
            return true
        }
        if tokenType == TokenType.LeftParen {
            return true
        }
        if tokenType == TokenType.LeftBracket {
            return true
        }
        if tokenType == TokenType.Immutable {
            return true
        }
        if tokenType == TokenType.Plus {
            return true
        }
        if tokenType == TokenType.Minus {
            return true
        }
        if tokenType == TokenType.Not {
            return true
        }
        if tokenType == TokenType.BitwiseNot {
            return true
        }
        if tokenType == TokenType.Increment {
            return true
        }
        if tokenType == TokenType.Decrement {
            return true
        }
        if tokenType == TokenType.Must {
            return true
        }
        if tokenType == TokenType.Await {
            return true
        }
        if tokenType == TokenType.Throw {
            return true
        }
        if tokenType == TokenType.Match {
            return true
        }
        if tokenType == TokenType.Typeof {
            return true
        }
        if tokenType == TokenType.Nameof {
            return true
        }
        if tokenType == TokenType.Sizeof {
            return true
        }
        if tokenType == TokenType.Checked {
            return true
        }
        if tokenType == TokenType.Unchecked {
            return true
        }
        return false
    }

    static func IsTypeReferenceStart(tokenType: TokenType): bool {
        if tokenType == TokenType.Identifier {
            return true
        }
        if tokenType == TokenType.LeftParen {
            return true
        }
        if tokenType == TokenType.BitwiseAnd {
            return true
        }
        return false
    }

    static func IsTypeDeclarationKeyword(tokenType: TokenType): bool {
        if tokenType == TokenType.Class {
            return true
        }
        if tokenType == TokenType.Struct {
            return true
        }
        if tokenType == TokenType.Record {
            return true
        }
        if tokenType == TokenType.Interface {
            return true
        }
        if tokenType == TokenType.Union {
            return true
        }
        if tokenType == TokenType.Enum {
            return true
        }
        if tokenType == TokenType.Type {
            return true
        }
        return false
    }

    static func IsDeclarationKeyword(tokenType: TokenType): bool {
        if tokenType == TokenType.Func {
            return true
        }
        if IsTypeDeclarationKeyword(tokenType) {
            return true
        }
        if tokenType == TokenType.Test {
            return true
        }
        if tokenType == TokenType.Implicit {
            return true
        }
        if tokenType == TokenType.Explicit {
            return true
        }
        if tokenType == TokenType.Duck {
            return true
        }
        if tokenType == TokenType.Ref {
            return true
        }
        return false
    }

    static func IsModifierKeyword(tokenType: TokenType): bool {
        if tokenType == TokenType.Static {
            return true
        }
        if tokenType == TokenType.Internal {
            return true
        }
        if tokenType == TokenType.Protected {
            return true
        }
        if tokenType == TokenType.Virtual {
            return true
        }
        if tokenType == TokenType.Override {
            return true
        }
        if tokenType == TokenType.Abstract {
            return true
        }
        if tokenType == TokenType.Sealed {
            return true
        }
        if tokenType == TokenType.Readonly {
            return true
        }
        if tokenType == TokenType.Partial {
            return true
        }
        if tokenType == TokenType.Async {
            return true
        }
        if tokenType == TokenType.File {
            return true
        }
        return false
    }

    static func IsStatementStartKeyword(tokenType: TokenType): bool {
        if tokenType == TokenType.Let {
            return true
        }
        if tokenType == TokenType.Const {
            return true
        }
        if tokenType == TokenType.Readonly {
            return true
        }
        if tokenType == TokenType.If {
            return true
        }
        if tokenType == TokenType.For {
            return true
        }
        if tokenType == TokenType.Foreach {
            return true
        }
        if tokenType == TokenType.While {
            return true
        }
        if tokenType == TokenType.Return {
            return true
        }
        if tokenType == TokenType.Yield {
            return true
        }
        if tokenType == TokenType.Break {
            return true
        }
        if tokenType == TokenType.Continue {
            return true
        }
        if tokenType == TokenType.Throw {
            return true
        }
        if tokenType == TokenType.Try {
            return true
        }
        if tokenType == TokenType.Using {
            return true
        }
        if tokenType == TokenType.Lock {
            return true
        }
        if tokenType == TokenType.Switch {
            return true
        }
        if tokenType == TokenType.Print {
            return true
        }
        if tokenType == TokenType.Assert {
            return true
        }
        if tokenType == TokenType.Unsafe {
            return true
        }
        if tokenType == TokenType.Allow {
            return true
        }
        if tokenType == TokenType.Func {
            return true
        }
        if tokenType == TokenType.Semicolon {
            return true
        }
        if tokenType == TokenType.LeftBrace {
            return true
        }
        return false
    }

    static func IsExpressionTerminator(tokenType: TokenType): bool {
        if tokenType == TokenType.RightBrace {
            return true
        }
        if tokenType == TokenType.RightParen {
            return true
        }
        if tokenType == TokenType.RightBracket {
            return true
        }
        if tokenType == TokenType.Comma {
            return true
        }
        if tokenType == TokenType.Semicolon {
            return true
        }
        if tokenType == TokenType.Eof {
            return true
        }
        return false
    }
}
