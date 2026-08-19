namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR `project.yml` — THE FILE EVERY N# PROJECT IS BUILT FROM (020 slice 15).
//
// These came out of `tests/ProjectFileTests.cs`, which is deleted. That file asked twenty-three
// questions of this parser: eight whole documents, three rejections, the two directory entry
// points, the default, the template, and six reference shapes.
//
// EVERY REJECTION IS NOW STATED AS ITS WHOLE MESSAGE AND ITS EXCEPTION TYPE. The deleted file wrote
// `Assert.Throws<InvalidOperationException>(() => ProjectFileParser.Parse(tempFile))` three times.
// Those three assertions cannot tell one refusal from another: a parser that rejected every
// document with "Invalid backend" would have passed all three. `ValidateConfig` has NINE distinct
// refusals and the deleted file reached three of them; all nine are below, each with the text a
// user actually sees.
//
// AND THE FILE-NOT-FOUND FAMILY WAS ENTIRELY UNASSERTED. `Parse` on a missing path, an `entry:`
// naming a file that is not there, a `dll:` that is not there and a `project:` that is not there
// are four different `FileNotFoundException`s carrying four different sentences — the ones a
// developer sees when a project is half-checked-out — and no C# assertion ever produced one.

func PfpTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-file-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

func PfpWrite(directory: string, yaml: string): string {
    path := Path.Combine(directory, "project.yml")
    File.WriteAllText(path, yaml)
    return path
}

// One line, both halves of a rejection: the exception TYPE and the whole sentence. `<parsed:…>`
// when nothing is thrown, so a validation that silently stopped refusing cannot read as a pass.
func PfpParseOutcome(path: string): string {
    try {
        parsed := ProjectFileParser.Parse(path)
        return "<parsed:" + (parsed.Name ?? "<null>") + ">"
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        if invalid != null {
            return "InvalidOperationException|" + ex.Message
        }

        missing := ex as FileNotFoundException
        if missing != null {
            return "FileNotFoundException|" + ex.Message
        }

        return "<unexpected exception type>|" + ex.Message
    }
}

func PfpOutcomeOf(directory: string, yaml: string): string {
    return PfpParseOutcome(PfpWrite(directory, yaml))
}

func PfpReferenceCensus(references: List<Reference>): string {
    census := ""
    index := 0
    while index < references.Count {
        reference := references[index]
        kind := "framework"
        if reference.Type == ReferenceType.NuGet {
            kind = "nuget"
        }
        if reference.Type == ReferenceType.Dll {
            kind = "dll"
        }
        if reference.Type == ReferenceType.Project {
            kind = "project"
        }

        census = census + kind + ":" + reference.Value + "@" + (reference.Version ?? "<none>") + ";"
        index = index + 1
    }

    return census
}

func PfpTemplateText(projectName: string): string {
    return "name: " + projectName + "\nversion: 1.0.0\nentry: Program.nl\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n\n# Test framework: xunit (default) or nunit\n# testFramework: xunit\n\n# Add your dependencies here\n# dependencies:\n#   - nuget: Newtonsoft.Json\n#     version: 13.0.3\n\nlanguage:\n  profile: default\n  asyncDefaultType: ValueTask\n\n# package:\n#   author: Your Name\n#   description: A short description\n#   license: MIT\n"
}

// ── a whole document ──────────────────────────────────────────────────────────────────────────

test "a complete project.yml reads back field for field, including the dependency list" {
    directory := PfpTempDirectory("valid")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "// test")
    path := PfpWrite(directory, "name: MyProject\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n\ndependencies:\n  - nuget: Newtonsoft.Json\n    version: 13.0.3\n  - nuget: System.Text.Json\n    version: 8.0.0\n\nlanguage:\n  asyncDefaultType: ValueTask\n")

    config := ProjectFileParser.Parse(path)
    assert config.Name == "MyProject"
    assert config.Version == "1.0.0"
    assert config.Entry == "Program.nl"
    assert config.OutputType == "exe"
    assert config.TargetFramework == "net10.0"
    assert config.Backend == "il"
    assert config.Dependencies.Count == 2
    assert config.Dependencies[0].Nuget == "Newtonsoft.Json"
    assert config.Dependencies[0].Version == "13.0.3"
    assert config.Dependencies[1].Nuget == "System.Text.Json"
    assert config.Dependencies[1].Version == "8.0.0"
    assert config.Language.AsyncDefaultType == "ValueTask"

    // The C# read the two dependencies through `FirstOrDefault(r => r.Nuget == …)`, which cannot see
    // ORDER. The census states both rows, their kinds, their versions and their order at once.
    assert PfpReferenceCensus(config.Dependencies) == "nuget:Newtonsoft.Json@13.0.3;nuget:System.Text.Json@8.0.0;"
    assert config.TestDependencies.Count == 0

    Directory.Delete(directory, true)
}

test "a project.yml carrying nothing but a name carries every default with it" {
    directory := PfpTempDirectory("minimal")
    path := PfpWrite(directory, "name: MinimalProject\n")

    config := ProjectFileParser.Parse(path)
    assert config.Name == "MinimalProject"
    assert config.Version == null
    assert config.Entry == null
    assert config.Backend == "il"
    assert config.OutputType == "exe"
    assert config.TargetFramework == "net10.0"
    assert config.Dependencies.Count == 0
    assert config.Language.AsyncDefaultType == "ValueTask"

    // The defaults the deleted file never read off a PARSED document — only off `new ProjectConfig()`
    // or not at all. A deserializer that wrote an empty string into one of these would have passed.
    assert config.TestFramework == "xunit"
    assert config.Sdk == "Microsoft.NET.Sdk"
    assert config.Language.PooledAsync == false
    assert config.Language.Profile == "default"
    assert config.Language.Systems.Mode == "strict"
    assert config.Language.Systems.UnknownExternalCalls == "warn"
    assert config.Language.Systems.AotTarget == "nativeaot"
    assert config.Language.Systems.StackBudgetBytes == 4096
    assert config.Exclude.Count == 0
    assert config.Defines.Count == 0
    assert config.Package == null

    Directory.Delete(directory, true)
}

test "a library project keeps the output type and the target framework it was given" {
    directory := PfpTempDirectory("library")
    path := PfpWrite(directory, "name: MyLibrary\noutputType: library\ntargetFramework: net8.0\n")

    config := ProjectFileParser.Parse(path)
    assert config.Name == "MyLibrary"
    assert config.OutputType == "library"
    assert config.TargetFramework == "net8.0"

    Directory.Delete(directory, true)
}

test "the backend is `il`, whether it is written down or left out" {
    directory := PfpTempDirectory("backend")
    written := ProjectFileParser.Parse(PfpWrite(directory, "name: IlProject\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n"))
    assert written.Backend == "il"

    omitted := ProjectFileParser.Parse(PfpWrite(directory, "name: IlProject\n"))
    assert omitted.Backend == "il"

    Directory.Delete(directory, true)
}

test "the async default type and the pooled-async flag are read from the language section" {
    directory := PfpTempDirectory("language")
    task := ProjectFileParser.Parse(PfpWrite(directory, "name: TaskProject\nlanguage:\n  asyncDefaultType: Task\n"))
    assert task.Language.AsyncDefaultType == "Task"
    assert task.Language.PooledAsync == false

    pooled := ProjectFileParser.Parse(PfpWrite(directory, "name: PooledProject\nlanguage:\n  asyncDefaultType: ValueTask\n  pooledAsync: true\n"))
    assert pooled.Language.PooledAsync
    assert pooled.Language.AsyncDefaultType == "ValueTask"

    unset := ProjectFileParser.Parse(PfpWrite(directory, "name: DefaultProject\n"))
    assert unset.Language.PooledAsync == false

    Directory.Delete(directory, true)
}

test "the test framework is read, defaulted, and refused when it is neither" {
    directory := PfpTempDirectory("testframework")
    xunit := ProjectFileParser.Parse(PfpWrite(directory, "name: MyProject\nversion: 1.0.0\noutputType: exe\ntargetFramework: net10.0\ntestFramework: xunit\n"))
    assert xunit.TestFramework == "xunit"

    nunit := ProjectFileParser.Parse(PfpWrite(directory, "name: MyProject\nversion: 1.0.0\noutputType: exe\ntargetFramework: net10.0\ntestFramework: nunit\n"))
    assert nunit.TestFramework == "nunit"

    assert PfpOutcomeOf(directory, "name: MyProject\nversion: 1.0.0\noutputType: exe\ntargetFramework: net10.0\ntestFramework: mstest\n") == "InvalidOperationException|Invalid testFramework: 'mstest'. Must be 'xunit' or 'nunit'."

    Directory.Delete(directory, true)
}

// ── the refusals, all nine of them, as whole sentences ────────────────────────────────────────

test "EVERY VALIDATION REFUSES WITH ITS OWN SENTENCE, AND THE DELETED FILE REACHED THREE OF NINE" {
    directory := PfpTempDirectory("refusals")

    assert PfpOutcomeOf(directory, "name: BadProject\noutputType: invalid\n") == "InvalidOperationException|Invalid outputType: 'invalid'. Must be 'exe' or 'library'."
    assert PfpOutcomeOf(directory, "name: BadProject\nbackend: wasm\n") == "InvalidOperationException|Invalid backend: 'wasm'. Must be 'il'."
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  asyncDefaultType: Promise\n") == "InvalidOperationException|Invalid language.asyncDefaultType: 'Promise'. Must be 'Task' or 'ValueTask'."
    assert PfpOutcomeOf(directory, "name: BadProject\ntestFramework: mstest\n") == "InvalidOperationException|Invalid testFramework: 'mstest'. Must be 'xunit' or 'nunit'."

    // The five nobody had ever produced.
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  profile: turbo\n") == "InvalidOperationException|Invalid language.profile: 'turbo'. Must be 'default' or 'systems'."
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  systems:\n    mode: lenient\n") == "InvalidOperationException|Invalid language.systems.mode: 'lenient'. Must be 'audit' or 'strict'."
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  systems:\n    unknownExternalCalls: shout\n") == "InvalidOperationException|Invalid language.systems.unknownExternalCalls: 'shout'. Must be 'allow', 'warn', or 'error'."
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  systems:\n    aotTarget: jvm\n") == "InvalidOperationException|Invalid language.systems.aotTarget: 'jvm'. Must be 'nativeaot', 'coreclr', or 'mono-wasm'."
    assert PfpOutcomeOf(directory, "name: BadProject\nlanguage:\n  systems:\n    stackBudgetBytes: 0\n") == "InvalidOperationException|Invalid language.systems.stackBudgetBytes: '0'. Must be greater than zero."

    // And the ORDER of the walk, which no single-refusal document can show: a document that is wrong
    // in two places reports the FIRST check, not the loudest one.
    assert PfpOutcomeOf(directory, "name: BadProject\noutputType: invalid\nbackend: wasm\n") == "InvalidOperationException|Invalid outputType: 'invalid'. Must be 'exe' or 'library'."

    // The control: the same shapes with legal values are accepted, so the refusals above are
    // decided by the VALUE and not by the section being present at all.
    assert PfpOutcomeOf(directory, "name: GoodProject\noutputType: library\nlanguage:\n  profile: systems\n  systems:\n    mode: audit\n    unknownExternalCalls: error\n    aotTarget: coreclr\n    stackBudgetBytes: 8192\n") == "<parsed:GoodProject>"

    Directory.Delete(directory, true)
}

test "THE FILE-NOT-FOUND FAMILY, WHICH NO C# ASSERTION EVER PRODUCED" {
    directory := PfpTempDirectory("missing")

    absent := Path.Combine(directory, "not-a-project.yml")
    assert PfpParseOutcome(absent) == "FileNotFoundException|Project file not found: " + absent

    // An `entry:` that names a file that is not there names the file AND the path it resolved to.
    entryPath := Path.Combine(directory, "Program.nl")
    assert PfpOutcomeOf(directory, "name: EntryProject\nentry: Program.nl\n") == "FileNotFoundException|Entry file not found: Program.nl (resolved to " + entryPath + ")"

    // Written down, the same document parses — so the refusal is the missing FILE and not the field.
    File.WriteAllText(entryPath, "func main() {}\n")
    assert PfpOutcomeOf(directory, "name: EntryProject\nentry: Program.nl\n") == "<parsed:EntryProject>"

    // A `dll:` and a `project:` reference are validated against the project directory too.
    dllPath := Path.Combine(directory, "MyLibrary.dll")
    assert PfpOutcomeOf(directory, "name: DllProject\ndependencies:\n  - dll: MyLibrary.dll\n") == "FileNotFoundException|DLL not found: MyLibrary.dll (resolved to " + dllPath + ")"

    projectPath := Path.Combine(directory, "Shared/Shared.csproj")
    assert PfpOutcomeOf(directory, "name: ProjectRefProject\ndependencies:\n  - project: Shared/Shared.csproj\n") == "FileNotFoundException|Project file not found: Shared/Shared.csproj (resolved to " + projectPath + ")"

    // A `nuget:` and a `framework:` reference are NOT validated against the disk, which is why a
    // restore-less check still works. The asymmetry was never stated.
    assert PfpOutcomeOf(directory, "name: NugetProject\ndependencies:\n  - nuget: Dapper\n") == "<parsed:NugetProject>"
    assert PfpOutcomeOf(directory, "name: FrameworkProject\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n") == "<parsed:FrameworkProject>"

    Directory.Delete(directory, true)
}

// ── the reference list ────────────────────────────────────────────────────────────────────────

test "a nuget reference reads back with a version, without one, and in the `name@version` shorthand" {
    directory := PfpTempDirectory("nuget")

    withVersion := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - nuget: Microsoft.EntityFrameworkCore\n    version: 9.0.0\n"))
    assert withVersion.Dependencies.Count == 1
    assert withVersion.Dependencies[0].Type == ReferenceType.NuGet
    assert withVersion.Dependencies[0].Nuget == "Microsoft.EntityFrameworkCore"
    assert withVersion.Dependencies[0].Version == "9.0.0"

    withoutVersion := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - nuget: Dapper\n"))
    assert withoutVersion.Dependencies.Count == 1
    assert withoutVersion.Dependencies[0].Type == ReferenceType.NuGet
    assert withoutVersion.Dependencies[0].Nuget == "Dapper"
    assert withoutVersion.Dependencies[0].Version == null

    shorthand := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - nuget: Dapper@2.1.28\n"))
    assert shorthand.Dependencies.Count == 1
    assert shorthand.Dependencies[0].Type == ReferenceType.NuGet
    assert shorthand.Dependencies[0].Nuget == "Dapper"
    assert shorthand.Dependencies[0].Version == "2.1.28"

    Directory.Delete(directory, true)
}

test "a framework, a dll and a project reference each read back as their own kind" {
    directory := PfpTempDirectory("kinds")

    framework := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n"))
    assert framework.Dependencies.Count == 1
    assert framework.Dependencies[0].Type == ReferenceType.Framework
    assert framework.Dependencies[0].Framework == "Microsoft.AspNetCore.App"

    File.WriteAllText(Path.Combine(directory, "MyLibrary.dll"), "dummy")
    dll := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - dll: MyLibrary.dll\n"))
    assert dll.Dependencies.Count == 1
    assert dll.Dependencies[0].Type == ReferenceType.Dll
    assert dll.Dependencies[0].Dll == "MyLibrary.dll"

    sharedDirectory := Path.Combine(directory, "Shared")
    Directory.CreateDirectory(sharedDirectory)
    File.WriteAllText(Path.Combine(sharedDirectory, "Shared.csproj"), "<Project />")
    projectReference := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - project: Shared/Shared.csproj\n"))
    assert projectReference.Dependencies.Count == 1
    assert projectReference.Dependencies[0].Type == ReferenceType.Project
    assert projectReference.Dependencies[0].Project == "Shared/Shared.csproj"

    Directory.Delete(directory, true)
}

test "four kinds in one document keep their kinds, their values AND their written order" {
    directory := PfpTempDirectory("mixed")
    File.WriteAllText(Path.Combine(directory, "Custom.dll"), "dummy")
    sharedDirectory := Path.Combine(directory, "Shared")
    Directory.CreateDirectory(sharedDirectory)
    File.WriteAllText(Path.Combine(sharedDirectory, "Shared.csproj"), "<Project />")

    config := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - nuget: Dapper@2.1.28\n  - dll: Custom.dll\n  - project: Shared/Shared.csproj\n  - framework: Microsoft.AspNetCore.App\n"))

    assert config.Dependencies.Count == 4
    assert config.Dependencies[0].Type == ReferenceType.NuGet
    assert config.Dependencies[0].Nuget == "Dapper"
    assert config.Dependencies[0].Version == "2.1.28"
    assert config.Dependencies[1].Type == ReferenceType.Dll
    assert config.Dependencies[1].Dll == "Custom.dll"
    assert config.Dependencies[2].Type == ReferenceType.Project
    assert config.Dependencies[2].Project == "Shared/Shared.csproj"
    assert config.Dependencies[3].Type == ReferenceType.Framework
    assert config.Dependencies[3].Framework == "Microsoft.AspNetCore.App"
    assert PfpReferenceCensus(config.Dependencies) == "nuget:Dapper@2.1.28;dll:Custom.dll@<none>;project:Shared/Shared.csproj@<none>;framework:Microsoft.AspNetCore.App@<none>;"

    Directory.Delete(directory, true)
}

test "AN EMPTY REFERENCE ROW IS DROPPED RATHER THAN CARRIED, IN BOTH DEPENDENCY LISTS" {
    // `FilterReferences` runs over `Dependencies` AND `TestDependencies` and removes every row with
    // no value at all — the shape a half-written or commented-out list leaves behind. Nothing
    // asserted it, and a carried empty row throws from `Reference.Type` the moment anything asks.
    directory := PfpTempDirectory("filter")
    config := ProjectFileParser.Parse(PfpWrite(directory, "name: TestProject\ndependencies:\n  - nuget: Dapper\n  - nuget: \"\"\n  - nuget: \"   \"\ntestDependencies:\n  - nuget: \"\"\n  - nuget: xunit\n"))

    assert PfpReferenceCensus(config.Dependencies) == "nuget:Dapper@<none>;"
    assert PfpReferenceCensus(config.TestDependencies) == "nuget:xunit@<none>;"

    Directory.Delete(directory, true)
}

test "A SECTION KEY WRITTEN WITH NOTHING UNDER IT IS THE EMPTY DEFAULT, NOT A NULL" {
    // `exclude:`, `defines:` and `language:` with no content deserialize a NULL into the setter, and
    // each setter replaces it with the empty value. This is the arm that stops `nlc build` from
    // throwing a `NullReferenceException` on a half-written `project.yml` — a shape every user
    // produces the moment they comment a list out — and nothing asserted it.
    directory := PfpTempDirectory("emptysections")
    config := ProjectFileParser.Parse(PfpWrite(directory, "name: EmptySections\nexclude:\ndefines:\nlanguage:\n"))

    assert config.Exclude.Count == 0
    assert config.Defines.Count == 0
    assert config.Language.AsyncDefaultType == "ValueTask"
    assert config.Language.Profile == "default"
    assert config.Language.Systems.Mode == "strict"
    assert config.Name == "EmptySections"

    Directory.Delete(directory, true)
}

// ── the directory entry points ────────────────────────────────────────────────────────────────

test "ParseFromDirectory answers the document when there is one and null when there is not" {
    directory := PfpTempDirectory("fromdir")
    absent := ProjectFileParser.ParseFromDirectory(directory)
    assert absent == null

    PfpWrite(directory, "name: DirProject\nversion: 2.0.0\n")
    config := ProjectFileParser.ParseFromDirectory(directory)
    assert config != null
    if config != null {
        assert config.Name == "DirProject"
        assert config.Version == "2.0.0"
    }

    // The file it looks for is `project.yml` and nothing else — not `project.yaml`, which is the
    // spelling a YAML-trained developer reaches for first.
    other := PfpTempDirectory("fromdir-other")
    File.WriteAllText(Path.Combine(other, "project.yaml"), "name: WrongExtension\n")
    wrongExtension := ProjectFileParser.ParseFromDirectory(other)
    assert wrongExtension == null

    Directory.Delete(other, true)
    Directory.Delete(directory, true)
}

test "ParseFromDirectoryOrDefault names the project after the directory when there is no document" {
    directory := PfpTempDirectory("ordefault")
    config := ProjectFileParser.ParseFromDirectoryOrDefault(directory)
    assert config.Name == Path.GetFileName(directory)
    assert config.Backend == "il"
    assert config.TargetFramework == "net10.0"
    assert config.OutputType == "exe"
    assert config.Language.AsyncDefaultType == "ValueTask"

    // And it prefers the real document when there is one, which the deleted file never checked on
    // this entry point — only on `ParseFromDirectory`.
    PfpWrite(directory, "name: WrittenDown\n")
    written := ProjectFileParser.ParseFromDirectoryOrDefault(directory)
    assert written.Name == "WrittenDown"

    Directory.Delete(directory, true)
}

test "CreateDefault carries the same defaults a document-less directory gets" {
    config := ProjectFileParser.CreateDefault("TestProject")
    assert config.Name == "TestProject"
    assert config.OutputType == "exe"
    assert config.TargetFramework == "net10.0"
    assert config.Backend == "il"
    assert config.Dependencies.Count == 0
    assert config.Language.AsyncDefaultType == "ValueTask"

    // The nameless arity the CLI uses when it has no directory to name the project after.
    anonymous := ProjectFileParser.CreateDefault(null)
    assert anonymous.Name == null
    assert anonymous.Backend == "il"
    assert anonymous.TestFramework == "xunit"
}

// ── the template ──────────────────────────────────────────────────────────────────────────────

test "THE GENERATED TEMPLATE IS PINNED WHOLE, NOT SAMPLED BY SEVEN `Contains`" {
    // The deleted file asserted that seven substrings appear somewhere. That is satisfied by a
    // template with the lines in any order, with a duplicated key, or with the comment block gone.
    // `nlc new` writes this file into every project a user ever starts, so it is stated whole.
    template := ProjectFileParser.GenerateTemplate("MyNewProject")
    assert template == PfpTemplateText("MyNewProject")

    // The seven the deleted file named, kept explicitly so the whole-text pin above is not the only
    // place a lost line would show.
    assert template.Contains("name: MyNewProject")
    assert template.Contains("version: 1.0.0")
    assert template.Contains("entry: Program.nl")
    assert template.Contains("backend: il")
    assert template.Contains("outputType: exe")
    assert template.Contains("targetFramework: net10.0")
    assert template.Contains("asyncDefaultType: ValueTask")

    // The name is the ONLY thing that moves between two templates.
    other := ProjectFileParser.GenerateTemplate("Other")
    assert other == PfpTemplateText("Other")

    // Every line ends with `\n` and the file ends with one, so the template is not platform-dependent
    // the way an `AppendLine` fixture would be.
    assert !template.Contains("\r")
    assert template.EndsWith("license: MIT\n")
}

test "the generated template is a document THIS parser accepts, and its dependency lists are empty" {
    directory := PfpTempDirectory("template")
    path := PfpWrite(directory, ProjectFileParser.GenerateTemplate("GeneratedProject"))
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "func main() { }")

    config := ProjectFileParser.Parse(path)
    assert config.Name == "GeneratedProject"
    assert config.Entry == "Program.nl"
    assert config.Dependencies.Count == 0
    assert config.TestDependencies.Count == 0

    // The commented-out block is a comment and nothing else: the round trip keeps every other field
    // the template writes down, which four `Assert`s could not say.
    assert config.Version == "1.0.0"
    assert config.Backend == "il"
    assert config.OutputType == "exe"
    assert config.TargetFramework == "net10.0"
    assert config.TestFramework == "xunit"
    assert config.Language.Profile == "default"
    assert config.Language.AsyncDefaultType == "ValueTask"
    assert config.Package == null

    Directory.Delete(directory, true)
}
