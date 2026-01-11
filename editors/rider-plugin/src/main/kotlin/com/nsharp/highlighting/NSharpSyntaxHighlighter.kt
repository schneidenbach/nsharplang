package com.nsharp.highlighting

import com.intellij.openapi.editor.DefaultLanguageHighlighterColors
import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighterBase
import com.intellij.psi.tree.IElementType

class NSharpSyntaxHighlighter : SyntaxHighlighterBase() {
    override fun getHighlightingLexer() = NSharpLexer()

    override fun getTokenHighlights(tokenType: IElementType): Array<TextAttributesKey> {
        return when (tokenType) {
            NSharpTokenTypes.KEYWORD -> pack(NSharpTextAttributes.KEYWORD)
            NSharpTokenTypes.STRING -> pack(NSharpTextAttributes.STRING)
            NSharpTokenTypes.NUMBER -> pack(NSharpTextAttributes.NUMBER)
            NSharpTokenTypes.LINE_COMMENT, NSharpTokenTypes.BLOCK_COMMENT -> pack(NSharpTextAttributes.COMMENT)
            NSharpTokenTypes.OPERATOR -> pack(NSharpTextAttributes.OPERATOR)
            else -> emptyArray()
        }
    }
}

object NSharpTextAttributes {
    @JvmField val KEYWORD: TextAttributesKey =
        TextAttributesKey.createTextAttributesKey("NSHARP_KEYWORD", DefaultLanguageHighlighterColors.KEYWORD)
    @JvmField val STRING: TextAttributesKey =
        TextAttributesKey.createTextAttributesKey("NSHARP_STRING", DefaultLanguageHighlighterColors.STRING)
    @JvmField val NUMBER: TextAttributesKey =
        TextAttributesKey.createTextAttributesKey("NSHARP_NUMBER", DefaultLanguageHighlighterColors.NUMBER)
    @JvmField val COMMENT: TextAttributesKey =
        TextAttributesKey.createTextAttributesKey("NSHARP_COMMENT", DefaultLanguageHighlighterColors.LINE_COMMENT)
    @JvmField val OPERATOR: TextAttributesKey =
        TextAttributesKey.createTextAttributesKey("NSHARP_OPERATOR", DefaultLanguageHighlighterColors.OPERATION_SIGN)
}

