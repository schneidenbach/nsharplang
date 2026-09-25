namespace NSharpLang.ProcessGlobalStateGuard.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text.RegularExpressions

// NO TEST ROW WRITES PROCESS-GLOBAL STATE.
//
// The compiler-service estate is ONE xunit process, and a native project is one `nlc test` process;
// in both, every `.tests.nl` file is its own test class and the classes run IN PARALLEL. An
// environment variable, the current directory or a console writer a row rewrites - even inside
// `try`/`finally` - is visible to every row running beside it. Measured, not supposed: two
// `CompilationReferenceResolver.tests.nl` rows that pointed `NUGET_PACKAGES` at a fixture cache made
// `ExternalAssemblyRuntimePairing.tests.nl`'s NuGet lookups throw on the temporary path (31ec1df96),
// and the `NSHARP_EXPERIMENTAL_SOA` rows in `AnalyzerTypeResolver.tests.nl` and
// `AnalyzerTypeDeclarations.tests.nl` flipped the gate other analyzer rows read.
//
// The fix is always the same one: the setting becomes an input of the owner the row drives
// (`ReferenceResolutionOptions.PackagesFolder`, `Analyzer.SoaEnabled`,
// `MultiFileCompiler.ColumnarDeclineLog`), read from the environment ONCE at the product's entry
// point, and a row whose claim is about that entry point runs a CHILD process with the variable in
// the child's own environment block. This guard keeps the call shapes from coming back. See
// memory/testing.md, "Estate Rows Never Rewrite Process-Global State".
func RepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not find repository root (NSharpLang.sln) above this test tree.")
}

// The banned writes: the process environment, the process's current directory (both spellings),
// and the three console streams. Reading any of them is fine; only the writes are shared hazards.
func ProcessGlobalWrite(): Regex {
    return new Regex(
        "\\bEnvironment\\s*\\.\\s*SetEnvironmentVariable\\s*\\(" + "|\\bDirectory\\s*\\.\\s*SetCurrentDirectory\\s*\\(" + "|\\bEnvironment\\s*\\.\\s*CurrentDirectory\\s*=(?!=)" + "|\\bConsole\\s*\\.\\s*Set(Out|Error|In)\\s*\\(",
        RegexOptions.Compiled
    )
}

// Comments legitimately name the banned APIs - most of the files that used to call them now explain
// why they do not - so only code before a `//` counts.
func StripLineCommentTail(line: string): string {
    commentStart := line.IndexOf("//", StringComparison.Ordinal)
    if commentStart < 0 {
        return line
    }

    return line.Substring(0, commentStart)
}

func IsBuildOutputPath(relativePath: string): bool {
    separators := [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]
    for segment in relativePath.Split(separators) {
        if segment == "bin" || segment == "obj" || segment == "TestResults" {
            return true
        }
    }

    return false
}

func AppendOffenders(repositoryRoot: string, sourcePath: string, pattern: Regex, offenders: List<string>) {
    lines := File.ReadAllLines(sourcePath)
    index := 0
    while index < lines.Length {
        if pattern.IsMatch(StripLineCommentTail(lines[index])) {
            offenders.Add(Path.GetRelativePath(repositoryRoot, sourcePath) + ":" + (index + 1).ToString() + ": " + lines[index].Trim())
        }

        index = index + 1
    }
}

// Every `.tests.nl` under `src/` - the estate, whichever project it lives beside once Compiler.Core
// is split.
func EstateFiles(repositoryRoot: string): List<string> {
    files := new List<string>()
    for sourcePath in Directory.EnumerateFiles(Path.Combine(repositoryRoot, "src"), "*.tests.nl", SearchOption.AllDirectories) {
        if !IsBuildOutputPath(Path.GetRelativePath(repositoryRoot, sourcePath)) {
            files.Add(sourcePath)
        }
    }

    files.Sort(StringComparer.Ordinal)
    return files
}

// Every `.nl` a native project compiles into its test assembly: its `.tests.nl` rows AND the plain
// `.nl` fixtures they call, which run in the same process. A directory below a project root that
// carries its own `project.yml` is a separate program the rows build and launch - its own process -
// and is not scanned.
func NativeTestProcessFiles(repositoryRoot: string): List<string> {
    files := new List<string>()
    nativeRoot := Path.Combine(Path.Combine(repositoryRoot, "tests"), "native")
    for projectDirectory in Directory.EnumerateDirectories(nativeRoot) {
        if !File.Exists(Path.Combine(projectDirectory, "project.yml")) {
            continue
        }

        for sourcePath in Directory.EnumerateFiles(projectDirectory, "*.nl", SearchOption.AllDirectories) {
            relative := Path.GetRelativePath(repositoryRoot, sourcePath)
            if IsBuildOutputPath(relative) || IsInsideNestedProject(projectDirectory, sourcePath) {
                continue
            }

            files.Add(sourcePath)
        }
    }

    files.Sort(StringComparer.Ordinal)
    return files
}

func IsInsideNestedProject(projectDirectory: string, sourcePath: string): bool {
    projectRoot := Path.GetFullPath(projectDirectory)
    current := Path.GetDirectoryName(Path.GetFullPath(sourcePath)) ?? projectRoot
    while current.Length > projectRoot.Length && current.StartsWith(projectRoot, StringComparison.Ordinal) {
        if File.Exists(Path.Combine(current, "project.yml")) {
            return true
        }

        current = Path.GetDirectoryName(current) ?? projectRoot
    }

    return false
}

func Offenders(files: List<string>): List<string> {
    repositoryRoot := RepositoryRoot()
    pattern := ProcessGlobalWrite()
    offenders := new List<string>()
    for sourcePath in files {
        AppendOffenders(repositoryRoot, sourcePath, pattern, offenders)
    }

    return offenders
}

test "no estate row writes the process environment, the current directory or a console stream" {
    files := EstateFiles(RepositoryRoot())

    // Not vacuous: the estate is hundreds of files, and a scan that found none proves nothing.
    assert files.Count >= 400, files.Count.ToString()
    offenders := Offenders(files)
    assert offenders.Count == 0, "Process-global writes in a test process (give the owner the value as an input, or set it in a child's environment):\n" + string.Join("\n", offenders)
}

test "no native test process writes the process environment, the current directory or a console stream" {
    files := NativeTestProcessFiles(RepositoryRoot())

    assert files.Count >= 400, files.Count.ToString()
    offenders := Offenders(files)
    assert offenders.Count == 0, "Process-global writes in a test process (give the owner the value as an input, or set it in a child's environment):\n" + string.Join("\n", offenders)
}

// The guard's own machinery is proved on text it controls, so a scan that silently stopped matching
// is caught. The banned spellings are assembled from pieces so this file does not trip its own scan.
test "the guard matches every banned write and ignores reads, look-alikes and comment tails" {
    pattern := ProcessGlobalWrite()
    setVariable := "Environment.Set" + "EnvironmentVariable"
    setDirectory := "Directory.Set" + "CurrentDirectory"
    currentDirectory := "Environment." + "CurrentDirectory"

    assert pattern.IsMatch(setVariable + "(\"NUGET_PACKAGES\", root)")
    assert pattern.IsMatch("System." + setVariable + " ( name, null )")
    assert pattern.IsMatch(setDirectory + "(root)")
    assert pattern.IsMatch(currentDirectory + " = root")
    assert pattern.IsMatch("Console.Set" + "Out(writer)")
    assert pattern.IsMatch("Console.Set" + "Error(writer)")
    assert pattern.IsMatch("Console . Set" + "In(reader)")

    assert !pattern.IsMatch("Environment.GetEnvironmentVariable(\"NUGET_PACKAGES\")")
    assert !pattern.IsMatch("startInfo.Environment[\"NUGET_PACKAGES\"] = root")
    assert !pattern.IsMatch("root := " + currentDirectory)
    assert !pattern.IsMatch("if " + currentDirectory + " == root {")
    assert !pattern.IsMatch("Directory.GetCurrentDirectory()")
    assert !pattern.IsMatch("writer := Console.Error")

    assert !pattern.IsMatch(StripLineCommentTail("// never call " + setVariable + "(name, value)"))
    assert pattern.IsMatch(StripLineCommentTail(setVariable + "(name, value) // banned"))
}

test "a nested project below a native project is its own program and is not scanned as the test process" {
    scratch := Path.Combine(Path.GetTempPath(), "nsharp-process-global-guard-" + Guid.NewGuid().ToString("N"))
    nested := Path.Combine(Path.Combine(scratch, "fixture"), "child")
    Directory.CreateDirectory(nested)
    try {
        File.WriteAllText(Path.Combine(scratch, "project.yml"), "name: Outer\n")
        File.WriteAllText(Path.Combine(Path.Combine(scratch, "fixture"), "project.yml"), "name: Child\n")
        assert IsInsideNestedProject(scratch, Path.Combine(nested, "Program.nl"))
        assert IsInsideNestedProject(scratch, Path.Combine(Path.Combine(scratch, "fixture"), "Program.nl"))
        assert !IsInsideNestedProject(scratch, Path.Combine(scratch, "Rows.tests.nl"))
    } finally {
        Directory.Delete(scratch, true)
    }
}
