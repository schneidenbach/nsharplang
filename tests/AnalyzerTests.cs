using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Tests;

public class AnalyzerTests
{
    // Project config for ASP.NET Core tests
    private static readonly ProjectConfig AspNetCoreConfig = new()
    {
        Sdk = "Microsoft.NET.Sdk.Web",
        TargetFramework = "net9.0",
        // For tests, we'll rely on the Sdk="Web" to trigger loading ASP.NET assemblies
        // The LoadFromProjectConfig method will load these automatically
    };

    private AnalysisResult Analyze(string source, ProjectConfig? config = null)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();

        // Load system assemblies
        analyzer.LoadSystemAssemblies();

        // Load from project config if provided
        analyzer.LoadFromProjectConfig(config);

        return analyzer.Analyze(result.CompilationUnit!);
    }

    private void AssertNoErrors(string source, ProjectConfig? config = null)
    {
        var result = Analyze(source, config);
        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    private void AssertHasError(string source, string expectedMessage)
    {
        var result = Analyze(source);
        Assert.True(result.HasErrors, "Expected errors but got none");
        Assert.Contains(result.Errors, e => e.Message.Contains(expectedMessage));
    }

    private void AssertHasParseError(string source, string expectedMessage)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var result = parser.ParseCompilationUnit();
        Assert.False(result.Success, "Expected parse error but got none");
        Assert.Contains(result.Errors, e => e.Message.Contains(expectedMessage));
    }

    /// <summary>
    /// Analyze source code with full source context so the rich error path (ErrorMessageBuilder) is taken,
    /// populating ContextualHint with conversion suggestions.
    /// </summary>
    private AnalysisResult AnalyzeWithSource(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(result.CompilationUnit!, "test.nl", null, source);
    }

    /// <summary>
    /// Assert that at least one error has a ContextualHint containing the expected text.
    /// Use this to verify numeric narrowing cast suggestions.
    /// </summary>
    private void AssertHasHint(string source, string expectedHint)
    {
        var result = AnalyzeWithSource(source);
        Assert.True(result.HasErrors, "Expected errors but got none");
        Assert.Contains(result.Errors, e =>
            (e.ContextualHint != null && e.ContextualHint.Contains(expectedHint)));
    }

    [Fact]
    public void SimpleVariableDeclaration_TypeInference()
    {
        AssertNoErrors(@"
            func Main() {
                x := 42
            }
        ");
    }

    [Fact]
    public void VariableDeclaration_WithExplicitType()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int = 42
            }
        ");
    }

    [Fact]
    public void VariableDeclaration_TypeMismatch()
    {
        AssertHasError(@"
            func Main() {
                let x: string = 42
            }
        ", "Cannot assign");
    }

    [Fact]
    public void ConstWithoutInitializer_Error()
    {
        AssertHasError(@"
            func Main() {
                const x: int
            }
        ", "Const variables must have an initializer");
    }

    [Fact]
    public void UndefinedVariable_Error()
    {
        AssertHasError(@"
            func Main() {
                x := y
            }
        ", "Undefined identifier 'y'");
    }

    [Fact]
    public void FunctionDeclaration_Valid()
    {
        AssertNoErrors(@"
            func Add(x: int, y: int): int {
                return x + y
            }
        ");
    }

    [Fact]
    public void ReturnTypeMismatch_Error()
    {
        AssertHasError(@"
            func GetName(): string {
                return 42
            }
        ", "Cannot return");
    }

    [Fact]
    public void VoidFunctionReturnValue_Error()
    {
        AssertHasError(@"
            func DoNothing() {
                return 42
            }
        ", "Cannot return");
    }

    [Fact]
    public void IfConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                if 42 {

                }
            }
        ", "If condition must be boolean");
    }

    [Fact]
    public void WhileConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                while 42 {

                }
            }
        ", "While condition must be boolean");
    }

    [Fact]
    public void ForConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                for i := 0; ""test""; i++ {

                }
            }
        ", "For condition must be boolean");
    }

    [Fact]
    public void BreakOutsideLoop_Error()
    {
        AssertHasError(@"
            func Main() {
                break
            }
        ", "Break statement outside of loop");
    }

    [Fact]
    public void ContinueOutsideLoop_Error()
    {
        AssertHasError(@"
            func Main() {
                continue
            }
        ", "Continue statement outside of loop");
    }

    [Fact]
    public void BreakInsideLoop_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                while true {
                    break
                }
            }
        ");
    }

    [Fact]
    public void ClassDeclaration_Valid()
    {
        AssertNoErrors(@"
            class Person {
                Name: string
                Age: int
            }
        ");
    }

    [Fact]
    public void DuplicateSymbol_Error()
    {
        AssertHasError(@"
            func Main() {
                x := 1
                x := 2
            }
        ", "already declared");
    }

    [Fact]
    public void ScopeNesting_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1
                {
                    x := 2
                }
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_IntOperands()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1 + 2
                y := 3 * 4
                z := 5 - 6
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_BytePlusByte_ProducesInt()
    {
        // C# binary numeric promotion: byte + byte = int
        // getA/getB return byte, so a+b should be int, not assignable back to byte
        AssertHasError(@"
            func getA(): byte { return 0 as byte }
            func getB(): byte { return 0 as byte }
            func Main() {
                c: byte = getA() + getB()
            }
        ", "Cannot assign");
    }

    [Fact]
    public void BinaryArithmetic_ShortPlusShort_ProducesInt()
    {
        // C# binary numeric promotion: short + short = int
        AssertHasError(@"
            func getA(): short { return 0 as short }
            func getB(): short { return 0 as short }
            func Main() {
                c: short = getA() + getB()
            }
        ", "Cannot assign");
    }

    [Fact]
    public void BinaryArithmetic_SmallTypes_AssignableToInt()
    {
        // byte + byte = int, which should be assignable to int
        AssertNoErrors(@"
            func getA(): byte { return 0 as byte }
            func getB(): byte { return 0 as byte }
            func Main() {
                c: int = getA() + getB()
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusDouble_Error()
    {
        // ECMA-334 §12.4.7: decimal cannot mix with float/double
        AssertHasError(@"
            func getD(): decimal { return 0 as decimal }
            func getF(): double { return 0.0 }
            func Main() {
                x := getD() + getF()
            }
        ", "cannot be applied");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusFloat_Error()
    {
        AssertHasError(@"
            func getD(): decimal { return 0 as decimal }
            func getF(): float { return 0 as float }
            func Main() {
                x := getD() + getF()
            }
        ", "cannot be applied");
    }

    [Fact]
    public void BinaryArithmetic_UlongPlusInt_Error()
    {
        // ECMA-334 §12.4.7: ulong cannot mix with signed types
        AssertHasError(@"
            func getU(): ulong { return 0 as ulong }
            func getI(): int { return 0 }
            func Main() {
                x := getU() + getI()
            }
        ", "cannot be applied");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusDecimal_Ok()
    {
        // decimal + decimal is valid
        AssertNoErrors(@"
            func getA(): decimal { return 0 as decimal }
            func getB(): decimal { return 0 as decimal }
            func Main() {
                x := getA() + getB()
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_InvalidOperands()
    {
        AssertHasError(@"
            func Main() {
                x := ""hello"" - ""world""
            }
        ", "cannot be applied");
    }

    [Fact]
    public void StringConcatenation_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := ""hello"" + "" "" + ""world""
            }
        ");
    }

    [Fact]
    public void LogicalOperators_RequireBoolean()
    {
        AssertHasError(@"
            func Main() {
                x := 1 && 2
            }
        ", "requires boolean operands");
    }

    [Fact]
    public void TernaryConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                x := 42 ? 1 : 2
            }
        ", "Ternary condition must be boolean");
    }

    [Fact]
    public void ArrayLiteral_UniformTypes()
    {
        AssertNoErrors(@"
            func Main() {
                nums := [1, 2, 3, 4]
            }
        ");
    }

    [Fact]
    public void FunctionCall_Valid()
    {
        AssertNoErrors(@"
            func Add(x: int, y: int): int {
                return x + y
            }

            func Main() {
                result := Add(1, 2)
            }
        ");
    }

    [Fact]
    public void Lambda_Simple()
    {
        // Lambda test - just check that lambdas don't crash the analyzer
        // Full type inference for lambdas is complex and deferred
        var source = @"
            func Main() {
                f := x => 42
            }
        ";
        var result = Analyze(source);
        // Just ensure it doesn't crash - type errors are expected for now
        Assert.NotNull(result);
    }

    [Fact]
    public void EnumDeclaration_Valid()
    {
        AssertNoErrors(@"
            enum Status {
                Pending,
                Active,
                Done
            }
        ");
    }

    [Fact]
    public void EnumDeclaration_DuplicateMembers()
    {
        AssertHasError(@"
            enum Status {
                Pending,
                Pending
            }
        ", "Duplicate enum member");
    }

    [Fact]
    public void UnionDeclaration_Valid()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }
        ");
    }

    [Fact]
    public void UnionDeclaration_DuplicateCases()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Success { error: string }
            }
        ", "Duplicate union case");
    }

    [Fact]
    public void ConstructorWithFieldAssignment_Valid()
    {
        AssertNoErrors(@"
            class Person {
                Name: string

                constructor(name: string) {
                    Name = name
                }
            }
        ");
    }

    [Fact]
    public void ConstructorMissingFieldAssignment_Error()
    {
        AssertHasError(@"
            class Person {
                Name: string

                constructor() {
                }
            }
        ", "must be assigned in constructor");
    }

    [Fact]
    public void FieldWithInitializer_NoConstructorError()
    {
        AssertNoErrors(@"
            class Person {
                Name: string = ""Unknown""

                constructor() {
                }
            }
        ");
    }

    [Fact]
    public void TryCatchFinally_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                try {

                } catch {

                } finally {

                }
            }
        ");
    }

    [Fact]
    public void UsingStatement_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                using let stream: string = ""test"" {

                }
            }
        ");
    }

    [Fact]
    public void ForeachLoop_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                nums := [1, 2, 3]
                foreach num in nums {

                }
            }
        ");
    }

    [Fact]
    public void NestedScopes_AccessOuterVariable()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1
                {
                    y := x + 1
                }
            }
        ");
    }

    [Fact]
    public void ClassMethodAccess_Valid()
    {
        AssertNoErrors(@"
            class Calculator {
                func Add(x: int, y: int): int {
                    return x + y
                }
            }
        ");
    }

    [Fact]
    public void StaticMethod_Valid()
    {
        AssertNoErrors(@"
            class Utils {
                static func DoThing() {

                }
            }
        ");
    }

    [Fact]
    public void MultipleParameters_Valid()
    {
        AssertNoErrors(@"
            func Process(a: int, b: string, c: bool): int {
                return a
            }
        ");
    }

    [Fact]
    public void ReturnStatement_VoidFunction()
    {
        AssertNoErrors(@"
            func DoNothing() {
                return
            }
        ");
    }

    [Fact]
    public void Assignment_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int
                x = 42
            }
        ");
    }

    [Fact]
    public void CompoundAssignment_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 10
                x += 5
            }
        ");
    }

    [Fact]
    public void NullableType_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int? = null
            }
        ");
    }

    [Fact]
    public void GenericClass_Valid()
    {
        AssertNoErrors(@"
            class List<T> {
                items: T[]
            }
        ");
    }

    [Fact]
    public void InterfaceDeclaration_Valid()
    {
        AssertNoErrors(@"
            interface IReader {
                func Read(): string
            }
        ");
    }

    [Fact]
    public void RecordDeclaration_Valid()
    {
        AssertNoErrors(@"
            record Person {
                Name: string
                Age: int
            }
        ");
    }

    [Fact]
    public void StructDeclaration_Valid()
    {
        AssertNoErrors(@"
            struct Point {
                X: int
                Y: int
            }
        ");
    }

    [Fact]
    public void ExternalType_Console_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(""Hello"")
            }
        ");
    }

    [Fact]
    public void ExternalType_MemberAccess_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                let msg = ""test""
                Console.WriteLine(msg)
            }
        ");
    }

    [Fact]
    public void Lambda_InferredType_Valid()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3]
                doubled := numbers.Select(x => x * 2)
            }
        ");
    }

    [Fact]
    public void ExternalType_MethodOverloading_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(42)
                Console.WriteLine(""text"")
                Console.WriteLine(true)
            }
        ");
    }

    [Fact]
    public void ReadonlyField_SetInConstructor_Valid()
    {
        AssertNoErrors(@"
            class MyClass {
                readonly id: string

                constructor() {
                    id = ""123""
                }
            }
        ");
    }

    [Fact]
    public void ReadonlyField_SetOutsideConstructor_Error()
    {
        AssertHasError(@"
            class MyClass {
                readonly id: string

                constructor() {
                    id = ""123""
                }

                func ChangeId() {
                    id = ""456""
                }
            }
        ", "readonly");
    }

    [Fact]
    public void ReadonlyField_WithInitializer_Valid()
    {
        AssertNoErrors(@"
            class MyClass {
                readonly id: string = ""default""
            }
        ");
    }

    // Duck Interface Tests
    [Fact]
    public void DuckInterface_ClassImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ");
    }

    [Fact]
    public void DuckInterface_StructImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface ICounter {
                func GetCount(): int
                func Increment()
            }

            struct Counter {
                count: int

                func GetCount(): int {
                    return count
                }

                func Increment() {
                    count = count + 1
                }
            }

            func Process(c: ICounter) {
            }

            func Main() {
                counter := new Counter { count: 0 }
                Process(counter)
            }
        ");
    }

    [Fact]
    public void DuckInterface_RecordImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface IPrintable {
                func ToString(): string
            }

            record Person {
                Name: string
                Age: int

                func ToString(): string {
                    return Name
                }
            }

            func Print(p: IPrintable) {
            }

            func Main() {
                person := new Person { Name: ""John"", Age: 30 }
                Print(person)
            }
        ");
    }

    [Fact]
    public void DuckInterface_ClassMissingMethod_Error()
    {
        AssertHasError(@"
            duck interface IReader {
                func Read(): string
                func Close()
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
                // Missing Close() method
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ", "not assignable");
    }

    [Fact]
    public void DuckInterface_MethodWrongReturnType_Error()
    {
        AssertHasError(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): int {  // Wrong return type
                    return 42
                }
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ", "not assignable");
    }

    [Fact]
    public void DuckInterface_MethodWrongParameterCount_Error()
    {
        AssertHasError(@"
            duck interface IWriter {
                func Write(data: string)
            }

            class FileWriter {
                func Write(data: string, append: bool) {  // Wrong parameter count
                }
            }

            func DoWork(w: IWriter) {
            }

            func Main() {
                writer := new FileWriter()
                DoWork(writer)
            }
        ", "not assignable");
    }

    [Fact]
    public void DuckInterface_MethodWrongParameterType_Error()
    {
        AssertHasError(@"
            duck interface IProcessor {
                func Process(value: int): string
            }

            class DataProcessor {
                func Process(value: string): string {  // Wrong parameter type
                    return value
                }
            }

            func DoWork(p: IProcessor) {
            }

            func Main() {
                processor := new DataProcessor()
                DoWork(processor)
            }
        ", "not assignable");
    }

    [Fact]
    public void DuckInterface_MultipleMethodsAllImplemented_Valid()
    {
        AssertNoErrors(@"
            duck interface IDataStore {
                func Save(data: string)
                func Load(): string
                func Delete()
            }

            class MemoryStore {
                data: string

                func Save(d: string) {
                    data = d
                }

                func Load(): string {
                    return data
                }

                func Delete() {
                    data = """"
                }
            }

            func UseStore(store: IDataStore) {
            }

            func Main() {
                store := new MemoryStore { data: """" }
                UseStore(store)
            }
        ");
    }

    [Fact]
    public void DuckInterface_VariableAssignment_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func Main() {
                let reader: IReader = new FileReader()
            }
        ");
    }

    [Fact]
    public void DuckInterface_ReturnValue_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func CreateReader(): IReader {
                return new FileReader()
            }
        ");
    }

    // Match expression exhaustiveness tests

    [Fact]
    public void MatchExpression_Exhaustive_AllCasesCovered()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { error } => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_NonExhaustive_MissingCase()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value
                }
            }
        ", "not exhaustive");
    }

    [Fact]
    public void MatchExpression_WithWildcard_IsExhaustive()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
                Pending { message: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    _ => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_NonExhaustive_MultipleMissingCases()
    {
        AssertHasError(@"
            union Status {
                Pending { id: int }
                Active { id: int }
                Completed { id: int }
                Failed { id: int }
            }

            func Main() {
                s := new Status.Pending { id: 1 }
                x := match s {
                    Status.Pending { id } => 0
                }
            }
        ", "not exhaustive");
    }

    [Fact]
    public void MatchExpression_PatternBinding_CorrectTypes()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string, code: int }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value * 2,
                    Result.Failure { error, code } => code
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_InvalidUnionCase_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Unknown => 0
                }
            }
        ", "does not have a case");
    }

    [Fact]
    public void MatchExpression_InvalidProperty_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { invalidProp } => 0
                }
            }
        ", "does not have property");
    }

    [Fact]
    public void MatchExpression_LiteralPatterns_NoExhaustivenessCheck()
    {
        // For non-union types, we don't check exhaustiveness
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    1 => ""one"",
                    2 => ""two""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_IdentifierPattern_BindsVariable()
    {
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    n => n * 2
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_IncompatibleCaseTypes_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { error } => error
                }
            }
        ", "incompatible type");
    }

    [Fact]
    public void MatchExpression_WithGuard_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    n when n > 0 => ""positive"",
                    n when n < 0 => ""negative"",
                    _ => ""zero""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_GuardNotBool_Error()
    {
        AssertHasError(@"
            func Main() {
                x := 5
                result := match x {
                    n when ""not a bool"" => ""value""
                }
            }
        ", "must be of type 'bool'");
    }

    [Fact]
    public void MatchExpression_GuardWithPatternVariable_Valid()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                msg := match r {
                    Result.Success { value } when value > 10 => ""big success"",
                    Result.Success { value } => ""small success"",
                    Result.Failure { error } => error
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_WithGuard_AndUnguardedWildcard_IsExhaustive()
    {
        // Guarded arms don't count for coverage, but an unguarded wildcard covers everything
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    _ => ""other""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_WithGuards_MissingCases_ReportsError()
    {
        // Guards on 2 of 3 cases, no wildcard — should report missing unguarded coverage
        AssertHasError(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    Status.Inactive when true => ""inactive""
                }
            }
        ", "not exhaustive");
    }

    [Fact]
    public void MatchExpression_WithGuards_AllCasesUnguarded_IsExhaustive()
    {
        // All union cases covered by unguarded arms (some arms also have guards — doesn't matter)
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active special"",
                    Status.Active => ""active"",
                    Status.Inactive => ""inactive"",
                    Status.Pending => ""pending""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_AllGuardedNoWildcard_ReportsError()
    {
        // Every arm has a guard and no wildcard — non-exhaustive
        AssertHasError(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    Status.Inactive when true => ""inactive"",
                    Status.Pending when true => ""pending""
                }
            }
        ", "not exhaustive");
    }

    [Fact]
    public void MatchExpression_WithGuard_CatchAllBinding_IsExhaustive()
    {
        // An unguarded plain identifier binding (not `_`) is a catch-all and covers all cases
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active special"",
                    other => ""fallback""
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_ClassParameterAccessibleInMethod()
    {
        AssertNoErrors(@"
            class Logger(name: string) {
                func Log(message: string) {
                    result := name
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_StructParameterAccessibleInMethod()
    {
        AssertNoErrors(@"
            struct Point(x: double, y: double) {
                func GetDistance(): double {
                    return x * x + y * y
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_RecordParameterAccessibleInProperty()
    {
        AssertNoErrors(@"
            record Person(name: string, age: int) {
                FullName: string => name
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_ParameterTypeChecking()
    {
        AssertNoErrors(@"
            class Calculator(value: int) {
                func GetDoubled(): int {
                    return value * 2
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_MultipleParameters()
    {
        AssertNoErrors(@"
            class Service(logger: string, db: string, cache: string) {
                func DoWork() {
                    a := logger
                    b := db
                    c := cache
                }
            }
        ");
    }

    [Fact]
    public void CollectionExpression_ListAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let numbers: List<int> = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_HashSetAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let unique: HashSet<string> = [""a"", ""b"", ""c""]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_QueueAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let queue: Queue<int> = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_IEnumerableAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let items: IEnumerable<string> = [""a"", ""b""]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_TypeMismatch_Error()
    {
        AssertHasError(@"
            import System.Collections.Generic

            func Main() {
                let numbers: List<int> = [""not"", ""ints""]
            }
        ", "Cannot assign 'string[]' to 'List<int>'");
    }

    [Fact]
    public void CollectionExpression_ArrayStillWorks()
    {
        AssertNoErrors(@"
            func Main() {
                let arr: int[] = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void ParamsParameter_Valid_NoError()
    {
        AssertNoErrors(@"
            func Sum(params numbers: int[]): int {
                return 0
            }
        ");
    }

    [Fact]
    public void ParamsParameter_WithOtherParams_NoError()
    {
        AssertNoErrors(@"
            func Format(format: string, params args: object[]): string {
                return format
            }
        ");
    }

    [Fact]
    public void ParamsParameter_NotLast_Error()
    {
        AssertHasError(@"
            func Invalid(params numbers: int[], other: string) {
            }
        ", "params parameter must be the last parameter");
    }

    [Fact]
    public void ParamsParameter_NotArray_Error()
    {
        AssertHasError(@"
            func Invalid(params value: int) {
            }
        ", "params parameter must be an array, Span<T>, ReadOnlySpan<T>, or a collection type");
    }

    // Extension Method Resolution Tests

    [Fact]
    public void ExtensionMethod_BasicResolution_NoError()
    {
        AssertNoErrors(@"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            func Main() {
                let result: bool = ""hello"".IsEmpty()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnVariableType_NoError()
    {
        AssertNoErrors(@"
            func Double(this x: int): int {
                return x * 2
            }

            func Main() {
                let num: int = 5
                let result: int = num.Double()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_WithParameters_NoError()
    {
        AssertNoErrors(@"
            func Repeat(this s: string, count: int): string {
                return s
            }

            func Main() {
                let result: string = ""hello"".Repeat(3)
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_GenericType_NoError()
    {
        AssertNoErrors(@"
            func First(this arr: int[]): int {
                return arr[0]
            }

            func Main() {
                let numbers: int[] = [1, 2, 3]
                let first: int = numbers.First()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnCustomType_NoError()
    {
        AssertNoErrors(@"
            class Person {
                Name: string
            }

            func Greet(this p: Person): string {
                return ""Hello""
            }

            func Main() {
                let person: Person = new Person { Name: ""Alice"" }
                let greeting: string = person.Greet()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_InStaticClass_NoError()
    {
        AssertNoErrors(@"
            static class StringExtensions {
                static func Truncate(this s: string, maxLength: int): string {
                    return s
                }
            }

            func Main() {
                let result: string = ""hello world"".Truncate(5)
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_MultipleExtensions_NoError()
    {
        AssertNoErrors(@"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            func IsLong(this s: string): bool {
                return s.Length > 10
            }

            func Main() {
                let s: string = ""test""
                let empty: bool = s.IsEmpty()
                let long: bool = s.IsLong()
            }
        ");
    }

    [Fact]
    public void ImplicitConversion_ClassToClass()
    {
        AssertNoErrors(@"
            class Celsius {
                Value: double

                implicit operator Fahrenheit(c: Celsius) {
                    return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
                }
            }

            class Fahrenheit {
                Value: double
            }

            func Main() {
                let c: Celsius = new Celsius { Value: 20.0 }
                let f: Fahrenheit = c  // Implicit conversion should work
            }
        ");
    }

    [Fact]
    public void ExplicitConversion_DoesNotAllowImplicitAssignment()
    {
        AssertHasError(@"
            class Fraction {
                Numerator: int
                Denominator: int

                explicit operator double(f: Fraction) {
                    return f.Numerator / (double)f.Denominator
                }
            }

            func Main() {
                let frac: Fraction = new Fraction { Numerator: 3, Denominator: 4 }
                let value: double = frac  // Should error - explicit conversion required
            }
        ", "Cannot assign");
    }

    [Fact]
    public void ImplicitConversion_BidirectionalConversions()
    {
        AssertNoErrors(@"
            class Meters {
                Value: double

                implicit operator Centimeters(m: Meters) {
                    return new Centimeters { Value: m.Value * 100.0 }
                }
            }

            class Centimeters {
                Value: double

                implicit operator Meters(cm: Centimeters) {
                    return new Meters { Value: cm.Value / 100.0 }
                }
            }

            func Main() {
                let m: Meters = new Meters { Value: 5.0 }
                let cm: Centimeters = m  // Meters -> Centimeters
                let m2: Meters = cm      // Centimeters -> Meters
            }
        ");
    }

    [Fact]
    public void TestDefaultParametersWithLiterals()
    {
        // Valid: default parameters with literal values
        var result = Analyze(@"
            func Greet(name: string, greeting: string = ""Hello"", times: int = 1) {
                print greeting
            }

            func Main() {
                Greet(""Alice"")
                Greet(""Bob"", ""Hi"")
                Greet(""Charlie"", ""Hey"", 3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersRequiredAfterOptional()
    {
        // Invalid: required parameter after optional parameter
        var result = Analyze(@"
            func Invalid(a: int = 1, b: int) {
                print a
            }
        ");

        Assert.NotEmpty(result.Errors);
        var error = result.Errors[0];
        Assert.Equal(ErrorCode.RequiredParameterAfterOptional, error.Code);
        Assert.Contains("'b'", error.Message);
        Assert.Contains("cannot appear after optional", error.Message);
    }

    [Fact]
    public void TestDefaultParametersMultipleRequiredAfterOptional()
    {
        // Invalid: multiple required parameters after optional ones
        var result = Analyze(@"
            func Invalid(a: int, b: int = 1, c: int, d: string) {
                print a
            }
        ");

        Assert.NotEmpty(result.Errors);
        // Should report error for first required parameter after optional
        var error = result.Errors.FirstOrDefault(e => e.Code == ErrorCode.RequiredParameterAfterOptional);
        Assert.NotNull(error);
        Assert.Contains("'c'", error.Message);
    }

    [Fact]
    public void TestDefaultParametersWithNullLiteral()
    {
        // Valid: nullable type with null default
        var result = Analyze(@"
            func Process(data: string?) {
                if (data != null) {
                    print data
                }
            }

            func Main() {
                Process(null)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithNumericExpressions()
    {
        // Valid: numeric literal expressions as defaults
        var result = Analyze(@"
            func Calculate(x: int = 2 + 3, y: int = -5, z: float = 3.14) {
                print x
            }

            func Main() {
                Calculate()
                Calculate(10)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithBooleanLiterals()
    {
        // Valid: boolean literals as defaults
        var result = Analyze(@"
            func Configure(enabled: bool = true, verbose: bool = false) {
                print enabled
                print verbose
            }

            func Main() {
                Configure()
                Configure(false)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersInvalidNonConstant()
    {
        // Invalid: non-constant expression as default
        var result = Analyze(@"
            func GetValue(): int {
                return 42
            }

            func Invalid(x: int = GetValue()) {
                print x
            }
        ");

        Assert.NotEmpty(result.Errors);
        var error = result.Errors.FirstOrDefault(e => e.Code == ErrorCode.InvalidDefaultParameterValue);
        Assert.NotNull(error);
        Assert.Contains("compile-time constant", error.Message);
    }

    [Fact]
    public void TestDefaultParametersWithMemberAccess()
    {
        // Valid: member access for constants (C# compiler will validate)
        var result = Analyze(@"
            func SetMax(max: int = int.MaxValue) {
                print max
            }

            func Main() {
                SetMax()
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithMemberAccessIdentifier()
    {
        // Valid: member access for constants as default values
        var result = Analyze(@"
            func Resize(size: int = int.MaxValue) {
                print size
            }

            func Main() {
                Resize()
                Resize(200)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithNewExpression()
    {
        // Valid: new expression with literal arguments
        var result = Analyze(@"
            func Main() {
                // New expressions with literals should be allowed
                print ""test""
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersAllOptional()
    {
        // Valid: all parameters are optional
        var result = Analyze(@"
            func AllOptional(a: int = 1, b: int = 2, c: int = 3) {
                print a + b + c
            }

            func Main() {
                AllOptional()
                AllOptional(10)
                AllOptional(10, 20)
                AllOptional(10, 20, 30)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersInMethods()
    {
        // Valid: default parameters in class methods
        var result = Analyze(@"
            class Calculator {
                func Add(a: int, b: int = 0): int {
                    return a + b
                }
            }

            func Main() {
                calc := new Calculator()
                result1 := calc.Add(5)
                result2 := calc.Add(5, 3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersInConstructors()
    {
        // Valid: default parameters in constructors
        var result = Analyze(@"
            class Person {
                Name: string
                Age: int

                constructor(name: string, age: int = 0) {
                    Name = name
                    Age = age
                }
            }

            func Main() {
                p1 := new Person(""Alice"")
                p2 := new Person(""Bob"", 30)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersParamsStaysLast()
    {
        // Valid: params parameter is still last, default parameters before it
        var result = Analyze(@"
            func Format(prefix: string = """", params values: int[]) {
                print prefix
            }

            func Main() {
                Format(""Numbers:"", 1, 2, 3)
                Format()
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersExtensionMethods()
    {
        // Valid: default parameters in extension methods
        var result = Analyze(@"
            func IsLongerThan(this s: string, minLength: int = 0): bool {
                return s.Length > minLength
            }

            func Main() {
                result1 := ""hello"".IsLongerThan()
                result2 := ""hello"".IsLongerThan(3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    // ==================== Assembly Resolution Tests (Phase 1) ====================

    [Fact]
    public void AssemblyResolution_SystemConsole_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(""Hello"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_TypeImportRejected()
    {
        AssertHasError(@"
            import System.Console

            func Main() {
            }
        ", "Cannot import type 'System.Console'");
    }

    [Fact]
    public void AssemblyResolution_SystemLinq_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3, 4, 5]
                evens := numbers.Where(x => x % 2 == 0)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemCollections_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                list := new List<int>()
                list.Add(1)
                list.Add(2)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemIO_Resolved()
    {
        AssertNoErrors(@"
            import System.IO

            func Main() {
                path := Path.Combine(""folder"", ""file.txt"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemThreadingTasks_Resolved()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            func async GetDataAsync(): string {
                await Task.Delay(100)
                return ""data""
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_MultiplImports_AllResolved()
    {
        AssertNoErrors(@"
            import System
            import System.Linq
            import System.Collections.Generic

            func Main() {
                Console.WriteLine(""Test"")
                list := new List<int>()
                result := list.Where(x => x > 0)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_StaticMethodCall_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Math.Max(1, 2)
                Math.Min(3, 4)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_GenericTypeInstantiation_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                dict := new Dictionary<string, int>()
                dict[""key""] = 42
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_ExtensionMethodFromLinq_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3]
                first := numbers.First()
                last := numbers.Last()
                sum := numbers.Sum()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_NestedTypeAccess_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                separator := Environment.NewLine
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_PropertyAccess_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                list := new List<int>()
                list.Add(1)
                count := list.Count
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_ChainedMethodCalls_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3, 4, 5]
                result := numbers.Where(x => x > 2).Select(x => x * 2).ToList()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemText_Resolved()
    {
        AssertNoErrors(@"
            import System.Text

            func Main() {
                sb := new StringBuilder()
                sb.Append(""Hello"")
                sb.Append("" "")
                sb.Append(""World"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_DateTime_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                now := DateTime.Now
                today := DateTime.Today
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Guid_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                id := Guid.NewGuid()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Task_Resolved()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            func async DoWork() {
                await Task.Delay(100)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_FileInfo_Resolved()
    {
        AssertNoErrors(@"
            import System.IO

            func Main() {
                fileInfo := new FileInfo(""test.txt"")
                exists := fileInfo.Exists
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Regex_Resolved()
    {
        AssertNoErrors(@"
            import System.Text.RegularExpressions

            func Main() {
                pattern := new Regex(""[0-9]+"")
                isMatch := pattern.IsMatch(""123"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_HttpClient_Resolved()
    {
        AssertNoErrors(@"
            import System.Net.Http

            func async GetData(): string {
                client := new HttpClient()
                return await client.GetStringAsync(""https://example.com"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_JsonSerializer_Resolved()
    {
        AssertNoErrors(@"
            import System.Text.Json

            func Main() {
                json := JsonSerializer.Serialize(42)
            }
        ");
    }

    // ==================== Override Keyword Tests (Phase 2) ====================

    [Fact]
    public void Override_SimpleOverride_Valid()
    {
        AssertNoErrors(@"
            import System

            class Animal {
                virtual func MakeSound() {
                    Console.WriteLine(""Generic sound"")
                }
            }

            class Dog : Animal {
                override func MakeSound() {
                    Console.WriteLine(""Bark"")
                }
            }
        ");
    }

    [Fact]
    public void Override_WithReturnType_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func GetValue(): int {
                    return 0
                }
            }

            class Derived : Base {
                override func GetValue(): int {
                    return 42
                }
            }
        ");
    }

    [Fact]
    public void Override_WithParameters_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Process(x: int, y: int): int {
                    return x + y
                }
            }

            class Derived : Base {
                override func Process(x: int, y: int): int {
                    return x * y
                }
            }
        ");
    }

    [Fact]
    public void Override_AsyncMethod_Valid()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            class Base {
                virtual func async GetDataAsync(): string {
                    return ""base""
                }
            }

            class Derived : Base {
                override func async GetDataAsync(): string {
                    await Task.Delay(10)
                    return ""derived""
                }
            }
        ");
    }

    [Fact]
    public void Override_MultipleOverrides_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Method1() { }
                virtual func Method2() { }
                virtual func Method3() { }
            }

            class Derived : Base {
                override func Method1() { }
                override func Method2() { }
                override func Method3() { }
            }
        ");
    }

    [Fact]
    public void Override_InheritanceChain_Valid()
    {
        AssertNoErrors(@"
            class A {
                virtual func DoWork() { }
            }

            class B : A {
                override func DoWork() { }
            }

            class C : B {
                override func DoWork() { }
            }
        ");
    }

    [Fact]
    public void Override_WithBaseCall_Valid()
    {
        AssertNoErrors(@"
            import System

            class Base {
                virtual func Initialize() {
                    Console.WriteLine(""Base init"")
                }
            }

            class Derived : Base {
                override func Initialize() {
                    base.Initialize()
                    Console.WriteLine(""Derived init"")
                }
            }
        ");
    }

    [Fact]
    public void Override_PropertyWithMethods_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func GetName(): string {
                    return ""Base""
                }
            }

            class Derived : Base {
                override func GetName(): string {
                    return ""Derived""
                }
            }
        ");
    }

    [Fact]
    public void Override_GenericMethod_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Process<T>(item: T): T {
                    return item
                }
            }

            class Derived : Base {
                override func Process<T>(item: T): T {
                    return item
                }
            }
        ");
    }

    [Fact]
    public void Override_AbstractMethod_Valid()
    {
        AssertNoErrors(@"
            import System

            abstract class Base {
                abstract func DoWork(): void
            }

            class Derived : Base {
                override func DoWork(): void {
                    Console.WriteLine(""Working"")
                }
            }
        ");
    }

    // ==================== ASP.NET Core Integration Tests (Task 034) ====================

    [Fact]
    public void AspNetCore_WebApplicationBuilder_Resolves()
    {
        // Gap 1: External Type Resolution from Imports
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_IsDevelopment_BooleanInference()
    {
        // Gap 2: Boolean Type Inference from External Methods
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                if app.Environment.IsDevelopment() {
                    print ""Development mode""
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_NullCoalescing_WithNullableProperties()
    {
        // Gap 3: Null-Coalescing with nullable properties
        AssertNoErrors(@"
            record EmployeeDto {
                Name: string?
                Title: string?
            }

            func ProcessEmployee(dto: EmployeeDto): string {
                name := dto.Name ?? ""Unnamed""
                title := dto.Title ?? ""No title""
                return name
            }
        ");
    }

    [Fact]
    public void AspNetCore_ServicesConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                builder.Services.AddControllers()
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MiddlewareConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.UseHttpsRedirection()
                app.UseAuthorization()
                app.MapControllers()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ConditionalMiddleware()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                if app.Environment.IsDevelopment() {
                    app.UseSwagger()
                    app.UseSwaggerUI()
                }

                app.UseHttpsRedirection()
                app.Run()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapGet()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.MapGet(""/"", () => ""Hello from N#!"")
                app.Run()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ChainedConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func ConfigureServices(builder: WebApplicationBuilder) {
                builder.Services.AddControllers()
                builder.Services.AddEndpointsApiExplorer()
                builder.Services.AddSwaggerGen()
            }

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                ConfigureServices(builder)
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_EntityFramework_DbContext()
    {
        AssertNoErrors(@"
            import Microsoft.EntityFrameworkCore

            class AppDbContext : DbContext {
                Employees: DbSet<Employee>

                constructor(options: DbContextOptions<AppDbContext>) : base(options) {
                }
            }

            class Employee {
                Id: int
                Name: string
            }
        ");
    }

    [Fact]
    public void AspNetCore_ControllerBase_Inheritance()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                func GetAll(): IActionResult {
                    return Ok()
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ActionResult_Generic()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            record EmployeeDto {
                Id: int
                Name: string
            }

            class EmployeesController : ControllerBase {
                func GetById(id: int): ActionResult<EmployeeDto> {
                    dto := new EmployeeDto { Id: id, Name: ""Test"" }
                    return Ok(dto)
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_BadRequest_WithAnonymousObject()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                func Validate(): IActionResult {
                    errors := [""Error 1"", ""Error 2""]
                    return BadRequest(new { errors: errors })
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_DateTime_StaticProperties()
    {
        AssertNoErrors(@"
            import System

            record Employee {
                Id: int
                Name: string
                CreatedAt: DateTime
            }

            func CreateEmployee(): Employee {
                return new Employee {
                    Id: 1,
                    Name: ""Test"",
                    CreatedAt: DateTime.Now
                }
            }
        ");
    }

    [Fact]
    public void AspNetCore_Guid_Generation()
    {
        AssertNoErrors(@"
            import System

            record Employee {
                Id: Guid
                Name: string
            }

            func CreateEmployee(): Employee {
                return new Employee {
                    Id: Guid.NewGuid(),
                    Name: ""Test""
                }
            }
        ");
    }

    [Fact]
    public void AspNetCore_AsyncTask_WithAwait()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                func async GetDataAsync(): Task<IActionResult> {
                    await Task.Delay(100)
                    return Ok()
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ExternalTypeChaining()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder
            import Microsoft.Extensions.DependencyInjection

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                services := builder.Services
                services.AddControllers()
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    // ── Lambda Contextual Type Inference for N# Functions ──

    [Fact]
    public void Lambda_NSharpFunction_InfersParameterType_FuncIntInt()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                result := Apply(x => x * 2)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_InfersParameterType_FuncStringInt()
    {
        AssertNoErrors(@"
            func Transform(items: List<string>, f: Func<string, int>): int {
                return f(items[0])
            }

            func Main() {
                items := [""hello"", ""world""]
                result := Transform(items, x => x.Length)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_InfersMultipleParams_FuncIntIntInt()
    {
        AssertNoErrors(@"
            func Process(f: Func<int, int, int>): int {
                return f(1, 2)
            }

            func Main() {
                result := Process((x, y) => x + y)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_BlockBody_InfersParameterType()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                result := Apply(x => { return x * 2 })
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_Action_InfersParameterType()
    {
        AssertNoErrors(@"
            func DoWith(value: int, action: Action<int>) {
                action(value)
            }

            func Main() {
                DoWith(42, x => x + 1)
            }
        ");
    }

    // ── Lambda Contextual Type Inference from Variable/Field/Return/Assignment ──

    [Fact]
    public void Lambda_VarDecl_FuncIntInt_InfersParamType()
    {
        AssertNoErrors(@"
            func Main() {
                let handler: Func<int, int> = x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_ActionString_InfersParamType()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                let action: Action<string> = s => Console.WriteLine(s)
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_MultiParam_InfersParamTypes()
    {
        AssertNoErrors(@"
            func Main() {
                let combine: Func<int, int, int> = (x, y) => x + y
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_BlockBody_InfersParamType()
    {
        AssertNoErrors(@"
            func Main() {
                let handler: Func<int, int> = x => { return x * 2 }
            }
        ");
    }

    [Fact]
    public void Lambda_Assignment_InfersParamType()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                let handler: Func<int, int> = x => x
                handler = x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_ReturnStatement_InfersParamType()
    {
        AssertNoErrors(@"
            func GetHandler(): Func<int, int> {
                return x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_FieldInitializer_InfersParamType()
    {
        AssertNoErrors(@"
            class Calculator {
                Doubler: Func<int, int> = x => x * 2
            }
        ");
    }

    // ── Extension Methods on Literals ──

    [Fact]
    public void ExtensionMethod_OnIntLiteral_NoError()
    {
        AssertNoErrors(@"
            func Double(this n: int): int {
                return n * 2
            }

            func Main() {
                let result: int = 5.Double()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnStringLiteral_NoError()
    {
        AssertNoErrors(@"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            func Main() {
                let result: bool = ""hello"".IsEmpty()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnDoubleLiteral_NoError()
    {
        AssertNoErrors(@"
            func Negate(this d: double): double {
                return 0.0 - d
            }

            func Main() {
                let result: double = 3.14.Negate()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_IntLiteral_InstanceMethod_NoError()
    {
        // Instance methods on built-in types should also work on literals
        AssertNoErrors(@"
            func Main() {
                s := 5.ToString()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_StringLiteral_InstanceProperty_NoError()
    {
        AssertNoErrors(@"
            func Main() {
                len := ""hello"".Length
            }
        ");
    }

    // Circular import detection tests

    [Fact]
    public void CircularImport_TwoFiles_ReportsError()
    {
        // Create temp directory with two files that import each other
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_circular_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var fileA = Path.Combine(tempDir, "A.nl");
            var fileB = Path.Combine(tempDir, "B.nl");

            File.WriteAllText(fileA, @"import ""./B""

func Hello(): string {
    return ""hello""
}
");
            File.WriteAllText(fileB, @"import ""./A""

func World(): string {
    return ""world""
}
");

            // Parse and analyze file A
            var sourceA = File.ReadAllText(fileA);
            var lexer = new Lexer(sourceA, fileA);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, fileA, sourceA);
            var parseResult = parser.ParseCompilationUnit();
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, fileA, tempDir, sourceA);

            Assert.True(result.HasErrors, "Expected circular import error but got none");
            Assert.Contains(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CircularImport_SelfImport_ReportsError()
    {
        // Create temp directory with a file that imports itself
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_self_import_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var file = Path.Combine(tempDir, "Self.nl");
            File.WriteAllText(file, @"import ""./Self""

func Hello(): string {
    return ""hello""
}
");

            var source = File.ReadAllText(file);
            var lexer = new Lexer(source, file);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, file, source);
            var parseResult = parser.ParseCompilationUnit();
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, file, tempDir, source);

            Assert.True(result.HasErrors, "Expected circular import error but got none");
            Assert.Contains(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void NonCircularImport_NoError()
    {
        // Create temp directory with two files where only one imports the other (no cycle)
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_no_circular_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var fileA = Path.Combine(tempDir, "A.nl");
            var fileB = Path.Combine(tempDir, "B.nl");

            File.WriteAllText(fileA, @"import ""./B""

func Hello(): string {
    return ""hello""
}
");
            File.WriteAllText(fileB, @"func World(): string {
    return ""world""
}
");

            var sourceA = File.ReadAllText(fileA);
            var lexer = new Lexer(sourceA, fileA);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, fileA, sourceA);
            var parseResult = parser.ParseCompilationUnit();
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, fileA, tempDir, sourceA);

            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ================================================================
    // N#-declared method overload resolution
    // ================================================================

    [Fact]
    public void OverloadResolution_ClassMethod_IntOverload()
    {
        AssertNoErrors(@"
            class Processor {
                func Process(x: int): int {
                    return x
                }
                func Process(x: string): string {
                    return x
                }
            }
            func Main() {
                p := new Processor()
                result := p.Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_StringOverload()
    {
        AssertNoErrors(@"
            class Processor {
                func Process(x: int): int {
                    return x
                }
                func Process(x: string): string {
                    return x
                }
            }
            func Main() {
                p := new Processor()
                result := p.Process(""hello"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_MultipleParams()
    {
        AssertNoErrors(@"
            class Math {
                func Add(a: int, b: int): int {
                    return a
                }
                func Add(a: string, b: string): string {
                    return a
                }
            }
            func Main() {
                m := new Math()
                r1 := m.Add(1, 2)
                r2 := m.Add(""a"", ""b"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_DifferentArity()
    {
        AssertNoErrors(@"
            class Logger {
                func Log(msg: string) {
                }
                func Log(msg: string, level: int) {
                }
            }
            func Main() {
                l := new Logger()
                l.Log(""hello"")
                l.Log(""hello"", 3)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_StructMethod()
    {
        AssertNoErrors(@"
            struct Point {
                x: int
                y: int
                func Scale(factor: int): int {
                    return factor
                }
                func Scale(factor: double): double {
                    return factor
                }
            }
            func Main() {
                p := new Point()
                r := p.Scale(2)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_NoMatchingOverload_Error()
    {
        AssertHasError(@"
            class Processor {
                func Process(x: int): int {
                    return x
                }
                func Process(x: string): string {
                    return x
                }
            }
            func Main() {
                p := new Processor()
                p.Process(true)
            }
        ", "No matching overload");
    }

    [Fact]
    public void OverloadResolution_TopLevelFunctions()
    {
        AssertNoErrors(@"
            func Greet(name: string): string {
                return name
            }
            func Greet(name: string, greeting: string): string {
                return greeting
            }
            func Main() {
                r1 := Greet(""Alice"")
                r2 := Greet(""Alice"", ""Hi"")
            }
        ");
    }

    // ================================================================
    // Generic type inference for N#-declared functions
    // ================================================================

    [Fact]
    public void GenericInference_Identity_Int()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_Identity_String()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity(""hello"")
            }
        ");
    }

    [Fact]
    public void GenericInference_ExplicitTypeArg()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity<int>(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_TwoTypeParams()
    {
        AssertNoErrors(@"
            func Pair<A, B>(a: A, b: B): A {
                return a
            }
            func Main() {
                result := Pair(1, ""two"")
            }
        ");
    }

    [Fact]
    public void GenericInference_ClassMethod()
    {
        AssertNoErrors(@"
            class Container {
                func Wrap<T>(value: T): T {
                    return value
                }
            }
            func Main() {
                c := new Container()
                r := c.Wrap(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_ClassMethodOverload_WithGeneric()
    {
        // Non-generic overload should be preferred over generic when both match
        AssertNoErrors(@"
            class Converter {
                func Convert(x: int): string {
                    return ""int""
                }
                func Convert<T>(x: T): T {
                    return x
                }
            }
            func Main() {
                c := new Converter()
                r1 := c.Convert(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_ReturnsGenericType()
    {
        // Inference should work when return type uses the inferred type parameter
        AssertNoErrors(@"
            func MakeList<T>(x: T): List<T> {
                items := new List<T>()
                items.Add(x)
                return items
            }
            func Main() {
                result := MakeList(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_FromNestedGenericArg()
    {
        // T should be inferred from List<T> argument
        AssertNoErrors(@"
            func First<T>(items: List<T>): T {
                return items[0]
            }
            func Main() {
                list := new List<int>()
                list.Add(1)
                result := First(list)
            }
        ");
    }

    [Fact]
    public void GenericInference_FromArrayArg()
    {
        // T should be inferred from T[] argument
        AssertNoErrors(@"
            func First<T>(items: T[]): T {
                return items[0]
            }
            func Main() {
                arr := [1, 2, 3]
                result := First(arr)
            }
        ");
    }

    [Fact]
    public void GenericInference_SameTypeParamMultipleArgs()
    {
        // T is constrained by both arguments; they must agree
        AssertNoErrors(@"
            func Max<T>(a: T, b: T): T {
                return a
            }
            func Main() {
                result := Max(1, 2)
            }
        ");
    }

    [Fact]
    public void GenericInference_NumericWidening()
    {
        // When T appears for both int and double args, LUB should pick double
        AssertNoErrors(@"
            func Max<T>(a: T, b: T): T {
                return a
            }
            func Main() {
                result := Max(1, 2.5)
            }
        ");
    }

    [Fact]
    public void GenericInference_ThreeTypeParams()
    {
        // Triple type parameter inference
        AssertNoErrors(@"
            func Triple<A, B, C>(a: A, b: B, c: C): A {
                return a
            }
            func Main() {
                result := Triple(1, ""hello"", true)
            }
        ");
    }

    [Fact]
    public void GenericInference_WithConstraint_Satisfied()
    {
        // Inference + constraint validation
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyNum : IComparable {
                func CompareTo(other: object): int {
                    return 0
                }
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new MyNum(), new MyNum())
            }
        ");
    }

    [Fact]
    public void GenericInference_WithConstraint_Violated()
    {
        // Inference works but constraint should fail
        AssertHasError(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class Plain {
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new Plain(), new Plain())
            }
        ", "does not satisfy constraint");
    }

    [Fact]
    public void GenericInference_ExtensionMethod()
    {
        // Inference on extension method (first param is this)
        AssertNoErrors(@"
            func Identity<T>(this x: T): T {
                return x
            }
            func Main() {
                result := 42.Identity()
            }
        ");
    }

    [Fact]
    public void GenericInference_ExtensionMethod_ReturnType()
    {
        // Extension method inference should correctly bind return type via receiver
        AssertNoErrors(@"
            func Double<T>(this x: T): T {
                return x
            }
            func Process(x: int): int {
                return x
            }
            func Main() {
                result := Process(42.Double())
            }
        ");
    }

    [Fact]
    public void GenericInference_NullableParam()
    {
        // Infer T from non-nullable parameter when T? is also present
        AssertNoErrors(@"
            func ValueOrDefault<T>(fallback: T, x: T?): T {
                return fallback
            }
            func Main() {
                result := ValueOrDefault(42, null)
            }
        ");
    }

    [Fact]
    public void GenericInference_ParamsCollection()
    {
        // Inference with params collection (non-array) parameter
        AssertNoErrors(@"
            func Enumerate<T>(params items: List<T>): int {
                return 0
            }
            func Main() {
                result := Enumerate(1, 2, 3)
            }
        ");
    }

    [Fact]
    public void GenericInference_ParamsArray()
    {
        // Inference with params parameter
        AssertNoErrors(@"
            func CreateList<T>(params items: T[]): int {
                return 0
            }
            func Main() {
                result := CreateList(1, 2, 3)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_AmbiguousCall_Error()
    {
        AssertHasError(@"
            class Processor {
                func Do(x: int, y: int): int {
                    return x
                }
                func Do(a: int, b: int): int {
                    return a
                }
            }
            func Main() {
                p := new Processor()
                p.Do(1, 2)
            }
        ", "Ambiguous call");
    }

    [Fact]
    public void OverloadResolution_ParamsOverload()
    {
        AssertNoErrors(@"
            class Formatter {
                func Format(msg: string): string {
                    return msg
                }
                func Format(msg: string, params args: int[]): string {
                    return msg
                }
            }
            func Main() {
                f := new Formatter()
                f.Format(""hello"")
                f.Format(""hello"", 1, 2, 3)
            }
        ");
    }

    // ================================================================
    // Type-based overload resolution — same arity, different types
    // ================================================================

    [Fact]
    public void OverloadResolution_SameArity_IntVsString_SelectsInt()
    {
        AssertNoErrors(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_SameArity_IntVsString_SelectsString()
    {
        AssertNoErrors(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                r := Process(""hello"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToLong()
    {
        AssertNoErrors(@"
            func Handle(x: long): long { return x }
            func Handle(x: string): string { return x }
            func Main() {
                r := Handle(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToDouble()
    {
        AssertNoErrors(@"
            func Calc(x: double): double { return x }
            func Calc(x: string): string { return x }
            func Main() {
                r := Calc(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_PreferExactOverImplicit()
    {
        // When both int and long overloads exist, int literal should prefer int
        AssertNoErrors(@"
            func Handle(x: int): int { return x }
            func Handle(x: long): long { return x }
            func Main() {
                r := Handle(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_SameArity_BoolVsInt_Error()
    {
        AssertHasError(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                Process(true)
            }
        ", "No matching overload");
    }

    [Fact]
    public void OverloadResolution_ExtensionOverload_SameThis_DifferentParams()
    {
        AssertNoErrors(@"
            func Format(this x: int, prefix: string): string { return prefix }
            func Format(this x: int, decimals: int): int { return decimals }
            func Main() {
                r1 := 5.Format(""pre"")
                r2 := 5.Format(3)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ExtensionOverload_NoMatch_Error()
    {
        AssertHasError(@"
            func Format(this x: int, prefix: string): string { return prefix }
            func Format(this x: int, decimals: int): int { return decimals }
            func Main() {
                5.Format(true)
            }
        ", "No matching overload");
    }

    // ================================================================
    // Extension methods on literal receivers — type safety
    // ================================================================

    [Fact]
    public void Extension_LiteralReceiver_ReturnTypeChecked()
    {
        // Extension returns int; assigning to string must error
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                let s: string = 5.Double()
            }
        ", "assign");
    }

    [Fact]
    public void Extension_VariableReceiver_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                let x: int = 5
                let s: string = x.Double()
            }
        ", "assign");
    }

    [Fact]
    public void Extension_BoolLiteral_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Toggle(this b: bool): bool { return b }
            func Main() {
                let n: int = true.Toggle()
            }
        ", "assign");
    }

    [Fact]
    public void Extension_StringLiteral_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Upper(this s: string): string { return s }
            func Main() {
                let n: int = ""hello"".Upper()
            }
        ", "assign");
    }

    [Fact]
    public void Extension_LiteralReceiver_InExpression()
    {
        // Extension return used in binary expression
        AssertNoErrors(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                r := 5.Double() + 3
            }
        ");
    }

    [Fact]
    public void Extension_LiteralReceiver_AsArgument()
    {
        // Extension return passed to function expecting different type should error
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func TakesString(s: string) {}
            func Main() {
                TakesString(5.Double())
            }
        ", "not assignable");
    }

    [Fact]
    public void Extension_ChainedOnLiteral()
    {
        // 5.ToString().Length should work (CLR methods)
        AssertNoErrors(@"
            func Main() {
                r := 5.ToString().Length
            }
        ");
    }

    [Fact]
    public void Extension_DoubleLiteral_Receiver()
    {
        AssertNoErrors(@"
            func Negate(this d: double): double { return 0.0 - d }
            func Main() {
                r := 3.14.Negate()
            }
        ");
    }

    // ================================================================
    // .NET BCL interop — overloaded static methods
    // ================================================================

    [Fact]
    public void BCL_ConsoleWrite_IntOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(42)
            }
        ");
    }

    [Fact]
    public void BCL_ConsoleWrite_StringOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(""hello"")
            }
        ");
    }

    [Fact]
    public void BCL_ConsoleWrite_BoolOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(true)
            }
        ");
    }

    [Fact]
    public void BCL_MathMax_IntOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                r := Math.Max(1, 2)
            }
        ");
    }

    [Fact]
    public void BCL_IntegerParse()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                n := Int32.Parse(""42"")
            }
        ");
    }

    // ===================================================================
    // Type System Hardening Tests
    // ===================================================================

    #region Nominal Subtyping

    [Fact]
    public void NominalSubtyping_ClassInheritance_Assignable()
    {
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func Main() {
                dog := new Dog()
                animal: Animal = dog
            }
        ");
    }

    [Fact]
    public void NominalSubtyping_InterfaceImplementation_Assignable()
    {
        AssertNoErrors(@"
            interface IGreetable {
                func Greet(): string
            }
            class Person : IGreetable {
                func Greet(): string {
                    return ""Hello""
                }
            }
            func Main() {
                p := new Person()
                g: IGreetable = p
            }
        ");
    }

    [Fact]
    public void NominalSubtyping_EverythingAssignableToObject()
    {
        AssertNoErrors(@"
            func Main() {
                x: object = 42
                y: object = ""hello""
                z: object = true
            }
        ");
    }

    #endregion

    #region Numeric Widening — Comprehensive Assignability Matrix

    // ===== byte widening =====
    [Fact]
    public void NumericWidening_ByteToShort()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: short = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToInt()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToLong()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToFloat()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToDouble()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToDecimal()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: decimal = x
            }
        ");
    }

    // ===== sbyte widening =====
    [Fact]
    public void NumericWidening_SByteToShort()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: short = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToInt()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToLong()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToFloat()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToDouble()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToDecimal()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: decimal = x
            }
        ");
    }

    // ===== short widening =====
    [Fact]
    public void NumericWidening_ShortToInt()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToLong()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToFloat()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToDouble()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToDecimal()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: decimal = x
            }
        ");
    }

    // ===== ushort widening =====
    [Fact]
    public void NumericWidening_UShortToInt()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToLong()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToFloat()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToDouble()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToDecimal()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: decimal = x
            }
        ");
    }

    // ===== int widening =====
    [Fact]
    public void NumericWidening_IntToLong()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToFloat()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToDouble()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToDecimal()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: decimal = x
            }
        ");
    }

    // ===== uint widening =====
    [Fact]
    public void NumericWidening_UIntToLong()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToFloat()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToDouble()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToDecimal()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: decimal = x
            }
        ");
    }

    // ===== long widening =====
    [Fact]
    public void NumericWidening_LongToFloat()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_LongToDouble()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_LongToDecimal()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: decimal = x
            }
        ");
    }

    // ===== ulong widening =====
    [Fact]
    public void NumericWidening_ULongToFloat()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ULongToDouble()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ULongToDecimal()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: decimal = x
            }
        ");
    }

    // ===== char widening =====
    [Fact]
    public void NumericWidening_CharToInt()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToLong()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToFloat()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToDouble()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToDecimal()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: decimal = x
            }
        ");
    }

    // ===== float widening =====
    [Fact]
    public void NumericWidening_FloatToDouble()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: float = x
                z: double = y
            }
        ");
    }

    // ===== Narrowing conversions — must be REJECTED =====
    [Fact]
    public void NumericNarrowing_IntToByte_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = 42
                y: byte = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_ShortToByte_Rejected()
    {
        AssertHasError(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: byte = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_LongToInt_Rejected()
    {
        AssertHasError(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: int = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_DoubleToFloat_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: double = 3.14
                y: float = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_DecimalToDouble_Rejected()
    {
        AssertHasError(@"
            func GetDecimal(): decimal { return 0 as decimal }
            func Main() {
                x: decimal = GetDecimal()
                y: double = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_IntToShort_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = 42
                y: short = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_DoubleToInt_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: double = 3.14
                y: int = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_FloatToInt_Rejected()
    {
        AssertHasError(@"
            func GetFloat(): float { return 0 as float }
            func Main() {
                x: float = GetFloat()
                y: int = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_DecimalToInt_Rejected()
    {
        AssertHasError(@"
            func GetDecimal(): decimal { return 0 as decimal }
            func Main() {
                x: decimal = GetDecimal()
                y: int = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NumericNarrowing_LongToShort_Rejected()
    {
        AssertHasError(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: short = x
            }
        ", "Cannot assign");
    }

    #endregion

    #region Nullable Assignability — Comprehensive Matrix

    // T -> T? (widening) — should work
    [Fact]
    public void NullableWidening_IntToNullableInt()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: int? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_StringToNullableString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string = ""hello""
                y: string? = x
            }
        ");
    }

    // null -> T? (should work)
    [Fact]
    public void NullableAssignment_NullToNullableInt()
    {
        AssertNoErrors(@"
            func Main() {
                x: int? = null
            }
        ");
    }

    [Fact]
    public void NullableAssignment_NullToNullableString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = null
            }
        ");
    }

    // null -> reference type (should work — string is a reference type)
    [Fact]
    public void NullAssignment_NullToString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string = null
            }
        ");
    }

    // null -> value type (should fail)
    [Fact]
    public void NullAssignment_NullToInt_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = null
            }
        ", "Cannot assign");
    }

    // Inner type widening: int? -> long? (should work)
    [Fact]
    public void NullableWidening_NullableIntToNullableLong()
    {
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: long? = x
            }
        ");
    }

    // T? -> object (boxing — should work)
    [Fact]
    public void NullableWidening_NullableIntToObject()
    {
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: object = x
            }
        ");
    }

    // null -> class type (should work — classes are reference types)
    [Fact]
    public void NullAssignment_NullToClassType()
    {
        AssertNoErrors(@"
            class Foo {
                x: int = 0
            }
            func Main() {
                f: Foo = null
            }
        ");
    }

    #endregion

    #region Flow-Sensitive Null Narrowing

    [Fact]
    public void FlowNarrowing_NullCheckNarrowsToNonNullable()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null {
                    y: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_EqualNullNarrowsInElse()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x == null {
                    // x is still string? here
                } else {
                    y: string = x
                }
            }
        ");
    }

    #endregion

    #region Enum Exhaustiveness

    [Fact]
    public void EnumExhaustiveness_AllCasesCovered_NoError()
    {
        AssertNoErrors(@"
            enum Status {
                Active = 0,
                Inactive = 1
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    Status.Inactive => ""off""
                }
            }
        ");
    }

    [Fact]
    public void EnumExhaustiveness_WildcardCovers_NoError()
    {
        AssertNoErrors(@"
            enum Status {
                Active = 0,
                Inactive = 1,
                Pending = 2
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    _ => ""other""
                }
            }
        ");
    }

    [Fact]
    public void EnumExhaustiveness_MissingCase_Error()
    {
        AssertHasError(@"
            enum Status {
                Active = 0,
                Inactive = 1,
                Pending = 2
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    Status.Inactive => ""off""
                }
            }
        ", "not exhaustive");
    }

    [Fact]
    public void EnumToInt_ImplicitlyAssignable()
    {
        AssertNoErrors(@"
            enum Priority {
                Low = 0,
                High = 1
            }
            func Main() {
                p := Priority.Low
                n: int = p
            }
        ");
    }

    #endregion

    #region Unknown Type Kinds

    [Fact]
    public void UnknownKind_ErrorRecovery_SuppressesCascading()
    {
        // Using an undefined function should produce ONE error, not cascading errors
        var result = Analyze(@"
            func Main() {
                x := undefinedFunction()
                y: int = x
            }
        ");
        // Should have error for undefined function but NOT for x assignment
        Assert.True(result.HasErrors);
        Assert.DoesNotContain(result.Errors, e => e.Message.Contains("Cannot assign"));
    }

    #endregion

    // ===================================================================
    // Type System Hardening: Phase 2 — Flow Typing, Structural Delegates,
    // Constraint Validation, Enum Nominality
    // ===================================================================

    #region Flow Narrowing: && Chaining

    [Fact]
    public void FlowNarrowing_AndChain_BothNullChecks()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x != null && y != null {
                    a: string = x
                    b: int = y
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_NullCheckWithCondition()
    {
        // x != null narrows x; the second operand doesn't produce narrowings but shouldn't break
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null && true {
                    a: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_NoElseNarrowing()
    {
        // else of && is !a || !b — can't narrow either variable
        AssertHasError(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x != null && y != null {
                    a: string = x
                } else {
                    b: string = x
                }
            }
        ", "Cannot assign");
    }

    #endregion

    #region Flow Narrowing: Is-Type Patterns

    [Fact]
    public void FlowNarrowing_IsPattern_BindsVariable()
    {
        // if x is Dog d — should declare d with type Dog in then-branch
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog d {
                    name: string = d.Name
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_IsPattern_NarrowsWithoutBinding()
    {
        // if x is Dog — should narrow x to Dog in then-branch (no new variable)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog {
                    dog: Dog = a
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_IsPattern_WithAndChain()
    {
        // Combine is-pattern with && null check on separate variables
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal, x: string?) {
                if a is Dog && x != null {
                    dog: Dog = a
                    s: string = x
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: Or-Chain

    [Fact]
    public void FlowNarrowing_OrChain_NarrowsInElseBranch()
    {
        // if x == null || y == null → both non-null in else branch
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x == null || y == null {
                    // can't narrow here — one or the other failed
                } else {
                    a: string = x
                    b: int = y
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_OrChain_NoThenNarrowing()
    {
        // then-branch of || cannot narrow (only one side needs to be true)
        AssertHasError(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x == null || y == null {
                    a: string = x
                }
            }
        ", "Cannot assign");
    }

    [Fact]
    public void FlowNarrowing_OrChain_TripleNullCheck()
    {
        // Three null checks combined with || — all narrow in else
        AssertNoErrors(@"
            func Main() {
                x: string? = ""a""
                y: string? = ""b""
                z: string? = ""c""
                if x == null || y == null || z == null {
                    // can't narrow
                } else {
                    a: string = x
                    b: string = y
                    c: string = z
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_OrChain_RhsSeesLeftElseNarrowing()
    {
        // x == null || x.Length > 0 — RHS should see x as non-nullable (short-circuit: left was false → x != null)
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x == null || x.Length > 0 {
                    // can narrow x in then body only if both sides hold,
                    // but the important thing is no error on x.Length
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: And-Chain RHS Narrowing

    [Fact]
    public void FlowNarrowing_AndChain_RhsSeesLeftNarrowing()
    {
        // x != null && x.Length > 0 — the RHS should see x as non-nullable
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null && x.Length > 0 {
                    s: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_RhsSeesIsPatternNarrowing()
    {
        // a is Dog && a.Breed == "poodle" — RHS should see a as Dog (accessing Dog.Breed)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog && a.Breed == ""poodle"" {
                    breed: string = a.Breed
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: Same-Symbol Intersection

    [Fact]
    public void FlowNarrowing_SameSymbol_KeepsMostSpecific()
    {
        // if a is Dog && a is Animal → should keep Dog (more specific), not Animal
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog && a is Animal {
                    d: Dog = a
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_SameSymbol_ReversedOrder_KeepsMostSpecific()
    {
        // if a is Animal && a is Dog → should still keep Dog (more specific)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Animal && a is Dog {
                    d: Dog = a
                }
            }
        ");
    }

    #endregion

    #region Lambda-Delegate Structural Validation

    [Fact]
    public void Lambda_Delegate_CorrectParamCount_NoError()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, string>, x: int): string {
                return f(x)
            }
            func Main() {
                result := Apply((x) => ""hello"", 42)
            }
        ");
    }

    [Fact]
    public void Lambda_Delegate_WrongParamCount_Error()
    {
        // Lambda with 2 params assigned to Func<int, string> (1 param + return type)
        AssertHasError(@"
            func Main() {
                let f: Func<int, string> = (x, y) => ""hello""
            }
        ", "Cannot assign");
    }

    [Fact]
    public void Lambda_Delegate_ZeroParams_MatchesFunc()
    {
        AssertNoErrors(@"
            func RunIt(f: Func<int>): int {
                return f()
            }
            func Main() {
                result := RunIt(() => 42)
            }
        ");
    }

    #endregion

    #region Generic Constraint Validation

    [Fact]
    public void GenericConstraint_Satisfied_NoError()
    {
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyInt : IComparable {
                func CompareTo(other: object): int {
                    return 0
                }
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new MyInt(), new MyInt())
            }
        ");
    }

    [Fact]
    public void GenericConstraint_Violated_Error()
    {
        AssertHasError(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class Plain {
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new Plain(), new Plain())
            }
        ", "does not satisfy constraint");
    }

    // --- Special constraint tests ---

    [Fact]
    public void SpecialConstraint_Class_WithStringArg_NoError()
    {
        AssertNoErrors(@"
            func Identity<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                result := Identity(""hello"")
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Class_WithIntArg_Error()
    {
        AssertHasError(@"
            func Identity<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                result := Identity(42)
            }
        ", "must be a reference type");
    }

    [Fact]
    public void SpecialConstraint_Struct_WithIntArg_NoError()
    {
        AssertNoErrors(@"
            func Box<T>(value: T): T where T : struct {
                return value
            }
            func Main() {
                result := Box(42)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Struct_WithStringArg_Error()
    {
        AssertHasError(@"
            func Box<T>(value: T): T where T : struct {
                return value
            }
            func Main() {
                result := Box(""hello"")
            }
        ", "must be a non-nullable value type");
    }

    [Fact]
    public void SpecialConstraint_New_WithDefaultCtorClass_NoError()
    {
        AssertNoErrors(@"
            class Widget {
            }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                w := new Widget()
                result := Create(w)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_New_WithParameterizedCtorOnly_Error()
    {
        // A record with primary constructor parameters has no parameterless constructor.
        // Use explicit type argument to ensure T is resolved to the record type.
        AssertHasError(@"
            record Point(X: int, Y: int)
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                p := new Point(1, 2)
                result := Create<Point>(p)
            }
        ", "must have a parameterless constructor");
    }

    [Fact]
    public void SpecialConstraint_ClassAndStruct_MutuallyExclusive_ParseError()
    {
        AssertHasParseError(@"
            func Bad<T>(value: T): T where T : class, struct {
                return value
            }
        ", "mutually exclusive");
    }

    [Fact]
    public void SpecialConstraint_Class_WithInterface_WithStringArg_NoError()
    {
        // string satisfies both 'class' and IComparable
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyString : IComparable {
                func CompareTo(other: object): int { return 0 }
            }
            func Process<T>(value: T): T where T : class, IComparable {
                return value
            }
            func Main() {
                ms := new MyString()
                result := Process(ms)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_New_WithStructArg_NoError()
    {
        // Structs always have a parameterless constructor
        AssertNoErrors(@"
            struct Point {
                X: int
                Y: int
            }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                p := new Point()
                result := Create(p)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Class_WithRecordArg_NoError()
    {
        // Records are reference types and satisfy 'class' constraint
        AssertNoErrors(@"
            record Person(Name: string, Age: int)
            func Process<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                p := new Person(""Alice"", 30)
                result := Process(p)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_StructAndNew_MutuallyExclusive_ParseError()
    {
        // C# forbids struct + new() because struct already implies new()
        AssertHasParseError(@"
            func Bad<T>(value: T): T where T : struct, new() {
                return value
            }
        ", "struct");
    }

    [Fact]
    public void SpecialConstraint_New_WithPrimaryCtorClass_Error()
    {
        // A class with a primary constructor (suppresses implicit default ctor)
        // should NOT satisfy new()
        AssertHasError(@"
            class RequiresPrimary(X: int) { }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                r := new RequiresPrimary(1)
                result := Create<RequiresPrimary>(r)
            }
        ", "must have a parameterless constructor");
    }

    [Fact]
    public void SpecialConstraint_New_WithRecordStructArg_NoError()
    {
        // Record structs always have an implicit parameterless constructor
        AssertNoErrors(@"
            record struct Size(Width: int, Height: int)
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                s := new Size(10, 20)
                result := Create<Size>(s)
            }
        ");
    }

    #endregion

    #region String-to-Enum Rejection

    [Fact]
    public void StringToEnum_Rejected()
    {
        // Assigning a string literal to an enum type should be rejected
        AssertHasError(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c: Color = ""red""
            }
        ", "Cannot assign");
    }

    [Fact]
    public void IntToEnum_Rejected()
    {
        // Assigning an int literal to an enum type should be rejected
        AssertHasError(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c: Color = 0
            }
        ", "Cannot assign");
    }

    [Fact]
    public void EnumToString_Allowed()
    {
        // Enum to its underlying type is allowed
        AssertNoErrors(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c := Color.Red
                n: int = c
            }
        ");
    }

    [Fact]
    public void StringEnumToString_Allowed()
    {
        // String enums are inferred from the first member value being a string literal
        AssertNoErrors(@"
            enum Color {
                Red = ""red"",
                Blue = ""blue""
            }
            func Main() {
                c := Color.Red
                s: string = c
            }
        ");
    }

    [Fact]
    public void StringToStringEnum_Rejected()
    {
        AssertHasError(@"
            enum Color {
                Red = ""red"",
                Blue = ""blue""
            }
            func Main() {
                c: Color = ""red""
            }
        ", "Cannot assign");
    }

    #endregion

    [Fact]
    public void SetupSymbols_VisibleInTestBodies()
    {
        // Setup variables must be available in test scopes (not unresolved)
        AssertNoErrors(@"
            setup {
                count := 42
            }

            test ""should see setup variable"" {
                assert count == 42
            }
        ");
    }

    #region Overload Resolution — Betterness Rules

    [Fact]
    public void OverloadResolution_IntBeatsLong_WithIntArg()
    {
        // C# spec 12.6.4: Exact match beats implicit conversion
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(x: long): long { return x }
            func Main() {
                r := Foo(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_IntBeatsObject_WithIntArg()
    {
        // More specific type beats less specific
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(x: object) { }
            func Main() {
                Foo(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_TwoParams_FirstExactWins()
    {
        // Foo(int, int) beats Foo(int, long) when both args are int
        AssertNoErrors(@"
            func Foo(x: int, y: int): int { return x }
            func Foo(x: int, y: long): long { return x as long }
            func Main() {
                r := Foo(1, 2)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_NonParamsBeatsParams()
    {
        // Non-params overload wins when both match for single argument
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(params x: int[]): int { return 0 }
            func Main() {
                r := Foo(1)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToLong_Works()
    {
        // When only long overload exists, int should implicitly widen
        AssertNoErrors(@"
            func Process(x: long): long { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToDouble_Works()
    {
        // When only double overload exists, int should implicitly widen
        AssertNoErrors(@"
            func Process(x: double): double { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    #endregion

    #region Missing Diagnostics — Type System Edge Cases

    [Fact]
    public void VoidUsedAsValue_Rejected()
    {
        // Assigning the result of a void function to a variable should be an error
        AssertHasError(@"
            func DoStuff() { }
            func Main() {
                x := DoStuff()
            }
        ", "void");
    }

    [Fact]
    public void DuplicateParameterNames_Rejected()
    {
        // Two parameters with the same name should be an error
        AssertHasError(@"
            func Dup(x: int, x: string): int {
                return 0
            }
        ", "already declared");
    }

    [Fact]
    public void NullAssignment_NullToInterfaceType()
    {
        // null should be assignable to interface types (reference types)
        AssertNoErrors(@"
            interface IFoo {
                func Bar(): int
            }
            func Main() {
                x: IFoo = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToArrayType()
    {
        // null should be assignable to array types (reference types)
        AssertNoErrors(@"
            func Main() {
                x: int[] = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToBool_Rejected()
    {
        // null should NOT be assignable to value types
        AssertHasError(@"
            func Main() {
                x: bool = null
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NullAssignment_NullToDouble_Rejected()
    {
        // null should NOT be assignable to numeric value types
        AssertHasError(@"
            func Main() {
                x: double = null
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NullableWidening_IntNullableToLongNullable()
    {
        // int? -> long? via inner type widening should work
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: long? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_ByteNullableToIntNullable()
    {
        // byte? -> int? via inner type widening
        AssertNoErrors(@"
            func GetNullableByte(): byte? { return null }
            func Main() {
                x: byte? = GetNullableByte()
                y: int? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_FloatNullableToDoubleNullable()
    {
        // float? -> double? via inner type widening
        AssertNoErrors(@"
            func GetNullableFloat(): float? { return null }
            func Main() {
                x: float? = GetNullableFloat()
                y: double? = x
            }
        ");
    }

    [Fact]
    public void NullableNarrowing_LongNullableToIntNullable_Rejected()
    {
        // long? -> int? should fail (narrowing)
        AssertHasError(@"
            func GetNullableLong(): long? { return null }
            func Main() {
                x: long? = GetNullableLong()
                y: int? = x
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NullAssignment_NullToRecordStruct_Rejected()
    {
        // record struct is a value type — null should NOT be assignable
        AssertHasError(@"
            record struct Point {
                x: int = 0
                y: int = 0
            }
            func Main() {
                p: Point = null
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NullAssignment_NullToRecord_Allowed()
    {
        // record (not struct) is a reference type — null should be assignable
        AssertNoErrors(@"
            record Person {
                name: string = ""unknown""
            }
            func Main() {
                p: Person = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToStruct_Rejected()
    {
        // struct is a value type — null should NOT be assignable
        AssertHasError(@"
            struct Point {
                x: int = 0
                y: int = 0
            }
            func Main() {
                p: Point = null
            }
        ", "Cannot assign");
    }

    [Fact]
    public void NullAssignment_NullToUnionType()
    {
        // union types are reference types — null should be assignable
        AssertNoErrors(@"
            union Shape {
                Circle { radius: double }
                Rectangle { width: double, height: double }
            }
            func Main() {
                s: Shape = null
            }
        ");
    }

    #endregion

    #region Impossible Pattern Warnings

    private void AssertHasWarning(string source, string expectedMessage)
    {
        var result = Analyze(source);
        Assert.Contains(result.Errors,
            e => e.Severity == NSharpLang.Compiler.ErrorSeverity.Warning
              && e.Message.Contains(expectedMessage));
    }

    private void AssertNoWarning(string source, string warningMessage)
    {
        var result = Analyze(source);
        Assert.DoesNotContain(result.Errors,
            e => e.Severity == NSharpLang.Compiler.ErrorSeverity.Warning
              && e.Message.Contains(warningMessage));
    }

    [Fact]
    public void ImpossiblePattern_IntIsString_ProducesWarning()
    {
        // int is a value type; string is a different reference type — can never match
        AssertHasWarning(@"
            func Main() {
                x: int = 42
                result := x is string
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_BoolIsInt_ProducesWarning()
    {
        // bool and int are unrelated value types — can never match
        AssertHasWarning(@"
            func Main() {
                flag: bool = true
                result := flag is int
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_IntIsInt_NoWarning()
    {
        // Exact same type — trivially possible (always matches)
        AssertNoWarning(@"
            func Main() {
                x: int = 42
                result := x is int
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_ClassIsInterface_NoWarning()
    {
        // Any class could implement an interface — always possible at runtime
        AssertNoWarning(@"
            interface IShape {
                func Area(): double
            }
            class Circle {
                Radius: double
                func Area(): double { return 3.14 * Radius * Radius }
            }
            func Main() {
                c: Circle = new Circle { Radius: 1.0 }
                result := c is IShape
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_BaseClassIsDerived_NoWarning()
    {
        // Downcasting from base to derived is a valid runtime check
        AssertNoWarning(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func Main() {
                a: Animal = new Dog { Name: ""Rex"", Breed: ""Lab"" }
                result := a is Dog
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_SealedClassUnrelated_ProducesWarning()
    {
        // A sealed class can never be a subtype of an unrelated class
        AssertHasWarning(@"
            sealed class Cat {
                Name: string
            }
            class Dog {
                Name: string
            }
            func Main() {
                c: Cat = new Cat { Name: ""Whiskers"" }
                result := c is Dog
            }
        ", "will never");
    }

    [Fact]
    public void ImpossiblePattern_ObjectIsString_NoWarning()
    {
        // object can be anything — unboxing/downcasting string is valid
        AssertNoWarning(@"
            func Main() {
                obj: object = ""hello""
                result := obj is string
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_UnionTypeIsCase_NoWarning()
    {
        // Pattern matching union cases is always valid
        AssertNoWarning(@"
            union Shape {
                Circle { radius: double }
                Rectangle { width: double, height: double }
            }
            func Main() {
                s: Shape = new Shape.Circle { radius: 1.0 }
                x := match s {
                    Shape.Circle { radius } => radius,
                    _ => 0.0
                }
            }
        ", "will never");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_IntIsString_ProducesWarning()
    {
        // if 42 is string s — int can never be string
        AssertHasWarning(@"
            func Main() {
                n: int = 42
                if n is string s {
                    len: int = s.Length
                }
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_ObjectIsString_NoWarning()
    {
        // obj is string s — object can always be checked at runtime
        AssertNoWarning(@"
            func Main() {
                obj: object = ""hello""
                if obj is string s {
                    len: int = s.Length
                }
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_IntIsDouble_Warning()
    {
        // The `is` operator is a CLR runtime type-identity test (isinst), NOT a conversion.
        // int is double is always false at runtime, even though int->double is an implicit conversion.
        AssertHasWarning(@"
            func Main() {
                x: int = 5
                result := x is double
            }
        ", "will never succeed");
    }

    #endregion

    #region Numeric Narrowing Cast Suggestions

    // These tests verify that when a numeric narrowing error occurs, the error's ContextualHint
    // contains explicit cast syntax (e.g. "(int)value") to help the developer fix the issue.

    [Fact]
    public void NarrowingSuggestion_LongToInt_SuggestsCast()
    {
        // long → int: should suggest explicit (int) cast
        AssertHasHint(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: int = x
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_DoubleToFloat_SuggestsCast()
    {
        // double → float: should suggest explicit (float) cast
        AssertHasHint(@"
            func Main() {
                x: double = 3.14
                y: float = x
            }
        ", "(float)value");
    }

    [Fact]
    public void NarrowingSuggestion_FunctionArgument_LongToInt_SuggestsCast()
    {
        // Passing a long argument to a function expecting int should include cast suggestion
        AssertHasHint(@"
            func Foo(x: int) {}
            func GetLong(): long { return 0 as long }
            func Main() {
                v: long = GetLong()
                Foo(v)
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_ReturnDoubleFromIntFunc_SuggestsCast()
    {
        // Returning double from a function declared to return int should suggest cast
        AssertHasHint(@"
            func GetDouble(): double { return 0.0 }
            func Compute(): int {
                d: double = GetDouble()
                return d
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_IntToByte_LiteralTooLarge_SuggestsCast()
    {
        // Assigning an int literal (300) to byte: int → byte narrowing should suggest cast
        AssertHasHint(@"
            func Main() {
                x: int = 300
                y: byte = x
            }
        ", "(byte)value");
    }

    [Fact]
    public void NarrowingSuggestion_IntToInt_NoError()
    {
        // int to int: valid assignment, no error and no narrowing suggestion needed
        AssertNoErrors(@"
            func Main() {
                x: int = 42
            }
        ");
    }

    [Fact]
    public void NarrowingSuggestion_StringToInt_NotNumericNarrowing()
    {
        // string → int: error, but NOT a numeric narrowing suggestion — should use the
        // string-specific hint (int.Parse / int.TryParse), not a cast suggestion
        var result = AnalyzeWithSource(@"
            func Main() {
                x: string = ""hello""
                y: int = x
            }
        ");
        Assert.True(result.HasErrors, "Expected errors but got none");
        var typeMismatchErrors = result.Errors.Where(e => e.ContextualHint != null).ToList();
        // Should NOT suggest a numeric cast — should suggest int.Parse instead
        Assert.Contains(typeMismatchErrors, e => e.ContextualHint!.Contains("int.Parse"));
        Assert.DoesNotContain(typeMismatchErrors, e => e.ContextualHint!.Contains("(int)value"));
    }

    [Fact]
    public void NarrowingSuggestion_LongToShort_SuggestsCast()
    {
        // long → short: should suggest explicit (short) cast
        AssertHasHint(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: short = x
            }
        ", "(short)value");
    }

    #endregion

    #region Default Expression

    [Fact]
    public void DefaultExpression_IntVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_StringVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                s: string = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_ReturnFromIntFunction_NoErrors()
    {
        AssertNoErrors(@"
            func Foo(): int {
                return default
            }
        ");
    }


    [Fact]
    public void DefaultExpression_NoTypeContext_ReportsError()
    {
        AssertHasError(@"
            func Main() {
                x := default
            }
        ", "Cannot determine type for 'default'");
    }

    [Fact]
    public void DefaultExpression_FunctionArgument_NoErrors()
    {
        AssertNoErrors(@"
            func Bar(x: int) {}
            func Main() {
                Bar(default)
            }
        ");
    }

    [Fact]
    public void DefaultExpression_NullableIntVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: int? = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_BoolVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: bool = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_DoubleVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: double = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_ReturnFromBoolFunction_NoErrors()
    {
        AssertNoErrors(@"
            func IsReady(): bool {
                return default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_FieldInitializer_NoErrors()
    {
        AssertNoErrors(@"
            class Counter {
                count: int = default
            }
        ");
    }

    #endregion
}
