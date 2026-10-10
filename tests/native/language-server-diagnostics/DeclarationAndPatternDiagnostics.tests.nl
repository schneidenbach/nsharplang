namespace NSharpLang.LanguageServerDiagnostics.Tests

test "DocumentManager unreachable statement uses unreachable keyword span" {
    source := LsdDecodedSource(
        """
func main() {
    return
    print "after"
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unreachable-statement-spans.nl", source),
        "UnreachableStatement",
        null
    )
    LsdAssertSpan(diagnostic, 3, 5, "print".Length)
    LsdAssertLspRange(diagnostic, 2, 4, 9)
}

test "DocumentManager invalid variable declarations use full name spans" {
    source := LsdDecodedSource(
        """
func main() {
    const answer: int
    let value
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///variable-declaration-spans.nl", source)

    constWithoutInitializer := LsdSingle(diagnostics, "InvalidSyntax", "'const'")
    LsdAssertSpan(constWithoutInitializer, 2, 11, "answer".Length)
    LsdAssertLspRange(constWithoutInitializer, 1, 10, 16)

    unknownVariableType := LsdSingle(diagnostics, "InvalidSyntax", "determine the type")
    LsdAssertSpan(unknownVariableType, 3, 9, "value".Length)
    LsdAssertLspRange(unknownVariableType, 2, 8, 13)
}

test "DocumentManager invalid generic constraints use offending constraint spans" {
    source := LsdDecodedSource(
        """
func BadClassStruct<T>(value: T): T where T : class, struct {
    return value
}

func BadStructNew<T>(value: T): T where T : struct, new() {
    return value
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///generic-constraint-spans.nl", source)

    classStructConflict := LsdSingle(diagnostics, "InvalidSyntax", "both 'class' and 'struct'")
    LsdAssertSpan(classStructConflict, 1, 54, "struct".Length)
    LsdAssertLspRange(classStructConflict, 0, 53, 59)

    structNewConflict := LsdSingle(diagnostics, "InvalidSyntax", "Cannot combine 'struct' and 'new()'")
    LsdAssertSpan(structNewConflict, 5, 53, "new()".Length)
    LsdAssertLspRange(structNewConflict, 4, 52, 57)
}

test "DocumentManager generic constraint violations underline offending arguments" {
    source := LsdDecodedSource(
        """
interface IShape {
    func Area(): int
}

class Plain {
}

func Wrap<T>(value: T): T where T : class {
    return value
}

func Box<T>(value: T): T where T : struct {
    return value
}

func Draw<T>(shape: T): T where T : IShape {
    return shape
}

func main() {
    a := Wrap(42)
    b := Box("hi")
    p := new Plain()
    c := Draw(p)
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///generic-constraint-violation-spans.nl", source)

    classViolation := LsdSingle(diagnostics, "GenericConstraintViolation", "`class` constraint")
    LsdAssertSpan(classViolation, 21, 15, "42".Length)
    LsdAssertLspRange(classViolation, 20, 14, 16)

    structViolation := LsdSingle(diagnostics, "GenericConstraintViolation", "`struct` constraint")
    LsdAssertSpan(structViolation, 22, 14, "\"hi\"".Length)
    LsdAssertLspRange(structViolation, 21, 13, 17)

    interfaceViolation := LsdSingle(diagnostics, "GenericConstraintViolation", "does not implement")
    LsdAssertSpan(interfaceViolation, 24, 15, "p".Length)
    LsdAssertLspRange(interfaceViolation, 23, 14, 15)
}

test "DocumentManager generic constraint violation falls back to callee name span" {
    source := LsdDecodedSource(
        """
interface IComparable {
    func CompareTo(other: object): int
}

class Plain {
}

func Max<T>(a: T, b: T): T where T : IComparable {
    return a
}

func main() {
    result := Max(new Plain(), new Plain())
}
"""
    )
    violation := LsdSingle(
        LsdCompilerDiagnostics("file:///generic-constraint-callee-span.nl", source),
        "GenericConstraintViolation",
        "does not implement"
    )
    LsdAssertSpan(violation, 13, 15, "Max".Length)
    LsdAssertLspRange(violation, 12, 14, 17)
}

test "DocumentManager anonymous union with too many arms underlines full union" {
    source := LsdDecodedSource(
        """
type Triple = int | string | bool
"""
    )
    tooManyArms := LsdSingle(
        LsdCompilerDiagnostics("file:///anonymous-union-arms-span.nl", source),
        "InvalidTypeArgument",
        "exactly two arms"
    )
    LsdAssertSpan(tooManyArms, 1, 15, "int | string | bool".Length)
    LsdAssertLspRange(tooManyArms, 0, 14, 33)
}

test "DocumentManager cannot infer type underlines default keyword" {
    source := LsdDecodedSource(
        """
func main() {
    value := default
}
"""
    )
    cannotInfer := LsdSingle(
        LsdCompilerDiagnostics("file:///cannot-infer-default-span.nl", source),
        "CannotInferType",
        null
    )
    LsdAssertSpan(cannotInfer, 2, 14, "default".Length)
    LsdAssertLspRange(cannotInfer, 1, 13, 20)
}

test "DocumentManager local declaration mismatch underlines initializer literal" {
    source := LsdDecodedSource(
        """
func main() {
    count: int = "five"
}
"""
    )
    mismatch := LsdSingle(
        LsdCompilerDiagnostics("file:///local-decl-type-mismatch-span.nl", source),
        "TypeMismatch",
        null
    )
    LsdAssertSpan(mismatch, 2, 18, "\"five\"".Length)
    LsdAssertLspRange(mismatch, 1, 17, 23)
}

test "DocumentManager assignment and operator mismatches use specific expression spans" {
    source := LsdDecodedSource(
        """
func main() {
    x := 0
    x = "text"

    oneBad := 1 - "two"
    bothBad := "one" - "two"
    logicalRight := true && 1
    logicalBoth := 1 && 2

    print x
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///assignment-operator-type-mismatch-spans.nl", source)

    assignmentValue := LsdSingleAt(diagnostics, "TypeMismatch", null, 3, -1)
    assert LsdFieldText(assignmentValue, "Message") == "Type mismatch in assignment — expected 'int' but got 'string'"
    LsdAssertSpan(assignmentValue, 3, 9, "\"text\"".Length)
    LsdAssertLspRange(assignmentValue, 2, 8, 14)

    arithmeticRightOperand := LsdSingleAt(diagnostics, "TypeMismatch", "right side", 5, -1)
    LsdAssertSpan(arithmeticRightOperand, 5, 19, "\"two\"".Length)
    LsdAssertLspRange(arithmeticRightOperand, 4, 18, 23)

    arithmeticOperator := LsdSingleAt(diagnostics, "TypeMismatch", "I found 'string' and 'string'", 6, -1)
    LsdAssertSpan(arithmeticOperator, 6, 22, "-".Length)
    LsdAssertLspRange(arithmeticOperator, 5, 21, 22)

    logicalRightOperand := LsdSingleAt(diagnostics, "TypeMismatch", "right side", 7, -1)
    LsdAssertSpan(logicalRightOperand, 7, 29, "1".Length)
    LsdAssertLspRange(logicalRightOperand, 6, 28, 29)

    logicalOperator := LsdSingleAt(diagnostics, "TypeMismatch", "I found 'int' and 'int'", 8, -1)
    LsdAssertSpan(logicalOperator, 8, 22, "&&".Length)
    LsdAssertLspRange(logicalOperator, 7, 21, 23)
}

test "DocumentManager pattern errors use specific pattern spans" {
    source := LsdDecodedSource(
        """
union Result {
    Success { value: int }
    Failure { message: string }
}

record User {
    Name: string
}

func main() {
    r := new Result.Success { value: 42 }
    x := match r {
        Result.Unknown => 0,
        Result.Success { missing: value } => value,
        Result.Failure { message } => 0
    }

    user := new User { Name: "Ada" }
    y := match user {
        { Missing: value } => value,
        _ => "unknown"
    }

    n := 1
    z := match n {
        [first, ..] => first,
        _ => 0
    }
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///pattern-error-spans.nl", source)

    missingCase := LsdSingleAt(diagnostics, "InvalidPattern", "'Result.Unknown'", 13, -1)
    LsdAssertSpan(missingCase, 13, 9, "Result.Unknown".Length)
    LsdAssertLspRange(missingCase, 12, 8, 22)

    missingUnionProperty := LsdSingleAt(diagnostics, "InvalidPattern", "'missing'", 14, -1)
    LsdAssertSpan(missingUnionProperty, 14, 26, "missing".Length)
    LsdAssertLspRange(missingUnionProperty, 13, 25, 32)

    missingObjectProperty := LsdSingleAt(diagnostics, "InvalidPattern", "'Missing'", 20, -1)
    LsdAssertSpan(missingObjectProperty, 20, 11, "Missing".Length)
    LsdAssertLspRange(missingObjectProperty, 19, 10, 17)

    listPatternMismatch := LsdSingle(diagnostics, "PatternTypeMismatch", null)
    LsdAssertSpan(listPatternMismatch, 26, 9, "[first, ..]".Length)
    LsdAssertLspRange(listPatternMismatch, 25, 8, 19)
}

test "DocumentManager impossible pattern underlines type name and is check" {
    source := LsdDecodedSource(
        """
func main() {
    x: int = 42
    label := match x {
        string s => 1,
        _ => 0
    }
    result := x is string
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///impossible-pattern-spans.nl", source)

    typePattern := LsdSingleAt(diagnostics, "ImpossiblePattern", null, 4, -1)
    LsdAssertSpan(typePattern, 4, 9, "string".Length)
    LsdAssertLspRange(typePattern, 3, 8, 14)

    isCheck := LsdSingleAt(diagnostics, "ImpossiblePattern", null, 7, -1)
    LsdAssertSpan(isCheck, 7, 17, "is string".Length)
    LsdAssertLspRange(isCheck, 6, 16, 25)
}

test "DocumentManager non exhaustive match underlines match keyword" {
    source := LsdDecodedSource(
        """
enum Color {
    Red,
    Green,
    Blue
}

func describe(c: Color): int {
    return match c {
        Color.Red => 1
    }
}
"""
    )
    nonExhaustive := LsdSingle(
        LsdCompilerDiagnostics("file:///non-exhaustive-match-spans.nl", source),
        "NonExhaustiveMatch",
        null
    )
    LsdAssertSpan(nonExhaustive, 8, 12, "match".Length)
    LsdAssertLspRange(nonExhaustive, 7, 11, 16)
}

test "DocumentManager non exhaustive nullable match underlines match keyword" {
    source := LsdDecodedSource(
        """
func describe(name: string?): int {
    return match name {
        null => 0
    }
}
"""
    )
    nonExhaustive := LsdSingle(
        LsdCompilerDiagnostics("file:///non-exhaustive-nullable-match-spans.nl", source),
        "NonExhaustiveMatch",
        null
    )
    LsdAssertSpan(nonExhaustive, 2, 12, "match".Length)
    LsdAssertLspRange(nonExhaustive, 1, 11, 16)
}

test "DocumentManager declaration errors use declaration name spans" {
    source := LsdDecodedSource(
        """
func Duplicate(value: int): int { return value }

func Duplicate(value: int): int { return value }

class Thing {}
class Thing {}

enum Status {
    Pending,
    Pending
}

union Result {
    Success
    Success
}

func BadParams(params rest: int[], tail: int) {}

func BadOrdering(first: int = 1, second: int) {}

func BadDefault(value: int = makeValue()) {}

func BadParamsType(params count: int) {}

func main() {
    value := 1
    value := 2
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///declaration-spans.nl", source)

    duplicateFunction := LsdSingleAt(diagnostics, "DuplicateDeclaration", "'Duplicate'", 3, -1)
    LsdAssertSpan(duplicateFunction, 3, 6, "Duplicate".Length)
    LsdAssertLspRange(duplicateFunction, 2, 5, 14)

    duplicateType := LsdSingleAt(diagnostics, "DuplicateDeclaration", "Thing", 6, -1)
    LsdAssertSpan(duplicateType, 6, 7, "Thing".Length)

    duplicateEnumMember := LsdSingleAt(diagnostics, "DuplicateDeclaration", "enum member", 10, -1)
    LsdAssertSpan(duplicateEnumMember, 10, 5, "Pending".Length)

    duplicateUnionCase := LsdSingleAt(diagnostics, "DuplicateDeclaration", "union case", 15, -1)
    LsdAssertSpan(duplicateUnionCase, 15, 5, "Success".Length)

    paramsNotLast := LsdSingle(diagnostics, "ParamsNotLast", null)
    LsdAssertSpan(paramsNotLast, 18, 23, "rest".Length)
    LsdAssertLspRange(paramsNotLast, 17, 22, 26)

    requiredAfterOptional := LsdSingle(diagnostics, "RequiredParameterAfterOptional", null)
    LsdAssertSpan(requiredAfterOptional, 20, 34, "second".Length)
    LsdAssertLspRange(requiredAfterOptional, 19, 33, 39)

    invalidDefault := LsdSingle(diagnostics, "InvalidDefaultParameterValue", null)
    LsdAssertSpan(invalidDefault, 22, 30, "makeValue".Length)
    LsdAssertLspRange(invalidDefault, 21, 29, 38)

    invalidParamsType := LsdSingle(diagnostics, "InvalidParameter", null)
    LsdAssertSpan(invalidParamsType, 24, 27, "count".Length)
    LsdAssertLspRange(invalidParamsType, 23, 26, 31)

    duplicateLocal := LsdSingleAt(diagnostics, "DuplicateDeclaration", "'value'", 28, -1)
    LsdAssertSpan(duplicateLocal, 28, 5, "value".Length)
}

test "DocumentManager operator overload errors use operator keyword and symbol spans" {
    source := LsdDecodedSource(
        """
class Vector {
    X: int

    func operator %(a: Vector, b: Vector, c: Vector): Vector {
        return a
    }

    static func operator true(a: Vector, b: Vector): bool {
        return true
    }
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///operator-overload-spans.nl", source)

    missingStatic := LsdSingle(diagnostics, "InvalidOperatorOverload", null)
    LsdAssertSpan(missingStatic, 4, 10, "operator".Length)
    LsdAssertLspRange(missingStatic, 3, 9, 17)

    moduloArity := LsdSingle(diagnostics, "OperatorParameterCount", "'%'")
    LsdAssertSpan(moduloArity, 4, 19, "%".Length)
    LsdAssertLspRange(moduloArity, 3, 18, 19)

    trueArity := LsdSingle(diagnostics, "OperatorParameterCount", "'true'")
    LsdAssertSpan(trueArity, 8, 26, "true".Length)
    LsdAssertLspRange(trueArity, 7, 25, 29)
}

test "DocumentManager duplicate test lifecycle blocks use full keyword spans" {
    source := LsdDecodedSource(
        """
setup {
    first := 1
}

setup {
    second := 2
}

teardown {
    Cleanup()
}

teardown {
    CleanupAgain()
}

func Cleanup() {}
func CleanupAgain() {}

test "works" {
    assert true
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///duplicate-lifecycle.tests.nl", source)

    duplicateSetup := LsdSingle(diagnostics, "DuplicateDeclaration", "setup block")
    LsdAssertSpan(duplicateSetup, 5, 1, "setup".Length)
    LsdAssertLspRange(duplicateSetup, 4, 0, 5)

    duplicateTeardown := LsdSingle(diagnostics, "DuplicateDeclaration", "teardown block")
    LsdAssertSpan(duplicateTeardown, 13, 1, "teardown".Length)
    LsdAssertLspRange(duplicateTeardown, 12, 0, 8)
}

test "DocumentManager return value without return type explains implicit void" {
    source := LsdLeadingNewlineSource(
        """
func Hi() {
    return 42
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///return-value.nl", source),
        "TypeMismatch",
        null
    )
    message := LsdFormatForTooling(diagnostic, true, false)
    assert message.Contains("NL202: Function 'Hi' returns int but has no return type")
    assert message.Contains("N# treats it as `void`")
    assert message.Contains("Add `: int`")
    assert message.Contains("func Hi() {")
    LsdAssertSpan(diagnostic, 2, 6, "Hi".Length)
    LsdAssertLspRange(diagnostic, 1, 5, 7)
}
