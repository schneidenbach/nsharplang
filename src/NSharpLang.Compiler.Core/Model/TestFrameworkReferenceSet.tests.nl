namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Cli


// THE SET IS ONE OWNER OR IT IS THREE ANSWERS.
//
// `nlc test` resolved the test framework from the emit host, `nlc check` asked the analyzer to load
// the package id as if it were an assembly, and the language server never asked. The observable was
// an attribute deriving from `FactAttribute` that bound in a build and did not bind in the editor,
// plus a warning naming a package that has no assembly to be unreadable.
func ReferenceSetAssemblyNames(rows: List<TestFrameworkAssemblyRow>): string {
    rendered := ""
    index := 0
    while index < rows.Count {
        rendered = rendered + rows[index].AssemblyName + "@" + rows[index].PackageId + ";"
        index = index + 1
    }

    return rendered
}

test "the framework name normalizes to xunit unless nunit is spelled" {
    assert TestFrameworkReferenceSet.NormalizeFrameworkName(null) == "xunit"
    assert TestFrameworkReferenceSet.NormalizeFrameworkName("") == "xunit"
    assert TestFrameworkReferenceSet.NormalizeFrameworkName("xunit") == "xunit"
    assert TestFrameworkReferenceSet.NormalizeFrameworkName("NUnit") == "nunit"
    assert TestFrameworkReferenceSet.NormalizeFrameworkName("nunit") == "nunit"

    // Anything unrecognised is xunit, which is the default `ProjectConfig.TestFramework` returns and
    // the default the SDK's `NSharpTestFramework` carries.
    assert TestFrameworkReferenceSet.NormalizeFrameworkName("mstest") == "xunit"
    assert TestFrameworkReferenceSet.IsNUnit("NUNIT")
    assert !TestFrameworkReferenceSet.IsNUnit("xunit")
}

test "the restore row is the package a project depends on, and it is a metapackage for xunit" {
    assert TestFrameworkReferenceSet.FrameworkPackageId(null) == "xunit"
    assert TestFrameworkReferenceSet.FrameworkPackageVersion(null) == "2.9.2"
    assert TestFrameworkReferenceSet.FrameworkPackageId("nunit") == "NUnit"
    assert TestFrameworkReferenceSet.FrameworkPackageVersion("nunit") == "4.3.2"

    // THE PACKAGE IS NEVER AN ASSEMBLY. This is the whole finding: `xunit` restores fine and ships
    // no dll, so the moment anything treats the restore row as a load request it manufactures a
    // failure about a file that was never supposed to exist.
    assert !TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunit")
    assert !TestFrameworkReferenceSet.IsFrameworkAssemblyName("NUnit")
}

test "a declared test dependency is recognised as the framework package case-insensitively" {
    assert TestFrameworkReferenceSet.IsFrameworkPackageId("xunit", null)
    assert TestFrameworkReferenceSet.IsFrameworkPackageId("XUnit", "xunit")
    assert !TestFrameworkReferenceSet.IsFrameworkPackageId("xunit.core", "xunit")
    assert !TestFrameworkReferenceSet.IsFrameworkPackageId("FluentAssertions", "xunit")

    // A project on nunit does not treat `xunit` as its framework package, and vice versa.
    assert TestFrameworkReferenceSet.IsFrameworkPackageId("nunit", "nunit")
    assert !TestFrameworkReferenceSet.IsFrameworkPackageId("xunit", "nunit")
}

test "the compile set names assemblies that exist, each with the package that actually ships it" {
    xunit := TestFrameworkReferenceSet.CompileAssemblies("xunit")

    assert ReferenceSetAssemblyNames(xunit) == "xunit.core@xunit.extensibility.core;xunit.assert@xunit.assert;xunit.abstractions@xunit.abstractions;"

    // `xunit.core` is a metapackage too — the assembly of that name is published by
    // `xunit.extensibility.core`. Guessing the package from the assembly is what could not work.
    assert xunit[0].AssemblyName != xunit[0].PackageId

    nunit := TestFrameworkReferenceSet.CompileAssemblies("nunit")
    assert ReferenceSetAssemblyNames(nunit) == "nunit.framework@NUnit;"
    assert nunit[0].AssemblyName != nunit[0].PackageId
}

test "the runtime set is what the runner needs and is not what the compile needs" {
    compile := TestFrameworkReferenceSet.CompileAssemblies("xunit")
    runtime := TestFrameworkReferenceSet.RuntimeAssemblies("xunit")

    // A test assembly binds attributes and assertions; it never names the execution engine, which is
    // found beside it when the run starts. Two questions, two sets.
    assert ReferenceSetAssemblyNames(runtime) == "xunit.execution.dotnet@xunit.extensibility.execution;"
    assert !TestFrameworkReferenceSet.MatchesAnyRow(compile, "xunit.execution.dotnet")
    assert !TestFrameworkReferenceSet.MatchesAnyRow(runtime, "xunit.core")

    // NUnit's runner is reflection over the same assembly the compile binds, so it adds nothing.
    assert TestFrameworkReferenceSet.RuntimeAssemblies("nunit").Count == 0
}

test "framework assembly membership is the set, not a name prefix" {
    assert TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunit.core")
    assert TestFrameworkReferenceSet.IsFrameworkAssemblyName("XUNIT.ASSERT")
    assert TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunit.abstractions")
    assert TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunit.execution.dotnet")
    assert TestFrameworkReferenceSet.IsFrameworkAssemblyName("nunit.framework")

    // A PREFIX WOULD OPEN THE WRONG FILES. The emitter walks every reference on the path looking for
    // `Xunit.FactAttribute`; `xunit.runner.visualstudio` cannot answer and neither can a user's own
    // `xunithelpers.dll`, and opening them is work that can only fail.
    assert !TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunit.runner.visualstudio")
    assert !TestFrameworkReferenceSet.IsFrameworkAssemblyName("xunithelpers")
    assert !TestFrameworkReferenceSet.IsFrameworkAssemblyName(null)
}

test "the host probe list keeps the v3 spelling that only an emit host can answer" {
    names := TestFrameworkReferenceSet.HostProbeAssemblyNames("xunit")

    // The emit host's last-ditch `Assembly.Load`: an xunit v3 host already carries `xunit.v3.core`.
    // It is deliberately NOT in the compile set — asking a v2 project's package cache for it could
    // only produce a failure about a package the project never restored.
    assert names.Length == 2
    assert names[0] == "xunit.core"
    assert names[1] == "xunit.v3.core"
    assert !TestFrameworkReferenceSet.MatchesAnyRow(TestFrameworkReferenceSet.CompileAssemblies("xunit"), "xunit.v3.core")

    nunitNames := TestFrameworkReferenceSet.HostProbeAssemblyNames("nunit")
    assert nunitNames.Length == 1
    assert nunitNames[0] == "nunit.framework"
}

test "the implicit test dependency plan restores the framework package the reference set names" {
    plan := CompilationReferenceResolverKernels.GetImplicitTestDependencyPlan(true, true, "xunit", new string[](0))

    // ONE OWNER FOR THE PACKAGE ROW TOO. The build restores what the analyzer plans to read; when
    // they were two literals they could drift to two versions without anything noticing.
    assert plan.ShouldAdd
    assert plan.PackageName == TestFrameworkReferenceSet.FrameworkPackageId("xunit")
    assert plan.Version == TestFrameworkReferenceSet.FrameworkPackageVersion("xunit")

    nunitPlan := CompilationReferenceResolverKernels.GetImplicitTestDependencyPlan(true, true, "nunit", new string[](0))
    assert nunitPlan.PackageName == TestFrameworkReferenceSet.FrameworkPackageId("nunit")
    assert nunitPlan.Version == TestFrameworkReferenceSet.FrameworkPackageVersion("nunit")
}

test "the metadata probe order can reach an asset published only for netstandard1.1" {
    frameworks := AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks("net10.0")

    // `xunit.core.dll` publishes at `lib/netstandard1.1` and nowhere newer, so a probe list that
    // stopped at `netstandard2.0` could not read the metadata for the attribute every `test` block
    // lowers to.
    found := false
    index := 0
    while index < frameworks.Length {
        if frameworks[index] == "netstandard1.1" {
            found = true
        }

        index = index + 1
    }

    assert found
    assert frameworks[0] == "net10.0"
}
