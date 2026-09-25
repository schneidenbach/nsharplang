namespace NSharpLang.CliCommandContracts.Tests

import System.IO
import System.Text.Json


// THE `nlc check` IMPORT AND VISIBILITY CONTRACTS, PROVEN AS PROCESSES.
//
// These are the `CheckCommand` rows of `tests/CliCommandTests.cs`. Like the query rows beside them
// they were written as `CheckCommand.Execute(args)` under a `Console.SetOut` capture, and like
// those rows they are re-made here against the shipped binary. The reason is merit, not necessity:
// an in-process call cannot show that `nlc check` REACHES the N# check owner, cannot show the exit
// code a shell or a CI job would see, and cannot show that the text arm's diagnostics go to STDERR
// while the JSON arm's envelope goes to STDOUT — which is exactly what the two cycle rows claim.
//
// WHAT THESE ROWS ARE FOR. The neighbouring `CliCommandContracts.tests.nl` already pins the check
// command's ENVELOPE and its argument handling. These rows are about the IMPORT GRAPH and the
// EXPORT RULE instead: file-import cycles, package versus namespace imports, and the NL308
// visibility diagnostic that decides whether a camelCase name is reachable from another package.
func CcCheckProject(prefix: string, name: string): string {
    directory := NewTempDirectory(prefix)
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: " + name + "\n" + "outputType: exe\n" + "targetFramework: net10.0\n"
    )
    return directory
}

func CcWriteFile(directory: string, relativePath: string, text: string) {
    fullPath := Path.Combine(directory, relativePath)
    parent := Path.GetDirectoryName(fullPath)
    if parent != null && parent != "" {
        Directory.CreateDirectory(parent ?? "")
    }

    File.WriteAllText(fullPath, text)
}

func CcTwoDigits(value: int): string {
    if value < 10 {
        return "0" + value.ToString()
    }

    return value.ToString()
}

func CcQuoted(path: string): string {
    return "\"" + path + "\""
}

// Every diagnostic code in a check envelope, comma-joined in report order.
func CcDiagnosticCodes(json: string): string {
    document := JsonDocument.Parse(json)
    text := ""
    enumerator := document.RootElement.GetProperty("results").EnumerateArray()
    while enumerator.MoveNext() {
        if text != "" {
            text = text + ","
        }

        text = text + TextOf(enumerator.Current.GetProperty("code"))
    }

    document.Dispose()
    return text
}

// The messages of every result carrying one code, comma-joined in report order.
func CcMessagesForCode(json: string, code: string): string {
    document := JsonDocument.Parse(json)
    text := ""
    enumerator := document.RootElement.GetProperty("results").EnumerateArray()
    while enumerator.MoveNext() {
        result := enumerator.Current
        if TextOf(result.GetProperty("code")) == code {
            if text != "" {
                text = text + ","
            }

            text = text + TextOf(result.GetProperty("message"))
        }
    }

    document.Dispose()
    return text
}

// ═══ THE HELP ROUTE AND THE DEFAULT ENVELOPE ══════════════════════════════════════════════════

test "nlc check --help prints its usage and never mistakes --help for a missing directory" {
    run := Nlc("check --help")

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Usage: nlc check")

    // The deleted row's real claim: asking for help is SIDE-EFFECT FREE. It must not fall through
    // to the project loader and report the working directory as missing.
    assert !run.Stderr.Contains("Directory not found")
}

test "nlc check defaults to the JSON envelope, with no --json needed, over a real example project" {
    project := CheckExampleProject("01-hello-world")

    run := Nlc("check --project " + CcQuoted(project))

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert TextOf(root.GetProperty("command")) == "check"
    assert root.GetProperty("ok").GetBoolean()
    assert EquivalentProcessPath(TextOf(root.GetProperty("projectRoot")), NormalizedFullPath(project))
    assert root.GetProperty("checkedFiles").GetInt32() >= 1
    assert QcRootKeys(run.Stdout) == QcContractKeys("check")
    document.Dispose()
}

test "nlc check over a missing project answers the structured error envelope naming the directory" {
    missingDirectory := MissingDirectoryPath("nsharp-check-missing-envelope")

    run := Nlc("check --project " + CcQuoted(missingDirectory))

    assert run.ExitCode == 1
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert TextOf(root.GetProperty("command")) == "check"
    assert !root.GetProperty("ok").GetBoolean()
    assert EquivalentProcessPath(TextOf(root.GetProperty("projectRoot")), NormalizedFullPath(missingDirectory))
    assert TextOf(root.GetProperty("error").GetProperty("message")).Contains("Directory not found")
    document.Dispose()
}

// ═══ MISSING IMPORTS AND IMPORT CYCLES ════════════════════════════════════════════════════════

test "nlc check reports the missing import for a type used without the import that provides it" {
    directory := NewTempDirectory("nsharp-check-missing-import")
    try {
        File.WriteAllText(
            Path.Combine(directory, "Program.nl"),
            "func Main() {\n" + "    sb := new StringBuilder()\n" + "    Console.WriteLine(sb.ToString())\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))
        assert run.ExitCode == 1

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert TextOf(root.GetProperty("command")) == "check"
        assert !root.GetProperty("ok").GetBoolean()
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a three-file import cycle fails both output modes, each on its own stream" {
    directory := CcCheckProject("nsharp-circular-import", "CircularImports")
    try {
        CcWriteFile(directory, "A.nl", "import \"B\"\n" + "\n" + "class A {\n" + "}\n")
        CcWriteFile(directory, "B.nl", "import \"C\"\n" + "\n" + "class B {\n" + "}\n")
        CcWriteFile(directory, "C.nl", "import \"A\"\n" + "\n" + "class C {\n" + "}\n")

        jsonRun := Nlc("check --project " + CcQuoted(directory))
        textRun := Nlc("check --project " + CcQuoted(directory) + " --text")

        // JSON arm: the failure is the envelope on STDOUT, and STDERR stays silent.
        assert jsonRun.ExitCode == 1
        assert jsonRun.Stderr.Trim().Length == 0
        jsonDocument := JsonDocument.Parse(jsonRun.Stdout)
        assert !jsonDocument.RootElement.GetProperty("ok").GetBoolean()
        assert jsonDocument.RootElement.GetProperty("checkedFiles").GetInt32() == 3
        jsonDocument.Dispose()

        // Text arm: the diagnostics are prose on STDERR, so STDOUT stays empty.
        assert textRun.ExitCode == 1
        assert textRun.Stdout.Trim().Length == 0
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a twelve-file import cycle stays bounded and still fails both output modes" {
    directory := CcCheckProject("nsharp-circular-import-long", "LongCircularImports")
    try {
        fileCount := 12
        index := 0
        while index < fileCount {
            current := "F" + CcTwoDigits(index)
            next := "F" + CcTwoDigits((index + 1) % fileCount)
            CcWriteFile(directory, current + ".nl", "import \"" + next + "\"\n" + "\n" + "class " + current + " {\n" + "}\n")
            index = index + 1
        }

        jsonRun := Nlc("check --project " + CcQuoted(directory))
        textRun := Nlc("check --project " + CcQuoted(directory) + " --text")

        assert jsonRun.ExitCode == 1
        assert jsonRun.Stderr.Trim().Length == 0
        jsonDocument := JsonDocument.Parse(jsonRun.Stdout)
        assert !jsonDocument.RootElement.GetProperty("ok").GetBoolean()
        assert jsonDocument.RootElement.GetProperty("checkedFiles").GetInt32() == fileCount
        jsonDocument.Dispose()

        assert textRun.ExitCode == 1
        assert textRun.Stdout.Trim().Length == 0
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ THE EXPORT RULE ACROSS A PACKAGE IMPORT ══════════════════════════════════════════════════
//
// PascalCase exports; camelCase stays inside the declaring package. An explicit `public` modifier
// overrides the casing, and an explicit `private` one overrides it the other way.

test "a package import reaches every PascalCase export and every explicitly public camelCase one" {
    directory := CcCheckProject("nsharp-package-exports", "PackageVisibility")
    try {
        CcWriteFile(
            directory,
            Path.Combine("Models", "Item.nl"),
            "package Models\n" + "\n" + "class Item {\n" + "    func Visible(): string {\n" + "        return \"visible\"\n" + "    }\n" + "}\n" + "\n" + "public class explicitItem {\n" + "    public func visibleExplicit(): string {\n" + "        return \"explicit\"\n" + "    }\n" + "}\n" + "\n" + "func BuildItem(): Item {\n" + "    return new Item()\n" + "}\n" + "\n" + "enum Status {\n" + "    Ready,\n" + "    hidden\n" + "}\n" + "\n" + "public func buildExplicit(): explicitItem {\n" + "    return new explicitItem()\n" + "}\n"
        )
        CcWriteFile(
            directory,
            "Program.nl",
            "import Models\n" + "\n" + "package App\n" + "\n" + "func Main() {\n" + "    item := BuildItem()\n" + "    explicitValue := buildExplicit()\n" + "    print item.Visible()\n" + "    print explicitValue.visibleExplicit()\n" + "    print Status.hidden\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert TextOf(root.GetProperty("command")) == "check"
        assert root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("results").GetArrayLength() == 0
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a package import refuses camelCase types, members, union cases and free functions alike" {
    directory := CcCheckProject("nsharp-package-hidden", "PackageVisibility")
    try {
        CcWriteFile(
            directory,
            Path.Combine("Models", "Item.nl"),
            "package Models\n" + "\n" + "class Item {\n" + "    func hiddenMethod(): string {\n" + "        return \"hidden\"\n" + "    }\n" + "}\n" + "\n" + "private class SecretPascal {\n" + "}\n" + "\n" + "class hiddenThing {\n" + "}\n" + "\n" + "union Outcome {\n" + "    Ok\n" + "    hidden\n" + "}\n" + "\n" + "func hiddenFunction(): string {\n" + "    return \"hidden\"\n" + "}\n"
        )
        CcWriteFile(
            directory,
            "Program.nl",
            "import Models\n" + "\n" + "package App\n" + "\n" + "func Main() {\n" + "    thing := new hiddenThing()\n" + "    secret := new SecretPascal()\n" + "    item := new Item()\n" + "    print item.hiddenMethod()\n" + "    print Outcome.hidden\n" + "    print hiddenFunction()\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()

        // ALL FIVE unreachable names are refused, not merely the first one the binder met: the
        // camelCase class, the explicitly private PascalCase class, the camelCase method, the
        // camelCase union case, and the camelCase free function.
        refusals := CcMessagesForCode(run.Stdout, "NL308")
        assert refusals.Contains("'hiddenThing' is not exported")
        assert refusals.Contains("'SecretPascal' is not exported")
        assert refusals.Contains("'hiddenMethod' is not exported")
        assert refusals.Contains("'hidden' is not exported")
        assert refusals.Contains("'hiddenFunction' is not exported")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a namespace import refuses camelCase types, members, union cases and free functions alike" {
    directory := CcCheckProject("nsharp-namespace-hidden", "NamespaceVisibility")
    try {
        CcWriteFile(
            directory,
            Path.Combine("Models", "Item.nl"),
            "namespace Models\n" + "\n" + "class Item {\n" + "    func hiddenMethod(): string {\n" + "        return \"hidden\"\n" + "    }\n" + "}\n" + "\n" + "private class SecretPascal {\n" + "}\n" + "\n" + "class hiddenThing {\n" + "}\n" + "\n" + "enum Status {\n" + "    Ready,\n" + "    hidden\n" + "}\n" + "\n" + "union Outcome {\n" + "    Ok\n" + "    hidden\n" + "}\n" + "\n" + "func hiddenFunction(): string {\n" + "    return \"hidden\"\n" + "}\n"
        )
        CcWriteFile(
            directory,
            "Program.nl",
            "namespace App\n" + "\n" + "import Models\n" + "\n" + "func Main() {\n" + "    thing := new hiddenThing()\n" + "    secret := new SecretPascal()\n" + "    item := new Item()\n" + "    print item.hiddenMethod()\n" + "    print Outcome.hidden\n" + "    print hiddenFunction()\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()

        // The NAMESPACE arm refuses exactly what the PACKAGE arm refuses — the two import forms
        // share one export rule.
        refusals := CcMessagesForCode(run.Stdout, "NL308")
        assert refusals.Contains("'hiddenThing' is not exported")
        assert refusals.Contains("'SecretPascal' is not exported")
        assert refusals.Contains("'hiddenMethod' is not exported")
        assert refusals.Contains("'hidden' is not exported")
        assert refusals.Contains("'hiddenFunction' is not exported")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "an inaccessible member is NL308 on the MEMBER name, not on the receiver or the whole call" {
    directory := CcCheckProject("nsharp-nl308-span", "InaccessibleSpan")
    try {
        CcWriteFile(
            directory,
            Path.Combine("Models", "Widget.nl"),
            "package Models\n" + "\n" + "class Widget {\n" + "    func secretMethod(): string {\n" + "        return \"x\"\n" + "    }\n" + "}\n"
        )
        CcWriteFile(
            directory,
            "Program.nl",
            "import \"Models/Widget\"\n" + "\n" + "package App\n" + "\n" + "func Main() {\n" + "    w := new Widget()\n" + "    print w.secretMethod()\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert !root.GetProperty("ok").GetBoolean()

        // ONE diagnostic, and its span covers `secretMethod` exactly — line 7, column 13, twelve
        // characters — which is the member name and nothing else.
        assert CcDiagnosticCodes(run.Stdout) == "NL308"
        only := ElementAt(root.GetProperty("results"), 0)
        assert TextOf(only.GetProperty("file")) == "Program.nl"
        assert only.GetProperty("line").GetInt32() == 7
        assert only.GetProperty("column").GetInt32() == 13
        assert only.GetProperty("length").GetInt32() == 12
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ A DUPLICATE NAME IN TWO PACKAGES ═════════════════════════════════════════════════════════
//
// Two packages each declare `Item`. Only one is imported, so the import must WIN rather than the
// project-wide duplicate turning into an ambiguity refusal.

test "an imported package's export beats a same-named symbol in a package that was not imported" {
    directory := CcCheckProject("nsharp-package-duplicate-export", "PackageVisibility")
    try {
        CcWriteFile(directory, Path.Combine("Models", "Item.nl"), "package Models\n" + "\n" + "class Item {\n" + "}\n")
        CcWriteFile(directory, Path.Combine("Other", "Item.nl"), "package Other\n" + "\n" + "class Item {\n" + "}\n")
        CcWriteFile(
            directory,
            "Program.nl",
            "import Models\n" + "\n" + "package App\n" + "\n" + "func Main() {\n" + "    _item := new Item()\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("results").GetArrayLength() == 0
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "when both duplicates are unexported the answer is the export refusal, never an ambiguity" {
    directory := CcCheckProject("nsharp-package-duplicate-hidden", "PackageVisibility")
    try {
        CcWriteFile(directory, Path.Combine("Models", "Item.nl"), "package Models\n" + "\n" + "class hiddenThing {\n" + "}\n")
        CcWriteFile(directory, Path.Combine("Other", "Item.nl"), "package Other\n" + "\n" + "class hiddenThing {\n" + "}\n")
        CcWriteFile(
            directory,
            "Program.nl",
            "import Models\n" + "\n" + "package App\n" + "\n" + "func Main() {\n" + "    thing := new hiddenThing()\n" + "}\n"
        )

        run := Nlc("check --project " + CcQuoted(directory))

        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0
        document := JsonDocument.Parse(run.Stdout)
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()

        // The diagnostic names the IMPORTED package as the one that does not export the name.
        refusal := CcMessagesForCode(run.Stdout, "NL308")
        assert refusal.Contains("'hiddenThing' is not exported from package/namespace 'Models'")
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ --use-built-references: A `project:` DEPENDENCY READ FROM ITS OWN BUILD ═══════════════════

func CcBuiltReferencePair(directory: string) {
    Directory.CreateDirectory(Path.Combine(directory, "Lib"))
    Directory.CreateDirectory(Path.Combine(directory, "App"))
    File.WriteAllText(Path.Combine(Path.Combine(directory, "Lib"), "project.yml"), "name: CcBuiltLib\noutputType: library\ntargetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(Path.Combine(directory, "Lib"), "Lib.nl"), "namespace CcBuilt\n\nfunc LibValue(): int {\n    return 41\n}\n")
    File.WriteAllText(Path.Combine(Path.Combine(directory, "App"), "project.yml"), "name: CcBuiltApp\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Lib/project.yml\n")
    File.WriteAllText(Path.Combine(Path.Combine(directory, "App"), "App.nl"), "namespace CcBuilt\n\nfunc AppValue(): int {\n    return LibValue() + 1\n}\n")
}

test "nlc check --use-built-references reads a project dependency from the assembly its build wrote, and refuses a missing or stale one by name" {
    directory := NewTempDirectory("nsharp-check-built-references")
    try {
        CcBuiltReferencePair(directory)
        app := Path.Combine(directory, "App")
        libYml := Path.Combine(Path.Combine(directory, "Lib"), "project.yml")
        libDll := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "Lib"), "bin"), "Debug"), "net10.0"), "CcBuiltLib.dll")

        // Never built: the envelope names the dependency and the assembly it looked for.
        missing := Nlc("check --use-built-references --project " + CcQuoted(app))
        assert missing.ExitCode == 1, missing.Stdout
        missingDocument := JsonDocument.Parse(missing.Stdout)
        missingMessage := TextOf(missingDocument.RootElement.GetProperty("error").GetProperty("message"))
        missingDocument.Dispose()
        assert missingMessage.Contains(libYml + "' has no built assembly at '" + libDll + "'"), missingMessage
        assert !File.Exists(libDll), "The check must not have built the dependency itself."

        // Built by its own `nlc build`: the check reads it and writes nothing.
        build := Nlc("build --project " + CcQuoted(Path.Combine(directory, "Lib")))
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        builtAt := File.GetLastWriteTimeUtc(libDll)
        File.SetLastWriteTimeUtc(Path.Combine(Path.Combine(directory, "Lib"), "Lib.nl"), builtAt.AddMinutes(-1))
        File.SetLastWriteTimeUtc(libYml, builtAt.AddMinutes(-1))
        clean := Nlc("check --use-built-references --project " + CcQuoted(app))
        assert clean.ExitCode == 0, clean.Stdout
        cleanDocument := JsonDocument.Parse(clean.Stdout)
        assert cleanDocument.RootElement.GetProperty("ok").GetBoolean()
        assert cleanDocument.RootElement.GetProperty("checkedFiles").GetInt32() == 1
        cleanDocument.Dispose()
        assert File.GetLastWriteTimeUtc(libDll) == builtAt

        // A source edited after the build: refused, in both output modes, naming the newer file.
        libSource := Path.Combine(Path.Combine(directory, "Lib"), "Lib.nl")
        File.SetLastWriteTimeUtc(libSource, builtAt.AddMinutes(1))
        stale := Nlc("check --use-built-references --project " + CcQuoted(app) + " --text")
        assert stale.ExitCode == 1
        assert stale.Stderr.Contains(libYml + "' is out of date: '" + libSource + "' is newer than its built assembly"), stale.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}
