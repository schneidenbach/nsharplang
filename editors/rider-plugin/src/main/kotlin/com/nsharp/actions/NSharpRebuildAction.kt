package com.nsharp.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.ProcessHandlerFactory
import com.intellij.execution.process.ProcessTerminatedListener
import java.io.File

class NSharpRebuildAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        try {
            val projectPath = project.basePath ?: return
            val cleanCommand = GeneralCommandLine("dotnet", "clean")
            cleanCommand.workDirectory = File(projectPath)
            val cleanHandler = ProcessHandlerFactory.getInstance().createColoredProcessHandler(cleanCommand)
            ProcessTerminatedListener.attach(cleanHandler)
            cleanHandler.startNotify()
            cleanHandler.waitFor()
            
            val buildCommand = GeneralCommandLine("dotnet", "build")
            buildCommand.workDirectory = File(projectPath)
            val buildHandler = ProcessHandlerFactory.getInstance().createColoredProcessHandler(buildCommand)
            ProcessTerminatedListener.attach(buildHandler)
            buildHandler.startNotify()
        } catch (ex: Exception) {
            Messages.showErrorDialog(project, "Failed to rebuild: ${ex.message}", "Rebuild Error")
        }
    }
    override fun update(e: AnActionEvent) {
        e.presentation.isEnabled = e.project != null
    }
}
