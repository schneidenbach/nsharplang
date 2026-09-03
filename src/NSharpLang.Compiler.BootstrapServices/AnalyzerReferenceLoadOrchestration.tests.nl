namespace NSharpLang.Compiler

import System.Collections.Generic


// THE THREE DECISIONS THAT CARRIED NO LITERAL.
//
// Task 021's audit moved every reference-loading decision that could be written as a string or a
// number into `AnalyzerMetadataLoadPolicy`, and left three behind because they are an ORDER and a
// KIND rather than a value. They stayed in `Analyzer.cs` for one more task and nothing pinned them,
// because the method that made them also opened files: the only observable was which assemblies
// happened to end up loaded on the machine running the test, which depends on that machine's NuGet
// cache and not on the rule.
//
// `PlanRequests` is the split that makes them assertable. It is pure — a `ProjectConfig` and a
// directory in, an ordered list of requests out — so every block below runs with no NuGet cache, no
// network, no restore output and no file of any kind.
func OrchestrationConfig(dependencies: List<Reference>, testDependencies: List<Reference>, sdk: string): ProjectConfig {
    config := new ProjectConfig()
    config.Name = "orchestration-probe"
    config.TargetFramework = "net10.0"
    config.Sdk = sdk
    config.Dependencies = dependencies
    config.TestDependencies = testDependencies
    return config
}

func OrchestrationReferences(values: List<Reference>): List<Reference> {
    return values
}

func OrchestrationKinds(requests: List<ReferenceLoadRequest>): string {
    rendered := ""
    index := 0
    while index < requests.Count {
        rendered = rendered + requests[index].Kind + ":" + requests[index].Value + ";"
        index = index + 1
    }

    return rendered
}

func OrchestrationEmpty(): List<Reference> {
    return new List<Reference>()
}

// ── D1: non-NuGet dependencies load before NuGet ones ────────────────────────

test "D1: every non-NuGet dependency is planned before every NuGet one, whatever the declaration order" {
    dependencies := new List<Reference>()
    dependencies.Add(new Reference { Nuget: "Alpha" })
    dependencies.Add(new Reference { Dll: "libs/Local.dll" })
    dependencies.Add(new Reference { Nuget: "Beta" })
    dependencies.Add(new Reference { Project: "../Shared/project.yml" })
    dependencies.Add(new Reference { Framework: "Microsoft.AspNetCore.App" })

    requests := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, OrchestrationEmpty(), "Microsoft.NET.Sdk"),
        "/proj"
    )

    // THE DECLARATION ORDER IS INTERLEAVED AND THE PLAN IS NOT. A `dll:` or `project:` reference is
    // the user's own build output; a `nuget:` one is a cache entry that may exist at several
    // versions, so the user's own is what wins the by-identity dedupe inside the load surface.
    assert requests.Count == 4
    assert requests[0].Kind == "dll"
    assert requests[1].Kind == "project"
    assert requests[2].Kind == "package"
    assert requests[3].Kind == "package"

    // Within each half, declaration order is preserved exactly.
    assert requests[2].Value == "Alpha"
    assert requests[3].Value == "Beta"

    // A `framework:` reference names something the host already has and plans NOTHING. It is the
    // fourth `ReferenceType` and the only one with no request of its own.
    assert OrchestrationKinds(requests).Contains("Microsoft.AspNetCore.App") == false
}

test "D1: a dll and a project reference resolve their path against the project directory" {
    dependencies := new List<Reference>()
    dependencies.Add(new Reference { Dll: "libs/Local.dll" })
    dependencies.Add(new Reference { Project: "../Shared/project.yml" })

    requests := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, OrchestrationEmpty(), "Microsoft.NET.Sdk"),
        "/proj"
    )

    assert requests.Count == 2
    assert requests[0].Value == AnalyzerMetadataLoadPolicy.ResolvedReferencePath("/proj", "libs/Local.dll")
    assert requests[1].Value == AnalyzerMetadataLoadPolicy.ResolvedReferencePath("/proj", "../Shared/project.yml")

    // The FAILURE identity is the raw spelling, not the resolved path: a user who wrote
    // `dll: libs/Local.dll` must read that back, not a directory they never typed.
    assert requests[0].Identity == "libs/Local.dll"
    assert requests[1].Identity == "../Shared/project.yml"
}

// ── D2: a test dependency contributes a NAME where a normal one contributes a PATH ──

test "D2: a normal NuGet dependency is planned by package and a test dependency by name" {
    dependencies := new List<Reference>()
    dependencies.Add(new Reference { Nuget: "Newtonsoft.Json", Version: "13.0.3" })

    testDependencies := new List<Reference>()
    testDependencies.Add(new Reference { Nuget: "xunit" })

    requests := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, testDependencies, "Microsoft.NET.Sdk"),
        "/proj"
    )

    assert requests.Count == 2

    // A normal dependency is resolved to a `lib/<tfm>/<name>.dll` under the project's pinned version,
    // so the version the project restored decides which metadata the diagnostics are computed against.
    assert requests[0].Kind == "package"
    assert requests[0].Value == "Newtonsoft.Json"
    assert requests[0].Version == "13.0.3"

    // A test dependency is left to the resolver BY NAME. Resolving it to a cache path would bind a
    // second copy of the test framework beside the one the host is already running.
    assert requests[1].Kind == "name"
    assert requests[1].Value == "xunit"
    assert requests[1].Version == null

    // And the test dependency is planned AFTER every ordinary one, which is the third half of D1.
    assert OrchestrationKinds(requests) == "package:Newtonsoft.Json;name:xunit;"
}

test "D2: a non-NuGet test dependency plans nothing at all" {
    testDependencies := new List<Reference>()
    testDependencies.Add(new Reference { Dll: "libs/Fake.dll" })
    testDependencies.Add(new Reference { Project: "../Fake/project.yml" })

    requests := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(OrchestrationEmpty(), testDependencies, "Microsoft.NET.Sdk"),
        "/proj"
    )

    // `testDependencies:` is a PACKAGE list. The C# this replaces filtered on `ReferenceType.NuGet`
    // and silently ignored anything else; that silence is the rule, and it is stated here rather
    // than left to be rediscovered.
    assert requests.Count == 0
}

// ── the package-name set the import diagnostics read ─────────────────────────

test "a blank package name still plans a request but contributes no name to the referenced set" {
    dependencies := new List<Reference>()
    dependencies.Add(new Reference { Nuget: "   " })
    dependencies.Add(new Reference { Nuget: "Real.Package" })

    requests := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, OrchestrationEmpty(), "Microsoft.NET.Sdk"),
        "/proj"
    )

    // TWO REQUESTS, ONE NAME. The blank entry is still attempted — the load fails and is recorded
    // under its own identity, which is how the user finds out — but it must not enter the set
    // `AnalyzerImports` consults when deciding whether an unresolved import names a real dependency.
    assert requests.Count == 2
    assert requests[0].RecordedPackageName == null
    assert requests[1].RecordedPackageName == "Real.Package"
    assert requests[0].Identity == "   "
}

// ── the ASP.NET tail ─────────────────────────────────────────────────────────

test "a web SDK appends its framework assemblies by name, last, and a plain SDK appends none" {
    dependencies := new List<Reference>()
    dependencies.Add(new Reference { Nuget: "Alpha" })

    plain := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, OrchestrationEmpty(), "Microsoft.NET.Sdk"),
        "/proj"
    )
    assert plain.Count == 1

    web := AnalyzerReferenceLoadOrchestration.PlanRequests(
        OrchestrationConfig(dependencies, OrchestrationEmpty(), "Microsoft.NET.Sdk.Web"),
        "/proj"
    )

    aspNetNames := AnalyzerMetadataLoadPolicy.AspNetCoreAssemblyNames()
    assert web.Count == 1 + aspNetNames.Length

    // They are NAMED, not referenced, so they take the same door a test dependency does — and they
    // come last, after everything the project actually declared.
    index := 0
    while index < aspNetNames.Length {
        assert web[1 + index].Kind == "name"
        assert web[1 + index].Value == aspNetNames[index]
        assert web[1 + index].RecordedPackageName == null
        index = index + 1
    }
}
