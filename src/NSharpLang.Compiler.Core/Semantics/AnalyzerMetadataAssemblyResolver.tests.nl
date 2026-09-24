namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices


// D3 — THE RESOLVER'S FOUR-STAGE PROBE ORDER, DRIVEN THROUGH A REAL `MetadataLoadContext`.
//
// This is the third of the three decisions task 021's audit could not move because none of them
// carries a literal. It is also the one that cannot be asserted on a pure function: `Resolve` is
// called BY the load context, its answer depends on what that context already holds, and its whole
// job is IO. So these blocks build a real context over a real resolver and ask it real questions,
// with fixtures written under this run's own temp directory.
//
// THE ORDER IS PROVEN BY MAKING THE STAGES DISAGREE. A block that puts one copy where exactly one
// stage can find it proves only that the stage works. Each block below places TWO answers and asserts
// which one comes back, so a reordering of the probe changes the verdict.
func ResolverProbeFrameworkDirectory(): string {
    return RuntimeEnvironment.GetRuntimeDirectory()
}

func ResolverProbeReferencePackDirectory(): string {
    seeds := new string[](1)
    seeds[0] = ResolverProbeFrameworkDirectory()
    directories := DocQueryKernels.GetReferencePackDirectories(seeds, Environment.GetEnvironmentVariable("DOTNET_ROOT"))
    index := 0
    while index < directories.Length {
        if File.Exists(Path.Combine(directories[index], "System.Console.dll")) {
            return directories[index]
        }

        index = index + 1
    }

    return ""
}

func ResolverProbeTempDirectory(name: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-resolver-probe-" + name)
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }

    Directory.CreateDirectory(directory)
    return directory
}

func ResolverProbeSurfaceless(directories: List<string>): AnalyzerMetadataAssemblyResolver {
    return new AnalyzerMetadataAssemblyResolver(
        directories,
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
}

func ResolverProbeList(values: string[]): List<string> {
    list := new List<string>()
    index := 0
    while index < values.Length {
        list.Add(values[index])
        index = index + 1
    }

    return list
}

func ResolverProbeOneDirectory(directory: string): List<string> {
    values := new string[](1)
    values[0] = directory
    return ResolverProbeList(values)
}

func ResolverProbeTwoDirectories(first: string, second: string): List<string> {
    values := new string[](2)
    values[0] = first
    values[1] = second
    return ResolverProbeList(values)
}

func ResolverProbeCameFrom(assembly: Assembly, directory: string): bool {
    return Path.GetFullPath(assembly.get_Location()) == Path.GetFullPath(Path.Combine(directory, "System.Console.dll"))
}

func ResolverProbeConsoleIdentity(): AssemblyName {
    return AssemblyName.GetAssemblyName(Path.Combine(ResolverProbeFrameworkDirectory(), "System.Console.dll"))
}

// ── the fixture ──────────────────────────────────────────────────────────────

test "the resolver probe fixture has one identity in two real directories" {
    frameworkDirectory := ResolverProbeFrameworkDirectory()
    referenceDirectory := ResolverProbeReferencePackDirectory()

    assert referenceDirectory.Length > 0
    assert frameworkDirectory != referenceDirectory
    assert File.Exists(Path.Combine(frameworkDirectory, "System.Console.dll"))
    assert File.Exists(Path.Combine(referenceDirectory, "System.Console.dll"))
}

// ── stage 2, and the fact that the resolver is what the context actually calls ──

test "the load context binds its core assembly THROUGH the resolver's search directories" {
    resolver := ResolverProbeSurfaceless(ResolverProbeOneDirectory(ResolverProbeFrameworkDirectory()))

    // Nothing else can answer: a `MetadataLoadContext` resolves NOTHING by itself, so a core assembly
    // coming back at all is proof that stage 2 ran and that this override is the slot the CLR calls.
    context := new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
    core := context.get_CoreAssembly()
    assert core != null
    coreName := core.GetName()
    assert coreName.get_Name() == AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName()
}

test "stage 2 walks the search directories IN ORDER, and reversing the list reverses the answer" {
    frameworkDirectory := ResolverProbeFrameworkDirectory()
    referenceDirectory := ResolverProbeReferencePackDirectory()
    identity := ResolverProbeConsoleIdentity()

    referenceFirst := ResolverProbeSurfaceless(ResolverProbeTwoDirectories(referenceDirectory, frameworkDirectory))
    referenceContext := new MetadataLoadContext(referenceFirst, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
    fromReference := referenceFirst.Resolve(referenceContext, identity)
    assert fromReference != null
    assert ResolverProbeCameFrom(fromReference, referenceDirectory)

    // THE LIST IS A PROBE ORDER, WHICH IS WHY `ShouldAddSearchDirectory` dedupes ORDINALLY: a
    // directory spelled two ways is two probe positions, and this is the observable that makes that
    // a rule rather than a preference.
    frameworkFirst := ResolverProbeSurfaceless(ResolverProbeTwoDirectories(frameworkDirectory, referenceDirectory))
    frameworkContext := new MetadataLoadContext(frameworkFirst, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
    fromFramework := frameworkFirst.Resolve(frameworkContext, identity)
    assert fromFramework != null
    assert !ResolverProbeCameFrom(fromFramework, referenceDirectory)
    assert ResolverProbeCameFrom(fromFramework, frameworkDirectory)
}

// ── stage 1 before stage 2 ───────────────────────────────────────────────────

test "stage 1 returns the already-loaded copy even when stage 2 would find a different file first" {
    frameworkDirectory := ResolverProbeFrameworkDirectory()
    referenceDirectory := ResolverProbeReferencePackDirectory()
    identity := ResolverProbeConsoleIdentity()

    // The REFERENCE directory is first in the probe order, so stage 2 alone would answer from it.
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    resolver := new AnalyzerMetadataAssemblyResolver(
        ResolverProbeTwoDirectories(referenceDirectory, frameworkDirectory),
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
        failures
    )
    context := new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())

    // ... but the framework copy is already IN the context.
    staged := context.LoadFromAssemblyPath(Path.Combine(frameworkDirectory, "System.Console.dll"))
    stagedName := staged.GetName()
    assert stagedName.get_Name() == "System.Console"

    resolved := resolver.Resolve(context, identity)
    assert resolved != null

    // STAGE 1 WINS, AND IT HAS TO. Type identity inside a load context is per assembly OBJECT, so a
    // second copy of an identity the context already bound would make `IsAssignable` answer no about
    // a type that plainly is one.
    assert ResolverProbeCameFrom(resolved, frameworkDirectory)

    // AND THE RETURN VALUE ALONE CANNOT SAY THAT, WHICH IS WHY THIS ASSERTION IS HERE. Measured by
    // mutation: moving stage 1 AFTER the search-directory walk does NOT change the assembly that
    // comes back, because the CLR refuses the duplicate identity itself -- stage 2 finds the
    // reference-pack file, `LoadFromAssemblyPath` throws `FileLoadException`, the failure is
    // recorded, the walk continues and the relocated stage 1 answers the same. The observable that
    // DOES separate the two orders is the failure table: stage 1 first means the resolver never
    // attempts a load that has to fail, so a correct probe order records NOTHING here.
    assert failures.Count == 0
}

// ── a bad file is recorded and the walk CONTINUES ────────────────────────────

test "a file that exists but will not load is recorded and the next directory still answers" {
    poisoned := ResolverProbeTempDirectory("poisoned")
    File.WriteAllText(Path.Combine(poisoned, "System.Console.dll"), "this is not a managed assembly")

    frameworkDirectory := ResolverProbeFrameworkDirectory()
    identity := ResolverProbeConsoleIdentity()

    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    resolver := new AnalyzerMetadataAssemblyResolver(
        ResolverProbeTwoDirectories(poisoned, frameworkDirectory),
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
        failures
    )

    context := new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
    resolved := resolver.Resolve(context, identity)

    // THROWING WOULD HAVE ABANDONED A RESOLUTION THE VERY NEXT CANDIDATE SATISFIES. The bad file is
    // recorded under its own path and the walk moves on.
    assert resolved != null
    assert ResolverProbeCameFrom(resolved, frameworkDirectory)
    assert failures.Count == 1
    assert failures.ContainsKey(Path.Combine(poisoned, "System.Console.dll"))

    Directory.Delete(poisoned, true)
}

test "a name no stage can answer resolves to null rather than throwing" {
    resolver := ResolverProbeSurfaceless(ResolverProbeOneDirectory(ResolverProbeFrameworkDirectory()))
    context := new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())

    // Absent everywhere: not loaded, in no search directory, and no package of that name or prefix.
    // All four stages miss, and a miss is an ANSWER -- returning null is what lets the context report
    // an unresolved reference instead of the resolver deciding the analysis is over.
    absent := new AssemblyName("NSharpLang.NoSuchAssembly.ProbeOnly")
    assert resolver.Resolve(context, absent) == null
}
