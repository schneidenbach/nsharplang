package com.nsharp.run

import com.intellij.execution.Executor
import com.intellij.execution.configurations.*
import com.intellij.execution.process.ProcessHandlerFactory
import com.intellij.execution.process.ProcessTerminatedListener
import com.intellij.execution.runners.ExecutionEnvironment
import com.intellij.openapi.options.SettingsEditor
import com.intellij.openapi.project.Project
import javax.swing.*
import java.io.File

class NSharpRunConfiguration(project: Project, factory: ConfigurationFactory, name: String) : RunConfigurationBase<NSharpRunConfigurationOptions>(project, factory, name) {
    override fun getOptions(): NSharpRunConfigurationOptions = super.getOptions() as NSharpRunConfigurationOptions
    override fun getConfigurationEditor(): SettingsEditor<out RunConfiguration> = NSharpRunConfigurationEditor()
    
    override fun getState(executor: Executor, environment: ExecutionEnvironment): RunProfileState {
        return object : CommandLineState(environment) {
            override fun startProcess(): com.intellij.execution.process.ProcessHandler {
                val projectPath = project.basePath ?: throw RuntimeException("Project path not found")
                val commandLine = GeneralCommandLine("dotnet", "run")
                commandLine.workDirectory = File(projectPath)
                val processHandler = ProcessHandlerFactory.getInstance().createColoredProcessHandler(commandLine)
                ProcessTerminatedListener.attach(processHandler)
                return processHandler
            }
        }
    }
}

class NSharpRunConfigurationOptions : RunConfigurationOptions()

class NSharpRunConfigurationEditor : SettingsEditor<NSharpRunConfiguration>() {
    private val panel = JPanel()
    init {
        panel.layout = BoxLayout(panel, BoxLayout.Y_AXIS)
        panel.add(JLabel("N# Run Configuration"))
        panel.add(JLabel("Uses 'dotnet run' to execute the project"))
    }
    override fun resetEditorFrom(config: NSharpRunConfiguration) {}
    override fun applyEditorTo(config: NSharpRunConfiguration) {}
    override fun createEditor(): JComponent = panel
}
