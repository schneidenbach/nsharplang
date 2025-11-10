package com.nsharp.run

import com.intellij.execution.configurations.ConfigurationFactory
import com.intellij.execution.configurations.ConfigurationType
import com.intellij.execution.configurations.RunConfiguration
import com.intellij.openapi.project.Project
import com.nsharp.icons.NSharpIcons
import javax.swing.Icon

class NSharpConfigurationType : ConfigurationType {
    override fun getDisplayName(): String = "N#"
    override fun getConfigurationTypeDescription(): String = "N# Run Configuration"
    override fun getIcon(): Icon = NSharpIcons.FILE
    override fun getId(): String = "NSharpRunConfiguration"
    override fun getConfigurationFactories(): Array<ConfigurationFactory> = arrayOf(NSharpConfigurationFactory(this))
}

class NSharpConfigurationFactory(type: ConfigurationType) : ConfigurationFactory(type) {
    override fun getId(): String = "N# Factory"
    override fun createTemplateConfiguration(project: Project): RunConfiguration = NSharpRunConfiguration(project, this, "N#")
    override fun getName(): String = "N# Configuration Factory"
}
