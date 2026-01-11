package com.nsharp

import com.intellij.openapi.fileTypes.LanguageFileType
import javax.swing.Icon

class NSharpFileType private constructor() : LanguageFileType(NSharpLanguage) {
    override fun getName(): String = "N#"
    override fun getDescription(): String = "N# source file"
    override fun getDefaultExtension(): String = "nl"
    override fun getIcon(): Icon = NSharpIcons.FILE

    companion object {
        @JvmField
        val INSTANCE: NSharpFileType = NSharpFileType()
    }
}

