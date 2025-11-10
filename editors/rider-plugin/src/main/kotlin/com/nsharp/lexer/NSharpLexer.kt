package com.nsharp.lexer

import com.intellij.lexer.LexerBase
import com.intellij.psi.tree.IElementType
import com.nsharp.psi.NSharpTokenTypes

class NSharpLexer : LexerBase() {
    private var buffer: CharSequence = ""
    private var startOffset = 0
    private var endOffset = 0
    private var currentOffset = 0
    private var tokenType: IElementType? = null
    private var tokenStart = 0
    private var tokenEnd = 0
    
    private val keywords = setOf("func", "type", "union", "match", "if", "else", "for", "in", "return", "var", "const", "import", "class", "interface", "struct", "record", "async", "await", "new", "this", "base", "true", "false", "null", "when", "is")
    
    override fun start(buffer: CharSequence, startOffset: Int, endOffset: Int, initialState: Int) {
        this.buffer = buffer
        this.startOffset = startOffset
        this.endOffset = endOffset
        this.currentOffset = startOffset
        advance()
    }
    
    override fun getState(): Int = 0
    override fun getTokenType(): IElementType? = tokenType
    override fun getTokenStart(): Int = tokenStart
    override fun getTokenEnd(): Int = tokenEnd
    
    override fun advance() {
        if (currentOffset >= endOffset) {
            tokenType = null
            return
        }
        tokenStart = currentOffset
        val c = buffer[currentOffset]
        when {
            c.isWhitespace() -> {
                while (currentOffset < endOffset && buffer[currentOffset].isWhitespace()) currentOffset++
                tokenEnd = currentOffset
                tokenType = NSharpTokenTypes.WHITESPACE
            }
            c == '/' && currentOffset + 1 < endOffset && buffer[currentOffset + 1] == '/' -> {
                currentOffset += 2
                while (currentOffset < endOffset && buffer[currentOffset] != '\n') currentOffset++
                tokenEnd = currentOffset
                tokenType = NSharpTokenTypes.COMMENT
            }
            c == '"' -> {
                currentOffset++
                while (currentOffset < endOffset && buffer[currentOffset] != '"') currentOffset++
                if (currentOffset < endOffset) currentOffset++
                tokenEnd = currentOffset
                tokenType = NSharpTokenTypes.STRING
            }
            c.isDigit() -> {
                while (currentOffset < endOffset && buffer[currentOffset].isDigit()) currentOffset++
                tokenEnd = currentOffset
                tokenType = NSharpTokenTypes.NUMBER
            }
            c.isLetter() || c == '_' -> {
                while (currentOffset < endOffset && (buffer[currentOffset].isLetterOrDigit() || buffer[currentOffset] == '_')) currentOffset++
                tokenEnd = currentOffset
                val text = buffer.substring(tokenStart, tokenEnd)
                tokenType = if (keywords.contains(text)) getKeywordType(text) else NSharpTokenTypes.IDENTIFIER
            }
            else -> {
                currentOffset++
                tokenEnd = currentOffset
                tokenType = NSharpTokenTypes.IDENTIFIER
            }
        }
    }
    
    private fun getKeywordType(keyword: String): IElementType = when (keyword) {
        "func" -> NSharpTokenTypes.FUNC
        "type" -> NSharpTokenTypes.TYPE
        "union" -> NSharpTokenTypes.UNION
        "match" -> NSharpTokenTypes.MATCH
        "if" -> NSharpTokenTypes.IF
        "else" -> NSharpTokenTypes.ELSE
        "for" -> NSharpTokenTypes.FOR
        "in" -> NSharpTokenTypes.IN
        "return" -> NSharpTokenTypes.RETURN
        "var" -> NSharpTokenTypes.VAR
        "const" -> NSharpTokenTypes.CONST
        "import" -> NSharpTokenTypes.IMPORT
        "class" -> NSharpTokenTypes.CLASS
        "interface" -> NSharpTokenTypes.INTERFACE
        "struct" -> NSharpTokenTypes.STRUCT
        "record" -> NSharpTokenTypes.RECORD
        "async" -> NSharpTokenTypes.ASYNC
        "await" -> NSharpTokenTypes.AWAIT
        "new" -> NSharpTokenTypes.NEW
        "this" -> NSharpTokenTypes.THIS
        "base" -> NSharpTokenTypes.BASE
        "true", "false" -> NSharpTokenTypes.TRUE
        "null" -> NSharpTokenTypes.NULL
        "when" -> NSharpTokenTypes.WHEN
        "is" -> NSharpTokenTypes.IS
        else -> NSharpTokenTypes.IDENTIFIER
    }
    
    override fun getBufferSequence(): CharSequence = buffer
    override fun getBufferEnd(): Int = endOffset
}
