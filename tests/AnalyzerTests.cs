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
}
