package com.nsharp

import com.intellij.lang.Language

object NSharpLanguage : Language("NSharp") {
    override fun getDisplayName(): String = "N#"
    override fun isCaseSensitive(): Boolean = true
}
