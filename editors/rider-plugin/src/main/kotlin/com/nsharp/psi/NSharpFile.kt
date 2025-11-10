package com.nsharp.psi

import com.intellij.extapi.psi.PsiFileBase
import com.intellij.openapi.fileTypes.FileType
import com.intellij.psi.FileViewProvider
import com.nsharp.NSharpFileType
import com.nsharp.NSharpLanguage

class NSharpFile(viewProvider: FileViewProvider) : PsiFileBase(viewProvider, NSharpLanguage) {
    override fun getFileType(): FileType = NSharpFileType.INSTANCE
    override fun toString(): String = "N# File"
}
