package com.nsharp.highlighting

import com.intellij.psi.tree.IElementType
import com.nsharp.NSharpLanguage

object NSharpTokenTypes {
    @JvmField val KEYWORD: IElementType = IElementType("NSHARP_KEYWORD", NSharpLanguage)
    @JvmField val IDENTIFIER: IElementType = IElementType("NSHARP_IDENTIFIER", NSharpLanguage)
    @JvmField val NUMBER: IElementType = IElementType("NSHARP_NUMBER", NSharpLanguage)
    @JvmField val STRING: IElementType = IElementType("NSHARP_STRING", NSharpLanguage)
    @JvmField val LINE_COMMENT: IElementType = IElementType("NSHARP_LINE_COMMENT", NSharpLanguage)
    @JvmField val BLOCK_COMMENT: IElementType = IElementType("NSHARP_BLOCK_COMMENT", NSharpLanguage)
    @JvmField val OPERATOR: IElementType = IElementType("NSHARP_OPERATOR", NSharpLanguage)
}

