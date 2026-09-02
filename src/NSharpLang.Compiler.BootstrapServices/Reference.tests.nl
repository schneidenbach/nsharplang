namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR A SINGLE DEPENDENCY ROW (020 slice 15).
//
// These came out of `tests/ProjectFileTests.cs`, which is deleted. That file asked three questions
// of this type: the four `Value` spellings, the four `Type` spellings, and that an empty row throws
// from both.
//
// THE TWO THROWS WERE STATED AS TYPES AND ARE NOW STATED AS SENTENCES — and they are DIFFERENT
// sentences, which `Assert.Throws<InvalidOperationException>` twice in a row could not say.
//
// AND `Validate` HAD NO DIRECT COVERAGE AT ALL. It is the method that decides whether `nlc build`
// stops with "DLL not found: …" or hands a missing path to the assembly loader, and every C#
// assertion reached it only through a `ProjectFileParser.Parse` that happened to succeed. Its four
// arms, the two path shapes each of the disk-backed arms accepts, and the three "must have a
// value" refusals are below.
func RfcTypeName(reference: Reference): string {
    try {
        kind := reference.Type
        if kind == ReferenceType.NuGet {
            return "nuget"
        }
        if kind == ReferenceType.Dll {
            return "dll"
        }
        if kind == ReferenceType.Project {
            return "project"
        }

        return "framework"
    } catch ex: Exception {
        return "<throws>" + ex.Message
    }
}

func RfcValue(reference: Reference): string {
    try {
        return reference.Value
    } catch ex: Exception {
        return "<throws>" + ex.Message
    }
}

func RfcValidate(reference: Reference, projectDirectory: string): string {
    try {
        reference.Validate(projectDirectory)
        return "<accepted>"
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

func RfcTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

// ── the four kinds ────────────────────────────────────────────────────────────────────────────

test "each of the four reference kinds answers its own Type and its own Value" {
    nugetReference := new Reference { Nuget: "TestPackage" }
    assert RfcTypeName(nugetReference) == "nuget"
    assert RfcValue(nugetReference) == "TestPackage"
    assert nugetReference.HasValue

    dllReference := new Reference { Dll: "test.dll" }
    assert RfcTypeName(dllReference) == "dll"
    assert RfcValue(dllReference) == "test.dll"
    assert dllReference.HasValue

    projectReference := new Reference { Project: "test.csproj" }
    assert RfcTypeName(projectReference) == "project"
    assert RfcValue(projectReference) == "test.csproj"
    assert projectReference.HasValue

    frameworkReference := new Reference { Framework: "Microsoft.AspNetCore.App" }
    assert RfcTypeName(frameworkReference) == "framework"
    assert RfcValue(frameworkReference) == "Microsoft.AspNetCore.App"
    assert frameworkReference.HasValue

    // The kind does not depend on the NAME, which the deleted file said by asking the same question
    // of a second spelling. Both spellings are kept.
    plainNuget := new Reference { Nuget: "Test" }
    assert RfcTypeName(plainNuget) == "nuget"
    plainFramework := new Reference { Framework: "Test" }
    assert RfcTypeName(plainFramework) == "framework"
    plainDll := new Reference { Dll: "test.dll" }
    assert RfcTypeName(plainDll) == "dll"
    plainProject := new Reference { Project: "test.csproj" }
    assert RfcTypeName(plainProject) == "project"
}

test "AN EMPTY ROW REFUSES BOTH QUESTIONS, WITH TWO DIFFERENT SENTENCES" {
    empty := new Reference()
    assert RfcTypeName(empty) == "<throws>Reference must specify one of: nuget, dll, project, or framework"
    assert RfcValue(empty) == "<throws>Invalid reference"
    assert empty.HasValue == false
}

test "the kind is decided by the FIRST field that is set, in the order nuget, dll, project, framework" {
    // A row that names two kinds is a document a user can write and nothing said what it means.
    // The order is the order `GetReferenceType` reads the fields in, and `Value` reads them in the
    // SAME order — which is what stops a row from reporting one kind and the other one's value.
    both := new Reference { Nuget: "Dapper", Dll: "Dapper.dll" }
    assert RfcTypeName(both) == "nuget"
    assert RfcValue(both) == "Dapper"

    dllOverProject := new Reference { Dll: "a.dll", Project: "b.csproj" }
    assert RfcTypeName(dllOverProject) == "dll"
    assert RfcValue(dllOverProject) == "a.dll"

    projectOverFramework := new Reference { Project: "b.csproj", Framework: "Microsoft.AspNetCore.App" }
    assert RfcTypeName(projectOverFramework) == "project"
    assert RfcValue(projectOverFramework) == "b.csproj"
}

test "HasValue is what drops a row, and an EMPTY spelling is not a value" {
    // This is the predicate `ProjectFileParser.FilterReferences` uses. An empty or whitespace-only
    // field still SETS the field, so `Type` answers a kind while `HasValue` answers false — the
    // exact pair that makes the filter necessary.
    blank := new Reference { Nuget: "" }
    assert blank.HasValue == false
    assert RfcTypeName(blank) == "nuget"

    whitespace := new Reference { Dll: "   " }
    assert whitespace.HasValue == false
    assert RfcTypeName(whitespace) == "dll"

    real := new Reference { Framework: "Microsoft.AspNetCore.App" }
    assert real.HasValue
}

// ── validation against the disk ───────────────────────────────────────────────────────────────

test "a nuget row is accepted without touching the disk, and an empty one is refused" {
    directory := RfcTempDirectory("nuget")
    assert RfcValidate(new Reference { Nuget: "Dapper" }, directory) == "<accepted>"
    assert RfcValidate(new Reference { Nuget: "   " }, directory) == "InvalidOperationException|NuGet reference must have a package name"
    Directory.Delete(directory, true)
}

test "a framework row is accepted without touching the disk, and an empty one is refused" {
    directory := RfcTempDirectory("framework")
    assert RfcValidate(new Reference { Framework: "Microsoft.AspNetCore.App" }, directory) == "<accepted>"
    assert RfcValidate(new Reference { Framework: "   " }, directory) == "InvalidOperationException|Framework reference must have a name"
    Directory.Delete(directory, true)
}

test "A DLL ROW IS RESOLVED AGAINST THE PROJECT DIRECTORY UNLESS IT IS ALREADY ROOTED" {
    directory := RfcTempDirectory("dll")
    relativeDll := Path.Combine(directory, "MyLibrary.dll")

    // Missing: the sentence names the value the user wrote AND the path it resolved to.
    assert RfcValidate(new Reference { Dll: "MyLibrary.dll" }, directory) == "FileNotFoundException|DLL not found: MyLibrary.dll (resolved to " + relativeDll + ")"

    File.WriteAllText(relativeDll, "dummy")
    assert RfcValidate(new Reference { Dll: "MyLibrary.dll" }, directory) == "<accepted>"

    // An already-rooted path is NOT re-rooted, which is what makes an absolute reference outside
    // the project work at all.
    assert RfcValidate(new Reference { Dll: relativeDll }, directory) == "<accepted>"

    elsewhere := RfcTempDirectory("dll-elsewhere")
    assert RfcValidate(new Reference { Dll: relativeDll }, elsewhere) == "<accepted>"
    assert RfcValidate(new Reference { Dll: "   " }, directory) == "InvalidOperationException|DLL reference must have a path"

    Directory.Delete(elsewhere, true)
    Directory.Delete(directory, true)
}

test "a project row is resolved the same way, and refuses with its own sentence" {
    directory := RfcTempDirectory("project")
    nested := Path.Combine(directory, "Shared")
    Directory.CreateDirectory(nested)
    csproj := Path.Combine(nested, "Shared.csproj")
    resolved := Path.Combine(directory, "Shared/Shared.csproj")

    assert RfcValidate(new Reference { Project: "Shared/Shared.csproj" }, directory) == "FileNotFoundException|Project file not found: Shared/Shared.csproj (resolved to " + resolved + ")"

    File.WriteAllText(csproj, "<Project />")
    assert RfcValidate(new Reference { Project: "Shared/Shared.csproj" }, directory) == "<accepted>"
    assert RfcValidate(new Reference { Project: csproj }, directory) == "<accepted>"
    assert RfcValidate(new Reference { Project: "   " }, directory) == "InvalidOperationException|Project reference must have a path"

    Directory.Delete(directory, true)
}

test "an empty row refuses validation before it can refuse anything else" {
    directory := RfcTempDirectory("empty")
    assert RfcValidate(new Reference(), directory) == "InvalidOperationException|Reference must specify one of: nuget, dll, project, or framework"
    Directory.Delete(directory, true)
}
