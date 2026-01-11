package com.nsharp

import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighter
import com.intellij.openapi.options.colors.AttributesDescriptor
import com.intellij.openapi.options.colors.ColorDescriptor
import com.intellij.openapi.options.colors.ColorSettingsPage
import com.nsharp.highlighting.NSharpTextAttributes
import javax.swing.Icon

class NSharpColorSettingsPage : ColorSettingsPage {
    override fun getIcon(): Icon = NSharpIcons.FILE

    override fun getHighlighter(): SyntaxHighlighter = NSharpSyntaxHighlighterFactory().getSyntaxHighlighter(null, null)

    override fun getDemoText(): String = """
        // N# demo
        func main(): void {
            let name := "world"
            print($"Hello, {name}!")
        }
    """.trimIndent()

    override fun getAdditionalHighlightingTagToDescriptorMap(): MutableMap<String, TextAttributesKey>? = null

    override fun getAttributeDescriptors(): Array<AttributesDescriptor> = arrayOf(
        AttributesDescriptor("Keyword", NSharpTextAttributes.KEYWORD),
        AttributesDescriptor("String", NSharpTextAttributes.STRING),
        AttributesDescriptor("Number", NSharpTextAttributes.NUMBER),
        AttributesDescriptor("Comment", NSharpTextAttributes.COMMENT),
        AttributesDescriptor("Operator", NSharpTextAttributes.OPERATOR)
    )

    override fun getColorDescriptors(): Array<ColorDescriptor> = ColorDescriptor.EMPTY_ARRAY

    override fun getDisplayName(): String = "N#"
}

