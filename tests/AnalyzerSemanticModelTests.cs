using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Columnar;

namespace Tests;

public class AnalyzerSemanticModelTests
{
    private AnalysisResult Analyze(string source)
    {
        var parseResult = ColumnarParserRecovery.ParseFileAst(source, "test.nl");

        Assert.NotNull(parseResult.CompilationUnit);

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(parseResult.CompilationUnit, "test.nl", null, source);
    }

    [Fact]
    public void Analyzer_RecordTypes_RecordStructFlagInSemanticModel()
    {
        var source = @"
record struct Point {
    X: int
}

record Address {
    City: string
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var pointType = Assert.IsType<RecordTypeInfo>(result.SemanticModel.Types["Point"]);
        var addressType = Assert.IsType<RecordTypeInfo>(result.SemanticModel.Types["Address"]);

        Assert.True(pointType.IsStruct);
        Assert.False(addressType.IsStruct);
    }

    [Fact]
    public void Analyzer_NominalTypes_SourceFactsInSemanticModel()
    {
        var source = @"
sealed class Closed {
}

class Open {
}

class Base {
}

class Derived: Base {
}

interface Marker {
}

interface ChildMarker: Marker {
}

class ImplementedDerived: Base, Marker {
}

class GenericBox<T> {
}

class PrimaryBox(value: int) {
}

class MemberBox {
    Value: int
    Name: string => ""box""
    func Compute(): int {
        return 1
    }
}

class FunctionMemberBox {
    func Format(label: string, ref value: int): string {
        return label
    }

    func FormatDefault(label: string, suffix: string = ""!""): string {
        return label + suffix
    }

    [MustUse]
    func BuildToken(): int {
        return 1
    }

    func Sum(params values: int[]): int {
        return 0
    }

    func Convert(value: int): string {
        return ""int""
    }

    func Convert(value: string): string {
        return value
    }

    func Identity<T>(value: T): T {
        return value
    }

    func RequireClass<T>(value: T): T where T : class {
        return value
    }
}

struct MarkedStruct: Marker {
}

struct GenericStruct<T> {
}

struct PrimaryPoint(x: double, y: double) {
}

record MarkedRecord: Marker {
}

record GenericRecord<T> {
}

record PrimaryPerson(name: string, age: int) {
}

interface GenericInterface<T> {
}

func UseImplementedAsMarker() {
    implemented := new ImplementedDerived()
    marker: Marker = implemented
}

func UseStructAsMarker() {
    marked := new MarkedStruct()
    marker: Marker = marked
}

func UseRecordAsMarker() {
    marked := new MarkedRecord()
    marker: Marker = marked
}

func UseChildMarkerAsMarker(child: ChildMarker) {
    marker: Marker = child
}

duck interface Reader {
    func Read(): string
}

interface Named {
    func Name(): string
}";

        var result = Analyze(source);

        Assert.NotNull(result.SemanticModel);
        var closedType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["Closed"]);
        var openType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["Open"]);
        var derivedType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["Derived"]);
        var implementedDerivedType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["ImplementedDerived"]);
        var markedStructType = Assert.IsType<StructTypeInfo>(result.SemanticModel.Types["MarkedStruct"]);
        var primaryPointType = Assert.IsType<StructTypeInfo>(result.SemanticModel.Types["PrimaryPoint"]);
        var markedRecordType = Assert.IsType<RecordTypeInfo>(result.SemanticModel.Types["MarkedRecord"]);
        var primaryPersonType = Assert.IsType<RecordTypeInfo>(result.SemanticModel.Types["PrimaryPerson"]);
        var childMarkerType = Assert.IsType<InterfaceTypeInfo>(result.SemanticModel.Types["ChildMarker"]);
        var genericBoxType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["GenericBox"]);
        var primaryBoxType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["PrimaryBox"]);
        var memberBoxType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["MemberBox"]);
        var functionMemberBoxType = Assert.IsType<ClassTypeInfo>(result.SemanticModel.Types["FunctionMemberBox"]);
        var genericStructType = Assert.IsType<StructTypeInfo>(result.SemanticModel.Types["GenericStruct"]);
        var genericRecordType = Assert.IsType<RecordTypeInfo>(result.SemanticModel.Types["GenericRecord"]);
        var genericInterfaceType = Assert.IsType<InterfaceTypeInfo>(result.SemanticModel.Types["GenericInterface"]);
        var readerType = Assert.IsType<InterfaceTypeInfo>(result.SemanticModel.Types["Reader"]);
        var namedType = Assert.IsType<InterfaceTypeInfo>(result.SemanticModel.Types["Named"]);

        Assert.True(closedType.IsSealed);
        Assert.False(openType.IsSealed);
        Assert.Null(openType.BaseClass);
        Assert.Empty(openType.Interfaces);
        Assert.Empty(openType.TypeParameters);
        Assert.Empty(openType.PrimaryConstructorParameters);
        var derivedBase = Assert.IsType<SimpleTypeReference>(derivedType.BaseClass);
        Assert.Equal("Base", derivedBase.Name);
        Assert.Equal("Marker", Assert.IsType<SimpleTypeReference>(Assert.Single(implementedDerivedType.Interfaces)).Name);
        Assert.Equal("Marker", Assert.IsType<SimpleTypeReference>(Assert.Single(markedStructType.Interfaces)).Name);
        Assert.Equal("Marker", Assert.IsType<SimpleTypeReference>(Assert.Single(markedRecordType.Interfaces)).Name);
        Assert.Equal("Marker", Assert.IsType<SimpleTypeReference>(Assert.Single(childMarkerType.BaseInterfaces)).Name);
        Assert.Equal("T", Assert.Single(genericBoxType.TypeParameters).Name);
        var primaryBoxParameter = Assert.Single(primaryBoxType.PrimaryConstructorParameters);
        Assert.Equal("value", primaryBoxParameter.Name);
        Assert.Equal("int", Assert.IsType<SimpleTypeReference>(primaryBoxParameter.Type).Name);
        var valueMember = Assert.Single(memberBoxType.DeclaredMembers, member => member.Name == "Value");
        Assert.Equal("MemberBox", valueMember.ContainingType);
        Assert.Equal(DeclaredMemberKind.Field, valueMember.Kind);
        Assert.Equal("int", Assert.IsType<SimpleTypeReference>(valueMember.Type).Name);
        var nameMember = Assert.Single(memberBoxType.DeclaredMembers, member => member.Name == "Name");
        Assert.Equal("MemberBox", nameMember.ContainingType);
        Assert.Equal(DeclaredMemberKind.Property, nameMember.Kind);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(nameMember.Type).Name);
        var computeMember = Assert.Single(memberBoxType.DeclaredMembers, member => member.Name == "Compute");
        Assert.Equal("MemberBox", computeMember.ContainingType);
        Assert.Equal(DeclaredMemberKind.Function, computeMember.Kind);
        Assert.Null(computeMember.Type);
        var formatMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "Format");
        Assert.Equal("FunctionMemberBox", formatMember.ContainingType);
        Assert.Equal(DeclaredMemberKind.Function, formatMember.Kind);
        Assert.Equal(2, formatMember.ParameterCount);
        Assert.Equal(new[] { "label", "value" }, formatMember.ParameterNames);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(formatMember.ParameterTypes[0]).Name);
        Assert.Equal("int", Assert.IsType<SimpleTypeReference>(formatMember.ParameterTypes[1]).Name);
        Assert.Equal(ParameterModifier.None, formatMember.ParameterModifiers[0]);
        Assert.Equal(ParameterModifier.Ref, formatMember.ParameterModifiers[1]);
        Assert.Equal(2, formatMember.RequiredParameterCount);
        Assert.False(formatMember.HasParamsParameter);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(formatMember.ReturnType).Name);
        Assert.Equal(0, formatMember.TypeParameterCount);
        Assert.Equal(0, formatMember.AttributeCount);
        Assert.False(formatMember.HasMustUseAttribute);
        Assert.False(formatMember.IsAsync);
        Assert.False(formatMember.IsGenerator);
        var formatDefaultMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "FormatDefault");
        Assert.Equal(DeclaredMemberKind.Function, formatDefaultMember.Kind);
        Assert.Equal(2, formatDefaultMember.ParameterCount);
        Assert.Equal(new[] { "label", "suffix" }, formatDefaultMember.ParameterNames);
        Assert.Equal(1, formatDefaultMember.RequiredParameterCount);
        Assert.False(formatDefaultMember.HasParamsParameter);
        Assert.False(formatDefaultMember.HasMustUseAttribute);
        var buildTokenMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "BuildToken");
        Assert.Equal(DeclaredMemberKind.Function, buildTokenMember.Kind);
        Assert.Equal(1, buildTokenMember.AttributeCount);
        Assert.True(buildTokenMember.HasMustUseAttribute);
        var sumMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "Sum");
        Assert.Equal(DeclaredMemberKind.Function, sumMember.Kind);
        Assert.Equal(1, sumMember.ParameterCount);
        Assert.Equal(new[] { "values" }, sumMember.ParameterNames);
        Assert.Equal(0, sumMember.RequiredParameterCount);
        Assert.True(sumMember.HasParamsParameter);
        var convertMembers = functionMemberBoxType.DeclaredMembers
            .Where(member => member.Name == "Convert")
            .OrderBy(member => Assert.IsType<SimpleTypeReference>(Assert.Single(member.ParameterTypes)).Name)
            .ToList();
        Assert.Equal(2, convertMembers.Count);
        Assert.All(convertMembers, member =>
        {
            Assert.Equal(DeclaredMemberKind.Function, member.Kind);
            Assert.Equal(1, member.ParameterCount);
            Assert.Equal(new[] { "value" }, member.ParameterNames);
            Assert.Equal(1, member.RequiredParameterCount);
            Assert.False(member.HasParamsParameter);
        });
        Assert.Equal("int", Assert.IsType<SimpleTypeReference>(Assert.Single(convertMembers[0].ParameterTypes)).Name);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(Assert.Single(convertMembers[1].ParameterTypes)).Name);
        var identityMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "Identity");
        Assert.Equal(DeclaredMemberKind.Function, identityMember.Kind);
        Assert.Equal(1, identityMember.TypeParameterCount);
        Assert.Equal("T", Assert.Single(identityMember.TypeParameters).Name);
        Assert.Empty(identityMember.GenericConstraints);
        Assert.Equal("T", Assert.IsType<SimpleTypeReference>(Assert.Single(identityMember.ParameterTypes)).Name);
        Assert.Equal("T", Assert.IsType<SimpleTypeReference>(identityMember.ReturnType).Name);
        var requireClassMember = Assert.Single(functionMemberBoxType.DeclaredMembers, member => member.Name == "RequireClass");
        Assert.Equal(DeclaredMemberKind.Function, requireClassMember.Kind);
        Assert.Equal(1, requireClassMember.TypeParameterCount);
        Assert.Equal("T", Assert.Single(requireClassMember.TypeParameters).Name);
        var requireClassConstraint = Assert.Single(requireClassMember.GenericConstraints);
        Assert.Equal("T", requireClassConstraint.TypeParameter);
        Assert.True(requireClassConstraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Class));
        Assert.Equal("T", Assert.Single(genericStructType.TypeParameters).Name);
        Assert.Collection(
            primaryPointType.PrimaryConstructorParameters,
            x =>
            {
                Assert.Equal("x", x.Name);
                Assert.Equal("double", Assert.IsType<SimpleTypeReference>(x.Type).Name);
            },
            y =>
            {
                Assert.Equal("y", y.Name);
                Assert.Equal("double", Assert.IsType<SimpleTypeReference>(y.Type).Name);
            });
        Assert.Equal("T", Assert.Single(genericRecordType.TypeParameters).Name);
        Assert.Collection(
            primaryPersonType.PrimaryConstructorParameters,
            name =>
            {
                Assert.Equal("name", name.Name);
                Assert.Equal("string", Assert.IsType<SimpleTypeReference>(name.Type).Name);
            },
            age =>
            {
                Assert.Equal("age", age.Name);
                Assert.Equal("int", Assert.IsType<SimpleTypeReference>(age.Type).Name);
            });
        Assert.Equal("T", Assert.Single(genericInterfaceType.TypeParameters).Name);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.True(readerType.IsDuckInterface);
        Assert.False(namedType.IsDuckInterface);
    }

    [Fact]
    public void Analyzer_NominalTypes_GenericArityUsesTypeInfoTypeParameters()
    {
        var source = @"
class Box<T> {
}

func Handle(input: Box<int, bool>) {
    _ = input
}";

        var result = Analyze(source);

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.InvalidTypeArgument &&
            e.Message.Contains("takes 1 type argument(s), but 2 were provided"));
    }

    [Fact]
    public void Analyzer_NominalTypes_GenericMemberInitializerUsesTypeInfoTypeParameters()
    {
        var source = @"
class Box<T> {
    Value: T
}

func Main() {
    box := new Box<int> { Value: 1 }
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_NominalTypes_GenericMemberInitializerUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Box<T> {
    Value: T
}

func Main(): Box<int> {
    return new Box<int> { Value: ""wrong"" }
}";

        var result = Analyze(source);

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_NominalTypes_PropertyPatternUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Person {
    Name: string
    Age: int => 42
}

func Main(person: Person): string {
    return match person {
        { Name: name, Age: 42 } => name,
        _ => """"
    }
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidPattern);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Analyzer_NominalTypes_ValueCopyMemberWriteUsesTypeInfoDeclaredMembers()
    {
        var source = @"
struct Cell {
    Value: int
}

func MakeCell(): Cell {
    return new Cell { Value: 1 }
}

func Main() {
    MakeCell().Value = 2
}";

        var result = Analyze(source);

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.MemberWriteThroughValueCopy);
    }

    [Fact]
    public void Analyzer_NominalTypes_UsingDisposePatternUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Resource {
    func Dispose(): void {
    }
}

func Main() {
    using resource := new Resource() {
    }
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
    }

    [Fact]
    public void Analyzer_NominalTypes_InvalidUsingDisposePatternUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Resource {
    static func Dispose(): void {
    }

    func Dispose(value: int): void {
    }

    func DisposeText(): string {
        return ""no""
    }
}

func Main() {
    using resource := new Resource() {
    }
}";

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Using resource of type 'Resource' must implement IDisposable", error.Message);
    }

    [Fact]
    public void Analyzer_NominalTypes_NonVoidUsingDisposePatternUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Resource {
    func Dispose(): int {
        return 0
    }
}

func Main() {
    using resource := new Resource() {
    }
}";

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Using resource of type 'Resource' must implement IDisposable", error.Message);
    }

    [Fact]
    public void Analyzer_NominalTypes_StaticRefFieldUsesTypeInfoDeclaredMembers()
    {
        var source = @"
func Bump(ref value: int) {
    value += 1
}

class Counter {
    static Value: int
}

func Main() {
    Bump(ref Counter.Value)
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
    }

    [Fact]
    public void Analyzer_NominalTypes_StaticRefPropertyUsesTypeInfoDeclaredMembers()
    {
        var source = @"
func Bump(ref value: int) {
    value += 1
}

class Counter {
    static Current: int {
        get {
            return 1
        }
    }
}

func Main() {
    Bump(ref Counter.Current)
}";

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("The 'ref' argument needs an assignable target", error.Message);
    }

    [Fact]
    public void Analyzer_NominalTypes_BinaryOperatorUsesTypeInfoDeclaredMembers()
    {
        var source = @"
struct Vec2 {
    X: double
    Y: double

    static func operator +(left: Vec2, right: Vec2): Vec2 {
        return new Vec2 { X: left.X + right.X, Y: left.Y + right.Y }
    }
}

func Add(left: Vec2, right: Vec2): Vec2 {
    return left + right
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void Analyzer_NominalTypes_UnaryOperatorUsesTypeInfoDeclaredMembers()
    {
        var source = @"
struct Flag {
    Value: int

    static func operator !(value: Flag): bool {
        return value.Value == 0
    }
}

func IsEmpty(value: Flag): bool {
    return !value
}";

        var result = Analyze(source);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void Analyzer_NominalTypes_OperatorParameterFactsRejectMismatchedOperands()
    {
        var source = @"
struct Vec2 {
    X: double
    Y: double

    static func operator +(left: int, right: int): Vec2 {
        return new Vec2 { X: 0.0, Y: 0.0 }
    }
}

func Add(left: Vec2, right: Vec2): Vec2 {
    return left + right
}";

        var result = Analyze(source);

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void Analyzer_NominalTypes_StaticReadonlyFieldUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Counter {
    static readonly Value: int = 1
}

func Main() {
    Counter.Value = 2
}";

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("static readonly", error.Message);
    }

    [Fact]
    public void Analyzer_NominalTypes_InstanceReadonlyFieldUsesTypeInfoDeclaredMembers()
    {
        var source = @"
class Counter {
    readonly value: int = 1
}

func Main(counter: Counter) {
    counter.value = 2
}";

        var result = Analyze(source);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
    }

    [Fact]
    public void Analyzer_NominalTypes_GenericPrimaryConstructorInitializerUsesTypeInfoParameters()
    {
        var source = @"
class Box<T>(value: T) {
}

func Main(): Box<int> {
    return new Box<int> { value: ""wrong"" }
}";

        var result = Analyze(source);

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }
}
