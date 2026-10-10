namespace NSharpLang.TestAssemblyLoadContexts.Tests

import System
import System.Collections.Generic
import System.IO
import System.Runtime.CompilerServices
import System.Runtime.Loader
import System.Text.RegularExpressions

// ─── HOW A TEST HOST LOADS THE ASSEMBLIES IT EMITS ────────────────────────────────────────────
//
// This project replaces `tests/CollectibleAssemblyScopeTests.cs` and retires its subject,
// `tests/CollectibleAssemblyScope.cs`. That helper existed for ONE host: the xunit process that ran
// `tests/Tests.csproj`. `Assembly.Load(byte[])` pins each emitted assembly in a fresh
// NON-collectible context for the host's lifetime, and with hundreds of emitted parity assemblies
// per run that was an unbounded leak which intermittently OOM-crashed the host. The helper wrapped
// every load in a collectible `AssemblyLoadContext` scoped by `using`.
//
// The C# had no remaining CALLER by the time it was deleted — every parity suite that used it had
// already migrated to N# — so what is worth keeping is not the wrapper but the two claims it rested
// on, and the guard that kept people honest. All three survive below, aimed at their live subjects
// rather than at the deleted type.
class LoadContextMarker {
}

// ═══ THE CLR CONTRACT THE HELPER RESTED ON ════════════════════════════════════════════════════
//
// `Load_UsesACollectibleNonDefaultContext` and `Dispose_LetsTheContextUnload` were, underneath,
// two claims about `AssemblyLoadContext` itself: a context created with `isCollectible: true` is
// collectible and is not the default one, and once it is unloaded and nothing roots it the runtime
// reclaims it. They are asserted here against the API directly, so they keep verifying the
// mechanism any future N#-side loader would have to use.

func SelfAssemblyPath(): string {
    location := typeof(LoadContextMarker).Assembly.Location
    if location.Length == 0 || !File.Exists(location) {
        throw new InvalidOperationException("This test assembly has no readable location on disk.")
    }

    return location
}

test "a context created collectible is collectible, and is not the default context" {
    context := new AssemblyLoadContext("CollectibleTestAssembly", true)
    try {
        assembly := context.LoadFromAssemblyPath(SelfAssemblyPath())

        loaded := AssemblyLoadContext.GetLoadContext(assembly)
        assert loaded != null
        assert loaded.IsCollectible
        assert !Object.ReferenceEquals(loaded, AssemblyLoadContext.Default)
        assert Object.ReferenceEquals(loaded, context)
    } finally {
        context.Unload()
    }
}

// No inlining: the locals that reference the context must be OUT OF SCOPE — not extended by the JIT
// into the caller's frame — before the unload-detecting collection runs. This is the same guard the
// deleted C# carried, and it is the reason the load happens in its own method.
class UnloadProbe {
    [MethodImpl(MethodImplOptions.NoInlining)]
    static func LoadAndUnload(assemblyPath: string): WeakReference {
        context := new AssemblyLoadContext("CollectibleTestAssembly", true)
        weakContext := new WeakReference(AssemblyLoadContext.GetLoadContext(context.LoadFromAssemblyPath(assemblyPath)))
        context.Unload()
        return weakContext
    }
}

test "an unloaded collectible context becomes reclaimable, so nothing roots it for the host's lifetime" {
    weakContext := UnloadProbe.LoadAndUnload(SelfAssemblyPath())

    // Unload completion is cooperative and lags under load (the EE's unload worker races other
    // threads' allocation and JIT churn), so be patient: a ~3s bound with an early exit.
    attempt := 0
    while weakContext.IsAlive && attempt < 30 {
        GC.Collect()
        GC.WaitForPendingFinalizers()
        System.Threading.Thread.Sleep(100)
        attempt = attempt + 1
    }

    assert !weakContext.IsAlive
}

// ═══ WHERE `nlc test` ACTUALLY PUTS THE ASSEMBLY IT EMITS ═════════════════════════════════════
//
// MEASURED, NOT ASSUMED. `nlc test` has two runners, and only one of them is collectible: the
// NUnit-shaped reflection runner loads the emitted assembly into a private collectible
// `NativeTestLoadContext`, while the DEFAULT xunit runner hands the path to `XunitFrontController`
// and resolves its neighbours through `AssemblyLoadContext.Default.Resolving` — so the emitted
// assembly lands in the DEFAULT, non-collectible context. Every native test project in this
// repository takes the second route, and this row records that.
//
// This is NOT the unbounded leak the deleted helper was written against, and that difference is the
// whole reason the row is a record rather than a failure: the gate runs `nlc test --project <dir>`
// as a SEPARATE PROCESS per project, so exactly one emitted assembly is pinned per process and it
// dies with the process. The xunit host the helper protected held one process across hundreds of
// emitted assemblies. If the runner is ever changed to run several projects in one process, this
// row trips first and says what has to be fixed before that lands.
test "the xunit runner leaves this emitted test assembly in the default, non-collectible context" {
    context := AssemblyLoadContext.GetLoadContext(typeof(LoadContextMarker).Assembly)

    assert context != null
    assert Object.ReferenceEquals(context, AssemblyLoadContext.Default)
    assert !context.IsCollectible
}

// ═══ THE GUARD ════════════════════════════════════════════════════════════════════════════════
//
// The helper only helped if tests actually used it: within hours of the original conversion, new
// dogfood slices reintroduced direct `Assembly.Load` calls, and this guard turned the convention
// (memory/testing.md, "Emitted Assemblies Load Into Collectible Scopes") into a failing test. It
// keeps its ORIGINAL SUBJECT — C# sources under `tests/` — because that is the host the rule was
// written for, and because the rule for an N# native project is a different rule with a different
// answer: those assemblies are loaded by `nlc test` itself, one per process, not by the source
// under test. The row is now a tripwire against C# coming BACK under `tests/` with the banned call
// shape, alongside the ownership growth ratchet which refuses the file outright.

func RepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not find repository root (NSharpLang.sln) above this test tree.")
}

// Matches the banned static loader call sites: the `Assembly` receiver, a dot, a `Load`-prefixed
// member, and an opening argument list on the same line. `AssemblyLoadContext` members
// (`LoadFromStream`, `LoadFromAssemblyPath`, …) do not match.
func DirectAssemblyLoadCall(): Regex {
    return new Regex("\\bAssembly\\s*\\.\\s*Load\\w*\\s*\\(", RegexOptions.Compiled)
}

// Comments and XML docs legitimately mention the banned APIs; only code outside a `//`-comment tail
// counts as a call site.
func StripLineCommentTail(line: string): string {
    commentStart := line.IndexOf("//", StringComparison.Ordinal)
    if commentStart < 0 {
        return line
    }

    return line.Substring(0, commentStart)
}

func IsBuildOutputPath(relativePath: string): bool {
    separators := [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]
    for segment in relativePath.Split(separators) {
        if segment == "bin" || segment == "obj" || segment == "TestResults" {
            return true
        }
    }

    return false
}

func DirectAssemblyLoadOffenders(): List<string> {
    repositoryRoot := RepositoryRoot()
    testsDirectory := Path.Combine(repositoryRoot, "tests")
    pattern := DirectAssemblyLoadCall()
    offenders := new List<string>()

    for sourcePath in Directory.EnumerateFiles(testsDirectory, "*.cs", SearchOption.AllDirectories) {
        relativePath := Path.GetRelativePath(repositoryRoot, sourcePath)
        if IsBuildOutputPath(relativePath) {
            continue
        }

        lines := File.ReadAllLines(sourcePath)
        index := 0
        while index < lines.Length {
            if pattern.IsMatch(StripLineCommentTail(lines[index])) {
                offenders.Add(relativePath + ":" + (index + 1).ToString() + ": " + lines[index].Trim())
            }

            index = index + 1
        }
    }

    return offenders
}

test "no C# source under tests/ calls Assembly.Load, Assembly.LoadFile or Assembly.LoadFrom directly" {
    offenders := DirectAssemblyLoadOffenders()

    // A direct static loader call pins the emitted assembly in a non-collectible context for the
    // host's lifetime. Load through a collectible AssemblyLoadContext instead — see
    // memory/testing.md, "Emitted Assemblies Load Into Collectible Scopes".
    assert string.Join("\n", offenders) == ""
    assert offenders.Count == 0
}

// The guard's own machinery is proved on text it controls, so a scan that silently stopped matching
// would be caught. The deleted C# had no such row: it asserted only that the repository was clean,
// which a broken regex also satisfies.
test "the guard matches the banned call shapes and ignores load-context members and comment tails" {
    pattern := DirectAssemblyLoadCall()

    assert pattern.IsMatch("var a = Assembly.Load(bytes);")
    assert pattern.IsMatch("Assembly . LoadFile ( path )")
    assert pattern.IsMatch("return Assembly.LoadFrom(path);")
    assert !pattern.IsMatch("context.LoadFromAssemblyPath(path)")
    assert !pattern.IsMatch("scope.LoadFromStream(stream)")

    assert StripLineCommentTail("// never call Assembly.Load(bytes)").Trim() == ""
    assert !pattern.IsMatch(StripLineCommentTail("// never call Assembly.Load(bytes)"))
    assert pattern.IsMatch(StripLineCommentTail("Assembly.Load(bytes); // banned"))
}
