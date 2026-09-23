namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// "MORE SPECIFIC PARAMETER TYPES" (ECMA-334 §12.6.4.3's last tie-break), OVER THE TYPES THE
// DECLARATION WROTE.
//
// Every rule above this one reads the CLOSED parameter types — the types the call would actually
// convert to, with each candidate's own inference substituted in. That is the right question for
// every conversion rule, and it is also why those rules run out of answers for a pair like
//
//     Task.Run<TResult>(Func<TResult>)          with TResult = Task<int>
//     Task.Run<TResult>(Func<Task<TResult>>)    with TResult = int
//
// called as `Task.Run(() => Task.FromResult(11))`. BOTH close to `Func<Task<int>>`. The conversions
// cannot separate them because there is nothing to separate; both are generic, neither expands a
// params tail, neither defaults a parameter. Left there the call is a tie, and a tie the compiler
// breaks by arrival order silently answers `Task<Task<int>>` where C# answers `Task<int>`.
//
// C# separates them by asking a DIFFERENT question of the SAME pair: which declaration wrote the
// more specific parameter types, reading the signatures UNINSTANTIATED. `Func<TResult>` says
// "whatever the lambda gives me"; `Func<Task<TResult>>` says "a task, whose result is whatever the
// lambda's task gives me". The second says more, so it is the better member.
//
// THE RELATION HAS THREE CLAUSES AND IT IS RECURSIVE:
//
//   1. A TYPE PARAMETER IS LESS SPECIFIC THAN ANYTHING THAT IS NOT ONE. `Task<TResult>` beats
//      `TResult`; two type parameters, or two non-type-parameters with no structure to compare, are
//      NEITHER.
//   2. AN ARRAY IS MORE SPECIFIC THAN AN ARRAY OF THE SAME RANK whose element type is less specific.
//      `T[]` against `Task<T>[]` is `T` against `Task<T>`, one dimension down.
//   3. A CONSTRUCTED TYPE IS MORE SPECIFIC THAN ONE OF THE SAME ARITY when at least one type
//      argument is more specific and none is less specific — the same all-or-nothing fold the
//      per-argument conversions use, which is why it is `FoldArgumentVerdicts` and not a second copy
//      of that rule. Two types of DIFFERENT arity have nothing to compare element-wise and answer
//      NEITHER: `Func<Task>` and `Func<Task<TResult>>` are not ordered by this rule, and the score
//      ladder is what separates a delegate that discards the lambda's result from one that keeps it.
//
// THE RULE IS SPELLED ONCE AND READ BY BOTH SIGNATURE WORLDS, exactly as `AnalyzerOverloadSpecificity`
// is. The reflected world spells an open parameter type as a CLR `Type` from a MetadataLoadContext,
// where a type parameter answers `IsGenericParameter`; the source world spells it as the
// `TypeReference` the declaration wrote, where a type parameter is a bare name that matches one of
// the signature's own `TypeParameters` — a name, because that is all a written signature has. The
// two spellings are the only difference between the walks, and the verdicts they produce are the
// same three-valued answers every other betterness rule produces.
class AnalyzerOpenTypeSpecificity {

    // THE LEAF CLAUSE, STATED ONCE: a type parameter is less specific than a type that is not one.
    static func CompareTypeParameterSpecificity(leftIsTypeParameter: bool, rightIsTypeParameter: bool): int {
        if leftIsTypeParameter == rightIsTypeParameter {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        if leftIsTypeParameter {
            return AnalyzerOverloadSpecificity.RightIsBetter
        }

        return AnalyzerOverloadSpecificity.LeftIsBetter
    }

    // ONE POSITION'S VERDICT IN THE REFLECTED WORLD. A position either candidate left unfilled has no
    // pair of types to compare and says nothing.
    static func CompareReflectionTypes(left: Type?, right: Type?): int {
        if left == null || right == null {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        leftIsTypeParameter := left.get_IsGenericParameter()
        rightIsTypeParameter := right.get_IsGenericParameter()
        if leftIsTypeParameter || rightIsTypeParameter {
            return CompareTypeParameterSpecificity(leftIsTypeParameter, rightIsTypeParameter)
        }

        if left.get_IsArray() || right.get_IsArray() {
            if !left.get_IsArray() || !right.get_IsArray() || left.GetArrayRank() != right.GetArrayRank() {
                return AnalyzerOverloadSpecificity.NeitherIsBetter
            }

            return CompareReflectionTypes(left.GetElementType(), right.GetElementType())
        }

        if !left.get_IsGenericType() || !right.get_IsGenericType() {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        verdicts := new List<int>()
        index := 0
        while index < leftArguments.Length {
            verdicts.Add(CompareReflectionTypes(leftArguments[index], rightArguments[index]))
            index = index + 1
        }

        return AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
    }

    // THE WHOLE PARAMETER LIST IN THE REFLECTED WORLD, position by position, folded all-or-nothing:
    // a candidate whose signature is more specific at one position and less specific at another is
    // INCOMPARABLE, which is how a genuine tie survives this rule instead of being broken by it.
    static func CompareReflectionParameterLists(left: Type?[], right: Type?[]): int {
        verdicts := new List<int>()
        index := 0
        while index < left.Length && index < right.Length {
            verdicts.Add(CompareReflectionTypes(left[index], right[index]))
            index = index + 1
        }

        return AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
    }

    // WHETHER A WRITTEN TYPE NAMES ONE OF THE SIGNATURE'S OWN TYPE PARAMETERS. A written signature
    // has no symbol for its type parameters — `T` is the identifier `T` — so the question is a name
    // lookup against the list the declaration itself wrote.
    static func IsSourceTypeParameter(typeReference: TypeReference?, typeParameters: List<TypeParameter>?): bool {
        if typeReference == null || typeParameters == null {
            return false
        }

        simple := typeReference as SimpleTypeReference
        if simple == null {
            return false
        }

        for typeParameter in typeParameters {
            if typeParameter.Name == simple.Name {
                return true
            }
        }

        return false
    }

    // ONE POSITION'S VERDICT IN THE SOURCE WORLD. The two candidates carry their OWN type-parameter
    // lists, because `F<T>(x: T)` and `G<U>(x: List<U>)` name their parameters independently and the
    // rule is about the SHAPE each wrote, never about which letter it chose.
    static func CompareSourceTypes(left: TypeReference?, right: TypeReference?, leftTypeParameters: List<TypeParameter>?, rightTypeParameters: List<TypeParameter>?): int {
        if left == null || right == null {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        leftIsTypeParameter := IsSourceTypeParameter(left, leftTypeParameters)
        rightIsTypeParameter := IsSourceTypeParameter(right, rightTypeParameters)
        if leftIsTypeParameter || rightIsTypeParameter {
            return CompareTypeParameterSpecificity(leftIsTypeParameter, rightIsTypeParameter)
        }

        leftArray := left as ArrayTypeReference
        rightArray := right as ArrayTypeReference
        if leftArray != null || rightArray != null {
            if leftArray == null || rightArray == null {
                return AnalyzerOverloadSpecificity.NeitherIsBetter
            }

            return CompareSourceTypes(leftArray.ElementType, rightArray.ElementType, leftTypeParameters, rightTypeParameters)
        }

        // `T?` IS A CONSTRUCTED TYPE WITH ONE ARGUMENT, written in the shorthand the language gives
        // it. Comparing the shorthand against the shorthand keeps `Nullable<T>` and `T?` the same
        // question one level down.
        leftNullable := left as NullableTypeReference
        rightNullable := right as NullableTypeReference
        if leftNullable != null || rightNullable != null {
            if leftNullable == null || rightNullable == null {
                return AnalyzerOverloadSpecificity.NeitherIsBetter
            }

            return CompareSourceTypes(leftNullable.InnerType, rightNullable.InnerType, leftTypeParameters, rightTypeParameters)
        }

        // A WRITTEN FUNCTION TYPE (`(int) -> T`) IS A DELEGATE SPELLED STRUCTURALLY: its parameters
        // and its return are its type arguments, and the same fold decides it.
        leftFunction := left as FunctionTypeReference
        rightFunction := right as FunctionTypeReference
        if leftFunction != null || rightFunction != null {
            if leftFunction == null || rightFunction == null || leftFunction.ParameterTypes.Count != rightFunction.ParameterTypes.Count {
                return AnalyzerOverloadSpecificity.NeitherIsBetter
            }

            functionVerdicts := new List<int>()
            functionIndex := 0
            while functionIndex < leftFunction.ParameterTypes.Count {
                functionVerdicts.Add(CompareSourceTypes(leftFunction.ParameterTypes[functionIndex], rightFunction.ParameterTypes[functionIndex], leftTypeParameters, rightTypeParameters))
                functionIndex = functionIndex + 1
            }

            functionVerdicts.Add(CompareSourceTypes(leftFunction.ReturnType, rightFunction.ReturnType, leftTypeParameters, rightTypeParameters))
            return AnalyzerOverloadSpecificity.FoldArgumentVerdicts(functionVerdicts)
        }

        leftGeneric := left as GenericTypeReference
        rightGeneric := right as GenericTypeReference
        if leftGeneric == null || rightGeneric == null || leftGeneric.TypeArguments.Count != rightGeneric.TypeArguments.Count {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        verdicts := new List<int>()
        index := 0
        while index < leftGeneric.TypeArguments.Count {
            verdicts.Add(CompareSourceTypes(leftGeneric.TypeArguments[index], rightGeneric.TypeArguments[index], leftTypeParameters, rightTypeParameters))
            index = index + 1
        }

        return AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
    }

    // THE WHOLE PARAMETER LIST IN THE SOURCE WORLD, folded exactly as the reflected one is.
    static func CompareSourceParameterLists(left: TypeReference?[], right: TypeReference?[], leftTypeParameters: List<TypeParameter>?, rightTypeParameters: List<TypeParameter>?): int {
        verdicts := new List<int>()
        index := 0
        while index < left.Length && index < right.Length {
            verdicts.Add(CompareSourceTypes(left[index], right[index], leftTypeParameters, rightTypeParameters))
            index = index + 1
        }

        return AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
    }
}
