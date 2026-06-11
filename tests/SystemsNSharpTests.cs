using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using System.Threading.Tasks;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Performance;
using NSharpLang.Tests.PerfEvidence;
using Xunit;

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
    public void ByRefTypeParameter_AcceptsRefArgument()
    {
        var result = CompileAndInvoke("""
ref struct FrameReader {
    pos: int
}

func Touch(reader: &FrameReader scoped 'reader): int {
    reader.pos = 1
    return reader.pos
}

func Run(): int {
    reader := new FrameReader { pos: 0 }
    return Touch(ref reader)
}
""", "Run");

        Assert.Equal(1, result);
    }

    [Fact]
    public void LifetimeOnlyTypeParameter_IsErasedFromIlSignature()
    {
        var source = """
import System

ref struct FrameReader {
    buf: ReadOnlySpan<int>
}

func First<'a>(reader: &FrameReader scoped 'a): int returns 'a {
    return reader.buf[0]
}

func Run(): int {
    values := [42]
    reader := new FrameReader { buf: values }
    return First(ref reader)
}
""";
        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"LifetimeOnlyTypeParameter_{Guid.NewGuid():N}.dll");
        var assemblyName = $"LifetimeOnlyTypeParameter_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath);
            compiler.Compile();

            loadContext = new AssemblyLoadContext($"LifetimeOnlyTypeParameter_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(File.ReadAllBytes(outputPath));
            var assembly = loadContext.LoadFromStream(stream);
            var program = assembly.GetType("Program")!;
            var first = program.GetMethod("First", BindingFlags.Public | BindingFlags.Static)!;
            var run = program.GetMethod("Run", BindingFlags.Public | BindingFlags.Static)!;

            Assert.False(first.IsGenericMethodDefinition);
            Assert.Empty(first.GetGenericArguments());
            Assert.Equal(42, run.Invoke(null, null));
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
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
    public void SourceGeneratedJsonBoundary_IsAotSafeButReportsAllocation()
    {
        var report = Analyze("""
import System.Text.Json
import System.Text.Json.Serialization

record Payload {
    Value: int
}

[JsonSerializable(typeof(Payload))]
partial class PayloadJsonContext : JsonSerializerContext {
}

[boundary]
func Emit(payload: Payload): string {
    return JsonSerializer.Serialize(payload, PayloadJsonContext.Default.Payload)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Effect == "allocation" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS060");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050");
    }

    [Fact]
    public void SourceGeneratedJsonContext_CompilesAndSerializesWithGeneratedTypeInfo()
    {
        var result = CompileProjectAndInvoke("""
import System.Text.Json
import System.Text.Json.Serialization

record Payload {
    Name: string
    Enabled: bool
    Count: int
}

[JsonSerializable(typeof(Payload))]
partial class PayloadJsonContext : JsonSerializerContext {
}

func Run(): string {
    payload := new Payload { Name: "alpha", Enabled: true, Count: 7 }
    return JsonSerializer.Serialize(payload, PayloadJsonContext.Default.Payload)
}
""", "Run");

        Assert.Equal("""{"Name":"alpha","Enabled":true,"Count":7}""", result);
    }

    [Fact]
    public void ReflectionJsonBoundary_IsTargetQualifiedAotBlocker()
    {
        var report = Analyze("""
import System.Text.Json

record Payload {
    Value: int
}

[boundary]
func Emit(payload: Payload): string {
    return JsonSerializer.Serialize(payload)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS060" && f.Effect == "aot" && f.Severity == "warning");
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
            Assert.True(File.Exists(Path.Combine(dir, "interop.golden.txt")), $"{dir} is missing interop.golden.txt");

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
                case "aotBlockers":
                    if (property.Value.ValueKind == JsonValueKind.Array && !property.Value.EnumerateArray().Any())
                    {
                        Assert.DoesNotContain(report.Findings, finding => finding.Code == "NSYS060");
                    }
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
    public void SystemsProofProjects_AreExecutableAndCoveredByAudit()
    {
        var repoRoot = FindRepoRoot();
        var proofsRoot = Path.Combine(repoRoot, "docs", "design", "systems-samples", "proofs");
        var auditPath = Path.Combine(repoRoot, "docs", "audits", "systems-proof-project-audit.md");
        var readmePath = Path.Combine(repoRoot, "docs", "design", "systems-samples", "README.md");

        var proofProjects = Directory.GetDirectories(proofsRoot)
            .Select(Path.GetFileName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var executableProofProjects = new[]
        {
            "24-zero-copy-frame-reader",
            "25-trusted-memory-copy",
            "26-native-device-handle",
            "27-c-library-cli",
            "28-nativeaot-json-cli",
            "29-generated-regex-boundary",
            "30-cold-failure-logging",
            "31-hot-metrics",
            "32-cache-prewarm",
            "33-arraypool-file-io",
            "34-memorypool-disposal",
            "35-async-file-hot-parser",
            "36-dictionary-setup-hot-read",
            "37-fixed-capacity-map",
            "38-unmanaged-sort-comparer",
            "39-hot-linq-pipeline",
            "40-csharp-hot-parser-api",
            "41-structured-errors",
            "42-aot-friendly-public-api",
            "43-mono-wasm-plugin",
            "44-ci-allocation-gate",
            "45-trusted-audit",
            "46-dapper-boundary",
            "47-cli-startup-honesty",
            "48-effect-drift"
        };
        var designOnlyProjects = proofProjects.Except(executableProofProjects, StringComparer.Ordinal).ToArray();

        Assert.Equal(25, proofProjects.Length);
        Assert.Empty(designOnlyProjects);
        Assert.True(File.Exists(auditPath), "Systems proof projects must have an explicit audit artifact.");

        var readme = File.ReadAllText(readmePath);
        Assert.Contains("Status: executable proof samples", readme, StringComparison.Ordinal);
        Assert.Contains("Executable proof projects", readme, StringComparison.Ordinal);

        var audit = File.ReadAllText(auditPath);
        Assert.Contains("Status: executable proof report and compiler audit", audit, StringComparison.Ordinal);
        foreach (var project in executableProofProjects)
        {
            Assert.Contains($"`{project}` | executable", audit, StringComparison.Ordinal);
        }

        foreach (var project in designOnlyProjects)
        {
            Assert.Contains($"`{project}`", audit, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence()
    {
        var repoRoot = FindRepoRoot();
        var proofsRoot = Path.Combine(repoRoot, "docs", "design", "systems-samples", "proofs");
        var zeroCopyFrameReader = Path.Combine(proofsRoot, "24-zero-copy-frame-reader");
        var trustedMemoryCopy = Path.Combine(proofsRoot, "25-trusted-memory-copy");
        var nativeDeviceHandle = Path.Combine(proofsRoot, "26-native-device-handle");
        var cLibraryCli = Path.Combine(proofsRoot, "27-c-library-cli");
        var nativeAotJsonCli = Path.Combine(proofsRoot, "28-nativeaot-json-cli");
        var generatedRegexBoundary = Path.Combine(proofsRoot, "29-generated-regex-boundary");
        var coldFailureLogging = Path.Combine(proofsRoot, "30-cold-failure-logging");
        var hotMetrics = Path.Combine(proofsRoot, "31-hot-metrics");
        var cachePrewarm = Path.Combine(proofsRoot, "32-cache-prewarm");
        var arrayPoolFileIo = Path.Combine(proofsRoot, "33-arraypool-file-io");
        var memoryPoolDisposal = Path.Combine(proofsRoot, "34-memorypool-disposal");
        var asyncFileHotParser = Path.Combine(proofsRoot, "35-async-file-hot-parser");
        var dictionarySetup = Path.Combine(proofsRoot, "36-dictionary-setup-hot-read");
        var fixedCapacityMap = Path.Combine(proofsRoot, "37-fixed-capacity-map");
        var unmanagedSortComparer = Path.Combine(proofsRoot, "38-unmanaged-sort-comparer");
        var hotLinqPipeline = Path.Combine(proofsRoot, "39-hot-linq-pipeline");
        var csharpHotParserApi = Path.Combine(proofsRoot, "40-csharp-hot-parser-api");
        var structuredErrors = Path.Combine(proofsRoot, "41-structured-errors");
        var aotFriendlyPublicApi = Path.Combine(proofsRoot, "42-aot-friendly-public-api");
        var monoWasmPlugin = Path.Combine(proofsRoot, "43-mono-wasm-plugin");
        var allocationGate = Path.Combine(proofsRoot, "44-ci-allocation-gate");
        var trustedAudit = Path.Combine(proofsRoot, "45-trusted-audit");
        var dapperBoundary = Path.Combine(proofsRoot, "46-dapper-boundary");
        var cliStartupHonesty = Path.Combine(proofsRoot, "47-cli-startup-honesty");
        var effectDrift = Path.Combine(proofsRoot, "48-effect-drift");

        var proofBuilds = BuildSystemsProofProjects(new[]
        {
            zeroCopyFrameReader,
            trustedMemoryCopy,
            nativeDeviceHandle,
            cLibraryCli,
            nativeAotJsonCli,
            generatedRegexBoundary,
            coldFailureLogging,
            hotMetrics,
            cachePrewarm,
            arrayPoolFileIo,
            memoryPoolDisposal,
            asyncFileHotParser,
            dictionarySetup,
            fixedCapacityMap,
            unmanagedSortComparer,
            hotLinqPipeline,
            csharpHotParserApi,
            structuredErrors,
            aotFriendlyPublicApi,
            monoWasmPlugin,
            allocationGate,
            trustedAudit,
            dapperBoundary,
            cliStartupHonesty,
            effectDrift
        });

        SystemsProofBuildResult BuildProof(string projectDir) => proofBuilds[projectDir];

        var zeroCopyCheck = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", zeroCopyFrameReader, "--systems-report" }));
        Assert.Equal(0, zeroCopyCheck.ExitCode);
        using (var doc = JsonDocument.Parse(zeroCopyCheck.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("warnings").GetInt32());

            var nextFrame = doc.RootElement
                .GetProperty("systemsReport")
                .GetProperty("functions")
                .EnumerateArray()
                .Single(function => function.GetProperty("name").GetString() == "NextFrame");
            Assert.True(nextFrame.GetProperty("isHot").GetBoolean());
            Assert.False(nextFrame.GetProperty("effects").GetProperty("allocates").GetBoolean());
            Assert.False(nextFrame.GetProperty("effects").GetProperty("hasImplicitTrapObligation").GetBoolean());
            Assert.False(nextFrame.GetProperty("effects").GetProperty("usesUnknownExternalCall").GetBoolean());
            Assert.True(nextFrame.GetProperty("effects").GetProperty("aotSafe").GetBoolean());
        }

        var zeroCopyBuild = BuildProof(zeroCopyFrameReader);
        Assert.Equal(0, zeroCopyBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(zeroCopyBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(zeroCopyBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var zeroCopyOutputDir = Path.Combine(zeroCopyFrameReader, "bin", "Debug", "net10.0");
        var zeroCopyAssembly = Path.Combine(zeroCopyOutputDir, "SystemsProof24ZeroCopyFrameReader.dll");
        Assert.True(File.Exists(Path.Combine(zeroCopyOutputDir, "NSharpLang.Runtime.dll")));
        var zeroCopyRun = DotnetRunner.Run($"\"{zeroCopyAssembly}\"", zeroCopyOutputDir);
        Assert.True(zeroCopyRun.ExitCode == 0,
            $"zero-copy frame reader proof failed to run\nstdout:\n{zeroCopyRun.Stdout}\nstderr:\n{zeroCopyRun.Stderr}");

        var trustedCopyBuild = BuildProof(trustedMemoryCopy);
        Assert.Equal(0, trustedCopyBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(trustedCopyBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(trustedCopyBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());

            var trustedSite = Assert.Single(perf.GetProperty("trustedSites").EnumerateArray());
            Assert.Equal("CopyExact", trustedSite.GetProperty("function").GetString());
            Assert.Equal("runtime-core", trustedSite.GetProperty("owner").GetString());
            Assert.True(trustedSite.GetProperty("hasUnsafe").GetBoolean());
        }

        var trustedCopyOutputDir = Path.Combine(trustedMemoryCopy, "bin", "Debug", "net10.0");
        var trustedCopyAssembly = Path.Combine(trustedCopyOutputDir, "SystemsProof25TrustedMemoryCopy.dll");
        Assert.True(File.Exists(Path.Combine(trustedCopyOutputDir, "NSharpLang.Runtime.dll")));
        var trustedCopyRun = DotnetRunner.Run($"\"{trustedCopyAssembly}\"", trustedCopyOutputDir);
        Assert.True(trustedCopyRun.ExitCode == 0,
            $"trusted memory copy proof failed to run\nstdout:\n{trustedCopyRun.Stdout}\nstderr:\n{trustedCopyRun.Stderr}");

        var nativeDeviceBuild = BuildProof(nativeDeviceHandle);
        Assert.Equal(0, nativeDeviceBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(nativeDeviceBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(nativeDeviceBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var nativeDeviceOutputDir = Path.Combine(nativeDeviceHandle, "bin", "Debug", "net10.0");
        var nativeDeviceAssembly = Path.Combine(nativeDeviceOutputDir, "SystemsProof26NativeDeviceHandle.dll");
        Assert.True(File.Exists(Path.Combine(nativeDeviceOutputDir, "NSharpLang.Runtime.dll")));
        AssertNativeImportHasNoManagedBody(
            nativeDeviceAssembly,
            "SystemsProofs.NativeDeviceHandle.NativeMethods",
            "Open");
        AssertNativeImportHasNoManagedBody(
            nativeDeviceAssembly,
            "SystemsProofs.NativeDeviceHandle.NativeMethods",
            "Close");

        var trustedCopyQuery = CaptureConsole(() =>
            QueryCommand.Execute(new[] { "trusted", "--project", trustedMemoryCopy }));
        Assert.Equal(0, trustedCopyQuery.ExitCode);
        using (var doc = JsonDocument.Parse(trustedCopyQuery.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var result = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("CopyExact", result.GetProperty("function").GetString());
            Assert.Equal("runtime-core", result.GetProperty("owner").GetString());
            Assert.Equal("2027-06-01", result.GetProperty("expires").GetString());
        }

        var cLibraryBuild = BuildProof(cLibraryCli);
        Assert.Equal(0, cLibraryBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(cLibraryBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(cLibraryBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var cLibraryOutputDir = Path.Combine(cLibraryCli, "bin", "Debug", "net10.0");
        AssertNativeImportHasNoManagedBody(
            Path.Combine(cLibraryOutputDir, "SystemsProof27CLibraryCli.dll"),
            "SystemsProofs.CLibraryCli.NativeHash",
            "Hash64");

        var nativeAotJsonCheck = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", nativeAotJsonCli, "--systems-report" }));
        Assert.Equal(0, nativeAotJsonCheck.ExitCode);
        using (var doc = JsonDocument.Parse(nativeAotJsonCheck.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
            Assert.Equal(6, doc.RootElement.GetProperty("summary").GetProperty("warnings").GetInt32());

            var report = doc.RootElement.GetProperty("systemsReport");
            Assert.Equal("pass", report.GetProperty("aot").GetProperty("analysis").GetString());
            Assert.True(report.GetProperty("aot").GetProperty("trimSafe").GetBoolean());
        }

        var nativeAotJsonBuild = BuildProof(nativeAotJsonCli);
        Assert.Equal(0, nativeAotJsonBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(nativeAotJsonBuild.Stderr, expectedWarnings: 6);
        using (var doc = JsonDocument.Parse(nativeAotJsonBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Equal(3, perf.GetProperty("allocationSites").EnumerateArray().Count());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("closureCaptures").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var nativeAotJsonOutputDir = Path.Combine(nativeAotJsonCli, "bin", "Debug", "net10.0");
        var nativeAotJsonAssembly = Path.Combine(nativeAotJsonOutputDir, "SystemsProof28NativeAotJsonCli.dll");
        Assert.True(File.Exists(Path.Combine(nativeAotJsonOutputDir, "NSharpLang.Runtime.dll")));
        AssertJsonContextShape(
            nativeAotJsonAssembly,
            "SystemsProofs.NativeAotJsonCli.CliJsonContext",
            "CliOptions");
        var nativeAotJsonRun = DotnetRunner.Run($"\"{nativeAotJsonAssembly}\" input.txt --verbose", nativeAotJsonOutputDir);
        Assert.True(nativeAotJsonRun.ExitCode == 0,
            $"native AOT JSON CLI proof failed to run\nstdout:\n{nativeAotJsonRun.Stdout}\nstderr:\n{nativeAotJsonRun.Stderr}");
        Assert.Equal("""{"Input":"input.txt","Verbose":true}""", nativeAotJsonRun.Stdout.Trim());

        var generatedRegexBuild = BuildProof(generatedRegexBoundary);
        Assert.Equal(0, generatedRegexBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(generatedRegexBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(generatedRegexBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSite = Assert.Single(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Equal("ParseRoute", allocationSite.GetProperty("function").GetString());
            Assert.Equal("NSYS001", allocationSite.GetProperty("code").GetString());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("closureCaptures").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var generatedRegexOutputDir = Path.Combine(generatedRegexBoundary, "bin", "Debug", "net10.0");
        var generatedRegexAssembly = Path.Combine(generatedRegexOutputDir, "SystemsProof29GeneratedRegexBoundary.dll");
        Assert.True(File.Exists(Path.Combine(generatedRegexOutputDir, "NSharpLang.Runtime.dll")));
        AssertGeneratedRegexFactoryShape(
            generatedRegexAssembly,
            "SystemsProofs.GeneratedRegexBoundary.RouteParser",
            "RouteRegex");
        var generatedRegexRun = DotnetRunner.Run($"\"{generatedRegexAssembly}\"", generatedRegexOutputDir);
        Assert.True(generatedRegexRun.ExitCode == 0,
            $"generated regex boundary proof failed to run\nstdout:\n{generatedRegexRun.Stdout}\nstderr:\n{generatedRegexRun.Stderr}");

        var coldLoggingBuild = BuildProof(coldFailureLogging);
        Assert.Equal(0, coldLoggingBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(coldLoggingBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(coldLoggingBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSite = Assert.Single(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Equal("LogColdFailure", allocationSite.GetProperty("function").GetString());
            Assert.Equal("NSYS001", allocationSite.GetProperty("code").GetString());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var coldLoggingOutputDir = Path.Combine(coldFailureLogging, "bin", "Debug", "net10.0");
        var coldLoggingAssembly = Path.Combine(coldLoggingOutputDir, "SystemsProof30ColdFailureLogging.dll");
        Assert.True(File.Exists(Path.Combine(coldLoggingOutputDir, "NSharpLang.Runtime.dll")));
        var coldLoggingRun = DotnetRunner.Run($"\"{coldLoggingAssembly}\"", coldLoggingOutputDir);
        Assert.True(coldLoggingRun.ExitCode == 0,
            $"cold failure logging proof failed to run\nstdout:\n{coldLoggingRun.Stdout}\nstderr:\n{coldLoggingRun.Stderr}");

        var metricsBuild = BuildProof(hotMetrics);
        Assert.Equal(0, metricsBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(metricsBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(metricsBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
        }

        var cacheBuild = BuildProof(cachePrewarm);
        Assert.Equal(0, cacheBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(cacheBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(cacheBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var arrayPoolBuild = BuildProof(arrayPoolFileIo);
        Assert.Equal(0, arrayPoolBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(arrayPoolBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(arrayPoolBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("poolSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("resourceSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var arrayPoolOutputDir = Path.Combine(arrayPoolFileIo, "bin", "Debug", "net10.0");
        var arrayPoolAssembly = Path.Combine(arrayPoolOutputDir, "SystemsProof33ArrayPoolFileIo.dll");
        Assert.True(File.Exists(Path.Combine(arrayPoolOutputDir, "NSharpLang.Runtime.dll")));
        var arrayPoolRun = DotnetRunner.Run($"\"{arrayPoolAssembly}\"", arrayPoolOutputDir);
        Assert.True(arrayPoolRun.ExitCode == 0,
            $"array pool file IO proof failed to run\nstdout:\n{arrayPoolRun.Stdout}\nstderr:\n{arrayPoolRun.Stderr}");

        var memoryPoolBuild = BuildProof(memoryPoolDisposal);
        Assert.Equal(0, memoryPoolBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(memoryPoolBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(memoryPoolBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("poolSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("resourceSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var memoryPoolOutputDir = Path.Combine(memoryPoolDisposal, "bin", "Debug", "net10.0");
        var memoryPoolAssembly = Path.Combine(memoryPoolOutputDir, "SystemsProof34MemoryPoolDisposal.dll");
        Assert.True(File.Exists(Path.Combine(memoryPoolOutputDir, "NSharpLang.Runtime.dll")));
        var memoryPoolRun = DotnetRunner.Run($"\"{memoryPoolAssembly}\"", memoryPoolOutputDir);
        Assert.True(memoryPoolRun.ExitCode == 0,
            $"memory pool disposal proof failed to run\nstdout:\n{memoryPoolRun.Stdout}\nstderr:\n{memoryPoolRun.Stderr}");

        var asyncFileBuild = BuildProof(asyncFileHotParser);
        Assert.Equal(0, asyncFileBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(asyncFileBuild.Stderr, expectedWarnings: 4);
        using (var doc = JsonDocument.Parse(asyncFileBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            var boundaryLeaks = perf.GetProperty("boundaryLeakSites").EnumerateArray().ToArray();
            Assert.Equal(2, boundaryLeaks.Length);
            Assert.Contains(boundaryLeaks,
                site => site.GetProperty("function").GetString() == "ReadAndCount"
                        && site.GetProperty("code").GetString() == "NSYS070");
            Assert.Contains(boundaryLeaks,
                site => site.GetProperty("function").GetString() == "Main"
                        && site.GetProperty("code").GetString() == "NSYS070");
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var asyncFileOutputDir = Path.Combine(asyncFileHotParser, "bin", "Debug", "net10.0");
        var asyncFileAssembly = Path.Combine(asyncFileOutputDir, "SystemsProof35AsyncFileHotParser.dll");
        Assert.True(File.Exists(Path.Combine(asyncFileOutputDir, "NSharpLang.Runtime.dll")));
        var asyncFileRun = DotnetRunner.Run($"\"{asyncFileAssembly}\"", asyncFileOutputDir);
        Assert.True(asyncFileRun.ExitCode == 0,
            $"async file hot parser proof failed to run\nstdout:\n{asyncFileRun.Stdout}\nstderr:\n{asyncFileRun.Stderr}");

        var dictionaryBuild = BuildProof(dictionarySetup);
        Assert.Equal(0, dictionaryBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(dictionaryBuild.Stderr, expectedWarnings: 3);
        using (var doc = JsonDocument.Parse(dictionaryBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Contains(perf.GetProperty("allocationSites").EnumerateArray(),
                site => site.GetProperty("function").GetString() == "BuildCatalog"
                        && site.GetProperty("code").GetString() == "NSYS001");
            Assert.Contains(perf.GetProperty("boundaryLeakSites").EnumerateArray(),
                site => site.GetProperty("function").GetString() == "BuildCatalog"
                        && site.GetProperty("code").GetString() == "NSYS070");
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var fixedMapBuild = BuildProof(fixedCapacityMap);
        Assert.Equal(0, fixedMapBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(fixedMapBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(fixedMapBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSite = Assert.Single(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Equal("NewMap", allocationSite.GetProperty("function").GetString());
            Assert.Equal("NSYS001", allocationSite.GetProperty("code").GetString());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var fixedMapOutputDir = Path.Combine(fixedCapacityMap, "bin", "Debug", "net10.0");
        var fixedMapAssembly = Path.Combine(fixedMapOutputDir, "SystemsProof37FixedCapacityMap.dll");
        Assert.True(File.Exists(Path.Combine(fixedMapOutputDir, "NSharpLang.Runtime.dll")));
        var fixedMapRun = DotnetRunner.Run($"\"{fixedMapAssembly}\"", fixedMapOutputDir);
        Assert.True(fixedMapRun.ExitCode == 0,
            $"fixed-capacity map proof failed to run\nstdout:\n{fixedMapRun.Stdout}\nstderr:\n{fixedMapRun.Stderr}");

        var unmanagedSortBuild = BuildProof(unmanagedSortComparer);
        Assert.Equal(0, unmanagedSortBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(unmanagedSortBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(unmanagedSortBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSite = Assert.Single(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Equal("Main", allocationSite.GetProperty("function").GetString());
            Assert.Equal("NSYS001", allocationSite.GetProperty("code").GetString());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var unmanagedSortOutputDir = Path.Combine(unmanagedSortComparer, "bin", "Debug", "net10.0");
        var unmanagedSortAssembly = Path.Combine(unmanagedSortOutputDir, "SystemsProof38UnmanagedSortComparer.dll");
        Assert.True(File.Exists(Path.Combine(unmanagedSortOutputDir, "NSharpLang.Runtime.dll")));
        var sortOpcodes = DecodeMethodOpcodeNames(unmanagedSortAssembly, "SortPair");
        Assert.Contains("constrained.", sortOpcodes);
        Assert.DoesNotContain("box", sortOpcodes);
        var unmanagedSortRun = DotnetRunner.Run($"\"{unmanagedSortAssembly}\"", unmanagedSortOutputDir);
        Assert.True(unmanagedSortRun.ExitCode == 0,
            $"unmanaged sort comparer proof failed to run\nstdout:\n{unmanagedSortRun.Stdout}\nstderr:\n{unmanagedSortRun.Stderr}");

        var hotLinqBuild = BuildProof(hotLinqPipeline);
        Assert.Equal(0, hotLinqBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(hotLinqBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(hotLinqBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSite = Assert.Single(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Equal("Main", allocationSite.GetProperty("function").GetString());
            Assert.Equal("NSYS001", allocationSite.GetProperty("code").GetString());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("closureCaptures").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var hotLinqOutputDir = Path.Combine(hotLinqPipeline, "bin", "Debug", "net10.0");
        var hotLinqAssembly = Path.Combine(hotLinqOutputDir, "SystemsProof39HotLinqPipeline.dll");
        Assert.True(File.Exists(Path.Combine(hotLinqOutputDir, "NSharpLang.Runtime.dll")));
        var hotLinqRun = DotnetRunner.Run($"\"{hotLinqAssembly}\"", hotLinqOutputDir);
        Assert.True(hotLinqRun.ExitCode == 0,
            $"hot LINQ pipeline proof failed to run\nstdout:\n{hotLinqRun.Stdout}\nstderr:\n{hotLinqRun.Stderr}");

        var parserApiBuild = BuildProof(csharpHotParserApi);
        Assert.Equal(0, parserApiBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(parserApiBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(parserApiBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        AssertCSharpConsumerCanCallParserApi(csharpHotParserApi);

        var structuredErrorsBuild = BuildProof(structuredErrors);
        Assert.Equal(0, structuredErrorsBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(structuredErrorsBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(structuredErrorsBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var structuredErrorsOutputDir = Path.Combine(structuredErrors, "bin", "Debug", "net10.0");
        var structuredErrorsAssembly = Path.Combine(structuredErrorsOutputDir, "SystemsProof41StructuredErrors.dll");
        Assert.True(File.Exists(Path.Combine(structuredErrorsOutputDir, "NSharpLang.Runtime.dll")));
        var structuredErrorsRun = DotnetRunner.Run($"\"{structuredErrorsAssembly}\"", structuredErrorsOutputDir);
        Assert.True(structuredErrorsRun.ExitCode == 0,
            $"structured errors proof failed to run\nstdout:\n{structuredErrorsRun.Stdout}\nstderr:\n{structuredErrorsRun.Stderr}");

        var aotCheck = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", aotFriendlyPublicApi, "--systems-report" }));
        Assert.Equal(0, aotCheck.ExitCode);
        Assert.True(string.IsNullOrWhiteSpace(aotCheck.Stderr));
        using (var doc = JsonDocument.Parse(aotCheck.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
            Assert.Equal(2, doc.RootElement.GetProperty("summary").GetProperty("warnings").GetInt32());

            var report = doc.RootElement.GetProperty("systemsReport");
            Assert.Equal("pass", report.GetProperty("aot").GetProperty("analysis").GetString());
            Assert.True(report.GetProperty("aot").GetProperty("trimSafe").GetBoolean());

            var normalize = report.GetProperty("functions")
                .EnumerateArray()
                .Single(function => function.GetProperty("name").GetString() == "NameApi.Normalize");
            Assert.True(normalize.GetProperty("effects").GetProperty("aotSafe").GetBoolean());
        }

        var aotBuild = BuildProof(aotFriendlyPublicApi);
        Assert.Equal(0, aotBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(aotBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(aotBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var aotOutputDir = Path.Combine(aotFriendlyPublicApi, "bin", "Debug", "net10.0");
        Assert.True(File.Exists(Path.Combine(aotOutputDir, "SystemsProof42AotFriendlyPublicApi.dll")));
        Assert.True(File.Exists(Path.Combine(aotOutputDir, "NSharpLang.Runtime.dll")));

        var monoWasmBuild = BuildProof(monoWasmPlugin);
        Assert.Equal(0, monoWasmBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(monoWasmBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(monoWasmBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Empty(perf.GetProperty("allocationSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var allocationBuild = BuildProof(allocationGate);
        Assert.Equal(0, allocationBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(allocationBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(allocationBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Contains(perf.GetProperty("allocationSites").EnumerateArray(),
                site => site.GetProperty("function").GetString() == "Main"
                        && site.GetProperty("code").GetString() == "NSYS001");
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
        }

        var trustedBuild = BuildProof(trustedAudit);
        Assert.Equal(0, trustedBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(trustedBuild.Stderr, expectedWarnings: 0);
        using (var doc = JsonDocument.Parse(trustedBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var trustedSite = Assert.Single(doc.RootElement
                .GetProperty("perfReport")
                .GetProperty("trustedSites")
                .EnumerateArray());
            Assert.Equal("UnsafeAuditSurface.WrapHandle", trustedSite.GetProperty("function").GetString());
            Assert.Equal("interop", trustedSite.GetProperty("owner").GetString());
            Assert.True(trustedSite.GetProperty("hasUnsafe").GetBoolean());
        }

        var trustedQuery = CaptureConsole(() =>
            QueryCommand.Execute(new[] { "trusted", "--project", trustedAudit }));
        Assert.Equal(0, trustedQuery.ExitCode);
        using (var doc = JsonDocument.Parse(trustedQuery.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var result = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("UnsafeAuditSurface.WrapHandle", result.GetProperty("function").GetString());
            Assert.Equal("2027-06-01", result.GetProperty("expires").GetString());
        }

        var dapperBuild = BuildProof(dapperBoundary);
        Assert.Equal(0, dapperBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(dapperBuild.Stderr, expectedWarnings: 2);
        using (var doc = JsonDocument.Parse(dapperBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            var allocationSites = perf.GetProperty("allocationSites").EnumerateArray().ToArray();
            Assert.Equal(2, allocationSites.Length);
            Assert.Contains(allocationSites,
                site => site.GetProperty("function").GetString() == "LoadFirstUser"
                        && site.GetProperty("code").GetString() == "NSYS001");
            Assert.Contains(allocationSites,
                site => site.GetProperty("function").GetString() == "Main"
                        && site.GetProperty("code").GetString() == "NSYS001");
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var dapperOutputDir = Path.Combine(dapperBoundary, "bin", "Debug", "net10.0");
        var dapperAssembly = Path.Combine(dapperOutputDir, "SystemsProof46DapperBoundary.dll");
        Assert.True(File.Exists(Path.Combine(dapperOutputDir, "NSharpLang.Runtime.dll")));
        var dapperRun = DotnetRunner.Run($"\"{dapperAssembly}\"", dapperOutputDir);
        Assert.True(dapperRun.ExitCode == 0,
            $"database boundary proof failed to run\nstdout:\n{dapperRun.Stdout}\nstderr:\n{dapperRun.Stderr}");

        var cliStartupCheck = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", cliStartupHonesty, "--systems-report" }));
        Assert.Equal(0, cliStartupCheck.ExitCode);
        using (var doc = JsonDocument.Parse(cliStartupCheck.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
            Assert.Equal(5, doc.RootElement.GetProperty("summary").GetProperty("warnings").GetInt32());

            var report = doc.RootElement.GetProperty("systemsReport");
            Assert.Equal("pass", report.GetProperty("aot").GetProperty("analysis").GetString());
            Assert.True(report.GetProperty("aot").GetProperty("trimSafe").GetBoolean());
            Assert.Contains(report.GetProperty("warmup").EnumerateArray(),
                warmup => warmup.GetString() == "SystemsProofs.CliStartupHonesty.Warmup");
        }

        var cliStartupBuild = BuildProof(cliStartupHonesty);
        Assert.Equal(0, cliStartupBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(cliStartupBuild.Stderr, expectedWarnings: 5);
        using (var doc = JsonDocument.Parse(cliStartupBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Equal(4, perf.GetProperty("allocationSites").EnumerateArray().Count());
            Assert.Empty(perf.GetProperty("delegateSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("boxingSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("dispatchSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("closureCaptures").EnumerateArray());
            Assert.Empty(perf.GetProperty("boundaryLeakSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }

        var cliStartupOutputDir = Path.Combine(cliStartupHonesty, "bin", "Debug", "net10.0");
        var cliStartupAssembly = Path.Combine(cliStartupOutputDir, "SystemsProof47CliStartupHonesty.dll");
        Assert.True(File.Exists(Path.Combine(cliStartupOutputDir, "NSharpLang.Runtime.dll")));
        AssertJsonContextShape(
            cliStartupAssembly,
            "SystemsProofs.CliStartupHonesty.StartupJsonContext",
            "StartupReport");
        var cliStartupRun = DotnetRunner.Run($"\"{cliStartupAssembly}\"", cliStartupOutputDir);
        Assert.True(cliStartupRun.ExitCode == 0,
            $"CLI startup honesty proof failed to run\nstdout:\n{cliStartupRun.Stdout}\nstderr:\n{cliStartupRun.Stderr}");
        Assert.Equal("""{"Ready":true,"Mode":"run"}""", cliStartupRun.Stdout.Trim());

        var driftBuild = BuildProof(effectDrift);
        Assert.Equal(0, driftBuild.ExitCode);
        AssertSystemsProofBuildDiagnostics(driftBuild.Stderr, expectedWarnings: 1);
        using (var doc = JsonDocument.Parse(driftBuild.Stdout))
        {
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var perf = doc.RootElement.GetProperty("perfReport");
            Assert.Contains(perf.GetProperty("allocationSites").EnumerateArray(),
                site => site.GetProperty("function").GetString() == "Main"
                        && site.GetProperty("code").GetString() == "NSYS001");
            Assert.Empty(perf.GetProperty("hotReadinessSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("implicitTrapSites").EnumerateArray());
            Assert.Empty(perf.GetProperty("aotBlockers").EnumerateArray());
        }
    }

    private sealed record SystemsProofBuildResult(
        int ExitCode,
        string Stdout,
        string Stderr,
        string AssemblyPath,
        SystemsReport SystemsReport,
        IReadOnlyList<CompilerError> Diagnostics);

    private static IReadOnlyDictionary<string, SystemsProofBuildResult> BuildSystemsProofProjects(IEnumerable<string> projectDirs)
    {
        var results = new ConcurrentDictionary<string, SystemsProofBuildResult>(StringComparer.Ordinal);
        var uniqueProjects = projectDirs.Distinct(StringComparer.Ordinal).ToArray();
        // Cap parallelism low (2): each task runs a full in-process N# compilation (MultiFileCompiler +
        // Reflection.Emit + reference resolution). The N# compiler is single-project by design and not
        // hardened for many concurrent compilations; the previous 8-way spike, layered on the already-
        // loaded product gate, intermittently failed this proof-build test (and the in-process-compiling
        // test that runs right after it in the serialized ProcessState collection) while both passed in
        // isolation. Two-way keeps the test reasonably fast without the resource/contention spike.
        var options = new ParallelOptions
        {
            MaxDegreeOfParallelism = Math.Max(1, Math.Min(2, Environment.ProcessorCount))
        };

        Parallel.ForEach(uniqueProjects, options, projectDir =>
        {
            results[projectDir] = BuildSystemsProofProject(projectDir);
        });

        return results;
    }

    private static SystemsProofBuildResult BuildSystemsProofProject(string projectDir)
    {
        var projectRoot = Path.GetFullPath(projectDir);
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var configuration = "Debug";
        var outputDir = CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);
        var references = CompilationReferenceResolver.AddResolvedDllReferences(
            projectRoot,
            config,
            new ReferenceResolutionOptions(Configuration: configuration, Quiet: true));

        Directory.CreateDirectory(outputDir);
        var assemblyName = CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config);
        var outputPath = Path.Combine(outputDir, $"{assemblyName}.dll");
        var sourceFiles = config.GetSourceFiles(projectRoot, includeTests: false);
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        var result = compiler.CompileToIlAssembly(assemblyName, outputPath, validateStrictLint: true);

        if (result.Success && !string.IsNullOrWhiteSpace(result.OutputAssemblyPath))
        {
            if (string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
            {
                CompilationArtifacts.WriteRuntimeConfig(config, result.OutputAssemblyPath);
            }

            references.CopyRuntimeAssets(outputDir);
        }

        var diagnostics = result.Errors.ToArray();
        return new SystemsProofBuildResult(
            result.Success ? 0 : 1,
            BuildSystemsProofPerfReportJson(projectRoot, result.Success, compiler),
            string.Join(Environment.NewLine, diagnostics.Select(error => error.Format())),
            result.OutputAssemblyPath ?? outputPath,
            compiler.SystemsReport,
            diagnostics);
    }

    private static string BuildSystemsProofPerfReportJson(string projectRoot, bool ok, MultiFileCompiler compiler)
    {
        var sites = compiler.SystemsReport.Findings
            .Select(finding => new OutputFormatter.PerfReportSite(
                finding.Code,
                finding.Effect,
                finding.File,
                finding.Line,
                finding.Column,
                finding.Message,
                finding.Function,
                finding.Suggestion))
            .ToArray();

        return OutputFormatter.BuildPerfReportToJson(
            projectRoot,
            ok,
            aotBlockers: compiler.AotBlockers.Select(ToPerfReportBlocker).ToArray(),
            allocationSites: sites.Where(site => site.Effect is "allocation").ToArray(),
            delegateSites: sites.Where(site => site.Effect is "delegate").ToArray(),
            boxingSites: sites.Where(site => site.Effect is "boxing").ToArray(),
            dispatchSites: sites.Where(site => site.Effect is "dispatch").ToArray(),
            closureCaptures: sites.Where(site => site.Effect is "closure").ToArray(),
            poolSites: sites.Where(site => site.Effect is "pool").ToArray(),
            resourceSites: sites.Where(site => site.Effect is "resource").ToArray(),
            boundaryLeakSites: sites.Where(site => site.Effect is "boundaryLeak").ToArray(),
            hotReadinessSites: sites.Where(site => site.Effect is "hotReadiness").ToArray(),
            implicitTrapSites: sites.Where(site => site.Effect is "implicitTrap").ToArray(),
            trustedSites: compiler.SystemsReport.TrustedSites
                .Select(site => new OutputFormatter.PerfReportTrustedSite(
                    site.Function,
                    site.File,
                    site.Line,
                    site.Column,
                    site.Owner,
                    site.Review,
                    site.Expires,
                    site.HasUnsafe,
                    site.BodyStatementCount))
                .ToArray());
    }

    private static OutputFormatter.PerfReportAotBlocker ToPerfReportBlocker(AotBlocker blocker)
        => new(
            Code: $"NL{(int)blocker.DiagnosticCode:D3}",
            Kind: blocker.Kind.ToString(),
            File: blocker.File,
            Line: blocker.Line,
            Column: blocker.Column,
            Construct: blocker.Construct,
            EnclosingBoundary: blocker.EnclosingBoundary.ToString(),
            EnclosingDeclaration: blocker.EnclosingDeclaration,
            OnPublicSurface: blocker.IsOnPublicSurface);

    private static void AssertSystemsProofBuildDiagnostics(string stderr, int expectedWarnings)
    {
        var normalized = StripAnsi(stderr);
        Assert.DoesNotContain("-- ERROR", normalized, StringComparison.Ordinal);
        Assert.Equal(expectedWarnings, Regex.Matches(normalized, "-- WARNING").Count);
    }

    private static string StripAnsi(string value)
        => Regex.Replace(value, "\u001B\\[[0-?]*[ -/]*[@-~]", string.Empty);

    private static string[] DecodeMethodOpcodeNames(string assemblyPath, string methodName)
    {
        Assert.True(File.Exists(assemblyPath), $"Expected proof assembly at {assemblyPath}");

        var outputDir = Path.GetDirectoryName(assemblyPath)!;
        var loadContext = new AssemblyLoadContext($"SystemsProofIlShape_{Guid.NewGuid():N}", isCollectible: true);
        loadContext.Resolving += (context, assemblyName) =>
        {
            var localAssemblyPath = Path.Combine(outputDir, $"{assemblyName.Name}.dll");
            return File.Exists(localAssemblyPath) ? context.LoadFromAssemblyPath(localAssemblyPath) : null;
        };

        try
        {
            using var stream = File.OpenRead(assemblyPath);
            var assembly = loadContext.LoadFromStream(stream);
            var method = assembly
                .GetTypes()
                .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance))
                .SingleOrDefault(candidate => candidate.Name == methodName);
            Assert.NotNull(method);
            return ILShapeInspector.Decode(method!).Select(instruction => instruction.OpCode.Name ?? string.Empty).ToArray();
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static void AssertGeneratedRegexFactoryShape(string assemblyPath, string typeName, string methodName)
    {
        Assert.True(File.Exists(assemblyPath), $"Expected proof assembly at {assemblyPath}");

        var outputDir = Path.GetDirectoryName(assemblyPath)!;
        var loadContext = new AssemblyLoadContext($"SystemsProofGeneratedRegex_{Guid.NewGuid():N}", isCollectible: true);
        loadContext.Resolving += (context, assemblyName) =>
        {
            var localAssemblyPath = Path.Combine(outputDir, $"{assemblyName.Name}.dll");
            return File.Exists(localAssemblyPath) ? context.LoadFromAssemblyPath(localAssemblyPath) : null;
        };

        try
        {
            using var stream = File.OpenRead(assemblyPath);
            var assembly = loadContext.LoadFromStream(stream);
            var type = assembly.GetType(typeName);
            Assert.NotNull(type);
            var method = type!.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            Assert.Contains(method!.GetCustomAttributesData(), attribute =>
                attribute.AttributeType.FullName == "System.Text.RegularExpressions.GeneratedRegexAttribute");

            var first = Assert.IsType<Regex>(method.Invoke(null, null));
            var second = Assert.IsType<Regex>(method.Invoke(null, null));
            Assert.Same(first, second);
            Assert.True(first.IsMatch("GET /health"));
            Assert.False(first.IsMatch("DELETE /health"));

            var cacheField = Assert.Single(type.GetFields(BindingFlags.NonPublic | BindingFlags.Static),
                field => field.FieldType == typeof(Regex)
                         && field.Name.Contains("GeneratedRegex", StringComparison.Ordinal));
            Assert.Same(first, cacheField.GetValue(null));
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static void AssertJsonContextShape(
        string assemblyPath,
        string contextTypeName,
        string jsonTypeInfoPropertyName)
    {
        Assert.True(File.Exists(assemblyPath), $"Expected proof assembly at {assemblyPath}");

        var outputDir = Path.GetDirectoryName(assemblyPath)!;
        var loadContext = new AssemblyLoadContext($"SystemsProofJsonContext_{Guid.NewGuid():N}", isCollectible: true);
        loadContext.Resolving += (context, assemblyName) =>
        {
            var localAssemblyPath = Path.Combine(outputDir, $"{assemblyName.Name}.dll");
            return File.Exists(localAssemblyPath) ? context.LoadFromAssemblyPath(localAssemblyPath) : null;
        };

        try
        {
            using var stream = File.OpenRead(assemblyPath);
            var assembly = loadContext.LoadFromStream(stream);
            var contextType = assembly.GetType(contextTypeName);
            Assert.NotNull(contextType);
            Assert.True(typeof(JsonSerializerContext).IsAssignableFrom(contextType));
            Assert.True(typeof(IJsonTypeInfoResolver).IsAssignableFrom(contextType));

            var defaultProperty = contextType!.GetProperty(
                "Default",
                BindingFlags.Public | BindingFlags.Static);
            Assert.NotNull(defaultProperty);
            Assert.Equal(contextType, defaultProperty!.PropertyType);
            var contextInstance = defaultProperty.GetValue(null);
            Assert.NotNull(contextInstance);

            var jsonTypeInfoProperty = contextType.GetProperty(
                jsonTypeInfoPropertyName,
                BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(jsonTypeInfoProperty);
            Assert.True(jsonTypeInfoProperty!.PropertyType.IsGenericType);
            Assert.Equal(typeof(JsonTypeInfo<>), jsonTypeInfoProperty.PropertyType.GetGenericTypeDefinition());

            var typeInfo = Assert.IsAssignableFrom<JsonTypeInfo>(jsonTypeInfoProperty.GetValue(contextInstance));
            Assert.Equal(contextInstance, typeInfo.OriginatingResolver);

            var getTypeInfo = contextType.GetMethod(
                nameof(JsonSerializerContext.GetTypeInfo),
                BindingFlags.Public | BindingFlags.Instance,
                binder: null,
                new[] { typeof(Type) },
                modifiers: null);
            Assert.NotNull(getTypeInfo);
            Assert.NotSame(typeof(JsonSerializerContext), getTypeInfo!.DeclaringType);

            Assert.DoesNotContain(
                assembly.GetTypes(),
                type => type.FullName?.Contains("__NSharpJson", StringComparison.Ordinal) == true);
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static void AssertNativeImportHasNoManagedBody(string assemblyPath, string typeName, string methodName)
    {
        Assert.True(File.Exists(assemblyPath), $"Expected proof assembly at {assemblyPath}");

        var outputDir = Path.GetDirectoryName(assemblyPath)!;
        var loadContext = new AssemblyLoadContext($"SystemsProofNativeImport_{Guid.NewGuid():N}", isCollectible: true);
        loadContext.Resolving += (context, assemblyName) =>
        {
            var localAssemblyPath = Path.Combine(outputDir, $"{assemblyName.Name}.dll");
            return File.Exists(localAssemblyPath) ? context.LoadFromAssemblyPath(localAssemblyPath) : null;
        };

        try
        {
            using var stream = File.OpenRead(assemblyPath);
            var assembly = loadContext.LoadFromStream(stream);
            var type = assembly.GetType(typeName);
            Assert.NotNull(type);
            var method = type!.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            Assert.Null(method!.GetMethodBody());
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static void AssertCSharpConsumerCanCallParserApi(string proofDir)
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-systems-csharp-consumer-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);

            var nsharpProjectDir = Path.Combine(tempDir, "Proof");
            Directory.CreateDirectory(nsharpProjectDir);
            File.Copy(Path.Combine(proofDir, "Program.nl"), Path.Combine(nsharpProjectDir, "Program.nl"));
            File.Copy(Path.Combine(proofDir, "project.yml"), Path.Combine(nsharpProjectDir, "project.yml"));
            File.WriteAllText(Path.Combine(nsharpProjectDir, "Proof.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");

            File.WriteAllText(Path.Combine(tempDir, "Consumer.csproj"), $$"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="{{Path.Combine(nsharpProjectDir, "Proof.csproj")}}" />
  </ItemGroup>
</Project>
""");

            File.WriteAllText(Path.Combine(tempDir, "Program.cs"), """
using System;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;
using SystemsProofs.CsharpHotParserApi;

AssemblyLoadContext.Default.Resolving += (_, assemblyName) =>
{
    if (assemblyName.Name != "SystemsProof40CsharpHotParserApi")
    {
        return null;
    }

    var localAssemblyPath = Path.Combine(AppContext.BaseDirectory, "SystemsProof40CsharpHotParserApi.dll");
    return File.Exists(localAssemblyPath)
        ? AssemblyLoadContext.Default.LoadFromAssemblyPath(localAssemblyPath)
        : null;
};

var ok = PacketApi.ParseHeader(new byte[] { 1, 0, 5, 0, 0, 0 });
if (!ok.TryGetOk(out var header))
{
    throw new InvalidOperationException($"expected ok, got {ok}");
}

if (header.Version != 1 || header.Length != 5)
{
    throw new InvalidOperationException($"bad header {header.Version}:{header.Length}");
}

var err = PacketApi.ParseHeader(new byte[] { 1, 0 });
if (!err.TryGetErr(out var error) || error != HeaderError.Short)
{
    throw new InvalidOperationException($"expected Short, got {err}");
}

Console.WriteLine($"{header.Version}:{header.Length}:{error}");
""");

            var restore = DotnetRunner.Run("restore --disable-build-servers", tempDir);
            Assert.True(restore.ExitCode == 0,
                $"dotnet restore failed\nstdout:\n{restore.Stdout}\nstderr:\n{restore.Stderr}");

            var run = DotnetRunner.Run("run --no-restore --disable-build-servers", tempDir);
            var consumerOutputDir = Path.Combine(tempDir, "bin", "Debug", "net10.0");
            var consumerOutput = Directory.Exists(consumerOutputDir)
                ? string.Join(Environment.NewLine, Directory.GetFiles(consumerOutputDir).OrderBy(path => path, StringComparer.Ordinal).Select(Path.GetFileName))
                : "<missing>";
            Assert.True(run.ExitCode == 0,
                $"dotnet run failed\nstdout:\n{run.Stdout}\nstderr:\n{run.Stderr}\noutput:\n{consumerOutput}");
            Assert.Equal("1:5:Short", run.Stdout.Trim());
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

    [Fact]
    public void SystemsBenchmark_UsesBenchmarkDotNetForPerformanceAndAllocationCoverage()
    {
        var root = FindRepoRoot();
        var benchmarkClasses = new[]
        {
            "SystemsFastGateBenchmarks",
            "SystemsHotPathBenchmarks",
            "SystemsSpanHandoffBenchmarks",
            "SystemsCallerBufferBenchmarks",
            "SystemsResultBenchmarks",
            "SystemsPooledBoundaryBenchmarks",
            "SystemsCombinationBenchmarks",
        };

        foreach (var benchmarkClass in benchmarkClasses)
        {
            var benchmarkPath = Path.Combine(root, "benchmarks", $"{benchmarkClass}.cs");
            var source = File.ReadAllText(benchmarkPath);

            Assert.Contains($"class {benchmarkClass}", source, StringComparison.Ordinal);
            Assert.Contains("[MemoryDiagnoser]", source, StringComparison.Ordinal);
            Assert.Contains("[Benchmark(Baseline = true", source, StringComparison.Ordinal);
            Assert.Contains("[Benchmark", source, StringComparison.Ordinal);
        }

        var fastGateBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsFastGateBenchmarks.cs"));
        Assert.Contains("GateScenario.HotLoops", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("GateScenario.SpanHandoff", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("GateScenario.CallerBuffers", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("GateScenario.ResultAbi", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("GateScenario.PooledBoundary", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("GateScenario.HotResultCombinations", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("switch (Scenario)", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("OperationsPerInvoke = InnerOperations", fastGateBenchmark, StringComparison.Ordinal);
        // The gate aggregates per-workload (apples-to-apples) so it measures codegen, not loop
        // fusion (H8). Both sides must run the same distinct per-workload functions, NOT the fused
        // *All() helpers.
        Assert.Contains("benchmark.NSharp() : benchmark.CSharp()", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("foreach (var workload in HotWorkloads)", fastGateBenchmark, StringComparison.Ordinal);
        Assert.DoesNotContain("benchmark.NSharpAll() : benchmark.CSharpAll()", fastGateBenchmark, StringComparison.Ordinal);
        Assert.Contains("RunCombination(_combination64", fastGateBenchmark, StringComparison.Ordinal);

        var compiledMethodSupport = File.ReadAllText(Path.Combine(root, "benchmarks", "NSharpCompiledMethod.cs"));
        Assert.Contains("ConcurrentDictionary<string, Lazy<Type>>", compiledMethodSupport, StringComparison.Ordinal);
        Assert.Contains("CompileProgram(cachedSource)", compiledMethodSupport, StringComparison.Ordinal);

        var hotPathBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsHotPathBenchmarks.cs"));
        Assert.Contains("HotPathWorkload.Checksum", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.ScoreFrame", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.ScanTag", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.CountAscii", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.MinMaxDelta", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.RollingHash", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.ParseEightDigits", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("HotPathWorkload.CountTransitions", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("func allHot(values: int[], tag: int): int", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("public int NSharpAll() => _allHot(_values, _tag)", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("value >= 32 && value <= 126", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("parseOk := true", hotPathBenchmark, StringComparison.Ordinal);
        Assert.Contains("NSharpCompiledMethod.Bind<Func<int[], int>>", hotPathBenchmark, StringComparison.Ordinal);

        var spanHandoffBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsSpanHandoffBenchmarks.cs"));
        Assert.Contains("SpanHandoffWorkload.SumSpan", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.CountEven", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.CopyUntilNegative", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.ReverseCopy", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.ArrayToSpanCaller", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.CopyPositive", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("SpanHandoffWorkload.ChecksumAndCopy", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("NSharpCompiledMethod.Bind<ReadOnlySpanIntDelegate>", spanHandoffBenchmark, StringComparison.Ordinal);
        Assert.Contains("NSharpCompiledMethod.Bind<SpanCopyDelegate>", spanHandoffBenchmark, StringComparison.Ordinal);

        var callerBufferBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsCallerBufferBenchmarks.cs"));
        Assert.Contains("CallerBufferWorkload.CopyPositive", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.WriteFrame", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.Transform", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.PrefixSum", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.CompactEven", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.FilterAndScale", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("CallerBufferWorkload.PairSums", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("func allCallerBuffers(src: int[], dst: int[]): int", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("public int NSharpAll() => _allCallerBuffers(_source, _destination)", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("positiveWritten := 0", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("value := src[i]", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("if (value & 1) == 0", callerBufferBenchmark, StringComparison.Ordinal);
        Assert.Contains("if value > 0", callerBufferBenchmark, StringComparison.Ordinal);

        var resultBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsResultBenchmarks.cs"));
        Assert.Contains("ResultWorkload.SumOkValues", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.SumErrValues", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.BranchAndCopy", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.AllOkFastPath", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.AllErrFastPath", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.FirstErrOrSum", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ResultWorkload.ValidateAllOkAscending", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("private const int InnerOperations = 16", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("OperationsPerInvoke = InnerOperations", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("RuntimeResult", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("OkValueUnchecked", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("ErrValueUnchecked", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("CSharpTaggedResult<int, int>", resultBenchmark, StringComparison.Ordinal);
        Assert.DoesNotContain("MatchDelegate", resultBenchmark, StringComparison.Ordinal);

        var pooledBoundaryBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsPooledBoundaryBenchmarks.cs"));
        Assert.Contains("PooledBoundaryWorkload.CountNonZero", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.ScorePooledFrame", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.ClampAndScore", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.FindFirstZero", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.ClampWindow", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.SumPositive", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("PooledBoundaryWorkload.ZeroOdd", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("private const int InnerOperations = 8", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("OperationsPerInvoke = InnerOperations", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("func allPooled(values: int[], len: int): int", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("_allPooled(buffer, _seed.Length)", pooledBoundaryBenchmark, StringComparison.Ordinal);
        Assert.Contains("(values[i] & 1) != 0", pooledBoundaryBenchmark, StringComparison.Ordinal);

        var combinationBenchmark = File.ReadAllText(Path.Combine(root, "benchmarks", "SystemsCombinationBenchmarks.cs"));
        Assert.Contains("CombinationWorkload.ScanDigitsResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.WriteChecksumResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.CopyDigitsResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.ScanAndChecksumResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.CopyPositiveChecksumResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.ScanThenChecksumResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.ScanThenCopyDigitsResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.ChecksumThenFrameResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.CopyDigitsThenFrameResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("CombinationWorkload.CopyPositiveThenFrameResult", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Params(64, 4096)]", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("private const int InnerOperations = 8", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("OperationsPerInvoke = InnerOperations", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("func allCombinations(digits: int[], payload: int[], destination: int[], scratch: int[], digitsLen: int, payloadLen: int): int", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int, int, int>>(Source, \"allCombinations\")", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("public int CSharpAll()", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("public int NSharpAll()", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("=> _allCombinations(_digits, _payload, _destination, _scratch, _digits.Length, _payload.Length)", combinationBenchmark, StringComparison.Ordinal);
        Assert.Contains("result.IsOk ? result.OkValueUnchecked : 0", combinationBenchmark, StringComparison.Ordinal);

        var script = File.ReadAllText(Path.Combine(root, "scripts", "benchmark-systems.sh"));
        Assert.Contains("MODE=\"${NSHARP_SYSTEMS_BENCH_MODE:-gate}\"", script, StringComparison.Ordinal);
        Assert.Contains("FILTER=\"*SystemsFastGateBenchmarks*\"", script, StringComparison.Ordinal);
        Assert.Contains("ITERATION_COUNT=\"${NSHARP_SYSTEMS_BENCH_ITERATION_COUNT:-16}\"", script, StringComparison.Ordinal);
        Assert.Contains("ITERATION_TIME=\"${NSHARP_SYSTEMS_BENCH_ITERATION_TIME:-250}\"", script, StringComparison.Ordinal);
        Assert.Contains("--iterationTime \"$ITERATION_TIME\"", script, StringComparison.Ordinal);
        Assert.Contains("rm -rf \"$ARTIFACTS/results\"", script, StringComparison.Ordinal);
        Assert.Contains("BenchmarkRun-*.log", script, StringComparison.Ordinal);
        Assert.Contains("Systems N# BenchmarkDotNet coverage:", script, StringComparison.Ordinal);
        Assert.Contains("Systems N# BenchmarkDotNet allocation gate: all rows allocated 0 B", script, StringComparison.Ordinal);
        Assert.Contains("Systems N# BenchmarkDotNet worst throughput ratios (median):", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsFastGateBenchmarks\", \"NSharp\"): 6", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsHotPathBenchmarks\", \"NSharp\"): 16", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsSpanHandoffBenchmarks\", \"NSharp\"): 14", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsCallerBufferBenchmarks\", \"NSharp\"): 14", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsResultBenchmarks\", \"RuntimeResult\"): 14", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsPooledBoundaryBenchmarks\", \"NSharp\"): 14", script, StringComparison.Ordinal);
        Assert.Contains("(\"SystemsCombinationBenchmarks\", \"NSharp\"): 20", script, StringComparison.Ordinal);
        Assert.Contains("key[1] in (\"NSharp\", \"RuntimeResult\")", script, StringComparison.Ordinal);
        Assert.Contains("RATIO_TOLERANCE = 1.05", script, StringComparison.Ordinal);
        Assert.Contains("allocated != 0", script, StringComparison.Ordinal);
        // The throughput gate compares MEDIANs (robust to the thermal/load tail that only inflates the
        // mean), sourced from BenchmarkDotNet's full JSON report. Pin the median wiring so the gate
        // cannot silently regress back to a mean-based, load-flaky comparison.
        Assert.Contains("--exporters json csv", script, StringComparison.Ordinal);
        Assert.Contains("BytesAllocatedPerOperation", script, StringComparison.Ordinal);
        Assert.Contains("gating statistic: median", script, StringComparison.Ordinal);
        Assert.Contains("ratio = median_ns / baseline_median", script, StringComparison.Ordinal);
        Assert.Contains("ratio > limit", script, StringComparison.Ordinal);

        var testAllCore = File.ReadAllText(Path.Combine(root, "tests", "scripts", "test-all-core.sh"));
        Assert.Contains("Step 3a: Systems BenchmarkDotNet Gate", testAllCore, StringComparison.Ordinal);
        Assert.Contains("scripts/benchmark-systems.sh", testAllCore, StringComparison.Ordinal);
    }

    [Fact]
    public void SystemsPolicyAttributes_AreCompilerOnlyAndHotEmitsJitImplementationFlags()
    {
        var source = """
[hot]
func Run(): int {
    return 1
}
""";

        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"SystemsPolicyAttributes_{Guid.NewGuid():N}.dll");
        var assemblyName = $"SystemsPolicyAttributes_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath);
            compiler.Compile();

            loadContext = new AssemblyLoadContext($"SystemsPolicyAttributes_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(File.ReadAllBytes(outputPath));
            var assembly = loadContext.LoadFromStream(stream);
            var method = assembly.GetType("Program")!.GetMethod("Run", BindingFlags.Public | BindingFlags.Static)!;

            Assert.DoesNotContain(method.CustomAttributes,
                attribute => attribute.AttributeType.Name.Contains("hot", StringComparison.OrdinalIgnoreCase));
            var implementationFlags = method.GetMethodImplementationFlags();
            Assert.True(
                implementationFlags.HasFlag(MethodImplAttributes.AggressiveInlining),
                $"Expected [hot] to emit {MethodImplAttributes.AggressiveInlining}, got {implementationFlags}.");
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    [Fact]
    public void StackallocExpression_CompilesToSpan()
    {
        var result = CompileAndInvoke("""
import System

func Run(): int {
    scratch := stackalloc int[4]
    return scratch.Length
}
""", "Run");

        Assert.Equal(4, result);
    }

    [Fact]
    public void ArrayCanFlowToReadOnlySpanParameter()
    {
        var result = CompileAndInvoke("""
import System

func Sum(values: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < values.Length; i++ {
        total = total + values[i]
    }
    return total
}

func Run(): int {
    values := [1, 2, 3]
    return Sum(values)
}
""", "Run");

        Assert.Equal(6, result);
    }

    [Fact]
    public void SpanPtrAndBufferMemoryCopy_CompileAndCopyBytes()
    {
        var result = CompileAndInvoke("""
import System

[memory(safe)]
[trusted(reason: "length is checked against both spans", owner: "runtime-core", review: "SYS-25")]
[hot]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): int {
    if len < 0 || len > dst.Length || len > src.Length {
        return -1
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    }

    return len
}

func Run(): int {
    src := new byte[4]
    src[0] = (byte)1
    src[1] = (byte)2
    src[2] = (byte)3
    src[3] = (byte)4
    dst := new byte[4]
    copied := CopyExact(dst, src, 4)
    return copied + (int)dst[0] + (int)dst[1] + (int)dst[2] + (int)dst[3]
}
""", "Run");

        Assert.Equal(14, result);
    }

    private static SystemsReport Analyze(string source, string profile = "default", string mode = "strict", Action<ProjectConfig>? configure = null)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-analysis-{Guid.NewGuid():N}");
        var file = Path.Combine(projectRoot, "Program.nl");
        var unit = Parse(source, file);

        var config = ProjectFileParser.CreateDefault("SystemsTest");
        config.Language.Profile = profile;
        config.Language.Systems.Mode = mode;
        configure?.Invoke(config);

        return new SystemsAnalyzer(projectRoot, config).Analyze(
            new Dictionary<string, CompilationUnit> { [file] = unit },
            new PerformanceFactStore());
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

            var file = Path.Combine(projectRoot, "Program.nl");
            var unit = Parse(source, file);
            var config = ProjectFileParser.CreateDefault("SystemsSidecar");
            config.Language.Profile = "systems";
            config.Language.Systems.HotSummaryFiles.Add("external.hotsummary.json");
            config.Language.Systems.AllowHotSidecars = allowHotSidecars;

            return new SystemsAnalyzer(projectRoot, config).Analyze(
                new Dictionary<string, CompilationUnit> { [file] = unit },
                new PerformanceFactStore());
        }
        finally
        {
            Directory.Delete(projectRoot, recursive: true);
        }
    }

    private static CompilationUnit Parse(string source, string file = "Program.nl")
    {
        var lexer = new Lexer(source, file);
        var parser = new Parser(lexer.Tokenize(), file, source);
        var result = parser.ParseCompilationUnit();

        Assert.NotNull(result.CompilationUnit);
        Assert.DoesNotContain(result.Errors, error => error.Severity == ErrorSeverity.Error);
        return result.CompilationUnit!;
    }

    private static object? CompileAndInvoke(string source, string functionName)
    {
        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"SystemsCompile_{Guid.NewGuid():N}.dll");
        var assemblyName = $"SystemsCompile_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath);
            compiler.Compile();

            loadContext = new AssemblyLoadContext($"SystemsCompile_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(File.ReadAllBytes(outputPath));
            var assembly = loadContext.LoadFromStream(stream);
            var method = assembly.GetType("Program")!.GetMethod(functionName, BindingFlags.Public | BindingFlags.Static)!;
            return method.Invoke(null, null);
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static object? CompileProjectAndInvoke(string source, string functionName)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-project-{Guid.NewGuid():N}");
        Directory.CreateDirectory(projectRoot);
        var programPath = Path.Combine(projectRoot, "Program.nl");
        var outputPath = Path.Combine(projectRoot, "bin", "SystemsCompile.dll");
        AssemblyLoadContext? loadContext = null;

        try
        {
            File.WriteAllText(programPath, source);
            var config = ProjectFileParser.CreateDefault("SystemsCompile");
            config.OutputType = "library";
            config.TargetFramework = "net10.0";

            var compiler = new MultiFileCompiler(new[] { programPath }, projectRoot, config);
            var result = compiler.CompileToIlAssembly("SystemsCompile", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(FormatCompilerError)));
            Assert.NotNull(result.OutputAssemblyPath);

            loadContext = new AssemblyLoadContext($"SystemsCompile_{Guid.NewGuid():N}", isCollectible: true);
            var assembly = loadContext.LoadFromAssemblyPath(result.OutputAssemblyPath!);
            var method = assembly.GetTypes()
                .Select(type => type.GetMethod(functionName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static))
                .FirstOrDefault(method => method != null);
            Assert.NotNull(method);
            return method.Invoke(null, null);
        }
        finally
        {
            loadContext?.Unload();
            if (Directory.Exists(projectRoot))
            {
                Directory.Delete(projectRoot, recursive: true);
            }
        }
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
