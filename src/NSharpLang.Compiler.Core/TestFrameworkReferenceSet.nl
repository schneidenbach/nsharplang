namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// ONE ROW OF A TEST FRAMEWORK'S REFERENCE SET: AN ASSEMBLY, AND THE PACKAGE THAT SHIPS IT.
//
// The two are NOT the same string and assuming they were is what produced
// "Reference assembly 'xunit' could not be loaded": `xunit` is a METAPACKAGE — it carries no `lib`
// folder at all — and `xunit.core.dll` ships inside a package called `xunit.extensibility.core`.
// Every probe the compiler makes for a test-framework assembly needs BOTH halves, so a row carries
// both and nothing has to guess one from the other.
class TestFrameworkAssemblyRow {
    AssemblyName: string
    PackageId: string

    constructor(assemblyName: string, packageId: string) {
        AssemblyName = assemblyName
        PackageId = packageId
    }
}

// THE TEST-FRAMEWORK REFERENCE SET, AND THE ONLY PLACE IT IS SPELLED.
//
// A `test "..."` block lowers to a method carrying the framework's own attributes, so the compiler
// has to bind those attribute types before it can emit, and the editor has to bind them before it
// can say anything true about a `.tests.nl` file. Three products asked that question separately and
// answered it three different ways: `nlc test` resolved the framework from the emit host, `nlc check`
// asked the analyzer to load the *package id* as if it were an assembly, and the language server
// never asked at all — so an attribute deriving from `FactAttribute` bound in a build and did not
// bind in the editor.
//
// THE SET IS SPLIT IN TWO BECAUSE THE TWO QUESTIONS ARE DIFFERENT.
//
//   COMPILE — what a `test` block's lowering must BIND against: the attribute types it attaches and
//   the assertion surface its body calls. Nothing here is needed to run anything; it is the metadata
//   the analyzer and the emitter read.
//
//   RUNTIME — what must sit beside the emitted test assembly for the runner to DISCOVER and EXECUTE
//   those methods. xunit's execution engine is a separate assembly from its attribute surface, and a
//   project can compile perfectly against the compile set and still have nothing to run it with.
//
// A METAPACKAGE IS NEVER A ROW. `xunit` and `xunit.core` are both metapackages; neither can appear as
// an assembly name, so neither can ever be reported as one that failed to load.
class TestFrameworkReferenceSet {
    static func XunitFrameworkName(): string {
        return "xunit"
    }

    static func NUnitFrameworkName(): string {
        return "nunit"
    }

    // `project.yml` spells `testFramework:`; an absent or unrecognised value means xunit, which is
    // the same default `ProjectConfig.TestFramework` and the SDK's `NSharpTestFramework` carry.
    static func NormalizeFrameworkName(testFramework: string?): string {
        if string.Equals(testFramework ?? "", NUnitFrameworkName(), StringComparison.OrdinalIgnoreCase) {
            return NUnitFrameworkName()
        }

        return XunitFrameworkName()
    }

    static func IsNUnit(testFramework: string?): bool {
        return NormalizeFrameworkName(testFramework) == NUnitFrameworkName()
    }

    // THE RESTORE ROW: the package a project that writes tests depends on, and the version the
    // toolchain pins. `nlc build`, `nlc check` and `nlc test` all restore this one.
    static func FrameworkPackageId(testFramework: string?): string {
        if IsNUnit(testFramework) {
            return "NUnit"
        }

        return "xunit"
    }

    static func FrameworkPackageVersion(testFramework: string?): string {
        if IsNUnit(testFramework) {
            return "4.3.2"
        }

        return "2.9.2"
    }

    // Does this declared test dependency name the framework's own package? A project that pins the
    // framework itself has its reference set decided here; any OTHER test dependency is an ordinary
    // package and keeps the ordinary treatment.
    static func IsFrameworkPackageId(packageId: string?, testFramework: string?): bool {
        return string.Equals(packageId ?? "", FrameworkPackageId(testFramework), StringComparison.OrdinalIgnoreCase)
    }

    // WHAT A `test` BLOCK'S LOWERING BINDS AGAINST.
    //
    // xunit: `Xunit.FactAttribute` and `Xunit.TraitAttribute` live in `xunit.core.dll`, which ships in
    // the `xunit.extensibility.core` package; `Xunit.Assert` lives in `xunit.assert.dll`; both name
    // types from `xunit.abstractions.dll`, so metadata for it has to be loadable or every member the
    // other two expose through it reads as unresolved.
    static func CompileAssemblies(testFramework: string?): List<TestFrameworkAssemblyRow> {
        rows := new List<TestFrameworkAssemblyRow>()
        if IsNUnit(testFramework) {
            rows.Add(new TestFrameworkAssemblyRow("nunit.framework", "NUnit"))
            return rows
        }

        rows.Add(new TestFrameworkAssemblyRow("xunit.core", "xunit.extensibility.core"))
        rows.Add(new TestFrameworkAssemblyRow("xunit.assert", "xunit.assert"))
        rows.Add(new TestFrameworkAssemblyRow("xunit.abstractions", "xunit.abstractions"))
        return rows
    }

    // WHAT THE RUNNER NEEDS AT RUN TIME, BEYOND THE COMPILE SET. xunit's discovery and execution
    // engine is `xunit.execution.dotnet.dll`, which no compile ever names: a test assembly binds only
    // the attribute and assertion surface, and the engine is found beside it when the run starts.
    static func RuntimeAssemblies(testFramework: string?): List<TestFrameworkAssemblyRow> {
        rows := new List<TestFrameworkAssemblyRow>()
        if IsNUnit(testFramework) {
            return rows
        }

        rows.Add(new TestFrameworkAssemblyRow("xunit.execution.dotnet", "xunit.extensibility.execution"))
        return rows
    }

    // The compile set as bare names, for the emit host's last-ditch `Assembly.Load` probe. The v3
    // spelling is a HOST probe only: an xunit v3 emit host carries `xunit.v3.core` already loaded, and
    // asking a v2 project's package cache for it would only manufacture a failure.
    static func HostProbeAssemblyNames(testFramework: string?): string[] {
        if IsNUnit(testFramework) {
            names := new string[](1)
            names[0] = "nunit.framework"
            return names
        }

        xunitNames := new string[](2)
        xunitNames[0] = "xunit.core"
        xunitNames[1] = "xunit.v3.core"
        return xunitNames
    }

    // IS THIS REFERENCE PATH ONE OF THE FRAMEWORK'S OWN ASSEMBLIES? Asked of every reference on the
    // path the emitter walks looking for `Xunit.FactAttribute`, so that a project referencing a
    // hundred packages opens only the handful that could possibly answer. The question is membership
    // of the set above — not a name prefix, which would also open `xunit.runner.visualstudio` and
    // anything else a user happened to call `xunitfoo`.
    static func IsFrameworkAssemblyName(assemblySimpleName: string?): bool {
        if assemblySimpleName == null {
            return false
        }

        if MatchesAnyRow(CompileAssemblies(XunitFrameworkName()), assemblySimpleName) {
            return true
        }

        if MatchesAnyRow(RuntimeAssemblies(XunitFrameworkName()), assemblySimpleName) {
            return true
        }

        if MatchesAnyRow(CompileAssemblies(NUnitFrameworkName()), assemblySimpleName) {
            return true
        }

        return MatchesAnyRow(RuntimeAssemblies(NUnitFrameworkName()), assemblySimpleName)
    }

    static func MatchesAnyRow(rows: List<TestFrameworkAssemblyRow>, assemblySimpleName: string): bool {
        index := 0
        while index < rows.Count {
            if string.Equals(rows[index].AssemblyName, assemblySimpleName, StringComparison.OrdinalIgnoreCase) {
                return true
            }

            index = index + 1
        }

        return false
    }
}
