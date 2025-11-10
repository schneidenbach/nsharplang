package com.nsharp.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.ProcessHandlerFactory
import com.intellij.execution.process.ProcessTerminatedListener
import java.io.File

class NSharpBuildAction : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        try {
            val projectPath = project.basePath ?: return
            val commandLine = GeneralCommandLine("dotnet", "build")
            commandLine.workDirectory = File(projectPath)
            val processHandler = ProcessHandlerFactory.getInstance().createColoredProcessHandler(commandLine)
            ProcessTerminatedListener.attach(processHandler)
            processHandler.startNotify()
        } catch (ex: Exception) {
            Messages.showErrorDialog(project, "Failed to build: ${ex.message}", "Build Error")
        }
    }
    override fun update(e: AnActionEvent) {
        e.presentation.isEnabled = e.project != null
    }
}
