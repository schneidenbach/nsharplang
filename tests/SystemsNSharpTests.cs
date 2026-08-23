using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Performance;
using Xunit;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SystemsNSharpTests
{
    [Fact]
    public void HotFunction_RejectsHeapAllocation()
    {
        var report = Analyze("""
[hot]
func Make(): int {
    value := new Box()
    return 1
}

class Box {}
""");

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("error", finding.Severity);
        Assert.Equal("allocation", finding.Effect);
        Assert.Equal("Make", finding.Function);
    }

    [Fact]
    public void SystemsStrict_RequiresExplicitAllocMarkerForHeapNew()
    {
        var report = Analyze("""
func Make(): Box {
    return new Box()
}

class Box {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Severity == "error");
    }

    [Fact]
    public void SystemsStrict_AcceptsExplicitAllocMarkerOutsideHot()
    {
        var report = Analyze("""
func Make(): Box {
    return alloc new Box()
}

class Box {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS001");
    }

    [Fact]
    public void SystemsStrict_AcceptsAllocBlockForObviousAllocationSugar()
    {
        var report = Analyze("""
func Make(): Box {
    alloc {
        return new Box()
    }
}

class Box {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS001");
    }

    [Fact]
    public void HotFunction_RejectsUnguardedIndexTrap()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    return bytes[0]
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_AcceptsSimpleLengthGuardedIndex()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    if bytes.Length < 1 {
        return 0
    }
    return bytes[0]
}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_AcceptsIfTrueBranchLengthGuardedIndex()
    {
        var report = Analyze("""
[hot]
func Read(values: int[], index: int): int {
    if index < values.Length {
        return values[index]
    }
    return -1
}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_DoesNotApplyPostIfGuardInsideFailingBranch()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    if bytes.Length < 1 {
        return bytes[0]
    }
    return 0
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_AcceptsNarrowAllowAllocBlock()
    {
        var report = Analyze("""
[hot]
func Make(): int {
    allow(alloc, reason: "cold fallback table") {
        value := alloc new Box()
    }
    return 1
}

class Box {}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS010" && f.Effect == "allocation");
    }

    [Fact]
    public void BoundaryFunction_ReportsAllocationAndUnknownExternalCallWithoutBlocking()
    {
        var report = Analyze("""
[boundary]
func Load(): int {
    value := new Box()
    Console.WriteLine("loaded")
    return 1
}

class Box {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Severity == "warning");
        Assert.Contains(report.Findings, f => f.Code == "NSYS050" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Severity == "error");
    }

    [Fact]
    public void TrustedFunction_RequiresGovernanceMetadata()
    {
        var report = Analyze("""
[trusted(reason: "wraps native copy")]
func Copy(): int {
    return 1
}
""", profile: "systems");

        Assert.Single(report.TrustedSites);
        Assert.Contains(report.Findings, f => f.Code == "NSYS100" && f.Severity == "error");
    }

    [Fact]
    public void TrustedMemorySafeWrapper_AllowsRestrictedUnsafeBlock()
    {
        var report = Analyze("""
[memory(safe)]
[trusted(reason: "bounds checked by caller", owner: "runtime-core", review: "SYS-1")]
func Copy(): int {
    unsafe {
        value := 1
    }
    return 1
}
""", profile: "systems");

        Assert.Single(report.TrustedSites);
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS100");
    }

    [Fact]
    public void BufferMemoryCopy_InTrustedUnsafeWrapper_IsHotCallable()
    {
        var report = Analyze("""
import System

enum CopyStatus {
    Ok,
    OutOfRange
}

[memory(safe)]
[trusted(reason: "length is checked against both spans", owner: "runtime-core", review: "SYS-25")]
[hot]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): CopyStatus {
    if len < 0 || len > dst.Length || len > src.Length {
        return CopyStatus.OutOfRange
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    }

    return CopyStatus.Ok
}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code is "NSYS050" or "NSYS100" or "NSYS110");
        var copy = Assert.Single(report.Functions, function => function.Name == "CopyExact");
        Assert.True(copy.IsHot);
        Assert.False(copy.Effects.Allocates);
        Assert.False(copy.Effects.UsesUnknownExternalCall);
        Assert.False(copy.Effects.RequiresWarmup);
        Assert.Contains("Buffer.MemoryCopy", copy.Calls);
        var trusted = Assert.Single(report.TrustedSites);
        Assert.Equal("CopyExact", trusted.Function);
        Assert.True(trusted.HasUnsafe);
    }

    [Fact]
    public void BufferMemoryCopy_OutsideUnsafeBlock_FailsMemorySafety()
    {
        var report = Analyze("""
import System

[memory(safe)]
[trusted(reason: "missing unsafe isolation", owner: "runtime-core", review: "SYS-25")]
[hot]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): int {
    Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    return len
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS100" && f.Effect == "memorySafety");
    }

    [Fact]
    public void HotFunction_PropagatesCalleeAllocationWithCallPath()
    {
        var report = Analyze("""
[hot]
func Caller(): int {
    return Cold()
}

func Cold(): int {
    value := new Box()
    return 1
}

class Box {}
""");

        var finding = Assert.Single(report.Findings,
            f => f.Code == "NSYS010" && f.Message.Contains("Cold", StringComparison.Ordinal));
        Assert.Equal(new[] { "Caller", "Cold" }, finding.CallPath);
    }

    private const string HotCalleeAllocSource = """
class Alloc {
    func Helper(): Box {
        return alloc new Box()
    }

    [hot]
    func Hot(): int {
        value := this.Helper()
        return value.Tag
    }
}

class Box {
    Tag: int
}
""";

    private const string HotCalleeCleanSource = """
class Clean {
    func Helper(): int {
        return 1
    }
}
""";

    [Theory]
    [InlineData("a_alloc.nl", "z_clean.nl")]
    [InlineData("z_alloc.nl", "a_clean.nl")]
    public void HotCallee_SameMethodNameInTwoClasses_FlagsNsys010RegardlessOfFileOrder(string allocFile, string cleanFile)
    {
        var report = AnalyzeFiles(new Dictionary<string, string>
        {
            [allocFile] = HotCalleeAllocSource,
            [cleanFile] = HotCalleeCleanSource,
        });

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("Alloc.Hot", finding.Function);
        Assert.Contains("Alloc.Helper", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void HotCallee_SameFileLaterDuplicate_StillFlagged()
    {
        var report = Analyze(HotCalleeAllocSource + Environment.NewLine + HotCalleeCleanSource);

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("Alloc.Hot", finding.Function);
        Assert.Contains("Alloc.Helper", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void HotCallee_CleanHotPath_NotBlamedForUnrelatedAllocator()
    {
        var report = AnalyzeFiles(new Dictionary<string, string>
        {
            ["a_clean.nl"] = """
class Clean {
    func Helper(): int {
        return 1
    }

    [hot]
    func Hot(): int {
        return this.Helper()
    }
}
""",
            ["z_alloc.nl"] = """
class Alloc {
    func Helper(): Box {
        return alloc new Box()
    }
}

class Box {}
""",
        });

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS010");
        var hot = Assert.Single(report.Functions, function => function.Name == "Clean.Hot");
        Assert.False(hot.Effects.Allocates);
    }

    [Fact]
    public void FilePrivateTopLevelDuplicates_ResolvePerFile()
    {
        var report = AnalyzeFiles(new Dictionary<string, string>
        {
            ["a_other.nl"] = """
func helper(): int {
    return 2
}
""",
            ["z_hot.nl"] = """
func helper(): int {
    box := alloc new Box()
    return box.Tag
}

[hot]
func HotPath(): int {
    return helper()
}

class Box {
    Tag: int
}
""",
        });

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("HotPath", finding.Function);

        // Both file-private duplicates are distinct functions: each body is analyzed and reported.
        var helpers = report.Functions.Where(function => function.Name == "helper").ToList();
        Assert.Equal(2, helpers.Count);
        Assert.False(helpers.Single(function => function.File.EndsWith("a_other.nl", StringComparison.Ordinal)).Effects.Allocates);
        Assert.True(helpers.Single(function => function.File.EndsWith("z_hot.nl", StringComparison.Ordinal)).Effects.Allocates);
    }

    [Fact]
    public void HotCallee_OverloadsResolveByArity_AllocatingOverloadFlagged()
    {
        var report = Analyze("""
class Alloc {
    func Helper(): int {
        return 1
    }

    func Helper(n: int): Box {
        return alloc new Box()
    }

    [hot]
    func Hot(): int {
        value := this.Helper(2)
        return 1
    }
}

class Box {}
""");

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("Alloc.Hot", finding.Function);
    }

    [Fact]
    public void HotCallee_OverloadsResolveByArity_CleanOverloadNotFlagged()
    {
        var report = Analyze("""
class Alloc {
    func Helper(): int {
        return 1
    }

    func Helper(n: int): Box {
        return alloc new Box()
    }

    [hot]
    func Hot(): int {
        return this.Helper()
    }
}

class Box {}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS010");
        var hot = Assert.Single(report.Functions, function => function.Name == "Alloc.Hot");
        Assert.False(hot.Effects.Allocates);
    }

    [Fact]
    public void Nsys050_NotSuppressedByCoincidentalName()
    {
        var report = Analyze("""
class Unrelated {
    func Helper(): int {
        return 1
    }
}

[hot]
func Hot(io: SomeUnknownService): int {
    return io.Helper()
}
""");

        Assert.Contains(report.Findings,
            f => f.Code == "NSYS050" && f.Message.Contains("io.Helper", StringComparison.Ordinal));
    }

    [Fact]
    public void HotConstrainedGenericCall_ResolvesThroughConstraintInterface()
    {
        var report = Analyze("""
interface Sortable<T> {
    func LessThan(other: T): bool
}

struct Pair : Sortable<Pair> {
    Value: int

    func LessThan(other: Pair): bool {
        return Value < other.Value
    }
}

[hot]
func SortPair<T>(items: T[]): int where T : struct, Sortable<T> {
    if items.Length < 2 {
        return 0
    }

    if items[1].LessThan(items[0]) {
        tmp := items[0]
        items[0] = items[1]
        items[1] = tmp
    }

    return 0
}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050");
        var sortPair = Assert.Single(report.Functions, function => function.Name == "SortPair");
        Assert.Contains("Sortable.LessThan", sortPair.Calls);
    }

    [Fact]
    public void HotCallee_ResolvesAcrossFileImport()
    {
        var report = AnalyzeFiles(new Dictionary<string, string>
        {
            ["lib.nl"] = """
func MakeBox(): Box {
    return alloc new Box()
}

class Box {}
""",
            ["main.nl"] = """
import "lib"

[hot]
func Hot(): int {
    value := MakeBox()
    return 1
}
""",
        });

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("Hot", finding.Function);
        Assert.Contains("MakeBox", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void HotCallee_ImportedDuplicateSourceSite_ResolvesImportedDeclaration()
    {
        var report = AnalyzeFiles(new Dictionary<string, string>
        {
            ["libA.nl"] = """
func MakeBox(): Box {
    return alloc new Box()
}

class Box {
    Tag: int
}
""",
            ["libB.nl"] = """
func MakeBox(): int {
    return 1
}
""",
            ["main.nl"] = """
import "libA"

[hot]
func Hot(): int {
    value := MakeBox()
    return value.Tag
}
""",
        });

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("Hot", finding.Function);
        Assert.Contains("MakeBox", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050");
    }

    [Fact]
    public void RefStruct_AllowsRefLikeFieldsButOrdinaryStructDoesNot()
    {
        var report = Analyze("""
import System

ref struct Reader {
    buf: ReadOnlySpan<byte>
}

struct Holder {
    buf: ReadOnlySpan<byte>
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Function == "Holder");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS080" && f.Function == "Reader");
    }

    [Fact]
    public void LifetimeSyntax_ParsesScopedParameterAndReturnLifetime()
    {
        var unit = Parse("""
import System

func Slice<'a>(buf: ReadOnlySpan<byte> scoped 'a, start: int, len: int): ReadOnlySpan<byte> returns 'a {
    return buf.Slice(start, len)
}
""");

        var function = Assert.IsType<FunctionDeclaration>(Assert.Single(unit.Declarations.OfType<FunctionDeclaration>()));
        Assert.Equal("'a", Assert.Single(function.TypeParameters!).Name);
        Assert.Equal("'a", function.ReturnLifetime);
        var parameter = Assert.Single(function.Parameters.Where(p => p.Name == "buf"));
        Assert.True(parameter.IsScoped);
        Assert.Equal("'a", parameter.Lifetime);
    }

    [Fact]
    public void LifetimeSyntax_ParsesHeapReturnLifetime()
    {
        var unit = Parse("""
import System

func Slice(arena: &Arena, start: int, len: int): Span<byte> returns heap(arena) {
    return arena.backing.AsSpan(start, len)
}

struct Arena {
    backing: byte[]
}
""");

        var function = Assert.Single(unit.Declarations.OfType<FunctionDeclaration>());
        Assert.Equal("heap(arena)", function.ReturnLifetime);
    }

    [Fact]
    public void HotRefLikeReturn_RequiresReturnLifetime()
    {
        var report = Analyze("""
import System

[hot]
func Slice(buf: ReadOnlySpan<byte>): ReadOnlySpan<byte> {
    return buf.Slice(0, 1)
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Effect == "lifetime");
    }

    [Fact]
    public void Stackalloc_UsesConfiguredBudget()
    {
        var report = Analyze("""
func Scratch(): int {
    scratch := stackalloc byte[65]
    return scratch.Length
}
""", profile: "systems", configure: config => config.Language.Systems.StackBudgetBytes = 64);

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Message.Contains("64", StringComparison.Ordinal));
    }

    [Fact]
    public void Stackalloc_WrappedLiteralLength_UsesConfiguredBudget()
    {
        var report = Analyze("""
func Scratch(): int {
    scratch := stackalloc byte[checked((int)65)]
    return scratch.Length
}
""", profile: "systems", configure: config => config.Language.Systems.StackBudgetBytes = 64);

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS080");
        Assert.Contains("64", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("statically bounded", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Stackalloc_AliasedWrappedLiteralLength_UsesConfiguredBudget()
    {
        var report = Analyze("""
type Count = short

func Scratch(): int {
    scratch := stackalloc byte[checked((Count)65)]
    return scratch.Length
}
""", profile: "systems", configure: config => config.Language.Systems.StackBudgetBytes = 64);

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS080");
        Assert.Contains("65 bytes", finding.Message, StringComparison.Ordinal);
        Assert.Contains("64 bytes", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("statically bounded", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Stackalloc_WrappedNegativeLength_ReportsNegative()
    {
        var report = Analyze("""
func Scratch(): int {
    scratch := stackalloc byte[unchecked(-(1))]
    return scratch.Length
}
""", profile: "systems");

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS080");
        Assert.Contains("cannot be negative", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("statically bounded", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Stackalloc_AliasedWrappedNegativeLength_ReportsNegative()
    {
        var report = Analyze("""
type Count = short

func Scratch(): int {
    scratch := stackalloc byte[unchecked((Count)-1)]
    return scratch.Length
}
""", profile: "systems");

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS080");
        Assert.Contains("cannot be negative", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("statically bounded", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Stackalloc_AliasedElementType_UsesResolvedElementSizeForBudget()
    {
        var report = Analyze("""
type ScratchByte = byte

func Scratch(): int {
    scratch := stackalloc ScratchByte[65]
    return scratch.Length
}
""", profile: "systems", configure: config => config.Language.Systems.StackBudgetBytes = 64);

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS080");
        Assert.Contains("65 bytes", finding.Message, StringComparison.Ordinal);
        Assert.Contains("64 bytes", finding.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("1040 bytes", finding.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Stackalloc_OversizedCount_DoesNotOverflowBudgetCheck()
    {
        // M4: elementCount*elementSize was computed in int; 2_000_000_000 * 4 overflowed to a
        // negative value that wrongly passed the budget check. Computed in long, it is correctly
        // rejected as over-budget.
        var report = Analyze("""
func Scratch(): int {
    scratch := stackalloc int[2000000000]
    return scratch.Length
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS080");
    }

    [Fact]
    public void HotDivision_ByNonZeroFloatLiteral_IsNotAnImplicitTrap()
    {
        // M2: the divide/modulo trap check only recognized non-zero INT literals, so a float-literal
        // divisor was wrongly reported as an unproven trap. A non-zero literal can never
        // divide-by-zero.
        var report = Analyze("""
[hot]
func Scale(n: int): double {
    return n / 2.0
}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotDivision_GuardFromEarlyReturn_ExpiresWithItsScope()
    {
        // M3: PopGuards removed guards by value, and flow guards added via AddGuards (e.g. the
        // `d != 0` implied by `if d == 0 return`) leaked past the scope that introduced them. With
        // mark/truncate popping, the guard is scoped to the outer `if flag` block: the division
        // INSIDE the block is proven non-zero, but the one AFTER the block is not and must trap.
        var report = Analyze("""
[hot]
func Ratio(n: int, d: int, flag: bool): int {
    if flag {
        if d == 0 {
            return 0
        }
        inside := n / d
    }
    outside := n / d
    return outside
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void PoolRent_MustBeReturnedOnObviousLexicalPath()
    {
        var report = Analyze("""
func Lease(): int {
    buffer := ArrayPool.Shared.Rent(128)
    return 1
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS130" && f.Effect == "pool");
    }

    [Fact]
    public void SystemsStrict_DisposableResourceMustBeDisposed()
    {
        var report = Analyze("""
func Open(): int {
    stream := alloc new FileStream()
    return 1
}

class FileStream {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS090" && f.Effect == "resource");
    }

    [Fact]
    public void SystemsStrict_DisposeCallSatisfiesObviousResourceOwnership()
    {
        var report = Analyze("""
func Open(): int {
    stream := alloc new FileStream()
    stream.Dispose()
    return 1
}

class FileStream {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS090" && f.Effect == "resource");
    }

    [Fact]
    public void BoundaryExceptionControlFlow_IsReportedWithoutBlocking()
    {
        var report = Analyze("""
[boundary]
func Load(): Result<int, string> {
    try {
        return Ok(1)
    } catch ex: Exception {
        return Err("failed")
    }
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "throw" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Severity == "error");
    }

    [Fact]
    public void UnsupportedConcurrencyPrimitive_FailsClosedInHotCode()
    {
        var report = Analyze("""
[hot]
func ReadCounter(value: int): int {
    return Interlocked.Read(value)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS140" && f.Effect == "concurrency");
    }

    [Fact]
    public void HotBoundarySurface_RejectsSystemsHostileTypes()
    {
        var report = Analyze("""
import System.Collections.Generic

[hot]
func Count(values: IEnumerable<int>): int {
    return 0
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS070" && f.Effect == "boundaryLeak");
    }

    [Fact]
    public void HotBoundarySurface_AcceptsStructConstrainedGenericComparer()
    {
        var report = Analyze("""
interface ValueComparer<T> {
    func Less(a: T, b: T): bool
}

[hot]
func Sort<T, TComparer>(values: Span<T>, comparer: TComparer): int where T : struct where TComparer : struct, ValueComparer<T> {
    return values.Length
}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings,
            f => f.Code == "NSYS070"
                 && f.Effect == "boundaryLeak"
                 && f.Message.Contains("comparer", StringComparison.Ordinal));
    }

    [Fact]
    public void HotBoundarySurface_RejectsUnconstrainedGenericComparer()
    {
        var report = Analyze("""
[hot]
func Sort<T, TComparer>(values: Span<T>, comparer: TComparer): int where T : struct {
    return values.Length
}
""", profile: "systems");

        Assert.Contains(report.Findings,
            f => f.Code == "NSYS070"
                 && f.Effect == "boundaryLeak"
                 && f.Message.Contains("comparer", StringComparison.Ordinal));
    }

    [Fact]
    public void DictionaryTryGetValue_OnRegisteredDictionaryMember_IsHotSummaryCovered()
    {
        var report = Analyze("""
import System.Collections.Generic

static class Catalog {
    static Codes: Dictionary<int, int> = Build()
}

[boundary]
func Build(): Dictionary<int, int> {
    map := alloc new Dictionary<int, int>(capacity: 4)
    map[1] = 100
    return map
}

[hot]
func Lookup(code: int): Result<int, string> {
    value := 0
    if Catalog.Codes.TryGetValue(code, out value) {
        return Ok(value)
    }
    return Err("missing")
}
""", profile: "systems", configure: config => config.Language.Systems.Warmup.Add("Build"));

        Assert.DoesNotContain(report.Findings,
            f => f.Code == "NSYS050"
                 && f.Effect == "unknownExternalCall"
                 && string.Equals(f.Function, "Lookup", StringComparison.Ordinal));
    }

    [Fact]
    public void TryGetValue_OnUnregisteredReceiver_StillFailsClosedInHotCode()
    {
        var report = Analyze("""
import System.Collections.Generic

static class Catalog {
    static Store: SortedDictionary<int, int> = Build()
}

[boundary]
func Build(): SortedDictionary<int, int> {
    map := alloc new SortedDictionary<int, int>()
    map[1] = 100
    return map
}

[hot]
func Lookup(code: int): Result<int, string> {
    value := 0
    if Catalog.Store.TryGetValue(code, out value) {
        return Ok(value)
    }
    return Err("missing")
}
""", profile: "systems", configure: config => config.Language.Systems.Warmup.Add("Build"));

        Assert.Contains(report.Findings,
            f => f.Code == "NSYS050"
                 && f.Effect == "unknownExternalCall"
                 && string.Equals(f.Function, "Lookup", StringComparison.Ordinal));
    }

    [Fact]
    public void FunctionLevelAllow_RequiresReasonAndPublicOwner()
    {
        var report = Analyze("""
[allow(alloc)]
public func Visible(): int {
    return 1
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS180" && f.Effect == "effectPolicy" && f.Message.Contains("reason", StringComparison.Ordinal));
        Assert.Contains(report.Findings, f => f.Code == "NSYS180" && f.Effect == "effectPolicy" && f.Message.Contains("owner", StringComparison.Ordinal));
    }

    [Fact]
    public void ResultHelpers_AreKnownInHotResultContext()
    {
        var report = Analyze("""
enum ParseError {
    Bad
}

[hot]
func Parse(value: int): Result<int, ParseError> {
    if value == 0 {
        return Err(ParseError.Bad)
    }
    return Ok(value)
}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050" && (f.Message.Contains("Ok", StringComparison.Ordinal) || f.Message.Contains("Err", StringComparison.Ordinal)));
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS070");
    }

    [Fact]
    public void ResultValue_MustBeUsedOnSystemsPaths()
    {
        var report = Analyze("""
enum ParseError {
    Bad
}

func Parse(value: int): Result<int, ParseError> {
    return Ok(value)
}

func Run(): int {
    Parse(1)
    return 0
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS160" && f.Effect == "resultMustUse");
    }

    [Fact]
    public void ResultRuntimeAbi_IsAllocationFreeTaggedStruct()
    {
        var ok = NSharpLang.Runtime.Result<int, string>.Ok(42);
        var err = NSharpLang.Runtime.Result<int, string>.Err("bad");

        Assert.True(ok.IsOk);
        Assert.False(ok.IsErr);
        Assert.True(ok.TryGetOk(out var value));
        Assert.Equal(42, value);
        Assert.Equal(42, ok.OkValueUnchecked);
        Assert.False(ok.TryGetErr(out _));

        Assert.True(err.IsErr);
        Assert.False(err.IsOk);
        Assert.True(err.TryGetErr(out var error));
        Assert.Equal("bad", error);
        Assert.Equal("bad", err.ErrValueUnchecked);
        Assert.False(err.TryGetOk(out _));

        Assert.True(typeof(NSharpLang.Runtime.Result<int, string>).IsValueType);
        Assert.True(typeof(NSharpLang.Runtime.Result<int, string>).IsAssignableTo(typeof(IEquatable<NSharpLang.Runtime.Result<int, string>>)));
    }

    [Fact]
    public void SidecarHotSummary_FailsClosedForHotUnlessPolicyAllowsIt()
    {
        var source = """
[hot]
func Run(): int {
    return External.Fast()
}
""";

        var denied = AnalyzeWithSidecar(source, allowHotSidecars: false);
        Assert.Contains(denied.Findings, f => f.Code == "NSYS050" && f.Message.Contains("sidecar", StringComparison.Ordinal));

        var allowed = AnalyzeWithSidecar(source, allowHotSidecars: true);
        Assert.DoesNotContain(allowed.Findings, f => f.Code == "NSYS050");
    }

    [Fact]
    public void SidecarHotSummary_MissingIdentityReportsEffectDrift()
    {
        var report = AnalyzeWithSidecarDocument("""
[hot]
func Run(): int {
    return External.Fast()
}
""", """
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "External",
      "targetFramework": "*",
      "method": "External.Fast",
      "source": "sidecar",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      }
    }
  ]
}
""", allowHotSidecars: true);

        Assert.Contains(report.Findings, f => f.Code == "NSYS150" && f.Effect == "effectDrift");
    }

    [Fact]
    public void SourceInferredHelper_GainingAllocationFailsHotCaller()
    {
        var report = Analyze("""
[hot]
func ParseDigits(bytes: ReadOnlySpan<byte>): Result<int, string> {
    if bytes.Length == 0 {
        _ = FormatForDebug()
        return Err("empty")
    }
    return Ok(bytes[0])
}

func FormatForDebug(): int[] {
    return alloc new int[1]
}
""", profile: "systems");

        Assert.Contains(report.Findings,
            f => f.Code == "NSYS010"
                 && f.Effect == "allocation"
                 && f.Message.Contains("FormatForDebug", StringComparison.Ordinal));
    }

    [Fact]
    public void AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations()
    {
        var root = Path.Combine(FindRepoRoot(), "tests", "fixtures", "systems-gauntlet");
        var cases = Directory.GetDirectories(root).OrderBy(path => path, StringComparer.Ordinal).ToArray();

        Assert.Equal(10, cases.Length);
        foreach (var dir in cases)
        {
            var sourcePath = Path.Combine(dir, "sample.nl");
            var diagnosticsPath = Path.Combine(dir, "diagnostics.golden.txt");
            Assert.True(File.Exists(sourcePath), $"{dir} is missing sample.nl");
            Assert.True(File.Exists(Path.Combine(dir, "systems.golden.json")), $"{dir} is missing systems.golden.json");
            Assert.True(File.Exists(diagnosticsPath), $"{dir} is missing diagnostics.golden.txt");
            Assert.True(File.Exists(Path.Combine(dir, "perf-report.golden.json")), $"{dir} is missing perf-report.golden.json");
            var source = File.ReadAllText(sourcePath);
            var unit = Parse(source, sourcePath);
            var report = Analyze(source, profile: "systems");

            AssertSystemsGolden(dir, unit, report, Path.Combine(dir, "systems.golden.json"));
            AssertDiagnosticsGolden(dir, report, diagnosticsPath);
            AssertPerfGolden(dir, report, Path.Combine(dir, "perf-report.golden.json"));
        }
    }

    private static void AssertSystemsGolden(string caseDir, CompilationUnit unit, SystemsReport report, string goldenPath)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(goldenPath));
        Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        var expected = doc.RootElement.GetProperty("expected");

        foreach (var property in expected.EnumerateObject())
        {
            switch (property.Name)
            {
                case "errors":
                    if (property.Value.ValueKind == JsonValueKind.Array && !property.Value.EnumerateArray().Any())
                    {
                        Assert.DoesNotContain(report.Findings, finding => finding.Severity == "error");
                    }
                    break;

                case "hot":
                    var hot = property.Value.GetString();
                    if (hot == "pass")
                    {
                        Assert.DoesNotContain(report.Findings, finding => finding.Severity == "error");
                    }
                    else
                    {
                        Assert.Contains(report.Functions, function => function.Name == hot && function.IsHot);
                    }
                    break;

                case "boundary":
                    Assert.Contains(report.Functions, function => function.Name == property.Value.GetString() && function.IsBoundary);
                    break;

                case "bclHotSummary":
                    foreach (var required in property.Value.EnumerateArray().Select(value => value.GetString()).Where(value => value != null))
                    {
                        var token = required!.Split('.').Last();
                        Assert.Contains(report.Functions.SelectMany(function => function.Calls),
                            call => call.Contains(token, StringComparison.Ordinal));
                    }
                    break;

                case "boundsProof":
                    Assert.DoesNotContain(report.Findings,
                        finding => finding.Code == "NSYS120" && finding.Effect == "implicitTrap");
                    break;

                case "concurrencyPrimitive":
                    Assert.True(report.Functions.Any(function => function.Effects.UsesConcurrencyPrimitive),
                        $"{caseDir} expected a concurrency primitive in the generated systems report.");
                    break;

                case "returnLifetime":
                    Assert.Contains(unit.Declarations.OfType<FunctionDeclaration>(),
                        function => function.ReturnLifetime == property.Value.GetString());
                    break;

                case "resultAbi":
                    Assert.Contains(unit.Declarations.OfType<FunctionDeclaration>(),
                        function => TypeReferenceText(function.ReturnType) == property.Value.GetString());
                    break;

                case "refStruct":
                    Assert.Contains(unit.Declarations.OfType<StructDeclaration>(),
                        declaration => declaration.Name == property.Value.GetString() && declaration.IsRefStruct);
                    break;

                case "failure":
                    Assert.NotEmpty(report.Findings);
                    break;

                case "code":
                    Assert.Contains(report.Findings, finding => finding.Code == property.Value.GetString());
                    break;

                case "trustedSites":
                    foreach (var site in property.Value.EnumerateArray().Select(value => value.GetString()).Where(value => value != null))
                    {
                        Assert.Contains(report.TrustedSites, trusted => trusted.Function == site);
                    }
                    break;

                case "aotTarget":
                    Assert.Equal(property.Value.GetString(), report.AotTarget);
                    Assert.Equal(property.Value.GetString(), report.Aot.Target);
                    break;

                case "aot":
                    Assert.DoesNotContain(report.Findings, finding => finding.Code == "NSYS060");
                    break;

                case "nativeImageEmitted":
                    Assert.Equal(property.Value.GetBoolean(), report.Aot.NativeImageEmitted);
                    break;

                default:
                    throw new InvalidOperationException($"Unhandled systems gauntlet expectation '{property.Name}' in {caseDir}.");
            }
        }
    }

    private static void AssertDiagnosticsGolden(string caseDir, SystemsReport report, string diagnosticsPath)
    {
        var text = File.ReadAllText(diagnosticsPath).Trim();
        Assert.False(string.IsNullOrWhiteSpace(text), $"{caseDir} has an empty diagnostics golden.");

        if (text.StartsWith("PASS:", StringComparison.Ordinal))
        {
            Assert.DoesNotContain(report.Findings, finding => finding.Severity == "error");
            return;
        }

        var match = Regex.Match(text, @"^(NSYS\d{3})\s+(error|warning):\s+(.+)$", RegexOptions.Singleline);
        Assert.True(match.Success, $"{caseDir} diagnostics golden must start with PASS or an NSYS finding line.");

        var code = match.Groups[1].Value;
        var severity = match.Groups[2].Value;
        var expectedMessage = NormalizeDiagnosticText(match.Groups[3].Value);

        Assert.Contains(report.Findings, finding =>
            finding.Code == code
            && finding.Severity == severity
            && NormalizeDiagnosticText(finding.Message).Contains(expectedMessage, StringComparison.Ordinal));
    }

    private static void AssertPerfGolden(string caseDir, SystemsReport report, string goldenPath)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(goldenPath));
        Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("build", doc.RootElement.GetProperty("command").GetString());
        var expected = doc.RootElement.GetProperty("expected");

        foreach (var property in expected.EnumerateObject())
        {
            switch (property.Name)
            {
                case "allocationSites":
                    AssertPerfSites(caseDir, property.Value, SitesForEffect(report, "allocation"));
                    break;
                case "boxingSites":
                    AssertPerfSites(caseDir, property.Value, SitesForEffect(report, "boxing"));
                    break;
                case "dispatchSites":
                    AssertPerfSites(caseDir, property.Value, SitesForEffect(report, "dispatch"));
                    break;
                case "poolSites":
                    AssertPerfSites(caseDir, property.Value, SitesForEffect(report, "pool"));
                    break;
                case "boundaryLeakSites":
                    AssertPerfSites(caseDir, property.Value, SitesForEffect(report, "boundaryLeak"));
                    break;
                case "trustedSites":
                    AssertStringSites(caseDir, property.Value, report.TrustedSites.Select(site => site.Function));
                    break;
                case "aotAnalysis":
                    Assert.Equal(property.Value.GetString(), report.Aot.Analysis);
                    break;
                default:
                    throw new InvalidOperationException($"Unhandled perf gauntlet expectation '{property.Name}' in {caseDir}.");
            }
        }
    }

    private static IEnumerable<SystemsFinding> SitesForEffect(SystemsReport report, string effect)
        => report.Findings.Where(finding => finding.Effect == effect);

    private static void AssertPerfSites(string caseDir, JsonElement expected, IEnumerable<SystemsFinding> actualSites)
    {
        var sites = actualSites.ToArray();
        if (expected.ValueKind == JsonValueKind.Array && !expected.EnumerateArray().Any())
        {
            Assert.Empty(sites);
            return;
        }

        AssertStringSites(caseDir, expected, sites.Select(site =>
            string.Join(" ", new[] { site.Code, site.Effect, site.Function, site.Message, site.Suggestion }
                .Where(value => !string.IsNullOrWhiteSpace(value)))));
    }

    private static void AssertStringSites(string caseDir, JsonElement expected, IEnumerable<string?> actualSites)
    {
        var actual = actualSites
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => NormalizeDiagnosticText(value!))
            .ToArray();

        foreach (var expectedSite in expected.EnumerateArray().Select(value => value.GetString()).Where(value => value != null))
        {
            var normalized = NormalizeDiagnosticText(expectedSite!);
            Assert.Contains(actual, site => site.Contains(normalized, StringComparison.Ordinal));
        }
    }

    private static string TypeReferenceText(TypeReference? type) => type switch
    {
        null => "",
        SimpleTypeReference simple => simple.Name,
        GenericTypeReference generic => $"{generic.Name}<{string.Join(", ", generic.TypeArguments.Select(TypeReferenceText))}>",
        ArrayTypeReference array => $"{TypeReferenceText(array.ElementType)}[]",
        NullableTypeReference nullable => $"{TypeReferenceText(nullable.InnerType)}?",
        ByRefTypeReference byRef => $"&{TypeReferenceText(byRef.InnerType)}",
        UnionTypeReference union => string.Join(" | ", union.Arms.Select(TypeReferenceText)),
        _ => type.ToString() ?? ""
    };

    private static string NormalizeDiagnosticText(string value)
        => Regex.Replace(value.ToLowerInvariant(), @"[^a-z0-9]+", " ").Trim();

    [Fact]
    public void CheckCommand_SystemsReport_EmitsVersionedJson()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
  systems:
    mode: strict
""", """
func Make(): Box {
    return new Box()
}

class Box {}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--systems-report" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check.systemsReport", doc.RootElement.GetProperty("command").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("systemsReport").GetProperty("schemaVersion").GetInt32());
            Assert.False(doc.RootElement.GetProperty("systemsReport").GetProperty("aot").GetProperty("nativeImageEmitted").GetBoolean());
            Assert.Contains(doc.RootElement.GetProperty("systemsReport").GetProperty("findings").EnumerateArray(),
                finding => finding.GetProperty("code").GetString() == "NSYS001");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void BuildCommand_PerfReport_EmitsSystemsEffectSitesFromRealBuild()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
  systems:
    mode: strict
""", """
[boundary]
func Make(): object {
    return new Box()
}

class Box {}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--project", tempDir, "--perf-report"));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stderr);
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("build", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

            var perfReport = doc.RootElement.GetProperty("perfReport");
            Assert.Contains(perfReport.GetProperty("allocationSites").EnumerateArray(),
                site => site.GetProperty("code").GetString() == "NSYS001"
                        && site.GetProperty("function").GetString() == "Make");
            Assert.Contains(perfReport.GetProperty("boundaryLeakSites").EnumerateArray(),
                site => site.GetProperty("code").GetString() == "NSYS070"
                        && site.GetProperty("function").GetString() == "Make");
            Assert.Equal(JsonValueKind.Array, perfReport.GetProperty("poolSites").ValueKind);
            Assert.Equal(JsonValueKind.Array, perfReport.GetProperty("resourceSites").ValueKind);
            Assert.Equal(JsonValueKind.Array, perfReport.GetProperty("hotReadinessSites").ValueKind);
            Assert.Equal(JsonValueKind.Array, perfReport.GetProperty("implicitTrapSites").ValueKind);
            Assert.Equal(JsonValueKind.Array, perfReport.GetProperty("trustedSites").ValueKind);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void QueryPerf_ReturnsSystemsFindingAtPosition()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
""", """
func Make(): Box {
    return new Box()
}

class Box {}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                QueryCommand.Execute(new[] { "perf", "--project", tempDir, "--file", "Program.nl", "--pos", "2:12" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("perf", doc.RootElement.GetProperty("command").GetString());
            Assert.Contains(doc.RootElement.GetProperty("facts").EnumerateArray(),
                fact => fact.GetProperty("source").GetString() == "systems"
                        && fact.GetProperty("code").GetString() == "NSYS001");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void QueryTrusted_ReturnsTrustedSites()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
  systems:
    mode: audit
""", """
[trusted(reason: "reviewed wrapper", owner: "runtime", review: "SYS-1")]
func Copy(): int {
    return 1
}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                QueryCommand.Execute(new[] { "trusted", "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("trusted", doc.RootElement.GetProperty("command").GetString());
            var site = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("Copy", site.GetProperty("function").GetString());
            Assert.Equal("runtime", site.GetProperty("owner").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    private static SystemsReport Analyze(string source, string profile = "default", string mode = "strict", Action<ProjectConfig>? configure = null)
        => AnalyzeFiles(new Dictionary<string, string> { ["Program.nl"] = source }, profile, mode, configure);

    private static SystemsReport AnalyzeFiles(
        IReadOnlyDictionary<string, string> sources,
        string profile = "default",
        string mode = "strict",
        Action<ProjectConfig>? configure = null)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-analysis-{Guid.NewGuid():N}");

        var config = ProjectFileParser.CreateDefault("SystemsTest");
        config.Language.Profile = profile;
        config.Language.Systems.Mode = mode;
        configure?.Invoke(config);

        return AnalyzeProject(projectRoot, config, sources);
    }

    private static SystemsReport AnalyzeProject(string projectRoot, ProjectConfig config, IReadOnlyDictionary<string, string> sources)
    {
        var sourceTexts = sources.ToDictionary(
            kvp => Path.Combine(projectRoot, kvp.Key),
            kvp => kvp.Value,
            StringComparer.OrdinalIgnoreCase);

        foreach (var (file, text) in sourceTexts)
        {
            Parse(text, file);
        }

        // Run the same analysis pipeline `nlc check` runs (parse + semantic Analyzer + systems
        // policy): systems callee resolution consumes the Analyzer's semantic models, so feeding
        // SystemsAnalyzer bare ASTs would conservatively flag every user call as unknown.
        var compiler = new MultiFileCompiler(sourceTexts.Keys, projectRoot, config, sourceTexts);
        compiler.CompileForAnalysis();
        return compiler.SystemsReport;
    }

    private static SystemsReport AnalyzeWithSidecar(string source, bool allowHotSidecars)
        => AnalyzeWithSidecarDocument(source, """
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "External",
      "targetFramework": "*",
      "method": "External.Fast",
      "source": "sidecar",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      },
      "bodyIdentity": "test-body"
    }
  ]
}
""", allowHotSidecars);

    private static SystemsReport AnalyzeWithSidecarDocument(string source, string sidecarJson, bool allowHotSidecars)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-sidecar-{Guid.NewGuid():N}");
        Directory.CreateDirectory(projectRoot);
        try
        {
            var sidecarPath = Path.Combine(projectRoot, "external.hotsummary.json");
            File.WriteAllText(sidecarPath, sidecarJson);

            var config = ProjectFileParser.CreateDefault("SystemsSidecar");
            config.Language.Profile = "systems";
            config.Language.Systems.HotSummaryFiles.Add("external.hotsummary.json");
            config.Language.Systems.AllowHotSidecars = allowHotSidecars;

            return AnalyzeProject(projectRoot, config, new Dictionary<string, string> { ["Program.nl"] = source });
        }
        finally
        {
            Directory.Delete(projectRoot, recursive: true);
        }
    }

    private static CompilationUnit Parse(string source, string file = "Program.nl")
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, file);

        Assert.NotNull(result.CompilationUnit);
        Assert.DoesNotContain(result.Errors, error => error.Severity == ErrorSeverity.Error);
        return result.CompilationUnit!;
    }

    private static string FormatCompilerError(CompilerError error)
        => $"{error.DiagnosticId}: {error.Message} ({error.FileName}:{error.Line}:{error.Column})";

    private static string CreateTempProject(string languageConfig, string program)
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-systems-cli-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "project.yml"), $"""
name: SystemsCliTest
outputType: library
targetFramework: net10.0
{languageConfig}
""");
        File.WriteAllText(Path.Combine(tempDir, "Program.nl"), program);
        return tempDir;
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalErr = Console.Error;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        try
        {
            Console.SetOut(stdout);
            Console.SetError(stderr);
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalErr);
        }
    }

    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", BindingFlags.Static | BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        while (true)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            var parent = Directory.GetParent(dir);
            if (parent == null)
            {
                throw new DirectoryNotFoundException("Could not find repository root.");
            }

            dir = parent.FullName;
        }
    }
}
