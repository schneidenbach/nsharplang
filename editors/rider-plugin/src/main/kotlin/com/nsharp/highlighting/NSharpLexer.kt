package com.nsharp.highlighting

import com.intellij.lexer.LexerBase
import com.intellij.psi.TokenType
import com.intellij.psi.tree.IElementType

class NSharpLexer : LexerBase() {
    private var buffer: CharSequence = ""
    private var bufferEnd = 0
    private var tokenStart = 0
    private var tokenEnd = 0
    private var tokenType: IElementType? = null

    override fun start(buffer: CharSequence, startOffset: Int, endOffset: Int, initialState: Int) {
        this.buffer = buffer
        this.bufferEnd = endOffset
        this.tokenStart = startOffset
        this.tokenEnd = startOffset
        this.tokenType = null
        advance()
    }

    override fun getState(): Int = 0

    override fun getTokenType(): IElementType? = tokenType

    override fun getTokenStart(): Int = tokenStart

    override fun getTokenEnd(): Int = tokenEnd

    override fun advance() {
        if (tokenEnd >= bufferEnd) {
            tokenType = null
            return
        }

        tokenStart = tokenEnd

        val c = buffer[tokenStart]

        // Whitespace
        if (c.isWhitespace()) {
            tokenEnd = scanWhile(tokenStart) { it.isWhitespace() }
            tokenType = TokenType.WHITE_SPACE
            return
        }

        // Line comment: //
        if (c == '/' && peek(tokenStart + 1) == '/') {
            tokenEnd = scanUntil(tokenStart + 2) { it == '\n' }
            tokenType = NSharpTokenTypes.LINE_COMMENT
            return
        }

        // Block comment: /* ... */
        if (c == '/' && peek(tokenStart + 1) == '*') {
            var i = tokenStart + 2
            while (i < bufferEnd) {
                if (peek(i) == '*' && peek(i + 1) == '/') {
                    i += 2
                    break
                }
                i++
            }
            tokenEnd = i
            tokenType = NSharpTokenTypes.BLOCK_COMMENT
            return
        }

        // Interpolated string start: $"
        if (c == '$' && peek(tokenStart + 1) == '"') {
            tokenEnd = scanString(tokenStart + 2)
            tokenType = NSharpTokenTypes.STRING
            return
        }

        // String: "..."
        if (c == '"') {
            tokenEnd = scanString(tokenStart + 1)
            tokenType = NSharpTokenTypes.STRING
            return
        }

        // Number
        if (c.isDigit()) {
            var i = tokenStart + 1
            while (i < bufferEnd && peek(i).isDigit()) i++
            if (i < bufferEnd && peek(i) == '.' && i + 1 < bufferEnd && peek(i + 1).isDigit()) {
                i++
                while (i < bufferEnd && peek(i).isDigit()) i++
            }
            tokenEnd = i
            tokenType = NSharpTokenTypes.NUMBER
            return
        }

        // Identifier / keyword
        if (c.isLetter() || c == '_' ) {
            tokenEnd = scanWhile(tokenStart + 1) { it.isLetterOrDigit() || it == '_' }
            val text = buffer.subSequence(tokenStart, tokenEnd).toString()
            tokenType = if (KEYWORDS.contains(text)) NSharpTokenTypes.KEYWORD else NSharpTokenTypes.IDENTIFIER
            return
        }

        // Fallback: single character operator/punctuation
        tokenEnd = tokenStart + 1
        tokenType = NSharpTokenTypes.OPERATOR
    }

    override fun getBufferSequence(): CharSequence = buffer

    override fun getBufferEnd(): Int = bufferEnd

    private fun peek(index: Int): Char = if (index in 0 until bufferEnd) buffer[index] else 0.toChar()

    private fun scanWhile(start: Int, predicate: (Char) -> Boolean): Int {
        var i = start
        while (i < bufferEnd && predicate(peek(i))) i++
        return i
    }

    private fun scanUntil(start: Int, predicate: (Char) -> Boolean): Int {
        var i = start
        while (i < bufferEnd && !predicate(peek(i))) i++
        return i
    }

    private fun scanString(start: Int): Int {
        var i = start
        var escaped = false
        while (i < bufferEnd) {
            val ch = peek(i)
            if (!escaped && ch == '"') {
                i++
                break
            }
            if (!escaped && ch == '\\') {
                escaped = true
                i++
                continue
            }
            escaped = false
            i++
        }
        return i
    }

    companion object {
        private val KEYWORDS = setOf(
            "func", "class", "struct", "record", "interface", "enum", "union", "namespace",
            "using", "import", "if", "else", "for", "foreach", "while", "return", "break",
            "continue", "match", "switch", "case", "when", "yield", "await", "async",
            "throw", "try", "catch", "finally", "lock", "new", "this", "base", "static",
            "virtual", "override", "abstract", "sealed", "partial", "readonly", "const",
            "file", "duck", "public", "private", "internal", "protected", "required",
            "init", "let", "var", "type", "out", "ref", "params", "true", "false",
            "null", "is", "as", "typeof", "nameof", "checked", "unchecked", "and",
            "or", "not", "with", "immutable", "print", "test", "assert", "implicit", "explicit"
        )
    }
}

