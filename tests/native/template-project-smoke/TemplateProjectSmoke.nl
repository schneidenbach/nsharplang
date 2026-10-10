namespace NSharpLang.TemplateProjectSmoke.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Cli
import NSharpLang.Compiler


// THE TEMPLATES, BUILT WHERE THE INNER LOOP CAN SEE THEM.
//
// The gate builds a template-generated project in Steps 5-7 (`dotnet new nsharp-console`,
// `dotnet new nsharp-webapi`, then `nlc build` on each) and it is the ONLY thing that does. That
// step is what caught a wrong package-version rule in the resolver while the native sweep, the
// compiler-service estate, the front door and `ilverify` were all green with it — a resolver change
// is exactly the kind `dev.sh --since` will not route to a template, because no template is a test.
//
// This project closes that hole by doing the same two things OFFLINE, in process, as ordinary rows:
//
//   * every `templates/*/` project in the repository is copied to a scratch directory and built
//     through `CliIlBackend.BuildWithIlBackend` — the exact call `nlc build` makes, reference
//     resolution and all — and its output file is asserted to exist;
//   * every template `nlc new` can scaffold is WRITTEN from `NewCommandKernels` (the project.yml
//     text, the source-file set and each file's text, which is what `nlc new` puts on disk) and
//     built the same way.
//
// THE TWO SOURCES ARE DIFFERENT AND BOTH SHIP. `templates/` is the `dotnet new` template package;
// `NewCommandKernels` is what `nlc new` writes. A defect in either is a defect a user meets on
// their first command, and neither had a row.
//
// THE BUILD COMMAND IS THE ENTRY AND THAT IS THE WHOLE POINT. Reaching past it to
// `MultiFileCompiler` skips the reference-resolution half — measured, `nsharp-webapi` then declines
// at `emit.declaration.base-type` on `ControllerBase`, because its `framework:` dependency is
// resolved by the command — and the resolver is the thing this project exists to cover.
//
// OFFLINE IS NOT A SIMPLIFICATION: nothing here restores from a feed, exactly as `nlc build` does
// not. A build that reports nothing and produces no file is a failure with a named reason, never a
// silent pass.
class TemplateSmokeOutcome {
    Name: string
    Built: bool
    // Empty when the build succeeded; otherwise what failed, so the assertion that reads it names
    // the template AND the reason without a second run.
    Reason: string

    constructor(name: string, built: bool, reason: string) {
        Name = name
        Built = built
        Reason = reason
    }
}

func TemplateSmokeRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "templates")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this assembly.")
}

func TemplateSmokeTemplatesDirectory(): string {
    return Path.Combine(TemplateSmokeRepositoryRoot(), "templates")
}

// Every `templates/<name>` directory that carries a `project.yml`, in a stable order. The template
// PACKAGE project (`NSharpLang.Templates.csproj`) is a file rather than a directory, so it is not
// one of these and needs no exclusion.
func TemplateSmokeTemplateNames(): List<string> {
    names := new List<string>()
    directories := Directory.GetDirectories(TemplateSmokeTemplatesDirectory())
    Array.Sort(directories)
    index := 0
    while index < directories.Length {
        candidate := directories[index]
        if File.Exists(Path.Combine(candidate, "project.yml")) {
            leaf := Path.GetFileName(candidate)
            if leaf != null {
                names.Add(leaf)
            }
        }

        index = index + 1
    }

    return names
}

func TemplateSmokeScratchRoot(label: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-template-smoke-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

// A RECURSIVE COPY, because a template may carry a subdirectory (`nsharp-webapi/Controllers`) and a
// template built in place would leave `bin/` and `obj/` inside the repository.
func TemplateSmokeCopyDirectory(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    files := Directory.GetFiles(source)
    fileIndex := 0
    while fileIndex < files.Length {
        name := Path.GetFileName(files[fileIndex])
        if name != null {
            File.Copy(files[fileIndex], Path.Combine(destination, name), true)
        }

        fileIndex = fileIndex + 1
    }

    directories := Directory.GetDirectories(source)
    directoryIndex := 0
    while directoryIndex < directories.Length {
        child := Path.GetFileName(directories[directoryIndex])
        if child != null && child != "bin" && child != "obj" {
            TemplateSmokeCopyDirectory(directories[directoryIndex], Path.Combine(destination, child))
        }

        directoryIndex = directoryIndex + 1
    }
}

// BUILD ONE PROJECT DIRECTORY the way `nlc build` does, and require BOTH a zero exit code and a
// file on disk.
func TemplateSmokeBuildDirectory(name: string, projectDirectory: string): TemplateSmokeOutcome {
    // `CliIlBackend.BuildWithIlBackend` IS `nlc build`: `ProgramCommands.BuildCommand` calls exactly
    // this with the project root and nothing else. Reaching for `MultiFileCompiler` directly would
    // skip the whole reference-resolution half — measured, `nsharp-webapi` then declines at
    // `emit.declaration.base-type` on `ControllerBase`, because the `framework:` dependency is
    // resolved by the command and not by the compiler — and the resolver is the thing this project
    // exists to cover.
    config := ProjectFileParser.Parse(Path.Combine(projectDirectory, "project.yml"))
    outputDirectory := Path.Combine(projectDirectory, "smoke-out")
    exitCode := CliIlBackend.BuildWithIlBackend(projectDirectory, false, outputDirectory, false).ExitCode
    outputPath := Path.Combine(outputDirectory, config.Name + ".dll")
    emitted := File.Exists(outputPath)
    if exitCode == 0 && emitted {
        return new TemplateSmokeOutcome(name, true, "")
    }

    // A build that reports nothing and produces nothing is not a pass, so the reason says which of
    // the two halves failed rather than leaving an empty message behind a false assertion. The
    // build's own diagnostics have already gone to the console the runner captures.
    return new TemplateSmokeOutcome(name, false, "exit=" + exitCode.ToString() + " emitted=" + emitted.ToString() + " at " + outputPath)
}

// Build the repository's own `templates/<name>` sources, copied out of the tree first.
func TemplateSmokeBuildShippedTemplate(name: string): TemplateSmokeOutcome {
    scratch := TemplateSmokeScratchRoot(name)
    projectDirectory := Path.Combine(scratch, name)
    TemplateSmokeCopyDirectory(Path.Combine(TemplateSmokeTemplatesDirectory(), name), projectDirectory)

    return TemplateSmokeBuildDirectory(name, projectDirectory)
}

// WHAT `nlc new <name> --template <kind>` PUTS ON DISK, written from the same kernels the command
// writes it from: the `project.yml` text, the source-file set for the template, and each file's
// text. The `global.json` and `NuGet.config` the command also writes are MSBuild-path files and are
// written here too, so the scratch directory is byte-identical to a scaffolded one.
func TemplateSmokeScaffold(templateName: string, projectName: string): string {
    scratch := TemplateSmokeScratchRoot("new-" + templateName)
    projectDirectory := NewCommandKernels.GetProjectDirectory(scratch, projectName)
    Directory.CreateDirectory(projectDirectory)

    File.WriteAllText(NewCommandKernels.GetProjectYamlPath(projectDirectory), NewCommandKernels.GetProjectYamlText(projectName, templateName))
    File.WriteAllText(NewCommandKernels.GetGlobalJsonPath(projectDirectory), NewCommandKernels.GetGlobalJsonText())
    File.WriteAllText(NewCommandKernels.GetNuGetConfigPath(projectDirectory), NewCommandKernels.GetNuGetConfigText("packages"))

    sourceFileKinds := NewCommandKernels.GetTemplateSourceFileKinds(templateName)
    index := 0
    while index < sourceFileKinds.Length {
        sourceFileKind := sourceFileKinds[index]
        sourceDirectory := NewCommandKernels.GetTemplateSourceFileDirectory(projectDirectory, sourceFileKind)
        if sourceDirectory != null {
            Directory.CreateDirectory(sourceDirectory)
        }

        File.WriteAllText(
            NewCommandKernels.GetTemplateSourceFilePath(projectDirectory, sourceFileKind),
            NewCommandKernels.GetTemplateSourceText(templateName, sourceFileKind)
        )
        index = index + 1
    }

    return projectDirectory
}

func TemplateSmokeBuildScaffolded(templateName: string): TemplateSmokeOutcome {
    return TemplateSmokeBuildDirectory("nlc new --template " + templateName, TemplateSmokeScaffold(templateName, "SmokeApp"))
}

// EVERY TEMPLATE, BUILT, AND THE FAILURES NAMED. A summary line rather than a boolean, because the
// row that fails has to say WHICH template and WHY without a second run.
func TemplateSmokeBuildAllShipped(): string {
    report := ""
    for name in TemplateSmokeTemplateNames() {
        outcome := TemplateSmokeBuildShippedTemplate(name)
        if !outcome.Built {
            if report.Length > 0 {
                report = report + " ;; "
            }

            report = report + outcome.Name + ": " + outcome.Reason
        }
    }

    return report
}
