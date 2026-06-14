using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

[Collection("ProcessState")]
public class SoaRecordILShapeTests
{
    private const string ExperimentalSoaEnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";

    [Fact]
    public void RowProjection_UsesColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func read(nodes: NodeTable, row: int): int {
                return nodes[row].kind + nodes[row].start
            }

            func write(nodes: NodeTable, row: int): int {
                nodes[row].kind = 3
                nodes[row].start = nodes[row].kind + 4
                return nodes[row].start
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var read = ILShapeInspector.GetProgramMethod(assembly, "read");
            var write = ILShapeInspector.GetProgramMethod(assembly, "write");

            AssertNoAllocationOrDispatch(read);
            AssertNoAllocationOrDispatch(write);

            Assert.Equal(2, ILShapeInspector.CountOpcode(read, OpCodes.Ldfld));
            Assert.Equal(2, CountArrayElementLoads(read));
            Assert.Equal(0, CountArrayElementStores(read));

            Assert.Equal(0, ILShapeInspector.CountOpcode(write, OpCodes.Pop));
            Assert.True(
                ILShapeInspector.CountOpcode(write, OpCodes.Ldfld) >= 4,
                "Row writes should load column array fields directly.");
            Assert.Equal(2, CountArrayElementLoads(write));
            Assert.Equal(2, CountArrayElementStores(write));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnElementAccess_UsesColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func update(nodes: NodeTable, row: int): int {
                nodes.kind[row] = 3
                nodes.kind[row] += 4
                old := nodes.kind[row]++
                return old * 10 + nodes.kind[row]
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(78, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 4,
                "Direct SoA column element operations should load the column field directly.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(3, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnDefaultAssignment_StoresDefaultWithoutReadingOldValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearColumns(nodes: NodeTable, row: int) {
                nodes.kind[row] = default
                nodes.text[row] = default
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 9
                nodes.text[row] = "set"
                clearColumns(nodes, row)
                return nodes.kind[row] + (nodes.text[row] == null ? 100 : 0)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearColumns = ILShapeInspector.GetProgramMethod(assembly, "clearColumns");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(100, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearColumns);
            Assert.True(
                ILShapeInspector.CountOpcode(clearColumns, OpCodes.Ldfld) >= 2,
                "Direct column default assignment should load column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearColumns));
            Assert.Equal(2, CountArrayElementStores(clearColumns));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnDefaultAssignmentExpression_ReturnsDefaultValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearAsExpression(nodes: NodeTable, row: int): int {
                kindDefault := nodes.kind[row] = default
                textDefault := nodes.text[row] = default
                return kindDefault + (textDefault == null ? 100 : 0) + nodes.kind[row] + (nodes.text[row] == null ? 1000 : 0)
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 9
                nodes.text[row] = "set"
                return clearAsExpression(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1100, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAsExpression, OpCodes.Ldfld) >= 4,
                "Direct column default assignment expressions should load column fields directly.");
            Assert.Equal(2, CountArrayElementLoads(clearAsExpression));
            Assert.Equal(2, CountArrayElementStores(clearAsExpression));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnAssignmentExpression_ReturnsAssignedValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func adjust(nodes: NodeTable, row: int): int {
                assigned := nodes.kind[row] += 5
                stored := nodes.kind[row] = assigned + 2
                return assigned * 100 + stored * 10 + nodes.kind[row]
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 8
                return adjust(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adjust = ILShapeInspector.GetProgramMethod(assembly, "adjust");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1465, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(adjust);
            Assert.True(
                ILShapeInspector.CountOpcode(adjust, OpCodes.Ldfld) >= 3,
                "Direct column assignment expressions should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(adjust) >= 2,
                "Direct column assignment expressions should read current and returned values from the column array.");
            Assert.Equal(2, CountArrayElementStores(adjust));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnPrefixIncrementDecrement_ReturnsUpdatedValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func bump(nodes: NodeTable, row: int): int {
                preUp := ++nodes.kind[row]
                preDown := --nodes.kind[row]
                return preUp * 100 + preDown * 10 + nodes.kind[row]
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 10
                return bump(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bump = ILShapeInspector.GetProgramMethod(assembly, "bump");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1210, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(bump);
            Assert.True(
                ILShapeInspector.CountOpcode(bump, OpCodes.Ldfld) >= 3,
                "Direct column prefix increment/decrement should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(bump) >= 3,
                "Direct column prefix increment/decrement should load current values and the returned value from the column array.");
            Assert.Equal(2, CountArrayElementStores(bump));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndIndex_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func lastSlot(nodes: NodeTable): int {
                nodes.kind[^1] = 9
                return nodes.kind[^1]
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return lastSlot(nodes) + row
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var lastSlot = ILShapeInspector.GetProgramMethod(assembly, "lastSlot");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(9, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(lastSlot);
            Assert.Equal(0, ILShapeInspector.CountOpcode(lastSlot, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(lastSlot));
            Assert.Equal(0, ILShapeInspector.CountOpcode(lastSlot, OpCodes.Callvirt));
            Assert.Equal(0, ILShapeInspector.CountCallsTo(
                lastSlot,
                typeof(System.Runtime.CompilerServices.RuntimeHelpers),
                nameof(System.Runtime.CompilerServices.RuntimeHelpers.GetSubArray)));
            Assert.True(
                ILShapeInspector.CountOpcode(lastSlot, OpCodes.Ldfld) >= 2,
                "Direct SoA from-end column access should still read the backing column field.");
            Assert.Equal(1, CountArrayElementLoads(lastSlot));
            Assert.Equal(1, CountArrayElementStores(lastSlot));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndAssignmentExpression_ReturnsAssignedValueWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func assignLast(nodes: NodeTable): int {
                assigned := nodes.kind[^1] = 42
                return assigned * 10 + nodes.kind[^1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                return assignLast(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var assignLast = ILShapeInspector.GetProgramMethod(assembly, "assignLast");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(462, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(assignLast);
            Assert.True(
                ILShapeInspector.CountOpcode(assignLast, OpCodes.Ldfld) >= 2,
                "Direct SoA from-end assignment expressions should load backing column fields directly.");
            Assert.Equal(1, CountArrayElementLoads(assignLast));
            Assert.Equal(1, CountArrayElementStores(assignLast));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndIndexUpdates_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func updateLast(nodes: NodeTable): int {
                nodes.kind[^1] = 10
                assigned := nodes.kind[^1] += 5
                old := nodes.kind[^1]++
                pre := ++nodes.kind[^1]
                return assigned * 1000 + old * 100 + pre * 10 + nodes.kind[^1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                return updateLast(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var updateLast = ILShapeInspector.GetProgramMethod(assembly, "updateLast");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(16687, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(updateLast);
            Assert.Equal(0, ILShapeInspector.CountOpcode(updateLast, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(updateLast));
            Assert.Equal(0, ILShapeInspector.CountOpcode(updateLast, OpCodes.Callvirt));
            Assert.Equal(0, ILShapeInspector.CountCallsTo(
                updateLast,
                typeof(System.Runtime.CompilerServices.RuntimeHelpers),
                nameof(System.Runtime.CompilerServices.RuntimeHelpers.GetSubArray)));
            Assert.True(
                ILShapeInspector.CountOpcode(updateLast, OpCodes.Ldfld) >= 5,
                "Direct SoA from-end column updates should still read the backing column field.");
            Assert.True(
                CountArrayElementLoads(updateLast) >= 5,
                "Direct SoA from-end column updates should read current and returned values from the backing array.");
            Assert.Equal(4, CountArrayElementStores(updateLast));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndDecrement_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func decrementLast(nodes: NodeTable): int {
                nodes.kind[^1] = 10
                old := nodes.kind[^1]--
                pre := --nodes.kind[^1]
                return old * 100 + pre * 10 + nodes.kind[^1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                return decrementLast(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var decrementLast = ILShapeInspector.GetProgramMethod(assembly, "decrementLast");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1088, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(decrementLast);
            Assert.True(
                ILShapeInspector.CountOpcode(decrementLast, OpCodes.Ldfld) >= 4,
                "Direct SoA from-end decrement should load the backing column field directly.");
            Assert.True(
                CountArrayElementLoads(decrementLast) >= 3,
                "Direct SoA from-end decrement should read current and returned values from the backing array.");
            Assert.Equal(3, CountArrayElementStores(decrementLast));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndNullCoalescing_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func readLast(nodes: NodeTable): string {
                return nodes.text[^1] ?? "fallback"
            }

            func assignMissing(nodes: NodeTable): string {
                return nodes.text[^1] ??= "assigned"
            }

            func keepExisting(nodes: NodeTable): string {
                nodes.text[^1] = "ready"
                return nodes.text[^1] ??= "ignored"
            }

            func main(): string {
                nodes := new NodeTable(2)
                missing := readLast(nodes)
                assigned := assignMissing(nodes)
                existing := keepExisting(nodes)
                return missing + ":" + assigned + ":" + existing
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var readLast = ILShapeInspector.GetProgramMethod(assembly, "readLast");
            var assignMissing = ILShapeInspector.GetProgramMethod(assembly, "assignMissing");
            var keepExisting = ILShapeInspector.GetProgramMethod(assembly, "keepExisting");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal("fallback:assigned:ready", Assert.IsType<string>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(readLast);
            Assert.True(
                ILShapeInspector.CountOpcode(readLast, OpCodes.Ldfld) >= 1,
                "Direct SoA from-end null-coalescing reads should load the backing column field.");
            Assert.Equal(1, CountArrayElementLoads(readLast));
            Assert.Equal(0, CountArrayElementStores(readLast));

            AssertNoFromEndSliceAllocation(assignMissing);
            Assert.True(
                ILShapeInspector.CountOpcode(assignMissing, OpCodes.Ldfld) >= 1,
                "Direct SoA from-end null-coalescing assignment should load the backing column field.");
            Assert.True(
                CountArrayElementLoads(assignMissing) >= 1,
                "Direct SoA from-end null-coalescing assignment should read the current value from the backing array.");
            Assert.Equal(1, CountArrayElementStores(assignMissing));

            AssertNoFromEndSliceAllocation(keepExisting);
            Assert.True(
                ILShapeInspector.CountOpcode(keepExisting, OpCodes.Ldfld) >= 2,
                "Direct SoA from-end null-coalescing assignment should keep direct column field access after an existing store.");
            Assert.True(
                CountArrayElementLoads(keepExisting) >= 1,
                "Direct SoA from-end null-coalescing assignment should read an existing column value before deciding to store.");
            Assert.Equal(2, CountArrayElementStores(keepExisting));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndDefaultStores_DoNotReadOldElement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearLast(nodes: NodeTable) {
                nodes.kind[^1] = default
                nodes.text[^1] = default
            }

            func clearLastAsExpression(nodes: NodeTable): int {
                kindDefault := nodes.kind[^1] = default
                textDefault := nodes.text[^1] = default
                return kindDefault + (textDefault == null ? 100 : 0)
            }

            func main(): int {
                nodes := new NodeTable(2)
                nodes.kind[^1] = 9
                nodes.text[^1] = "set"
                clearLast(nodes)
                first := nodes.kind[^1] + (nodes.text[^1] == null ? 100 : 0)

                nodes.kind[^1] = 8
                nodes.text[^1] = "set"
                second := clearLastAsExpression(nodes)
                third := nodes.kind[^1] + (nodes.text[^1] == null ? 1000 : 0)
                return first + second + third
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearLast = ILShapeInspector.GetProgramMethod(assembly, "clearLast");
            var clearLastAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearLastAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1200, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clearLast);
            Assert.True(
                ILShapeInspector.CountOpcode(clearLast, OpCodes.Ldfld) >= 2,
                "Direct SoA from-end default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLast));
            Assert.Equal(2, CountArrayElementStores(clearLast));

            AssertNoFromEndSliceAllocation(clearLastAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearLastAsExpression, OpCodes.Ldfld) >= 2,
                "Direct SoA from-end default assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLastAsExpression));
            Assert.Equal(2, CountArrayElementStores(clearLastAsExpression));

            return 0;
        });
    }

    [Fact]
    public void NewCapacityConstructor_AllocatesOneArrayPerColumnWithoutRowObjects()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func make(): int {
                nodes := new NodeTable(4)
                return nodes.length + nodes.capacity
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var constructor = tableType!.GetConstructor(new[] { typeof(int) });
            Assert.NotNull(constructor);

            ILShapeInspector.AssertNoBoxing(constructor!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newobj)); // capacity guard exception
            Assert.Equal(2, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountOpcode(constructor!, OpCodes.Call));
            Assert.Equal(0, ILShapeInspector.CountOpcode(constructor!, OpCodes.Callvirt));
            Assert.Equal(0, CountArrayElementLoads(constructor!));
            Assert.Equal(0, CountArrayElementStores(constructor!));
            Assert.Equal(4, ILShapeInspector.CountOpcode(constructor!, OpCodes.Stfld));

            return 0;
        });
    }

    [Fact]
    public void Wrap_StoresColumnReferencesWithoutElementCopies()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func view(kind: int[], start: int[]): int {
                nodes := NodeTable.wrap(kind, start, 1)
                return nodes.length + nodes.capacity
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var wrap = tableType!.GetMethod("wrap", BindingFlags.Public | BindingFlags.Static);
            Assert.NotNull(wrap);

            ILShapeInspector.AssertNoBoxing(wrap!);
            Assert.Equal(0, ILShapeInspector.CountOpcode(wrap!, OpCodes.Newarr));
            Assert.Equal(0, CountArrayElementLoads(wrap!));
            Assert.Equal(0, CountArrayElementStores(wrap!));
            Assert.Equal(4, ILShapeInspector.CountOpcode(wrap!, OpCodes.Stfld));

            return 0;
        });
    }

    [Fact]
    public void CopyRowAndClear_UseColumnArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func exercise(nodes: NodeTable): int {
                nodes.copyRow(0, 2)
                nodes.clear()
                return nodes.length
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var copyRow = tableType!.GetMethod("copyRow", BindingFlags.Public | BindingFlags.Instance);
            var clear = tableType.GetMethod("clear", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(copyRow);
            Assert.NotNull(clear);

            ILShapeInspector.AssertNoBoxing(copyRow!);
            Assert.Equal(4, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newobj)); // source/target/range/overflow guard exceptions
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(copyRow!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Call));
            Assert.Equal(2, CountArrayElementLoads(copyRow!));
            Assert.Equal(2, CountArrayElementStores(copyRow!));
            Assert.True(
                ILShapeInspector.CountOpcode(copyRow!, OpCodes.Ldfld) >= 5,
                "copyRow should load each column array plus the length field directly.");

            AssertNoAllocationOrDispatch(clear!);
            Assert.Equal(0, CountArrayElementLoads(clear!));
            Assert.Equal(0, CountArrayElementStores(clear!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(clear!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(clear!, OpCodes.Stfld));

            return 0;
        });
    }

    [Fact]
    public void AddAndEnsureCapacity_UseLengthCapacityAndArrayResizeWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func exercise(nodes: NodeTable): int {
                index := nodes.add()
                nodes.ensureCapacity(index + 4)
                return nodes.length + nodes.capacity
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var add = tableType!.GetMethod("add", BindingFlags.Public | BindingFlags.Instance);
            var ensureCapacity = tableType.GetMethod("ensureCapacity", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(add);
            Assert.NotNull(ensureCapacity);

            ILShapeInspector.AssertNoBoxing(add!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Newobj)); // length guard exception
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(add!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Call));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(add!));
            Assert.Equal(0, CountArrayElementStores(add!));

            ILShapeInspector.AssertNoBoxing(ensureCapacity!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Newobj)); // capacity guard exception
            Assert.Equal(0, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(ensureCapacity!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Callvirt));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(ensureCapacity!, typeof(Array), nameof(Array.Resize)));
            Assert.Equal(2, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Ldflda));
            Assert.Equal(1, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(ensureCapacity!));
            Assert.Equal(0, CountArrayElementStores(ensureCapacity!));

            return 0;
        });
    }

    [Fact]
    public void RowColumnNullCoalesceAssign_UsesColumnArrayLoadStore()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func adopt(nodes: NodeTable, row: int): string {
                nodes[row].text ??= "fallback"
                return nodes[row].text
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adopt = ILShapeInspector.GetProgramMethod(assembly, "adopt");
            AssertNoAllocationOrDispatch(adopt);
            Assert.True(
                ILShapeInspector.CountOpcode(adopt, OpCodes.Ldfld) >= 2,
                "Row-column null coalescing should load the column field directly.");
            Assert.True(
                CountArrayElementLoads(adopt) >= 2,
                "Row-column null coalescing should read the current value and the returned value from the column array.");
            Assert.Equal(1, CountArrayElementStores(adopt));
            return 0;
        });
    }

    [Fact]
    public void RowColumnNullCoalesceAssignExpression_ReturnsCurrentOrAssignedValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func adoptMissing(nodes: NodeTable, row: int): string {
                value := nodes[row].text ??= "fallback"
                return value
            }

            func keepExisting(nodes: NodeTable, row: int): string {
                nodes[row].text = "ready"
                value := nodes[row].text ??= "fallback"
                return value
            }

            func main(): string {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                return adoptMissing(nodes, first) + ":" + keepExisting(nodes, second)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adoptMissing = ILShapeInspector.GetProgramMethod(assembly, "adoptMissing");
            var keepExisting = ILShapeInspector.GetProgramMethod(assembly, "keepExisting");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal("fallback:ready", Assert.IsType<string>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(adoptMissing);
            Assert.True(
                ILShapeInspector.CountOpcode(adoptMissing, OpCodes.Ldfld) >= 1,
                "Row-column null-coalescing assignment expressions should load the column field directly.");
            Assert.True(
                CountArrayElementLoads(adoptMissing) >= 1,
                "Row-column null-coalescing assignment expressions should read the current column value.");
            Assert.Equal(1, CountArrayElementStores(adoptMissing));

            AssertNoAllocationOrDispatch(keepExisting);
            Assert.True(
                ILShapeInspector.CountOpcode(keepExisting, OpCodes.Ldfld) >= 2,
                "Row-column null-coalescing assignment expressions should keep direct column field access after an existing store.");
            Assert.True(
                CountArrayElementLoads(keepExisting) >= 1,
                "Row-column null-coalescing assignment expressions should read an existing column value before deciding to store.");
            Assert.Equal(2, CountArrayElementStores(keepExisting));

            return 0;
        });
    }

    [Fact]
    public void RowColumnNullCoalesce_UsesColumnArrayLoad()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func chooseMissing(nodes: NodeTable, row: int): string {
                return nodes[row].text ?? "fallback"
            }

            func chooseExisting(nodes: NodeTable, row: int): string {
                nodes[row].text = "ready"
                return nodes[row].text ?? "fallback"
            }

            func main(): string {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                return chooseMissing(nodes, first) + ":" + chooseExisting(nodes, second)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var chooseMissing = ILShapeInspector.GetProgramMethod(assembly, "chooseMissing");
            var chooseExisting = ILShapeInspector.GetProgramMethod(assembly, "chooseExisting");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal("fallback:ready", Assert.IsType<string>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(chooseMissing);
            Assert.True(
                ILShapeInspector.CountOpcode(chooseMissing, OpCodes.Ldfld) >= 1,
                "Row-column null-coalescing expressions should load the column field directly.");
            Assert.Equal(1, CountArrayElementLoads(chooseMissing));
            Assert.Equal(0, CountArrayElementStores(chooseMissing));

            AssertNoAllocationOrDispatch(chooseExisting);
            Assert.True(
                ILShapeInspector.CountOpcode(chooseExisting, OpCodes.Ldfld) >= 2,
                "Row-column null-coalescing expressions should keep direct column field access after an existing store.");
            Assert.Equal(1, CountArrayElementLoads(chooseExisting));
            Assert.Equal(1, CountArrayElementStores(chooseExisting));

            return 0;
        });
    }

    [Fact]
    public void RowColumnDefaultAssignment_StoresDefaultWithoutReadingOldValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearColumns(nodes: NodeTable, row: int) {
                nodes[row].kind = default
                nodes[row].text = default
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 9
                nodes[row].text = "set"
                clearColumns(nodes, row)
                return nodes[row].kind + (nodes[row].text == null ? 100 : 0)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearColumns = ILShapeInspector.GetProgramMethod(assembly, "clearColumns");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(100, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearColumns);
            Assert.True(
                ILShapeInspector.CountOpcode(clearColumns, OpCodes.Ldfld) >= 2,
                "Default row-column assignment should load column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearColumns));
            Assert.Equal(2, CountArrayElementStores(clearColumns));

            return 0;
        });
    }

    [Fact]
    public void RowColumnDefaultAssignmentExpression_ReturnsDefaultValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearAsExpression(nodes: NodeTable, row: int): int {
                kindDefault := nodes[row].kind = default
                textDefault := nodes[row].text = default
                return kindDefault + (textDefault == null ? 100 : 0) + nodes[row].kind + (nodes[row].text == null ? 1000 : 0)
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 9
                nodes[row].text = "set"
                return clearAsExpression(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1100, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAsExpression, OpCodes.Ldfld) >= 4,
                "Default row-column assignment expressions should load column fields directly.");
            Assert.Equal(2, CountArrayElementLoads(clearAsExpression));
            Assert.Equal(2, CountArrayElementStores(clearAsExpression));

            return 0;
        });
    }

    [Fact]
    public void RowColumnCompoundAssignment_UsesColumnArrayLoadStore()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func adjust(nodes: NodeTable, row: int): int {
                nodes[row].kind += 5
                nodes[row].kind *= 2
                return nodes[row].kind
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 8
                return adjust(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adjust = ILShapeInspector.GetProgramMethod(assembly, "adjust");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(26, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(adjust);
            Assert.True(
                ILShapeInspector.CountOpcode(adjust, OpCodes.Ldfld) >= 3,
                "Row-column compound assignment should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(adjust) >= 3,
                "Row-column compound assignment should read current values and the returned value from the column array.");
            Assert.Equal(2, CountArrayElementStores(adjust));

            return 0;
        });
    }

    [Fact]
    public void RowColumnAssignmentExpression_ReturnsAssignedValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func adjust(nodes: NodeTable, row: int): int {
                assigned := nodes[row].kind += 5
                stored := nodes[row].kind = assigned + 2
                return assigned * 100 + stored * 10 + nodes[row].kind
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 8
                return adjust(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adjust = ILShapeInspector.GetProgramMethod(assembly, "adjust");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1465, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(adjust);
            Assert.True(
                ILShapeInspector.CountOpcode(adjust, OpCodes.Ldfld) >= 3,
                "Row-column assignment expressions should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(adjust) >= 2,
                "Row-column assignment expressions should read current and returned values from the column array.");
            Assert.Equal(2, CountArrayElementStores(adjust));

            return 0;
        });
    }

    [Fact]
    public void RowColumnIncrementDecrement_UsesColumnArrayLoadStore()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func bump(nodes: NodeTable, row: int): int {
                old := nodes[row].kind++
                nodes[row].kind--
                return old + nodes[row].kind
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bump = ILShapeInspector.GetProgramMethod(assembly, "bump");
            AssertNoAllocationOrDispatch(bump);
            Assert.True(
                ILShapeInspector.CountOpcode(bump, OpCodes.Ldfld) >= 3,
                "Row-column increment/decrement should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(bump) >= 3,
                "Row-column increment/decrement should load current values and the returned value from the column array.");
            Assert.Equal(2, CountArrayElementStores(bump));
            return 0;
        });
    }

    [Fact]
    public void RowColumnPrefixIncrementDecrement_ReturnsUpdatedValueWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func bump(nodes: NodeTable, row: int): int {
                preUp := ++nodes[row].kind
                preDown := --nodes[row].kind
                return preUp * 100 + preDown * 10 + nodes[row].kind
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 10
                return bump(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bump = ILShapeInspector.GetProgramMethod(assembly, "bump");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1210, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(bump);
            Assert.True(
                ILShapeInspector.CountOpcode(bump, OpCodes.Ldfld) >= 3,
                "Row-column prefix increment/decrement should load column fields directly.");
            Assert.True(
                CountArrayElementLoads(bump) >= 3,
                "Row-column prefix increment/decrement should load current values and the returned value from the column array.");
            Assert.Equal(2, CountArrayElementStores(bump));
            return 0;
        });
    }

    [Fact]
    public void VerifiedColumnTypes_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                start: long
                active: bool
                marker: char
                name: string
                optionalName: string?
                count: int
            }

            func setAll(nodes: NodeTable, row: int, name: string, optionalName: string?) {
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = name
                nodes[row].optionalName = optionalName
                nodes[row].count = 11
            }

            func readScalars(nodes: NodeTable, row: int): int {
                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].count
                return total
            }

            func readName(nodes: NodeTable, row: int): string {
                return nodes[row].name
            }

            func readOptional(nodes: NodeTable, row: int): string? {
                return nodes[row].optionalName
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var setAll = ILShapeInspector.GetProgramMethod(assembly, "setAll");
            var readScalars = ILShapeInspector.GetProgramMethod(assembly, "readScalars");
            var readName = ILShapeInspector.GetProgramMethod(assembly, "readName");
            var readOptional = ILShapeInspector.GetProgramMethod(assembly, "readOptional");

            AssertNoAllocationOrDispatch(setAll);
            AssertNoAllocationOrDispatch(readScalars);
            AssertNoAllocationOrDispatch(readName);
            AssertNoAllocationOrDispatch(readOptional);

            Assert.Equal(8, CountArrayElementStores(setAll));
            Assert.Equal(0, CountArrayElementLoads(setAll));
            Assert.Equal(6, CountArrayElementLoads(readScalars));
            Assert.Equal(0, CountArrayElementStores(readScalars));
            Assert.Equal(1, CountArrayElementLoads(readName));
            Assert.Equal(1, CountArrayElementLoads(readOptional));
            Assert.Equal(0, CountArrayElementStores(readName));
            Assert.Equal(0, CountArrayElementStores(readOptional));

            return 0;
        });
    }

    [Fact]
    public void VerifiedDirectColumnTypes_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                start: long
                active: bool
                marker: char
                name: string
                optionalName: string?
                count: int
            }

            func setAll(nodes: NodeTable, row: int, name: string, optionalName: string?) {
                nodes.kind[row] = 3
                nodes.flags[row] = (uint)7
                nodes.start[row] = 19L
                nodes.active[row] = true
                nodes.marker[row] = 'A'
                nodes.name[row] = name
                nodes.optionalName[row] = optionalName
                nodes.count[row] = 11
            }

            func readScalars(nodes: NodeTable, row: int): int {
                total := nodes.kind[row]
                total += (int)nodes.flags[row]
                total += (int)nodes.start[row]
                total += (nodes.active[row] ? 100 : 0)
                total += (int)nodes.marker[row]
                total += nodes.count[row]
                return total
            }

            func readName(nodes: NodeTable, row: int): string {
                return nodes.name[row]
            }

            func readOptional(nodes: NodeTable, row: int): string? {
                return nodes.optionalName[row]
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                setAll(nodes, row, "abcd", null)
                total := readScalars(nodes, row)
                total += readName(nodes, row).Length
                total += (readOptional(nodes, row) == null ? 1000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var setAll = ILShapeInspector.GetProgramMethod(assembly, "setAll");
            var readScalars = ILShapeInspector.GetProgramMethod(assembly, "readScalars");
            var readName = ILShapeInspector.GetProgramMethod(assembly, "readName");
            var readOptional = ILShapeInspector.GetProgramMethod(assembly, "readOptional");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1209, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(setAll);
            AssertNoAllocationOrDispatch(readScalars);
            AssertNoAllocationOrDispatch(readName);
            AssertNoAllocationOrDispatch(readOptional);

            Assert.Equal(8, CountArrayElementStores(setAll));
            Assert.Equal(0, CountArrayElementLoads(setAll));
            Assert.Equal(6, CountArrayElementLoads(readScalars));
            Assert.Equal(0, CountArrayElementStores(readScalars));
            Assert.Equal(1, CountArrayElementLoads(readName));
            Assert.Equal(1, CountArrayElementLoads(readOptional));
            Assert.Equal(0, CountArrayElementStores(readName));
            Assert.Equal(0, CountArrayElementStores(readOptional));

            return 0;
        });
    }

    private static void AssertNoAllocationOrDispatch(MethodInfo method)
    {
        ILShapeInspector.AssertNoBoxing(method);
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newobj));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newarr));
        Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(method));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Call));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
    }

    private static void AssertNoFromEndSliceAllocation(MethodInfo method)
    {
        ILShapeInspector.AssertNoBoxing(method);
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newarr));
        Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(method));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
        Assert.Equal(0, ILShapeInspector.CountCallsTo(
            method,
            typeof(System.Runtime.CompilerServices.RuntimeHelpers),
            nameof(System.Runtime.CompilerServices.RuntimeHelpers.GetSubArray)));
    }

    private static int CountArrayElementLoads(MethodBase method)
    {
        return CountOpcodes(
            method,
            OpCodes.Ldelem,
            OpCodes.Ldelem_I1,
            OpCodes.Ldelem_I2,
            OpCodes.Ldelem_I4,
            OpCodes.Ldelem_I8,
            OpCodes.Ldelem_R4,
            OpCodes.Ldelem_R8,
            OpCodes.Ldelem_Ref,
            OpCodes.Ldelem_U1,
            OpCodes.Ldelem_U2,
            OpCodes.Ldelem_U4,
            OpCodes.Ldelema);
    }

    private static int CountArrayElementStores(MethodBase method)
    {
        return CountOpcodes(
            method,
            OpCodes.Stelem,
            OpCodes.Stelem_I,
            OpCodes.Stelem_I1,
            OpCodes.Stelem_I2,
            OpCodes.Stelem_I4,
            OpCodes.Stelem_I8,
            OpCodes.Stelem_R4,
            OpCodes.Stelem_R8,
            OpCodes.Stelem_Ref);
    }

    private static int CountOpcodes(MethodBase method, params OpCode[] opCodes)
    {
        return ILShapeInspector.Decode(method).Count(instruction => opCodes.Contains(instruction.OpCode));
    }

    private static IDisposable SetEnvironmentVariable(string name, string? value)
    {
        var previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
        return new RestoreEnvironmentVariable(name, previousValue);
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }
}
