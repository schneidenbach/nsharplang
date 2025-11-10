package com.nsharp.run

import com.intellij.execution.actions.ConfigurationContext
import com.intellij.execution.actions.LazyRunConfigurationProducer
import com.intellij.execution.configurations.ConfigurationFactory
import com.intellij.openapi.util.Ref
import com.intellij.psi.PsiElement
import com.nsharp.NSharpFileType

class NSharpRunConfigurationProducer : LazyRunConfigurationProducer<NSharpRunConfiguration>() {
    override fun getConfigurationFactory(): ConfigurationFactory = NSharpConfigurationFactory(NSharpConfigurationType())
    
    override fun isConfigurationFromContext(configuration: NSharpRunConfiguration, context: ConfigurationContext): Boolean {
        val location = context.location ?: return false
        val file = location.psiElement.containingFile ?: return false
        return file.fileType is NSharpFileType
    }
    
    override fun setupConfigurationFromContext(configuration: NSharpRunConfiguration, context: ConfigurationContext, sourceElement: Ref<PsiElement>): Boolean {
        val location = context.location ?: return false
        val file = location.psiElement.containingFile ?: return false
        if (file.fileType !is NSharpFileType) return false
        configuration.name = "Run ${file.name}"
        return true
    }
}
