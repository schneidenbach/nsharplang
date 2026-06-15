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
    public void ParenthesizedDefaultStores_DoNotReadOldElement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearParenthesized(nodes: NodeTable, row: int) {
                ((nodes[row]).kind) = default;
                ((nodes[row]).text) = default;
                ((nodes.kind)[row]) = default;
                ((nodes.text)[row]) = default;
                ((nodes.kind)[^1]) = default;
                ((nodes.text)[^1]) = default;
                idx := ^1;
                ((nodes.kind)[idx]) = default;
                ((nodes.text)[idx]) = default;
            }

            func clearParenthesizedAsExpression(nodes: NodeTable, row: int): int {
                idx := ^1;
                rowKind := ((nodes[row]).kind) = default;
                rowText := ((nodes[row]).text) = default;
                directKind := ((nodes.kind)[row]) = default;
                directText := ((nodes.text)[row]) = default;
                literalKind := ((nodes.kind)[^1]) = default;
                literalText := ((nodes.text)[^1]) = default;
                variableKind := ((nodes.kind)[idx]) = default;
                variableText := ((nodes.text)[idx]) = default;
                total := rowKind + directKind + literalKind + variableKind
                total += (rowText == null ? 10 : 0)
                total += (directText == null ? 100 : 0)
                total += (literalText == null ? 1000 : 0)
                total += (variableText == null ? 10000 : 0)
                return total
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 9
                nodes.text[first] = "first"
                nodes.kind[second] = 7
                nodes.text[second] = "second"
                clearParenthesized(nodes, first)
                firstScore := nodes.kind[first] + (nodes.text[first] == null ? 100 : 0)
                firstScore += nodes.kind[second] + (nodes.text[second] == null ? 1000 : 0)

                nodes.kind[first] = 8
                nodes.text[first] = "again"
                nodes.kind[second] = 6
                nodes.text[second] = "again"
                expressionScore := clearParenthesizedAsExpression(nodes, first)
                afterScore := nodes.kind[first] + (nodes.text[first] == null ? 100 : 0)
                afterScore += nodes.kind[second] + (nodes.text[second] == null ? 1000 : 0)
                return firstScore + expressionScore + afterScore
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearParenthesized = ILShapeInspector.GetProgramMethod(assembly, "clearParenthesized");
            var clearParenthesizedAsExpression = ILShapeInspector.GetProgramMethod(
                assembly,
                "clearParenthesizedAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(13310, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clearParenthesized);
            Assert.True(
                ILShapeInspector.CountOpcode(clearParenthesized, OpCodes.Ldfld) >= 8,
                "Parenthesized SoA default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearParenthesized));
            Assert.Equal(8, CountArrayElementStores(clearParenthesized));

            AssertNoFromEndSliceAllocation(clearParenthesizedAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearParenthesizedAsExpression, OpCodes.Ldfld) >= 8,
                "Parenthesized SoA default store expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearParenthesizedAsExpression));
            Assert.Equal(8, CountArrayElementStores(clearParenthesizedAsExpression));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnVerifiedTypeDefaultStores_DoNotReadOldElement()
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

            func clearAll(nodes: NodeTable, row: int) {
                nodes.kind[row] = default
                nodes.flags[row] = default
                nodes.start[row] = default
                nodes.active[row] = default
                nodes.marker[row] = default
                nodes.name[row] = default
                nodes.optionalName[row] = default
                nodes.count[row] = default
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 3
                nodes.flags[row] = (uint)7
                nodes.start[row] = 19L
                nodes.active[row] = true
                nodes.marker[row] = 'A'
                nodes.name[row] = "name"
                nodes.optionalName[row] = "optional"
                nodes.count[row] = 11
                clearAll(nodes, row)
                total := nodes.kind[row]
                total += (int)nodes.flags[row]
                total += (int)nodes.start[row]
                total += (nodes.active[row] ? 100 : 0)
                total += (int)nodes.marker[row]
                total += nodes.count[row]
                total += (nodes.name[row] == null ? 1000 : 0)
                total += (nodes.optionalName[row] == null ? 10000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAll = ILShapeInspector.GetProgramMethod(assembly, "clearAll");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(11000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAll);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAll, OpCodes.Ldfld) >= 8,
                "Direct column default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearAll));
            Assert.Equal(8, CountArrayElementStores(clearAll));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnVerifiedTypeDefaultStoreExpressions_ReturnDefaultWithoutOldElementRead()
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

            func clearAllAsExpression(nodes: NodeTable, row: int): int {
                kindDefault := nodes.kind[row] = default
                flagsDefault := nodes.flags[row] = default
                startDefault := nodes.start[row] = default
                activeDefault := nodes.active[row] = default
                markerDefault := nodes.marker[row] = default
                nameDefault := nodes.name[row] = default
                optionalNameDefault := nodes.optionalName[row] = default
                countDefault := nodes.count[row] = default

                total := kindDefault
                total += (int)flagsDefault
                total += (int)startDefault
                total += (activeDefault ? 100 : 0)
                total += (int)markerDefault
                total += countDefault
                total += (nameDefault == null ? 1000 : 0)
                total += (optionalNameDefault == null ? 10000 : 0)
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.kind[row] = 3
                nodes.flags[row] = (uint)7
                nodes.start[row] = 19L
                nodes.active[row] = true
                nodes.marker[row] = 'A'
                nodes.name[row] = "name"
                nodes.optionalName[row] = "optional"
                nodes.count[row] = 11

                expressionTotal := clearAllAsExpression(nodes, row)
                storedTotal := nodes.kind[row]
                storedTotal += (int)nodes.flags[row]
                storedTotal += (int)nodes.start[row]
                storedTotal += (nodes.active[row] ? 100 : 0)
                storedTotal += (int)nodes.marker[row]
                storedTotal += nodes.count[row]
                storedTotal += (nodes.name[row] == null ? 1000 : 0)
                storedTotal += (nodes.optionalName[row] == null ? 10000 : 0)
                return expressionTotal + storedTotal
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAllAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearAllAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(22000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAllAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAllAsExpression, OpCodes.Ldfld) >= 8,
                "Direct column default assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearAllAsExpression));
            Assert.Equal(8, CountArrayElementStores(clearAllAsExpression));

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
    public void DirectColumnIntegralVerifiedTypeUpdates_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                flags: uint
                start: long
                marker: char
            }

            func update(nodes: NodeTable, row: int): int {
                nodes.flags[row] += (uint)5
                oldFlags := nodes.flags[row]++
                nodes.start[row] += 7L
                oldStart := nodes.start[row]--
                oldMarker := nodes.marker[row]++
                preMarker := ++nodes.marker[row]

                total := (int)nodes.flags[row]
                total += (int)oldFlags * 10
                total += (int)nodes.start[row]
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)nodes.marker[row]
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes.flags[row] = (uint)2
                nodes.start[row] = 20L
                nodes.marker[row] = 'A'
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(330, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 9,
                "Direct column integral updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(update) >= 9,
                "Direct column integral updates should read current and returned values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(update));

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
    public void DirectColumnVariableFromEndIndex_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func lastSlot(nodes: NodeTable): int {
                idx := ^1
                nodes.kind[idx] = 9
                assigned := nodes.kind[idx] = nodes.kind[idx] + 4
                return assigned * 10 + nodes.kind[idx]
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

            Assert.Equal(143, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(lastSlot);
            Assert.True(
                ILShapeInspector.CountOpcode(lastSlot, OpCodes.Ldfld) >= 4,
                "Direct SoA variable from-end column access should load backing column fields directly.");
            Assert.Equal(2, CountArrayElementLoads(lastSlot));
            Assert.Equal(2, CountArrayElementStores(lastSlot));

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberElementAccess_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func useColumns(nodes: NodeTable, row: int): int {
                idx := ^1;
                (nodes.kind)[row] = 3;
                (nodes.text)[row] = "row";
                rowAssigned := (nodes.kind)[row] = (nodes.kind)[row] + 4;
                (nodes.kind)[^1] = 11;
                literalAssigned := (nodes.kind)[^1] = (nodes.kind)[^1] + 2;
                (nodes.text)[^1] ??= "last";
                variableAssigned := (nodes.kind)[idx] = (nodes.kind)[idx] + 5
                textScore := ((nodes.text)[row] == "row" ? 10000 : 0)
                textScore += ((nodes.text)[idx] == "last" ? 100000 : 0)
                return rowAssigned + literalAssigned * 10 + variableAssigned * 100 + textScore + (nodes.kind)[row] + (nodes.kind)[idx]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                return useColumns(nodes, first)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var useColumns = ILShapeInspector.GetProgramMethod(assembly, "useColumns");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111962, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(useColumns);
            Assert.True(
                ILShapeInspector.CountOpcode(useColumns, OpCodes.Ldfld) >= 14,
                "Parenthesized direct column members should load backing column fields directly.");
            Assert.Equal(8, CountArrayElementLoads(useColumns));
            Assert.Equal(7, CountArrayElementStores(useColumns));

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
    public void DirectColumnFromEndIntegralVerifiedTypeUpdates_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                flags: uint
                start: long
                marker: char
            }

            func updateLast(nodes: NodeTable): int {
                nodes.flags[^1] += (uint)5
                oldFlags := nodes.flags[^1]++
                nodes.start[^1] += 7L
                oldStart := nodes.start[^1]--
                oldMarker := nodes.marker[^1]++
                preMarker := ++nodes.marker[^1]

                total := (int)nodes.flags[^1]
                total += (int)oldFlags * 10
                total += (int)nodes.start[^1]
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)nodes.marker[^1]
                return total
            }

            func main(): int {
                nodes := new NodeTable(2)
                nodes.flags[^1] = (uint)2
                nodes.start[^1] = 20L
                nodes.marker[^1] = 'A'
                return updateLast(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var updateLast = ILShapeInspector.GetProgramMethod(assembly, "updateLast");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(330, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(updateLast);
            Assert.True(
                ILShapeInspector.CountOpcode(updateLast, OpCodes.Ldfld) >= 9,
                "Direct from-end integral updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(updateLast) >= 9,
                "Direct from-end integral updates should read current and returned values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(updateLast));

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
    public void DirectColumnVariableFromEndDefaultStores_DoNotReadOldElement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearLast(nodes: NodeTable) {
                idx := ^1
                nodes.kind[idx] = default
                nodes.text[idx] = default
            }

            func clearLastAsExpression(nodes: NodeTable): int {
                idx := ^1
                kindDefault := nodes.kind[idx] = default
                textDefault := nodes.text[idx] = default
                return kindDefault + (textDefault == null ? 100 : 0)
            }

            func main(): int {
                nodes := new NodeTable(2)
                idx := ^1
                nodes.kind[idx] = 9
                nodes.text[idx] = "set"
                clearLast(nodes)
                first := nodes.kind[idx] + (nodes.text[idx] == null ? 100 : 0)

                nodes.kind[idx] = 8
                nodes.text[idx] = "set"
                second := clearLastAsExpression(nodes)
                third := nodes.kind[idx] + (nodes.text[idx] == null ? 1000 : 0)
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
                "Direct SoA variable from-end default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLast));
            Assert.Equal(2, CountArrayElementStores(clearLast));

            AssertNoFromEndSliceAllocation(clearLastAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearLastAsExpression, OpCodes.Ldfld) >= 2,
                "Direct SoA variable from-end default assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLastAsExpression));
            Assert.Equal(2, CountArrayElementStores(clearLastAsExpression));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndVerifiedTypes_UseColumnArrayOffsetWithoutSliceAllocation()
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

            func setLast(nodes: NodeTable, name: string, optionalName: string?) {
                nodes.kind[^1] = 3
                nodes.flags[^1] = (uint)7
                nodes.start[^1] = 19L
                nodes.active[^1] = true
                nodes.marker[^1] = 'A'
                nodes.name[^1] = name
                nodes.optionalName[^1] = optionalName
                nodes.count[^1] = 11
            }

            func readScalars(nodes: NodeTable): int {
                total := nodes.kind[^1]
                total += (int)nodes.flags[^1]
                total += (int)nodes.start[^1]
                total += (nodes.active[^1] ? 100 : 0)
                total += (int)nodes.marker[^1]
                total += nodes.count[^1]
                return total
            }

            func readName(nodes: NodeTable): string {
                return nodes.name[^1]
            }

            func readOptional(nodes: NodeTable): string? {
                return nodes.optionalName[^1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                setLast(nodes, "abcd", null)
                total := readScalars(nodes)
                total += readName(nodes).Length
                total += (readOptional(nodes) == null ? 1000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var setLast = ILShapeInspector.GetProgramMethod(assembly, "setLast");
            var readScalars = ILShapeInspector.GetProgramMethod(assembly, "readScalars");
            var readName = ILShapeInspector.GetProgramMethod(assembly, "readName");
            var readOptional = ILShapeInspector.GetProgramMethod(assembly, "readOptional");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1209, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(setLast);
            AssertNoFromEndSliceAllocation(readScalars);
            AssertNoFromEndSliceAllocation(readName);
            AssertNoFromEndSliceAllocation(readOptional);

            Assert.Equal(8, CountArrayElementStores(setLast));
            Assert.Equal(0, CountArrayElementLoads(setLast));
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
    public void DirectColumnFromEndVerifiedTypeDefaultStores_DoNotReadOldElement()
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

            func clearLast(nodes: NodeTable) {
                nodes.kind[^1] = default
                nodes.flags[^1] = default
                nodes.start[^1] = default
                nodes.active[^1] = default
                nodes.marker[^1] = default
                nodes.name[^1] = default
                nodes.optionalName[^1] = default
                nodes.count[^1] = default
            }

            func main(): int {
                nodes := new NodeTable(2)
                nodes.kind[^1] = 3
                nodes.flags[^1] = (uint)7
                nodes.start[^1] = 19L
                nodes.active[^1] = true
                nodes.marker[^1] = 'A'
                nodes.name[^1] = "name"
                nodes.optionalName[^1] = "optional"
                nodes.count[^1] = 11
                clearLast(nodes)
                total := nodes.kind[^1]
                total += (int)nodes.flags[^1]
                total += (int)nodes.start[^1]
                total += (nodes.active[^1] ? 100 : 0)
                total += (int)nodes.marker[^1]
                total += nodes.count[^1]
                total += (nodes.name[^1] == null ? 1000 : 0)
                total += (nodes.optionalName[^1] == null ? 10000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearLast = ILShapeInspector.GetProgramMethod(assembly, "clearLast");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(11000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clearLast);
            Assert.True(
                ILShapeInspector.CountOpcode(clearLast, OpCodes.Ldfld) >= 8,
                "Direct SoA from-end default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLast));
            Assert.Equal(8, CountArrayElementStores(clearLast));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnFromEndVerifiedTypeDefaultStoreExpressions_ReturnDefaultWithoutOldElementRead()
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

            func clearLastAsExpression(nodes: NodeTable): int {
                kindDefault := nodes.kind[^1] = default
                flagsDefault := nodes.flags[^1] = default
                startDefault := nodes.start[^1] = default
                activeDefault := nodes.active[^1] = default
                markerDefault := nodes.marker[^1] = default
                nameDefault := nodes.name[^1] = default
                optionalNameDefault := nodes.optionalName[^1] = default
                countDefault := nodes.count[^1] = default

                total := kindDefault
                total += (int)flagsDefault
                total += (int)startDefault
                total += (activeDefault ? 100 : 0)
                total += (int)markerDefault
                total += countDefault
                total += (nameDefault == null ? 1000 : 0)
                total += (optionalNameDefault == null ? 10000 : 0)
                return total
            }

            func main(): int {
                nodes := new NodeTable(2)
                nodes.kind[^1] = 3
                nodes.flags[^1] = (uint)7
                nodes.start[^1] = 19L
                nodes.active[^1] = true
                nodes.marker[^1] = 'A'
                nodes.name[^1] = "name"
                nodes.optionalName[^1] = "optional"
                nodes.count[^1] = 11

                expressionTotal := clearLastAsExpression(nodes)
                storedTotal := nodes.kind[^1]
                storedTotal += (int)nodes.flags[^1]
                storedTotal += (int)nodes.start[^1]
                storedTotal += (nodes.active[^1] ? 100 : 0)
                storedTotal += (int)nodes.marker[^1]
                storedTotal += nodes.count[^1]
                storedTotal += (nodes.name[^1] == null ? 1000 : 0)
                storedTotal += (nodes.optionalName[^1] == null ? 10000 : 0)
                return expressionTotal + storedTotal
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearLastAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearLastAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(22000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clearLastAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearLastAsExpression, OpCodes.Ldfld) >= 8,
                "Direct SoA from-end default assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearLastAsExpression));
            Assert.Equal(8, CountArrayElementStores(clearLastAsExpression));

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
    public void NewWrapAndEnsureCapacityVerifiedColumnTypes_UseColumnArraysWithoutElementCopies()
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

            func make(): int {
                nodes := new NodeTable(4)
                return nodes.length + nodes.capacity
            }

            func grow(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = "name"
                nodes[row].optionalName = null
                nodes[row].count = 11

                nodes.ensureCapacity(4)

                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].count
                total += nodes[row].name.Length
                total += (nodes[row].optionalName == null ? 1000 : 0)
                return total + nodes.length * 10000 + nodes.capacity * 100000
            }

            func view(kind: int[], flags: uint[], start: long[], active: bool[], marker: char[], name: string[], optionalName: string?[], counts: int[]): int {
                nodes := NodeTable.wrap(kind, flags, start, active, marker, name, optionalName, counts, 1)
                total := nodes[0].kind
                total += (int)nodes[0].flags
                total += (int)nodes[0].start
                total += (nodes[0].active ? 100 : 0)
                total += (int)nodes[0].marker
                total += nodes[0].count
                total += nodes[0].name.Length
                total += (nodes[0].optionalName == null ? 1000 : 0)
                return total + nodes.length * 10000 + nodes.capacity * 100000
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var constructor = tableType!.GetConstructor(new[] { typeof(int) });
            var wrap = tableType.GetMethod("wrap", BindingFlags.Public | BindingFlags.Static);
            var ensureCapacity = tableType.GetMethod("ensureCapacity", BindingFlags.Public | BindingFlags.Instance);
            var make = ILShapeInspector.GetProgramMethod(assembly, "make");
            var grow = ILShapeInspector.GetProgramMethod(assembly, "grow");
            var view = ILShapeInspector.GetProgramMethod(assembly, "view");
            Assert.NotNull(constructor);
            Assert.NotNull(wrap);
            Assert.NotNull(ensureCapacity);

            Assert.Equal(4, Assert.IsType<int>(make.Invoke(null, null)));
            Assert.Equal(411209, Assert.IsType<int>(grow.Invoke(null, null)));
            Assert.Equal(
                111209,
                Assert.IsType<int>(view.Invoke(
                    null,
                    new object[]
                    {
                        new[] { 3 },
                        new uint[] { 7 },
                        new long[] { 19L },
                        new[] { true },
                        new[] { 'A' },
                        new[] { "name" },
                        new string?[] { null },
                        new[] { 11 }
                    })));

            ILShapeInspector.AssertNoBoxing(constructor!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newobj)); // capacity guard exception
            Assert.Equal(8, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountOpcode(constructor!, OpCodes.Call));
            Assert.Equal(0, ILShapeInspector.CountOpcode(constructor!, OpCodes.Callvirt));
            Assert.Equal(0, CountArrayElementLoads(constructor!));
            Assert.Equal(0, CountArrayElementStores(constructor!));
            Assert.Equal(10, ILShapeInspector.CountOpcode(constructor!, OpCodes.Stfld));

            ILShapeInspector.AssertNoBoxing(wrap!);
            Assert.Equal(3, ILShapeInspector.CountOpcode(wrap!, OpCodes.Newobj)); // null/length/mismatch guard exceptions
            Assert.Equal(0, ILShapeInspector.CountOpcode(wrap!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(wrap!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(wrap!, OpCodes.Callvirt));
            Assert.Equal(0, CountArrayElementLoads(wrap!));
            Assert.Equal(0, CountArrayElementStores(wrap!));
            Assert.Equal(10, ILShapeInspector.CountOpcode(wrap!, OpCodes.Stfld));

            ILShapeInspector.AssertNoBoxing(ensureCapacity!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Newobj)); // capacity guard exception
            Assert.Equal(0, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(ensureCapacity!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Callvirt));
            Assert.Equal(8, ILShapeInspector.CountCallsTo(ensureCapacity!, typeof(Array), nameof(Array.Resize)));
            Assert.Equal(8, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Ldflda));
            Assert.Equal(1, ILShapeInspector.CountOpcode(ensureCapacity!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(ensureCapacity!));
            Assert.Equal(0, CountArrayElementStores(ensureCapacity!));

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
    public void CopyRowVerifiedColumnTypes_UsesColumnElementCopiesWithoutRowAllocation()
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

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = "name"
                nodes[row].optionalName = null
                nodes[row].count = 11

                nodes.copyRow(row, 1)

                total := nodes[1].kind
                total += (int)nodes[1].flags
                total += (int)nodes[1].start
                total += (nodes[1].active ? 100 : 0)
                total += (int)nodes[1].marker
                total += nodes[1].count
                total += nodes[1].name.Length
                total += (nodes[1].optionalName == null ? 1000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var copyRow = tableType!.GetMethod("copyRow", BindingFlags.Public | BindingFlags.Instance);
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.NotNull(copyRow);

            Assert.Equal(1209, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(copyRow!);
            Assert.Equal(4, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newobj)); // source/target/range/overflow guard exceptions
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(copyRow!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Call)); // ensureCapacity
            Assert.Equal(8, CountArrayElementLoads(copyRow!));
            Assert.Equal(8, CountArrayElementStores(copyRow!));
            Assert.True(
                ILShapeInspector.CountOpcode(copyRow!, OpCodes.Ldfld) >= 17,
                "copyRow should load each column array plus the length field directly.");

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
    public void AddAndClearVerifiedColumnTypes_UseLengthMetadataWithoutElementTraffic()
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

            func main(): int {
                nodes := new NodeTable(1)
                first := nodes.add()
                second := nodes.add()

                nodes[first].kind = 3
                nodes[first].flags = (uint)7
                nodes[first].start = 19L
                nodes[first].active = true
                nodes[first].marker = 'A'
                nodes[first].name = "name"
                nodes[first].optionalName = null
                nodes[first].count = 11

                nodes[second].kind = 5
                nodes[second].count = 13

                beforeClear := first * 1000000
                beforeClear += second * 100000
                beforeClear += nodes.length * 10000
                beforeClear += nodes.capacity * 1000
                beforeClear += nodes[first].kind * 10
                beforeClear += nodes[second].count

                nodes.clear()
                return beforeClear + nodes.length
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var add = tableType!.GetMethod("add", BindingFlags.Public | BindingFlags.Instance);
            var clear = tableType.GetMethod("clear", BindingFlags.Public | BindingFlags.Instance);
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.NotNull(add);
            Assert.NotNull(clear);

            Assert.Equal(124043, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(add!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Newobj)); // length guard exception
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(add!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(add!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Call)); // ensureCapacity
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(add!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(add!));
            Assert.Equal(0, CountArrayElementStores(add!));

            AssertNoAllocationOrDispatch(clear!);
            Assert.Equal(0, ILShapeInspector.CountOpcode(clear!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(clear!, OpCodes.Stfld));
            Assert.Equal(0, CountArrayElementLoads(clear!));
            Assert.Equal(0, CountArrayElementStores(clear!));

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
    public void RowColumnVerifiedTypeDefaultStores_DoNotReadOldElement()
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

            func clearAll(nodes: NodeTable, row: int) {
                nodes[row].kind = default
                nodes[row].flags = default
                nodes[row].start = default
                nodes[row].active = default
                nodes[row].marker = default
                nodes[row].name = default
                nodes[row].optionalName = default
                nodes[row].count = default
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = "name"
                nodes[row].optionalName = "optional"
                nodes[row].count = 11
                clearAll(nodes, row)
                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].count
                total += (nodes[row].name == null ? 1000 : 0)
                total += (nodes[row].optionalName == null ? 10000 : 0)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAll = ILShapeInspector.GetProgramMethod(assembly, "clearAll");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(11000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAll);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAll, OpCodes.Ldfld) >= 8,
                "Row-column default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearAll));
            Assert.Equal(8, CountArrayElementStores(clearAll));

            return 0;
        });
    }

    [Fact]
    public void RowColumnVerifiedTypeDefaultStoreExpressions_ReturnDefaultWithoutOldElementRead()
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

            func clearAllAsExpression(nodes: NodeTable, row: int): int {
                kindDefault := nodes[row].kind = default
                flagsDefault := nodes[row].flags = default
                startDefault := nodes[row].start = default
                activeDefault := nodes[row].active = default
                markerDefault := nodes[row].marker = default
                nameDefault := nodes[row].name = default
                optionalNameDefault := nodes[row].optionalName = default
                countDefault := nodes[row].count = default

                total := kindDefault
                total += (int)flagsDefault
                total += (int)startDefault
                total += (activeDefault ? 100 : 0)
                total += (int)markerDefault
                total += countDefault
                total += (nameDefault == null ? 1000 : 0)
                total += (optionalNameDefault == null ? 10000 : 0)
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = "name"
                nodes[row].optionalName = "optional"
                nodes[row].count = 11

                expressionTotal := clearAllAsExpression(nodes, row)
                storedTotal := nodes[row].kind
                storedTotal += (int)nodes[row].flags
                storedTotal += (int)nodes[row].start
                storedTotal += (nodes[row].active ? 100 : 0)
                storedTotal += (int)nodes[row].marker
                storedTotal += nodes[row].count
                storedTotal += (nodes[row].name == null ? 1000 : 0)
                storedTotal += (nodes[row].optionalName == null ? 10000 : 0)
                return expressionTotal + storedTotal
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearAllAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearAllAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(22000, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(clearAllAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAllAsExpression, OpCodes.Ldfld) >= 8,
                "Row-column default assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearAllAsExpression));
            Assert.Equal(8, CountArrayElementStores(clearAllAsExpression));

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
    public void RowColumnIntegralVerifiedTypeUpdates_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                flags: uint
                start: long
                marker: char
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].flags += (uint)5
                oldFlags := nodes[row].flags++
                nodes[row].start += 7L
                oldStart := nodes[row].start--
                oldMarker := nodes[row].marker++
                preMarker := ++nodes[row].marker

                total := (int)nodes[row].flags
                total += (int)oldFlags * 10
                total += (int)nodes[row].start
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)nodes[row].marker
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].flags = (uint)2
                nodes[row].start = 20L
                nodes[row].marker = 'A'
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(330, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 9,
                "Row-column integral updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(update) >= 9,
                "Row-column integral updates should read current and returned values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(update));

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

    [Fact]
    public void EnumColumn_UsesColumnArrayLoadStoreAndGeneratedMethodsWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
                count: int
            }

            enum NodeKind {
                Unknown,
                Identifier,
                Literal
            }

            func set(nodes: NodeTable, row: int) {
                nodes[row].kind = NodeKind.Identifier
                nodes.kind[row] = NodeKind.Literal
                nodes[row].count = 3
            }

            func read(nodes: NodeTable, row: int): int {
                total := nodes[row].kind == NodeKind.Literal ? 10 : 0
                total += nodes.kind[row] == NodeKind.Literal ? 100 : 0
                total += nodes[row].count
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                set(nodes, row)
                nodes.copyRow(row, 1)
                view := NodeTable.wrap(nodes.kind, nodes.count, nodes.length)
                return read(view, 1) + view.length * 1000 + view.capacity * 10000
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var constructor = tableType!.GetConstructor(new[] { typeof(int) });
            var wrap = tableType.GetMethod("wrap", BindingFlags.Public | BindingFlags.Static);
            var copyRow = tableType.GetMethod("copyRow", BindingFlags.Public | BindingFlags.Instance);
            var kindField = tableType.GetField("kind", BindingFlags.Public | BindingFlags.Instance);
            var set = ILShapeInspector.GetProgramMethod(assembly, "set");
            var read = ILShapeInspector.GetProgramMethod(assembly, "read");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.NotNull(constructor);
            Assert.NotNull(wrap);
            Assert.NotNull(copyRow);
            Assert.NotNull(kindField);

            Assert.True(kindField!.FieldType.IsArray);
            Assert.True(kindField.FieldType.GetElementType()?.IsEnum);
            Assert.Equal(42113, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(set);
            Assert.True(
                ILShapeInspector.CountOpcode(set, OpCodes.Ldfld) >= 3,
                "Enum SoA stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(set));
            Assert.Equal(3, CountArrayElementStores(set));

            AssertNoAllocationOrDispatch(read);
            Assert.True(
                ILShapeInspector.CountOpcode(read, OpCodes.Ldfld) >= 3,
                "Enum SoA reads should load backing column fields directly.");
            Assert.Equal(3, CountArrayElementLoads(read));
            Assert.Equal(0, CountArrayElementStores(read));

            ILShapeInspector.AssertNoBoxing(constructor!);
            Assert.Equal(1, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newobj)); // capacity guard exception
            Assert.Equal(2, ILShapeInspector.CountOpcode(constructor!, OpCodes.Newarr));
            Assert.Equal(0, CountArrayElementLoads(constructor!));
            Assert.Equal(0, CountArrayElementStores(constructor!));

            ILShapeInspector.AssertNoBoxing(wrap!);
            Assert.Equal(3, ILShapeInspector.CountOpcode(wrap!, OpCodes.Newobj)); // null/length/mismatch guard exceptions
            Assert.Equal(0, ILShapeInspector.CountOpcode(wrap!, OpCodes.Newarr));
            Assert.Equal(0, CountArrayElementLoads(wrap!));
            Assert.Equal(0, CountArrayElementStores(wrap!));
            Assert.Equal(4, ILShapeInspector.CountOpcode(wrap!, OpCodes.Stfld));

            ILShapeInspector.AssertNoBoxing(copyRow!);
            Assert.Equal(4, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newobj)); // source/target/range/overflow guard exceptions
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(copyRow!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Call)); // ensureCapacity
            Assert.Equal(2, CountArrayElementLoads(copyRow!));
            Assert.Equal(2, CountArrayElementStores(copyRow!));

            return 0;
        });
    }

    [Fact]
    public void EnumColumnUpdates_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
            }

            enum NodeKind {
                Unknown,
                Identifier,
                Literal,
                Error
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].kind = NodeKind.Identifier
                oldRow := nodes[row].kind++
                oldDirect := nodes.kind[row]++
                oldFromEnd := nodes.kind[^1]--
                preRow := ++nodes[row].kind
                preDirect := --nodes.kind[row]
                preFromEnd := ++nodes.kind[^1]
                current := nodes[row].kind

                total := oldRow == NodeKind.Identifier ? 1000000 : 0
                total += oldDirect == NodeKind.Literal ? 100000 : 0
                total += oldFromEnd == NodeKind.Error ? 10000 : 0
                total += preRow == NodeKind.Error ? 1000 : 0
                total += preDirect == NodeKind.Literal ? 100 : 0
                total += preFromEnd == NodeKind.Error ? 10 : 0
                total += current == NodeKind.Error ? 1 : 0
                return total
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

            Assert.Equal(1111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 4,
                "Enum SoA updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(update) >= 7,
                "Enum SoA updates should read current and returned values from the backing array.");
            Assert.Equal(7, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void EnumColumnDefaultStores_ReturnDefaultWithoutOldElementRead()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
            }

            enum NodeKind {
                Unknown,
                Identifier
            }

            func clear(nodes: NodeTable, row: int): int {
                nodes[row].kind = NodeKind.Identifier
                rowDefault := nodes[row].kind = default
                nodes.kind[row] = NodeKind.Identifier
                directDefault := nodes.kind[row] = default
                nodes.kind[^1] = NodeKind.Identifier
                fromEndDefault := nodes.kind[^1] = default

                total := rowDefault == NodeKind.Unknown ? 100 : 0
                total += directDefault == NodeKind.Unknown ? 10 : 0
                total += fromEndDefault == NodeKind.Unknown ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return clear(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clear = ILShapeInspector.GetProgramMethod(assembly, "clear");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clear);
            Assert.True(
                ILShapeInspector.CountOpcode(clear, OpCodes.Ldfld) >= 6,
                "Enum SoA default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clear));
            Assert.Equal(6, CountArrayElementStores(clear));

            return 0;
        });
    }

    [Fact]
    public void EnumColumnBitwiseExpressions_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
            }

            enum NodeKind {
                Unknown = 0,
                Identifier = 1,
                Literal = 2,
                Both = 3
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].kind = NodeKind.Identifier
                rowValue := nodes[row].kind = nodes[row].kind | NodeKind.Literal
                directValue := nodes.kind[row] = nodes.kind[row] ^ NodeKind.Identifier
                fromEndValue := nodes.kind[^1] = nodes.kind[^1] & NodeKind.Literal

                total := rowValue == NodeKind.Both ? 100 : 0
                total += directValue == NodeKind.Literal ? 10 : 0
                total += fromEndValue == NodeKind.Literal ? 1 : 0
                return total
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

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 4,
                "Enum SoA bitwise stores should load backing column fields directly.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(4, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void BoolColumnBitwiseExpressions_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].active = false
                rowValue := nodes[row].active = nodes[row].active | true
                nodes.active[row] = true
                directValue := nodes.active[row] = nodes.active[row] ^ true
                nodes.active[^1] = true
                fromEndValue := nodes.active[^1] = nodes.active[^1] & true

                total := rowValue ? 100 : 0
                total += directValue ? 10 : 0
                total += fromEndValue ? 1 : 0
                return total
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

            Assert.Equal(101, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 6,
                "Bool SoA bitwise stores should load backing column fields directly.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(6, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Or) >= 1,
                "Bool SoA bitwise-or should use the direct OR opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Xor) >= 1,
                "Bool SoA bitwise-xor should use the direct XOR opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.And) >= 1,
                "Bool SoA bitwise-and should use the direct AND opcode.");

            return 0;
        });
    }

    [Fact]
    public void BoolColumnLogicalNot_UsesColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].active = false
                rowValue := nodes[row].active = !nodes[row].active

                nodes.active[directRow] = true
                directValue := nodes.active[directRow] = !nodes.active[directRow]

                nodes.active[^1] = false
                fromEndValue := nodes.active[^1] = !nodes.active[^1]

                total := rowValue ? 100 : 0
                total += directValue ? 10 : 0
                total += fromEndValue ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(101, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 6,
                "Bool SoA logical-not stores should load backing column fields directly.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(6, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ceq) >= 3,
                "Bool SoA logical-not should lower through direct comparison opcodes.");

            return 0;
        });
    }

    [Fact]
    public void BoolColumnLogicalExpressions_UseColumnArrayLoadStoreAndShortCircuitBranchesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
                ready: bool
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].active = true
                nodes[row].ready = true
                rowAnd := nodes[row].active = nodes[row].active && nodes[row].ready
                nodes[row].ready = false
                rowOr := nodes[row].ready = nodes[row].active || nodes[row].ready

                nodes.active[directRow] = true
                nodes.ready[directRow] = false
                directAnd := nodes.active[directRow] = nodes.active[directRow] && nodes.ready[directRow]
                nodes.ready[directRow] = true
                directOr := nodes.ready[directRow] = nodes.active[directRow] || nodes.ready[directRow]

                nodes.active[^1] = false
                nodes.ready[^1] = true
                fromEndAnd := nodes.active[^1] = nodes.active[^1] && nodes.ready[^1]
                fromEndOr := nodes.ready[^1] = nodes.active[^1] || nodes.ready[^1]

                total := rowAnd ? 100000 : 0
                total += rowOr ? 10000 : 0
                total += directAnd ? 1000 : 0
                total += directOr ? 100 : 0
                total += fromEndAnd ? 10 : 0
                total += fromEndOr ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(110101, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 20,
                "Bool SoA logical expressions should load backing column fields directly.");
            Assert.Equal(12, CountArrayElementLoads(update));
            Assert.Equal(14, CountArrayElementStores(update));
            Assert.True(
                CountOpcodes(update, OpCodes.Brfalse, OpCodes.Brfalse_S) >= 6,
                "Bool SoA logical-and should lower through short-circuit false branches.");
            Assert.True(
                CountOpcodes(update, OpCodes.Brtrue, OpCodes.Brtrue_S) >= 6,
                "Bool SoA logical-or should lower through short-circuit true branches.");

            return 0;
        });
    }

    [Fact]
    public void BoolColumnEquality_UsesColumnArrayLoadsAndComparisonOpcodesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
            }

            func compare(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].active = true
                rowScore := nodes[row].active == true ? 100000 : 0
                rowScore += nodes[row].active != false ? 10000 : 0

                nodes.active[directRow] = false
                directScore := nodes.active[directRow] == false ? 1000 : 0
                directScore += nodes.active[directRow] != true ? 100 : 0

                nodes.active[^1] = true
                fromEndScore := nodes.active[^1] == true ? 10 : 0
                fromEndScore += nodes.active[^1] != false ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 9,
                "Bool SoA equality should load backing column fields directly.");
            Assert.Equal(6, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ceq) >= 9,
                "Bool SoA equality and inequality should use direct comparison opcodes.");

            return 0;
        });
    }

    [Fact]
    public void CharColumnComparisons_UseColumnArrayLoadsAndComparisonOpcodesOrBranchesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                marker: char
            }

            func compare(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].marker = 'B'
                rowScore := nodes[row].marker == 'B' ? 1 : 0
                rowScore += nodes[row].marker != 'A' ? 1 : 0
                rowScore += nodes[row].marker >= 'A' ? 1 : 0
                rowScore += nodes[row].marker < 'C' ? 1 : 0

                nodes.marker[directRow] = 'm'
                directScore := nodes.marker[directRow] == 'm' ? 1 : 0
                directScore += nodes.marker[directRow] != 'z' ? 1 : 0
                directScore += nodes.marker[directRow] >= 'a' ? 1 : 0
                directScore += nodes.marker[directRow] < 'n' ? 1 : 0

                nodes.marker[^1] = '7'
                fromEndScore := nodes.marker[^1] == '7' ? 1 : 0
                fromEndScore += nodes.marker[^1] != '8' ? 1 : 0
                fromEndScore += nodes.marker[^1] >= '0' ? 1 : 0
                fromEndScore += nodes.marker[^1] < ':' ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(12, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 15,
                "Char SoA comparisons should load backing column fields directly.");
            Assert.Equal(12, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            var equalityComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Ceq);
            var lessThanComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Clt);
            var greaterThanComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Cgt);
            var unsignedLessThanComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Clt_Un);
            var unsignedGreaterThanComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Cgt_Un);
            var relationalBranches = CountOpcodes(
                compare,
                OpCodes.Blt,
                OpCodes.Blt_S,
                OpCodes.Blt_Un,
                OpCodes.Blt_Un_S,
                OpCodes.Ble,
                OpCodes.Ble_S,
                OpCodes.Ble_Un,
                OpCodes.Ble_Un_S,
                OpCodes.Bgt,
                OpCodes.Bgt_S,
                OpCodes.Bgt_Un,
                OpCodes.Bgt_Un_S,
                OpCodes.Bge,
                OpCodes.Bge_S,
                OpCodes.Bge_Un,
                OpCodes.Bge_Un_S);
            Assert.True(
                equalityComparisons >= 6,
                $"Char SoA equality and inequality should use direct comparison opcodes. Actual: {equalityComparisons}.");
            Assert.True(
                lessThanComparisons
                    + greaterThanComparisons
                    + unsignedLessThanComparisons
                    + unsignedGreaterThanComparisons
                    + relationalBranches >= 6,
                "Char SoA relational comparisons should use direct comparison opcodes or branches. " +
                "Actual clt/cgt/clt.un/cgt.un/branches: " +
                $"{lessThanComparisons}/{greaterThanComparisons}/{unsignedLessThanComparisons}/" +
                $"{unsignedGreaterThanComparisons}/{relationalBranches}.");

            return 0;
        });
    }

    [Fact]
    public void CharColumnNumericPromotionExpressions_UseColumnArrayLoadsAndOpcodesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                marker: char
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].marker = 'A'
                rowScore := nodes[row].marker + 1
                rowScore += nodes[row].marker - 60
                rowScore += nodes[row].marker & 15
                rowScore += nodes[row].marker | 2
                rowScore += nodes[row].marker ^ 1

                nodes.marker[directRow] = 'B'
                directScore := nodes.marker[directRow] << 1
                directScore += nodes.marker[directRow] >> 1
                directScore += nodes.marker[directRow] * 2

                nodes.marker[^1] = 'C'
                fromEndScore := ~nodes.marker[^1]
                fromEndScore += nodes.marker[^1] % 10
                fromEndScore += nodes.marker[^1] / 2

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(472, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 14,
                "Char SoA numeric-promotion expressions should load backing column fields directly.");
            Assert.Equal(11, CountArrayElementLoads(update));
            Assert.Equal(3, CountArrayElementStores(update));
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Add) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Sub) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.And) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Or) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Xor) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Shl) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Shr_Un) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Mul) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Rem) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Div) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Not) >= 1);

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnComparisons_UseColumnArrayLoadsAndComparisonOpcodesOrBranchesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                start: long
            }

            func compare(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = -2
                nodes[row].flags = (uint)7
                nodes[row].start = 20L
                rowScore := nodes[row].kind == -2 ? 1 : 0
                rowScore += nodes[row].kind != 5 ? 1 : 0
                rowScore += nodes[row].kind < 0 ? 1 : 0
                rowScore += nodes[row].kind >= -2 ? 1 : 0
                rowScore += nodes[row].flags == (uint)7 ? 1 : 0
                rowScore += nodes[row].flags != (uint)3 ? 1 : 0
                rowScore += nodes[row].flags < (uint)10 ? 1 : 0
                rowScore += nodes[row].flags >= (uint)7 ? 1 : 0
                rowScore += nodes[row].start == 20L ? 1 : 0
                rowScore += nodes[row].start != 99L ? 1 : 0
                rowScore += nodes[row].start > 10L ? 1 : 0
                rowScore += nodes[row].start <= 20L ? 1 : 0

                nodes.kind[directRow] = 12
                nodes.flags[directRow] = (uint)100
                nodes.start[directRow] = -5L
                directScore := nodes.kind[directRow] == 12 ? 1 : 0
                directScore += nodes.kind[directRow] != -1 ? 1 : 0
                directScore += nodes.kind[directRow] > 10 ? 1 : 0
                directScore += nodes.kind[directRow] <= 12 ? 1 : 0
                directScore += nodes.flags[directRow] == (uint)100 ? 1 : 0
                directScore += nodes.flags[directRow] != (uint)50 ? 1 : 0
                directScore += nodes.flags[directRow] > (uint)90 ? 1 : 0
                directScore += nodes.flags[directRow] <= (uint)100 ? 1 : 0
                directScore += nodes.start[directRow] == -5L ? 1 : 0
                directScore += nodes.start[directRow] != 0L ? 1 : 0
                directScore += nodes.start[directRow] < 0L ? 1 : 0
                directScore += nodes.start[directRow] >= -5L ? 1 : 0

                nodes.kind[^1] = 4
                nodes.flags[^1] = (uint)2
                nodes.start[^1] = 1000L
                fromEndScore := nodes.kind[^1] == 4 ? 1 : 0
                fromEndScore += nodes.kind[^1] != 9 ? 1 : 0
                fromEndScore += nodes.kind[^1] < 5 ? 1 : 0
                fromEndScore += nodes.kind[^1] >= 4 ? 1 : 0
                fromEndScore += nodes.flags[^1] == (uint)2 ? 1 : 0
                fromEndScore += nodes.flags[^1] != (uint)9 ? 1 : 0
                fromEndScore += nodes.flags[^1] < (uint)3 ? 1 : 0
                fromEndScore += nodes.flags[^1] >= (uint)2 ? 1 : 0
                fromEndScore += nodes.start[^1] == 1000L ? 1 : 0
                fromEndScore += nodes.start[^1] != 1L ? 1 : 0
                fromEndScore += nodes.start[^1] > 999L ? 1 : 0
                fromEndScore += nodes.start[^1] <= 1000L ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(36, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 45,
                "Numeric SoA comparisons should load backing column fields directly.");
            Assert.Equal(36, CountArrayElementLoads(compare));
            Assert.Equal(9, CountArrayElementStores(compare));

            var equalityComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Ceq)
                + CountOpcodes(compare, OpCodes.Beq, OpCodes.Beq_S, OpCodes.Bne_Un, OpCodes.Bne_Un_S);
            var signedRelationalComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Clt)
                + ILShapeInspector.CountOpcode(compare, OpCodes.Cgt)
                + CountOpcodes(
                    compare,
                    OpCodes.Blt,
                    OpCodes.Blt_S,
                    OpCodes.Ble,
                    OpCodes.Ble_S,
                    OpCodes.Bgt,
                    OpCodes.Bgt_S,
                    OpCodes.Bge,
                    OpCodes.Bge_S);
            var unsignedRelationalComparisons = ILShapeInspector.CountOpcode(compare, OpCodes.Clt_Un)
                + ILShapeInspector.CountOpcode(compare, OpCodes.Cgt_Un)
                + CountOpcodes(
                    compare,
                    OpCodes.Blt_Un,
                    OpCodes.Blt_Un_S,
                    OpCodes.Ble_Un,
                    OpCodes.Ble_Un_S,
                    OpCodes.Bgt_Un,
                    OpCodes.Bgt_Un_S,
                    OpCodes.Bge_Un,
                    OpCodes.Bge_Un_S);

            Assert.True(
                equalityComparisons >= 18,
                $"Numeric SoA equality and inequality should use direct comparison opcodes or branches. Actual: {equalityComparisons}.");
            Assert.True(
                signedRelationalComparisons >= 12,
                $"Signed int/long SoA relational comparisons should use direct comparison opcodes or branches. Actual: {signedRelationalComparisons}.");
            Assert.True(
                unsignedRelationalComparisons >= 6,
                $"Unsigned uint SoA relational comparisons should use unsigned comparison opcodes or branches. Actual: {unsignedRelationalComparisons}.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnBitwiseExpressions_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 10
                rowInt := nodes[row].kind = nodes[row].kind | 5
                nodes[row].flags = (uint)12
                rowUInt := nodes[row].flags = nodes[row].flags & (uint)10
                nodes[row].mask = 3L
                rowLong := nodes[row].mask = nodes[row].mask ^ 10L

                nodes.kind[directRow] = 12
                directInt := nodes.kind[directRow] = nodes.kind[directRow] & 10
                nodes.flags[directRow] = (uint)3
                directUInt := nodes.flags[directRow] = nodes.flags[directRow] | (uint)8
                nodes.mask[directRow] = 15L
                directLong := nodes.mask[directRow] = nodes.mask[directRow] & 6L

                nodes.kind[^1] = 6
                fromEndInt := nodes.kind[^1] = nodes.kind[^1] ^ 3
                nodes.flags[^1] = (uint)5
                fromEndUInt := nodes.flags[^1] = nodes.flags[^1] ^ (uint)12
                nodes.mask[^1] = 8L
                fromEndLong := nodes.mask[^1] = nodes.mask[^1] | 1L

                total := rowInt + (int)rowUInt + (int)rowLong
                total += directInt + (int)directUInt + (int)directLong
                total += fromEndInt + (int)fromEndUInt + (int)fromEndLong
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(80, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 18,
                "Numeric SoA bitwise stores should load backing column fields directly.");
            Assert.Equal(9, CountArrayElementLoads(update));
            Assert.Equal(18, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Or) >= 3,
                "Numeric SoA bitwise-or should use the direct OR opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.And) >= 3,
                "Numeric SoA bitwise-and should use the direct AND opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Xor) >= 3,
                "Numeric SoA bitwise-xor should use the direct XOR opcode.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnUnaryBitwiseNot_UsesColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 1
                rowInt := nodes[row].kind = ~nodes[row].kind
                nodes[row].flags = (uint)0
                rowUInt := nodes[row].flags = ~nodes[row].flags
                nodes[row].mask = 2L
                rowLong := nodes[row].mask = ~nodes[row].mask

                nodes.kind[directRow] = 3
                directInt := nodes.kind[directRow] = ~nodes.kind[directRow]
                nodes.flags[directRow] = (uint)1
                directUInt := nodes.flags[directRow] = ~nodes.flags[directRow]
                nodes.mask[directRow] = 4L
                directLong := nodes.mask[directRow] = ~nodes.mask[directRow]

                nodes.kind[^1] = 5
                fromEndInt := nodes.kind[^1] = ~nodes.kind[^1]
                nodes.flags[^1] = (uint)2
                fromEndUInt := nodes.flags[^1] = ~nodes.flags[^1]
                nodes.mask[^1] = 6L
                fromEndLong := nodes.mask[^1] = ~nodes.mask[^1]

                total := rowInt == -2 ? 100000000 : 0
                total += rowUInt > (uint)0 ? 10000000 : 0
                total += rowLong == -3L ? 1000000 : 0
                total += directInt == -4 ? 100000 : 0
                total += directUInt > (uint)0 ? 10000 : 0
                total += directLong == -5L ? 1000 : 0
                total += fromEndInt == -6 ? 100 : 0
                total += fromEndUInt > (uint)0 ? 10 : 0
                total += fromEndLong == -7L ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 18,
                "Numeric SoA unary bitwise-not stores should load backing column fields directly.");
            Assert.Equal(9, CountArrayElementLoads(update));
            Assert.Equal(18, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Not) >= 9,
                "Numeric SoA unary bitwise-not should use the direct NOT opcode.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnUnaryNegation_UsesColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 7
                rowInt := nodes[row].kind = -nodes[row].kind
                nodes[row].mask = 11L
                rowLong := nodes[row].mask = -nodes[row].mask

                nodes.kind[directRow] = 13
                directInt := nodes.kind[directRow] = -nodes.kind[directRow]
                nodes.mask[directRow] = 17L
                directLong := nodes.mask[directRow] = -nodes.mask[directRow]

                nodes.kind[^1] = 19
                fromEndInt := nodes.kind[^1] = -nodes.kind[^1]
                nodes.mask[^1] = 23L
                fromEndLong := nodes.mask[^1] = -nodes.mask[^1]

                return rowInt + (int)rowLong + directInt + (int)directLong + fromEndInt + (int)fromEndLong
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(-90, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 12,
                "Signed numeric SoA unary negation stores should load backing column fields directly.");
            Assert.Equal(6, CountArrayElementLoads(update));
            Assert.Equal(12, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Neg) >= 6,
                "Signed numeric SoA unary negation should use the direct NEG opcode.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnShiftExpressions_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 4
                rowInt := nodes[row].kind = nodes[row].kind << 2
                nodes[row].flags = (uint)16
                rowUInt := nodes[row].flags = nodes[row].flags >> 2
                nodes[row].mask = 8L
                rowLong := nodes[row].mask = nodes[row].mask << 1

                nodes.kind[directRow] = -16
                directInt := nodes.kind[directRow] = nodes.kind[directRow] >> 2
                nodes.flags[directRow] = (uint)1
                directUInt := nodes.flags[directRow] = nodes.flags[directRow] << 3
                nodes.mask[directRow] = -16L
                directLong := nodes.mask[directRow] = nodes.mask[directRow] >> 1

                nodes.kind[^1] = 7
                fromEndInt := nodes.kind[^1] = nodes.kind[^1] << 1
                nodes.flags[^1] = (uint)8
                fromEndUInt := nodes.flags[^1] = nodes.flags[^1] >> 1
                nodes.mask[^1] = 3L
                fromEndLong := nodes.mask[^1] = nodes.mask[^1] << 2

                total := rowInt + (int)rowUInt + (int)rowLong
                total += directInt + (int)directUInt + (int)directLong
                total += fromEndInt + (int)fromEndUInt + (int)fromEndLong
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(62, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 18,
                "Numeric SoA shift stores should load backing column fields directly.");
            Assert.Equal(9, CountArrayElementLoads(update));
            Assert.Equal(18, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Shl) >= 5,
                "Numeric SoA left shifts should use the direct SHL opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Shr) >= 2,
                "Signed int/long SoA right shifts should use the direct SHR opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Shr_Un) >= 2,
                "Unsigned uint SoA right shifts should use the direct SHR.UN opcode.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnArithmeticExpressions_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 10
                rowInt := nodes[row].kind = nodes[row].kind + 5
                nodes[row].flags = (uint)20
                rowUInt := nodes[row].flags = nodes[row].flags / (uint)4
                nodes[row].mask = 7L
                rowLong := nodes[row].mask = nodes[row].mask * 3L

                nodes.kind[directRow] = 20
                directInt := nodes.kind[directRow] = nodes.kind[directRow] - 6
                nodes.flags[directRow] = (uint)22
                directUInt := nodes.flags[directRow] = nodes.flags[directRow] % (uint)5
                nodes.mask[directRow] = 22L
                directLong := nodes.mask[directRow] = nodes.mask[directRow] / 2L

                nodes.kind[^1] = 23
                fromEndInt := nodes.kind[^1] = nodes.kind[^1] % 7
                nodes.flags[^1] = (uint)3
                fromEndUInt := nodes.flags[^1] = nodes.flags[^1] * (uint)4
                nodes.mask[^1] = 30L
                fromEndLong := nodes.mask[^1] = nodes.mask[^1] - 8L

                total := rowInt + (int)rowUInt + (int)rowLong
                total += directInt + (int)directUInt + (int)directLong
                total += fromEndInt + (int)fromEndUInt + (int)fromEndLong
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(104, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 18,
                "Numeric SoA arithmetic stores should load backing column fields directly.");
            Assert.Equal(9, CountArrayElementLoads(update));
            Assert.Equal(18, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Add) >= 1,
                "Numeric SoA addition should use the direct ADD opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Sub) >= 2,
                "Numeric SoA subtraction should use the direct SUB opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Mul) >= 2,
                "Numeric SoA multiplication should use the direct MUL opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Div) >= 1,
                "Signed int/long SoA division should use the direct DIV opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Rem) >= 1,
                "Signed int/long SoA remainder should use the direct REM opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Div_Un) >= 1,
                "Unsigned uint SoA division should use the direct DIV.UN opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Rem_Un) >= 1,
                "Unsigned uint SoA remainder should use the direct REM.UN opcode.");

            return 0;
        });
    }

    [Fact]
    public void NumericScalarColumnCompoundAssignments_UseColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].kind = 10
                rowInt := nodes[row].kind += 5
                nodes[row].flags = (uint)20
                rowUInt := nodes[row].flags /= (uint)4
                nodes[row].mask = 7L
                rowLong := nodes[row].mask *= 3L

                nodes.kind[directRow] = 20
                directInt := nodes.kind[directRow] -= 6
                nodes.flags[directRow] = (uint)3
                directUInt := nodes.flags[directRow] += (uint)8
                nodes.mask[directRow] = 22L
                directLong := nodes.mask[directRow] /= 2L

                nodes.kind[^1] = 4
                fromEndInt := nodes.kind[^1] *= 3
                nodes.flags[^1] = (uint)20
                fromEndUInt := nodes.flags[^1] -= (uint)9
                nodes.mask[^1] = 30L
                fromEndLong := nodes.mask[^1] += 8L

                total := rowInt + (int)rowUInt + (int)rowLong
                total += directInt + (int)directUInt + (int)directLong
                total += fromEndInt + (int)fromEndUInt + (int)fromEndLong
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(138, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 18,
                "Numeric SoA compound assignments should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(update) >= 9,
                "Numeric SoA compound assignments should read current values from backing column arrays.");
            Assert.Equal(18, CountArrayElementStores(update));
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Add) >= 3,
                "Numeric SoA compound addition should use the direct ADD opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Sub) >= 2,
                "Numeric SoA compound subtraction should use the direct SUB opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Mul) >= 2,
                "Numeric SoA compound multiplication should use the direct MUL opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Div) >= 1,
                "Signed int/long SoA compound division should use the direct DIV opcode.");
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Div_Un) >= 1,
                "Unsigned uint SoA compound division should use the direct DIV.UN opcode.");

            return 0;
        });
    }

    [Fact]
    public void StringColumnEquality_UsesColumnArrayLoadsAndStringOperatorsWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
            }

            func compare(nodes: NodeTable, row: int): int {
                nodes[row].name = "alpha"
                rowScore := nodes[row].name == "alpha" ? 100000 : 0
                rowScore += nodes[row].name != "beta" ? 10000 : 0

                nodes.name[row] = "beta"
                directScore := nodes.name[row] == "beta" ? 1000 : 0
                directScore += nodes.name[row] != "alpha" ? 100 : 0

                nodes.name[^1] = "gamma"
                fromEndScore := nodes.name[^1] == "gamma" ? 10 : 0
                fromEndScore += nodes.name[^1] != "beta" ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 9,
                "String SoA equality should load backing column fields directly.");
            Assert.Equal(6, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Equality"));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Inequality"));

            return 0;
        });
    }

    [Fact]
    public void NullableStringColumnEquality_UsesColumnArrayLoadsAndStringOperatorsWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string?
            }

            func compare(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].name = "alpha"
                rowScore := nodes[row].name == "alpha" ? 100000 : 0
                rowScore += nodes[row].name != "beta" ? 10000 : 0

                nodes.name[directRow] = "beta"
                directScore := nodes.name[directRow] == "beta" ? 1000 : 0
                directScore += nodes.name[directRow] != "alpha" ? 100 : 0

                nodes.name[^1] = "gamma"
                fromEndScore := nodes.name[^1] == "gamma" ? 10 : 0
                fromEndScore += nodes.name[^1] != "beta" ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 9,
                "Nullable string SoA equality should load backing column fields directly.");
            Assert.Equal(6, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Equality"));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Inequality"));

            return 0;
        });
    }

    [Fact]
    public void NullableStringColumnNullEquality_UsesColumnArrayLoadsAndNullBranchesWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                optionalName: string?
            }

            func compare(nodes: NodeTable, row: int): int {
                directRow := row + 1

                rowScore := nodes[row].optionalName == null ? 100000 : 0
                nodes[row].optionalName = "row"
                rowScore += nodes[row].optionalName != null ? 10000 : 0

                directScore := nodes.optionalName[directRow] == null ? 1000 : 0
                nodes.optionalName[directRow] = "direct"
                directScore += nodes.optionalName[directRow] != null ? 100 : 0

                fromEndScore := nodes.optionalName[^1] == null ? 10 : 0
                nodes.optionalName[^1] = "last"
                fromEndScore += nodes.optionalName[^1] != null ? 1 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 9,
                "Nullable string SoA null equality should load backing column fields directly.");
            Assert.Equal(6, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Brfalse) >= 3,
                "Nullable string SoA equality should branch on null references directly.");
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Brtrue) >= 3,
                "Nullable string SoA inequality should branch on non-null references directly.");
            Assert.Equal(0, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Equality"));
            Assert.Equal(0, ILShapeInspector.CountCallsTo(compare, typeof(string), "op_Inequality"));

            return 0;
        });
    }

    [Fact]
    public void StringColumnConcatenationExpressions_UseColumnArrayLoadStoreAndStringConcatWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                nodes[row].name = "row"
                rowValue := nodes[row].name = nodes[row].name + "-value"

                nodes.name[directRow] = "direct"
                directValue := nodes.name[directRow] = nodes.name[directRow] + "-value"

                nodes.name[^1] = "last"
                fromEndValue := nodes.name[^1] = nodes.name[^1] + "-value"

                total := rowValue == "row-value" ? 100 : 0
                total += directValue == "direct-value" ? 10 : 0
                total += fromEndValue == "last-value" ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            var fieldLoads = ILShapeInspector.CountOpcode(update, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 6,
                $"String SoA concatenation expressions should load backing column fields directly; saw {fieldLoads} field loads.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(6, CountArrayElementStores(update));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(update, typeof(string), nameof(string.Concat)));

            return 0;
        });
    }

    [Fact]
    public void NullableStringColumnConcatenationExpressions_UseColumnArrayLoadStoreAndStringConcatWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string?
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                rowValue := nodes[row].name = nodes[row].name + "row"

                nodes.name[directRow] = "direct"
                directValue := nodes.name[directRow] = nodes.name[directRow] + "-suffix"

                fromEndValue := nodes.name[^1] = nodes.name[^1] + "last"

                total := rowValue == "row" ? 100 : 0
                total += directValue == "direct-suffix" ? 10 : 0
                total += fromEndValue == "last" ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            var fieldLoads = ILShapeInspector.CountOpcode(update, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 4,
                $"Nullable string SoA concatenation expressions should load backing column fields directly; saw {fieldLoads} field loads.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(4, CountArrayElementStores(update));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(update, typeof(string), nameof(string.Concat)));

            return 0;
        });
    }

    [Fact]
    public void StringColumnCompoundAssignment_UsesColumnArrayLoadStoreAndStringConcat()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].name = "a"
                rowValue := nodes[row].name += "b"

                nodes.name[row] = "c"
                directValue := nodes.name[row] += "d"

                nodes.name[^1] = "e"
                fromEndValue := nodes.name[^1] += "f"

                total := rowValue == "ab" ? 100 : 0
                total += directValue == "cd" ? 10 : 0
                total += fromEndValue == "ef" ? 1 : 0
                return total
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

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            var fieldLoads = ILShapeInspector.CountOpcode(update, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 6,
                $"String SoA compound assignment should load backing column fields directly; saw {fieldLoads} field loads.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(6, CountArrayElementStores(update));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(update, typeof(string), nameof(string.Concat)));

            return 0;
        });
    }

    [Fact]
    public void NullableStringColumnCompoundAssignment_UsesColumnArrayLoadStoreAndStringConcat()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string?
            }

            func update(nodes: NodeTable, row: int): int {
                directRow := row + 1

                rowValue := nodes[row].name += "row"

                nodes.name[directRow] = "direct"
                directValue := nodes.name[directRow] += "-suffix"

                fromEndValue := nodes.name[^1] += "last"

                total := rowValue == "row" ? 100 : 0
                total += directValue == "direct-suffix" ? 10 : 0
                total += fromEndValue == "last" ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes.add()
                nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            var fieldLoads = ILShapeInspector.CountOpcode(update, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 4,
                $"Nullable string SoA compound assignment should load backing column fields directly; saw {fieldLoads} field loads.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(4, CountArrayElementStores(update));
            Assert.Equal(3, ILShapeInspector.CountCallsTo(update, typeof(string), nameof(string.Concat)));

            return 0;
        });
    }

    [Fact]
    public void EnumColumnUnaryBitwiseNot_UsesColumnArrayLoadStoreWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
            }

            enum NodeKind {
                Unknown = 0,
                Identifier = 1,
                Literal = 2
            }

            func update(nodes: NodeTable, row: int): int {
                nodes[row].kind = NodeKind.Identifier
                rowValue := nodes[row].kind = ~nodes[row].kind
                nodes.kind[row] = NodeKind.Literal
                directValue := nodes.kind[row] = ~nodes.kind[row]
                nodes.kind[^1] = NodeKind.Unknown
                fromEndValue := nodes.kind[^1] = ~nodes.kind[^1]
                return (int)rowValue * 100 + (int)directValue * 10 + (int)fromEndValue
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

            Assert.Equal(-231, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 6,
                "Enum SoA unary bitwise stores should load backing column fields directly.");
            Assert.Equal(3, CountArrayElementLoads(update));
            Assert.Equal(6, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void EnumColumnComparisons_UseColumnArrayLoadsWithoutRowOrSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: NodeKind
            }

            enum NodeKind {
                Unknown = 0,
                Identifier = 1,
                Literal = 2,
                Error = 3
            }

            func compare(nodes: NodeTable, row: int): int {
                nodes[row].kind = NodeKind.Identifier
                rowScore := nodes[row].kind == NodeKind.Identifier ? 100000 : 0
                rowScore += nodes[row].kind != NodeKind.Literal ? 10000 : 0
                rowScore += nodes[row].kind < NodeKind.Literal ? 1000 : 0
                rowScore += nodes[row].kind <= NodeKind.Identifier ? 100 : 0
                rowScore += nodes[row].kind > NodeKind.Unknown ? 10 : 0
                rowScore += nodes[row].kind >= NodeKind.Identifier ? 1 : 0

                nodes.kind[row] = NodeKind.Literal
                directScore := nodes.kind[row] == NodeKind.Literal ? 200000 : 0
                directScore += nodes.kind[row] != NodeKind.Identifier ? 20000 : 0
                directScore += nodes.kind[row] > NodeKind.Identifier ? 2000 : 0
                directScore += nodes.kind[row] >= NodeKind.Literal ? 200 : 0
                directScore += nodes.kind[row] < NodeKind.Error ? 20 : 0
                directScore += nodes.kind[row] <= NodeKind.Literal ? 2 : 0

                nodes.kind[^1] = NodeKind.Identifier
                fromEndScore := nodes.kind[^1] == NodeKind.Identifier ? 300000 : 0
                fromEndScore += nodes.kind[^1] != NodeKind.Literal ? 30000 : 0
                fromEndScore += nodes.kind[^1] < NodeKind.Literal ? 3000 : 0
                fromEndScore += nodes.kind[^1] <= NodeKind.Identifier ? 300 : 0
                fromEndScore += nodes.kind[^1] > NodeKind.Unknown ? 30 : 0
                fromEndScore += nodes.kind[^1] >= NodeKind.Identifier ? 3 : 0

                return rowScore + directScore + fromEndScore
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return compare(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var compare = ILShapeInspector.GetProgramMethod(assembly, "compare");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(666666, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(compare);
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ldfld) >= 21,
                "Enum SoA comparisons should load backing column fields directly.");
            Assert.Equal(18, CountArrayElementLoads(compare));
            Assert.Equal(3, CountArrayElementStores(compare));
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Ceq) >= 15,
                "Enum SoA equality comparisons should use direct comparison opcodes.");
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Clt) >= 6,
                "Enum SoA less-than comparisons should use direct comparison opcodes.");
            Assert.True(
                ILShapeInspector.CountOpcode(compare, OpCodes.Cgt) >= 6,
                "Enum SoA greater-than comparisons should use direct comparison opcodes.");

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
