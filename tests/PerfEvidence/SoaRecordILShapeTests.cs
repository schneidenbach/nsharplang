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
            Assert.Equal(0, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newobj));
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
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newobj));
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
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(add!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Call));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(add!));
            Assert.Equal(0, CountArrayElementStores(add!));

            ILShapeInspector.AssertNoBoxing(ensureCapacity!);
            Assert.Equal(0, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Newobj));
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

    private static void AssertNoAllocationOrDispatch(MethodInfo method)
    {
        ILShapeInspector.AssertNoBoxing(method);
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newobj));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newarr));
        Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(method));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Call));
        Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
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
