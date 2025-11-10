package com.nsharp.icons

import com.intellij.ide.IconProvider
import com.intellij.openapi.project.DumbAware
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import com.nsharp.NSharpFileType
import javax.swing.Icon

class NSharpIconProvider : IconProvider(), DumbAware {
    override fun getIcon(element: PsiElement, flags: Int): Icon? {
        val file = element as? PsiFile ?: return null
        if (file.fileType is NSharpFileType) {
            return NSharpIcons.FILE
        }
        if (file.name == "project.yml") {
            return NSharpIcons.PROJECT
        }
        return null
    }
}
