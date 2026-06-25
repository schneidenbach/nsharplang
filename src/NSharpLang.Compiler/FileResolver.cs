using System.IO;

namespace NSharpLang.Compiler;

/// <summary>
/// Resolves file paths for file-based imports.
/// Handles relative paths (./,  ../), project-root paths, and .nl extension inference.
/// </summary>
public class FileResolver
{
    public string ProjectRoot { get; }
    public string CurrentFile { get; }

    public FileResolver(string projectRoot, string currentFile)
    {
        ProjectRoot = Path.GetFullPath(projectRoot);
        CurrentFile = Path.GetFullPath(currentFile);
    }

    /// <summary>
    /// Resolves an import path to an absolute file path.
    /// </summary>
    /// <param name="importPath">The import path from the import statement (e.g., "./Helpers", "Models/Person")</param>
    /// <returns>The absolute path to the .nl file</returns>
    public string ResolveFilePath(string importPath)
    {
        // Add .nl extension if not present
        if (!importPath.EndsWith(".nl"))
        {
            importPath += ".nl";
        }

        string resolvedPath;

        if (importPath.StartsWith("./") || importPath.StartsWith("../"))
        {
            // Relative to current file
            var currentDir = Path.GetDirectoryName(CurrentFile) ?? ProjectRoot;
            resolvedPath = Path.GetFullPath(Path.Combine(currentDir, importPath));
        }
        else
        {
            // Relative to project root
            resolvedPath = Path.GetFullPath(Path.Combine(ProjectRoot, importPath));
        }

        return resolvedPath;
    }

}
