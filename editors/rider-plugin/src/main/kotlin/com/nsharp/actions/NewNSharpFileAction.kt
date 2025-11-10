package com.nsharp.actions

import com.intellij.ide.actions.CreateFileFromTemplateAction
import com.intellij.ide.actions.CreateFileFromTemplateDialog
import com.intellij.openapi.project.Project
import com.intellij.psi.PsiDirectory
import com.nsharp.icons.NSharpIcons

class NewNSharpFileAction : CreateFileFromTemplateAction("N# File", "Create new N# file", NSharpIcons.FILE) {
    override fun buildDialog(project: Project, directory: PsiDirectory, builder: CreateFileFromTemplateDialog.Builder) {
        builder.setTitle("New N# File").addKind("N# File", NSharpIcons.FILE, "NSharp File")
    }
    override fun getActionName(directory: PsiDirectory, newName: String, templateName: String): String = "Create N# File $newName"
    override fun hashCode(): Int = javaClass.hashCode()
    override fun equals(other: Any?): Boolean = other is NewNSharpFileAction
}
