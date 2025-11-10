package com.nsharp.icons

import com.intellij.openapi.util.IconLoader
import javax.swing.Icon

object NSharpIcons {
    @JvmField
    val FILE: Icon = IconLoader.getIcon("/icons/nsharp-file.svg", NSharpIcons::class.java)

    @JvmField
    val PROJECT: Icon = IconLoader.getIcon("/icons/nsharp-project.svg", NSharpIcons::class.java)
}
