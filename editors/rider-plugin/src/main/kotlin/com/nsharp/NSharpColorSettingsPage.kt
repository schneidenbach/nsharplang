package com.nsharp

import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighter
import com.intellij.openapi.options.colors.AttributesDescriptor
import com.intellij.openapi.options.colors.ColorDescriptor
import com.intellij.openapi.options.colors.ColorSettingsPage
import com.nsharp.icons.NSharpIcons
import javax.swing.Icon

class NSharpColorSettingsPage : ColorSettingsPage {
    override fun getIcon(): Icon = NSharpIcons.FILE
    override fun getHighlighter(): SyntaxHighlighter = NSharpSyntaxHighlighter()
    override fun getDemoText(): String = """
        import System
        
        func main() {
            name := "N#"
            Console.WriteLine("Hello from " + name)
        }
    """.trimIndent()
    override fun getAdditionalHighlightingTagToDescriptorMap(): Map<String, TextAttributesKey>? = null
    override fun getAttributeDescriptors(): Array<AttributesDescriptor> = DESCRIPTORS
    override fun getColorDescriptors(): Array<ColorDescriptor> = ColorDescriptor.EMPTY_ARRAY
    override fun getDisplayName(): String = "N#"
    
    companion object {
        private val DESCRIPTORS = arrayOf(
            AttributesDescriptor("Keywords", NSharpSyntaxHighlighter.KEYWORD),
            AttributesDescriptor("String", NSharpSyntaxHighlighter.STRING),
            AttributesDescriptor("Number", NSharpSyntaxHighlighter.NUMBER),
            AttributesDescriptor("Comment", NSharpSyntaxHighlighter.COMMENT),
            AttributesDescriptor("Identifier", NSharpSyntaxHighlighter.IDENTIFIER)
        )
    }
}
