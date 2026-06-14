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
