using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class ILCompilerCoverageTests : ILCompilerTestBase
{
    private static bool HasLiftedStorageField(Assembly assembly)
    {
        return assembly.GetTypes()
            .SelectMany(type => type.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            .Any(field => IsLiftedStorageType(field.FieldType));
    }

    private static bool IsLiftedStorageType(Type type)
    {
        return type.IsGenericType && type.GetGenericTypeDefinition() == typeof(System.Runtime.CompilerServices.StrongBox<>)
            || type.Name.StartsWith("<>LiftedBox", StringComparison.Ordinal);
    }

    // NAMED TUPLE member access (`t.x` on a value typed (x: int, y: int)): the analyzer always resolved
    // names via TupleTypeInfo, but the emitter resolved members by literal-name reflection on the erased
    // CLR ValueTuple<> (which only has ItemN fields) and threw "Member x not found on type ValueTuple`2".
    // The emitter now retains declared element names per variable (_tupleElementNamesByVariable) and
    // rewrites named members to their positional ItemN spelling at the member-resolution tails.
    // Interpolated-string TEXT segments decode the shared escape set (they historically emitted RAW
    // while plain strings decoded — the IL path diverged from the transpile path; strings slice 3).
    [Fact]
    public void ILCompiler_InterpolatedStringTextSegmentsDecodeEscapes()
    {
        var source = @"
func main(): int {
    n := 42
    withHole := $""a\nb{n}c\td""
    pure := $""x\ny""
    return withHole.Length * 100 + pure.Length
}";
        // a, \n, b, 4, 2, c, \t, d = 8 chars; x, \n, y = 3 chars.
        var result = CompileAndInvoke(source);
        Assert.Equal(803, Assert.IsType<int>(result));
    }

    // Reflection.Emit's BeginCatchBlock/BeginFinallyBlock/EndExceptionBlock append implicit `leave`
    // instructions, which make the post-block position reachable in the JIT importer's view EVEN when
    // every region exits via `throw`. A value body whose only exits are throws inside a try/catch (or
    // lock/using) therefore still needs the structured-return tail — without it, control "falls off" a
    // reachable method end and EVERY call throws InvalidProgramException (probe-found while mapping the
    // exceptions arc: the wrap-and-rethrow catch pattern was broken in every position). The tail now
    // also emits when the body emitted an exception block and never returned (_emittedExceptionBlockInBody)
    // at all three tail sites: top-level functions, type-member methods, and nested lambda/local-function
    // bodies (TryCloseNestedStructuredReturn).
    [Fact]
    public void ILCompiler_ThrowTerminatedExceptionBlocks_EmitValidIl()
    {
        // The wrap-and-rethrow catch pattern: both regions exit via throw, no return anywhere.
        var wrapped = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    try {
        throw new FormatException(""orig"")
    } catch {
        throw new InvalidOperationException(""wrapped"")
    }
}"));
        Assert.Equal("wrapped", wrapped.Message);

        // Typed catch with the bound variable flowing into the new exception.
        var flowed = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    try {
        throw new FormatException(""orig"")
    } catch (e: FormatException) {
        throw new InvalidOperationException(e.Message)
    }
}"));
        Assert.Equal("orig", flowed.Message);

        // lock body that always throws — EmitLock's try/finally has the same implicit-leave mechanics.
        var locked = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func locker(): string {
    return ""k""
}

func main(): int {
    lock locker() {
        throw new InvalidOperationException(""locked"")
    }
}"));
        Assert.Equal("locked", locked.Message);

        // Nested local function whose body is an all-throws try/catch (the nested-body tail closer).
        var nested = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    func g(): int {
        try {
            throw new FormatException(""a"")
        } catch {
            throw new InvalidOperationException(""lam"")
        }
    }
    return g()
}"));
        Assert.Equal("lam", nested.Message);

        // Block-bodied lambda all-throws (LambdaEmitter goes through the same nested-body tail closer).
        var lambda = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    g: Func<int> = () => {
        try {
            throw new FormatException(""a"")
        } catch {
            throw new InvalidOperationException(""lam2"")
        }
    }
    return g()
}"));
        Assert.Equal("lam2", lambda.Message);
    }

    // break/continue from inside a try/catch/finally whose loop began OUTSIDE the region crossed the
    // boundary with a plain `br` — invalid IL, InvalidProgramException on every call (probe-found while
    // mapping the exceptions arc; fully general across while/for/foreach). BranchTarget now records the
    // protected-region depth at loop entry and EmitBreak/EmitContinue emit `leave` when the branch exits
    // outward (which also runs an intervening finally); a loop wholly inside one region keeps `br`.
    [Fact]
    public void ILCompiler_LoopBranchesCrossingExceptionRegions_EmitValidIl()
    {
        // break out of a try/catch inside a while loop.
        Assert.Equal(183, CompileAndInvoke(@"
func main(): int {
    total := 0
    i := 0
    while i < 10 {
        try {
            if i == 3 {
                break
            }
            total = total + 100 / (i + 1)
        } catch {
            total = total + 1000
        }
        i = i + 1
    }
    return total
}"));

        // continue from inside a try/catch in a loop.
        Assert.Equal(8, CompileAndInvoke(@"
func main(): int {
    total := 0
    i := 0
    while i < 4 {
        i = i + 1
        try {
            if i == 2 {
                continue
            }
            total = total + i
        } catch {
            total = total + 1000
        }
    }
    return total
}"));

        // break THROUGH a finally — the handler must run on the break path.
        Assert.Equal(32, CompileAndInvoke(@"
func main(): int {
    total := 0
    i := 0
    while i < 5 {
        try {
            if i == 2 {
                break
            }
            total = total + 1
        } finally {
            total = total + 10
        }
        i = i + 1
    }
    return total
}"));

        // a loop WHOLLY inside a try — the break does not cross; plain `br` stays valid.
        Assert.Equal(3, CompileAndInvoke(@"
func main(): int {
    total := 0
    try {
        i := 0
        while i < 10 {
            if i == 3 {
                break
            }
            total = total + 1
            i = i + 1
        }
    } catch {
        total = 0 - 1
    }
    return total
}"));
    }

    // Control transfer OUT of a finally handler is analyzer-rejected (NL319, the CS0157 analog) —
    // emitting it would produce a `leave` out of the handler, which ECMA-335 forbids
    // (ilverify: LeaveOutOfFinally; InvalidProgramException on every call). This harness compiles
    // through the ILCompiler directly, BYPASSING the analyzer, so it pins the emitter's
    // defense-in-depth guards: they must throw a compiler-bug error rather than emit the invalid IL.
    [Fact]
    public void ILCompiler_ControlTransferOutOfFinally_NeverReachesEmit()
    {
        // return out of a finally (the void form that previously built and crashed at runtime).
        var ret = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main() {
    n := 0
    try {
        n = n + 1
    } finally {
        return
    }
}"));
        Assert.Contains("NL319", ret.Message);

        // break out of a finally to a loop outside it.
        var brk = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    total := 0
    i := 0
    while i < 5 {
        i = i + 1
        try {
            total = total + 1
        } finally {
            if i == 2 {
                break
            }
        }
    }
    return total
}"));
        Assert.Contains("NL319", brk.Message);

        // continue out of a finally to a loop outside it.
        var cont = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    total := 0
    i := 0
    while i < 5 {
        i = i + 1
        try {
            total = total + 1
        } finally {
            if i == 2 {
                continue
            }
        }
    }
    return total
}"));
        Assert.Contains("NL319", cont.Message);

        // a loop OPENED inside the finally — its own break/continue never leave the handler and
        // must keep compiling and running (the guard records the loop-entry finally depth).
        Assert.Equal(4, CompileAndInvoke(@"
func main(): int {
    total := 0
    try {
        total = total + 1
    } finally {
        i := 0
        while i < 10 {
            if i == 3 {
                break
            }
            total = total + 1
            i = i + 1
        }
    }
    return total
}"));
    }

    [Fact]
    public void ILCompiler_NestedBodiesDoNotCaptureOuterLoopBranchTargets()
    {
        // The analyzer rejects both shapes as ordinary invalid break/continue usage. This direct
        // ILCompiler harness bypasses analysis, so it pins the emitter isolation guard: nested
        // method bodies must not reuse the enclosing method's loop labels.
        var lambdaBreak = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    i := 0
    while i < 1 {
        try {
            i = i + 1
        } finally {
            let f: Func<int> = () => {
                break
                return 1
            }
            i = f()
        }
    }
    return i
}"));
        Assert.Contains("break used outside", lambdaBreak.Message);

        var localContinue = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(@"
func main(): int {
    i := 0
    while i < 1 {
        try {
            i = i + 1
        } finally {
            func bump(): int {
                continue
                return 1
            }
            i = bump()
        }
    }
    return i
}"));
        Assert.Contains("continue used outside", localContinue.Message);
    }

    [Fact]
    public void ILCompiler_NamedTupleMemberAccess_AllReceiverShapes()
    {
        var source = @"
func mk(): (x: int, y: int) {
    return (x: 3, y: 4)
}

func dist(p: (x: int, y: int)): int {
    return p.x + p.y
}

func viaLambdaParamShadow(): int {
    t := (a: 100, b: 200)
    f: Func<int, int> = n => n + 1
    return f(t.a)
}

func main(): int {
    t := mk()                      // local inferred from a call's declared return type
    lit := (a: 10, b: 20)          // local inferred from a NAMED tuple literal
    copy := lit                    // identifier copy propagates the names
    sum := t.x + t.y               // 7
    sum = sum + lit.a + lit.b      // +30 = 37
    sum = sum + copy.a             // +10 = 47
    sum = sum + dist((x: 5, y: 6)) // +11 = 58 (PARAM receiver inside dist)
    sum = sum + mk().x             // +3 = 61 (direct CALL receiver)
    sum = sum + t.Item1            // +3 = 64 (positional spelling stays valid on a named tuple)
    sum = sum + viaLambdaParamShadow() // +101 = 165 (names survive the lambda body boundary)
    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(165, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_NamedTupleMemberAccess_CrossNamedAssignmentStaysPositional()
    {
        // Tuple identity is positional — differently-named tuple types assign freely (C# semantics),
        // and the RECEIVING name set governs member access.
        var source = @"
func mk(): (x: int, y: int) {
    return (x: 3, y: 4)
}

func take(p: (a: int, b: int)): int {
    return p.a + p.b
}

func main(): int {
    return take(mk())
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteLockStatementAndReleaseMonitor()
    {
        var source = @"
import System
import System.Threading

func main(): int {
    gate := new object()
    entered := false
    reacquired := false

    try {
        lock gate {
            entered = Monitor.IsEntered(gate)
            throw new Exception(""boom"")
        }
    } catch {
    }

    Monitor.Enter(gate)
    reacquired = Monitor.IsEntered(gate)
    Monitor.Exit(gate)

    if entered && reacquired {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnAdditionOverflow()
    {
        var source = @"
func main(): int {
    max := 2147483647
    return checked(max + 1)
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnMultiplicationOverflow()
    {
        var source = @"
func main(): int {
    return checked(50000 * 50000)
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_UncheckedExpressionWrapsOnOverflow()
    {
        var source = @"
func main(): int {
    max := 2147483647
    min := -2147483647 - 1
    expectedMin := -2147483647 - 1
    expectedMax := 2147483647
    wrappedAdd := unchecked(max + 1)
    wrappedSub := unchecked(min - 1)

    if wrappedAdd == expectedMin && wrappedSub == expectedMax {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnOverflowingCast()
    {
        var source = @"
func main(): int {
    value := checked((byte)256)
    return value
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_UncheckedExpressionWrapsOverflowingCast()
    {
        var source = @"
func main(): int {
    value := unchecked((byte)256)
    return value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(0, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteEmptyStatements()
    {
        var source = @"
func main(): int {
    total := 0
    ;

    for i := 0; i < 3; i++ {
        ;
        total += 1
    }

    if total == 3 {
        ;
        return total
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteFloatLiteralsWithSuffixes()
    {
        var source = @"
func main(): double {
    value: float = 1.25f
    bonus: double = 2.5d
    return (double)value + bonus
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3.75, Assert.IsType<double>(result), precision: 5);
    }

    [Fact]
    public void ILCompiler_CanExecuteBuiltInUnaryOperators()
    {
        var source = @"
class Box {
    Value: int
}

func main(): int {
    count := 1
    flag := false
    mask := 5
    box := new Box { Value: 3 }
    values := [10]

    pre := ++count
    postMember := box.Value++
    postIndex := values[0]--

    if !flag && -count == -2 && ~mask == -6 {
        return pre * 10000 + postMember * 1000 + box.Value * 100 + postIndex * 10 + values[0]
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(23509, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullLiteralsForReferenceAndNullableTypes()
    {
        var source = @"
class Node {
    Value: int
}

func main(): int {
    text: string = null
    node: Node = null
    maybe: int? = null
    value := maybe ?? 42

    if text == null && node == null && value == 42 {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteEmittedClassNullComparisonsInBothOperandOrders()
    {
        var source = @"
class Node {
    Value: int
}

func main(): int {
    missing: Node = null
    present := new Node { Value: 7 }
    score := 0

    if missing == null {
        score = score + 1
    }

    if null == missing {
        score = score + 2
    }

    if present != null {
        score = score + 4
    }

    if null != present {
        score = score + 8
    }

    return score
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullableNullComparisonsAndCoalesce()
    {
        var source = @"
func main(): int {
    missing: int? = null
    present: int? = 7
    value := missing ?? 42
    score := 0

    if missing == null {
        score = score + 1
    }

    if null == missing {
        score = score + 2
    }

    if present != null {
        score = score + 4
    }

    if null != present {
        score = score + 8
    }

    if value == 42 {
        score = score + 16
    }

    return score
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(31, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringConcatenationWithMixedOperands()
    {
        var source = @"
func main(): string {
    return ""sum="" + 42 + "",ok="" + true
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("sum=42,ok=True", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringConcatenationWhenStringIsRightOperand()
    {
        var source = @"
func main(): string {
    return 42 + "" items""
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("42 items", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringIndexFromEndAndRange()
    {
        var source = @"
func main(): string {
    text := ""abcdef""
    middle := text[1..^1]
    tail := text[^2]
    return middle + ""|"" + tail
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("bcde|e", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_EmitsAttributesAcrossConstructorFieldPropertyAndIndexerTargets()
    {
        var source = @"
import System

class Annotated {
    [Obsolete(""field"")]
    data: int

    [Obsolete(""ctor"")]
    constructor([CLSCompliant(true)] seed: int) {
        data = seed
    }

    [Obsolete(""property"")]
    Value: int {
        get {
            return data
        }
    }

    [Obsolete(""indexer"")]
    func this[index: int]: int {
        get {
            return data + index
        }
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var annotatedType = assembly.GetType("Annotated");
            Assert.NotNull(annotatedType);

            var field = annotatedType!.GetField("data", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(field);
            var fieldAttribute = GetCustomAttribute(field!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "field" }, GetAttributeArguments(fieldAttribute));

            var constructor = Assert.Single(annotatedType.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic));
            var constructorAttribute = GetCustomAttribute(constructor, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "ctor" }, GetAttributeArguments(constructorAttribute));
            var constructorParameterAttribute = Assert.Single(constructor.GetParameters()[0].CustomAttributes);
            Assert.Equal("System.CLSCompliantAttribute", constructorParameterAttribute.AttributeType.FullName);

            var valueProperty = annotatedType.GetProperty("Value", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(valueProperty);
            var propertyAttribute = GetCustomAttribute(valueProperty!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "property" }, GetAttributeArguments(propertyAttribute));

            var indexerProperty = annotatedType.GetProperty("Item", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(indexerProperty);
            var indexerAttribute = GetCustomAttribute(indexerProperty!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "indexer" }, GetAttributeArguments(indexerAttribute));

            return 0;
        });
    }

    [Fact]
    public void ILCompiler_EmitsParameterAttributesOnMethods()
    {
        var source = @"
import NSharpLang.Tests

class Api {
    func Create([RuntimeCoverage(42, [""route""], Enabled: true)] id: int): int {
        return id
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var apiType = assembly.GetType("Api");
            Assert.NotNull(apiType);
            var createMethod = apiType!.GetMethod("Create", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(createMethod);

            var attribute = Assert.Single(createMethod!.GetParameters()[0].CustomAttributes);
            Assert.Equal("NSharpLang.Tests.RuntimeCoverageAttribute", attribute.AttributeType.FullName);
            Assert.Equal(new object?[] { 42, new object?[] { "route" } }, GetAttributeArguments(attribute));
            Assert.True(Assert.IsType<bool>(GetNamedAttributeValue(attribute, "Enabled")));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsAspNetParameterAttributes()
    {
        var source = @"
import Microsoft.AspNetCore.Mvc

class IssuesController {
    func Create([FromRoute] id: int, [FromBody] request: CreateIssueRequest): int {
        return id
    }
}

class CreateIssueRequest {
    Title: string
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        CompileAndInspect(source, config, assembly =>
        {
            var controllerType = assembly.GetType("IssuesController");
            Assert.NotNull(controllerType);

            var createMethod = controllerType!.GetMethod("Create", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(createMethod);

            var parameters = createMethod!.GetParameters();
            Assert.Contains(parameters[0].CustomAttributes, attribute => attribute.AttributeType.FullName == "Microsoft.AspNetCore.Mvc.FromRouteAttribute");
            Assert.Contains(parameters[1].CustomAttributes, attribute => attribute.AttributeType.FullName == "Microsoft.AspNetCore.Mvc.FromBodyAttribute");
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteListPatternOnCustomIndexedTypeWithSliceBinding()
    {
        var source = @"
class Window {
    values: int[]

    constructor() {
        values = [1, 2, 3, 4]
    }

    Count: int {
        get {
            return values.Length
        }
    }

    func this[index: int]: int {
        get {
            return values[index]
        }
    }
}

func main(): int {
    window := new Window()
    return match window {
        [1, .. middle, 4] => middle[0] * 100 + middle[1] * 10 + middle.Length
        _ => 0
    }
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(232, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrDecimalOptionalDefaultValue()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    return ILCompilerCallHelpers.DecimalDefaultScaled()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(125, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrNullableOptionalDefaultValue()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    return ILCompilerCallHelpers.NullableOrDefault()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(17, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoCustomAddCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    bag: IntAddBag = [1, 2, 3, 4]
    return bag.Sum()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoCustomEnqueueCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    bag: IntEnqueueBag = [4, 2, 7]
    return bag.ReadAsDigits()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(427, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoEnumerableConstructorCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    prefix := [1, 2]
    box: IntEnumerableBox = [0, ...prefix, 3]
    return box.Signature()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(403, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoISetInterfaceTarget()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    values: ISet<int> = [1, 1, 2, 3]
    return values.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanPassArrayDirectlyToClrParamsMethod()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    items := [1, 2, 3, 4]
    return ILCompilerCallHelpers.Sum(items)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferCompositeGenericLocalFunctionTypes()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    func second<T>(items: T[]): T {
        return items[1]
    }

    func consume<T>(items: List<T>, projector: Func<T, int>): int {
        return 7
    }

    projector: Func<int, int> = x => x
    values: List<int> = [7, 8, 9]
    return second([4, 5, 6]) * 10
        + consume(values, projector)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(57, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferTupleGenericLocalFunctionTypes()
    {
        var source = @"
func main(): int {
    func score<TLeft, TRight>(pair: (TLeft, TRight)): int {
        return 4
    }

    return score((1, 4))
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_DirectLocalFunctionCall_DoesNotMaterializeDelegateInCaller()
    {
        var source = @"
func main(): int {
    func addOne(value: int): int {
        return value + 1
    }

    return addOne(4) + addOne(5)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                CallCount = opCodes.Count(opCode => opCode == OpCodes.Call)
            };
        });

        Assert.Equal(11, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
        Assert.True(result.CallCount >= 2, "Direct local function calls should lower to direct call instructions.");
    }

    [Fact]
    public void ILCompiler_DirectLocalFunctionLoop_DoesNotLiftUncapturedLocals()
    {
        var source = @"
func main(): int {
    func addOne(value: int): int {
        return value + 1
    }

    total := 0
    for i := 0; i < 8; i++ {
        total += addOne(i)
    }

    return total
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt)
            };
        });

        Assert.Equal(36, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
    }

    [Fact]
    public void ILCompiler_DirectCapturingLocalFunctionCall_DoesNotMaterializeDelegateInCaller()
    {
        var source = @"
func main(): int {
    offset := 3
    func addOffset(value: int): int {
        return value + offset
    }

    return addOffset(4)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                CallCount = opCodes.Count(opCode => opCode == OpCodes.Call)
            };
        });

        Assert.Equal(7, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
        Assert.True(result.CallCount >= 1, "Direct capturing local function calls should lower to direct calls with capture arguments.");
    }

    [Fact]
    public void ILCompiler_NonCapturingLocalFunctionValue_MaterializesDelegateOnlyAtValueBoundary()
    {
        var source = @"
import System

func main(): int {
    func addOne(value: int): int {
        return value + 1
    }

    escaped: Func<int, int> = addOne
    return addOne(4)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                CallCount = opCodes.Count(opCode => opCode == OpCodes.Call)
            };
        });

        Assert.Equal(5, Assert.IsType<int>(result.Value));
        Assert.True(result.NewobjCount >= 1, "Escaping a local function as a Func value must materialize a delegate at the value boundary.");
        Assert.Equal(0, result.CallvirtCount);
        Assert.True(result.CallCount >= 1, "Direct calls should remain direct calls even when the same local function also escapes as a value.");
    }

    [Fact]
    public void ILCompiler_EscapingLocalFunctionValue_MaterializesDelegateAtBoundary()
    {
        var source = @"
import System

func main(): int {
    func addOne(value: int): int {
        return value + 1
    }

    escaped: Func<int, int> = addOne
    return escaped(4)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt)
            };
        });

        Assert.Equal(5, Assert.IsType<int>(result.Value));
        Assert.True(result.NewobjCount >= 1, "Escaping a local function as a Func value must materialize a delegate.");
        Assert.True(result.CallvirtCount >= 1, "Invoking an escaped delegate should still use the delegate Invoke path.");
    }

    [Fact]
    public void ILCompiler_DirectLambdaLocalCall_DoesNotMaterializeDelegateInCaller()
    {
        var source = @"
func main(): int {
    getValue := () => 42
    return getValue() + getValue()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                CallCount = opCodes.Count(opCode => opCode == OpCodes.Call)
            };
        });

        Assert.Equal(84, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
        Assert.True(result.CallCount >= 2, "Non-escaping lambda local invocations should lower to direct call instructions.");
    }

    [Fact]
    public void ILCompiler_DirectLambdaLocalLoop_DoesNotLiftUncapturedLocals()
    {
        var source = @"
func main(): int {
    one := () => 1
    total := 0
    for i := 0; i < 8; i++ {
        total += i + one()
    }

    return total
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt)
            };
        });

        Assert.Equal(36, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
    }

    [Fact]
    public void ILCompiler_DirectContextualLambdaLocalLoop_DoesNotMaterializeDelegateInCaller()
    {
        var source = @"
import System

func main(): int {
    addOne: Func<int, int> = value => value + 1
    total := 0
    for i := 0; i < 8; i++ {
        total += addOne(i)
    }

    return total
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                CallCount = opCodes.Count(opCode => opCode == OpCodes.Call)
            };
        });

        Assert.Equal(36, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
        Assert.True(result.CallCount >= 1, "Non-escaping contextual lambda locals should lower to direct helper calls.");
    }

    [Fact]
    public void ILCompiler_DirectContextualCapturedLambdaLocal_DoesNotLiftReadonlyCapture()
    {
        var source = @"
import System

func main(): int {
    offset := 3
    addOffset: Func<int, int> = value => value + offset
    return addOffset(4)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt),
                HasLiftedStorageField = HasLiftedStorageField(assembly)
            };
        });

        Assert.Equal(7, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.Equal(0, result.CallvirtCount);
        Assert.False(result.HasLiftedStorageField, "Readonly captures used only by a direct helper should not allocate lifted storage.");
    }

    [Fact]
    public void ILCompiler_ShadowedLambdaParameter_DoesNotForceReadonlyCaptureLiftedStorage()
    {
        var source = @"
import System

func main(): int {
    value := 3
    getValue: Func<int> = () => value
    mutateShadow: Func<int, int> = value => {
        value = 9
        return value
    }

    ignored := mutateShadow(1)
    return getValue() + ignored
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasLiftedStorageField = HasLiftedStorageField(assembly)
            };
        });

        Assert.Equal(12, Assert.IsType<int>(result.Value));
        Assert.False(result.HasLiftedStorageField, "Mutation of a shadowing lambda parameter must not force lifted storage for an outer readonly capture.");
    }

    [Fact]
    public void ILCompiler_EscapingLambdaLocal_MaterializesDelegateAtBoundary()
    {
        var source = @"
import System

func observe(getValue: Func<int>): int {
    return 0
}

func main(): int {
    getValue: Func<int> = () => 42
    ignored := observe(getValue)
    return getValue()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt)
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.True(result.NewobjCount >= 1, "Escaping a lambda as a Func value must materialize a delegate at the value boundary.");
        Assert.True(result.CallvirtCount >= 1, "Invoking an escaped lambda delegate should use the CLR delegate Invoke path.");
    }

    [Fact]
    public void ILCompiler_NonCapturingEscapedLambda_UsesCachedDelegateField()
    {
        var source = @"
import System

func observe(getValue: Func<int>): int {
    return 0
}

func main(): int {
    getValue: Func<int> = () => 42
    ignored := observe(getValue)
    return getValue()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);
            var cachedDelegateFields = assembly.GetTypes()
                .SelectMany(type => type.GetFields(BindingFlags.NonPublic | BindingFlags.Static))
                .Where(field => typeof(Delegate).IsAssignableFrom(field.FieldType))
                .ToArray();

            return new
            {
                Value = main!.Invoke(null, null),
                LdsfldCount = opCodes.Count(opCode => opCode == OpCodes.Ldsfld),
                StsfldCount = opCodes.Count(opCode => opCode == OpCodes.Stsfld),
                CachedDelegateFieldCount = cachedDelegateFields.Length
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.True(result.LdsfldCount >= 1, "A cached non-capturing lambda should load a static delegate field.");
        Assert.True(result.StsfldCount >= 1, "A cached non-capturing lambda should initialize a static delegate field.");
        Assert.True(result.CachedDelegateFieldCount >= 1, "The compiler should define a static delegate cache field.");
    }

    [Fact]
    public void ILCompiler_EscapingReadonlyCapturedLambda_DoesNotUseLiftedStorage()
    {
        var source = @"
import System

func make(): Func<int> {
    value := 42
    return () => value
}

func main(): int {
    getValue := make()
    return getValue()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasLiftedStorageField = HasLiftedStorageField(assembly)
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.False(result.HasLiftedStorageField, "Readonly escaped lambda captures can be copied into the display class without StrongBox storage.");
    }

    [Fact]
    public void ILCompiler_InstanceLambdaWithoutInstanceAccess_DoesNotCreateDisplayClass()
    {
        var source = @"
import System

class Holder {
    value: int = 40

    func Run(): int {
        getValue: Func<int> = () => 42
        return getValue()
    }
}

func main(): int {
    holder := new Holder()
    return holder.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal))
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.False(result.HasDisplayClass, "A lambda in an instance method must not allocate a closure when it does not reference instance state.");
    }

    [Fact]
    public void ILCompiler_InstanceLambdaCapturingOnlyThisField_DoesNotCreateDisplayClass()
    {
        // A bare lambda passed as an argument (so it is lowered through EmitLambda, not the
        // local-function path) that references only an instance field must be emitted as an
        // instance method bound to 'this' rather than allocating a <>c__DisplayClass closure.
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

class Counter {
    value: int = 41

    func Run(): int {
        return apply(() => value + 1)
    }
}

func main(): int {
    counter := new Counter()
    return counter.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            var counterType = assembly.GetType("Counter");
            Assert.NotNull(counterType);
            var instanceLambdaMethods = counterType!
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .Where(method => method.Name.StartsWith("<Lambda>", StringComparison.Ordinal))
                .ToArray();

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal)),
                InstanceLambdaMethodCount = instanceLambdaMethods.Length
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.False(result.HasDisplayClass, "A lambda that only captures 'this' must bind to the existing instance instead of allocating a closure.");
        Assert.True(result.InstanceLambdaMethodCount >= 1, "The 'this'-only lambda should be emitted as an instance method on the declaring type.");
    }

    [Fact]
    public void ILCompiler_InstanceLambdaCapturingOnlyThisViaThisExpression_DoesNotCreateDisplayClass()
    {
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

class Box {
    payload: int = 7

    func Run(): int {
        return apply(() => this.payload * 2)
    }
}

func main(): int {
    box := new Box()
    return box.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            var boxType = assembly.GetType("Box");
            Assert.NotNull(boxType);
            var instanceLambdaMethods = boxType!
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .Where(method => method.Name.StartsWith("<Lambda>", StringComparison.Ordinal))
                .ToArray();

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal)),
                InstanceLambdaMethodCount = instanceLambdaMethods.Length
            };
        });

        Assert.Equal(14, Assert.IsType<int>(result.Value));
        Assert.False(result.HasDisplayClass, "A lambda that only references 'this' via a this-expression should still avoid allocating a display class.");
        Assert.True(result.InstanceLambdaMethodCount >= 1, "The 'this'-only lambda should be emitted as an instance method on the declaring type.");
    }

    [Fact]
    public void ILCompiler_InstanceLambdaCapturingThisAndLocal_StillCreatesDisplayClass()
    {
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

class Adder {
    seed: int = 10

    func Run(): int {
        offset := 5
        return apply(() => seed + offset)
    }
}

func main(): int {
    adder := new Adder()
    return adder.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal))
            };
        });

        Assert.Equal(15, Assert.IsType<int>(result.Value));
        Assert.True(result.HasDisplayClass, "A lambda that captures both 'this' and a local must still allocate a display class to thread the local capture.");
    }

    [Fact]
    public void ILCompiler_NoCaptureLambdaArgument_DoesNotCreateDisplayClass()
    {
        // A lambda inside an instance method that references neither 'this' nor any local must
        // be emitted statically with no display class.
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

class Holder {
    value: int = 99

    func Run(): int {
        return apply(() => 42)
    }
}

func main(): int {
    holder := new Holder()
    return holder.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal))
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.False(result.HasDisplayClass, "A non-capturing lambda must not allocate a display class.");
    }

    [Fact]
    public void ILCompiler_StructLambdaCapturingOnlyThis_DoesNotUseInstanceLambdaFastPath()
    {
        // A value-type 'this' is a managed pointer at arg0 and cannot be bound to a delegate
        // without boxing a copy, which would change capture semantics. The 'this'-only
        // instance-lambda fast path must therefore be skipped for structs: the lambda must be
        // emitted on a display class rather than as an instance method on the struct itself.
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

struct Tally {
    total: int

    func Run(): int {
        return apply(() => total + 1)
    }
}

func main(): int {
    tally := new Tally { total: 41 }
    return tally.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var tallyType = assembly.GetType("Tally");
            Assert.NotNull(tallyType);
            var structInstanceLambdaMethods = tallyType!
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .Where(method => method.Name.StartsWith("<Lambda>", StringComparison.Ordinal))
                .ToArray();

            return new
            {
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal)),
                StructInstanceLambdaMethodCount = structInstanceLambdaMethods.Length
            };
        });

        Assert.Equal(0, result.StructInstanceLambdaMethodCount);
        Assert.True(result.HasDisplayClass, "A struct 'this'-only lambda must fall back to the display-class path, not the instance-method fast path.");
    }

    [Fact]
    public void ILCompiler_InstanceBlockBodyLambdaCapturingOnlyThis_DoesNotCreateDisplayClass()
    {
        // Exercise the block-body branch of the 'this'-only instance-lambda path.
        var source = @"
import System

func apply(f: Func<int>): int {
    return f()
}

class Service {
    seed: int = 20

    func Run(): int {
        return apply(() => {
            doubled := seed * 2
            return doubled + 2
        })
    }
}

func main(): int {
    service := new Service()
    return service.Run()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasDisplayClass = assembly.GetTypes().Any(type => type.Name.Contains("<>c__DisplayClass", StringComparison.Ordinal))
            };
        });

        Assert.Equal(42, Assert.IsType<int>(result.Value));
        Assert.False(result.HasDisplayClass, "A block-body lambda that only captures 'this' should bind to the instance without a display class.");
    }

    [Fact]
    public void ILCompiler_DirectMutableCapturedLambdaLocal_PreservesMutation()
    {
        var source = @"
func main(): int {
    value := 0
    increment := () => {
        value += 1
        return value
    }

    return increment() + increment()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            var opCodes = GetMethodOpCodes(main!);

            return new
            {
                Value = main!.Invoke(null, null),
                CallvirtCount = opCodes.Count(opCode => opCode == OpCodes.Callvirt)
            };
        });

        Assert.Equal(3, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.CallvirtCount);
    }

    [Fact]
    public void ILCompiler_EscapingMutableCapturedLambdaLocal_UsesLiftedStorage()
    {
        var source = @"
import System

func make(): Func<int> {
    value := 1
    getValue: Func<int> = () => value
    value = 4
    return getValue
}

func main(): int {
    getValue := make()
    return getValue()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                HasLiftedStorageField = HasLiftedStorageField(assembly)
            };
        });

        Assert.Equal(4, Assert.IsType<int>(result.Value));
        Assert.True(result.HasLiftedStorageField, "A mutable escaped capture must keep shared lifted storage so post-capture writes are visible.");
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionCapturingByRefParameter()
    {
        var source = @"
func adjust(ref current: int, delta: int): int {
    func project<T>(value: T): int {
        current += delta
        return current
    }

    return project(0)
}

func main(): int {
    value := 40
    return adjust(ref value, 2) + value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(84, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteMemberAssignmentExpressionWithoutReevaluatingReferenceReceiver()
    {
        var source = @"
class Box {
    Value: int
}

class Source {
    Count: int

    func Next(): Box {
        Count += 1
        return new Box { Value: Count }
    }
}

func main(): int {
    source := new Source()
    assigned := source.Next().Value = 5
    return assigned * 10 + source.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(51, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticFieldAndPropertyLoads()
    {
        var source = @"
class State {
    static backing: int

    static Value: int {
        get {
            return State.backing
        }
        set {
            State.backing = value
        }
    }
}

func main(): int {
    State.Value = 4
    State.Value = State.Value + 5
    return State.Value * 10 + State.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(99, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteValueTypeObjectInitializersWithFieldPropertyAndIndexer()
    {
        var source = @"
struct Bag {
    first: int
    second: int

    Sum: int {
        get {
            return first + second
        }
        set {
            second = value - first
        }
    }

    func this[index: int]: int {
        get {
            if index == 0 {
                return first
            }

            return second
        }
        set {
            if index == 0 {
                first = value
            } else {
                second = value
            }
        }
    }

    static func createPair(): Bag {
        return new Bag { first: 3, [1] = 4 }
    }

    static func createTotal(): Bag {
        return new Bag { first: 2, Sum: 9 }
    }
}

func main(): int {
    bag := Bag.createPair()
    other := Bag.createTotal()
    return bag.Sum * 100 + other.Sum * 10
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(790, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticCompoundAndNullCoalesceAssignments()
    {
        var source = @"
class State {
    static Maybe: string
}

func main(): int {
    RuntimeCoverageBag.StaticField = 1
    RuntimeCoverageBag.StaticField += 2

    RuntimeCoverageBag.StaticProperty = 4
    RuntimeCoverageBag.StaticProperty += RuntimeCoverageBag.StaticField

    State.Maybe ??= ""go""
    State.Maybe ??= ""no""

    return RuntimeCoverageBag.StaticField * 100
        + RuntimeCoverageBag.StaticProperty * 10
        + State.Maybe.Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(372, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrStaticMembersAndRuntimeObjectInitializers()
    {
        var source = @"
func touch(ref value: int): void {
    value += 1
}

func main(): int {
    RuntimeCoverageBag.StaticField = 3
    RuntimeCoverageBag.StaticProperty = RuntimeCoverageBag.StaticField + 4

    bag := new RuntimeCoverageBag { Field: 2, Property: 5, [1] = 6 }
    bag.Add(7)
    bag.Add(8)
    bag.Field = bag.Field + RuntimeCoverageBag.StaticField
    bag.Property += bag[1]
    bag[1] = bag[1] + bag.ValuesCount

    touch(ref bag.Field)
    touch(ref RuntimeCoverageBag.StaticField)

    return RuntimeCoverageBag.StaticField * 1000000
        + RuntimeCoverageBag.StaticProperty * 100000
        + bag.Field * 10000
        + bag.Property * 1000
        + bag[1] * 100
        + bag.ValuesCount * 10
        + bag.ValuesSum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4771835, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrWithExpressionsOnClassAndStruct()
    {
        var source = @"
func main(): int {
    original := new RuntimeCoverageBag { Field: 2, Property: 3 }
    copy := original with { Field: 5, Property: original.Property + 4 }

    point := new RuntimeCoverageStruct { Field: 7, Property: 8 }
    pointCopy := point with { Field: 9, Property: point.Property + 1 }

    return original.Field * 10000000
        + original.Property * 1000000
        + copy.Field * 100000
        + copy.Property * 10000
        + point.Field * 1000
        + point.Property * 100
        + pointCopy.Field * 10
        + pointCopy.Property
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(23577899, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionWithExplicitTypeArgumentsNamedDefaultsAndParams()
    {
        var source = @"
func main(): int {
    seed := 7
    extras := [8, 9]

    func collect<T>(value: T, prefix: int = 1, params rest: T[]): int {
        return prefix * 100 + (rest.Length + 1) * 10 + seed
    }

    first := collect<int>(value: 5, prefix: 2)
    second := collect<int>(4, 3, extras)
    third := collect<int>(6)
    return first + second + third
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(671, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanAssignToHighIndexParameter()
    {
        var parameters = string.Join(", ", Enumerable.Range(0, 260).Select(index => $"p{index}: int"));
        var arguments = string.Join(", ", Enumerable.Range(0, 260));
        var source = $$"""
func mutate({{parameters}}): int {
    p259 = p259 + p1
    return p259
}

func main(): int {
    return mutate({{arguments}})
}
""";

        var result = CompileAndInvoke(source);
        Assert.Equal(260, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParametersAcrossIndirectStorageKinds()
    {
        var source = @"
struct Pair {
    Left: int
    Right: int
}

func bumpByte(ref value: byte): void {
    value = (byte)(value + 1)
}

func bumpShort(ref value: short): void {
    value = (short)(value + 2)
}

func setChar(ref value: char): void {
    value = (char)90
}

func bumpLong(ref value: long): void {
    value += 3
}

func flipBool(ref value: bool): void {
    value = !value
}

func bumpFloat(ref value: float): void {
    value = value + 1.5f
}

func bumpDouble(ref value: double): void {
    value = value + 2.5d
}

func replacePair(ref value: Pair): void {
    value = new Pair { Left: value.Left + 4, Right: value.Right + 5 }
}

func decorate(ref value: string): void {
    value = value + ""!""
}

func bumpInt(ref value: int): void {
    value += 6
}

func main(): int {
    b: byte = 1
    s: short = 2
    c: char = (char)65
    l: long = 3
    flag := false
    f: float = 4.0f
    d: double = 5.0d
    pair := new Pair { Left: 6, Right: 7 }
    text := ""hi""
    values := [10, 20, 30]

    bumpByte(ref b)
    bumpShort(ref s)
    setChar(ref c)
    bumpLong(ref l)
    flipBool(ref flag)
    bumpFloat(ref f)
    bumpDouble(ref d)
    replacePair(ref pair)
    decorate(ref text)
    bumpInt(ref values[^1])

    boolDigit := flag ? 1 : 0
    return b * 100000000
        + s * 10000000
        + ((int)c - 60) * 1000000
        + (int)l * 100000
        + boolDigit * 10000
        + (int)f * 1000
        + (int)d * 100
        + pair.Left * 10
        + pair.Right
        + values[^1]
        + text.Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(270615851, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteArrayStoresForPrimitiveReferenceAndValueTypes()
    {
        var source = @"
struct Pair {
    Left: int
    Right: int
}

func main(): int {
    longs: long[] = [1, 2]
    flags: bool[] = [false, false]
    floats: float[] = [1.0f]
    doubles: double[] = [2.0d]
    texts: string[] = [""a""]
    pairs: Pair[] = [new Pair { Left: 3, Right: 4 }]

    longs[1] = 5
    flags[0] = true
    floats[0] = 6.5f
    doubles[0] = 7.5d
    texts[0] = ""ok""
    pairs[0] = new Pair { Left: 8, Right: 9 }

    return (int)longs[1] * 100000
        + (flags[0] ? 1 : 0) * 10000
        + (int)floats[0] * 1000
        + (int)doubles[0] * 100
        + texts[0].Length * 10
        + pairs[0].Left
        + pairs[0].Right
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(516737, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteDynamicArrayConstruction()
    {
        var source = @"
func make(size: int): int[] {
    values := new int[](size)
    for i := 0; i < values.Length; i++ {
        values[i] = i * 3
    }

    return values
}

func main(): int {
    values := make(5)
    return values.Length * 1000 + values[0] * 100 + values[4]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5012, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionInsideClosureWithClosureFieldCapture()
    {
        var source = @"
func main(): int {
    offset := 2

    compute := () => {
        baseline := 5

        func project<T>(value: T): int {
            return baseline * 10 + offset
        }

        return project<string>(""x"")
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(52, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsNUnitIgnoreMetadataForSkippedTests()
    {
        var source = @"
test ""needs network"" skip ""no network in CI"" {
    assert true
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        CompileAndInspect(source, config, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("NeedsNetwork", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);

            var ignoreAttribute = GetCustomAttribute(testMethod!, "NUnit.Framework.IgnoreAttribute");
            Assert.Equal(new object?[] { "no network in CI" }, GetAttributeArguments(ignoreAttribute));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteUserDefinedBitwiseShiftAndUnaryOperatorOverloads()
    {
        var source = @"
struct Flags {
    Value: int

    static func operator &(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value & b.Value }
    }

    static func operator |(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value | b.Value }
    }

    static func operator ^(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value ^ b.Value }
    }

    static func operator <<(a: Flags, amount: int): Flags {
        return new Flags { Value: a.Value << amount }
    }

    static func operator >>(a: Flags, amount: int): Flags {
        return new Flags { Value: a.Value >> amount }
    }

    static func operator ~(value: Flags): Flags {
        return new Flags { Value: ~value.Value }
    }
}

func main(): int {
    a := new Flags { Value: 6 }
    b := new Flags { Value: 3 }

    masked := a & b
    merged := a | b
    toggled := a ^ b
    shifted := (a << 1) >> 2
    inverted := ~b

    return masked.Value * 100000
        + merged.Value * 10000
        + toggled.Value * 1000
        + shifted.Value * 100
        + (0 - inverted.Value)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(275304, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithObjectInitializer()
    {
        var source = @"
class LambdaBox {
    Value: int
    Items: int[]
}

func main(): int {
    offset := 2
    box := new LambdaBox { Value: 5, Items: [6, 7] }

    compute := () => {
        box.Value = box.Value + offset
        snapshot := new LambdaBox { Value: box.Value + offset, Items: [offset, box.Items[0]] }
        return snapshot.Value * 100
            + snapshot.Items[1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(906, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithTuple()
    {
        var source = @"
func main(): int {
    offset := 2
    value := 5

    compute := () => {
        pair := (offset, value)
        return pair.Item1 * 100
            + pair.Item2
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(205, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithObjectInitializerAndTuple()
    {
        var source = @"
class LambdaBox {
    Value: int
    Items: int[]
}

func main(): int {
    offset := 2
    box := new LambdaBox { Value: 5, Items: [6, 7] }

    compute := () => {
        box.Value = box.Value + offset
        snapshot := new LambdaBox { Value: box.Value + offset, Items: [offset, box.Items[0]] }
        pair := (offset, box.Value)
        return snapshot.Value * 100
            + pair.Item2 * 10
            + snapshot.Items[1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(976, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithRangeSpreadAndIndexFromEnd()
    {
        var source = @"
func main(): int {
    offset := 2
    values := [1, 2, 3, 4]
    label := ""wxyz""

    compute := () => {
        pieces := [offset, ...values[1..3]]
        return pieces[0] * 100
            + pieces[1] * 10
            + pieces[2]
            + (int)label[^1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(345, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithNestedLambdaCheckedAndUnchecked()
    {
        var source = @"
func main(): int {
    offset := 2

    compute := () => {
        nested: Func<int> = () => offset + 1
        ternaryValue := offset > 1 ? nested() : 0
        checkedValue := checked(offset + 1)
        uncheckedValue := unchecked(2147483647 + 1)

        if uncheckedValue < 0 {
            return ternaryValue + checkedValue + 1
        }

        return 0
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithLockLoopsAndFinally()
    {
        var source = @"
import System

func main(): int {
    offset := 2
    values := [1, 2, 3]
    gate := new object()

    compute := () => {
        total := 0
        index := 0

        try {
            lock gate {
                for value in values {
                    total += value + offset
                }

                while index < 3 {
                    index += 1
                    if index == 2 {
                        continue
                    }

                    total += index

                    if index == 3 {
                        break
                    }
                }
            }
        } finally {
            total += offset
        }

        return total
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(18, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithPatternMatchAndIsBinding()
    {
        var source = @"
func main(): int {
    offset := 2
    values := [1, 2, 3, 4]
    maybe: object = ""hi""

    compute := () => {
        total := 0

        if maybe is string s {
            total += s.Length
        }

        matched := match values {
            [1, 2, 3, 4] => offset + 5
            _ => 0
        }

        return total + matched
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(9, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithSwitchAssertAndLocalFunction()
    {
        var source = @"
import System

func main(): int {
    seed := 2
    items := [1, 2, 3]
    maybe: object = ""xy""

    compute := () => {
        total := 0

        first, second := (seed, items[0])

        switch first + second {
            case 3 => total += 10
            default => total += 1
        }

        assert total == 10

        assert throws InvalidOperationException {
            throw new InvalidOperationException(""boom"")
        }

        print second

        func addLocal(value: int): int => value + seed

        if maybe is string text {
            total += addLocal(text.Length)
        }

        return total
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(14, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericLocalFunctionFromDelegateAndArrayArguments()
    {
        var source = @"
func main(): int {
    prefix := 2
    formatter: Func<int, string> = value => ""v="" + (value + prefix)

    func project<T>(items: T[], format: Func<T, string>): int {
        return items.Length * 10 + prefix
    }

    value := project([3, 4], formatter)
    return value * 10 + formatter(5).Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(223, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsComplexClrAttributeArgumentShapes()
    {
        var source = @"
import System
import NSharpLang.Tests

[RuntimeCoverage(
    RuntimeCoverageMetadata.DefaultCode,
    [""alpha"", nameof(Covered), RuntimeCoverageMetadata.Label],
    Enabled = !false,
    Mode = RuntimeCoverageMetadata.DefaultMode,
    RuntimeType = typeof(RuntimeCoverageBag),
    Targets = AttributeTargets.Class | AttributeTargets.Struct)]
class Covered {
}";

        CompileAndInspect(source, assembly =>
        {
            var coveredType = assembly.GetType("Covered");
            Assert.NotNull(coveredType);

            var attribute = GetCustomAttribute(coveredType!, "NSharpLang.Tests.RuntimeCoverageAttribute");
            Assert.Equal(
                new object?[] { 19, new object?[] { "alpha", "Covered", "runtime" } },
                GetAttributeArguments(attribute));
            Assert.True(Assert.IsType<bool>(GetNamedAttributeValue(attribute, "Enabled")));
            Assert.Equal((int)ILCompilerCallMode.Fast, Assert.IsType<int>(GetNamedAttributeValue(attribute, "Mode")));
            Assert.Equal(typeof(RuntimeCoverageBag), Assert.IsAssignableFrom<Type>(GetNamedAttributeValue(attribute, "RuntimeType")));
            Assert.Equal(
                (int)(AttributeTargets.Class | AttributeTargets.Struct),
                Assert.IsType<int>(GetNamedAttributeValue(attribute, "Targets")));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsInteropVisibilityModifiersAndHonorsExplicitPublicMigrationEscape()
    {
        var source = @"
internal class VisibilityBox {
    public shown: int
    private hidden: int
    protected guarded: int
    internal shared: int
    protected internal bridge: int

    public func shownMethod(): int {
        return 0
    }

    private func hiddenMethod(): int {
        return 1
    }

    protected func guardedMethod(): int {
        return 2
    }

    internal func sharedMethod(): int {
        return 3
    }

    protected internal func bridgeMethod(): int {
        return 4
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var type = assembly.GetType("VisibilityBox");
            Assert.NotNull(type);
            Assert.False(type!.IsPublic);

            var fields = type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.Null(type.GetField("shown", BindingFlags.Public | BindingFlags.Instance));
            Assert.NotNull(type.GetProperty("shown", BindingFlags.Public | BindingFlags.Instance));
            Assert.Contains(fields, field => field.Name == "hidden" && field.IsPrivate);
            Assert.Contains(fields, field => field.Name == "guarded" && field.IsFamily);
            Assert.Contains(fields, field => field.Name == "shared" && field.IsAssembly);
            Assert.Contains(fields, field => field.Name == "bridge" && field.IsFamilyOrAssembly);

            var methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .Where(method => !method.IsSpecialName)
                .ToArray();
            Assert.Contains(methods, method => method.Name == "shownMethod" && method.IsPublic);
            Assert.Contains(methods, method => method.Name == "hiddenMethod" && method.IsPrivate);
            Assert.Contains(methods, method => method.Name == "guardedMethod" && method.IsFamily);
            Assert.Contains(methods, method => method.Name == "sharedMethod" && method.IsAssembly);
            Assert.Contains(methods, method => method.Name == "bridgeMethod" && method.IsFamilyOrAssembly);
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanInferTopLevelGenericBindingsFromArrayArguments()
    {
        var source = @"
func second<T>(items: T[]): T {
    return items[1]
}

func main(): int {
    return second([3, 4, 5])
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTopLevelGenericDelegateInvocationAcrossListAndTuple()
    {
        var source = @"
import System.Collections.Generic

func project<T>(items: List<T>, pair: (T, T), format: Func<T, string>): int {
    return items.Count * 100
        + format(pair.Item1).Length * 10
        + format(pair.Item2).Length
}

func main(): int {
    items := new List<int>()
    items.Add(7)
    items.Add(8)
    format: Func<int, string> = value => ""n"" + value
    return project<int>(items, (7, 8), format)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(222, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_CanWrapImplicitAsyncReturnTypesForEntryPointAndHelpersAsync()
    {
        var source = @"
import System.Threading.Tasks

async func helper(): int {
    await Task.Yield()
    return 7
}

async func main() {
    value := await helper()
    assert value == 7
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal("System.Threading.Tasks.VoidTaskResult", result?.GetType().FullName);
    }

    [Fact]
    public async Task ILCompiler_CanWrapImplicitAsyncReturnTypesForLocalFunctionsAsync()
    {
        var source = @"
import System.Threading.Tasks

async func main(): Task<int> {
    async func helper(): int {
        await Task.Yield()
        return 4
    }

    return await helper()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaCapturingHighIndexParameters()
    {
        var parameters = string.Join(", ", Enumerable.Range(0, 260).Select(index => $"p{index}: int"));
        var arguments = string.Join(", ", Enumerable.Range(0, 260));
        var source = $$"""
func capture({{parameters}}): int {
    compute := () => p0 + p1 + p2 + p3 + p4 + p259
    return compute()
}

func main(): int {
    return capture({{arguments}})
}
""";

        var result = CompileAndInvoke(source);
        Assert.Equal(269, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanLiftCapturedEnumParametersFromUserTypes()
    {
        var source = @"
import System

enum Priority {
    Low,
    High
}

class Item {
    Priority: Priority
}

class Service {
    func matches(priority: Priority): int {
        predicate: Func<Item, bool> = item => item.Priority == priority
        item := new Item { Priority: Priority.High }
        return predicate(item) ? 1 : 0
    }
}

func main(): int {
    service := new Service()
    return service.matches(Priority.High)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanDispatchThroughDuckInterfaceCollections()
    {
        var source = @"
import System.Collections.Generic

duck interface INotifier {
    func Notify(message: string): string
}

class ConsoleNotifier {
    func Notify(message: string): string {
        return ""console:"" + message
    }
}

class Hub {
    notifiers: List<INotifier>

    constructor() {
        notifiers = new List<INotifier>()
        notifiers.Add(new ConsoleNotifier())
    }

    func Broadcast(message: string): string {
        result := """"
        for notifier in notifiers {
            result = notifier.Notify(message)
        }
        return result
    }
}

func main(): string {
    return new Hub().Broadcast(""ok"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("console:ok", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_PrefersInstanceMembersOverStaticTypeLookupForCapitalizedNames()
    {
        var source = @"
record Filter {
    Query: string

    func HasQuery(): bool {
        return Query.Length > 0
    }
}

func main(): bool {
    filter := new Filter { Query: ""hi"" }
    return filter.HasQuery()
}";

        var result = CompileAndInvoke(source);
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericLocalFunctionAcrossNamedTupleDelegateAndParams()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    seed := 5

    func project<T>(items: List<T>, pair: (T, T), format: Func<T, string>, bonus: int = 2, params extras: T[]): int {
        return seed * 1000
            + bonus * 100
            + items.Count * 10
            + extras.Length
            + format(pair.Item2).Length
    }

    values: List<int> = [7, 8, 9]
    extras := [1, 2]
    formatter: Func<int, string> = value => ""v"" + value

    return project(items: values, pair: (7, 8), format: formatter, extras: extras)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5234, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferClrGenericBindingsFromTupleAndDelegateArguments()
    {
        var source = @"
func main(): int {
    formatter: Func<int, string> = value => ""v"" + value
    return ILCompilerCallHelpers.ScorePair((7, 8), formatter)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(22, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindClrGenericNamedOptionalAndDirectParamsArrayArguments()
    {
        var source = @"
func main(): int {
    extras := [4, 5]
    return ILCompilerCallHelpers.DescribeGeneric(value: 7, rest: extras)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(121, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRealBclNamedOptionalAndEnumerableOverloadCalls()
    {
        var source = @"
import System
import System.Collections.Generic

func main(): string {
    names := new List<string>()
    names.Add(""alpha"")
    names.Add(""beta"")

    joined := String.Join(separator: "","", values: names)
    formatted := String.Format(format: ""{0}-{1}"", arg0: ""left"", arg1: ""right"")
    return joined + ""|"" + formatted
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("alpha,beta|left-right", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaCapturingMultipleParameters()
    {
        var source = @"
func make(a: int, b: int, c: int, d: int, e: int): Func<int> {
    bonus := 1
    compute := () => a + b + c + d + e + bonus
    return compute
}

func main(): int {
    return make(1, 2, 3, 4, 5)()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(16, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanResolveNestedClrTypesForStaticMembers()
    {
        var source = @"
import System
import System.IO

func main(): string {
    return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "".taskr"")
}";

        var expected = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".taskr");

        var result = CompileAndInvoke(source);
        Assert.Equal(expected, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanResolveFrameworkReferencedStaticTypes()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

func main(args: string[]): bool {
    builder := WebApplication.CreateBuilder(args)
    return builder != null
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        var result = CompileAndInvoke(source, config, "main", new object[] { Array.Empty<string>() });
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanBindImportedFrameworkExtensionMethods()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

func main(args: string[]): bool {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()
    app.UseDefaultFiles()
    return app != null
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        var result = CompileAndInvoke(source, config, "main", new object[] { Array.Empty<string>() });
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanInferAspNetRequestDelegateForMapGetLambda()
    {
        var source = @"
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http

func main(args: string[]): bool {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()
    app.MapGet(""/api/health"", context => context.Response.WriteAsync(""ok""))
    return app != null
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        var result = CompileAndInvoke(source, config, "main", new object[] { Array.Empty<string>() });
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanInferAspNetRequestDelegateForMapPostBlockLambda()
    {
        var source = @"
import System.IO
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http

func main(args: string[]): bool {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()
    app.MapPost(""/api/issues"", context => {
        reader := new StreamReader(context.Request.Body)
        body := reader.ReadToEndAsync().Result

        if body == """" {
            context.Response.StatusCode = 400
            return context.Response.WriteAsync(""Invalid request body"")
        }

        context.Response.StatusCode = 201
        return context.Response.WriteAsync(body)
    })
    return app != null
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        var result = CompileAndInvoke(source, config, "main", new object[] { Array.Empty<string>() });
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanInferAspNetRequestDelegateForMethodGroup()
    {
        var source = @"
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http

class Routes {
    func Map(app: WebApplication) {
        app.MapGet(""/api/issues"", HandleList)
    }

    func HandleList(context: HttpContext): Task {
        return context.Response.WriteAsync(""ok"")
    }
}

func main(args: string[]): bool {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()
    routes := new Routes()
    routes.Map(app)
    return app != null
}";

        var config = new ProjectConfig
        {
            Sdk = "Microsoft.NET.Sdk.Web",
            Dependencies = [new Reference { Framework = "Microsoft.AspNetCore.App" }]
        };

        var result = CompileAndInvoke(source, config, "main", new object[] { Array.Empty<string>() });
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupPreservesVirtualDispatch()
    {
        var source = @"
import System

class Base {
    virtual func Value(): string {
        return ""base""
    }

    func Get(): Func<string> {
        return Value
    }
}

class Derived : Base {
    override func Value(): string {
        return ""derived""
    }
}

func main(): string {
    item: Base = new Derived()
    getValue := item.Get()
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("derived", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupCanUseInheritedInstanceMethod()
    {
        var source = @"
import System

class Base {
    func Value(): string {
        return ""base""
    }
}

class Derived : Base {
    func Get(): Func<string> {
        return Value
    }
}

func main(): string {
    item := new Derived()
    getValue := item.Get()
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("base", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupBoxesStructReceiverForDelegate()
    {
        var source = @"
import System

struct Counter {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func GetValue(): int {
        return Value
    }

    func Get(): Func<int> {
        return GetValue
    }
}

func main(): int {
    counter := new Counter(7)
    getValue := counter.Get()
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupAllowsGenericTypeParameters()
    {
        var source = @"
import System

class Box<T> {
    value: T

    constructor(value: T) {
        this.value = value
    }

    func Value(): T {
        return value
    }

    func Getter(): Func<T> {
        return Value
    }
}

func main(): string {
    box := new Box<string>(""ok"")
    getValue := box.Getter()
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("ok", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRejectsNumericParameterConversion()
    {
        var source = @"
import System

func AcceptLong(value: long) {
}

func main(): bool {
    action: Action<int> = AcceptLong
    return action != null
}";

        var error = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("AcceptLong", error.Message);
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRejectsRefParameterMismatch()
    {
        var source = @"
import System

func Bump(ref value: int) {
    value = value + 1
}

func main(): bool {
    action: Action<int> = Bump
    return action != null
}";

        var error = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("Bump", error.Message);
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRejectsExpressionTreeTarget()
    {
        var source = @"
import NSharpLang.Tests

func Handler() {
}

func main(): bool {
    RuntimeDelegateOverloadHelpers.AcceptExpression(Handler)
    return true
}";

        var error = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("AcceptExpression", error.Message);
    }

    [Fact]
    public void ILCompiler_RuntimeExtensionReceiverRejectsNumericConversion()
    {
        var source = @"
import NSharpLang.Tests

func main(): long {
    value := 1
    return value.ExtensionLong()
}";

        var error = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("ExtensionLong", error.Message);
    }

    [Fact]
    public void ILCompiler_RuntimeMethodGroupOverloadPrefersExactParameterMatch()
    {
        var source = @"
import NSharpLang.Tests

func AcceptObject(value: object) {
}

func main(): int {
    return RuntimeDelegateOverloadHelpers.UseMethodGroup(AcceptObject)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_RuntimeMethodGroupBindsGenericDelegateReturnType()
    {
        var source = @"
import System.Linq

func Convert(value: int): string {
    return value.ToString()
}

func main(): string {
    values := [1, 2]
    texts := values.Select(Convert).ToArray()
    return texts[0]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("1", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_LocalFunctionMethodGroupCanMaterializeForSystemDelegate()
    {
        var source = @"
import NSharpLang.Tests

func main(): string {
    func Handle(value: int): string {
        return value.ToString()
    }

    return DelegateInteropProbe.CaptureDelegate(Handle)
}";

        var result = CompileAndInvoke(source);
        Assert.False(string.IsNullOrWhiteSpace(Assert.IsType<string>(result)));
    }

    [Fact]
    public void ILCompiler_RuntimeLambdaRejectsConcreteObjectReturnForNonObjectDelegate()
    {
        var source = @"
import System

func main(): int {
    lazy := new Lazy<string>(() => new object())
    return 0
}";

        var error = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("Lazy", error.Message);
    }

    [Fact]
    public void ILCompiler_BlockLambdaReturnInferenceRestoresNestedLocalTypes()
    {
        var source = @"
import System

func main(): string {
    lazy := new Lazy<string>(() => {
        x := ""outer""
        if false {
            x := 1
            return x.ToString()
        }

        return x
    })

    return lazy.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("outer", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_BlockLambdaReturnInferenceHandlesErrorTupleResultTypes()
    {
        var source = @"
import System

class Issue {
    Title: string
}

class IssueService {
    func CreateIssue(): Issue {
        return new Issue { Title: ""created"" }
    }
}

class Routes {
    service: IssueService

    constructor(service: IssueService) {
        this.service = service
    }

    func Handler(): Func<string> {
        return () => {
            issue, err := service.CreateIssue()
            if err != null {
                return err.Message
            }

            return issue.Title
        }
    }
}

func main(): string {
    handler := new Routes(new IssueService()).Handler()
    return handler()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("created", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRespectsCapturedLocalFunctionShadowing()
    {
        var source = @"
import System

func Handle(): string {
    return ""outer""
}

func main(): string {
    value := ""inner""

    func Handle(): string {
        return value
    }

    getValue: Func<string> = Handle
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("inner", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRespectsDirectLocalFunctionShadowing()
    {
        var source = @"
import System

func Handle(): string {
    return ""outer""
}

func main(): string {
    func Handle(): string {
        return ""inner""
    }

    getValue: Func<string> = Handle
    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("inner", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_ContextualMethodGroupRespectsInstanceMemberShadowing()
    {
        var source = @"
import System

func Handle(): string {
    return ""outer""
}

class Routes {
    func Handle(): string {
        return ""inner""
    }

    func Run(): string {
        getValue: Func<string> = Handle
        return getValue()
    }
}

func main(): string {
    routes := new Routes()
    return routes.Run()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("inner", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindRuntimeExpressionTreeLambdaForGenericFluentChains()
    {
        var source = @"
import NSharpLang.Tests

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<RuntimeExpressionEntity>(entity => {
        entity.Property(e => e.Id).ValueGeneratedOnAdd()
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(int).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeWhereSelect()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1, 2, 3]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    filtered: IQueryable<int> = Queryable.Where<int>(query, x => x > 1)
    texts: IQueryable<string> = Queryable.Select<int, string>(filtered, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("2:3", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeCallArguments()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [2, 3]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    texts: IQueryable<string> = Queryable.Select<int, string>(query, x => x.ToString(""D2""))
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("02:03", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeModulo()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1, 2, 3, 4]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    odds: IQueryable<int> = Queryable.Where<int>(query, x => x % 2 == 1)
    texts: IQueryable<string> = Queryable.Select<int, string>(odds, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("1:3", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeUnaryNegation()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1, 2, 3]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    filtered: IQueryable<int> = Queryable.Where<int>(query, x => -x < -1)
    texts: IQueryable<string> = Queryable.Select<int, string>(filtered, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("2:3", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeHardCast()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1, 2, 3]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    filtered: IQueryable<int> = Queryable.Where<int>(query, x => (double)x > 1.5)
    texts: IQueryable<string> = Queryable.Select<int, string>(filtered, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("2:3", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeBitwiseOperators()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1, 2, 3, 4]
    query: IQueryable<int> = Queryable.AsQueryable<int>(source)
    filtered: IQueryable<int> = Queryable.Where<int>(
        query,
        x => ((x & 1) == 1) || ((x | 1) == 3) || ((x ^ 3) == 0))
    texts: IQueryable<string> = Queryable.Select<int, string>(filtered, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("1:2:3", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueryableExpressionTreeShiftOperators()
    {
        var source = @"
import System
import System.Linq

func main(): string {
    source := [1L, 2L, 3L, 4L, 5L]
    query: IQueryable<long> = Queryable.AsQueryable<long>(source)
    filtered: IQueryable<long> = Queryable.Where<long>(
        query,
        x => ((x << 1) == 4L) || ((x >> 1) == 2L))
    texts: IQueryable<string> = Queryable.Select<long, string>(filtered, x => x.ToString())
    return String.Join("":"", texts)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("2:4:5", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanEmitAnonymousObjectExpressionTreeLambdas()
    {
        var source = @"
import NSharpLang.Tests

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<RuntimeExpressionEntity>(entity => {
        entity.HasKey(e => new() { Id: e.Id, OtherId: e.OtherId })
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Contains("<>f__AnonymousType", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExpressionTreeRelationshipFluentChains()
    {
        var source = @"
import NSharpLang.Tests

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<RuntimeExpressionEntity>(entity => {
        entity.HasOne(e => e.Related).WithMany(r => r.Entities).HasConstraintName(""fk"")
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Contains("RuntimeReferenceCollectionBuilder", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExpressionTreeRelationshipFluentChainsOverEmittedTypes()
    {
        var source = @"
import System.Collections.Generic
import NSharpLang.Tests

class LocalEntity {
    Id: int
    Related: LocalRelated?
}

class LocalRelated {
    Entities: ICollection<LocalEntity> = new List<LocalEntity>()
}

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<LocalEntity>(entity => {
        entity.HasOne(e => e.Related).WithMany(r => r.Entities).HasConstraintName(""fk"")
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Contains("RuntimeReferenceCollectionBuilder", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExpressionTreeReferenceRelationshipFluentChains()
    {
        var source = @"
import NSharpLang.Tests

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<RuntimeExpressionEntity>(entity => {
        entity.HasOne(e => e.Related)
            .WithOne(r => r.Entity)
            .HasPrincipalKey<RuntimeRelatedExpressionEntity>(r => r.PrincipalId)
            .HasForeignKey<RuntimeExpressionEntity>(e => e.Id)
            .OnDelete(ILCompilerCallMode.Fast)
            .HasConstraintName(""fk"")
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Contains("RuntimeReferenceReferenceBuilder", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExpressionTreeReferenceRelationshipFluentChainsOverEmittedTypes()
    {
        var source = @"
import NSharpLang.Tests

class LocalReferenceEntity {
    Id: int
    Related: LocalReferenceRelated?
}

class LocalReferenceRelated {
    Entity: LocalReferenceEntity?
    PrincipalId: int
}

func main(): string {
    builder := new RuntimeExpressionModelBuilder()
    builder.Entity<LocalReferenceEntity>(entity => {
        entity.HasOne(e => e.Related)
            .WithOne(r => r.Entity)
            .HasPrincipalKey<LocalReferenceRelated>(r => r.PrincipalId)
            .HasForeignKey<LocalReferenceEntity>(e => e.Id)
            .OnDelete(ILCompilerCallMode.Fast)
            .HasConstraintName(""fk"")
    })

    return builder.LastPropertyTypeName
}";

        var result = CompileAndInvoke(source);
        Assert.Contains("RuntimeReferenceReferenceBuilder", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanLiftCapturedParametersTypedAsRuntimeGenericsOverEmittedTypes()
    {
        var source = @"
import System.Collections.Generic

class Item {
    Value: int
}

class Counter {
    func Count(items: List<Item>): int {
        getCount := () => items.Count
        return getCount()
    }
}

func main(): int {
    counter := new Counter()
    items: List<Item> = [new Item { Value: 1 }, new Item { Value: 2 }]
    return counter.Count(items)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanAccessCurrentTypePropertiesByBareIdentifier()
    {
        var source = @"
class Person {
    FirstName: string
    LastName: string

    FullName: string => FirstName + "" "" + LastName

    func Greeting(): string => ""Hello, "" + FullName + ""!""
}

func main(): string {
    person := new Person { FirstName: ""Ada"", LastName: ""Lovelace"" }
    return person.Greeting()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("Hello, Ada Lovelace!", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindDeclaredExtensionMethodsInsideStaticClasses()
    {
        var source = @"
static class StringExtensions {
    static func Capitalize(this s: string): string {
        if s.Length == 0 {
            return s
        }

        return s.Substring(0, 1).ToUpper() + s.Substring(1)
    }
}

func main(): string {
    return ""hello"".Capitalize()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("Hello", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindDeclaredExtensionMethodsWithLambdaParameters()
    {
        var source = @"
import System

func Times(this n: int, action: Func<int, void>) {
    for i := 0; i < n; i++ {
        action(i)
    }
}

func main(): int {
    total := 0
    5.Times(i => total += i)
    return total
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericTypeArgumentsForParamsMethods()
    {
        var source = @"
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main(): int {
    values := CreateList(1, 2, 3)
    return values.Count * 10 + values[0]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(31, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindNullLiteralsInDeclaredParamsCollections()
    {
        var source = @"
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main(): int {
    values := CreateList<int?>(1, null, 3, null)
    return values.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExplicitNullableTypeArgumentsInParamsMethods()
    {
        var source = @"
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main(): int {
    values := CreateList<int?>(1, null, 3, null, 5)
    return values.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindExplicitArrayTypeArgumentsInParamsMethods()
    {
        var source = @"
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main(): int {
    values := CreateList<int[]>([1, 2], [3, 4], [5, 6])
    return values.Count * 10 + values[0][1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(32, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteParamsSpanAndReadOnlySpanArguments()
    {
        var source = @"
import System

func SumReadOnlySpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total += numbers[i]
    }

    return total
}

func ModifyValues(params values: Span<int>): int {
    for i := 0; i < values.Length; i++ {
        values[i] = values[i] * 2
    }

    return values[0] + values[1] + values[2]
}

func main(): int {
    return SumReadOnlySpan(1, 2, 3) + ModifyValues(4, 5, 6)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(36, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericIterators()
    {
        var source = @"
import System
import System.Collections.Generic

func* Repeat<T>(value: T, count: int): IEnumerable<T> {
    i := 0
    while i < count {
        yield value
        i = i + 1
    }
}

func main(): string {
    return String.Join("","", Repeat(""x"", 3))
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("x,x,x", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanApplyWithExpressionsToRecordStructPrimaryConstructorMembers()
    {
        var source = @"
record struct Color(r: byte, g: byte, b: byte) {
    func ToHex(): string => $""#{r:X2}{g:X2}{b:X2}""
}

func main(): string {
    color := new Color(255, 0, 0)
    updated := color with { g: 128 }
    return updated.ToHex()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("#FF8000", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanEmitIntMinValueLiteral()
    {
        var source = @"
func main(): int {
    min := -2147483648
    return unchecked(min - 1)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(int.MaxValue, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanEmitNestedTypeDeclarations()
    {
        var source = @"
class BankAccount {
    enum Status {
        Active,
        Frozen
    }

    class Transaction {
        Amount: int
    }

    static func GetStatus(): BankAccount.Status {
        return BankAccount.Status.Active
    }
}

func main(): int {
    return (int)BankAccount.GetStatus()
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var bankAccountType = assembly.GetType("BankAccount", throwOnError: true)!;
            Assert.NotNull(bankAccountType.GetNestedType("Status", BindingFlags.Public | BindingFlags.NonPublic));
            Assert.NotNull(bankAccountType.GetNestedType("Transaction", BindingFlags.Public | BindingFlags.NonPublic));

            var programType = assembly.GetType("Program", throwOnError: true)!;
            var mainMethod = programType.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(mainMethod);
            return mainMethod!.Invoke(null, null);
        });

        Assert.Equal(0, Assert.IsType<int>(result));
    }

    // ---- foreach over Span<T> / ReadOnlySpan<T> lowering (allocation-free index loop) ----

    /// <summary>
    /// Decodes a method body and returns the simple names of every method referenced by a
    /// call/callvirt/newobj instruction. Used to assert that span foreach never resolves an
    /// enumerator (GetEnumerator / MoveNext / get_Current) or allocates one.
    /// </summary>
    private static IReadOnlyList<string> GetReferencedMethodNames(MethodInfo method)
    {
        var body = method.GetMethodBody();
        var il = body?.GetILAsByteArray() ?? Array.Empty<byte>();
        var module = method.Module;
        var genericTypeArgs = method.DeclaringType?.GetGenericArguments();
        var genericMethodArgs = method.GetGenericArguments();
        var names = new List<string>();

        for (var offset = 0; offset < il.Length;)
        {
            var opCodeValue = il[offset++];
            OpCode opCode;
            if (opCodeValue == 0xfe)
            {
                opCode = MultiByteOpCodes[il[offset++]];
            }
            else
            {
                opCode = SingleByteOpCodes[opCodeValue];
            }

            if ((opCode == OpCodes.Call || opCode == OpCodes.Callvirt || opCode == OpCodes.Newobj)
                && opCode.OperandType == OperandType.InlineMethod)
            {
                var token = BitConverter.ToInt32(il, offset);
                try
                {
                    var member = module.ResolveMethod(token, genericTypeArgs, genericMethodArgs);
                    if (member != null)
                    {
                        names.Add(member.Name);
                    }
                }
                catch (Exception)
                {
                    // Best-effort: unresolved tokens are not enumerator references we care about.
                }
            }

            offset += GetOperandSize(opCode.OperandType, il, offset);
        }

        return names;
    }

    [Fact]
    public void ILCompiler_ForeachOverReadOnlySpan_DoesNotAllocateEnumerator()
    {
        // A `params ReadOnlySpan<int>` parameter hands the body a ReadOnlySpan<int> we can
        // iterate with `for ... in`, exercising the span foreach lowering directly.
        var source = @"
func sumSpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for number in numbers {
        total += number
    }
    return total
}

func main(): int {
    return sumSpan(1, 2, 3, 4)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var sumSpan = programType!.GetMethod("sumSpan", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(sumSpan);

            var opCodes = GetMethodOpCodes(sumSpan!);
            var calledMethods = GetReferencedMethodNames(sumSpan!);
            var main = programType.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CalledMethods = calledMethods,
            };
        });

        Assert.Equal(10, Assert.IsType<int>(result.Value));
        // No enumerator allocation in the loop method.
        Assert.Equal(0, result.NewobjCount);
        // No enumerator protocol calls — the loop is a plain index walk.
        Assert.DoesNotContain("GetEnumerator", result.CalledMethods);
        Assert.DoesNotContain("MoveNext", result.CalledMethods);
        Assert.DoesNotContain("get_Current", result.CalledMethods);
    }

    [Fact]
    public void ILCompiler_ForeachOverSpan_DoesNotAllocateEnumerator()
    {
        var source = @"
func sumSpan(params numbers: Span<int>): int {
    total := 0
    for number in numbers {
        total += number
    }
    return total
}

func main(): int {
    return sumSpan(5, 6, 7)
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var sumSpan = programType!.GetMethod("sumSpan", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(sumSpan);

            var opCodes = GetMethodOpCodes(sumSpan!);
            var calledMethods = GetReferencedMethodNames(sumSpan!);
            var main = programType.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);

            return new
            {
                Value = main!.Invoke(null, null),
                NewobjCount = opCodes.Count(opCode => opCode == OpCodes.Newobj),
                CalledMethods = calledMethods,
            };
        });

        Assert.Equal(18, Assert.IsType<int>(result.Value));
        Assert.Equal(0, result.NewobjCount);
        Assert.DoesNotContain("GetEnumerator", result.CalledMethods);
        Assert.DoesNotContain("MoveNext", result.CalledMethods);
        Assert.DoesNotContain("get_Current", result.CalledMethods);
    }

    [Fact]
    public void ILCompiler_ForeachOverReadOnlySpan_IteratesAllElementsInOrder()
    {
        // Behavioral coverage: the lowered loop must visit every element exactly once, in order.
        var source = @"
func lastTimesCount(params numbers: ReadOnlySpan<int>): int {
    last := 0
    count := 0
    for number in numbers {
        last = number
        count += 1
    }
    return last * 100 + count
}

func main(): int {
    return lastTimesCount(2, 4, 6, 8, 9)
}";

        var result = CompileAndInvoke(source);
        // last element 9 * 100 + count 5 = 905
        Assert.Equal(905, Assert.IsType<int>(result));
    }

    // Member writes through NESTED receivers silently LOST the store (oracle defect #22):
    // EmitAddressableExpression had no MemberAccess/array-element case, so any receiver that was
    // not a bare local/param/`this` spilled to a TEMP COPY and the Stfld wrote into the copy —
    // `o.i.X = 5` compiled clean and read back the OLD value. The address builder now recurses:
    // value-typed FIELD hops chain `ldflda` from the rooted local/param/this address, reference
    // hops load the object ref, and array elements use `ldelema`. Probe-pinned shapes; rvalue
    // receivers (List indexer / call results) are analyzer-rejected instead (NL322).
    [Fact]
    public void ILCompiler_NestedValueReceiverMemberWrites_StoreThrough()
    {
        var source = @"
struct Inner {
    X: int
}

struct Outer {
    i: Inner
}

class Holder {
    s: Inner
    constructor(v: Inner) {
        s = v
    }
}

func paramNested(p: Outer): int {
    p.i.X = 5
    return p.i.X
}

func main(): int {
    o := new Outer { i: new Inner { X: 1 } }
    o.i.X = 5
    a := o.i.X

    h := new Holder(new Inner { X: 1 })
    h.s.X = 5
    b := h.s.X

    c := paramNested(new Outer { i: new Inner { X: 1 } })

    o2 := new Outer { i: new Inner { X: 2 } }
    o2.i.X += 3
    d := o2.i.X

    arr := new Inner[2]
    arr[0].X = 5
    e := arr[0].X

    return a + b * 10 + c * 100 + d * 1000 + e * 10000
}";
        var result = CompileAndInvoke(source);
        Assert.Equal(55555, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_ParenthesizedNestedValueReceiverMemberWrites_StoreThrough()
    {
        var source = @"
struct Inner {
    X: int
}

struct Outer {
    i: Inner
}

class Holder {
    s: Inner
    constructor(v: Inner) {
        s = v
    }
}

func paramNested(p: Outer): int {
    (p.i).X = 6;
    return (p.i).X
}

func main(): int {
    o := new Outer { i: new Inner { X: 1 } }
    (o.i).X = 5;
    a := (o.i).X

    h := new Holder(new Inner { X: 1 })
    (h.s).X = 6;
    b := (h.s).X

    c := paramNested(new Outer { i: new Inner { X: 1 } })

    o2 := new Outer { i: new Inner { X: 3 } }
    (o2.i).X += 4;
    d := (o2.i).X

    arr := new Inner[2];
    (arr[0]).X = 8;
    e := (arr[0]).X

    return a + b * 10 + c * 100 + d * 1000 + e * 10000
}";
        var result = CompileAndInvoke(source);
        Assert.Equal(87665, Assert.IsType<int>(result));
    }

    // A NON-async lambda or local function declared inside an ASYNC method inherited the enclosing
    // _currentAsync* return context (saved but never CLEARED for non-async nested bodies): the
    // nested body took the async wrap path and `ret` a ValueTask<T> struct from a method whose CLR
    // signature is T — callers read garbage (0 for int, null for string). Fixed by clearing the
    // trio after SaveAndResetNestedMethodReturnContext in all three LambdaEmitter paths and the
    // local-function emitter (async nested bodies re-establish it). Review-probe-found while
    // routing the columnar async rung.
    [Fact]
    public void ILCompiler_NonAsyncNestedBodiesInsideAsync_DoNotInheritAsyncReturnContext()
    {
        var source = @"
async func one(): int {
    return 1
}

async func viaLambda(): int {
    zero := () => 99
    return zero() + await one()
}

async func viaString(): string {
    mk := () => ""abc""
    return mk()
}

async func viaLocalFn(): int {
    func g(): int {
        return 5
    }
    return g() + await one()
}

func main(): int {
    s := await viaString()
    return await viaLambda() * 1000 + await viaLocalFn() * 10 + s.Length
}";
        var result = CompileAndInvoke(source);
        // pre-fix: lambdas/local fns returned 0/null -> 63 (0*1000 + 1*10 + ...) crashed on null.Length.
        Assert.Equal(100063, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_ThreeDeepStructTailWrite_StoresThrough()
    {
        // class -> class -> struct tail: the reference hops load refs, the struct tail takes
        // ldflda from the last object ref — the deep chain stores through (was silently lost).
        var source = @"
struct S {
    X: int
}

class B {
    s: S
    constructor(v: S) {
        s = v
    }
}

class A {
    b: B
    constructor(v: B) {
        b = v
    }
}

func main(): int {
    a := new A(new B(new S { X: 1 }))
    a.b.s.X = 5
    return a.b.s.X
}";
        var result = CompileAndInvoke(source);
        Assert.Equal(5, Assert.IsType<int>(result));
    }
}
