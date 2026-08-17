namespace NSharpLang.DocQuery.Tests

import System
import System.Collections
import System.Diagnostics
import System.IO
import System.Reflection
import System.Text.Json

// THE CANONICAL CONTRACTS FOR `nlc query doc`, IN N#.
//
// These replace `tests/DocQueryTests.cs`, which was the last canonical C# assertion layer over a
// surface that is otherwise entirely N# (`DocQuery.nl`). Every one of its 30 assertions has a named
// successor here. Five declarations report ELEVEN cases, because three of them are TABLE-DRIVEN:
// one declaration, one row per case, and one INDEPENDENT reported test per row — so a single bad
// row names itself instead of hiding inside a loop.
//
// The production type is reached BY REFLECTION, the same way `tests/native/query-completions` and
// `tests/native/extension-calls` reach theirs: this project runs through `nlc test`, so the
// compiler that built it is the compiler under test, and reflection keeps the asserts independent
// of assembly identity across load contexts.

func SetDocQueryObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// A production `DocQuery` with the reference-pack seed assemblies loaded — `new DocQuery()` plus
// `LoadSystemAssemblies()`, which is exactly what `QueryCommand` does before it answers anything.
func NewLoadedDocQuery(): object {
    docQueryType := Type.GetType("NSharpLang.Compiler.CodeIntelligence.DocQuery, NSharpLang.Compiler.BootstrapServices")
    if docQueryType == null {
        throw new InvalidOperationException("The production doc-query type was not loadable.")
    }

    docQueryConstructor := docQueryType.GetConstructor(new Type[](0))
    if docQueryConstructor == null {
        throw new InvalidOperationException("The production doc-query type was not constructible.")
    }

    docQuery := docQueryConstructor.Invoke(new object?[](0))
    loadMethod := docQueryType.GetMethod("LoadSystemAssemblies", new Type[](0))
    if loadMethod == null {
        throw new InvalidOperationException("The production seed-assembly loader was not found.")
    }

    loadArguments := new object?[](0)
    loaded := loadMethod.Invoke(docQuery, loadArguments)
    if loaded != null {
        throw new InvalidOperationException("The production seed-assembly loader answered a value.")
    }

    return docQuery
}

// `DocQuery.Lookup(query)` — the one entry point `nlc query doc` calls.
func DocQueryLookup(docQuery: object, query: string): object? {
    lookupParameterTypes := new Type[](1)
    lookupParameterTypes[0] = typeof(string)
    lookupMethod := docQuery.GetType().GetMethod("Lookup", lookupParameterTypes)
    if lookupMethod == null {
        throw new InvalidOperationException("The production doc-query lookup entry point was not found.")
    }

    lookupArguments := new object?[](1)
    SetDocQueryObject(lookupArguments, 0, query)
    return lookupMethod.Invoke(docQuery, lookupArguments)
}

// One lookup, seeded and answered. Every table row starts here.
func LookupDoc(query: string): object? {
    return DocQueryLookup(NewLoadedDocQuery(), query)
}

// One named member of a production doc record, read as a property OR as a field — an N# record's
// positional members are not required to be one or the other, and this cluster asserts about the
// VALUES, not about the shape the emitter chose for them.
func DocProperty(owner: object, propertyName: string): object? {
    ownerType := owner.GetType()
    ownerProperty := ownerType.GetProperty(propertyName)
    if ownerProperty != null {
        return ownerProperty.GetValue(owner)
    }

    ownerField := ownerType.GetField(propertyName)
    if ownerField != null {
        return ownerField.GetValue(owner)
    }

    throw new InvalidOperationException("The production doc result has no " + propertyName + " member.")
}


func DocTextOf(value: object): string {
    text := value.ToString()
    if text == null {
        return ""
    }

    return text ?? ""
}

// A named string property, or "" when it is absent or null — the shape every
// `string.IsNullOrWhiteSpace` assertion in the C# cluster was really testing.
func DocText(owner: object, propertyName: string): string {
    value := DocProperty(owner, propertyName)
    if value != null {
        return DocTextOf(value)
    }

    return ""
}

func IsBlank(text: string): bool {
    return text.Trim().Length == 0
}

// The members array of a doc result, walked by reflection because its element type lives in the
// assembly under test.
func DocMemberCount(result: object): int {
    members := DocProperty(result, "Members")
    if members == null {
        return 0
    }

    memberArray := members as IList
    if memberArray == null {
        return 0
    }

    return memberArray.Count
}

func DocMemberAt(result: object, index: int): object {
    members := DocProperty(result, "Members")
    if members == null {
        throw new InvalidOperationException("The production doc result exposed no members.")
    }

    memberArray := members as IList
    if memberArray == null {
        throw new InvalidOperationException("The production doc result members were not an array.")
    }

    member := memberArray[index]
    if member != null {
        return member
    }

    throw new InvalidOperationException("The production doc result held a null member.")
}

// True when the result lists a member with exactly this kind and this name.
func HasDocMember(result: object, memberKind: string, memberName: string): bool {
    total := DocMemberCount(result)
    i := 0
    while i < total {
        member := DocMemberAt(result, i)
        if DocText(member, "Kind") == memberKind && DocText(member, "Name") == memberName {
            return true
        }

        i = i + 1
    }

    return false
}

func DocParameterCount(result: object): int {
    parameters := DocProperty(result, "Parameters")
    if parameters == null {
        return 0
    }

    parameterArray := parameters as IList
    if parameterArray == null {
        return 0
    }

    return parameterArray.Count
}

func DocParameterAt(result: object, index: int): object {
    parameters := DocProperty(result, "Parameters")
    if parameters == null {
        throw new InvalidOperationException("The production doc result exposed no parameters.")
    }

    parameterArray := parameters as IList
    if parameterArray == null {
        throw new InvalidOperationException("The production doc result parameters were not an array.")
    }

    parameter := parameterArray[index]
    if parameter != null {
        return parameter
    }

    throw new InvalidOperationException("The production doc result held a null parameter.")
}

// The built product CLI above this test tree. The CLI runs on Microsoft.NETCore.App ONLY, so the
// reference packs offer it assembly names its own runtime cannot load — the environment that used
// to crash `nlc query doc` outright, and the one the ASP.NET-enabled xUnit host can never
// reproduce. Running the built `Cli.dll` under its own runtimeconfig reproduces it exactly.
func FindCliDll(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        hostDll := Path.Combine(directory, "Cli.dll")
        if File.Exists(hostDll) {
            return hostDll
        }

        buildRoot := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
        buildDll := Path.Combine(buildRoot, "Cli.dll")
        if File.Exists(buildDll) {
            return buildDll
        }

        current = Path.GetDirectoryName(directory)
    }

    throw new InvalidOperationException("Could not locate the built N# CLI above this test tree.")
}

// The `error.message` a doc-query envelope carries, DECODED — the CLI escapes apostrophes as
// `\u0027` on the wire, so only the decoded string can be asserted against the sentence a human
// reads.
func QueryDocErrorMessage(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    errorElement := new JsonElement()
    if root.TryGetProperty("error", out errorElement) {
        messageElement := new JsonElement()
        if errorElement.TryGetProperty("message", out messageElement) {
            text := messageElement.GetString()
            document.Dispose()
            if text != null {
                return text ?? ""
            }

            return ""
        }
    }

    document.Dispose()
    return ""
}

class CliRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

// `dotnet <Cli.dll> query doc <name>` from a directory that is not the repository, so the run sees
// only its own runtime.
func RunQueryDoc(name: string): CliRun {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: "\"" + FindCliDll() + "\" query doc " + name }
    startInfo.WorkingDirectory = Path.GetTempPath()
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdout := process.StandardOutput.ReadToEnd()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    return new CliRun(exitCode, stdout, stderr)
}

// ---------------------------------------------------------------------------------------------
// THE CONTRACTS.
// ---------------------------------------------------------------------------------------------

// Successor to Lookup_Console_LoadsXmlDocsFromReferencePacks,
// Lookup_EnvironmentSpecialFolder_ResolvesNestedType and
// Lookup_Regex_FindsAssembliesOutsideHardcodedSeedList. Console proves the reference-pack XML is
// read at all; the nested `Environment.SpecialFolder` proves a dotted name resolves to a NESTED
// type rather than a member; `Regex` proves the search reaches assemblies outside the hard-coded
// seed list. Each row also pins the KIND, which the C# asserted only for the enum.
test "doc lookup resolves a documented type" with (query: string, fullName: string, kind: string) [
    ("Console", "System.Console", "static class"),
    ("Environment.SpecialFolder", "System.Environment.SpecialFolder", "enum"),
    ("Regex", "System.Text.RegularExpressions.Regex", "class")
] {
    result := LookupDoc(query)
    assert result != null
    if result != null {
        assert DocText(result, "FullName") == fullName
        assert DocText(result, "Kind") == kind
        assert !IsBlank(DocText(result, "Summary"))
    }
}

// Successor to Lookup_List_And_Process_ExposeConstructorsAndEvents and
// Lookup_Environment_ListsNestedTypes. The C# asserted "some member of this kind exists" for the
// constructor and "this exact named member of this kind exists" for the rest; every row here pins
// the exact name, so each row is at least as strong as the assertion it replaces.
test "doc lookup lists a member" with (query: string, memberKind: string, memberName: string) [
    ("List", "constructor", "List()"),
    ("List", "method", "Add"),
    ("Process", "event", "Exited"),
    ("Environment", "nested type", "SpecialFolder")
] {
    result := LookupDoc(query)
    assert result != null
    if result != null {
        assert HasDocMember(result, memberKind, memberName)
    }
}

// Successor to Lookup_ListAdd_UsesGenericDocIdsForParameters. Not table-shaped: it is the only
// assertion in the cluster about the PARAMETER projection, and about the whitespace hygiene of the
// text the XML `<see>`/`<paramref>` elements are flattened into.
test "doc lookup describes a generic method's parameters" {
    result := LookupDoc("List.Add")
    assert result != null
    if result != null {
        kind := DocText(result, "Kind")
        assert kind.StartsWith("method", StringComparison.Ordinal)
        summary := DocText(result, "Summary")
        assert !IsBlank(summary)
        assert summary.IndexOf(" end of the .", StringComparison.Ordinal) < 0

        assert DocParameterCount(result) == 1
        item := DocParameterAt(result, 0)
        assert DocText(item, "Name") == "item"
        assert DocText(item, "Type") == "T"
        itemSummary := DocText(item, "Summary")
        assert !IsBlank(itemSummary)
        assert itemSummary.IndexOf(" can be  ", StringComparison.Ordinal) < 0
    }
}

// Successor to QueryDoc_InTheCliRuntime_SkipsUnloadablePackAssemblies_AndExplainsTheMiss, first
// half: a name the runtime CAN document is answered, and the envelope says so.
test "the CLI runtime answers a doc query it can document" {
    run := RunQueryDoc("Console")
    assert run.ExitCode == 0, run.Stderr
    assert run.Stdout.IndexOf("\"ok\": true", StringComparison.Ordinal) >= 0, run.Stdout
}

// Successor to the same test's second half: a name the reference packs document but this runtime
// cannot LOAD exits 1 and EXPLAINS itself — it names the assembly the documentation lives in and
// says that assembly is not part of this runtime, rather than crashing on the unloadable pack
// assembly the way it once did. One row per sentence the explanation must carry.
test "the CLI runtime explains a doc query it cannot document" with (fragment: string) [
    ("No documentation found for 'HttpLoggingOptions'."),
    ("(assembly 'Microsoft.AspNetCore.HttpLogging'), but that assembly is not part of this runtime")
] {
    run := RunQueryDoc("HttpLoggingOptions")
    assert run.ExitCode == 1, run.Stderr
    assert run.Stdout.IndexOf("\"ok\": false", StringComparison.Ordinal) >= 0, run.Stdout
    message := QueryDocErrorMessage(run.Stdout)
    assert message.IndexOf(fragment, StringComparison.Ordinal) >= 0, message
}
