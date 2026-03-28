using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.LanguageServer.Client;
using Microsoft.VisualStudio.Threading;
using Microsoft.VisualStudio.Utilities;

namespace NSharpLang.VisualStudio.LanguageServer
{
    /// <summary>
    /// Language Server Protocol client for N# in Visual Studio.
    /// Provides IntelliSense, diagnostics, and other language features.
    /// </summary>
    [ContentType("nsharp")]
    [Export(typeof(ILanguageClient))]
    public class NSharpLanguageClient : ILanguageClient
    {
        public string Name => "N# Language Server Client";

        public IEnumerable<string> ConfigurationSections => null;

        public object InitializationOptions => null;

        public IEnumerable<string> FilesToWatch => null;

        public bool ShowNotificationOnInitializeFailed => true;

        public event AsyncEventHandler<EventArgs> StartAsync;
        public event AsyncEventHandler<EventArgs> StopAsync;

        /// <summary>
        /// Activates the language server by starting the N# LSP process.
        /// </summary>
        public async Task<Connection> ActivateAsync(CancellationToken token)
        {
            await Task.Yield();

            var languageServerPath = GetLanguageServerPath();

            if (string.IsNullOrEmpty(languageServerPath))
            {
                throw new FileNotFoundException(
                    "N# Language Server not found. Please ensure the N# SDK is installed.");
            }

            var processStartInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = languageServerPath,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(languageServerPath)
            };

            var process = Process.Start(processStartInfo);

            if (process == null)
            {
                throw new InvalidOperationException("Failed to start N# Language Server process.");
            }

            return new Connection(
                process.StandardOutput.BaseStream,
                process.StandardInput.BaseStream);
        }

        /// <summary>
        /// Called when the language client is loaded.
        /// </summary>
        public async Task OnLoadedAsync()
        {
            await StartAsync.InvokeAsync(this, EventArgs.Empty);
        }

        /// <summary>
        /// Called when the server is initialized.
        /// </summary>
        public Task OnServerInitializedAsync()
        {
            return Task.CompletedTask;
        }

        /// <summary>
        /// Called when the server initialization fails.
        /// </summary>
        public Task<InitializationFailureContext?> OnServerInitializeFailedAsync(ILanguageClientInitializationInfo initializationState)
        {
            // Return null to use default error handling
            return Task.FromResult<InitializationFailureContext?>(null);
        }

        /// <summary>
        /// Finds the N# Language Server executable.
        /// Searches in common installation locations.
        /// </summary>
        private string GetLanguageServerPath()
        {
            // Strategy 1: Look for dotnet tool installation
            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var dotnetToolsPath = Path.Combine(userProfile, ".dotnet", "tools", ".store",
                "nsharp.languageserver");

            if (Directory.Exists(dotnetToolsPath))
            {
                var languageServerDll = Directory.GetFiles(dotnetToolsPath, "LanguageServer.dll",
                    SearchOption.AllDirectories).FirstOrDefault();
                if (!string.IsNullOrEmpty(languageServerDll))
                {
                    return languageServerDll;
                }
            }

            // Strategy 2: Look in NuGet packages
            var nugetPackagesPath = Path.Combine(userProfile, ".nuget", "packages",
                "nsharp.languageserver");

            if (Directory.Exists(nugetPackagesPath))
            {
                var languageServerDll = Directory.GetFiles(nugetPackagesPath, "LanguageServer.dll",
                    SearchOption.AllDirectories).FirstOrDefault();
                if (!string.IsNullOrEmpty(languageServerDll))
                {
                    return languageServerDll;
                }
            }

            // Strategy 3: Look in Program Files
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            var nsharpPath = Path.Combine(programFiles, "NSharp", "LanguageServer");

            if (Directory.Exists(nsharpPath))
            {
                var languageServerDll = Path.Combine(nsharpPath, "LanguageServer.dll");
                if (File.Exists(languageServerDll))
                {
                    return languageServerDll;
                }
            }

            // Strategy 4: Look in development environment (relative to current assembly)
            var assemblyLocation = typeof(NSharpLanguageClient).Assembly.Location;
            var assemblyDir = Path.GetDirectoryName(assemblyLocation);

            // Go up to find src/NSharpLang.LanguageServer
            var currentDir = new DirectoryInfo(assemblyDir);
            while (currentDir != null)
            {
                var langServerPath = Path.Combine(currentDir.FullName, "src", "NSharpLang.LanguageServer",
                    "bin", "Debug", "net9.0", "LanguageServer.dll");

                if (File.Exists(langServerPath))
                {
                    return langServerPath;
                }

                // Also check Release
                langServerPath = Path.Combine(currentDir.FullName, "src", "NSharpLang.LanguageServer",
                    "bin", "Release", "net9.0", "LanguageServer.dll");

                if (File.Exists(langServerPath))
                {
                    return langServerPath;
                }

                currentDir = currentDir.Parent;
            }

            return null;
        }
    }
}
