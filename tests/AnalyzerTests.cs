using System.Linq;
using Xunit;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Tests;

public class AnalyzerTests
{
    private AnalysisResult Analyze(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var ast = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();
        return analyzer.Analyze(ast);
    }

    private void AssertNoErrors(string source)
    {
        var result = Analyze(source);
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
            using System

            func Main() {
                Console.WriteLine(""Hello"")
            }
        ");
    }

    [Fact]
    public void ExternalType_MemberAccess_Valid()
    {
        AssertNoErrors(@"
            using System

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
            using System.Linq

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
            using System

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
                    Result.Success { value } => value
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
                    Result.Success { value } => value
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
                    Result.Success { value } => value * 2
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
                    Result.Success { value } => value
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
                    Result.Success { value } => value
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
                    1 => ""one""
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
                    Result.Success { value } => value
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
    public void MatchExpression_WithGuard_SkipsExhaustivenessCheck()
    {
        // When guards are present, exhaustiveness checking is skipped
        // This should not report a missing case error
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
}
