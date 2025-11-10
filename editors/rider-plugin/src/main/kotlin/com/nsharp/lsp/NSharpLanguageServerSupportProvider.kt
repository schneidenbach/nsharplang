package com.nsharp.lsp

import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import com.intellij.platform.lsp.api.LspServerSupportProvider
import com.intellij.platform.lsp.api.ProjectWideLspServerDescriptor
import java.io.File
import java.nio.file.Paths

/**
 * Provides LSP server support for N# language files.
 */
class NSharpLanguageServerSupportProvider : LspServerSupportProvider {
    private val logger = Logger.getInstance(NSharpLanguageServerSupportProvider::class.java)

    override fun fileOpened(
        project: Project,
        file: VirtualFile,
        serverStarter: LspServerSupportProvider.LspServerStarter
    ) {
        if (file.extension == "nl") {
            logger.info("Opening N# file: ${file.path}")
            serverStarter.ensureServerStarted(NSharpLspServerDescriptor(project))
        }
    }

    /**
     * LSP server descriptor for N# language.
     */
    private class NSharpLspServerDescriptor(project: Project) : ProjectWideLspServerDescriptor(project, "N#") {
        private val logger = Logger.getInstance(NSharpLspServerDescriptor::class.java)

        override fun isSupportedFile(file: VirtualFile): Boolean {
            return file.extension == "nl"
        }

        override fun createCommandLine(): GeneralCommandLine {
            val serverPath = findLanguageServer()
            logger.info("Starting N# Language Server from: $serverPath")

            return GeneralCommandLine()
                .withExePath("dotnet")
                .withParameters(serverPath)
                .withCharset(Charsets.UTF_8)
                .apply {
                    // Set working directory to project base path
                    withWorkDirectory(project.basePath)
                }
        }

        /**
         * Finds the N# Language Server DLL.
         *
         * Search order:
         * 1. Bundled with plugin
         * 2. User's home directory (.nsharp/sdk)
         * 3. System-wide installation
         */
        private fun findLanguageServer(): String {
            // 1. Check bundled server (for plugin distribution)
            val pluginPath = System.getProperty("idea.plugins.path")
            if (pluginPath != null) {
                val bundledServer = File(pluginPath, "nsharp/server/LanguageServer.dll")
                if (bundledServer.exists()) {
                    logger.info("Found bundled Language Server: ${bundledServer.absolutePath}")
                    return bundledServer.absolutePath
                }
            }

            // 2. Check user's home directory
            val userHome = System.getProperty("user.home")
            val userServer = Paths.get(userHome, ".nsharp", "sdk", "LanguageServer.dll").toFile()
            if (userServer.exists()) {
                logger.info("Found user Language Server: ${userServer.absolutePath}")
                return userServer.absolutePath
            }

            // 3. Try to find in PATH (system installation)
            val dotnetSdk = findDotnetSdk()
            if (dotnetSdk != null) {
                val sdkServer = File(dotnetSdk, "LanguageServer.dll")
                if (sdkServer.exists()) {
                    logger.info("Found SDK Language Server: ${sdkServer.absolutePath}")
                    return sdkServer.absolutePath
                }
            }

            // Fall back to just the name - might be in PATH
            logger.warn("Language Server not found in standard locations, trying PATH")
            return "LanguageServer.dll"
        }

        /**
         * Attempts to locate the .NET SDK installation.
         */
        private fun findDotnetSdk(): String? {
            try {
                val process = ProcessBuilder("dotnet", "--list-sdks")
                    .redirectErrorStream(true)
                    .start()

                val output = process.inputStream.bufferedReader().readText()
                process.waitFor()

                // Parse output to find SDK location
                // Format: "9.0.100 [/usr/local/share/dotnet/sdk]"
                val sdkRegex = """\d+\.\d+\.\d+\s+\[(.+)]""".toRegex()
                val match = sdkRegex.find(output)

                return match?.groupValues?.get(1)
            } catch (e: Exception) {
                logger.warn("Failed to find dotnet SDK: ${e.message}")
                return null
            }
        }
    }
}
