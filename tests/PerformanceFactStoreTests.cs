using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for PerformanceFactStore — testing the data structure directly.
/// The store is a pure data model with no behavior wired into emission.
/// </summary>
public class PerformanceFactStoreTests
{
    private static PerformanceFacts MakeFacts(
        EscapeKind escape = EscapeKind.LocalOnly,
        AllocationKind allocation = AllocationKind.None,
        DispatchKind dispatch = DispatchKind.Direct) =>
        new(
            escape,
            CaptureKind.None,
            allocation,
            dispatch,
            ValueLayoutKind.Struct,
            AotSafetyKind.NoReflection);

    // ── Record + Lookup ──────────────────────────────────────────────────

    [Fact]
    public void Record_CanLookUpByPosition()
    {
        var store = new PerformanceFactStore();
        var facts = MakeFacts(EscapeKind.Returned, AllocationKind.Closure, DispatchKind.Interface);

        store.Record("a.nl", 3, 10, facts);

        var result = store.Lookup("a.nl", 3, 10);

        Assert.NotNull(result);
        Assert.Equal(EscapeKind.Returned, result!.Escape);
        Assert.Equal(AllocationKind.Closure, result.Allocation);
        Assert.Equal(DispatchKind.Interface, result.Dispatch);
    }

    [Fact]
    public void Lookup_ReturnsNull_WhenNoFactsRecorded()
    {
        var store = new PerformanceFactStore();

        Assert.Null(store.Lookup("a.nl", 1, 1));
    }

    [Fact]
    public void Lookup_DistinguishesByFile()
    {
        var store = new PerformanceFactStore();
        store.Record("a.nl", 1, 1, MakeFacts(EscapeKind.LocalOnly));
        store.Record("b.nl", 1, 1, MakeFacts(EscapeKind.PublicAbi));

        Assert.Equal(EscapeKind.LocalOnly, store.Lookup("a.nl", 1, 1)!.Escape);
        Assert.Equal(EscapeKind.PublicAbi, store.Lookup("b.nl", 1, 1)!.Escape);
    }

    [Fact]
    public void Lookup_TreatsNullFileAsItsOwnKey()
    {
        var store = new PerformanceFactStore();
        store.Record(null, 5, 2, MakeFacts(EscapeKind.Stored));

        Assert.NotNull(store.Lookup(null, 5, 2));
        Assert.Null(store.Lookup("a.nl", 5, 2));
    }

    [Fact]
    public void Record_LastWriteWins()
    {
        var store = new PerformanceFactStore();
        store.Record("a.nl", 2, 4, MakeFacts(EscapeKind.LocalOnly));
        store.Record("a.nl", 2, 4, MakeFacts(EscapeKind.ReflectionBoundary));

        Assert.Equal(EscapeKind.ReflectionBoundary, store.Lookup("a.nl", 2, 4)!.Escape);
        Assert.Equal(1, store.Count);
    }

    [Fact]
    public void Default_IsMostConservative()
    {
        var d = PerformanceFacts.Default;

        Assert.Equal(EscapeKind.LocalOnly, d.Escape);
        Assert.Equal(CaptureKind.None, d.Capture);
        Assert.Equal(AllocationKind.None, d.Allocation);
        Assert.Equal(DispatchKind.Direct, d.Dispatch);
        Assert.Equal(AotSafetyKind.NoReflection, d.AotSafety);
    }

    // ── Merge ────────────────────────────────────────────────────────────

    [Fact]
    public void Merge_CombinesNonOverlappingPositions()
    {
        var a = new PerformanceFactStore();
        a.Record("a.nl", 1, 1, MakeFacts(EscapeKind.LocalOnly));

        var b = new PerformanceFactStore();
        b.Record("b.nl", 2, 2, MakeFacts(EscapeKind.Returned));

        a.Merge(b);

        Assert.Equal(2, a.Count);
        Assert.Equal(EscapeKind.LocalOnly, a.Lookup("a.nl", 1, 1)!.Escape);
        Assert.Equal(EscapeKind.Returned, a.Lookup("b.nl", 2, 2)!.Escape);
    }

    [Fact]
    public void Merge_OtherStoreWinsOnCollision()
    {
        var a = new PerformanceFactStore();
        a.Record("a.nl", 1, 1, MakeFacts(EscapeKind.LocalOnly, AllocationKind.None));

        var b = new PerformanceFactStore();
        b.Record("a.nl", 1, 1, MakeFacts(EscapeKind.PublicAbi, AllocationKind.Boxing));

        a.Merge(b);

        Assert.Equal(1, a.Count);
        var merged = a.Lookup("a.nl", 1, 1);
        Assert.Equal(EscapeKind.PublicAbi, merged!.Escape);
        Assert.Equal(AllocationKind.Boxing, merged.Allocation);
    }

    [Fact]
    public void Merge_DoesNotMutateOtherStore()
    {
        var a = new PerformanceFactStore();
        a.Record("a.nl", 1, 1, MakeFacts());

        var b = new PerformanceFactStore();
        b.Record("b.nl", 2, 2, MakeFacts());

        a.Merge(b);

        Assert.Equal(1, b.Count);
        Assert.Null(b.Lookup("a.nl", 1, 1));
    }

    [Fact]
    public void All_ExposesEveryRecordedPosition()
    {
        var store = new PerformanceFactStore();
        store.Record("a.nl", 1, 1, MakeFacts());
        store.Record("a.nl", 2, 2, MakeFacts());

        Assert.Equal(2, store.All.Count);
        Assert.True(store.All.ContainsKey(("a.nl", 1, 1)));
        Assert.True(store.All.ContainsKey(("a.nl", 2, 2)));
    }
}
