package com.nsharp

import com.intellij.lexer.Lexer
import com.intellij.openapi.editor.DefaultLanguageHighlighterColors
import com.intellij.openapi.editor.HighlighterColors
import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighterBase
import com.intellij.psi.tree.IElementType
import com.nsharp.lexer.NSharpLexer
import com.nsharp.psi.NSharpTokenTypes

class NSharpSyntaxHighlighter : SyntaxHighlighterBase() {
    override fun getHighlightingLexer(): Lexer = NSharpLexer()
    
    override fun getTokenHighlights(tokenType: IElementType): Array<TextAttributesKey> {
        return when (tokenType) {
            NSharpTokenTypes.FUNC, NSharpTokenTypes.TYPE, NSharpTokenTypes.UNION, NSharpTokenTypes.MATCH, NSharpTokenTypes.IF, NSharpTokenTypes.ELSE,
            NSharpTokenTypes.FOR, NSharpTokenTypes.IN, NSharpTokenTypes.RETURN, NSharpTokenTypes.VAR, NSharpTokenTypes.CONST, NSharpTokenTypes.IMPORT,
            NSharpTokenTypes.CLASS, NSharpTokenTypes.INTERFACE, NSharpTokenTypes.STRUCT, NSharpTokenTypes.RECORD, NSharpTokenTypes.ASYNC, NSharpTokenTypes.AWAIT,
            NSharpTokenTypes.NEW, NSharpTokenTypes.THIS, NSharpTokenTypes.BASE, NSharpTokenTypes.WHEN, NSharpTokenTypes.IS, NSharpTokenTypes.TRUE, NSharpTokenTypes.FALSE, NSharpTokenTypes.NULL -> pack(KEYWORD)
            NSharpTokenTypes.NUMBER -> pack(NUMBER)
            NSharpTokenTypes.STRING -> pack(STRING)
            NSharpTokenTypes.COMMENT, NSharpTokenTypes.BLOCK_COMMENT -> pack(COMMENT)
            NSharpTokenTypes.IDENTIFIER -> pack(IDENTIFIER)
            else -> emptyArray()
        }
    }
    
    companion object {
        val KEYWORD = TextAttributesKey.createTextAttributesKey("NSHARP_KEYWORD", DefaultLanguageHighlighterColors.KEYWORD)
        val STRING = TextAttributesKey.createTextAttributesKey("NSHARP_STRING", DefaultLanguageHighlighterColors.STRING)
        val NUMBER = TextAttributesKey.createTextAttributesKey("NSHARP_NUMBER", DefaultLanguageHighlighterColors.NUMBER)
        val COMMENT = TextAttributesKey.createTextAttributesKey("NSHARP_COMMENT", DefaultLanguageHighlighterColors.LINE_COMMENT)
        val IDENTIFIER = TextAttributesKey.createTextAttributesKey("NSHARP_IDENTIFIER", DefaultLanguageHighlighterColors.IDENTIFIER)
    }
}
