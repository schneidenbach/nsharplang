using System;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SoaRecordTests : ILCompilerTestBase
{
    private const string ExperimentalSoaEnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";

    [Fact]
    public void Analyzer_SoaRecordWithoutFlag_IsFeatureGated()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, null);

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                valueStart: int
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("soa record 'NodeTable'", error.Message);
        Assert.Contains(ExperimentalSoaEnvironmentVariable, error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_TypesTableMembersAndRowProjection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                start: int
            }

            func probe(): int {
                nodes := new NodeTable(4)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.kind[row] = nodes[row].kind + nodes.capacity + nodes.length
                return nodes.kind[row]
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_AllowsVerifiedColumnTypes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            type CountColumn = int
            type OptionalNameColumn = string?

            soa record NodeTable {
                kind: int
                flags: uint
                start: long
                active: bool
                marker: char
                name: string
                optionalName: OptionalNameColumn
                count: CountColumn
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsUnsupportedColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                payload: object
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'object' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, or string?", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsUnsupportedAliasedColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            type PayloadColumn = object

            soa record NodeTable {
                payload: PayloadColumn
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'object' is not supported in this lowering", error.Message);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsDuplicateColumnName()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                kind: int
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DuplicateDeclaration);
        Assert.Contains("SoA column 'kind' is already defined", error.Message);
        Assert.Contains("unique name", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsGeneratedMemberColumnName()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                length: int
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DuplicateDeclaration);
        Assert.Contains("SoA column 'length' conflicts with a generated table member", error.Message);
        Assert.Contains("reserve length, capacity, add, clear, ensureCapacity, copyRow, and wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoLocal()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                row := nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a variable", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoCallArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func consume(value: object) {
            }

            func bad(nodes: NodeTable): int {
                consume(nodes[0])
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be passed as an argument", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughReturn()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): object {
                return nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughExpressionBodiedFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): object => nodes[0]
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughExpressionBodiedLocalFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                func leak(): object => nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughExpressionBodiedProperty()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
                Row: object => Nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughTypedExpressionBodiedLambda()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                let leak: Func<object> = () => nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughInferredExpressionBodiedLambda()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                leak := () => nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughBlockBodiedLambda()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                let leak: Func<object> = () => { return nodes[0] }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoArrayLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                values := [nodes[0]]
                return values.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an array", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoTupleLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                values := (row: nodes[0], fallback: 1)
                return values.fallback
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a tuple", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughArrayInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                values := new object[] { nodes[0] }
                return values.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an initializer", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsInitializerIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Bag {
                func this[index: int]: int {
                    get {
                        return 0
                    }
                    set {
                    }
                }
            }

            func bad(nodes: NodeTable): int {
                bag := new Bag {
                    [nodes[0]] = 1
                }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an initializer index", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoConstructorArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                constructor(value: object) {
                }
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder(nodes[0])
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be passed as a constructor argument", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBePrinted()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                print nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be printed", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeFormattedInInterpolatedString()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): string {
                return $"{nodes[0]}"
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be formatted in an interpolated string", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeThrown()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                throw nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be thrown", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeThrownFromExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, ok: bool): int {
                return ok ? 1 : throw nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be thrown", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeDiscarded()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                _ = nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be discarded", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeYielded()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func* bad(nodes: NodeTable): IEnumerable<object> {
                yield nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be yielded", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeAsserted()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                assert nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be asserted", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsAssertMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                assert true, nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an assertion message", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsUsingResource()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                using (nodes[0]) {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a using resource", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeLocked()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                lock (nodes[0]) {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be locked", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsSwitchValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                switch nodes[0] {
                    default => return 0
                }
                return 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a switch value", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsOperatorOperand()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): bool {
                return nodes[0] == null
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an operator operand", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsUnaryOperand()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                assert !nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a unary operand", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeCast()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0] as object
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be cast", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeTestedWithIs()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                if nodes[0] is object {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be tested with 'is'", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUnwrappedWithMust()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := must nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be unwrapped with 'must'", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeAwaited()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                await nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be awaited", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsTernaryResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, ok: bool) {
                value := ok ? nodes[0] : null
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a ternary result", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsMatchResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, ok: bool) {
                value := match ok {
                    true => nodes[0],
                    false => null
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a match result", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsExpressionStatement()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be discarded", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsIfCondition()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                if nodes[0] {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an 'if' condition", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsWhileCondition()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                while nodes[0] {
                    break
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a 'while' condition", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsForCondition()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                for i := 0; nodes[0]; i++ {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a 'for' condition", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsTernaryCondition()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[0] ? 1 : 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a ternary condition", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsMatchValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return match nodes[0] {
                    _ => 0
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a match value", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsMatchGuard()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, ok: bool): int {
                return match ok {
                    true when nodes[0] => 1,
                    _ => 0
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a match guard", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsForeachCollection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                foreach value in nodes[0] {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a foreach collection", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsAsyncForeachCollection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                await foreach value in nodes[0] {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an async foreach collection", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsRangeBound()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0]..1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a range bound", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeSpread()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                values := [...nodes[0]]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be spread", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeAllocated()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := alloc (nodes[0])
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("this operation would allocate row objects; use column access instead", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsArrayLength()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                values := new int[nodes[0]]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an array length", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsStackAllocLength()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                span := stackalloc int[nodes[0]]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a stackalloc length", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedInCheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := checked(nodes[0])
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used in a checked expression", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedInUncheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := unchecked(nodes[0])
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used in an unchecked expression", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughFieldInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable = new NodeTable(1)
                Row: object = Nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a field", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsMemberReceiver()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0].ToString
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a member receiver", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsIndexReceiver()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0][0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an index receiver", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsIndexValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                values := [1, 2]
                value := values[nodes[0]]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an index value", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableRowIndexMustBeInt()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes["0"].kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("'string'", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseRangeIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[0..1].kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("range", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsRelationalPatternValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return match 5 {
                    < (nodes[0]) => 1,
                    _ => 0
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a relational pattern value", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsLiteralPatternValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return match 5 {
                    0 => 1,
                    _ => 0
                }
            }
            """;
        var unit = ParseForAnalysis(source);
        var function = Assert.IsType<FunctionDeclaration>(unit.Declarations[1]);
        var returnStatement = Assert.IsType<ReturnStatement>(function.Body!.Statements[0]);
        var match = Assert.IsType<MatchExpression>(returnStatement.Value);
        match.Cases[0] = match.Cases[0] with
        {
            Pattern = new LiteralPattern(CreateSoaRowView("nodes"), Line: 7, Column: 17)
        };

        var result = Analyze(unit, source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a pattern value", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsWithTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0] with { kind: 1 }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a with target", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsWithInitializerIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Value: int
            }

            func bad(nodes: NodeTable) {
                original := new Holder { Value: 1 }
                updated := original with { Value: 1 }
            }
            """;
        var unit = ParseForAnalysis(source);
        var function = Assert.IsType<FunctionDeclaration>(unit.Declarations[2]);
        var updated = Assert.IsType<VariableDeclarationStatement>(function.Body!.Statements[1]);
        var with = Assert.IsType<WithExpression>(updated.Initializer);
        with.Properties.Clear();
        with.Properties.Add(new PropertyInitializer(
            null,
            CreateSoaRowView("nodes"),
            new IntLiteralExpression("1", Line: 11, Column: 42),
            NameLine: 11,
            NameColumn: 42));

        var result = Analyze(unit, source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a with initializer index", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsWithValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Value: object
            }

            func bad(nodes: NodeTable) {
                original := new Holder { Value: 1 }
                updated := original with { Value: nodes[0] }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a with expression", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsEventTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                on nodes[0] (sender, args) => { }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an event target", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsOffHandle()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                off nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an off handle", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeUsedAsNameofTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): string {
                return nameof(nodes[0])
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a nameof target", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughAssignment()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Value: object
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder()
                holder.Value = nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be assigned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughObjectInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Value: object
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder { Value: nodes[0] }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an object initializer", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnArrayCannotBeAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind = new int[](1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'kind' cannot be assigned directly", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableLengthCannotBeAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.length = 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'length' cannot be assigned directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableLengthCannotBeIncrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.length++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'length' cannot be incremented or decremented directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void ILCompiler_SoaRecordNewAddAndRowProjection_LowersToColumns()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                first := nodes.add()
                nodes[first].kind = 10
                nodes[first].start = 20
                second := nodes.add()
                nodes[second].kind = nodes[first].kind + 1
                nodes[second].kind += nodes[first].kind
                nodes[second].start = nodes[first].start + 2
                return nodes.length * 1000 + nodes.capacity * 100 + nodes[second].kind * 10 + nodes[second].start
            }
            """;

        Assert.Equal(2632, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordVerifiedColumnTypes_LoadStoreRoundTrip()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            type CountColumn = int
            type OptionalNameColumn = string?

            soa record NodeTable {
                kind: int
                flags: uint
                start: long
                active: bool
                marker: char
                name: string
                optionalName: OptionalNameColumn
                count: CountColumn
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 3
                nodes[row].flags = (uint)7
                nodes[row].start = 19L
                nodes[row].active = true
                nodes[row].marker = 'A'
                nodes[row].name = "abcd"
                nodes[row].optionalName = null
                nodes[row].count = 11
                total := nodes[row].kind
                total += (int)nodes[row].flags
                total += (int)nodes[row].start
                total += (nodes[row].active ? 100 : 0)
                total += (int)nodes[row].marker
                total += nodes[row].name.Length
                total += (nodes[row].optionalName == null ? 1000 : 0)
                total += nodes[row].count
                return total
            }
            """;

        Assert.Equal(1209, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordWrap_IsZeroCopyAndValidatesLength()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds := new int[](2)
                starts := new int[](2)
                kinds[0] = 3
                starts[0] = 4
                nodes := NodeTable.wrap(kinds, starts, 1)
                nodes[0].kind = 8
                nodes[0].start += 5
                return kinds[0] + starts[0] * 10 + nodes.capacity * 100 + nodes.length * 1000
            }
            """;

        Assert.Equal(1298, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordWrapMismatchedColumns_ReportsColumnLengthMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds := new int[](2)
                starts := new int[](3)
                nodes := NodeTable.wrap(kinds, starts, 1)
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("column lengths for NodeTable do not match", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordWrapNullColumn_ReportsNullColumnMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds: int[] = null
                starts := new int[](2)
                nodes := NodeTable.wrap(kinds, starts, 1)
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("columns for NodeTable.wrap cannot be null", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordWrapNegativeLength_ReportsLengthMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds := new int[](2)
                starts := new int[](2)
                nodes := NodeTable.wrap(kinds, starts, -1)
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("length for NodeTable.wrap must be between 0 and column length", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordWrapLengthBeyondCapacity_ReportsLengthMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds := new int[](2)
                starts := new int[](2)
                nodes := NodeTable.wrap(kinds, starts, 3)
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("length for NodeTable.wrap must be between 0 and column length", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordCopyRowAndClear_UpdateLengthWithoutRowObjects()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 5
                nodes[row].start = 7
                nodes.copyRow(0, 3)
                before := nodes.length * 100 + nodes.capacity * 10 + nodes[3].kind + nodes[3].start
                nodes.clear()
                return before * 10 + nodes.length
            }
            """;

        Assert.Equal(4520, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceAssignOnRowColumn_StoresOnlyWhenNull()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func main(): string {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes[first].text ??= "fallback"
                nodes[first].text ??= "other"
                nodes[second].text = "ready"
                nodes[second].text ??= "ignored"
                return nodes[first].text + ":" + nodes[second].text
            }
            """;

        Assert.Equal("fallback:ready", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceOnRowColumn_ChoosesFallbackOrExistingValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func main(): string {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                missing := nodes[first].text ?? "fallback"
                nodes[second].text = "ready"
                existing := nodes[second].text ?? "ignored"
                return missing + ":" + existing
            }
            """;

        Assert.Equal("fallback:ready", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceAssignOnNonNullableRowColumn_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].kind ??= 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnNonNullableRowColumn_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int): int {
                return nodes[row].kind ?? 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void ILCompiler_SoaRecordRowColumnIncrementAndDecrement_PreservesPostfixSemantics()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 10
                oldUp := nodes[row].kind++
                oldDown := nodes[row].kind--
                nodes[row].kind++
                nodes[row].kind++
                return oldUp * 1000 + oldDown * 100 + nodes[row].kind
            }
            """;

        Assert.Equal(11112, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    private static CompilationUnit ParseForAnalysis(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();
        Assert.True(parseResult.Success, string.Join(Environment.NewLine, parseResult.Errors.Select(error => error.Message)));
        return parseResult.CompilationUnit!;
    }

    private static AnalysisResult Analyze(string source)
        => Analyze(ParseForAnalysis(source), source);

    private static AnalysisResult Analyze(CompilationUnit unit, string source)
    {
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(unit, "test.nl", null, source);
    }

    private static IndexAccessExpression CreateSoaRowView(string tableName)
        => new(
            new IdentifierExpression(tableName, Line: 1, Column: 1),
            new IntLiteralExpression("0", Line: 1, Column: 1),
            IsNullConditional: false,
            Line: 1,
            Column: 1);

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
