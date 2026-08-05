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
