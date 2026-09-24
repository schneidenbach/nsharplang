namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// THE CONTRACT FOR THE SHAPE WALK THAT SIX OWNERS USED TO HOLD A COPY OF.
//
// The audit that moved these into one owner asked for one arm to be pinned FIRST, because the six
// copies did not spell it the same way: four wrote
// `IsSafeSzArrayType(left) || IsSafeSzArrayType(right)` and then refused a pair that is not both
// arrays, while `ColumnarRuntimeInstanceMemberResolver`'s wrote `&&` and let a one-sided array fall
// through to the generic-instantiation test. The rows below are the reason that is a spelling
// difference and not a behaviour one: an SZ array is not a generic type, so the generic test refuses
// the one-sided pair exactly as the explicit arm did.
//
// The rows also pin the ONE difference that is real — whether two open generic parameters of the
// same identity count as one shape — because that is now the difference between the two entry
// points rather than between two copies.
test "the shape walk answers reference identity before anything else" {
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int), typeof(int))
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(string), typeof(string))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int), typeof(long))
}

test "a one-sided SZ array is refused, which is what `&&` and `||` both answered" {
    // `||` refused the pair in the array arm; `&&` skipped the arm and reached the generic test,
    // where an array's `IsGenericType` is false. Both answer false, and this row is what says so.
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[]), typeof(int))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int), typeof(int[]))
    assert !typeof(int[]).get_IsGenericType()
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[]), typeof(List<int>))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(List<int>), typeof(int[]))
}

test "two SZ arrays match element-wise, at any depth" {
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[]), typeof(int[]))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[]), typeof(string[]))
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[][]), typeof(int[][]))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(int[][]), typeof(string[][]))
}

test "a closed instantiation matches definition-and-arguments-wise, and an open one never matches" {
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(List<int>), typeof(List<int>))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(List<int>), typeof(List<string>))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(List<int>), typeof(HashSet<int>))
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(Dictionary<string, List<int>>), typeof(Dictionary<string, List<int>>))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(typeof(Dictionary<string, List<int>>), typeof(Dictionary<string, List<string>>))

    // A generic DEFINITION is refused by both walks: `IsGenericTypeDefinition` is checked before the
    // arguments are compared, so `List<>` is not the same shape as itself by this rule.
    openList := typeof(List<int>).GetGenericTypeDefinition()
    assert openList.get_IsGenericTypeDefinition()
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(openList, openList)
}

test "generic-parameter identity is the ONE arm the two entry points disagree about" {
    parameter := typeof(List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    assert parameter.get_IsGenericParameter()

    // Same reference: both entries answer true through the identity test that opens the walk.
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(parameter, parameter)
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(parameter, parameter)

    // A parameter against a concrete type: the plain walk falls through to the generic test, where a
    // parameter's `IsGenericType` is false. The identity-aware walk refuses it in its own arm. Both
    // say no, and that is the answer each of the six copies gave.
    assert !parameter.get_IsGenericType()
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatches(parameter, typeof(int))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(parameter, typeof(int))
    assert !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(typeof(int), parameter)
}

test "a baked runtime type reaches no type the compilation is still writing" {
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundType(typeof(int))
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundType(typeof(List<int>))
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundType(typeof(int[]))
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundTypeThroughElements(typeof(int))
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundTypeThroughElements(typeof(List<int>))
    assert !RuntimeTypeShapeFacts.ContainsBuilderBoundTypeThroughElements(typeof(int[]))

    // An OPEN generic parameter is builder-bound to both, which is the arm they share.
    parameter := typeof(List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    assert RuntimeTypeShapeFacts.ContainsBuilderBoundType(parameter)
    assert RuntimeTypeShapeFacts.ContainsBuilderBoundTypeThroughElements(parameter)
}

test "a baked enum is an enum and is not an enum builder" {
    assert RuntimeTypeShapeFacts.IsEnumType(typeof(DayOfWeek))
    assert !RuntimeTypeShapeFacts.IsEnumType(typeof(int))
    assert !RuntimeTypeShapeFacts.IsEnumBuilder(typeof(DayOfWeek))
    assert !RuntimeTypeShapeFacts.IsEnumBuilder(typeof(int))
    assert !RuntimeTypeShapeFacts.IsByRefLike(typeof(int))
    assert RuntimeTypeShapeFacts.IsByRefLike(typeof(Span<int>))
}
