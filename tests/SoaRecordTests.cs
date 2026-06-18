using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
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
    public void Analyzer_SoaRecordWithoutFlag_DoesNotResolveColumnTypes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, null);

        var result = Analyze("""
            soa record NodeTable {
                payload: MissingColumnType
            }
            """);

        var error = Assert.Single(result.Errors);
        Assert.Equal(ErrorCode.FeatureNotImplemented, error.Code);
        Assert.Contains("soa record 'NodeTable'", error.Message);
        Assert.DoesNotContain("MissingColumnType", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordWithoutFlag_DoesNotReportRowTypeAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, null);

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(row: NodeTable.Row): int {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors);
        Assert.Equal(ErrorCode.FeatureNotImplemented, error.Code);
        Assert.Contains("soa record 'NodeTable'", error.Message);
        Assert.DoesNotContain("NodeTable.Row", error.Message);
    }

    [Fact]
    public void Analyzer_NestedSoaRecordWithFlag_DoesNotResolveColumnTypes()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            class Holder {
                soa record NodeTable {
                    payload: MissingColumnType
                }
            }
            """);

        var error = Assert.Single(result.Errors);
        Assert.Equal(ErrorCode.FeatureNotImplemented, error.Code);
        Assert.Contains("nested soa record 'NodeTable'", error.Message);
        Assert.DoesNotContain("MissingColumnType", error.Message);
    }

    [Fact]
    public void Parser_SoaRecordRejectsTypeParametersBeforeAnalysis()
    {
        var result = ParseWithErrors("""
            soa record NodeTable<T> {
                kind: int
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("soa record type parameters are not supported yet", error.Message);
        Assert.Contains("Generic soa tables need an explicit ABI design", error.HumanExplanation);
        Assert.Contains("Remove the type parameter list", error.ContextualHint);
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
            type KindColumn = int
            type FlagsColumn = uint
            type StartColumn = long
            type ActiveColumn = bool
            type MarkerColumn = char
            type NameColumn = string
            type CountColumn = int
            type OptionalNameColumn = string?

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
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_AllowsIntEnumColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_AllowsAliasedIntEnumColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            type KindColumn = NodeKind

            soa record NodeTable {
                kind: KindColumn
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsStringEnumColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind: string {
                Identifier = "identifier"
            }

            soa record NodeTable {
                kind: NodeKind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'NodeKind' is not supported in this lowering", error.Message);
        Assert.Contains("int-backed enum columns", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsAliasedStringEnumColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind: string {
                Identifier = "identifier"
            }

            type KindColumn = NodeKind

            soa record NodeTable {
                kind: KindColumn
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'NodeKind' is not supported in this lowering", error.Message);
        Assert.Contains("int-backed enum columns", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
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
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
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
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsArrayColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                values: int[]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'int[]' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsAliasedArrayColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            type ValuesColumn = int[]

            soa record NodeTable {
                values: ValuesColumn
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'int[]' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsNullableNonStringColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                maybeKind: int?
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'int?' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsAliasedNullableNonStringColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            type MaybeKindColumn = int?

            soa record NodeTable {
                maybeKind: MaybeKindColumn
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'int?' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsNestedSoaColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record ChildTable {
                kind: int
            }

            soa record ParentTable {
                child: ChildTable
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'ChildTable' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_RejectsAliasedNestedSoaColumnType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record ChildTable {
                kind: int
            }

            type ChildColumn = ChildTable

            soa record ParentTable {
                child: ChildColumn
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("SoA column type 'ChildTable' is not supported in this lowering", error.Message);
        Assert.Contains("Use int, uint, long, bool, char, string, string?, or int-backed enum columns", error.Suggestion);
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
    public void Analyzer_SoaTableCannotBeDefaultInitializedInLocal()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = default
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultReturned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable {
                return default
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultReturnedFromExpressionBodiedFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable => default
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultReturnedFromExpressionBodiedLocalFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                func make(): NodeTable => default
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultPassedAsArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func consume(nodes: NodeTable) {
            }

            func bad() {
                consume(default)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInHardCast()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := (NodeTable)default
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInCheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = checked(default)
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInUncheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = unchecked(default)
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultParameterValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = default) {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseNullAsDefaultParameterValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = null) {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidDefaultParameterValue);
        Assert.Contains("SoA table 'NodeTable' cannot be used as a default parameter value", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseCapacityConstructorAsDefaultParameterValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = new NodeTable(1)) {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidDefaultParameterValue);
        Assert.Contains("SoA table 'NodeTable' cannot be used as a default parameter value", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseDefaultParameterValueOutsideTopLevelFunctions()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new (string Source, string Message)[]
        {
            ("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                constructor(nodes: NodeTable = null) {
                }
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                constructor(nodes: NodeTable = new NodeTable(1)) {
                }
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            func outer() {
                func inner(nodes: NodeTable = null) {
                }
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            test "bad table default" with (nodes: NodeTable = null) [
                (null)
            ] {
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            test "bad table default" with (nodes: NodeTable = new NodeTable(1)) [
                (null)
            ] {
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            class Holder(nodes: NodeTable = null) {
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            struct Holder(nodes: NodeTable = null) {
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            record Holder(nodes: NodeTable = null) {
            }
            """, "SoA table 'NodeTable' cannot be used as a default parameter value")
        };

        foreach (var (source, message) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidDefaultParameterValue);
            Assert.Contains(message, error.Message);
            Assert.Contains("new NodeTable(capacity)", error.Suggestion);
            Assert.Contains("NodeTable.wrap", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableAliasCannotBeDefaultInitialized()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new (string Source, ErrorCode Code, string Message)[]
        {
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes: Nodes = default
                return nodes.length
            }
            """, ErrorCode.InvalidSyntax, "SoA table 'NodeTable' cannot be default-initialized"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes: Nodes? = default
                return 0
            }
            """, ErrorCode.InvalidSyntax, "SoA table 'NodeTable' cannot be default-initialized"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): Nodes {
                return default
            }
            """, ErrorCode.InvalidSyntax, "SoA table 'NodeTable' cannot be default-initialized"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func consume(nodes: Nodes) {
            }

            func bad() {
                consume(default)
            }
            """, ErrorCode.InvalidSyntax, "SoA table 'NodeTable' cannot be default-initialized"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes := (Nodes)default
                return nodes.length
            }
            """, ErrorCode.InvalidSyntax, "SoA table 'NodeTable' cannot be default-initialized"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes = null) {
            }
            """, ErrorCode.InvalidDefaultParameterValue, "SoA table 'NodeTable' cannot be used as a default parameter value"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes = new Nodes(1)) {
            }
            """, ErrorCode.InvalidDefaultParameterValue, "SoA table 'NodeTable' cannot be used as a default parameter value")
        };

        foreach (var (source, code, message) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == code);
            Assert.Contains(message, error.Message);
            Assert.Contains("new NodeTable(capacity)", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaTableAliasCannotUseTargetTypedNewWithoutCapacity()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes: Nodes = new()
                return nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes: Nodes? = new()
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): Nodes {
                return new()
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func consume(nodes: Nodes) {
            }

            func bad() {
                consume(new())
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes := (Nodes)new()
                return nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                nodes: Nodes = checked(new())
                return nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes = new()) {
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
            Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
            Assert.Contains("new NodeTable(capacity)", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaTableTargetTypedDefaultAndNewCannotHideInLambdaReturns()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new (string Statement, ErrorCode Code, string Message, string Suggestion)[]
        {
            (
                "let make: Func<NodeTable> = () => default",
                ErrorCode.InvalidSyntax,
                "SoA table 'NodeTable' cannot be default-initialized",
                "NodeTable.wrap"),
            (
                "let make: Func<NodeTable> = () => { return default }",
                ErrorCode.InvalidSyntax,
                "SoA table 'NodeTable' cannot be default-initialized",
                "NodeTable.wrap"),
            (
                "let make: Func<NodeTable> = () => new()",
                ErrorCode.NoMatchingOverload,
                "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                "new NodeTable(capacity)"),
            (
                "let make: Func<NodeTable> = () => { return new() }",
                ErrorCode.NoMatchingOverload,
                "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                "new NodeTable(capacity)"),
            (
                "let make: Func<Nodes> = () => default",
                ErrorCode.InvalidSyntax,
                "SoA table 'NodeTable' cannot be default-initialized",
                "NodeTable.wrap"),
            (
                "let make: Func<Nodes> = () => { return default }",
                ErrorCode.InvalidSyntax,
                "SoA table 'NodeTable' cannot be default-initialized",
                "NodeTable.wrap"),
            (
                "let make: Func<Nodes> = () => new()",
                ErrorCode.NoMatchingOverload,
                "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                "new NodeTable(capacity)"),
            (
                "let make: Func<Nodes> = () => { return new() }",
                ErrorCode.NoMatchingOverload,
                "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                "new NodeTable(capacity)")
        };

        foreach (var (statement, code, message, suggestion) in cases)
        {
            var result = Analyze($$"""
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(): int {
                    {{statement}}
                    return 0
                }
                """);

            var error = Assert.Single(result.Errors, e => e.Code == code && e.Message.Contains(message));
            Assert.Contains(suggestion, error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInField()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                nodes: NodeTable = default
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInExpressionBodiedProperty()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable => default
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInObjectInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
            }

            func bad(): Holder {
                return new Holder { Nodes: default }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInWithExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Nodes: NodeTable
            }

            func bad(): int {
                original := new Holder { Nodes: new NodeTable(1) }
                updated := original with { Nodes: default }
                return updated.Nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := new NodeTable(1)
                nodes = default
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInArrayLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables: NodeTable[] = [default]
                return tables.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInCollectionLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let tables: List<NodeTable> = [default]
                return tables.Count
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInArrayInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables := new NodeTable[] { default }
                return tables.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInNamedTupleLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (nodes: NodeTable, count: int) = (nodes: default, count: 1)
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInPositionalTupleLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (NodeTable, int) = (default, 1)
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInTernaryResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = ok ? new NodeTable(1) : default
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotBeDefaultInitializedInMatchResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = match ok {
                    true => new NodeTable(1),
                    false => default
                }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table 'NodeTable' cannot be default-initialized", error.Message);
        Assert.Contains("NodeTable.wrap", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInLocal()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = new()
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInNullableLocal()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable? = new()
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInReturn()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable {
                return new()
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInNullableReturn()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable? {
                return new()
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInExpressionBodiedFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable => new()
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInExpressionBodiedLocalFunction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                func make(): NodeTable => new()
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityAsArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func consume(nodes: NodeTable) {
            }

            func bad() {
                consume(new())
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityAsNullableArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func consume(nodes: NodeTable?) {
            }

            func bad() {
                consume(new())
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInHardCast()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := (NodeTable)new()
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInNullableHardCast()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := (NodeTable?)new()
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInCheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = checked(new())
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInUncheckedExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes: NodeTable = unchecked(new())
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityAsDefaultParameterValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = new()) {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInField()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                nodes: NodeTable = new()
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInExpressionBodiedProperty()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable => new()
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInObjectInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
            }

            func bad(): Holder {
                return new Holder { Nodes: new() }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInWithExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Nodes: NodeTable
            }

            func bad(): int {
                original := new Holder { Nodes: new NodeTable(1) }
                updated := original with { Nodes: new() }
                return updated.Nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInAssignment()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := new NodeTable(1)
                nodes = new()
                return nodes.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInArrayLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables: NodeTable[] = [new()]
                return tables.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInCollectionLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let tables: List<NodeTable> = [new()]
                return tables.Count
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInArrayInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables := new NodeTable[] { new() }
                return tables.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInNamedTupleLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (nodes: NodeTable, count: int) = (nodes: new(), count: 1)
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInPositionalTupleLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (NodeTable, int) = (new(), 1)
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInTernaryResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = ok ? new() : new NodeTable(1)
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseTargetTypedNewWithoutCapacityInMatchResult()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = match ok {
                    true => new(),
                    false => new NodeTable(1)
                }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableParenthesizedTargetTypedDefaultAndNewPreserveExpectedType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(): int {
                    nodes: NodeTable = (default)
                    return nodes.length
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA table 'NodeTable' cannot be default-initialized",
                Suggestion: "NodeTable.wrap"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(): NodeTable {
                    return (default)
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA table 'NodeTable' cannot be default-initialized",
                Suggestion: "NodeTable.wrap"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func consume(nodes: NodeTable) {
                }

                func bad() {
                    consume((default))
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA table 'NodeTable' cannot be default-initialized",
                Suggestion: "NodeTable.wrap"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(): int {
                    nodes: NodeTable = (new())
                    return nodes.length
                }
                """,
                Code: ErrorCode.NoMatchingOverload,
                Message: "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                Suggestion: "new NodeTable(capacity)"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(): NodeTable {
                    return (new())
                }
                """,
                Code: ErrorCode.NoMatchingOverload,
                Message: "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                Suggestion: "new NodeTable(capacity)"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func consume(nodes: NodeTable) {
                }

                func bad() {
                    consume((new()))
                }
                """,
                Code: ErrorCode.NoMatchingOverload,
                Message: "SoA table 'NodeTable' construction expects exactly one int capacity argument",
                Suggestion: "new NodeTable(capacity)")
        };

        foreach (var (source, code, message, suggestion) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == code && e.Message.Contains(message));
            Assert.Contains(suggestion, error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
        }
    }

    [Fact]
    public void Analyzer_SoaTableParenthesizedTargetTypedDefaultAndNewStayDiagnosedInStorageAndResultContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var defaultCases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = (default)) {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                nodes: NodeTable = (default)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable => (default)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
            }

            func bad(): Holder {
                return new Holder { Nodes: (default) }
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Nodes: NodeTable
            }

            func bad(): int {
                original := new Holder { Nodes: new NodeTable(1) }
                updated := original with { Nodes: (default) }
                return updated.Nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := new NodeTable(1)
                nodes = (default)
                return nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables: NodeTable[] = [(default)]
                return tables.Length
            }
            """,
            """
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let tables: List<NodeTable> = [(default)]
                return tables.Count
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables := new NodeTable[] { (default) }
                return tables.Length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (nodes: NodeTable, count: int) = (nodes: (default), count: 1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (NodeTable, int) = ((default), 1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = ok ? (default) : new NodeTable(1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = match ok {
                    true => (default),
                    false => new NodeTable(1)
                }
                return 0
            }
            """
        };

        foreach (var source in defaultCases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA table 'NodeTable' cannot be default-initialized"));
            Assert.Contains("NodeTable.wrap", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
        }

        var newCases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable = (new())) {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                nodes: NodeTable = (new())
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable => (new())
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
            }

            func bad(): Holder {
                return new Holder { Nodes: (new()) }
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            record Holder {
                Nodes: NodeTable
            }

            func bad(): int {
                original := new Holder { Nodes: new NodeTable(1) }
                updated := original with { Nodes: (new()) }
                return updated.Nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := new NodeTable(1)
                nodes = (new())
                return nodes.length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables: NodeTable[] = [(new())]
                return tables.Length
            }
            """,
            """
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let tables: List<NodeTable> = [(new())]
                return tables.Count
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                tables := new NodeTable[] { (new()) }
                return tables.Length
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (nodes: NodeTable, count: int) = (nodes: (new()), count: 1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                let values: (NodeTable, int) = ((new()), 1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = ok ? (new()) : new NodeTable(1)
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(ok: bool): int {
                let nodes: NodeTable = match ok {
                    true => (new()),
                    false => new NodeTable(1)
                }
                return 0
            }
            """
        };

        foreach (var source in newCases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.NoMatchingOverload
                    && e.Message.Contains("SoA table 'NodeTable' construction expects exactly one int capacity argument"));
            Assert.Contains("new NodeTable(capacity)", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CannotInferType);
        }
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
    public void Analyzer_SoaRowViewCannotEscapeThroughTupleDeconstruction()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                (row, other) := nodes[0]
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                row, other := nodes[0]
                return 0
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA row views cannot be deconstructed", error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromCoreContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    row := (nodes[0])
                    return 0
                }
                """,
                Message: "SoA row views cannot be stored in a variable"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): object {
                    return (nodes[0])
                }
                """,
                Message: "SoA row views cannot be returned"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func consume(value: object) {
                }

                func bad(nodes: NodeTable): int {
                    consume((nodes[0]))
                    return 0
                }
                """,
                Message: "SoA row views cannot be passed as an argument"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    values := [(nodes[0])]
                    return values.Length
                }
                """,
                Message: "SoA row views cannot be stored in an array")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromAdvancedContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): bool {
                    return (nodes[0]) == null
                }
                """,
                Message: "SoA row views cannot be used as an operator operand"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    if (nodes[0]) {
                    }
                }
                """,
                Message: "SoA row views cannot be used as an 'if' condition"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    foreach value in (nodes[0]) {
                    }
                }
                """,
                Message: "SoA row views cannot be used as a foreach collection"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := checked((nodes[0]))
                }
                """,
                Message: "SoA row views cannot be used in a checked expression"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0]) with { kind: 1 }
                }
                """,
                Message: "SoA row views cannot be used as a with target"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (nodes[0]) = 1
                }
                """,
                Message: "SoA row views cannot be assigned")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromTypeAndResultContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0]) as object
                }
                """,
                Message: "SoA row views cannot be cast"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    if (nodes[0]) is object {
                    }
                }
                """,
                Message: "SoA row views cannot be tested with 'is'"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := must (nodes[0])
                }
                """,
                Message: "SoA row views cannot be unwrapped with 'must'"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    await (nodes[0])
                }
                """,
                Message: "SoA row views cannot be awaited"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable, ok: bool) {
                    value := ok ? (nodes[0]) : null
                }
                """,
                Message: "SoA row views cannot be used as a ternary result"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable, ok: bool) {
                    value := match ok {
                        true => (nodes[0]),
                        false => null
                    }
                }
                """,
                Message: "SoA row views cannot be used as a match result")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromControlAndAllocationContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    while (nodes[0]) {
                        break
                    }
                }
                """,
                Message: "SoA row views cannot be used as a 'while' condition"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    for i := 0; (nodes[0]); i++ {
                    }
                }
                """,
                Message: "SoA row views cannot be used as a 'for' condition"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return (nodes[0]) ? 1 : 0
                }
                """,
                Message: "SoA row views cannot be used as a ternary condition"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return match (nodes[0]) {
                        _ => 0
                    }
                }
                """,
                Message: "SoA row views cannot be used as a match value"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable, ok: bool): int {
                    return match ok {
                        true when (nodes[0]) => 1,
                        _ => 0
                    }
                }
                """,
                Message: "SoA row views cannot be used as a match guard"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0])..1
                }
                """,
                Message: "SoA row views cannot be used as a range bound"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    values := [...(nodes[0])]
                }
                """,
                Message: "SoA row views cannot be spread"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    values := new int[(nodes[0])]
                }
                """,
                Message: "SoA row views cannot be used as an array length"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    span := stackalloc int[(nodes[0])]
                }
                """,
                Message: "SoA row views cannot be used as a stackalloc length")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromReceiverAndMetadataContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (nodes[0])
                }
                """,
                Message: "SoA row views cannot be discarded"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0]).ToString
                }
                """,
                Message: "SoA row views cannot be used as a member receiver"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0])[0]
                }
                """,
                Message: "SoA row views cannot be used as an index receiver"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    values := [1, 2]
                    value := values[(nodes[0])]
                }
                """,
                Message: "SoA row views cannot be used as an index value"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := (nodes[0])?.kind
                }
                """,
                Message: "SoA row views cannot be used with null-conditional member access"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                record Holder {
                    Value: object
                }

                func bad(nodes: NodeTable) {
                    original := new Holder { Value: 1 }
                    updated := original with { Value: (nodes[0]) }
                }
                """,
                Message: "SoA row views cannot be stored in a with expression"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): string {
                    return nameof((nodes[0]))
                }
                """,
                Message: "SoA row views cannot be used as a nameof target")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromLiteralStatementAndResourceContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    values := [(nodes[0])]
                    return values.Length
                }
                """,
                Message: "SoA row views cannot be stored in an array"),
            (Source: """
                import System.Collections.Generic

                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    let values: List<object> = [(nodes[0])]
                    return values.Count
                }
                """,
                Message: "SoA row views cannot be stored in a collection literal"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    values := (row: (nodes[0]), fallback: 1)
                    return values.fallback
                }
                """,
                Message: "SoA row views cannot be stored in a tuple"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    values := new object[] { (nodes[0]) }
                    return values.Length
                }
                """,
                Message: "SoA row views cannot be stored in an initializer"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                class Holder {
                    constructor(value: object) {
                    }
                }

                func bad(nodes: NodeTable): int {
                    holder := new Holder((nodes[0]))
                    return 0
                }
                """,
                Message: "SoA row views cannot be passed as a constructor argument"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    print (nodes[0])
                }
                """,
                Message: "SoA row views cannot be printed"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): string {
                    return $"{(nodes[0])}"
                }
                """,
                Message: "SoA row views cannot be formatted in an interpolated string"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    throw (nodes[0])
                }
                """,
                Message: "SoA row views cannot be thrown"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    _ = (nodes[0])
                }
                """,
                Message: "SoA row views cannot be discarded"),
            (Source: """
                import System.Collections.Generic

                soa record NodeTable {
                    kind: int
                }

                func* bad(nodes: NodeTable): IEnumerable<object> {
                    yield (nodes[0])
                }
                """,
                Message: "SoA row views cannot be yielded"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    assert (nodes[0])
                }
                """,
                Message: "SoA row views cannot be asserted"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    assert true, (nodes[0])
                }
                """,
                Message: "SoA row views cannot be used as an assertion message"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    using ((nodes[0])) {
                    }
                }
                """,
                Message: "SoA row views cannot be used as a using resource"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    lock ((nodes[0])) {
                    }
                }
                """,
                Message: "SoA row views cannot be locked"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    switch (nodes[0]) {
                        default => return 0
                    }
                    return 1
                }
                """,
                Message: "SoA row views cannot be used as a switch value")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromExpressionBodiedContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): object => (nodes[0])
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                func leak(): object => (nodes[0])
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Nodes: NodeTable
                Row: object => (Nodes[0])
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                let leak: Func<object> = () => (nodes[0])
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                leak := () => (nodes[0])
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                let leak: Func<object> = () => { return (nodes[0]) }
                return 0
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA row views cannot be returned", error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromStorageAndMutationContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                class Holder {
                    Nodes: NodeTable = new NodeTable(1)
                    Row: object = (Nodes[0])
                }
                """,
                Message: "SoA row views cannot be stored in a field"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                class Holder {
                    Value: object
                }

                func bad(nodes: NodeTable): int {
                    holder := new Holder()
                    holder.Value = (nodes[0])
                    return 0
                }
                """,
                Message: "SoA row views cannot be assigned"),
            (Source: """
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
                        [(nodes[0])] = 1
                    }
                    return 0
                }
                """,
                Message: "SoA row views cannot be used as an initializer index"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                class Holder {
                    Value: object
                }

                func bad(nodes: NodeTable): int {
                    holder := new Holder { Value: (nodes[0]) }
                    return 0
                }
                """,
                Message: "SoA row views cannot be stored in an object initializer"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := unchecked((nodes[0]))
                }
                """,
                Message: "SoA row views cannot be used in an unchecked expression"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (nodes[0]) += 1
                }
                """,
                Message: "SoA row views cannot be assigned"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (nodes[0]) ??= null
                }
                """,
                Message: "SoA row views cannot be assigned"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (nodes[0])++
                }
                """,
                Message: "SoA row views cannot be used as a unary operand")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_ParenthesizedSoaRowViewCannotEscapeFromPatternEventAndAsyncContexts()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    await foreach value in (nodes[0]) {
                    }
                }
                """,
                Message: "SoA row views cannot be used as an async foreach collection"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    row := (nodes)?[0]
                }
                """,
                Message: "SoA row views cannot be used with null-conditional indexing"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable, ok: bool): int {
                    return ok ? 1 : throw (nodes[0])
                }
                """,
                Message: "SoA row views cannot be thrown"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return match 5 {
                        < (nodes[0]) => 1,
                        _ => 0
                    }
                }
                """,
                Message: "SoA row views cannot be used as a relational pattern value"),
            (Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    value := alloc (nodes[0])
                }
                """,
                Message: "this operation would allocate row objects; use column access instead")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        }

        var patternSource = """
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
        var patternUnit = ParseForAnalysis(patternSource);
        var patternFunction = Assert.IsType<FunctionDeclaration>(patternUnit.Declarations[1]);
        var patternReturn = Assert.IsType<ReturnStatement>(patternFunction.Body!.Statements[0]);
        var patternMatch = Assert.IsType<MatchExpression>(patternReturn.Value);
        patternMatch.Cases[0] = patternMatch.Cases[0] with
        {
            Pattern = new LiteralPattern(
                new ParenthesizedExpression(CreateSoaRowView("nodes"), Line: 7, Column: 17),
                Line: 7,
                Column: 17)
        };

        var patternResult = Analyze(patternUnit, patternSource);
        var patternError = Assert.Single(patternResult.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a pattern value", patternError.Message);
        Assert.Contains("table[index].column", patternError.Suggestion);

        var onSource = """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                on nodes[0] (sender, args) => { }
            }
            """;
        var onUnit = ParseForAnalysis(onSource);
        var onFunction = Assert.IsType<FunctionDeclaration>(onUnit.Declarations[1]);
        var onStatement = Assert.IsType<ExpressionStatement>(onFunction.Body!.Statements[0]);
        var onExpression = Assert.IsType<OnSubscriptionExpression>(onStatement.Expression);
        onFunction.Body.Statements[0] = onStatement with
        {
            Expression = onExpression with
            {
                Target = new ParenthesizedExpression(CreateSoaRowView("nodes"), Line: 6, Column: 16)
            }
        };

        var onResult = Analyze(onUnit, onSource);
        var onError = Assert.Single(onResult.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an event target", onError.Message);
        Assert.Contains("table[index].column", onError.Suggestion);

        var offSource = """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                off handle
            }
            """;
        var offUnit = ParseForAnalysis(offSource);
        var offFunction = Assert.IsType<FunctionDeclaration>(offUnit.Declarations[1]);
        var offStatement = Assert.IsType<OffStatement>(offFunction.Body!.Statements[0]);
        offFunction.Body.Statements[0] = offStatement with
        {
            Handle = new ParenthesizedExpression(CreateSoaRowView("nodes"), Line: 6, Column: 16)
        };

        var offResult = Analyze(offUnit, offSource);
        var offError = Assert.Single(offResult.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as an off handle", offError.Message);
        Assert.Contains("table[index].column", offError.Suggestion);

        var withSource = """
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
        var withUnit = ParseForAnalysis(withSource);
        var withFunction = Assert.IsType<FunctionDeclaration>(withUnit.Declarations[2]);
        var updated = Assert.IsType<VariableDeclarationStatement>(withFunction.Body!.Statements[1]);
        var with = Assert.IsType<WithExpression>(updated.Initializer);
        with.Properties.Clear();
        with.Properties.Add(new PropertyInitializer(
            null,
            new ParenthesizedExpression(CreateSoaRowView("nodes"), Line: 11, Column: 42),
            new IntLiteralExpression("1", Line: 11, Column: 42),
            NameLine: 11,
            NameColumn: 42));

        var withResult = Analyze(withUnit, withSource);
        var withError = Assert.Single(withResult.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a with initializer index", withError.Message);
        Assert.Contains("table[index].column", withError.Suggestion);
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
    public void Analyzer_SoaRowTypeCannotBeUsedAsParameterAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(row: NodeTable.Row): int {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsReturnAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): NodeTable.Row {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsLocalAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                row: NodeTable.Row = 0
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsFieldAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                row: NodeTable.Row
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsPropertyAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Row: NodeTable.Row => 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsTypeAlias()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            type NodeRow = NodeTable.Row
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeThroughTableAliasCannotBeUsedAsParameterAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(row: Nodes.Row): int {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'Nodes.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeThroughTableAliasCannotBeHiddenInsideComposedTypeReferences()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable
            type MaybeRow = Nodes.Row?
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable
            type RowTuple = (row: Nodes.Row, count: int)
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable
            type RowChoice = Nodes.Row | int
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable
            type RowFactory = Func<int, Nodes.Row>
            """,
            """
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(rowsByName: Dictionary<string, Nodes.Row[]>): int {
                return 0
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA row type 'Nodes.Row' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsArrayElementAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(rows: NodeTable.Row[]): int {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedAsGenericArgumentAnnotation()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(rows: List<NodeTable.Row>): int {
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeHiddenInsideComposedTypeReferences()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type MaybeRow = NodeTable.Row?
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type RowTuple = (row: NodeTable.Row, count: int)
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type RowChoice = NodeTable.Row | int
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type RowFactory = Func<int, NodeTable.Row>
            """,
            """
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(rowsByName: Dictionary<string, NodeTable.Row[]>): int {
                return 0
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA row type 'NodeTable.Row' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInTypeofExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): Type {
                return typeof(NodeTable.Row)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInTableTestCaseTypeofValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            test "bad table case" with (value: Type) [
                (typeof(NodeTable.Row))
            ] {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.ConstantRequired);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInAttributeTypeofArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
            class TypeMarkerAttribute: Attribute {
                constructor(valueType: Type) {
                }
            }

            soa record NodeTable {
                kind: int
            }

            [TypeMarker(typeof(NodeTable.Row))]
            class Holder {
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            class TypeMarkerAttribute: Attribute {
                constructor(valueType: Type) {
                }
            }

            soa record NodeTable {
                kind: int
            }

            func bad([TypeMarker(typeof(NodeTable.Row))] value: int): int {
                return value
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            class TypeMarkerAttribute: Attribute {
                constructor(valueType: Type) {
                }
            }

            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            [TypeMarker(typeof(Nodes.Row))]
            class Holder {
            }
            """, RowType: "Nodes.Row"),
            (Source: """
            class TypeMarkerAttribute: Attribute {
                constructor(valueType: Type) {
                }
            }

            soa record NodeTable {
                kind: int
            }

            [TypeMarker(typeof(Func<int, NodeTable.Row>))]
            class Holder {
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            class TypeMarkerAttribute: Attribute {
                constructor(valueType: Type) {
                }
            }

            soa record NodeTable {
                kind: int
            }

            test "bad table attribute" with ([TypeMarker(typeof(NodeTable.Row))] value: int) [
                (0)
            ] {
            }
            """, RowType: "NodeTable.Row")
        };

        foreach (var (source, rowType) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"SoA row type '{rowType}' is not part of this lowering", error.Message);
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInTableTestParameters()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
            soa record NodeTable {
                kind: int
            }

            test "bad row" with (row: NodeTable.Row) [
                (0)
            ] {
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            test "bad row" with (row: Nodes.Row) [
                (0)
            ] {
            }
            """, RowType: "Nodes.Row")
        };

        foreach (var (source, rowType) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains($"SoA row type '{rowType}' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInIndexerDeclarations()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (Source: """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                func this[row: NodeTable.Row]: int {
                    get {
                        return 0
                    }
                }
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            soa record NodeTable {
                kind: int
            }

            class Holder {
                func this[index: int]: NodeTable.Row {
                    get {
                        return 0
                    }
                }
            }
            """, RowType: "NodeTable.Row"),
            (Source: """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            class Holder {
                func this[index: int]: Nodes.Row {
                    get {
                        return 0
                    }
                }
            }
            """, RowType: "Nodes.Row")
        };

        foreach (var (source, rowType) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains($"SoA row type '{rowType}' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeThroughTableAliasCannotBeUsedInTypeExpressions()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): Type {
                return typeof(Nodes.Row)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(): int {
                return sizeof(Nodes.Row)
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA row type 'Nodes.Row' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInSizeofExpression()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                return sizeof(NodeTable.Row)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row type 'NodeTable.Row' is not part of this lowering", error.Message);
        Assert.Contains("table and an int row index", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRowTypeCannotBeUsedInDeclaredTypePositions()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad<T>(value: T): int where T : NodeTable.Row {
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Holder : NodeTable.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            class Base {
            }

            class Holder : Base, NodeTable.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            struct Holder : NodeTable.Row {
                value: int
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            record Holder : NodeTable.Row {
                value: int
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            interface IRow : NodeTable.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type RowConsumer = Func<NodeTable.Row, int>
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(value: object): int {
                if value is NodeTable.Row {
                    return 1
                }

                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(value: object): object {
                return (NodeTable.Row)value
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            func bad(value: object): object {
                return value as NodeTable.Row
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA row type 'NodeTable.Row' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaRowTypeThroughTableAliasCannotBeUsedInDeclaredTypePositions()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad<T>(value: T): int where T : Nodes.Row {
                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            class Holder : Nodes.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            class Base {
            }

            class Holder : Base, Nodes.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            struct Holder : Nodes.Row {
                value: int
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            record Holder : Nodes.Row {
                value: int
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            interface IRow : Nodes.Row {
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable
            type RowConsumer = Func<Nodes.Row, int>
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(value: object): int {
                if value is Nodes.Row {
                    return 1
                }

                return 0
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(value: object): object {
                return (Nodes.Row)value
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(value: object): object {
                return value as Nodes.Row
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(
                result.Errors,
                e => e.Code == ErrorCode.InvalidSyntax
                    && e.Message.Contains("SoA row type 'Nodes.Row' is not part of this lowering"));
            Assert.Contains("table and an int row index", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
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
    public void Analyzer_SoaRowViewCannotEscapeIntoCollectionLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            import System.Collections.Generic

            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                let values: List<object> = [nodes[0]]
                return values.Count
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a collection literal", error.Message);
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
    public void Analyzer_SoaRowViewCannotBeUsedAsForIterator()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                for i := 0; i < 1; nodes[0] {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used as a 'for' iterator", error.Message);
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
    public void Analyzer_SoaTableCannotUseNullConditionalMemberAccess()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes?.length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA tables cannot use null-conditional member access", error.Message);
        Assert.Contains("direct table.member access", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseNullConditionalRowProjection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                row := nodes?[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used with null-conditional indexing", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotUseNullConditionalColumnAccess()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                value := nodes[0]?.kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be used with null-conditional member access", error.Message);
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
    public void Analyzer_SoaTableCannotWriteThroughRangeRowIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0..1].kind = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("range", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseFromEndRowIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[^1].kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("System.Index", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotWriteThroughFromEndRowIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[^1].kind = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("System.Index", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseVariableFromEndRowIndex()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                idx := ^1
                return nodes[idx].kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains("System.Index", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Theory]
    [InlineData("idx := ^1", "nodes[idx].kind = 1", "System.Index")]
    [InlineData("range := 0..1", "value := nodes[range].kind", "range")]
    [InlineData("range := 0..1", "nodes[range].kind = 1", "range")]
    public void Analyzer_SoaTableVariableNonIntRowIndexesAreRejected(
        string declaration,
        string statement,
        string expectedTypeDescription)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table indexes must be int row ids", error.Message);
        Assert.Contains(expectedTypeDescription, error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Theory]
    [InlineData("", "bump(ref nodes[^1].kind)", "SoA table indexes must be int row ids", "System.Index", "table[index].column")]
    [InlineData("", "reset(out nodes[0..1].kind)", "SoA table indexes must be int row ids", "range", "table[index].column")]
    [InlineData("idx := ^1", "bump(ref nodes[idx].kind)", "SoA table indexes must be int row ids", "System.Index", "table[index].column")]
    [InlineData("", "bump(ref nodes[(short)0].kind)", "SoA table indexes must be int row ids", "'short'", "table[index].column")]
    [InlineData("", "reset(out nodes[-1].kind)", "SoA table row indexes must not be negative", null, "non-negative row id")]
    [InlineData("", "bump(ref nodes[checked(-1)].kind)", "SoA table row indexes must not be negative", null, "non-negative row id")]
    [InlineData("", "reset(out nodes[unchecked((-1))].kind)", "SoA table row indexes must not be negative", null, "non-negative row id")]
    [InlineData("", "bump(ref nodes[(short)-1].kind)", "SoA table row indexes must not be negative", null, "non-negative row id")]
    public void Analyzer_SoaTableRefOutRowIndexesAreRejectedBeforeEmission(
        string declaration,
        string statement,
        string expectedMessage,
        string? expectedTypeDescription,
        string expectedSuggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func bad(nodes: Nodes) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(expectedMessage, error.Message);
        if (expectedTypeDescription != null)
        {
            Assert.Contains(expectedTypeDescription, error.Message);
        }

        Assert.Contains(expectedSuggestion, error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableRowIndexCannotBeNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[-1].kind
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table row indexes must not be negative", error.Message);
        Assert.Contains("non-negative row id", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableRowWriteIndexCannotBeNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[-1].kind = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table row indexes must not be negative", error.Message);
        Assert.Contains("non-negative row id", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnElementIndexMustBeInt()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind["0"] = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Array indexes must be int, System.Index, or System.Range", error.Message);
        Assert.Contains("'string'", error.Message);
        Assert.Contains("^n", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnElementIndexCannotBeNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[-1] = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA column row indexes must not be negative", error.Message);
        Assert.Contains("non-negative row id", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnElementReadIndexCannotBeNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes.kind[-1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA column row indexes must not be negative", error.Message);
        Assert.Contains("non-negative row id", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableNegativeIndexLiteralsInCheckedAndUncheckedWrappersAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return nodes[checked(-1)].kind
                }
                """,
                Message: "SoA table row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes[unchecked((-1))].kind = 1
                }
                """,
                Message: "SoA table row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.kind[checked(-1)] = 1
                }
                """,
                Message: "SoA column row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return nodes.kind[unchecked((-1))]
                }
                """,
                Message: "SoA column row indexes must not be negative")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("non-negative row id", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableSmallSignedCastNegativeIndexesAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return nodes[(short)-1].kind
                }
                """,
                Message: "SoA table row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type SmallCount = short

                func bad(nodes: NodeTable) {
                    nodes[(SmallCount)-1].kind = 1
                }
                """,
                Message: "SoA table row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.kind[checked((short)-1)] = 1
                }
                """,
                Message: "SoA column row indexes must not be negative"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type SmallCount = sbyte

                func bad(nodes: NodeTable): int {
                    return nodes.kind[unchecked((SmallCount)-1)]
                }
                """,
                Message: "SoA column row indexes must not be negative")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains("non-negative row id", error.Suggestion);
            Assert.DoesNotContain("must be int row ids", error.Message);
        }
    }

    [Fact]
    public void Analyzer_SoaTableSmallIntegerRowIndexesStillRequireInt()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[(short)1].kind
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type SmallCount = short

            func bad(nodes: NodeTable) {
                nodes[(SmallCount)1].kind = 1
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains("SoA table indexes must be int row ids", error.Message);
            Assert.DoesNotContain("must not be negative", error.Message);
        }
    }

    [Fact]
    public void Analyzer_SoaTableNegativeZeroIndexesAreAllowed()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                nodes[-0x0].kind = 1
                nodes.kind[-00] = 2
                return nodes[0].kind
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableColumnSliceCannotBeAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[0..1] = [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableParenthesizedColumnRangeSliceCannotBeAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                (nodes.kind)[0..1] = [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCheckedAndUncheckedColumnMemberAccessKeepsDirectColumnDiagnostics()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return (checked(nodes.kind))[-1]
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    range := 0..1
                    bump(ref (checked(nodes.kind))[range])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    range := 0..1
                    reset(out (unchecked(nodes.kind))[range])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref (checked(nodes.kind))["0"])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "Array indexes must be int, System.Index, or System.Range",
                Suggestion: "^n"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    idx := "0"
                    reset(out (unchecked(nodes.kind))[idx])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "Array indexes must be int, System.Index, or System.Range",
                Suggestion: "^n"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out (nodes.kind)[-1])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref (nodes.kind)[checked(-1)])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref (nodes.kind)[(short)-1])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return (unchecked(nodes.kind))["0"]
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "Array indexes must be int, System.Index, or System.Range",
                Suggestion: "^n"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (checked(nodes.kind))["0"] = 1
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "Array indexes must be int, System.Index, or System.Range",
                Suggestion: "^n"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    idx := "0"
                    return (checked(nodes.kind))[idx]
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "Array indexes must be int, System.Index, or System.Range",
                Suggestion: "^n"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    values := (checked(nodes.kind))[0..1]
                    return values.Length
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    (unchecked(nodes.kind))[0..1] = [1]
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == testCase.Code);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnRefOutIndexesAreRejectedBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref nodes.kind[0..1])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref checked(nodes.kind[0..1]))
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out unchecked((nodes.kind)[0..1]))
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    range := 0..1
                    reset(out nodes.kind[range])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref (nodes.kind)[0..1])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref (checked(nodes.kind))[0..1])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref nodes.kind[1..^1])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out (nodes.kind)[1..^1])
                }
                """,
                Code: ErrorCode.InvalidSyntax,
                Message: "SoA column range slices allocate arrays",
                Suggestion: "table.column[row]"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out nodes.kind[-1])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref nodes.kind[checked(-1)])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out nodes.kind[unchecked((-1))])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref nodes.kind[(short)-1])
                }
                """,
                Code: ErrorCode.TypeMismatch,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "non-negative row id")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == testCase.Code);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaRefOutCheckedAndUncheckedWholeArgumentsRejectBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref checked(nodes.kind[0]))
                }
                """,
                Modifier: "ref"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func reset(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    reset(out unchecked((nodes[0]).kind))
                }
                """,
                Modifier: "out"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bump(ref value: int) {
                    value += 1
                }

                func bad(nodes: Nodes) {
                    bump(ref checked((nodes.kind)[0]))
                }
                """,
                Modifier: "ref")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"'{testCase.Modifier}' argument needs an assignable target", error.Message);
            Assert.Contains($"as the {testCase.Modifier} argument", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectMembersCannotBeRefOutArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func replace(ref values: int[]) {
                }

                func bad(nodes: Nodes) {
                    replace(ref nodes.kind)
                }
                """,
                Member: "kind",
                Modifier: "ref",
                Suggestion: "construct/wrap"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func set(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    set(out nodes.length)
                }
                """,
                Member: "length",
                Modifier: "out",
                Suggestion: "add, clear, ensureCapacity, or copyRow"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func replace(ref values: int[]) {
                }

                func bad(nodes: Nodes) {
                    replace(ref checked(nodes.kind))
                }
                """,
                Member: "kind",
                Modifier: "ref",
                Suggestion: "construct/wrap"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func set(out value: int) {
                    value = 0
                }

                func bad(nodes: Nodes) {
                    set(out unchecked(nodes.capacity))
                }
                """,
                Member: "capacity",
                Modifier: "out",
                Suggestion: "add, clear, ensureCapacity, or copyRow")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"SoA table member '{testCase.Member}' cannot be used as the {testCase.Modifier} argument", error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnsCannotUseArrayInstanceMethods()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.kind.SetValue(1, 0)
                }
                """,
                Method: "SetValue"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    value := (nodes.kind).GetValue(0)
                }
                """,
                Method: "GetValue"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    clone := checked(nodes.kind).Clone()
                }
                """,
                Method: "Clone"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, dst: int[]) {
                    unchecked((nodes).kind).CopyTo(dst, 0)
                }
                """,
                Method: "CopyTo"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    iterator := nodes.kind.GetEnumerator()
                }
                """,
                Method: "GetEnumerator"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    unchecked(nodes.kind).Initialize()
                }
                """,
                Method: "Initialize"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): string {
                    return nodes.kind.ToString()
                }
                """,
                Method: "ToString"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return (nodes.kind).GetLength(0)
                }
                """,
                Method: "GetLength")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"SoA table member 'kind' cannot call array method '{testCase.Method}' directly", error.Message);
            Assert.Contains("Array.Fill, Array.Copy, and Array.Clear", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnArrayInstanceMethodsCannotBeUsedAsValues()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    let clone: Func<object> = nodes.kind.Clone
                }
                """,
                Method: "Clone"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    let clone: Func<object> = checked(nodes.kind).Clone
                }
                """,
                Method: "Clone"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func pull(getLength: Func<int, int>): int {
                    return getLength(0)
                }

                func bad(nodes: Nodes): int {
                    return pull((nodes.kind).GetLength)
                }
                """,
                Method: "GetLength"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    copy := unchecked((nodes).kind).CopyTo
                }
                """,
                Method: "CopyTo")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"SoA table member 'kind' cannot use array method '{testCase.Method}' as a value", error.Message);
            Assert.Contains("Array.Fill, Array.Copy, and Array.Clear", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnMetadataPropertiesCannotBeAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.kind.Length = 1
                }
                """,
                Property: "Length",
                Operator: "="),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    (nodes.kind).LongLength += 1L
                }
                """,
                Property: "LongLength",
                Operator: "+="),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.kind.Rank++
                }
                """,
                Property: "Rank",
                Operator: "++"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    checked(nodes.kind).Length = 1
                }
                """,
                Property: "Length",
                Operator: "="),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    unchecked((nodes.kind)).LongLength += 1L
                }
                """,
                Property: "LongLength",
                Operator: "+="),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    checked(nodes.kind).Rank++
                }
                """,
                Property: "Rank",
                Operator: "++")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"Property '{testCase.Property}' is read-only", error.Message);
            Assert.Contains($"'{testCase.Operator}'", error.Message);
            Assert.Contains("settable property", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnsCannotUseUnpinnedStaticArrayMethods()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return Array.IndexOf(nodes.kind, 2)
                }
                """,
                Method: "IndexOf"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return Array.IndexOf(value: 2, array: nodes.kind)
                }
                """,
                Method: "IndexOf"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return System.Array.IndexOf<int>(array: checked(nodes.kind), value: 2)
                }
                """,
                Method: "IndexOf"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return System.Array.BinarySearch((nodes).kind, 2)
                }
                """,
                Method: "BinarySearch"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return Array.BinarySearch<int>(array: unchecked((nodes).kind), value: 2)
                }
                """,
                Method: "BinarySearch"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, source: int[]) {
                    Array.ConstrainedCopy(source, 0, nodes.kind, 0, 1)
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, source: int[]) {
                    Array.ConstrainedCopy(length: 1, destinationIndex: 0, destinationArray: nodes.kind, sourceIndex: 0, sourceArray: source)
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, source: int[]) {
                    Array.ConstrainedCopy(length: 1, destinationIndex: 0, destinationArray: checked(nodes.kind), sourceIndex: 0, sourceArray: source)
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, target: int[]) {
                    Array.ConstrainedCopy(nodes.kind, 0, target, 0, 1)
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, target: int[]) {
                    System.Array.ConstrainedCopy(length: 1, destinationIndex: 0, destinationArray: target, sourceIndex: 0, sourceArray: nodes.kind)
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes, target: int[]) {
                    System.Array.ConstrainedCopy(length: 1, destinationIndex: 0, destinationArray: target, sourceIndex: 0, sourceArray: unchecked(nodes.kind))
                }
                """,
                Method: "ConstrainedCopy"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): bool {
                    return Array.Exists(checked(nodes.kind), value => value == 2)
                }
                """,
                Method: "Exists"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): object {
                    return Array.AsReadOnly(unchecked((nodes).kind))
                }
                """,
                Method: "AsReadOnly"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): object {
                    return Array.AsReadOnly(array: nodes.kind)
                }
                """,
                Method: "AsReadOnly"),
            (
                Source: """
                import System

                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): object {
                    return Array.AsReadOnly(array: unchecked(nodes.kind))
                }
                """,
                Method: "AsReadOnly")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains($"SoA table member 'kind' cannot be passed to Array method '{testCase.Method}' directly", error.Message);
            Assert.Contains("Array.Fill, Array.Copy, and Array.Clear", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnsCannotBeResizedThroughArrayResize()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(ref nodes.kind, 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(ref array: nodes.kind, newSize: 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(ref (nodes.kind), 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(ref checked(nodes.kind), 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(ref unchecked(nodes.kind), 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Resize(ref nodes.kind, 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize<int>(ref nodes.kind, 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Resize<int>(ref (nodes).kind, 4)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Resize<int>(newSize: 4, ref array: (nodes).kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Resize(newSize: 4, ref array: checked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Resize<int>(newSize: 4, ref array: unchecked((nodes).kind))
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA table member 'kind' cannot be used as the ref argument", error.Message);
            Assert.Contains("construct/wrap", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnsCannotBeSortedThroughArraySort()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort((nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(checked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(unchecked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(nodes.kind, 0, 1)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(index: 0, length: 1, array: nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort(index: 0, length: 1, array: checked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Sort(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, keys: int[]) {
                Array.Sort(keys, nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, keys: int[]) {
                Array.Sort(keys, (nodes.kind), 0, 1)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, keys: int[]) {
                System.Array.Sort<int, int>(keys, (nodes).kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, keys: int[]) {
                Array.Sort<int, int>(index: 0, length: 1, keys: keys, items: nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, keys: int[]) {
                Array.Sort<int, int>(index: 0, length: 1, keys: keys, items: unchecked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, items: int[]) {
                Array.Sort<int, int>(index: 0, length: 1, keys: nodes.kind, items: items)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, items: int[]) {
                Array.Sort<int, int>(index: 0, length: 1, keys: checked(nodes.kind), items: items)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes, items: int[]) {
                System.Array.Sort<int, int>(length: 1, items: items, index: 0, keys: (nodes).kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Sort<int>(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Sort<int>((nodes).kind)
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA table member 'kind' cannot be sorted directly", error.Message);
            Assert.Contains("construct/wrap", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaDirectColumnsCannotBeReversedThroughArrayReverse()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse((nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(checked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(unchecked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(nodes.kind, 0, 1)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(index: 0, length: 1, array: nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse(index: 0, length: 1, array: checked(nodes.kind))
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Reverse(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                Array.Reverse<int>(nodes.kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Reverse<int>((nodes).kind)
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                System.Array.Reverse<int>(array: unchecked((nodes).kind))
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA table member 'kind' cannot be reversed directly", error.Message);
            Assert.Contains("construct/wrap", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeSliceCannotBeAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[1..^1] = [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeSliceCannotBeCompoundAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[1..^1] += [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnSliceCannotBeCompoundAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[0..1] += [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnSliceCannotBeNullCoalescingAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[0..1] ??= [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeSliceCannotBeNullCoalescingAssigned()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[1..^1] ??= [1]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnSliceCannotBeIncremented()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[0..1]++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnSliceCannotBeDecremented()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[0..1]--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeSliceCannotBeIncremented()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[1..^1]++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeSliceCannotBeDecremented()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[1..^1]--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnRangeReadWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                slice := nodes.kind[0..1]
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableParenthesizedColumnRangeReadWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                slice := (nodes.kind)[0..1]
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("table.column[row]", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnFromEndRangeReadWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                slice := nodes.kind[1..^1]
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnRangeValueReadWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                range := 0..1
                slice := nodes.kind[range]
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Theory]
    [InlineData("nodes.kind[range] = [1]")]
    [InlineData("nodes.kind[range] += [1]")]
    [InlineData("nodes.kind[range] ??= [1]")]
    [InlineData("nodes.kind[range]++")]
    [InlineData("nodes.kind[range]--")]
    public void Analyzer_SoaTableColumnRangeValueMutationWouldAllocate(string statement)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                range := 0..1;
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableParenthesizedColumnRangeValueReadWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                range := 0..1;
                slice := (nodes.kind)[range]
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Theory]
    [InlineData("slice := (checked(nodes.kind))[range]")]
    [InlineData("slice := (unchecked(nodes.kind))[range]")]
    public void Analyzer_SoaTableCheckedAndUncheckedColumnRangeValueReadWouldAllocate(string statement)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                range := 0..1;
                {{statement}}
                return slice[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Theory]
    [InlineData("(nodes.kind)[range] = [1]")]
    [InlineData("(nodes.kind)[range] += [1]")]
    [InlineData("(nodes.kind)[range] ??= [1]")]
    [InlineData("(nodes.kind)[range]++")]
    [InlineData("(nodes.kind)[range]--")]
    public void Analyzer_SoaTableParenthesizedColumnRangeValueMutationWouldAllocate(string statement)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                range := 0..1;
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
    }

    [Theory]
    [InlineData("checked(nodes.kind[range]) = [1]")]
    [InlineData("unchecked((nodes.kind[range])) += [1]")]
    [InlineData("checked(nodes.kind[range])++")]
    [InlineData("unchecked((nodes.kind[range]))--")]
    [InlineData("(checked(nodes.kind))[range] = [1]")]
    [InlineData("(unchecked(nodes.kind))[range] += [1]")]
    [InlineData("((checked(nodes.kind))[range])++")]
    [InlineData("((unchecked(nodes.kind))[range])--")]
    public void Analyzer_SoaTableCheckedAndUncheckedColumnRangeValueMutationWouldAllocate(string statement)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                range := 0..1;
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA column range slices allocate arrays", error.Message);
        Assert.Contains("allocation-free view lowering", error.Suggestion);
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

    [Theory]
    [InlineData("NodeTable", "", "kind", "new int[](1)", "kind", "table[index].column")]
    [InlineData("NodeTable", "", "length", "1", "length", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("Nodes", "type Nodes = NodeTable", "capacity", "1", "capacity", "add, clear, ensureCapacity, or copyRow")]
    public void Analyzer_SoaTableWithExpressionCannotInitializeGeneratedMembers(
        string tableTypeName,
        string aliasDeclaration,
        string initializerMember,
        string initializerValue,
        string expectedMember,
        string expectedSuggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            {{aliasDeclaration}}

            func bad(nodes: {{tableTypeName}}): {{tableTypeName}} {
                return nodes with { {{initializerMember}}: {{initializerValue}} }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table member '{expectedMember}' cannot be initialized directly", error.Message);
        Assert.Contains(expectedSuggestion, error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_SoaTableWithExpressionReportsUnknownMembersBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): NodeTable {
                return nodes with { missing: 1 }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
        Assert.Contains("Member 'missing' not found on type 'NodeTable'", error.Message);
    }

    [Theory]
    [InlineData("NodeTable", "", false, "collection initializer entries")]
    [InlineData("NodeTable", "", true, "indexer initializers")]
    [InlineData("Nodes", "type Nodes = NodeTable", false, "collection initializer entries")]
    [InlineData("Nodes", "type Nodes = NodeTable", true, "indexer initializers")]
    public void Analyzer_SoaTableWithExpressionRejectsAstCollectionAndIndexerEntriesBeforeEmission(
        string tableTypeName,
        string aliasDeclaration,
        bool indexerInitializer,
        string expectedShape)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = $$"""
            soa record NodeTable {
                kind: int
            }

            {{aliasDeclaration}}

            func bad(nodes: {{tableTypeName}}): {{tableTypeName}} {
                return nodes with { kind: new int[](1) }
            }
            """;
        var unit = ParseForAnalysis(source);
        var function = Assert.IsType<FunctionDeclaration>(unit.Declarations[^1]);
        var returnStatement = Assert.IsType<ReturnStatement>(function.Body!.Statements[0]);
        var with = Assert.IsType<WithExpression>(returnStatement.Value);
        with.Properties.Clear();
        with.Properties.Add(indexerInitializer
            ? new PropertyInitializer(
                null,
                new IntLiteralExpression("0", Line: 7, Column: 37),
                new IntLiteralExpression("1", Line: 7, Column: 42),
                NameLine: 7,
                NameColumn: 37)
            : new PropertyInitializer(
                null,
                null,
                new IntLiteralExpression("1", Line: 7, Column: 37),
                NameLine: 7,
                NameColumn: 37));

        var result = Analyze(unit, source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA tables cannot use `with` {expectedShape}", error.Message);
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
    public void Analyzer_SoaRowViewCannotBeAssignmentTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0] = 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be assigned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeCompoundAssignmentTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0] += 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be assigned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeNullCoalescingAssignmentTarget()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0] ??= null
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be assigned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeIncrementedOrDecremented()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes[0]++
                nodes[0]--
            }
            """);

        var errors = result.Errors.Where(e => e.Code == ErrorCode.InvalidSyntax).ToArray();
        Assert.Equal(2, errors.Length);
        Assert.All(errors, error =>
        {
            Assert.Contains("SoA row views cannot be used as a unary operand", error.Message);
            Assert.Contains("table[index].column", error.Suggestion);
        });
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

    [Theory]
    [InlineData("NodeTable", "", "kind", "new int[](1)", "kind", "table[index].column")]
    [InlineData("NodeTable", "", "length", "1", "length", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("Nodes", "type Nodes = NodeTable", "capacity", "1", "capacity", "add, clear, ensureCapacity, or copyRow")]
    public void Analyzer_SoaTableObjectInitializerCannotInitializeGeneratedMembers(
        string tableTypeName,
        string aliasDeclaration,
        string initializerMember,
        string initializerValue,
        string expectedMember,
        string expectedSuggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            {{aliasDeclaration}}

            func bad(): {{tableTypeName}} {
                return new {{tableTypeName}}(1) { {{initializerMember}}: {{initializerValue}} }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table member '{expectedMember}' cannot be initialized directly", error.Message);
        Assert.Contains(expectedSuggestion, error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_SoaTableObjectInitializerReportsUnknownMembersBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable {
                return new NodeTable(1) { missing: 1 }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
        Assert.Contains("Member 'missing' not found on type 'NodeTable'", error.Message);
    }

    [Theory]
    [InlineData("", "NodeTable", "new NodeTable(1)")]
    [InlineData("type Nodes = NodeTable", "Nodes", "new Nodes(1)")]
    [InlineData("", "NodeTable", "new(1)")]
    [InlineData("type Nodes = NodeTable", "Nodes", "new(1)")]
    public void Analyzer_SoaTableObjectInitializerRejectsIndexerEntriesBeforeEmission(
        string aliasDeclaration,
        string returnTypeName,
        string construction)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            {{aliasDeclaration}}

            func bad(): {{returnTypeName}} {
                return {{construction}} { [0] = 1 }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA tables cannot use object-initializer indexer initializers", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableObjectInitializerRejectsAstCollectionEntriesBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func bad(): NodeTable {
                return new NodeTable(1) { kind: new int[](1) }
            }
            """;
        var unit = ParseForAnalysis(source);
        var function = Assert.IsType<FunctionDeclaration>(unit.Declarations[1]);
        var returnStatement = Assert.IsType<ReturnStatement>(function.Body!.Statements[0]);
        var newExpr = Assert.IsType<NewExpression>(returnStatement.Value);
        Assert.NotNull(newExpr.Initializer);
        var initializer = newExpr.Initializer!;
        initializer.Properties.Clear();
        initializer.Properties.Add(new PropertyInitializer(
            null,
            null,
            new IntLiteralExpression("1", Line: 7, Column: 43),
            NameLine: 7,
            NameColumn: 43));

        var result = Analyze(unit, source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA tables cannot use object-initializer collection initializer entries", error.Message);
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
    public void Analyzer_SoaTableColumnArrayCannotBeCompoundAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind += new int[](1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'kind' cannot be assigned directly", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnArrayCannotBeNullCoalescingAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind ??= new int[](1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'kind' cannot be assigned directly", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnArrayCannotBeIncrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'kind' cannot be incremented or decremented directly", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableColumnArrayCannotBeDecrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'kind' cannot be incremented or decremented directly", error.Message);
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
    public void Analyzer_SoaTableCapacityCannotBeAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.capacity = 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'capacity' cannot be assigned directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableLengthCannotBeNullCoalescingAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.length ??= 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'length' cannot be assigned directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityCannotBeNullCoalescingAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.capacity ??= 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'capacity' cannot be assigned directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableLengthCannotBeCompoundAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.length += 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'length' cannot be assigned directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityCannotBeCompoundAssignedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.capacity += 1
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'capacity' cannot be assigned directly", error.Message);
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
    public void Analyzer_SoaTableLengthCannotBeDecrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.length--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'length' cannot be incremented or decremented directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityCannotBeIncrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.capacity++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'capacity' cannot be incremented or decremented directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityCannotBeDecrementedDirectly()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.capacity--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table member 'capacity' cannot be incremented or decremented directly", error.Message);
        Assert.Contains("add, clear, ensureCapacity, or copyRow", error.Suggestion);
    }

    [Theory]
    [InlineData("((nodes.kind)) = new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("((nodes.kind)) += new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("((nodes.kind)) ??= new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("++((nodes.kind))", "kind", "incremented or decremented directly", "table[index].column")]
    [InlineData("--((nodes.kind))", "kind", "incremented or decremented directly", "table[index].column")]
    [InlineData("((nodes.length)) = 0", "length", "assigned directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("((nodes.capacity)) += 1", "capacity", "assigned directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("((nodes.length)) ??= 0", "length", "assigned directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("++((nodes.capacity))", "capacity", "incremented or decremented directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("--((nodes.length))", "length", "incremented or decremented directly", "add, clear, ensureCapacity, or copyRow")]
    public void Analyzer_SoaTableParenthesizedDirectMemberMutationsAreRejected(
        string statement,
        string member,
        string action,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table member '{member}' cannot be {action}", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Theory]
    [InlineData("checked(nodes.kind) = new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("unchecked((nodes.kind)) += new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("checked(nodes.length) ??= 0", "length", "assigned directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("++checked(nodes.capacity)", "capacity", "incremented or decremented directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("--unchecked((nodes.length))", "length", "incremented or decremented directly", "add, clear, ensureCapacity, or copyRow")]
    public void Analyzer_SoaTableCheckedAndUncheckedDirectMemberMutationsAreRejected(
        string statement,
        string member,
        string action,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table member '{member}' cannot be {action}", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRequiresOneArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable()
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("expects exactly one int capacity argument", error.Message);
        Assert.Contains("new NodeTable(capacity)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRejectsExtraArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable(1, 2)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("expects exactly one int capacity argument", error.Message);
        Assert.Contains("but 2 were provided", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRequiresInt()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable("4")
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table capacity must be int", error.Message);
        Assert.Contains("'string'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorAllowsImplicitSmallIntegerCapacity()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func ok(): int {
                nodes := new NodeTable((short)4)
                return nodes.capacity
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRejectsUnknownNamedArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable(size: 4)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("has no parameter named 'size'", error.Message);
        Assert.Contains("capacity", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRejectsNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable(-1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table capacity must not be negative", error.Message);
        Assert.Contains("zero or a positive capacity", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorRejectsSmallSignedCastNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := new NodeTable((short)-1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table capacity must not be negative", error.Message);
        Assert.Contains("zero or a positive capacity", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCapacityConstructorAllowsNegativeZeroLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(): int {
                nodes := new NodeTable(-0x0)
                return nodes.capacity
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableAddRejectsArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                row := nodes.add(1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.WrongArgumentCount);
        Assert.Contains("'add' takes 0 argument(s), but you passed 1", error.Message);
        Assert.Contains("argument count", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableEnsureCapacityRequiresInt()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.ensureCapacity("4")
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 1 to 'ensureCapacity' is 'string'", error.Message);
        Assert.Contains("expects 'int'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableEnsureCapacityNamedArgumentTypeUsesParameterBinding()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.ensureCapacity(capacity: "4")
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 'capacity' to 'ensureCapacity' is 'string'", error.Message);
        Assert.Contains("expects 'int'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableEnsureCapacityRejectsNegativeLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.ensureCapacity(-1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table capacity must not be negative", error.Message);
        Assert.Contains("ensureCapacity expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableEnsureCapacityRejectsNegativeNamedLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.ensureCapacity(capacity: -1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table capacity must not be negative", error.Message);
        Assert.Contains("ensureCapacity expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRequiresTwoArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.WrongArgumentCount);
        Assert.Contains("'copyRow' takes 2 argument(s), but you passed 1", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRequiresIntArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(0, "1")
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 2 to 'copyRow' is 'string'", error.Message);
        Assert.Contains("expects 'int'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableGeneratedOperationsAllowDeclaredNamedArguments()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func ok(nodes: NodeTable) {
                nodes.ensureCapacity(capacity: 2)
                nodes.copyRow(to: 1, from: 0)
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Theory]
    [InlineData("op := nodes.add", "add", "nodes.add()")]
    [InlineData("op := nodes.clear", "clear", "nodes.clear()")]
    [InlineData("op := nodes.ensureCapacity", "ensureCapacity", "nodes.ensureCapacity(...)")]
    [InlineData("op := nodes.copyRow", "copyRow", "nodes.copyRow(...)")]
    [InlineData("let op: Func<int> = nodes.add", "add", "nodes.add()")]
    [InlineData("let op: Action = nodes.clear", "clear", "nodes.clear()")]
    [InlineData("pull(nodes.add)", "add", "nodes.add()")]
    public void Analyzer_SoaTableGeneratedOperationsCannotBeUsedAsValues(
        string statement,
        string operation,
        string expectedCall)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func pull(p: Func<int>): int {
                return p()
            }

            func bad(nodes: Nodes) {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table generated operation '{operation}' cannot be used as a value", error.Message);
        Assert.Contains(expectedCall, error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapCannotBeUsedAsValue()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                let wrap: Func<int[], int, Nodes> = Nodes.wrap
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA table generated operation 'wrap' cannot be used as a value", error.Message);
        Assert.Contains("Nodes.wrap(...)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowNamedArgumentTypeUsesParameterBinding()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(to: "1", from: 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 'to' to 'copyRow' is 'string'", error.Message);
        Assert.Contains("expects 'int'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRejectsUnknownNamedArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(source: 0, to: 1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("'copyRow' has no parameter named 'source'", error.Message);
        Assert.Contains("copyRow(from, to)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRejectsDuplicateNamedArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(from: 0, from: 1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
        Assert.Contains("'copyRow' got multiple values for parameter 'from'", error.Message);
        Assert.Contains("copyRow(from, to)", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRejectsNegativeSourceLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(-1, 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table source row id must not be negative", error.Message);
        Assert.Contains("copyRow expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRejectsNegativeTargetLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(0, -1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table target row id must not be negative", error.Message);
        Assert.Contains("copyRow expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCopyRowRejectsNegativeNamedTargetLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.copyRow(to: -1, from: 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table target row id must not be negative", error.Message);
        Assert.Contains("copyRow expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsNegativeLengthLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                kinds := new int[](2)
                nodes := NodeTable.wrap(kinds, -1)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap length must not be negative", error.Message);
        Assert.Contains("wrap expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsNegativeNamedLengthLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                kinds := new int[](2)
                nodes := NodeTable.wrap(length: -1, kind: kinds)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap length must not be negative", error.Message);
        Assert.Contains("wrap expects a non-negative int argument", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableNegativeLiteralsInCheckedAndUncheckedWrappersAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := new NodeTable(checked(-1))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "zero or a positive capacity"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := new NodeTable(unchecked((-1)))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "zero or a positive capacity"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity(checked(-1))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(checked(-1), 0)
                }
                """,
                Message: "SoA table source row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(0, unchecked((-1)))
                }
                """,
                Message: "SoA table target row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(kinds, checked(-1))
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(length: unchecked((-1)), kind: kinds)
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableNegativeLiteralsInSignedIntegerCastsAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := new NodeTable((int)-1)
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "zero or a positive capacity"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity(checked((int)-1))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow((int)-1, 0)
                }
                """,
                Message: "SoA table source row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(0, unchecked((int)-1))
                }
                """,
                Message: "SoA table target row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(kinds, (int)-1)
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return nodes[(int)-1].kind
                }
                """,
                Message: "SoA table row indexes must not be negative",
                Suggestion: "Use zero or a valid non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.kind[checked((int)-1)] = 1
                }
                """,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "Use zero or a valid non-negative row id")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableGeneratedOperationSmallSignedCastNegativesAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity((short)-1)
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity(capacity: unchecked((sbyte)-1))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type SmallCount = short

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity((SmallCount)-1)
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(from: checked((short)-1), to: 0)
                }
                """,
                Message: "SoA table source row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(0, to: (sbyte)-1)
                }
                """,
                Message: "SoA table target row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(kinds, (short)-1)
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(length: unchecked((sbyte)-1), kind: kinds)
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableNegativeLiteralsWithParenthesizedOperandsAreRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := new NodeTable(-(1))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "zero or a positive capacity"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.ensureCapacity(checked(-(1)))
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(-(1), 0)
                }
                """,
                Message: "SoA table source row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.copyRow(0, unchecked(-(1)))
                }
                """,
                Message: "SoA table target row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(kinds, -(1))
                }
                """,
                Message: "SoA table wrap length must not be negative",
                Suggestion: "wrap expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable): int {
                    return nodes[-(1)].kind
                }
                """,
                Message: "SoA table row indexes must not be negative",
                Suggestion: "Use zero or a valid non-negative row id"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad(nodes: NodeTable) {
                    nodes.kind[checked(-(1))] = 1
                }
                """,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "Use zero or a valid non-negative row id")
        };

        foreach (var testCase in cases)
        {
            var result = Analyze(testCase.Source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(testCase.Message, error.Message);
            Assert.Contains(testCase.Suggestion, error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableWrapNamedArgumentTypeUsesParameterBinding()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := NodeTable.wrap(length: 1, kind: 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 'kind' to 'wrap' is 'int'", error.Message);
        Assert.Contains("expects 'int[]'", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsNullColumnLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := NodeTable.wrap(null, 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap column 'kind' cannot be null", error.Message);
        Assert.Contains("backing 'kind' column array", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsDefaultColumnLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := NodeTable.wrap(default, 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap column 'kind' cannot be null", error.Message);
        Assert.Contains("backing 'kind' column array", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsNullNamedColumnLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                name: string
            }

            func bad() {
                kinds := new int[](2)
                nodes := NodeTable.wrap(name: null, kind: kinds, length: 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap column 'name' cannot be null", error.Message);
        Assert.Contains("backing 'name' column array", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsDefaultNamedColumnLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                name: string
            }

            func bad() {
                nodes := NodeTable.wrap(name: default, kind: new(), length: 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("SoA table wrap column 'name' cannot be null", error.Message);
        Assert.Contains("backing 'name' column array", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsParenthesizedNullAndDefaultColumnLiterals()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap((null), 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap(((default)), 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(name: (null), kind: kinds, length: 0)
                }
                """,
                Column: "name"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    nodes := NodeTable.wrap(name: ((default)), kind: new(), length: 0)
                }
                """,
                Column: "name")
        };

        foreach (var (source, column) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains($"SoA table wrap column '{column}' cannot be null", error.Message);
            Assert.Contains($"backing '{column}' column array", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsCheckedAndUncheckedDefaultColumnLiterals()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap(checked(default), 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap(unchecked((default)), 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(name: checked((default)), kind: kinds, length: 0)
                }
                """,
                Column: "name"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    nodes := NodeTable.wrap(name: unchecked(default), kind: new(), length: 0)
                }
                """,
                Column: "name")
        };

        foreach (var (source, column) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains($"SoA table wrap column '{column}' cannot be null", error.Message);
            Assert.Contains($"backing '{column}' column array", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableWrapRejectsCastedNullAndDefaultColumnLiterals()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap((int[])null, 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                func bad() {
                    nodes := NodeTable.wrap((int[])default, 0)
                }
                """,
                Column: "kind"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    kinds := new int[](2)
                    nodes := NodeTable.wrap(name: (string[])null, kind: kinds, length: 0)
                }
                """,
                Column: "name"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                    name: string
                }

                func bad() {
                    nodes := NodeTable.wrap(name: unchecked((string[])default), kind: new(), length: 0)
                }
                """,
                Column: "name")
        };

        foreach (var (source, column) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains($"SoA table wrap column '{column}' cannot be null", error.Message);
            Assert.Contains($"backing '{column}' column array", error.Suggestion);
        }
    }

    [Fact]
    public void Analyzer_SoaTableWrapCastedNonArrayDefaultKeepsArgumentTypeDiagnostic()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad() {
                nodes := NodeTable.wrap((int)default, 0)
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Argument 1 to 'wrap' is 'int'", error.Message);
        Assert.DoesNotContain("cannot be null", error.Message);
    }

    [Fact]
    public void Analyzer_SoaTableWrapNamedTargetTypedNewUsesBoundExpectedType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                name: string
            }

            func ok() {
                nodes := NodeTable.wrap(name: new(), kind: new(), length: 0)
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableAliasWrapRejectsInvalidArgumentsBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new (string Source, string Message, string? Suggestion)[]
        {
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                nodes := Nodes.wrap(null, 0)
            }
            """, "SoA table wrap column 'kind' cannot be null", "backing 'kind' column array"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                nodes := Nodes.wrap(default, 0)
            }
            """, "SoA table wrap column 'kind' cannot be null", "backing 'kind' column array"),
            ("""
            soa record NodeTable {
                kind: int
                name: string
            }

            type Nodes = NodeTable

            func bad() {
                kinds := new int[](2)
                nodes := Nodes.wrap(name: null, kind: kinds, length: 0)
            }
            """, "SoA table wrap column 'name' cannot be null", "backing 'name' column array"),
            ("""
            soa record NodeTable {
                kind: int
                name: string
            }

            type Nodes = NodeTable

            func bad() {
                kinds := new int[](2)
                nodes := Nodes.wrap(name: checked((default)), kind: kinds, length: 0)
            }
            """, "SoA table wrap column 'name' cannot be null", "backing 'name' column array"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                nodes := Nodes.wrap(length: 1, kind: 0)
            }
            """, "Argument 'kind' to 'wrap' is 'int'", null),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                kinds := new int[](2)
                nodes := Nodes.wrap(kinds, (short)-1)
            }
            """, "SoA table wrap length must not be negative", "wrap expects a non-negative int argument"),
            ("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad() {
                kinds := new int[](2)
                nodes := Nodes.wrap(length: unchecked((sbyte)-1), kind: kinds)
            }
            """, "SoA table wrap length must not be negative", "wrap expects a non-negative int argument")
        };

        foreach (var (source, message, suggestion) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(message, error.Message);
            if (suggestion != null)
                Assert.Contains(suggestion, error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        }
    }

    [Fact]
    public void Analyzer_SoaTableAliasWrapNamedTargetTypedNewUsesBoundExpectedType()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                name: string
            }

            type Nodes = NodeTable

            func ok() {
                nodes := Nodes.wrap(name: new(), kind: new(), length: 0)
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableAliasTypesGeneratedMembersAndRowProjection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func ok(nodes: Nodes): int {
                nodes.ensureCapacity(2)
                row := nodes.add()
                nodes[row].kind = 4
                nodes.kind[row] = nodes[row].kind + nodes.length + nodes.capacity
                nodes.copyRow(row, row)
                view := Nodes.wrap(kind: nodes.kind, length: nodes.length)
                return view[row].kind
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaTableAliasGeneratedOperationsKeepSpecificDiagnostics()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.ensureCapacity((short)-1)
                }
                """,
                Message: "SoA table capacity must not be negative",
                Suggestion: "ensureCapacity expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.copyRow(from: (sbyte)-1, to: 0)
                }
                """,
                Message: "SoA table source row id must not be negative",
                Suggestion: "copyRow expects a non-negative int argument"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return nodes[(short)0].kind
                }
                """,
                Message: "SoA table indexes must be int row ids, but this index has type 'short'",
                Suggestion: "Use an int row index and read or write a column with table[index].column"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    nodes.kind[(sbyte)-1] = 1
                }
                """,
                Message: "SoA column row indexes must not be negative",
                Suggestion: "Use zero or a valid non-negative row id")
        };

        foreach (var (source, message, suggestion) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
            Assert.Contains(message, error.Message);
            Assert.Contains(suggestion, error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
        }
    }

    [Fact]
    public void Analyzer_SoaTableAliasRejectsNullConditionalAccessBeforeEmission()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return nodes?.length
                }
                """,
                Message: "SoA tables cannot use null-conditional member access",
                Suggestion: "direct table.member access"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes) {
                    row := nodes?[0]
                }
                """,
                Message: "SoA row views cannot be used with null-conditional indexing",
                Suggestion: "table[index].column"),
            (
                Source: """
                soa record NodeTable {
                    kind: int
                }

                type Nodes = NodeTable

                func bad(nodes: Nodes): int {
                    return nodes[0]?.kind
                }
                """,
                Message: "SoA row views cannot be used with null-conditional member access",
                Suggestion: "table[index].column")
        };

        foreach (var (source, message, suggestion) in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains(message, error.Message);
            Assert.Contains(suggestion, error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
        }
    }

    [Theory]
    [InlineData("nodes.kind = new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("checked(nodes.kind) ??= new int[](1)", "kind", "assigned directly", "table[index].column")]
    [InlineData("nodes.length += 1", "length", "assigned directly", "add, clear, ensureCapacity, or copyRow")]
    [InlineData("++checked(nodes.capacity)", "capacity", "incremented or decremented directly", "add, clear, ensureCapacity, or copyRow")]
    public void Analyzer_SoaTableAliasRejectsDirectMemberMutationsBeforeEmission(
        string statement,
        string member,
        string action,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"SoA table member '{member}' cannot be {action}", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_SoaTableAliasColumnRangeSlicesWouldAllocate()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var cases = new[]
        {
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes): int {
                slice := nodes.kind[0..1]
                return slice[0]
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                range := 0..1
                (nodes.kind)[range] = [1]
            }
            """,
            """
            soa record NodeTable {
                kind: int
            }

            type Nodes = NodeTable

            func bad(nodes: Nodes) {
                checked(nodes.kind[1..^1])++
            }
            """
        };

        foreach (var source in cases)
        {
            var result = Analyze(source);
            var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
            Assert.Contains("SoA column range slices allocate arrays", error.Message);
            Assert.Contains("allocation-free view lowering", error.Suggestion);
            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
        }
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
    public void Analyzer_SoaRecordBoolRowColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                active: bool
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].active += true
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordBoolDirectColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                active: bool
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.active[row] += true
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordBoolFromEndDirectColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                active: bool
            }

            func bad(nodes: NodeTable) {
                nodes.active[^1] += true
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordEnumRowColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].kind += NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'NodeKind' and 'NodeKind'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordEnumDirectColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.kind[row] += NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'NodeKind' and 'NodeKind'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordEnumFromEndDirectColumnCompoundAssignment_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable) {
                nodes.kind[^1] += NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'NodeKind' and 'NodeKind'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("", "nodes[row].flags")]
    [InlineData("", "nodes.flags[row]")]
    [InlineData("", "nodes.flags[^1]")]
    [InlineData("", "(nodes.flags)[row]")]
    [InlineData("", "(nodes.flags)[^1]")]
    [InlineData("idx := ^1;", "(nodes.flags)[idx]")]
    [InlineData("", "(checked(nodes.flags))[row]")]
    [InlineData("", "(unchecked(nodes.flags))[^1]")]
    [InlineData("idx := ^1;", "(checked(nodes.flags))[idx]")]
    public void Analyzer_SoaRecordUintUnaryNegationAssignment_IsRejected(string declaration, string target)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                flags: uint
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{target}} = -{{target}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Equal("long", error.ActualType);
        Assert.Equal("uint", error.ExpectedType);
    }

    [Theory]
    [InlineData("", "nodes[row].kind")]
    [InlineData("", "nodes.kind[row]")]
    [InlineData("", "nodes.kind[^1]")]
    [InlineData("", "(nodes.kind)[row]")]
    [InlineData("", "(nodes.kind)[^1]")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx]")]
    [InlineData("", "(checked(nodes.kind))[row]")]
    [InlineData("", "(unchecked(nodes.kind))[^1]")]
    [InlineData("idx := ^1;", "(checked(nodes.kind))[idx]")]
    public void Analyzer_SoaRecordNonBoolColumnLogicalNot_IsRejected(string declaration, string target)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int): bool {
                {{declaration}}
                return !{{target}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'!' operator doesn't work with 'int'", error.Message);
        Assert.Contains("boolean value", error.Message);
    }

    [Theory]
    [InlineData("", "nodes[row].kind", "&&")]
    [InlineData("", "nodes.kind[row]", "&&")]
    [InlineData("", "nodes.kind[^1]", "&&")]
    [InlineData("", "(nodes.kind)[row]", "&&")]
    [InlineData("", "(nodes.kind)[^1]", "&&")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx]", "&&")]
    [InlineData("", "(checked(nodes.kind))[row]", "&&")]
    [InlineData("", "(unchecked(nodes.kind))[^1]", "&&")]
    [InlineData("idx := ^1;", "(checked(nodes.kind))[idx]", "&&")]
    [InlineData("", "nodes[row].kind", "||")]
    [InlineData("", "nodes.kind[row]", "||")]
    [InlineData("", "nodes.kind[^1]", "||")]
    [InlineData("", "(nodes.kind)[row]", "||")]
    [InlineData("", "(nodes.kind)[^1]", "||")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx]", "||")]
    [InlineData("", "(unchecked(nodes.kind))[row]", "||")]
    [InlineData("", "(checked(nodes.kind))[^1]", "||")]
    [InlineData("idx := ^1;", "(unchecked(nodes.kind))[idx]", "||")]
    public void Analyzer_SoaRecordNonBoolColumnLogicalExpressions_AreRejected(
        string declaration,
        string target,
        string logicalOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int): bool {
                {{declaration}}
                return {{target}} {{logicalOperator}} true
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"Both sides of '{logicalOperator}' must be booleans", error.Message);
        Assert.Contains("left side is 'int'", error.Message);
    }

    [Theory]
    [InlineData("", "nodes[row].marker", "{target} + 1")]
    [InlineData("", "nodes[row].marker", "{target} & 1")]
    [InlineData("", "nodes[row].marker", "{target} << 1")]
    [InlineData("", "nodes[row].marker", "~{target}")]
    [InlineData("", "nodes.marker[row]", "{target} + 1")]
    [InlineData("", "nodes.marker[row]", "{target} & 1")]
    [InlineData("", "nodes.marker[row]", "{target} << 1")]
    [InlineData("", "nodes.marker[row]", "~{target}")]
    [InlineData("", "nodes.marker[^1]", "{target} + 1")]
    [InlineData("", "nodes.marker[^1]", "{target} & 1")]
    [InlineData("", "nodes.marker[^1]", "{target} << 1")]
    [InlineData("", "nodes.marker[^1]", "~{target}")]
    [InlineData("", "(nodes.marker)[row]", "{target} + 1")]
    [InlineData("", "(nodes.marker)[row]", "{target} & 1")]
    [InlineData("", "(nodes.marker)[row]", "{target} << 1")]
    [InlineData("", "(nodes.marker)[row]", "~{target}")]
    [InlineData("", "(nodes.marker)[^1]", "{target} + 1")]
    [InlineData("", "(nodes.marker)[^1]", "{target} & 1")]
    [InlineData("", "(nodes.marker)[^1]", "{target} << 1")]
    [InlineData("", "(nodes.marker)[^1]", "~{target}")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "{target} + 1")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "{target} & 1")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "{target} << 1")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "~{target}")]
    [InlineData("", "(checked(nodes.marker))[row]", "{target} + 1")]
    [InlineData("", "(unchecked(nodes.marker))[^1]", "{target} & 1")]
    [InlineData("idx := ^1;", "(checked(nodes.marker))[idx]", "{target} << 1")]
    [InlineData("idx := ^1;", "(unchecked(nodes.marker))[idx]", "~{target}")]
    public void Analyzer_SoaRecordCharPromotedExpressionAssignment_IsRejected(
        string declaration,
        string target,
        string expressionTemplate)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var expression = expressionTemplate.Replace("{target}", target, StringComparison.Ordinal);
        var result = Analyze($$"""
            soa record NodeTable {
                marker: char
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{target}} = {{expression}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Equal("int", error.ActualType);
        Assert.Equal("char", error.ExpectedType);
    }

    [Theory]
    [InlineData("", "nodes[row].marker", "+=", "+")]
    [InlineData("", "nodes[row].marker", "-=", "-")]
    [InlineData("", "nodes[row].marker", "*=", "*")]
    [InlineData("", "nodes[row].marker", "/=", "/")]
    [InlineData("", "nodes.marker[row]", "+=", "+")]
    [InlineData("", "nodes.marker[row]", "-=", "-")]
    [InlineData("", "nodes.marker[row]", "*=", "*")]
    [InlineData("", "nodes.marker[row]", "/=", "/")]
    [InlineData("", "nodes.marker[^1]", "+=", "+")]
    [InlineData("", "nodes.marker[^1]", "-=", "-")]
    [InlineData("", "nodes.marker[^1]", "*=", "*")]
    [InlineData("", "nodes.marker[^1]", "/=", "/")]
    [InlineData("", "(nodes.marker)[row]", "+=", "+")]
    [InlineData("", "(nodes.marker)[row]", "-=", "-")]
    [InlineData("", "(nodes.marker)[row]", "*=", "*")]
    [InlineData("", "(nodes.marker)[row]", "/=", "/")]
    [InlineData("", "(nodes.marker)[^1]", "+=", "+")]
    [InlineData("", "(nodes.marker)[^1]", "-=", "-")]
    [InlineData("", "(nodes.marker)[^1]", "*=", "*")]
    [InlineData("", "(nodes.marker)[^1]", "/=", "/")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "+=", "+")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "-=", "-")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "*=", "*")]
    [InlineData("idx := ^1;", "(nodes.marker)[idx]", "/=", "/")]
    public void Analyzer_SoaRecordCharArithmeticCompoundAssignments_AreRejected(
        string declaration,
        string target,
        string assignmentOperator,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                marker: char
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{target}} {{assignmentOperator}} 'a'
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"The '{assignmentOperator}' assignment produces 'int'", error.Message);
        Assert.Contains("can't be stored in 'char'", error.Message);
        Assert.DoesNotContain($"'{binaryOperator}' operator doesn't work", error.Message);
    }

    [Theory]
    [InlineData("nodes[row].active", "-=", "-")]
    [InlineData("nodes[row].active", "*=", "*")]
    [InlineData("nodes[row].active", "/=", "/")]
    [InlineData("nodes.active[row]", "-=", "-")]
    [InlineData("nodes.active[row]", "*=", "*")]
    [InlineData("nodes.active[row]", "/=", "/")]
    [InlineData("nodes.active[^1]", "-=", "-")]
    [InlineData("nodes.active[^1]", "*=", "*")]
    [InlineData("nodes.active[^1]", "/=", "/")]
    public void Analyzer_SoaRecordBoolUnsupportedCompoundAssignmentOperators_AreRejected(
        string target,
        string assignmentOperator,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                active: bool
            }

            func bad(nodes: NodeTable, row: int) {
                {{target}} {{assignmentOperator}} true
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{binaryOperator}' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("nodes[row].kind", "-=", "-")]
    [InlineData("nodes[row].kind", "*=", "*")]
    [InlineData("nodes[row].kind", "/=", "/")]
    [InlineData("nodes.kind[row]", "-=", "-")]
    [InlineData("nodes.kind[row]", "*=", "*")]
    [InlineData("nodes.kind[row]", "/=", "/")]
    [InlineData("nodes.kind[^1]", "-=", "-")]
    [InlineData("nodes.kind[^1]", "*=", "*")]
    [InlineData("nodes.kind[^1]", "/=", "/")]
    public void Analyzer_SoaRecordEnumUnsupportedCompoundAssignmentOperators_AreRejected(
        string target,
        string assignmentOperator,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                {{target}} {{assignmentOperator}} NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(
            $"'{binaryOperator}' operator doesn't work with 'NodeKind' and 'NodeKind'",
            error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("", "(nodes.active)[row] += true", "+")]
    [InlineData("", "(nodes.active)[row] -= true", "-")]
    [InlineData("", "(nodes.active)[^1] += true", "+")]
    [InlineData("", "(nodes.active)[^1] *= true", "*")]
    [InlineData("idx := ^1;", "(nodes.active)[idx] += true", "+")]
    [InlineData("idx := ^1;", "(nodes.active)[idx] /= true", "/")]
    public void Analyzer_SoaRecordParenthesizedColumnMemberBoolCompoundAssignments_AreRejected(
        string declaration,
        string statement,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                active: bool
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{binaryOperator}' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("", "(nodes.kind)[row] += NodeKind.Identifier", "+")]
    [InlineData("", "(nodes.kind)[row] -= NodeKind.Identifier", "-")]
    [InlineData("", "(nodes.kind)[^1] += NodeKind.Identifier", "+")]
    [InlineData("", "(nodes.kind)[^1] *= NodeKind.Identifier", "*")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx] += NodeKind.Identifier", "+")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx] /= NodeKind.Identifier", "/")]
    public void Analyzer_SoaRecordParenthesizedColumnMemberEnumCompoundAssignments_AreRejected(
        string declaration,
        string statement,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(
            $"'{binaryOperator}' operator doesn't work with 'NodeKind' and 'NodeKind'",
            error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("nodes[row].text", "-=", "-")]
    [InlineData("nodes[row].text", "*=", "*")]
    [InlineData("nodes[row].text", "/=", "/")]
    [InlineData("nodes.text[row]", "-=", "-")]
    [InlineData("nodes.text[row]", "*=", "*")]
    [InlineData("nodes.text[row]", "/=", "/")]
    [InlineData("nodes.text[^1]", "-=", "-")]
    [InlineData("nodes.text[^1]", "*=", "*")]
    [InlineData("nodes.text[^1]", "/=", "/")]
    public void Analyzer_SoaRecordStringUnsupportedCompoundAssignmentOperators_AreRejected(
        string target,
        string assignmentOperator,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable, row: int) {
                {{target}} {{assignmentOperator}} "suffix"
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(
            $"'{binaryOperator}' operator doesn't work with 'string' and 'string'",
            error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("nodes[row].text", "-=", "-")]
    [InlineData("nodes[row].text", "*=", "*")]
    [InlineData("nodes[row].text", "/=", "/")]
    [InlineData("nodes.text[row]", "-=", "-")]
    [InlineData("nodes.text[row]", "*=", "*")]
    [InlineData("nodes.text[row]", "/=", "/")]
    [InlineData("nodes.text[^1]", "-=", "-")]
    [InlineData("nodes.text[^1]", "*=", "*")]
    [InlineData("nodes.text[^1]", "/=", "/")]
    public void Analyzer_SoaRecordNullableStringUnsupportedCompoundAssignmentOperators_AreRejected(
        string target,
        string assignmentOperator,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                text: string?
            }

            func bad(nodes: NodeTable, row: int) {
                {{target}} {{assignmentOperator}} "suffix"
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{binaryOperator}' operator doesn't work", error.Message);
        Assert.Contains("string?", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData("string", "", "(nodes.text)[row] -= \"suffix\"", "-")]
    [InlineData("string", "", "(nodes.text)[row] *= \"suffix\"", "*")]
    [InlineData("string", "", "(nodes.text)[^1] -= \"suffix\"", "-")]
    [InlineData("string", "", "(nodes.text)[^1] /= \"suffix\"", "/")]
    [InlineData("string", "idx := ^1;", "(nodes.text)[idx] *= \"suffix\"", "*")]
    [InlineData("string", "idx := ^1;", "(nodes.text)[idx] /= \"suffix\"", "/")]
    [InlineData("string?", "", "(nodes.text)[row] -= \"suffix\"", "-")]
    [InlineData("string?", "", "(nodes.text)[row] *= \"suffix\"", "*")]
    [InlineData("string?", "", "(nodes.text)[^1] -= \"suffix\"", "-")]
    [InlineData("string?", "", "(nodes.text)[^1] /= \"suffix\"", "/")]
    [InlineData("string?", "idx := ^1;", "(nodes.text)[idx] *= \"suffix\"", "*")]
    [InlineData("string?", "idx := ^1;", "(nodes.text)[idx] /= \"suffix\"", "/")]
    public void Analyzer_SoaRecordParenthesizedColumnMemberStringCompoundAssignments_AreRejected(
        string columnType,
        string declaration,
        string statement,
        string binaryOperator)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                text: {{columnType}}
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{binaryOperator}' operator doesn't work", error.Message);
        Assert.Contains(columnType, error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Theory]
    [InlineData(
        """
        soa record NodeTable {
            marker: char
        }

        func bad(nodes: NodeTable, row: int) {
            (checked(nodes.marker))[row] += 'a'
        }
        """,
        "The '+=' assignment produces 'int'",
        "can't be stored in 'char'")]
    [InlineData(
        """
        soa record NodeTable {
            active: bool
        }

        func bad(nodes: NodeTable, row: int) {
            (unchecked(nodes.active))[^1] -= true
        }
        """,
        "'-' operator doesn't work with 'bool' and 'bool'",
        "numeric values")]
    [InlineData(
        """
        enum NodeKind {
            Unknown,
            Identifier
        }

        soa record NodeTable {
            kind: NodeKind
        }

        func bad(nodes: NodeTable, row: int) {
            idx := ^1
            (checked(nodes.kind))[idx] *= NodeKind.Identifier
        }
        """,
        "'*' operator doesn't work with 'NodeKind' and 'NodeKind'",
        "numeric values")]
    [InlineData(
        """
        soa record NodeTable {
            text: string
        }

        func bad(nodes: NodeTable, row: int) {
            (unchecked(nodes.text))[row] /= "suffix"
        }
        """,
        "'/' operator doesn't work with 'string' and 'string'",
        "numeric values")]
    [InlineData(
        """
        soa record NodeTable {
            text: string?
        }

        func bad(nodes: NodeTable, row: int) {
            (checked(nodes.text))[^1] -= "suffix"
        }
        """,
        "'-' operator doesn't work",
        "string?")]
    public void Analyzer_SoaRecordCheckedUncheckedColumnMemberUnsupportedCompoundAssignments_AreRejected(
        string source,
        string firstMessagePart,
        string secondMessagePart)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(firstMessagePart, error.Message);
        Assert.Contains(secondMessagePart, error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordGeneratedOperationsBindNamedArguments()
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
                nodes[first].kind = 7
                nodes[first].start = 8
                nodes.ensureCapacity(capacity: 3)
                nodes.copyRow(to: 2, from: first)
                return nodes.capacity * 1000 + nodes.length * 100 + nodes[2].kind * 10 + nodes[2].start
            }
            """;

        Assert.Equal(4378, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordGeneratedOperationsAcceptSmallIntegerArguments()
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
                kinds[0] = 7
                starts[0] = 8
                nodes := NodeTable.wrap(kind: kinds, start: starts, length: (short)1)
                nodes.ensureCapacity(capacity: (sbyte)3)
                nodes.copyRow(from: (short)0, to: (sbyte)2)
                return nodes.capacity * 1000 + nodes.length * 100 + nodes[2].kind * 10 + nodes[2].start
            }
            """;

        Assert.Equal(4378, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordCapacityConstructorBindsNamedArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                nodes := new NodeTable(capacity: 2)
                return nodes.capacity
            }
            """;

        Assert.Equal(2, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordCapacityConstructorAcceptsSmallIntegerCapacity()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func main(): int {
                nodes := new NodeTable((short)4)
                return nodes.capacity
            }
            """;

        Assert.Equal(4, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordRowProjection_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func rowOps(nodes: NodeTable, row: int): int {
                nodes[row].kind = 10
                nodes[row].start = nodes[row].kind + 2
                nodes[row].kind += nodes[row].start
                return nodes[row].kind + nodes[row].start
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row)
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var rowOps = assembly.GetType("Program")!.GetMethod(
                "rowOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(rowOps);
            return GetMethodOpCodes(rowOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedRowProjection_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func rowOps(nodes: NodeTable, row: int): int {
                (nodes[row]).kind = 10;
                kindBefore := (nodes[row]).kind
                nodes[row].start = kindBefore + 2;
                (nodes[row]).kind += (nodes[row]).start
                return (nodes[row]).kind + (nodes[row]).start
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row)
            }
            """;

        Assert.Equal(34, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var rowOps = assembly.GetType("Program")!.GetMethod(
                "rowOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(rowOps);
            return GetMethodOpCodes(rowOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedRowProjectionUpdateTargets_UseColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func rowOps(nodes: NodeTable, row: int): int {
                ((nodes[row]).kind) = 10;
                stored := (((nodes[row]).kind) += 2);
                ((nodes[row]).start) = stored + ((nodes[row]).kind)
                return stored * 100 + ((nodes[row]).kind) * 10 + ((nodes[row]).start)
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row)
            }
            """;

        Assert.Equal(1344, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var rowOps = assembly.GetType("Program")!.GetMethod(
                "rowOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(rowOps);
            return GetMethodOpCodes(rowOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedRowProjectionNullCoalesceAssign_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func textOps(nodes: NodeTable, row: int): string {
                ((nodes[row]).text) ??= "fallback"
                current := (((nodes[row]).text) ??= "ignored");
                return current + ":" + ((nodes[row]).text)
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return textOps(nodes, row)
            }
            """;

        Assert.Equal("fallback:fallback", Assert.IsType<string>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var textOps = assembly.GetType("Program")!.GetMethod(
                "textOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(textOps);
            return GetMethodOpCodes(textOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedRowProjectionIncrementTargets_UseColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func rowOps(nodes: NodeTable, row: int): int {
                ((nodes[row]).kind) = 10
                oldUp := ((nodes[row]).kind)++;
                afterPostUp := ((nodes[row]).kind)
                newUp := ++((nodes[row]).kind);
                oldDown := ((nodes[row]).kind)--;
                newDown := --((nodes[row]).kind);
                ((nodes[row]).kind)++;
                ++((nodes[row]).kind);
                return oldUp * 100000 + afterPostUp * 10000 + newUp * 1000 + oldDown * 100 + newDown * 10 + ((nodes[row]).kind)
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return rowOps(nodes, row)
            }
            """;

        Assert.Equal(1123312, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var rowOps = assembly.GetType("Program")!.GetMethod(
                "rowOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(rowOps);
            return GetMethodOpCodes(rowOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedDirectColumnElementTargets_UseColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func columnOps(nodes: NodeTable, row: int): int {
                ((nodes.kind)[row]) = 10
                stored := (((nodes.kind)[row]) += 2);
                oldUp := ((nodes.kind)[row])++;
                newUp := ++((nodes.kind)[row]);
                oldDown := ((nodes.kind)[row])--;
                newDown := --((nodes.kind)[row]);
                return stored * 100000 + oldUp * 10000 + newUp * 1000 + oldDown * 100 + newDown * 10 + ((nodes.kind)[row])
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                return columnOps(nodes, row)
            }
            """;

        Assert.Equal(1335532, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var columnOps = assembly.GetType("Program")!.GetMethod(
                "columnOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(columnOps);
            return GetMethodOpCodes(columnOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedFromEndDirectColumnElementTargets_UseColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func columnOps(nodes: NodeTable): int {
                nodes.add();
                ((nodes.kind)[^1]) = 10
                stored := (((nodes.kind)[^1]) += 2);
                oldUp := ((nodes.kind)[^1])++;
                newUp := ++((nodes.kind)[^1]);
                oldDown := ((nodes.kind)[^1])--;
                newDown := --((nodes.kind)[^1]);
                return stored * 100000 + oldUp * 10000 + newUp * 1000 + oldDown * 100 + newDown * 10 + ((nodes.kind)[^1])
            }

            func main(): int {
                nodes := new NodeTable(1)
                return columnOps(nodes)
            }
            """;

        Assert.Equal(1335532, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var columnOps = assembly.GetType("Program")!.GetMethod(
                "columnOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(columnOps);
            return GetMethodOpCodes(columnOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedVariableFromEndDirectColumnElementTargets_UseColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func columnOps(nodes: NodeTable): int {
                nodes.add();
                idx := ^1;
                ((nodes.kind)[idx]) = 10
                stored := (((nodes.kind)[idx]) += 2);
                oldUp := ((nodes.kind)[idx])++;
                newUp := ++((nodes.kind)[idx]);
                oldDown := ((nodes.kind)[idx])--;
                newDown := --((nodes.kind)[idx]);
                return stored * 100000 + oldUp * 10000 + newUp * 1000 + oldDown * 100 + newDown * 10 + ((nodes.kind)[idx])
            }

            func main(): int {
                nodes := new NodeTable(1)
                return columnOps(nodes)
            }
            """;

        Assert.Equal(1335532, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var columnOps = assembly.GetType("Program")!.GetMethod(
                "columnOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(columnOps);
            return GetMethodOpCodes(columnOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordDirectColumnRefOutArguments_UseColumnElementAddresses()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func bump(ref value: int) {
                value += 5
            }

            func reset(out value: int) {
                value = 11
            }

            func columnRefOut(nodes: NodeTable): int {
                first := nodes.add()
                second := nodes.add()
                nodes.kind[first] = 3
                nodes.kind[second] = 7
                bump(ref nodes.kind[first])
                reset(out nodes.kind[^1])
                idx := ^1
                bump(ref (nodes.kind)[idx])
                return nodes.kind[first] * 100 + nodes.kind[second]
            }

            func main(): int {
                nodes := new NodeTable(2)
                return columnRefOut(nodes)
            }
            """;

        Assert.Equal(816, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var columnRefOut = assembly.GetType("Program")!.GetMethod(
                "columnRefOut",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(columnRefOut);
            return GetMethodOpCodes(columnRefOut!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(OpCodes.Ldelema, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordEnumColumnRefOutArguments_UseColumnElementAddresses()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            enum NodeKind {
                Missing,
                Identifier,
                String,
                Number
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func setIdentifier(ref value: NodeKind) {
                value = NodeKind.Identifier
            }

            func setNumber(out value: NodeKind) {
                value = NodeKind.Number
            }

            func enumRefOut(nodes: NodeTable): int {
                first := nodes.add()
                second := nodes.add()
                nodes[first].kind = NodeKind.Missing
                nodes[second].kind = NodeKind.String
                setIdentifier(ref nodes[first].kind)
                setNumber(out (nodes[second]).kind)
                idx := ^1
                setIdentifier(ref (nodes.kind)[idx])
                return (nodes[first].kind == NodeKind.Identifier ? 10 : 0) + (nodes[second].kind == NodeKind.Identifier ? 1 : 0)
            }

            func main(): int {
                nodes := new NodeTable(2)
                return enumRefOut(nodes)
            }
            """;

        Assert.Equal(11, Assert.IsType<int>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var enumRefOut = assembly.GetType("Program")!.GetMethod(
                "enumRefOut",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(enumRefOut);
            return GetMethodOpCodes(enumRefOut!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(OpCodes.Ldelema, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedVariableFromEndDirectColumnNullCoalesceRead_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func readOps(nodes: NodeTable): string {
                missingIdx := ^2;
                existingIdx := ^1;
                missing := ((nodes.text)[missingIdx]) ?? "fallback";
                existing := (((nodes.text)[existingIdx]) ?? "ignored");
                return missing + ":" + existing
            }

            func main(): string {
                nodes := new NodeTable(2)
                nodes.add();
                nodes.add();
                nodes.text[1] = "ready"
                return readOps(nodes)
            }
            """;

        Assert.Equal("fallback:ready", Assert.IsType<string>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var readOps = assembly.GetType("Program")!.GetMethod(
                "readOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(readOps);
            return GetMethodOpCodes(readOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedVariableFromEndDirectColumnNullCoalesceAssign_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func textOps(nodes: NodeTable): string {
                nodes.add();
                idx := ^1;
                ((nodes.text)[idx]) ??= "fallback"
                current := (((nodes.text)[idx]) ??= "ignored");
                return current + ":" + ((nodes.text)[idx])
            }

            func main(): string {
                nodes := new NodeTable(1)
                return textOps(nodes)
            }
            """;

        Assert.Equal("fallback:fallback", Assert.IsType<string>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var textOps = assembly.GetType("Program")!.GetMethod(
                "textOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(textOps);
            return GetMethodOpCodes(textOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordParenthesizedFromEndDirectColumnNullCoalesceAssign_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func textOps(nodes: NodeTable): string {
                nodes.add();
                ((nodes.text)[^1]) ??= "fallback"
                current := (((nodes.text)[^1]) ??= "ignored");
                return current + ":" + ((nodes.text)[^1])
            }

            func main(): string {
                nodes := new NodeTable(1)
                return textOps(nodes)
            }
            """;

        Assert.Equal("fallback:fallback", Assert.IsType<string>(CompileAndInvoke(source)));

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var textOps = assembly.GetType("Program")!.GetMethod(
                "textOps",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(textOps);
            return GetMethodOpCodes(textOps!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordVerifiedColumnTypes_LoadStoreRoundTrip()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            type KindColumn = int
            type FlagsColumn = uint
            type StartColumn = long
            type ActiveColumn = bool
            type MarkerColumn = char
            type NameColumn = string
            type CountColumn = int
            type OptionalNameColumn = string?

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
    public void ILCompiler_SoaRecordWrapBindsNamedArguments()
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
                nodes := NodeTable.wrap(length: 1, start: starts, kind: kinds)
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
    public void ILCompiler_SoaRecordCapacityConstructorDynamicNegative_ReportsCapacityMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func capacity(): int {
                return 0 - 1
            }

            func main(): int {
                nodes := new NodeTable(capacity())
                return nodes.capacity
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("capacity for NodeTable must be non-negative", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordEnsureCapacityDynamicNegative_ReportsCapacityMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func capacity(): int {
                return 0 - 1
            }

            func main(): int {
                nodes := new NodeTable(1)
                nodes.ensureCapacity(capacity())
                return nodes.capacity
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source));
        Assert.Equal("capacity for NodeTable.ensureCapacity must be non-negative", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordAddDynamicMaxLength_ReportsLengthMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record EmptyTable {
            }

            func addAt(length: int): int {
                nodes := EmptyTable.wrap(length)
                nodes.add()
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source, "addAt", int.MaxValue));
        Assert.Equal("length for EmptyTable.add is too large", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordCopyRowDynamicNegativeRows_ReportRowMessages()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func copyFrom(from: int): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.copyRow(from, 0)
                return nodes.length
            }

            func copyTo(to: int): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.copyRow(0, to)
                return nodes.length
            }
            """;

        var sourceError = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source, "copyFrom", -1));
        Assert.Equal("source row for NodeTable.copyRow must be non-negative", sourceError.Message);

        var targetError = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source, "copyTo", -1));
        Assert.Equal("target row for NodeTable.copyRow must be non-negative", targetError.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordCopyRowDynamicSourcePastLength_ReportsRowMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func copyFrom(from: int): int {
                nodes := new NodeTable(3)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.copyRow(from, 0)
                return nodes[0].kind
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source, "copyFrom", 1));
        Assert.Equal("source row for NodeTable.copyRow must be less than length", error.Message);
    }

    [Fact]
    public void ILCompiler_SoaRecordCopyRowDynamicTargetMaxValue_ReportsRowMessage()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func copyTo(to: int): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.copyRow(0, to)
                return nodes.length
            }
            """;

        var error = Assert.Throws<ArgumentException>(() => CompileAndInvoke(source, "copyTo", int.MaxValue));
        Assert.Equal("target row for NodeTable.copyRow is too large", error.Message);
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
    public void ILCompiler_SoaRecordCopyRow_UsesColumnElementILShape()
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
                nodes.copyRow(0, 1)
                return nodes[1].kind + nodes[1].start
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var copyRow = assembly.GetType("NodeTable")!.GetMethod(
                "copyRow",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(copyRow);
            return GetMethodOpCodes(copyRow!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.Contains(OpCodes.Call, opCodes); // ensureCapacity
        Assert.Equal(4, opCodes.Count(opCode => opCode == OpCodes.Newobj)); // source/target/range/overflow guard exceptions
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
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
    public void ILCompiler_SoaRecordNullCoalesceOnRowColumn_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func readOrFallback(nodes: NodeTable, row: int): string {
                return nodes[row].text ?? "fallback"
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return readOrFallback(nodes, row)
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var readOrFallback = assembly.GetType("Program")!.GetMethod(
                "readOrFallback",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(readOrFallback);
            return GetMethodOpCodes(readOrFallback!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceAssignOnRowColumn_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func setIfMissing(nodes: NodeTable, row: int): string {
                nodes[row].text ??= "fallback"
                return nodes[row].text
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return setIfMissing(nodes, row)
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var setIfMissing = assembly.GetType("Program")!.GetMethod(
                "setIfMissing",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(setIfMissing);
            return GetMethodOpCodes(setIfMissing!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceOnDirectColumnElement_ChoosesFallbackOrExistingValue()
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
                missing := nodes.text[first] ?? "fallback"
                nodes.text[second] = "ready"
                existing := nodes.text[second] ?? "ignored"
                nodes.text[first] ??= "assigned"
                nodes.text[first] ??= "other"
                return missing + ":" + existing + ":" + nodes.text[first]
            }
            """;

        Assert.Equal("fallback:ready:assigned", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceOnDirectColumnElement_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func readOrFallback(nodes: NodeTable, row: int): string {
                return nodes.text[row] ?? "fallback"
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return readOrFallback(nodes, row)
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var readOrFallback = assembly.GetType("Program")!.GetMethod(
                "readOrFallback",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(readOrFallback);
            return GetMethodOpCodes(readOrFallback!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceAssignOnDirectColumnElement_UsesColumnElementILShape()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func setIfMissing(nodes: NodeTable, row: int): string {
                nodes.text[row] ??= "fallback"
                return nodes.text[row]
            }

            func main(): string {
                nodes := new NodeTable(1)
                row := nodes.add()
                return setIfMissing(nodes, row)
            }
            """;

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var setIfMissing = assembly.GetType("Program")!.GetMethod(
                "setIfMissing",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(setIfMissing);
            return GetMethodOpCodes(setIfMissing!);
        });

        Assert.Contains(OpCodes.Ldfld, opCodes);
        Assert.Contains(opCodes, IsArrayElementLoad);
        Assert.Contains(opCodes, IsArrayElementStore);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Newarr, opCodes);
        Assert.DoesNotContain(OpCodes.Box, opCodes);
        Assert.DoesNotContain(OpCodes.Ldftn, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
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
    public void Analyzer_SoaRecordNullCoalesceAssignOnNonNullableDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.kind[row] ??= 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnNonNullableDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int): int {
                return nodes.kind[row] ?? 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceAssignOnNonNullableFromEndDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                nodes.kind[^1] ??= 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnNonNullableFromEndDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes.kind[^1] ?? 5
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceAssignOnEnumRowColumn_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].kind ??= NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnEnumRowColumn_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int): NodeKind {
                return nodes[row].kind ?? NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceAssignOnEnumDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.kind[row] ??= NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnEnumDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int): NodeKind {
                return nodes.kind[row] ?? NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceAssignOnEnumFromEndDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable) {
                nodes.kind[^1] ??= NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNullCoalesceOnEnumFromEndDirectColumnElement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable): NodeKind {
                return nodes.kind[^1] ?? NodeKind.Identifier
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Theory]
    [InlineData("", "(nodes.kind)[row] ??= 5", "??=", "make the target nullable")]
    [InlineData("", "value := (nodes.kind)[row] ?? 5", "??", "make the left side nullable")]
    [InlineData("", "(nodes.kind)[^1] ??= 5", "??=", "make the target nullable")]
    [InlineData("", "value := (nodes.kind)[^1] ?? 5", "??", "make the left side nullable")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx] ??= 5", "??=", "make the target nullable")]
    [InlineData("idx := ^1;", "value := (nodes.kind)[idx] ?? 5", "??", "make the left side nullable")]
    public void Analyzer_SoaRecordParenthesizedColumnMemberNullCoalesceOnNonNullable_IsRejected(
        string declaration,
        string statement,
        string operatorText,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"left side of '{operatorText}' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Theory]
    [InlineData("", "(nodes.kind)[row] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("", "value := (nodes.kind)[row] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    [InlineData("", "(nodes.kind)[^1] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("", "value := (nodes.kind)[^1] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    [InlineData("idx := ^1;", "(nodes.kind)[idx] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("idx := ^1;", "value := (nodes.kind)[idx] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    public void Analyzer_SoaRecordParenthesizedColumnMemberNullCoalesceOnEnum_IsRejected(
        string declaration,
        string statement,
        string operatorText,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"left side of '{operatorText}' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Theory]
    [InlineData("", "(checked(nodes.kind))[row] ??= 5", "??=", "make the target nullable")]
    [InlineData("", "value := (unchecked(nodes.kind))[row] ?? 5", "??", "make the left side nullable")]
    [InlineData("", "(unchecked(nodes.kind))[^1] ??= 5", "??=", "make the target nullable")]
    [InlineData("", "value := (checked(nodes.kind))[^1] ?? 5", "??", "make the left side nullable")]
    [InlineData("idx := ^1;", "(checked(nodes.kind))[idx] ??= 5", "??=", "make the target nullable")]
    [InlineData("idx := ^1;", "value := (unchecked(nodes.kind))[idx] ?? 5", "??", "make the left side nullable")]
    public void Analyzer_SoaRecordCheckedUncheckedColumnMemberNullCoalesceOnNonNullable_IsRejected(
        string declaration,
        string statement,
        string operatorText,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"left side of '{operatorText}' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Theory]
    [InlineData("", "(checked(nodes.kind))[row] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("", "value := (unchecked(nodes.kind))[row] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    [InlineData("", "(unchecked(nodes.kind))[^1] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("", "value := (checked(nodes.kind))[^1] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    [InlineData("idx := ^1;", "(checked(nodes.kind))[idx] ??= NodeKind.Identifier", "??=", "make the target nullable")]
    [InlineData("idx := ^1;", "value := (unchecked(nodes.kind))[idx] ?? NodeKind.Identifier", "??", "make the left side nullable")]
    public void Analyzer_SoaRecordCheckedUncheckedColumnMemberNullCoalesceOnEnum_IsRejected(
        string declaration,
        string statement,
        string operatorText,
        string suggestion)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            enum NodeKind {
                Unknown,
                Identifier
            }

            soa record NodeTable {
                kind: NodeKind
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"left side of '{operatorText}' has type 'NodeKind'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains(suggestion, error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralRowColumnIncrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].text++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'++' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralDirectColumnIncrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.text[row]++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'++' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralFromEndDirectColumnIncrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable) {
                nodes.text[^1]++
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'++' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralRowColumnDecrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable, row: int) {
                nodes[row].text--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'--' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralDirectColumnDecrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable, row: int) {
                nodes.text[row]--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'--' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Analyzer_SoaRecordNonIntegralFromEndDirectColumnDecrement_IsRejected()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                text: string
            }

            func bad(nodes: NodeTable) {
                nodes.text[^1]--
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'--' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Theory]
    [InlineData("nodes[row].text++", "++")]
    [InlineData("nodes[row].text--", "--")]
    [InlineData("nodes.text[row]++", "++")]
    [InlineData("nodes.text[row]--", "--")]
    [InlineData("nodes.text[^1]++", "++")]
    [InlineData("nodes.text[^1]--", "--")]
    [InlineData("(nodes.text)[row]++", "++")]
    [InlineData("(nodes.text)[row]--", "--")]
    [InlineData("(nodes.text)[^1]++", "++")]
    [InlineData("(nodes.text)[^1]--", "--")]
    [InlineData("idx := ^1; (nodes.text)[idx]++", "++")]
    [InlineData("idx := ^1; (nodes.text)[idx]--", "--")]
    public void Analyzer_SoaRecordNullableStringIncrementAndDecrement_AreRejected(
        string expression,
        string operatorText)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                text: string?
            }

            func bad(nodes: NodeTable, row: int) {
                {{expression}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{operatorText}' operator doesn't work with 'string?'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Theory]
    [InlineData("string", "", "(checked(nodes.text))[row]++", "++", "string")]
    [InlineData("string", "", "(unchecked(nodes.text))[^1]--", "--", "string")]
    [InlineData("string", "idx := ^1;", "++((checked(nodes.text))[idx])", "++", "string")]
    [InlineData("string?", "", "(checked(nodes.text))[row]--", "--", "string?")]
    [InlineData("string?", "idx := ^1;", "++((unchecked(nodes.text))[idx])", "++", "string?")]
    [InlineData("bool", "", "(unchecked(nodes.text))[row]++", "++", "bool")]
    [InlineData("bool", "idx := ^1;", "--((checked(nodes.text))[idx])", "--", "bool")]
    public void Analyzer_SoaRecordCheckedUncheckedColumnMemberNonIntegralUpdates_AreRejected(
        string columnType,
        string declaration,
        string statement,
        string operatorText,
        string typeName)
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze($$"""
            soa record NodeTable {
                text: {{columnType}}
            }

            func bad(nodes: NodeTable, row: int) {
                {{declaration}}
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"'{operatorText}' operator doesn't work with '{typeName}'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
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

    private static ParseResult ParseWithErrors(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        return parser.ParseCompilationUnit();
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

    private static bool IsArrayElementLoad(OpCode opCode)
        => opCode == OpCodes.Ldelem
           || opCode == OpCodes.Ldelem_I
           || opCode == OpCodes.Ldelem_I1
           || opCode == OpCodes.Ldelem_I2
           || opCode == OpCodes.Ldelem_I4
           || opCode == OpCodes.Ldelem_I8
           || opCode == OpCodes.Ldelem_R4
           || opCode == OpCodes.Ldelem_R8
           || opCode == OpCodes.Ldelem_Ref
           || opCode == OpCodes.Ldelem_U1
           || opCode == OpCodes.Ldelem_U2
           || opCode == OpCodes.Ldelem_U4;

    private static bool IsArrayElementStore(OpCode opCode)
        => opCode == OpCodes.Stelem
           || opCode == OpCodes.Stelem_I
           || opCode == OpCodes.Stelem_I1
           || opCode == OpCodes.Stelem_I2
           || opCode == OpCodes.Stelem_I4
           || opCode == OpCodes.Stelem_I8
           || opCode == OpCodes.Stelem_R4
           || opCode == OpCodes.Stelem_R8
           || opCode == OpCodes.Stelem_Ref;

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
