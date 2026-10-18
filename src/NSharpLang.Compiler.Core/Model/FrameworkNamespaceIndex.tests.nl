namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Runtime.InteropServices

// THE CONTRACT FOR WHAT `Microsoft.NETCore.App` LETS A PROJECT NAME (`FrameworkNamespaceIndex`).
//
// The pure half -- the reference pack's list, the fallback without one, the namespace map -- is
// asserted on literals. The host half is asserted against the runtime these tests run on, which is
// the runtime the compiler's analyzer resolves from, so the issue #215 namespaces are pinned where
// they actually matter.

func FniRows(): List<FrameworkNamespaceRow> {
    return new List<FrameworkNamespaceRow>()
}

func FniNames(values: string[]): HashSet<string> {
    return new HashSet<string>(values, StringComparer.OrdinalIgnoreCase)
}

test "the reference pack's compile surface is its Managed rows, not its analyzers" {
    xml := "<FileList FrameworkName=\"Microsoft.NETCore.App\">\n" +
        "  <File Type=\"Analyzer\" Path=\"analyzers/dotnet/cs/System.Text.Json.SourceGeneration.dll\" AssemblyName=\"System.Text.Json.SourceGeneration\" />\n" +
        "  <File Type=\"Managed\" Path=\"ref/net10.0/System.Runtime.dll\" AssemblyName=\"System.Runtime\" />\n" +
        "  <File Type=\"Managed\" Path=\"ref/net10.0/System.Security.Claims.dll\" AssemblyName=\"System.Security.Claims\" />\n" +
        "</FileList>\n"
    names := FrameworkNamespaceIndex.ParseFrameworkListAssemblyNames(xml)
    assert names.Count == 2
    assert names.Contains("System.Runtime")
    assert names.Contains("system.security.claims")
    assert !names.Contains("System.Text.Json.SourceGeneration")
}

test "without a reference pack the runtime directory minus System.Private.* is the compile surface" {
    names := FrameworkNamespaceIndex.RuntimeCompileAssemblyNames(["System.Runtime", "System.Private.CoreLib", "System.Private.Xml", "System.Xml.ReaderWriter"])
    assert names.Count == 2
    assert names.Contains("System.Runtime")
    assert names.Contains("System.Xml.ReaderWriter")
}

test "a namespace is importable through a compile-surface assembly and loads the assemblies that define it" {
    rows := FniRows()
    rows.Add(new FrameworkNamespaceRow("System.Xml.ReaderWriter", "System.Xml", false))
    rows.Add(new FrameworkNamespaceRow("System.Private.Xml", "System.Xml", true))
    rows.Add(new FrameworkNamespaceRow("System.Private.CoreLib", "Internal", true))
    rows.Add(new FrameworkNamespaceRow("System.Security.Claims", "System.Security.Claims", true))
    rows.Add(new FrameworkNamespaceRow("System.ComponentModel", "System", true))
    rows.Add(new FrameworkNamespaceRow("System.Console", "System", true))
    map := FrameworkNamespaceIndex.BuildNamespaceMap(rows, FniNames(["System.Xml.ReaderWriter", "System.Security.Claims", "System.ComponentModel", "System.Console"]))

    assert string.Join("|", map["System.Xml"]) == "System.Private.Xml"
    assert string.Join("|", map["System.Security.Claims"]) == "System.Security.Claims"
    // Ordinal by assembly name, whatever order the directory listed them in.
    assert string.Join("|", map["System"]) == "System.ComponentModel|System.Console"
    // Carried only by an implementation assembly, so not a namespace a program can import.
    assert !map.ContainsKey("Internal")
}

test "a fully-qualified spelling answers its longest framework-namespace prefix" {
    namespaces := new Dictionary<string, string[]>(StringComparer.Ordinal)
    namespaces["System"] = ["System.Private.CoreLib"]
    namespaces["System.Numerics"] = ["System.Runtime.Numerics"]
    index := new FrameworkNamespaceIndex("/runtime", "", FniNames(["System.Runtime"]), namespaces)
    assert index.NamespaceOfTypeName("System.Numerics.BigInteger") == "System.Numerics"
    assert index.NamespaceOfTypeName("System.Environment.SpecialFolder") == "System"
    assert index.NamespaceOfTypeName("Contoso.Orders.Order") == null
    assert index.NamespaceOfTypeName("BigInteger") == null
}

test "the reference pack of the runtime's own version is preferred, then the highest of its major" {
    assert FrameworkNamespaceIndex.SelectReferencePackVersion(["10.0.5", "10.0.7", "9.0.3"], "10.0.7") == 1
    assert FrameworkNamespaceIndex.SelectReferencePackVersion(["9.0.3", "10.0.5", "10.0.2"], "10.0.7") == 1
    assert FrameworkNamespaceIndex.SelectReferencePackVersion(new string[](0), "10.0.7") == -1
}

test "the reference pack root sits beside shared/ under the dotnet root" {
    runtime := Path.Combine(Path.Combine(Path.Combine(Path.Combine("/opt", "dotnet"), "shared"), "Microsoft.NETCore.App"), "10.0.7")
    expected := Path.Combine(Path.Combine(Path.Combine("/opt", "dotnet"), "packs"), "Microsoft.NETCore.App.Ref")
    assert FrameworkNamespaceIndex.ReferencePackRoot(runtime) == expected
    assert FrameworkNamespaceIndex.ReferencePackRoot(Path.Combine(Path.Combine("/opt", "app"), "bin")) == null
}

// ── the host runtime: issue #215's namespaces are the framework's ─────────────────────────────

test "the host index answers every namespace issue #215 found missing" {
    index := FrameworkNamespaceIndex.ForHostRuntime()
    assert index.CompileAssemblyNames.Contains("System.Runtime")
    assert !index.CompileAssemblyNames.Contains("System.Private.CoreLib")

    expectations := new Dictionary<string, string>(StringComparer.Ordinal)
    expectations["System"] = "System.ComponentModel"
    expectations["System.Security.Claims"] = "System.Security.Claims"
    expectations["System.Xml"] = "System.Private.Xml"
    expectations["System.Numerics"] = "System.Runtime.Numerics"
    expectations["System.Collections.Immutable"] = "System.Collections.Immutable"
    expectations["System.Threading.Channels"] = "System.Threading.Channels"
    expectations["System.Diagnostics.Metrics"] = "System.Diagnostics.DiagnosticSource"
    expectations["System.ComponentModel"] = "System.ComponentModel.TypeConverter"
    expectations["System.Data"] = "System.Data.Common"
    for expectation in expectations {
        assemblies := index.AssembliesForNamespace(expectation.Key)
        assert assemblies != null, expectation.Key + " is not a framework namespace"
        assert Array.IndexOf(assemblies, expectation.Value) >= 0, expectation.Key + " does not load " + expectation.Value
    }
}

test "the host index is read once per runtime directory" {
    first := FrameworkNamespaceIndex.ForHostRuntime()
    second := FrameworkNamespaceIndex.ForRuntimeDirectory(RuntimeEnvironment.GetRuntimeDirectory())
    assert Object.ReferenceEquals(first, second)
}
