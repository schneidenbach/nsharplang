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
    public void HardCastedDirectColumnElementAccess_UsesColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func update(nodes: Nodes, row: int): int {
                ((NodeTable)nodes).kind[row] = 3
                ((Nodes)((NodeTable)nodes)).kind[row] += 4
                old := ((NodeTable)((Nodes)nodes)).kind[row]++
                ((Nodes)((NodeTable)nodes)).start[row] = old + ((NodeTable)nodes).kind[row]
                return old * 100 + ((Nodes)((NodeTable)nodes)).kind[row] * 10 + ((NodeTable)nodes).start[row]
            }

            func main(): int {
                nodes := new Nodes(1)
                row := nodes.add()
                return update(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(795, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 6,
                "Hard-casted direct SoA column element operations should load backing column fields directly.");
            Assert.Equal(5, CountArrayElementLoads(update));
            Assert.Equal(4, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnElementAccessCheckedUncheckedWrappers_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func update(nodes: NodeTable, row: int): int {
                (checked(nodes.kind))[row] = 3
                (unchecked(nodes.kind))[row] += 4
                old := (checked(nodes.kind))[row]++
                (unchecked(nodes.start))[^1] = old
                idx := ^1
                total := old * 1000
                total += (checked(nodes.kind))[row] * 100
                total += (unchecked(nodes.start))[idx] * 10
                total += checked(nodes.start).Length
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

            Assert.Equal(7871, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 7,
                "Checked/unchecked direct SoA column element operations should load backing column fields directly.");
            Assert.Equal(3, ILShapeInspector.CountOpcode(update, OpCodes.Ldlen));
            Assert.Equal(4, CountArrayElementLoads(update));
            Assert.Equal(4, CountArrayElementStores(update));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnAssignmentExpressionsCheckedUncheckedWrappers_ReturnAssignedValueWithoutOldElementRead()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func assign(nodes: NodeTable, row: int): int {
                idx := ^1
                rowKind := (checked(nodes.kind))[row] = 11
                rowStart := (unchecked(nodes.start))[row] = rowKind + 2
                literalKind := (checked(nodes.kind))[^1] = 23
                literalStart := (unchecked(nodes.start))[^1] = literalKind + 4
                variableKind := (unchecked(nodes.kind))[idx] = literalKind + 6
                variableStart := (checked(nodes.start))[idx] = variableKind + 8
                return rowKind + rowStart * 10 + literalKind * 100 + literalStart * 1000 + variableKind * 10000 + variableStart * 100000
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                assigned := assign(nodes, first)
                stored := nodes.kind[first] + nodes.start[first] * 10
                stored += nodes.kind[^1] * 100 + nodes.start[^1] * 1000
                return assigned + stored
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var assign = ILShapeInspector.GetProgramMethod(assembly, "assign");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(4059482, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(assign);
            Assert.True(
                ILShapeInspector.CountOpcode(assign, OpCodes.Ldfld) >= 6,
                "Checked/unchecked direct SoA column assignment expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(assign));
            Assert.Equal(6, CountArrayElementStores(assign));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnNumericUpdatesCheckedUncheckedWrappers_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func update(nodes: NodeTable, row: int): int {
                idx := ^1

                (checked(nodes.kind))[row] = 10
                rowCompound := (unchecked(nodes.kind))[row] += 5
                rowPost := (checked(nodes.kind))[row]++
                rowPre := ++((unchecked(nodes.kind))[row])

                (checked(nodes.kind))[^1] = 20
                literalCompound := (unchecked(nodes.kind))[^1] -= 3
                literalPost := ((checked(nodes.kind))[^1])--
                literalPre := --((unchecked(nodes.kind))[^1])

                variableCompound := (checked(nodes.kind))[idx] += 2
                variablePost := ((unchecked(nodes.kind))[idx])++
                variablePre := ++((checked(nodes.kind))[idx])

                return rowCompound + rowPost + rowPre
                    + literalCompound + literalPost + literalPre
                    + variableCompound + variablePost + variablePre
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                total := update(nodes, first)
                return total * 1000 + nodes.kind[first] * 10 + nodes.kind[^1]
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(149189, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            Assert.True(
                ILShapeInspector.CountOpcode(update, OpCodes.Ldfld) >= 11,
                "Checked/unchecked direct SoA column numeric updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(update) >= 9,
                "Checked/unchecked direct SoA column numeric updates should read current values from backing arrays.");
            Assert.Equal(11, CountArrayElementStores(update));
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Add) >= 4);
            Assert.True(ILShapeInspector.CountOpcode(update, OpCodes.Sub) >= 3);

            return 0;
        });
    }

    [Fact]
    public void DirectColumnScalarExpressionsCheckedUncheckedWrappers_UseColumnArrayLoadsAndOpcodesWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func evaluate(nodes: NodeTable, row: int): int {
                idx := ^1

                (checked(nodes.kind))[row] = 10
                (unchecked(nodes.flags))[row] = (uint)12
                (checked(nodes.mask))[row] = 3L
                (unchecked(nodes.kind))[^1] = -16
                (checked(nodes.flags))[^1] = (uint)8
                (unchecked(nodes.mask))[^1] = 5L

                rowScore := (checked(nodes.kind))[row] + 2
                rowScore += (int)((unchecked(nodes.flags))[row] & (uint)10)
                rowScore += (int)((checked(nodes.mask))[row] << 2)
                rowScore += (checked(nodes.kind))[row] == 10 ? 100 : 0
                rowScore += (unchecked(nodes.flags))[row] > (uint)10 ? 1000 : 0

                tailScore := (unchecked(nodes.kind))[idx] >> 2
                tailScore += (int)((checked(nodes.flags))[idx] >> 1)
                tailScore += (int)(~((unchecked(nodes.mask))[idx]))
                tailScore += (unchecked(nodes.kind))[idx] < 0 ? 10000 : 0
                tailScore += (checked(nodes.mask))[idx] >= 5L ? 100000 : 0

                return rowScore + tailScore
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                return evaluate(nodes, first)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var evaluate = ILShapeInspector.GetProgramMethod(assembly, "evaluate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111126, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(evaluate);
            Assert.True(
                ILShapeInspector.CountOpcode(evaluate, OpCodes.Ldfld) >= 16,
                "Checked/unchecked direct SoA column scalar expressions should load backing column fields directly.");
            Assert.Equal(10, CountArrayElementLoads(evaluate));
            Assert.Equal(6, CountArrayElementStores(evaluate));
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Add) >= 3);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.And) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Shl) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Shr) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Shr_Un) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Not) >= 1);
            Assert.True(
                ILShapeInspector.CountOpcode(evaluate, OpCodes.Ceq)
                + ILShapeInspector.CountOpcode(evaluate, OpCodes.Clt)
                + ILShapeInspector.CountOpcode(evaluate, OpCodes.Cgt)
                + ILShapeInspector.CountOpcode(evaluate, OpCodes.Clt_Un)
                + ILShapeInspector.CountOpcode(evaluate, OpCodes.Cgt_Un) >= 3);

            return 0;
        });
    }

    [Fact]
    public void DirectColumnReferenceAndBoolExpressionsCheckedUncheckedWrappers_UseColumnArrayLoadsWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
                alias: string?
                active: bool
            }

            func evaluate(nodes: NodeTable, row: int): int {
                idx := ^1

                (checked(nodes.name))[row] = "alpha"
                (unchecked(nodes.alias))[row] = null
                (checked(nodes.active))[row] = true
                (unchecked(nodes.name))[^1] = "tail"
                (checked(nodes.alias))[^1] = "tag"
                (unchecked(nodes.active))[^1] = false

                rowScore := (checked(nodes.name))[row] == "alpha" ? 1 : 0
                rowScore += (unchecked(nodes.name))[row] != "beta" ? 2 : 0
                rowScore += (checked(nodes.alias))[row] == null ? 4 : 0
                rowScore += !(unchecked(nodes.active))[row] ? 0 : 8
                rowScore += ((checked(nodes.active))[row] && (unchecked(nodes.name))[row] == "alpha") ? 16 : 0
                rowScore += ((checked(nodes.active))[row] || false) ? 32 : 0

                tailText := (unchecked(nodes.name))[idx] + (checked(nodes.alias))[idx]
                tailScore := tailText == "tailtag" ? 64 : 0
                tailScore += (unchecked(nodes.active))[idx] == false ? 128 : 0
                return rowScore + tailScore
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                return evaluate(nodes, first)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var evaluate = ILShapeInspector.GetProgramMethod(assembly, "evaluate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(255, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(evaluate);
            Assert.True(
                ILShapeInspector.CountOpcode(evaluate, OpCodes.Ldfld) >= 16,
                "Checked/unchecked direct SoA column reference and bool expressions should load backing column fields directly.");
            Assert.Equal(10, CountArrayElementLoads(evaluate));
            Assert.Equal(6, CountArrayElementStores(evaluate));
            Assert.True(
                ILShapeInspector.CountCallsTo(evaluate, typeof(string), nameof(string.Concat)) >= 1,
                "Checked/unchecked direct SoA string concatenation should call String.Concat without materializing rows or slices.");
            Assert.True(
                ILShapeInspector.CountCallsTo(evaluate, typeof(string), "op_Equality")
                + ILShapeInspector.CountCallsTo(evaluate, typeof(string), "op_Inequality") >= 3,
                "Checked/unchecked direct SoA string comparisons should use string comparison operators.");
            Assert.True(
                CountOpcodes(evaluate, OpCodes.Brfalse, OpCodes.Brfalse_S) >= 1,
                "Checked/unchecked direct SoA bool logical-and should lower through short-circuit false branches.");
            Assert.True(
                CountOpcodes(evaluate, OpCodes.Brtrue, OpCodes.Brtrue_S) >= 1,
                "Checked/unchecked direct SoA bool logical-or should lower through short-circuit true branches.");

            return 0;
        });
    }

    [Fact]
    public void DirectColumnCharAndEnumExpressionsCheckedUncheckedWrappers_UseColumnArrayLoadsAndOpcodesWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                marker: char
                kind: NodeKind
            }

            enum NodeKind {
                Unknown = 0,
                Identifier = 1,
                Literal = 2,
                Both = 3
            }

            func evaluate(nodes: NodeTable, row: int): int {
                idx := ^1

                (checked(nodes.marker))[row] = 'A'
                (unchecked(nodes.kind))[row] = NodeKind.Identifier
                (checked(nodes.marker))[^1] = 'C'
                (unchecked(nodes.kind))[^1] = NodeKind.Both

                rowScore := (checked(nodes.marker))[row] == 'A' ? 1 : 0
                rowScore += (unchecked(nodes.marker))[row] < 'B' ? 2 : 0
                rowScore += ((checked(nodes.marker))[row] + 1) == 66 ? 4 : 0
                rowScore += ((unchecked(nodes.marker))[row] & 15) == 1 ? 8 : 0
                rowKind := (checked(nodes.kind))[row] | NodeKind.Literal
                rowScore += rowKind == NodeKind.Both ? 16 : 0
                rowScore += (unchecked(nodes.kind))[row] < NodeKind.Both ? 32 : 0
                rowScore += (int)(~((checked(nodes.kind))[row])) == -2 ? 64 : 0

                tailScore := (checked(nodes.marker))[idx] == 'C' ? 128 : 0
                tailScore += ((unchecked(nodes.marker))[idx] - 60) == 7 ? 256 : 0
                tailKind := (unchecked(nodes.kind))[idx] & NodeKind.Literal
                tailScore += tailKind == NodeKind.Literal ? 512 : 0
                tailScore += (checked(nodes.kind))[idx] >= NodeKind.Literal ? 1024 : 0
                return rowScore + tailScore
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                return evaluate(nodes, first)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var evaluate = ILShapeInspector.GetProgramMethod(assembly, "evaluate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(2047, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(evaluate);
            Assert.True(
                ILShapeInspector.CountOpcode(evaluate, OpCodes.Ldfld) >= 15,
                "Checked/unchecked direct SoA char and enum expressions should load backing column fields directly.");
            Assert.Equal(11, CountArrayElementLoads(evaluate));
            Assert.Equal(4, CountArrayElementStores(evaluate));
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.And) >= 2);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Or) >= 1);
            Assert.True(ILShapeInspector.CountOpcode(evaluate, OpCodes.Not) >= 1);
            Assert.True(
                CountOpcodes(
                    evaluate,
                    OpCodes.Clt,
                    OpCodes.Cgt,
                    OpCodes.Clt_Un,
                    OpCodes.Cgt_Un,
                    OpCodes.Blt,
                    OpCodes.Blt_S,
                    OpCodes.Blt_Un,
                    OpCodes.Blt_Un_S,
                    OpCodes.Bge,
                    OpCodes.Bge_S,
                    OpCodes.Bge_Un,
                    OpCodes.Bge_Un_S) >= 2,
                "Checked/unchecked direct SoA char and enum relational expressions should use comparison opcodes or branches.");

            return 0;
        });
    }

    [Fact]
    public void DirectColumnStringCompoundAssignmentsCheckedUncheckedWrappers_UseStringConcatWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
                alias: string?
            }

            func update(nodes: NodeTable, row: int): int {
                idx := ^1

                (checked(nodes.name))[row] = "a"
                rowValue := (checked(nodes.name))[row] += "b"

                (unchecked(nodes.name))[^1] = "c"
                tailValue := (unchecked(nodes.name))[idx] += "d"

                rowNullable := (unchecked(nodes.alias))[row] += "row"

                (checked(nodes.alias))[^1] = "tail"
                tailNullable := (checked(nodes.alias))[idx] += "-suffix"

                total := rowValue == "ab" ? 1000 : 0
                total += tailValue == "cd" ? 100 : 0
                total += rowNullable == "row" ? 10 : 0
                total += tailNullable == "tail-suffix" ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                nodes.add()
                return update(nodes, first)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var update = ILShapeInspector.GetProgramMethod(assembly, "update");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1111, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(update);
            var fieldLoads = ILShapeInspector.CountOpcode(update, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 7,
                $"Checked/unchecked direct SoA string compound assignments should load backing column fields directly; saw {fieldLoads} field loads.");
            Assert.Equal(4, CountArrayElementLoads(update));
            Assert.Equal(7, CountArrayElementStores(update));
            Assert.Equal(4, ILShapeInspector.CountCallsTo(update, typeof(string), nameof(string.Concat)));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnNullCoalescingCheckedUncheckedWrappers_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func adopt(nodes: NodeTable, row: int): string {
                missing := (checked(nodes.text))[row] ?? "missing"
                (unchecked(nodes.text))[row] ??= "assigned"
                current := (checked(nodes.text))[row] ??= "ignored"
                (unchecked(nodes.text))[^1] ??= "tail"
                idx := ^1
                tail := (checked(nodes.text))[idx] ?? "fallback"
                return missing + ":" + current + ":" + tail
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return adopt(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var adopt = ILShapeInspector.GetProgramMethod(assembly, "adopt");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal("missing:assigned:assigned", Assert.IsType<string>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(adopt);
            Assert.True(
                ILShapeInspector.CountOpcode(adopt, OpCodes.Ldfld) >= 5,
                "Checked/unchecked direct SoA column null coalescing should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(adopt) >= 5,
                "Checked/unchecked direct SoA column null coalescing should read current values from backing arrays.");
            Assert.Equal(3, CountArrayElementStores(adopt));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnDefaultStoresCheckedUncheckedWrappers_DoNotReadOldElement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clear(nodes: NodeTable, row: int) {
                (checked(nodes.kind))[row] = default
                (unchecked(nodes.text))[row] = default
                (checked(nodes.kind))[^1] = default
                (unchecked(nodes.text))[^1] = default
                idx := ^1
                (checked(nodes.kind))[idx] = default
                (unchecked(nodes.text))[idx] = default
            }

            func clearAsExpression(nodes: NodeTable, row: int): int {
                idx := ^1
                directKind := (checked(nodes.kind))[row] = default
                directText := (unchecked(nodes.text))[row] = default
                literalKind := (checked(nodes.kind))[^1] = default
                literalText := (unchecked(nodes.text))[^1] = default
                variableKind := (checked(nodes.kind))[idx] = default
                variableText := (unchecked(nodes.text))[idx] = default
                total := directKind + literalKind + variableKind
                total += (directText == null ? 10 : 0)
                total += (literalText == null ? 100 : 0)
                total += (variableText == null ? 1000 : 0)
                return total
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                last := nodes.add()

                nodes.kind[first] = 9
                nodes.text[first] = "first"
                nodes.kind[last] = 8
                nodes.text[last] = "last"
                clear(nodes, first)
                afterStatement := nodes.kind[first] + nodes.kind[last]
                afterStatement += (nodes.text[first] == null ? 10 : 0)
                afterStatement += (nodes.text[last] == null ? 100 : 0)

                nodes.kind[first] = 7
                nodes.text[first] = "again"
                nodes.kind[last] = 6
                nodes.text[last] = "tail"
                expression := clearAsExpression(nodes, first)
                afterExpression := nodes.kind[first] + nodes.kind[last]
                afterExpression += (nodes.text[first] == null ? 10000 : 0)
                afterExpression += (nodes.text[last] == null ? 100000 : 0)
                return afterStatement + expression + afterExpression
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clear = ILShapeInspector.GetProgramMethod(assembly, "clear");
            var clearAsExpression = ILShapeInspector.GetProgramMethod(assembly, "clearAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(111220, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clear);
            Assert.True(
                ILShapeInspector.CountOpcode(clear, OpCodes.Ldfld) >= 6,
                "Checked/unchecked direct SoA column default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clear));
            Assert.Equal(6, CountArrayElementStores(clear));

            AssertNoFromEndSliceAllocation(clearAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearAsExpression, OpCodes.Ldfld) >= 6,
                "Checked/unchecked direct SoA column default store expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearAsExpression));
            Assert.Equal(6, CountArrayElementStores(clearAsExpression));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnMetadataProperties_UseBackingArrayLengthWithoutDispatch()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func metadata(nodes: NodeTable): int {
                return nodes.kind.Length + (int)nodes.kind.LongLength + nodes.kind.Rank
            }

            func main(): int {
                nodes := new NodeTable(3)
                return metadata(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var metadata = ILShapeInspector.GetProgramMethod(assembly, "metadata");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(7, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(metadata);
            Assert.Equal(2, ILShapeInspector.CountOpcode(metadata, OpCodes.Ldlen));
            Assert.True(
                ILShapeInspector.CountOpcode(metadata, OpCodes.Ldfld) >= 2,
                "Direct SoA column metadata should load backing column arrays directly.");
            Assert.Equal(0, CountArrayElementLoads(metadata));
            Assert.Equal(0, CountArrayElementStores(metadata));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnMetadataPropertiesCheckedUncheckedWrappers_UseBackingArrayLengthWithoutDispatch()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func metadata(nodes: NodeTable): int {
                return checked(nodes.kind).Length + (int)unchecked(nodes.kind).LongLength + checked(nodes.kind).Rank
            }

            func main(): int {
                nodes := new NodeTable(3)
                return metadata(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var metadata = ILShapeInspector.GetProgramMethod(assembly, "metadata");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(7, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(metadata);
            Assert.Equal(2, ILShapeInspector.CountOpcode(metadata, OpCodes.Ldlen));
            Assert.True(
                ILShapeInspector.CountOpcode(metadata, OpCodes.Ldfld) >= 2,
                "Checked/unchecked direct SoA column metadata should load backing column arrays directly.");
            Assert.Equal(0, CountArrayElementLoads(metadata));
            Assert.Equal(0, CountArrayElementStores(metadata));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperations_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
            }

            func bulk(nodes: NodeTable, source: int[]): int {
                Array.Fill(nodes.kind, 9)
                Array.Copy(source, nodes.kind, 2)
                Array.Clear(nodes.kind, 1, 1)
                return nodes.length * 100 + nodes.kind[0] * 10 + nodes.kind[1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                nodes.add()
                nodes.add()
                source := new int[](2)
                source[0] = 3
                source[1] = 4
                return bulk(nodes, source)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(230, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 6,
                "Direct SoA column bulk operations should load backing column arrays directly.");
            Assert.Equal(2, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationOverloads_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, source: int[]): int {
                Array.Fill(nodes.kind, 7, 1, 2)
                Array.Copy(source, 1, nodes.kind, 0, 2)
                Array.Clear(nodes.start)
                return nodes.length * 1000
                    + nodes.kind[0] * 100
                    + nodes.kind[1] * 10
                    + nodes.kind[2]
                    + nodes.start[0]
                    + nodes.start[1]
                    + nodes.start[2]
            }

            func main(): int {
                nodes := new NodeTable(3)
                first := nodes.add()
                second := nodes.add()
                third := nodes.add()
                nodes.start[first] = 8
                nodes.start[second] = 9
                nodes.start[third] = 10
                source := new int[](3)
                source[0] = 3
                source[1] = 4
                source[2] = 5
                return bulk(nodes, source)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(3457, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 9,
                "Direct SoA column bulk overloads should load backing column arrays directly.");
            Assert.Equal(6, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationNamedArguments_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, source: int[]): int {
                Array.Fill(count: 2, startIndex: 1, value: 7, array: nodes.kind)
                Array.Copy(length: 2, destinationIndex: 0, destinationArray: nodes.kind, sourceIndex: 1, sourceArray: source)
                Array.Clear(array: nodes.start)
                Array.Clear(length: 1, array: nodes.kind, index: 1)
                return nodes.length * 1000
                    + nodes.kind[0] * 100
                    + nodes.kind[1] * 10
                    + nodes.kind[2]
                    + nodes.start[0]
                    + nodes.start[1]
                    + nodes.start[2]
            }

            func main(): int {
                nodes := new NodeTable(3)
                first := nodes.add()
                second := nodes.add()
                third := nodes.add()
                nodes.start[first] = 8
                nodes.start[second] = 9
                nodes.start[third] = 10
                source := new int[](3)
                source[0] = 3
                source[1] = 4
                source[2] = 5
                return bulk(nodes, source)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(3407, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 9,
                "Named direct SoA column bulk operations should load backing column arrays directly.");
            Assert.Equal(6, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationQualifiedNamedArguments_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, source: int[]): int {
                System.Array.Fill(value: 6, array: nodes.kind)
                System.Array.Copy(length: 2, destinationArray: nodes.kind, sourceArray: source)
                System.Array.Clear(length: 1, index: 0, array: nodes.start)
                return nodes.length * 1000
                    + nodes.kind[0] * 100
                    + nodes.kind[1] * 10
                    + nodes.start[0]
                    + nodes.start[1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.start[first] = 8
                nodes.start[second] = 9
                source := new int[](2)
                source[0] = 3
                source[1] = 4
                return bulk(nodes, source)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(2349, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 6,
                "Qualified named direct SoA column bulk operations should load backing column arrays directly.");
            Assert.Equal(4, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationSourceColumnNamedArguments_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, target: int[]): int {
                Array.Copy(length: 2, destinationArray: target, sourceArray: nodes.kind)
                System.Array.Copy(length: 1, destinationIndex: 2, destinationArray: target, sourceIndex: 1, sourceArray: nodes.start)
                return target[0] * 100 + target[1] * 10 + target[2]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 3
                nodes.kind[second] = 4
                nodes.start[first] = 8
                nodes.start[second] = 9
                target := new int[](3)
                return bulk(nodes, target)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(349, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 2,
                "Named direct SoA column Array.Copy source arguments should load backing column arrays directly.");
            Assert.Equal(3, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationSourceColumnPositionalArguments_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, target: int[]): int {
                Array.Copy(nodes.kind, target, 2)
                System.Array.Copy(nodes.start, 1, target, 2, 1)
                return target[0] * 100 + target[1] * 10 + target[2]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 3
                nodes.kind[second] = 4
                nodes.start[first] = 8
                nodes.start[second] = 9
                target := new int[](3)
                return bulk(nodes, target)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(349, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 2,
                "Positional direct SoA column Array.Copy source arguments should load backing column arrays directly.");
            Assert.Equal(3, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnBulkArrayOperationCheckedUncheckedWrappers_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            func bulk(nodes: NodeTable, source: int[], target: int[]): int {
                Array.Fill(array: checked(nodes.kind), value: 6)
                Array.Copy(length: 2, destinationArray: target, sourceArray: unchecked(nodes.kind))
                System.Array.Copy(length: 1, destinationIndex: 1, destinationArray: checked(nodes.start), sourceIndex: 1, sourceArray: source)
                Array.Clear(length: 1, index: 0, array: unchecked(nodes.start))
                return target[0] * 1000 + target[1] * 100 + nodes.start[0] * 10 + nodes.start[1]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 3
                nodes.kind[second] = 4
                nodes.start[first] = 8
                nodes.start[second] = 9
                source := new int[](2)
                source[0] = 3
                source[1] = 4
                target := new int[](2)
                return bulk(nodes, source, target)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(6604, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 4,
                "Checked/unchecked direct SoA column bulk operations should load backing column arrays directly.");
            Assert.Equal(4, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void HardCastedDirectColumnBulkArrayOperations_UseBackingArraysWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            import System

            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func bulk(nodes: Nodes, source: int[], target: int[]): int {
                Array.Fill(((NodeTable)nodes).kind, 6)
                Array.Copy(sourceArray: source, destinationArray: ((Nodes)((NodeTable)nodes)).kind, length: 2)
                System.Array.Clear(array: ((NodeTable)((Nodes)nodes)).start)
                Array.Copy(length: 1, destinationArray: target, sourceArray: ((Nodes)nodes).start)
                return nodes.kind[0] * 1000 + nodes.kind[1] * 100 + nodes.start[0] * 10 + nodes.start[1] + target[0]
            }

            func main(): int {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 1
                nodes.kind[second] = 2
                nodes.start[first] = 8
                nodes.start[second] = 9
                source := new int[](2)
                source[0] = 3
                source[1] = 4
                target := new int[](2)
                return bulk(nodes, source, target)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var bulk = ILShapeInspector.GetProgramMethod(assembly, "bulk");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(3400, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(bulk);
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(bulk));
            Assert.Equal(0, ILShapeInspector.CountOpcode(bulk, OpCodes.Callvirt));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Fill)));
            Assert.Equal(2, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Copy)));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(bulk, typeof(Array), nameof(Array.Clear)));
            Assert.True(
                ILShapeInspector.CountOpcode(bulk, OpCodes.Ldfld) >= 6,
                "Hard-casted direct SoA column bulk operations should load backing column arrays directly.");
            Assert.Equal(5, CountArrayElementLoads(bulk));
            Assert.Equal(0, CountArrayElementStores(bulk));

            return 0;
        });
    }

    [Fact]
    public void RowProjectionRefAndOutArguments_UseColumnArrayElementAddress()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 13
            }

            func mutate(nodes: Nodes, row: int): int {
                bump(ref nodes[row].kind)
                reset(out nodes[row].start)
                return nodes[row].kind * 10 + nodes[row].start
            }

            func main(): int {
                nodes := new Nodes(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].start = 4
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(93, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(mutate);
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(mutate));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Callvirt));
            Assert.Equal(2, ILShapeInspector.CountOpcode(mutate, OpCodes.Call));
            Assert.Equal(2, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 4,
                "Row ref/out arguments should load backing column arrays directly.");
            Assert.Equal(4, CountArrayElementLoads(mutate));
            Assert.Equal(0, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnRefAndOutArguments_UseColumnArrayElementAddress()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 17
            }

            func mutate(nodes: Nodes, row: int): int {
                bump(ref nodes.kind[row])
                reset(out nodes.start[^1])
                return nodes.kind[row] * 10 + nodes.start[row]
            }

            func main(): int {
                nodes := new Nodes(1)
                row := nodes.add()
                nodes.kind[row] = 2
                nodes.start[row] = 3
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(87, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(mutate);
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 4,
                "Direct column ref/out arguments should load backing column arrays directly.");
            Assert.Equal(2, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            Assert.Equal(4, CountArrayElementLoads(mutate));
            Assert.Equal(0, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void HardCastedDirectColumnRefAndOutArguments_UseColumnArrayElementAddress()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 17
            }

            func mutate(nodes: Nodes, row: int): int {
                bump(ref ((NodeTable)nodes).kind[row])
                reset(out ((Nodes)((NodeTable)nodes)).start[^1])
                return nodes.kind[row] * 10 + nodes.start[row]
            }

            func main(): int {
                nodes := new Nodes(1)
                row := nodes.add()
                nodes.kind[row] = 2
                nodes.start[row] = 3
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(87, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(mutate);
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 4,
                "Hard-cast direct column ref/out arguments should load backing column arrays directly.");
            Assert.Equal(2, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            Assert.Equal(4, CountArrayElementLoads(mutate));
            Assert.Equal(0, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void DirectColumnRefAndOutArgumentsCheckedUncheckedWrappers_UseColumnArrayElementAddress()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
                active: bool
                name: string
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 17
            }

            func flip(ref value: bool) {
                value = !value
            }

            func setName(out value: string) {
                value = "done"
            }

            func mutate(nodes: Nodes, row: int): int {
                bump(ref (checked(nodes.kind))[row])
                reset(out (unchecked(nodes.start))[^1])
                idx := ^1
                bump(ref (unchecked(nodes.kind))[idx])
                flip(ref (checked(nodes.active))[row])
                setName(out (unchecked(nodes.name))[idx])

                score := nodes.kind[row] * 1000
                score += nodes.start[idx] * 100
                score += nodes.kind[idx] * 10
                score += nodes.active[row] ? 1 : 0
                score += nodes.name[idx] == "done" ? 2 : 0
                return score
            }

            func main(): int {
                nodes := new Nodes(2)
                row := nodes.add()
                nodes.add()
                nodes.kind[row] = 2
                nodes.start[row] = 3
                nodes.active[row] = true
                nodes.name[row] = "head"
                nodes.kind[^1] = 4
                nodes.start[^1] = 6
                nodes.active[^1] = false
                nodes.name[^1] = "tail"
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(8792, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(mutate);
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 10,
                "Checked/unchecked direct SoA column ref/out arguments should load backing column arrays directly.");
            Assert.Equal(5, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            Assert.Equal(10, CountArrayElementLoads(mutate));
            Assert.Equal(0, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedRefAndOutArguments_UseColumnArrayElementAddress()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 17
            }

            func mutate(nodes: Nodes, row: int): int {
                bump(ref (nodes[row]).kind)
                reset(out (nodes[row]).start)
                bump(ref ((nodes.kind)[row]))
                reset(out ((nodes.start)[^1]))
                bump(ref (nodes.kind)[row])
                reset(out (nodes.start)[^1])
                idx := ^1
                bump(ref (nodes.kind)[idx])
                return nodes[row].kind * 10 + nodes.start[row]
            }

            func main(): int {
                nodes := new Nodes(1)
                row := nodes.add()
                nodes[row].kind = 2
                nodes[row].start = 3
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(237, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(mutate);
            Assert.Equal(7, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            var fieldLoads = ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld);
            Assert.True(
                fieldLoads >= 9,
                $"Parenthesized SoA ref/out arguments, including parenthesized column receivers, should load backing column arrays directly; saw {fieldLoads} field loads.");
            Assert.Equal(0, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void RefAndOutArguments_UseColumnArrayElementAddressForVerifiedElementTypes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                flags: uint
                offset: long
                marker: char
                active: bool
                name: string
                kind: NodeKind
            }

            enum NodeKind {
                Unknown,
                Identifier,
                Literal
            }

            type Nodes = NodeTable

            func bumpFlags(ref value: uint) {
                value += (uint)2
            }

            func setOffset(out value: long) {
                value = 11L
            }

            func setMarker(out value: char) {
                value = 'Z'
            }

            func flip(ref value: bool) {
                value = !value
            }

            func setName(out value: string) {
                value = "row"
            }

            func setKind(ref value: NodeKind) {
                value = NodeKind.Literal
            }

            func mutate(nodes: Nodes, row: int): int {
                bumpFlags(ref nodes[row].flags)
                setOffset(out nodes[row].offset)
                setMarker(out nodes.marker[row])
                flip(ref nodes.active[row])
                setName(out nodes[row].name)
                setKind(ref nodes.kind[row])
                idx := ^1
                bumpFlags(ref nodes.flags[idx])
                setOffset(out nodes.offset[^1])
                setMarker(out nodes.marker[idx])
                flip(ref nodes.active[^1])
                setName(out nodes.name[idx])
                setKind(ref nodes.kind[^1])

                score := (int)nodes[row].flags
                score += (int)nodes[row].offset
                score += (int)nodes.marker[row]
                score += nodes.active[row] ? 1 : 0
                score += nodes[row].name == "row" ? 1000 : 0
                score += nodes.kind[row] == NodeKind.Literal ? 100 : 0
                score += (int)nodes.flags[idx]
                score += (int)nodes.offset[^1]
                score += (int)nodes.marker[idx]
                score += nodes.active[^1] ? 1 : 0
                score += nodes.name[idx] == "row" ? 1000 : 0
                score += nodes.kind[^1] == NodeKind.Literal ? 100 : 0
                return score
            }

            func main(): int {
                nodes := new Nodes(2)
                row := nodes.add()
                last := nodes.add()
                nodes[row].flags = (uint)5
                nodes[row].offset = 3L
                nodes.marker[row] = 'A'
                nodes.active[row] = true
                nodes[row].name = "start"
                nodes.kind[row] = NodeKind.Identifier
                nodes[last].flags = (uint)1
                nodes[last].offset = 2L
                nodes.marker[last] = 'B'
                nodes.active[last] = false
                nodes[last].name = "tail"
                nodes.kind[last] = NodeKind.Unknown
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);
            var kindField = tableType!.GetField("kind", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(kindField);
            var kindElementType = kindField!.FieldType.GetElementType();
            Assert.NotNull(kindElementType);
            Assert.True(kindElementType!.IsEnum);
            Assert.Equal(new[] { "Unknown", "Identifier", "Literal" }, Enum.GetNames(kindElementType));

            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(2413, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(mutate);
            Assert.Equal(12, ILShapeInspector.CountOpcode(mutate, OpCodes.Ldelema));
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 24,
                "Mixed SoA ref/out arguments, including from-end direct columns, should load backing column arrays directly.");
            Assert.Equal(0, CountArrayElementStores(mutate));

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
    public void ParenthesizedColumnMemberDefaultStores_DoNotReadOldElement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                text: string?
            }

            func clearColumns(nodes: NodeTable, row: int) {
                (nodes.kind)[row] = default;
                (nodes.text)[row] = default;
                (nodes.kind)[^1] = default;
                (nodes.text)[^1] = default;
                idx := ^1;
                (nodes.kind)[idx] = default;
                (nodes.text)[idx] = default;
            }

            func clearColumnsAsExpression(nodes: NodeTable, row: int): int {
                idx := ^1;
                rowKind := (nodes.kind)[row] = default;
                rowText := (nodes.text)[row] = default;
                literalKind := (nodes.kind)[^1] = default;
                literalText := (nodes.text)[^1] = default;
                variableKind := (nodes.kind)[idx] = default;
                variableText := (nodes.text)[idx] = default;
                total := rowKind + literalKind + variableKind
                total += (rowText == null ? 10 : 0)
                total += (literalText == null ? 100 : 0)
                total += (variableText == null ? 1000 : 0)
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
                clearColumns(nodes, first)
                firstScore := nodes.kind[first] + (nodes.text[first] == null ? 10 : 0)
                firstScore += nodes.kind[second] + (nodes.text[second] == null ? 100 : 0)

                nodes.kind[first] = 8
                nodes.text[first] = "again"
                nodes.kind[second] = 6
                nodes.text[second] = "again"
                expressionScore := clearColumnsAsExpression(nodes, first)
                afterScore := nodes.kind[first] + (nodes.text[first] == null ? 10 : 0)
                afterScore += nodes.kind[second] + (nodes.text[second] == null ? 100 : 0)
                return firstScore + expressionScore + afterScore
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var clearColumns = ILShapeInspector.GetProgramMethod(assembly, "clearColumns");
            var clearColumnsAsExpression = ILShapeInspector.GetProgramMethod(
                assembly,
                "clearColumnsAsExpression");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1330, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoFromEndSliceAllocation(clearColumns);
            Assert.True(
                ILShapeInspector.CountOpcode(clearColumns, OpCodes.Ldfld) >= 6,
                "Parenthesized SoA column-member receiver default stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearColumns));
            Assert.Equal(6, CountArrayElementStores(clearColumns));

            AssertNoFromEndSliceAllocation(clearColumnsAsExpression);
            Assert.True(
                ILShapeInspector.CountOpcode(clearColumnsAsExpression, OpCodes.Ldfld) >= 6,
                "Parenthesized SoA column-member receiver default store expressions should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(clearColumnsAsExpression));
            Assert.Equal(6, CountArrayElementStores(clearColumnsAsExpression));

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberUpdateOperands_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.kind)[row] = 10;
                stored := (nodes.kind)[row] += 2;
                oldUp := (nodes.kind)[row]++;
                newUp := ++(nodes.kind)[row];
                oldDown := (nodes.kind)[row]--;
                newDown := --(nodes.kind)[row];
                total := stored * 100000 + oldUp * 10000 + newUp * 1000
                total += oldDown * 100 + newDown * 10 + (nodes.kind)[row]
                return total
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.kind)[^1] = 10;
                stored := (nodes.kind)[^1] += 2;
                oldUp := (nodes.kind)[^1]++;
                newUp := ++(nodes.kind)[^1];
                oldDown := (nodes.kind)[^1]--;
                newDown := --(nodes.kind)[^1];
                total := stored * 100000 + oldUp * 10000 + newUp * 1000
                total += oldDown * 100 + newDown * 10 + (nodes.kind)[^1]
                return total
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.kind)[idx] = 10;
                stored := (nodes.kind)[idx] += 2;
                oldUp := (nodes.kind)[idx]++;
                newUp := ++(nodes.kind)[idx];
                oldDown := (nodes.kind)[idx]--;
                newDown := --(nodes.kind)[idx];
                total := stored * 100000 + oldUp * 10000 + newUp * 1000
                total += oldDown * 100 + newDown * 10 + (nodes.kind)[idx]
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row) + literalOps(nodes) + variableOps(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(4006596, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            Assert.True(
                ILShapeInspector.CountOpcode(rowOps, OpCodes.Ldfld) >= 6,
                "Parenthesized SoA column-member receiver updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(rowOps) >= 6,
                "Parenthesized SoA column-member receiver updates should read current values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(rowOps));

            AssertNoFromEndSliceAllocation(literalOps);
            Assert.True(
                ILShapeInspector.CountOpcode(literalOps, OpCodes.Ldfld) >= 6,
                "Parenthesized SoA column-member receiver from-end updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(literalOps) >= 6,
                "Parenthesized SoA column-member receiver from-end updates should read current values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(literalOps));

            AssertNoFromEndSliceAllocation(variableOps);
            Assert.True(
                ILShapeInspector.CountOpcode(variableOps, OpCodes.Ldfld) >= 6,
                "Parenthesized SoA column-member receiver variable from-end updates should load backing column fields directly.");
            Assert.True(
                CountArrayElementLoads(variableOps) >= 6,
                "Parenthesized SoA column-member receiver variable from-end updates should read current values from backing arrays.");
            Assert.Equal(6, CountArrayElementStores(variableOps));

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberIntegralVerifiedTypeUpdates_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                flags: uint
                start: long
                marker: char
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.flags)[row] += (uint)5
                oldFlags := (nodes.flags)[row]++
                (nodes.start)[row] += 7L
                oldStart := (nodes.start)[row]--
                oldMarker := (nodes.marker)[row]++
                preMarker := ++(nodes.marker)[row]

                total := (int)(nodes.flags)[row]
                total += (int)oldFlags * 10
                total += (int)(nodes.start)[row]
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)(nodes.marker)[row]
                return total
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.flags)[^1] += (uint)5
                oldFlags := (nodes.flags)[^1]++
                (nodes.start)[^1] += 7L
                oldStart := (nodes.start)[^1]--
                oldMarker := (nodes.marker)[^1]++
                preMarker := ++(nodes.marker)[^1]

                total := (int)(nodes.flags)[^1]
                total += (int)oldFlags * 10
                total += (int)(nodes.start)[^1]
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)(nodes.marker)[^1]
                return total
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.flags)[idx] += (uint)5
                oldFlags := (nodes.flags)[idx]++
                (nodes.start)[idx] += 7L
                oldStart := (nodes.start)[idx]--
                oldMarker := (nodes.marker)[idx]++
                preMarker := ++(nodes.marker)[idx]

                total := (int)(nodes.flags)[idx]
                total += (int)oldFlags * 10
                total += (int)(nodes.start)[idx]
                total += (int)oldStart
                total += (int)oldMarker
                total += (int)preMarker
                total += (int)(nodes.marker)[idx]
                return total
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()
                rowNodes.flags[row] = (uint)2
                rowNodes.start[row] = 20L
                rowNodes.marker[row] = 'A'

                literalNodes := new NodeTable(1)
                literalNodes.add()
                literalNodes.flags[^1] = (uint)2
                literalNodes.start[^1] = 20L
                literalNodes.marker[^1] = 'A'

                variableNodes := new NodeTable(1)
                variableNodes.add()
                idx := ^1
                variableNodes.flags[idx] = (uint)2
                variableNodes.start[idx] = 20L
                variableNodes.marker[idx] = 'A'

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(990, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedIntegralUpdateColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedIntegralUpdateColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedIntegralUpdateColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberNullCoalescing_UsesColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                text: string
            }

            func rowOps(nodes: NodeTable, missingRow: int, existingRow: int): int {
                missing := (nodes.text)[missingRow] ?? "m";
                existing := (nodes.text)[existingRow] ?? "ignored";
                assigned := (nodes.text)[missingRow] ??= "aaa";
                current := (nodes.text)[missingRow] ??= "ignored";
                score := (missing == "m" ? 1 : 0)
                score += (existing == "rr" ? 10 : 0)
                score += (assigned == "aaa" ? 100 : 0)
                score += (current == "aaa" ? 1000 : 0)
                score += ((nodes.text)[missingRow] == "aaa" ? 10000 : 0)
                return score
            }

            func literalOps(nodes: NodeTable): int {
                missing := (nodes.text)[^2] ?? "m";
                existing := (nodes.text)[^1] ?? "ignored";
                assigned := (nodes.text)[^2] ??= "aaa";
                current := (nodes.text)[^2] ??= "ignored";
                score := (missing == "m" ? 1 : 0)
                score += (existing == "rr" ? 10 : 0)
                score += (assigned == "aaa" ? 100 : 0)
                score += (current == "aaa" ? 1000 : 0)
                score += ((nodes.text)[^2] == "aaa" ? 10000 : 0)
                return score
            }

            func variableOps(nodes: NodeTable): int {
                missingIdx := ^2;
                existingIdx := ^1;
                missing := (nodes.text)[missingIdx] ?? "m";
                existing := (nodes.text)[existingIdx] ?? "ignored";
                assigned := (nodes.text)[missingIdx] ??= "aaa";
                current := (nodes.text)[missingIdx] ??= "ignored";
                score := (missing == "m" ? 1 : 0)
                score += (existing == "rr" ? 10 : 0)
                score += (assigned == "aaa" ? 100 : 0)
                score += (current == "aaa" ? 1000 : 0)
                score += ((nodes.text)[missingIdx] == "aaa" ? 10000 : 0)
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(2)
                missingRow := rowNodes.add()
                existingRow := rowNodes.add()
                rowNodes.text[existingRow] = "rr"

                literalNodes := new NodeTable(2)
                literalNodes.add()
                literalNodes.add()
                literalNodes.text[1] = "rr"

                variableNodes := new NodeTable(2)
                variableNodes.add()
                variableNodes.add()
                variableNodes.text[1] = "rr"

                return rowOps(rowNodes, missingRow, existingRow) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(33333, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(rowOps);
            Assert.Equal(0, ILShapeInspector.CountOpcode(rowOps, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(rowOps, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(rowOps));
            Assert.Equal(0, ILShapeInspector.CountOpcode(rowOps, OpCodes.Callvirt));
            Assert.True(
                ILShapeInspector.CountOpcode(rowOps, OpCodes.Ldfld) >= 5,
                "Parenthesized SoA column-member receiver null-coalescing should load backing column fields directly.");
            Assert.Equal(5, CountArrayElementLoads(rowOps));
            Assert.Equal(2, CountArrayElementStores(rowOps));

            AssertNoFromEndSliceAllocation(literalOps);
            Assert.True(
                ILShapeInspector.CountOpcode(literalOps, OpCodes.Ldfld) >= 5,
                "Parenthesized SoA column-member receiver from-end null-coalescing should load backing column fields directly.");
            Assert.Equal(5, CountArrayElementLoads(literalOps));
            Assert.Equal(2, CountArrayElementStores(literalOps));

            AssertNoFromEndSliceAllocation(variableOps);
            Assert.True(
                ILShapeInspector.CountOpcode(variableOps, OpCodes.Ldfld) >= 5,
                "Parenthesized SoA column-member receiver variable from-end null-coalescing should load backing column fields directly.");
            Assert.Equal(5, CountArrayElementLoads(variableOps));
            Assert.Equal(2, CountArrayElementStores(variableOps));

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberStringConcatenation_UsesColumnArrayOffsetAndStringConcat()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
                optionalName: string?
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.name)[row] = "row";
                exprValue := (nodes.name)[row] = (nodes.name)[row] + "-expr";
                compoundValue := (nodes.name)[row] += "-compound";
                nullableExpr := (nodes.optionalName)[row] = (nodes.optionalName)[row] + "maybe";
                nullableCompound := (nodes.optionalName)[row] += "-compound";

                score := exprValue == "row-expr" ? 1000 : 0
                score += compoundValue == "row-expr-compound" ? 100 : 0
                score += nullableExpr == "maybe" ? 10 : 0
                score += nullableCompound == "maybe-compound" ? 1 : 0
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.name)[^1] = "last";
                exprValue := (nodes.name)[^1] = (nodes.name)[^1] + "-expr";
                compoundValue := (nodes.name)[^1] += "-compound";
                nullableExpr := (nodes.optionalName)[^1] = (nodes.optionalName)[^1] + "maybe";
                nullableCompound := (nodes.optionalName)[^1] += "-compound";

                score := exprValue == "last-expr" ? 1000 : 0
                score += compoundValue == "last-expr-compound" ? 100 : 0
                score += nullableExpr == "maybe" ? 10 : 0
                score += nullableCompound == "maybe-compound" ? 1 : 0
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.name)[idx] = "var";
                exprValue := (nodes.name)[idx] = (nodes.name)[idx] + "-expr";
                compoundValue := (nodes.name)[idx] += "-compound";
                nullableExpr := (nodes.optionalName)[idx] = (nodes.optionalName)[idx] + "maybe";
                nullableCompound := (nodes.optionalName)[idx] += "-compound";

                score := exprValue == "var-expr" ? 1000 : 0
                score += compoundValue == "var-expr-compound" ? 100 : 0
                score += nullableExpr == "maybe" ? 10 : 0
                score += nullableCompound == "maybe-compound" ? 1 : 0
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()

                literalNodes := new NodeTable(1)
                literalNodes.add()

                variableNodes := new NodeTable(1)
                variableNodes.add()

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(3333, Assert.IsType<int>(main.Invoke(null, null)));

            AssertParenthesizedStringConcatColumnShape(rowOps, "row-index");
            AssertParenthesizedStringConcatColumnShape(literalOps, "literal from-end");
            AssertParenthesizedStringConcatColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberStringEquality_UsesColumnArrayOffsetAndStringOperators()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                name: string
                optionalName: string?
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.name)[row] = "alpha";
                nameMatches := (nodes.name)[row] == "alpha"
                nameDiffers := (nodes.name)[row] != "beta"

                optionalMissing := (nodes.optionalName)[row] == null
                (nodes.optionalName)[row] = "maybe";
                optionalPresent := (nodes.optionalName)[row] != null

                optionalMatches := (nodes.optionalName)[row] == "maybe"
                optionalDiffers := (nodes.optionalName)[row] != "nope"

                score := nameMatches ? 100000 : 0
                score += nameDiffers ? 10000 : 0
                score += optionalMissing ? 1000 : 0
                score += optionalPresent ? 100 : 0
                score += optionalMatches ? 10 : 0
                score += optionalDiffers ? 1 : 0
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.name)[^1] = "alpha";
                nameMatches := (nodes.name)[^1] == "alpha"
                nameDiffers := (nodes.name)[^1] != "beta"

                optionalMissing := (nodes.optionalName)[^1] == null
                (nodes.optionalName)[^1] = "maybe";
                optionalPresent := (nodes.optionalName)[^1] != null

                optionalMatches := (nodes.optionalName)[^1] == "maybe"
                optionalDiffers := (nodes.optionalName)[^1] != "nope"

                score := nameMatches ? 100000 : 0
                score += nameDiffers ? 10000 : 0
                score += optionalMissing ? 1000 : 0
                score += optionalPresent ? 100 : 0
                score += optionalMatches ? 10 : 0
                score += optionalDiffers ? 1 : 0
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.name)[idx] = "alpha";
                nameMatches := (nodes.name)[idx] == "alpha"
                nameDiffers := (nodes.name)[idx] != "beta"

                optionalMissing := (nodes.optionalName)[idx] == null
                (nodes.optionalName)[idx] = "maybe";
                optionalPresent := (nodes.optionalName)[idx] != null

                optionalMatches := (nodes.optionalName)[idx] == "maybe"
                optionalDiffers := (nodes.optionalName)[idx] != "nope"

                score := nameMatches ? 100000 : 0
                score += nameDiffers ? 10000 : 0
                score += optionalMissing ? 1000 : 0
                score += optionalPresent ? 100 : 0
                score += optionalMatches ? 10 : 0
                score += optionalDiffers ? 1 : 0
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()

                literalNodes := new NodeTable(1)
                literalNodes.add()

                variableNodes := new NodeTable(1)
                variableNodes.add()

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(333333, Assert.IsType<int>(main.Invoke(null, null)));

            AssertParenthesizedStringEqualityColumnShape(rowOps, "row-index");
            AssertParenthesizedStringEqualityColumnShape(literalOps, "literal from-end");
            AssertParenthesizedStringEqualityColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberScalarComparisons_UseColumnArrayLoadsAndComparisonOpcodes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
                marker: char
                active: bool
                nodeKind: NodeKind
            }

            enum NodeKind {
                Unknown = 0,
                Identifier = 1,
                Literal = 2,
                Error = 3
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.kind)[row] = -2;
                (nodes.flags)[row] = (uint)7;
                (nodes.mask)[row] = 20L;
                (nodes.marker)[row] = 'B';
                (nodes.active)[row] = true;
                (nodes.nodeKind)[row] = NodeKind.Identifier;

                score := (nodes.active)[row] == true ? 1 : 0
                score += (nodes.active)[row] != false ? 1 : 0
                score += (nodes.kind)[row] == -2 ? 1 : 0
                score += (nodes.kind)[row] != 5 ? 1 : 0
                score += (nodes.kind)[row] < 0 ? 1 : 0
                score += (nodes.kind)[row] >= -2 ? 1 : 0
                score += (nodes.flags)[row] == (uint)7 ? 1 : 0
                score += (nodes.flags)[row] >= (uint)7 ? 1 : 0
                score += (nodes.mask)[row] == 20L ? 1 : 0
                score += (nodes.mask)[row] > 10L ? 1 : 0
                score += (nodes.marker)[row] == 'B' ? 1 : 0
                score += (nodes.marker)[row] < 'C' ? 1 : 0
                score += (nodes.nodeKind)[row] == NodeKind.Identifier ? 1 : 0
                score += (nodes.nodeKind)[row] < NodeKind.Literal ? 1 : 0
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.kind)[^1] = -2;
                (nodes.flags)[^1] = (uint)7;
                (nodes.mask)[^1] = 20L;
                (nodes.marker)[^1] = 'B';
                (nodes.active)[^1] = true;
                (nodes.nodeKind)[^1] = NodeKind.Identifier;

                score := (nodes.active)[^1] == true ? 1 : 0
                score += (nodes.active)[^1] != false ? 1 : 0
                score += (nodes.kind)[^1] == -2 ? 1 : 0
                score += (nodes.kind)[^1] != 5 ? 1 : 0
                score += (nodes.kind)[^1] < 0 ? 1 : 0
                score += (nodes.kind)[^1] >= -2 ? 1 : 0
                score += (nodes.flags)[^1] == (uint)7 ? 1 : 0
                score += (nodes.flags)[^1] >= (uint)7 ? 1 : 0
                score += (nodes.mask)[^1] == 20L ? 1 : 0
                score += (nodes.mask)[^1] > 10L ? 1 : 0
                score += (nodes.marker)[^1] == 'B' ? 1 : 0
                score += (nodes.marker)[^1] < 'C' ? 1 : 0
                score += (nodes.nodeKind)[^1] == NodeKind.Identifier ? 1 : 0
                score += (nodes.nodeKind)[^1] < NodeKind.Literal ? 1 : 0
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.kind)[idx] = -2;
                (nodes.flags)[idx] = (uint)7;
                (nodes.mask)[idx] = 20L;
                (nodes.marker)[idx] = 'B';
                (nodes.active)[idx] = true;
                (nodes.nodeKind)[idx] = NodeKind.Identifier;

                score := (nodes.active)[idx] == true ? 1 : 0
                score += (nodes.active)[idx] != false ? 1 : 0
                score += (nodes.kind)[idx] == -2 ? 1 : 0
                score += (nodes.kind)[idx] != 5 ? 1 : 0
                score += (nodes.kind)[idx] < 0 ? 1 : 0
                score += (nodes.kind)[idx] >= -2 ? 1 : 0
                score += (nodes.flags)[idx] == (uint)7 ? 1 : 0
                score += (nodes.flags)[idx] >= (uint)7 ? 1 : 0
                score += (nodes.mask)[idx] == 20L ? 1 : 0
                score += (nodes.mask)[idx] > 10L ? 1 : 0
                score += (nodes.marker)[idx] == 'B' ? 1 : 0
                score += (nodes.marker)[idx] < 'C' ? 1 : 0
                score += (nodes.nodeKind)[idx] == NodeKind.Identifier ? 1 : 0
                score += (nodes.nodeKind)[idx] < NodeKind.Literal ? 1 : 0
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()

                literalNodes := new NodeTable(1)
                literalNodes.add()

                variableNodes := new NodeTable(1)
                variableNodes.add()

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(42, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedScalarComparisonColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedScalarComparisonColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedScalarComparisonColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberCharNumericPromotions_UseColumnArrayLoadsAndOpcodes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                marker: char
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.marker)[row] = 'A';
                score := (nodes.marker)[row] + 1
                score += (nodes.marker)[row] - 60
                score += (nodes.marker)[row] & 15
                score += (nodes.marker)[row] | 2
                score += (nodes.marker)[row] ^ 1
                score += (nodes.marker)[row] << 1
                score += (nodes.marker)[row] >> 1
                score += (nodes.marker)[row] * 2
                score += ~(nodes.marker)[row]
                score += (nodes.marker)[row] % 10
                score += (nodes.marker)[row] / 2
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.marker)[^1] = 'A';
                score := (nodes.marker)[^1] + 1
                score += (nodes.marker)[^1] - 60
                score += (nodes.marker)[^1] & 15
                score += (nodes.marker)[^1] | 2
                score += (nodes.marker)[^1] ^ 1
                score += (nodes.marker)[^1] << 1
                score += (nodes.marker)[^1] >> 1
                score += (nodes.marker)[^1] * 2
                score += ~(nodes.marker)[^1]
                score += (nodes.marker)[^1] % 10
                score += (nodes.marker)[^1] / 2
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.marker)[idx] = 'A';
                score := (nodes.marker)[idx] + 1
                score += (nodes.marker)[idx] - 60
                score += (nodes.marker)[idx] & 15
                score += (nodes.marker)[idx] | 2
                score += (nodes.marker)[idx] ^ 1
                score += (nodes.marker)[idx] << 1
                score += (nodes.marker)[idx] >> 1
                score += (nodes.marker)[idx] * 2
                score += ~(nodes.marker)[idx]
                score += (nodes.marker)[idx] % 10
                score += (nodes.marker)[idx] / 2
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()

                literalNodes := new NodeTable(1)
                literalNodes.add()

                variableNodes := new NodeTable(1)
                variableNodes.add()

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1398, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedCharPromotionColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedCharPromotionColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedCharPromotionColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberEnumBitwiseExpressions_UseColumnArrayOffsetWithoutSliceAllocation()
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

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.kind)[row] = NodeKind.Identifier;
                orValue := (nodes.kind)[row] = (nodes.kind)[row] | NodeKind.Literal;
                xorValue := (nodes.kind)[row] = (nodes.kind)[row] ^ NodeKind.Identifier;
                andValue := (nodes.kind)[row] = (nodes.kind)[row] & NodeKind.Literal;
                notValue := (nodes.kind)[row] = ~(nodes.kind)[row];

                score := orValue == NodeKind.Both ? 1000 : 0
                score += xorValue == NodeKind.Literal ? 100 : 0
                score += andValue == NodeKind.Literal ? 10 : 0
                score += (int)notValue == -3 ? 1 : 0
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.kind)[^1] = NodeKind.Identifier;
                orValue := (nodes.kind)[^1] = (nodes.kind)[^1] | NodeKind.Literal;
                xorValue := (nodes.kind)[^1] = (nodes.kind)[^1] ^ NodeKind.Identifier;
                andValue := (nodes.kind)[^1] = (nodes.kind)[^1] & NodeKind.Literal;
                notValue := (nodes.kind)[^1] = ~(nodes.kind)[^1];

                score := orValue == NodeKind.Both ? 1000 : 0
                score += xorValue == NodeKind.Literal ? 100 : 0
                score += andValue == NodeKind.Literal ? 10 : 0
                score += (int)notValue == -3 ? 1 : 0
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.kind)[idx] = NodeKind.Identifier;
                orValue := (nodes.kind)[idx] = (nodes.kind)[idx] | NodeKind.Literal;
                xorValue := (nodes.kind)[idx] = (nodes.kind)[idx] ^ NodeKind.Identifier;
                andValue := (nodes.kind)[idx] = (nodes.kind)[idx] & NodeKind.Literal;
                notValue := (nodes.kind)[idx] = ~(nodes.kind)[idx];

                score := orValue == NodeKind.Both ? 1000 : 0
                score += xorValue == NodeKind.Literal ? 100 : 0
                score += andValue == NodeKind.Literal ? 10 : 0
                score += (int)notValue == -3 ? 1 : 0
                return score
            }

            func main(): int {
                rowNodes := new NodeTable(1)
                row := rowNodes.add()

                literalNodes := new NodeTable(1)
                literalNodes.add()

                variableNodes := new NodeTable(1)
                variableNodes.add()

                return rowOps(rowNodes, row) + literalOps(literalNodes) + variableOps(variableNodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(3333, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedEnumBitwiseColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedEnumBitwiseColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedEnumBitwiseColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberBoolLogicalExpressions_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
                ready: bool
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.active)[row] = false;
                (nodes.ready)[row] = true;
                notValue := (nodes.active)[row] = !(nodes.active)[row];
                andValue := (nodes.ready)[row] = (nodes.active)[row] && (nodes.ready)[row];
                orValue := (nodes.active)[row] = (nodes.active)[row] || false;
                total := notValue ? 100 : 0
                total += andValue ? 10 : 0
                total += orValue ? 1 : 0
                return total
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.active)[^1] = false;
                (nodes.ready)[^1] = true;
                notValue := (nodes.active)[^1] = !(nodes.active)[^1];
                andValue := (nodes.ready)[^1] = (nodes.active)[^1] && (nodes.ready)[^1];
                orValue := (nodes.active)[^1] = (nodes.active)[^1] || false;
                total := notValue ? 100 : 0
                total += andValue ? 10 : 0
                total += orValue ? 1 : 0
                return total
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.active)[idx] = false;
                (nodes.ready)[idx] = true;
                notValue := (nodes.active)[idx] = !(nodes.active)[idx];
                andValue := (nodes.ready)[idx] = (nodes.active)[idx] && (nodes.ready)[idx];
                orValue := (nodes.active)[idx] = (nodes.active)[idx] || false;
                total := notValue ? 100 : 0
                total += andValue ? 10 : 0
                total += orValue ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row) + literalOps(nodes) + variableOps(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(333, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedBoolLogicalColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedBoolLogicalColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedBoolLogicalColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberBoolBitwiseExpressions_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                active: bool
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.active)[row] = false;
                orValue := (nodes.active)[row] = (nodes.active)[row] | true;
                xorValue := (nodes.active)[row] = (nodes.active)[row] ^ true;
                andValue := (nodes.active)[row] = (nodes.active)[row] & true;
                total := orValue ? 100 : 0
                total += xorValue ? 10 : 0
                total += andValue ? 1 : 0
                return total
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.active)[^1] = false;
                orValue := (nodes.active)[^1] = (nodes.active)[^1] | true;
                xorValue := (nodes.active)[^1] = (nodes.active)[^1] ^ true;
                andValue := (nodes.active)[^1] = (nodes.active)[^1] & true;
                total := orValue ? 100 : 0
                total += xorValue ? 10 : 0
                total += andValue ? 1 : 0
                return total
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.active)[idx] = false;
                orValue := (nodes.active)[idx] = (nodes.active)[idx] | true;
                xorValue := (nodes.active)[idx] = (nodes.active)[idx] ^ true;
                andValue := (nodes.active)[idx] = (nodes.active)[idx] & true;
                total := orValue ? 100 : 0
                total += xorValue ? 10 : 0
                total += andValue ? 1 : 0
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row) + literalOps(nodes) + variableOps(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(300, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedBoolBitwiseColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedBoolBitwiseColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedBoolBitwiseColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberNumericExpressions_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.kind)[row] = 10;
                addValue := (nodes.kind)[row] = (nodes.kind)[row] + 5;
                (nodes.kind)[row] = 20;
                subValue := (nodes.kind)[row] = (nodes.kind)[row] - 6;
                (nodes.kind)[row] = 23;
                remValue := (nodes.kind)[row] = (nodes.kind)[row] % 7;
                (nodes.flags)[row] = (uint)20;
                divUValue := (nodes.flags)[row] = (nodes.flags)[row] / (uint)4;
                (nodes.flags)[row] = (uint)22;
                remUValue := (nodes.flags)[row] = (nodes.flags)[row] % (uint)5;
                (nodes.mask)[row] = 7L;
                mulValue := (nodes.mask)[row] = (nodes.mask)[row] * 3L;
                (nodes.mask)[row] = 22L;
                divValue := (nodes.mask)[row] = (nodes.mask)[row] / 2L;
                (nodes.kind)[row] = 4;
                shlInt := (nodes.kind)[row] = (nodes.kind)[row] << 2;
                (nodes.kind)[row] = -16;
                shrInt := (nodes.kind)[row] = (nodes.kind)[row] >> 2;
                (nodes.flags)[row] = (uint)8;
                shrUInt := (nodes.flags)[row] = (nodes.flags)[row] >> 1;
                (nodes.mask)[row] = 3L;
                shlLong := (nodes.mask)[row] = (nodes.mask)[row] << 2;
                (nodes.kind)[row] = 10;
                orInt := (nodes.kind)[row] = (nodes.kind)[row] | 5;
                (nodes.flags)[row] = (uint)12;
                andUInt := (nodes.flags)[row] = (nodes.flags)[row] & (uint)10;
                (nodes.mask)[row] = 3L;
                xorLong := (nodes.mask)[row] = (nodes.mask)[row] ^ 10L;

                total := addValue + subValue + remValue + (int)divUValue + (int)remUValue
                total += (int)mulValue + (int)divValue + shlInt + shrInt + (int)shrUInt
                total += (int)shlLong + orInt + (int)andUInt + (int)xorLong
                return total
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.kind)[^1] = 10;
                addValue := (nodes.kind)[^1] = (nodes.kind)[^1] + 5;
                (nodes.kind)[^1] = 20;
                subValue := (nodes.kind)[^1] = (nodes.kind)[^1] - 6;
                (nodes.kind)[^1] = 23;
                remValue := (nodes.kind)[^1] = (nodes.kind)[^1] % 7;
                (nodes.flags)[^1] = (uint)20;
                divUValue := (nodes.flags)[^1] = (nodes.flags)[^1] / (uint)4;
                (nodes.flags)[^1] = (uint)22;
                remUValue := (nodes.flags)[^1] = (nodes.flags)[^1] % (uint)5;
                (nodes.mask)[^1] = 7L;
                mulValue := (nodes.mask)[^1] = (nodes.mask)[^1] * 3L;
                (nodes.mask)[^1] = 22L;
                divValue := (nodes.mask)[^1] = (nodes.mask)[^1] / 2L;
                (nodes.kind)[^1] = 4;
                shlInt := (nodes.kind)[^1] = (nodes.kind)[^1] << 2;
                (nodes.kind)[^1] = -16;
                shrInt := (nodes.kind)[^1] = (nodes.kind)[^1] >> 2;
                (nodes.flags)[^1] = (uint)8;
                shrUInt := (nodes.flags)[^1] = (nodes.flags)[^1] >> 1;
                (nodes.mask)[^1] = 3L;
                shlLong := (nodes.mask)[^1] = (nodes.mask)[^1] << 2;
                (nodes.kind)[^1] = 10;
                orInt := (nodes.kind)[^1] = (nodes.kind)[^1] | 5;
                (nodes.flags)[^1] = (uint)12;
                andUInt := (nodes.flags)[^1] = (nodes.flags)[^1] & (uint)10;
                (nodes.mask)[^1] = 3L;
                xorLong := (nodes.mask)[^1] = (nodes.mask)[^1] ^ 10L;

                total := addValue + subValue + remValue + (int)divUValue + (int)remUValue
                total += (int)mulValue + (int)divValue + shlInt + shrInt + (int)shrUInt
                total += (int)shlLong + orInt + (int)andUInt + (int)xorLong
                return total
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.kind)[idx] = 10;
                addValue := (nodes.kind)[idx] = (nodes.kind)[idx] + 5;
                (nodes.kind)[idx] = 20;
                subValue := (nodes.kind)[idx] = (nodes.kind)[idx] - 6;
                (nodes.kind)[idx] = 23;
                remValue := (nodes.kind)[idx] = (nodes.kind)[idx] % 7;
                (nodes.flags)[idx] = (uint)20;
                divUValue := (nodes.flags)[idx] = (nodes.flags)[idx] / (uint)4;
                (nodes.flags)[idx] = (uint)22;
                remUValue := (nodes.flags)[idx] = (nodes.flags)[idx] % (uint)5;
                (nodes.mask)[idx] = 7L;
                mulValue := (nodes.mask)[idx] = (nodes.mask)[idx] * 3L;
                (nodes.mask)[idx] = 22L;
                divValue := (nodes.mask)[idx] = (nodes.mask)[idx] / 2L;
                (nodes.kind)[idx] = 4;
                shlInt := (nodes.kind)[idx] = (nodes.kind)[idx] << 2;
                (nodes.kind)[idx] = -16;
                shrInt := (nodes.kind)[idx] = (nodes.kind)[idx] >> 2;
                (nodes.flags)[idx] = (uint)8;
                shrUInt := (nodes.flags)[idx] = (nodes.flags)[idx] >> 1;
                (nodes.mask)[idx] = 3L;
                shlLong := (nodes.mask)[idx] = (nodes.mask)[idx] << 2;
                (nodes.kind)[idx] = 10;
                orInt := (nodes.kind)[idx] = (nodes.kind)[idx] | 5;
                (nodes.flags)[idx] = (uint)12;
                andUInt := (nodes.flags)[idx] = (nodes.flags)[idx] & (uint)10;
                (nodes.mask)[idx] = 3L;
                xorLong := (nodes.mask)[idx] = (nodes.mask)[idx] ^ 10L;

                total := addValue + subValue + remValue + (int)divUValue + (int)remUValue
                total += (int)mulValue + (int)divValue + shlInt + shrInt + (int)shrUInt
                total += (int)shlLong + orInt + (int)andUInt + (int)xorLong
                return total
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row) + literalOps(nodes) + variableOps(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(390, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedNumericExpressionColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedNumericExpressionColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedNumericExpressionColumnShape(variableOps, "variable from-end");

            return 0;
        });
    }

    [Fact]
    public void ParenthesizedColumnMemberNumericUnaryExpressions_UseColumnArrayOffsetWithoutSliceAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                flags: uint
                mask: long
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes.kind)[row] = 7;
                negInt := (nodes.kind)[row] = -(nodes.kind)[row];
                (nodes.mask)[row] = 11L;
                negLong := (nodes.mask)[row] = -(nodes.mask)[row];
                (nodes.kind)[row] = 1;
                notInt := (nodes.kind)[row] = ~(nodes.kind)[row];
                (nodes.flags)[row] = (uint)0;
                notUInt := (nodes.flags)[row] = ~(nodes.flags)[row];
                (nodes.mask)[row] = 2L;
                notLong := (nodes.mask)[row] = ~(nodes.mask)[row];

                score := negInt == -7 ? 10000 : 0
                score += negLong == -11L ? 1000 : 0
                score += notInt == -2 ? 100 : 0
                score += notUInt > (uint)0 ? 10 : 0
                score += notLong == -3L ? 1 : 0
                return score
            }

            func literalOps(nodes: NodeTable): int {
                (nodes.kind)[^1] = 7;
                negInt := (nodes.kind)[^1] = -(nodes.kind)[^1];
                (nodes.mask)[^1] = 11L;
                negLong := (nodes.mask)[^1] = -(nodes.mask)[^1];
                (nodes.kind)[^1] = 1;
                notInt := (nodes.kind)[^1] = ~(nodes.kind)[^1];
                (nodes.flags)[^1] = (uint)0;
                notUInt := (nodes.flags)[^1] = ~(nodes.flags)[^1];
                (nodes.mask)[^1] = 2L;
                notLong := (nodes.mask)[^1] = ~(nodes.mask)[^1];

                score := negInt == -7 ? 10000 : 0
                score += negLong == -11L ? 1000 : 0
                score += notInt == -2 ? 100 : 0
                score += notUInt > (uint)0 ? 10 : 0
                score += notLong == -3L ? 1 : 0
                return score
            }

            func variableOps(nodes: NodeTable): int {
                idx := ^1;
                (nodes.kind)[idx] = 7;
                negInt := (nodes.kind)[idx] = -(nodes.kind)[idx];
                (nodes.mask)[idx] = 11L;
                negLong := (nodes.mask)[idx] = -(nodes.mask)[idx];
                (nodes.kind)[idx] = 1;
                notInt := (nodes.kind)[idx] = ~(nodes.kind)[idx];
                (nodes.flags)[idx] = (uint)0;
                notUInt := (nodes.flags)[idx] = ~(nodes.flags)[idx];
                (nodes.mask)[idx] = 2L;
                notLong := (nodes.mask)[idx] = ~(nodes.mask)[idx];

                score := negInt == -7 ? 10000 : 0
                score += negLong == -11L ? 1000 : 0
                score += notInt == -2 ? 100 : 0
                score += notUInt > (uint)0 ? 10 : 0
                score += notLong == -3L ? 1 : 0
                return score
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row) + literalOps(nodes) + variableOps(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var rowOps = ILShapeInspector.GetProgramMethod(assembly, "rowOps");
            var literalOps = ILShapeInspector.GetProgramMethod(assembly, "literalOps");
            var variableOps = ILShapeInspector.GetProgramMethod(assembly, "variableOps");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(33333, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(rowOps);
            AssertParenthesizedNumericUnaryColumnShape(rowOps, "row-index");

            AssertNoFromEndSliceAllocation(literalOps);
            AssertParenthesizedNumericUnaryColumnShape(literalOps, "literal from-end");

            AssertNoFromEndSliceAllocation(variableOps);
            AssertParenthesizedNumericUnaryColumnShape(variableOps, "variable from-end");

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
    public void AliasedSoaTableConstruction_UsesGeneratedTableShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func set(nodes: Nodes, row: int, kind: int) {
                nodes[row].kind = kind
                nodes.start[row] = nodes.capacity + nodes.length
            }

            func read(nodes: Nodes, row: int): int {
                return nodes[row].kind * 10 + nodes[row].start
            }

            func main(): int {
                nodes := new Nodes(2)
                first := nodes.add()
                set(nodes, first, 3)
                second := nodes.add()
                set(nodes, second, 4)
                view := Nodes.wrap(nodes.kind, nodes.start, nodes.length)
                return read(view, first) * 1000 + read(view, second) + view.length * 100000 + view.capacity * 1000000
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var set = ILShapeInspector.GetProgramMethod(assembly, "set");
            var read = ILShapeInspector.GetProgramMethod(assembly, "read");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(2233044, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(set);
            AssertNoAllocationOrDispatch(read);
            Assert.Equal(0, CountArrayElementLoads(set));
            Assert.Equal(2, CountArrayElementStores(set));
            Assert.Equal(2, CountArrayElementLoads(read));
            Assert.Equal(0, CountArrayElementStores(read));
            Assert.Equal(1, ILShapeInspector.CountOpcode(main, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(main, OpCodes.Newarr));

            return 0;
        });
    }

    [Fact]
    public void HardCastedAliasedSoaTableReceivers_UseGeneratedTableShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func mutate(nodes: NodeTable, row: int): int {
                ((Nodes)nodes)[row].kind = 7
                ((NodeTable)((Nodes)nodes)).start[row] = ((Nodes)nodes)[row].kind + 5
                return ((Nodes)nodes).kind[row] * 10 + ((NodeTable)nodes)[row].start
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return mutate(nodes, row)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(82, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(mutate);
            Assert.Equal(3, CountArrayElementLoads(mutate));
            Assert.Equal(2, CountArrayElementStores(mutate));

            return 0;
        });
    }

    [Fact]
    public void HardCastedAliasedSoaGeneratedOperations_MutateOriginalTableShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func mutate(nodes: Nodes): int {
                ((NodeTable)nodes).ensureCapacity(4)
                first := ((NodeTable)nodes).add()
                ((NodeTable)nodes)[first].kind = 9
                second := ((Nodes)((NodeTable)nodes)).add()
                ((Nodes)((NodeTable)nodes))[second].kind = 4
                ((NodeTable)nodes).copyRow(first, 3)
                ((Nodes)((NodeTable)nodes)).clear()
                return nodes.length * 100000
                    + nodes.capacity * 1000
                    + nodes.kind[first] * 100
                    + nodes.kind[second] * 10
                    + nodes.kind[3]
            }

            func main(): int {
                nodes := new Nodes(1)
                return mutate(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(4949, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(mutate);
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(mutate));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Callvirt));
            Assert.Equal(5, ILShapeInspector.CountOpcode(mutate, OpCodes.Call));

            return 0;
        });
    }

    [Fact]
    public void AliasedSoaTableGeneratedOperations_UseUnderlyingTableShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            type Nodes = NodeTable

            func mutate(nodes: Nodes): int {
                nodes.ensureCapacity(4)
                row := nodes.add()
                nodes[row].kind = 5
                nodes[row].start = 7
                nodes.copyRow(row, 2)
                nodes.clear()
                return nodes.length + nodes.capacity * 10 + nodes.kind[2] * 100 + nodes.start[2] * 1000
            }

            func main(): int {
                nodes := new Nodes(1)
                return mutate(nodes)
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            var mutate = ILShapeInspector.GetProgramMethod(assembly, "mutate");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.NotNull(tableType);

            var ensureCapacity = tableType!.GetMethod("ensureCapacity", BindingFlags.Public | BindingFlags.Instance);
            var copyRow = tableType.GetMethod("copyRow", BindingFlags.Public | BindingFlags.Instance);
            var clear = tableType.GetMethod("clear", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(ensureCapacity);
            Assert.NotNull(copyRow);
            Assert.NotNull(clear);

            Assert.Equal(7540, Assert.IsType<int>(main.Invoke(null, null)));

            ILShapeInspector.AssertNoBoxing(mutate);
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(mutate));
            Assert.Equal(0, ILShapeInspector.CountOpcode(mutate, OpCodes.Callvirt));
            Assert.Equal(4, ILShapeInspector.CountOpcode(mutate, OpCodes.Call));
            Assert.Equal(2, CountArrayElementLoads(mutate));
            Assert.Equal(2, CountArrayElementStores(mutate));
            Assert.True(
                ILShapeInspector.CountOpcode(mutate, OpCodes.Ldfld) >= 6,
                "Alias-typed generated operations should keep direct table field access around the calls.");

            Assert.Equal(2, ILShapeInspector.CountCallsTo(ensureCapacity!, typeof(Array), nameof(Array.Resize)));
            Assert.Equal(1, ILShapeInspector.CountOpcode(copyRow!, OpCodes.Call)); // ensureCapacity
            AssertNoAllocationOrDispatch(clear!);

            return 0;
        });
    }

    [Fact]
    public void AliasedVerifiedColumnTypes_UseColumnArrayLoadStoreWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            type KindColumn = int
            type FlagsColumn = uint
            type StartColumn = long
            type ActiveColumn = bool
            type MarkerColumn = char
            type NameColumn = string
            type OptionalNameColumn = string?
            type CountColumn = int

            soa record NodeTable {
                kind: KindColumn
                flags: FlagsColumn
                start: StartColumn
                active: ActiveColumn
                marker: MarkerColumn
                name: NameColumn
                optionalName: OptionalNameColumn
                count: CountColumn
            }

            func setRow(nodes: NodeTable, row: int, name: NameColumn, optionalName: OptionalNameColumn) {
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = name
                nodes[row].optionalName = optionalName
                nodes[row].count = 11
            }

            func setDirect(nodes: NodeTable, row: int, name: NameColumn, optionalName: OptionalNameColumn) {
                nodes.kind[row] = 3
                nodes.flags[row] = (uint)7
                nodes.start[row] = 19L
                nodes.active[row] = true
                nodes.marker[row] = 'A'
                nodes.name[row] = name
                nodes.optionalName[row] = optionalName
                nodes.count[row] = 11
            }

            func readRowScalars(nodes: NodeTable, row: int): int {
                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].count
                return total
            }

            func readDirectScalars(nodes: NodeTable, row: int): int {
                total := nodes.kind[row]
                total += (int)nodes.flags[row]
                total += (int)nodes.start[row]
                total += (nodes.active[row] ? 100 : 0)
                total += (int)nodes.marker[row]
                total += nodes.count[row]
                return total
            }

            func readRowName(nodes: NodeTable, row: int): NameColumn {
                return nodes[row].name
            }

            func readDirectName(nodes: NodeTable, row: int): NameColumn {
                return nodes.name[row]
            }

            func readRowOptional(nodes: NodeTable, row: int): OptionalNameColumn {
                return nodes[row].optionalName
            }

            func readDirectOptional(nodes: NodeTable, row: int): OptionalNameColumn {
                return nodes.optionalName[row]
            }

            func main(): int {
                nodes := new NodeTable(2)
                row := nodes.add()
                directRow := nodes.add()
                setRow(nodes, row, "abcd", null)
                setDirect(nodes, directRow, "efgh", "ij")

                total := readRowScalars(nodes, row)
                total += readRowName(nodes, row).Length
                total += (readRowOptional(nodes, row) == null ? 1000 : 0)
                total += readDirectScalars(nodes, directRow)
                total += readDirectName(nodes, directRow).Length
                directOptional := readDirectOptional(nodes, directRow)
                total += (directOptional == null ? 0 : directOptional.Length)
                return total
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var setRow = ILShapeInspector.GetProgramMethod(assembly, "setRow");
            var setDirect = ILShapeInspector.GetProgramMethod(assembly, "setDirect");
            var readRowScalars = ILShapeInspector.GetProgramMethod(assembly, "readRowScalars");
            var readDirectScalars = ILShapeInspector.GetProgramMethod(assembly, "readDirectScalars");
            var readRowName = ILShapeInspector.GetProgramMethod(assembly, "readRowName");
            var readDirectName = ILShapeInspector.GetProgramMethod(assembly, "readDirectName");
            var readRowOptional = ILShapeInspector.GetProgramMethod(assembly, "readRowOptional");
            var readDirectOptional = ILShapeInspector.GetProgramMethod(assembly, "readDirectOptional");
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(1420, Assert.IsType<int>(main.Invoke(null, null)));

            AssertNoAllocationOrDispatch(setRow);
            AssertNoAllocationOrDispatch(setDirect);
            AssertNoAllocationOrDispatch(readRowScalars);
            AssertNoAllocationOrDispatch(readDirectScalars);
            AssertNoAllocationOrDispatch(readRowName);
            AssertNoAllocationOrDispatch(readDirectName);
            AssertNoAllocationOrDispatch(readRowOptional);
            AssertNoAllocationOrDispatch(readDirectOptional);

            Assert.Equal(8, CountArrayElementStores(setRow));
            Assert.Equal(0, CountArrayElementLoads(setRow));
            Assert.Equal(8, CountArrayElementStores(setDirect));
            Assert.Equal(0, CountArrayElementLoads(setDirect));
            Assert.Equal(6, CountArrayElementLoads(readRowScalars));
            Assert.Equal(0, CountArrayElementStores(readRowScalars));
            Assert.Equal(6, CountArrayElementLoads(readDirectScalars));
            Assert.Equal(0, CountArrayElementStores(readDirectScalars));
            Assert.Equal(1, CountArrayElementLoads(readRowName));
            Assert.Equal(1, CountArrayElementLoads(readDirectName));
            Assert.Equal(1, CountArrayElementLoads(readRowOptional));
            Assert.Equal(1, CountArrayElementLoads(readDirectOptional));

            return 0;
        });
    }

    [Fact]
    public void AliasedVerifiedColumnTypes_GeneratedMethodsUseColumnArraysWithoutElementCopies()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            type KindColumn = int
            type FlagsColumn = uint
            type StartColumn = long
            type ActiveColumn = bool
            type MarkerColumn = char
            type NameColumn = string
            type OptionalNameColumn = string?
            type CountColumn = int

            soa record NodeTable {
                kind: KindColumn
                flags: FlagsColumn
                start: StartColumn
                active: ActiveColumn
                marker: MarkerColumn
                name: NameColumn
                optionalName: OptionalNameColumn
                count: CountColumn
            }

            func setAll(nodes: NodeTable, row: int, name: NameColumn, optionalName: OptionalNameColumn) {
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = name
                nodes[row].optionalName = optionalName
                nodes[row].count = 11
            }

            func readAll(nodes: NodeTable, row: int): int {
                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].count
                total += nodes[row].name.Length
                optional := nodes[row].optionalName
                total += (optional == null ? 1000 : optional.Length)
                return total
            }

            func make(): int {
                nodes := new NodeTable((short)4)
                return nodes.length + nodes.capacity
            }

            func grow(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                setAll(nodes, row, "abcd", null)
                nodes.ensureCapacity((short)4)
                return readAll(nodes, row) + nodes.length * 10000 + nodes.capacity * 100000
            }

            func view(kind: KindColumn[], flags: FlagsColumn[], start: StartColumn[], active: ActiveColumn[], marker: MarkerColumn[], name: NameColumn[], optionalName: OptionalNameColumn[], counts: CountColumn[]): int {
                nodes := NodeTable.wrap(kind, flags, start, active, marker, name, optionalName, counts, (short)1)
                nodes.copyRow(0, 1)
                return readAll(nodes, 1) + nodes.length * 10000 + nodes.capacity * 100000
            }
            """;

        ILShapeInspector.Compile(source, assembly =>
        {
            var tableType = assembly.GetType("NodeTable");
            Assert.NotNull(tableType);

            var constructor = tableType!.GetConstructor(new[] { typeof(int) });
            var wrap = tableType.GetMethod("wrap", BindingFlags.Public | BindingFlags.Static);
            var add = tableType.GetMethod("add", BindingFlags.Public | BindingFlags.Instance);
            var clear = tableType.GetMethod("clear", BindingFlags.Public | BindingFlags.Instance);
            var ensureCapacity = tableType.GetMethod("ensureCapacity", BindingFlags.Public | BindingFlags.Instance);
            var copyRow = tableType.GetMethod("copyRow", BindingFlags.Public | BindingFlags.Instance);
            var make = ILShapeInspector.GetProgramMethod(assembly, "make");
            var grow = ILShapeInspector.GetProgramMethod(assembly, "grow");
            var view = ILShapeInspector.GetProgramMethod(assembly, "view");
            Assert.NotNull(constructor);
            Assert.NotNull(wrap);
            Assert.NotNull(add);
            Assert.NotNull(clear);
            Assert.NotNull(ensureCapacity);
            Assert.NotNull(copyRow);

            Assert.Equal(typeof(int[]), tableType.GetField("kind")!.FieldType);
            Assert.Equal(typeof(uint[]), tableType.GetField("flags")!.FieldType);
            Assert.Equal(typeof(long[]), tableType.GetField("start")!.FieldType);
            Assert.Equal(typeof(bool[]), tableType.GetField("active")!.FieldType);
            Assert.Equal(typeof(char[]), tableType.GetField("marker")!.FieldType);
            Assert.Equal(typeof(string[]), tableType.GetField("name")!.FieldType);
            Assert.Equal(typeof(string[]), tableType.GetField("optionalName")!.FieldType);
            Assert.Equal(typeof(int[]), tableType.GetField("count")!.FieldType);

            Assert.Equal(4, Assert.IsType<int>(make.Invoke(null, null)));
            Assert.Equal(411209, Assert.IsType<int>(grow.Invoke(null, null)));
            Assert.Equal(
                221209,
                Assert.IsType<int>(view.Invoke(
                    null,
                    new object[]
                    {
                        new[] { 3, 0 },
                        new uint[] { 7, 0 },
                        new long[] { 19L, 0L },
                        new[] { true, false },
                        new[] { 'A', '\0' },
                        new[] { "abcd", "" },
                        new string?[] { null, null },
                        new[] { 11, 0 }
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
                "Aliased copyRow should load each column array plus the length field directly.");

            AssertNoAllocationOrDispatch(clear!);
            Assert.Equal(0, CountArrayElementLoads(clear!));
            Assert.Equal(0, CountArrayElementStores(clear!));
            Assert.Equal(0, ILShapeInspector.CountOpcode(clear!, OpCodes.Ldfld));
            Assert.Equal(1, ILShapeInspector.CountOpcode(clear!, OpCodes.Stfld));

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
    public void AliasedEnumColumn_UsesColumnArrayLoadStoreAndGeneratedMethodsWithoutRowAllocation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        const string source = """
            enum NodeKind {
                Unknown,
                Identifier,
                Literal
            }

            type KindColumn = NodeKind

            soa record NodeTable {
                kind: KindColumn
                count: int
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
                "Aliased enum SoA stores should load backing column fields directly.");
            Assert.Equal(0, CountArrayElementLoads(set));
            Assert.Equal(3, CountArrayElementStores(set));

            AssertNoAllocationOrDispatch(read);
            Assert.True(
                ILShapeInspector.CountOpcode(read, OpCodes.Ldfld) >= 3,
                "Aliased enum SoA reads should load backing column fields directly.");
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

    private static void AssertParenthesizedBoolLogicalColumnShape(MethodInfo method, string indexDescription)
    {
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Ldfld) >= 9,
            $"Parenthesized SoA bool logical stores should load backing column fields directly for {indexDescription} access.");
        Assert.True(
            CountArrayElementLoads(method) >= 4,
            $"Parenthesized SoA bool logical stores should read current values from backing arrays for {indexDescription} access.");
        Assert.Equal(5, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Ceq) >= 1,
            $"Parenthesized SoA bool logical-not should lower through direct comparison opcodes for {indexDescription} access.");
        Assert.True(
            CountOpcodes(method, OpCodes.Brfalse, OpCodes.Brfalse_S) >= 1,
            $"Parenthesized SoA bool logical-and should lower through short-circuit false branches for {indexDescription} access.");
        Assert.True(
            CountOpcodes(method, OpCodes.Brtrue, OpCodes.Brtrue_S) >= 1,
            $"Parenthesized SoA bool logical-or should lower through short-circuit true branches for {indexDescription} access.");
    }

    private static void AssertParenthesizedStringConcatColumnShape(MethodInfo method, string indexDescription)
    {
        AssertNoFromEndSliceAllocation(method);
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 7,
            $"Parenthesized SoA string concatenation stores should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.Equal(4, CountArrayElementLoads(method));
        Assert.Equal(5, CountArrayElementStores(method));
        Assert.Equal(4, ILShapeInspector.CountCallsTo(method, typeof(string), nameof(string.Concat)));
        Assert.Equal(4, ILShapeInspector.CountCallsTo(method, typeof(string), "op_Equality"));
    }

    private static void AssertParenthesizedStringEqualityColumnShape(MethodInfo method, string indexDescription)
    {
        AssertNoFromEndSliceAllocation(method);
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 8,
            $"Parenthesized SoA string equality should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.Equal(6, CountArrayElementLoads(method));
        Assert.Equal(2, CountArrayElementStores(method));
        Assert.Equal(2, ILShapeInspector.CountCallsTo(method, typeof(string), "op_Equality"));
        Assert.Equal(2, ILShapeInspector.CountCallsTo(method, typeof(string), "op_Inequality"));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Brfalse) >= 1,
            $"Parenthesized nullable-string null equality should branch on null references directly for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Brtrue) >= 1,
            $"Parenthesized nullable-string null inequality should branch on non-null references directly for {indexDescription} access.");
    }

    private static void AssertParenthesizedScalarComparisonColumnShape(MethodInfo method, string indexDescription)
    {
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 20,
            $"Parenthesized SoA scalar comparisons should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.Equal(14, CountArrayElementLoads(method));
        Assert.Equal(6, CountArrayElementStores(method));

        var equalityComparisons = ILShapeInspector.CountOpcode(method, OpCodes.Ceq)
            + CountOpcodes(method, OpCodes.Beq, OpCodes.Beq_S, OpCodes.Bne_Un, OpCodes.Bne_Un_S);
        var signedRelationalComparisons = ILShapeInspector.CountOpcode(method, OpCodes.Clt)
            + ILShapeInspector.CountOpcode(method, OpCodes.Cgt)
            + CountOpcodes(
                method,
                OpCodes.Blt,
                OpCodes.Blt_S,
                OpCodes.Ble,
                OpCodes.Ble_S,
                OpCodes.Bgt,
                OpCodes.Bgt_S,
                OpCodes.Bge,
                OpCodes.Bge_S);
        var unsignedRelationalComparisons = ILShapeInspector.CountOpcode(method, OpCodes.Clt_Un)
            + ILShapeInspector.CountOpcode(method, OpCodes.Cgt_Un)
            + CountOpcodes(
                method,
                OpCodes.Blt_Un,
                OpCodes.Blt_Un_S,
                OpCodes.Ble_Un,
                OpCodes.Ble_Un_S,
                OpCodes.Bgt_Un,
                OpCodes.Bgt_Un_S,
                OpCodes.Bge_Un,
                OpCodes.Bge_Un_S);

        Assert.True(
            equalityComparisons >= 8,
            $"Parenthesized SoA scalar equality/inequality should use direct comparison opcodes or branches for {indexDescription} access; saw {equalityComparisons}.");
        Assert.True(
            signedRelationalComparisons >= 4,
            $"Parenthesized SoA signed/enum relational comparisons should use direct comparison opcodes or branches for {indexDescription} access; saw {signedRelationalComparisons}.");
        Assert.True(
            unsignedRelationalComparisons >= 2,
            $"Parenthesized SoA unsigned/char relational comparisons should use unsigned comparison opcodes or branches for {indexDescription} access; saw {unsignedRelationalComparisons}.");
    }

    private static void AssertParenthesizedEnumBitwiseColumnShape(MethodInfo method, string indexDescription)
    {
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 9,
            $"Parenthesized SoA enum bitwise stores should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.Equal(4, CountArrayElementLoads(method));
        Assert.Equal(5, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Or) >= 1,
            $"Parenthesized SoA enum bitwise-or should use the direct OR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Xor) >= 1,
            $"Parenthesized SoA enum bitwise-xor should use the direct XOR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.And) >= 1,
            $"Parenthesized SoA enum bitwise-and should use the direct AND opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Not) >= 1,
            $"Parenthesized SoA enum unary bitwise-not should use the direct NOT opcode for {indexDescription} access.");
    }

    private static void AssertParenthesizedCharPromotionColumnShape(MethodInfo method, string indexDescription)
    {
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 12,
            $"Parenthesized SoA char numeric promotions should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.Equal(11, CountArrayElementLoads(method));
        Assert.Equal(1, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Add) >= 1,
            $"Parenthesized SoA char addition should use the direct ADD opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Sub) >= 1,
            $"Parenthesized SoA char subtraction should use the direct SUB opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.And) >= 1,
            $"Parenthesized SoA char bitwise-and should use the direct AND opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Or) >= 1,
            $"Parenthesized SoA char bitwise-or should use the direct OR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Xor) >= 1,
            $"Parenthesized SoA char bitwise-xor should use the direct XOR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Shl) >= 1,
            $"Parenthesized SoA char left shift should use the direct SHL opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Shr_Un) >= 1,
            $"Parenthesized SoA char right shift should use the direct SHR.UN opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Mul) >= 1,
            $"Parenthesized SoA char multiplication should use the direct MUL opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Not) >= 1,
            $"Parenthesized SoA char unary bitwise-not should use the direct NOT opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Rem) >= 1,
            $"Parenthesized SoA char remainder should use the direct REM opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Div) >= 1,
            $"Parenthesized SoA char division should use the direct DIV opcode for {indexDescription} access.");
    }

    private static void AssertParenthesizedIntegralUpdateColumnShape(MethodInfo method, string indexDescription)
    {
        var fieldLoads = ILShapeInspector.CountOpcode(method, OpCodes.Ldfld);
        Assert.True(
            fieldLoads >= 9,
            $"Parenthesized SoA integral verified-type updates should load backing column fields directly for {indexDescription} access; saw {fieldLoads} field loads.");
        Assert.True(
            CountArrayElementLoads(method) >= 9,
            $"Parenthesized SoA integral verified-type updates should read current and returned values from backing arrays for {indexDescription} access.");
        Assert.Equal(6, CountArrayElementStores(method));
    }

    private static void AssertParenthesizedBoolBitwiseColumnShape(MethodInfo method, string indexDescription)
    {
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Ldfld) >= 7,
            $"Parenthesized SoA bool bitwise stores should load backing column fields directly for {indexDescription} access.");
        Assert.True(
            CountArrayElementLoads(method) >= 3,
            $"Parenthesized SoA bool bitwise stores should read current values from backing arrays for {indexDescription} access.");
        Assert.Equal(4, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Or) >= 1,
            $"Parenthesized SoA bool bitwise-or should use the direct OR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Xor) >= 1,
            $"Parenthesized SoA bool bitwise-xor should use the direct XOR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.And) >= 1,
            $"Parenthesized SoA bool bitwise-and should use the direct AND opcode for {indexDescription} access.");
    }

    private static void AssertParenthesizedNumericExpressionColumnShape(MethodInfo method, string indexDescription)
    {
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Ldfld) >= 28,
            $"Parenthesized SoA numeric expression stores should load backing column fields directly for {indexDescription} access.");
        Assert.True(
            CountArrayElementLoads(method) >= 14,
            $"Parenthesized SoA numeric expression stores should read current values from backing arrays for {indexDescription} access.");
        Assert.Equal(28, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Add) >= 1,
            $"Parenthesized SoA numeric addition should use the direct ADD opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Sub) >= 1,
            $"Parenthesized SoA numeric subtraction should use the direct SUB opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Mul) >= 1,
            $"Parenthesized SoA numeric multiplication should use the direct MUL opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Div) >= 1,
            $"Parenthesized SoA signed numeric division should use the direct DIV opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Rem) >= 1,
            $"Parenthesized SoA signed numeric remainder should use the direct REM opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Div_Un) >= 1,
            $"Parenthesized SoA unsigned numeric division should use the direct DIV.UN opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Rem_Un) >= 1,
            $"Parenthesized SoA unsigned numeric remainder should use the direct REM.UN opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Shl) >= 2,
            $"Parenthesized SoA numeric left shifts should use the direct SHL opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Shr) >= 1,
            $"Parenthesized SoA signed numeric right shifts should use the direct SHR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Shr_Un) >= 1,
            $"Parenthesized SoA unsigned numeric right shifts should use the direct SHR.UN opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Or) >= 1,
            $"Parenthesized SoA numeric bitwise-or should use the direct OR opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.And) >= 1,
            $"Parenthesized SoA numeric bitwise-and should use the direct AND opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Xor) >= 1,
            $"Parenthesized SoA numeric bitwise-xor should use the direct XOR opcode for {indexDescription} access.");
    }

    private static void AssertParenthesizedNumericUnaryColumnShape(MethodInfo method, string indexDescription)
    {
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Ldfld) >= 10,
            $"Parenthesized SoA numeric unary stores should load backing column fields directly for {indexDescription} access.");
        Assert.True(
            CountArrayElementLoads(method) >= 5,
            $"Parenthesized SoA numeric unary stores should read current values from backing arrays for {indexDescription} access.");
        Assert.Equal(10, CountArrayElementStores(method));
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Neg) >= 2,
            $"Parenthesized SoA signed numeric unary negation should use the direct NEG opcode for {indexDescription} access.");
        Assert.True(
            ILShapeInspector.CountOpcode(method, OpCodes.Not) >= 3,
            $"Parenthesized SoA numeric unary bitwise-not should use the direct NOT opcode for {indexDescription} access.");
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
