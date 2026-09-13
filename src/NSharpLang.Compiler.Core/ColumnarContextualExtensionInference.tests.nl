namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Linq
import System.Reflection


// NATIVE CONTRACTS FOR THE CONTEXTUAL INFERENCE ENGINE.
//
// This owner is what replaced the emitter's per-member Enumerable table, so the assertions are
// written against the FRAMEWORK's own declarations rather than against stand-ins: if
// `Enumerable.ToDictionary` ever changed shape these would say so, which is the point of resolving
// it by inference instead of by name.
func ContextualMethod(owner: Type, name: string, parameterCount: int): MethodInfo {
    for candidate in owner.GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if candidate.get_Name() == name && candidate.GetParameters().Length == parameterCount && candidate.get_IsGenericMethodDefinition() {
            return candidate
        }
    }

    throw new InvalidOperationException("Required contextual-inference probe method was not found: " + name)
}

// `Enumerable.ToDictionary<TSource, TKey, TElement>(IEnumerable<TSource>, Func<TSource, TKey>, Func<TSource, TElement>)`
// is the census's own §12 shape: three type parameters, two of them decided by two different lambdas.
func ContextualToDictionary(): MethodInfo {
    for candidate in typeof(Enumerable).GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if candidate.get_Name() != "ToDictionary" || !candidate.get_IsGenericMethodDefinition() || candidate.GetGenericArguments().Length != 3 {
            continue
        }

        parameters := candidate.GetParameters()
        if parameters.Length == 3 && parameters[2].get_ParameterType().get_IsGenericType() && parameters[2].get_ParameterType().GetGenericTypeDefinition() == typeof(Func<int, int>).GetGenericTypeDefinition() {
            return candidate
        }
    }

    throw new InvalidOperationException("Enumerable.ToDictionary<TSource, TKey, TElement> was not found.")
}

func ContextualCandidateFor(method: MethodInfo): ColumnarExtensionMethodCandidate {
    parameters := method.GetParameters()
    parameterTypes := new Type[](parameters.Length)
    index := 0
    while index < parameters.Length {
        parameterTypes[index] = parameters[index].get_ParameterType()
        index = index + 1
    }

    declaringType := method.get_DeclaringType()
    if declaringType == null {
        throw new InvalidOperationException("A contextual-inference probe candidate has no declaring type.")
    }

    return new ColumnarExtensionMethodCandidate(method, declaringType, parameterTypes, method.get_ReturnType())
}

// ── the receiver slot widens ──────────────────────────────────────────────────────────────────

test "the receiver slot is read through the receiver's own interfaces" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Count", 2))
    let binding: ColumnarContextualExtensionBinding? = null

    // `List<string>` does not NAME `IEnumerable<TSource>`; it implements it, and that is what fixes
    // `TSource`. Without this the whole sequence-extension surface is unreachable.
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)
    assert binding != null
    assert binding.Inferred[0] == typeof(string)
    assert binding.ParameterOffset == 1
}

test "an arity that does not fit is not a candidate at all" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Count", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert !ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 2, out binding)
}

test "a receiver the declaration cannot accept is not a candidate" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Count", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert !ColumnarContextualExtensionInference.TryBegin(candidate, typeof(int), 1, out binding)
}

// ── phase two: each lambda folds into ITS OWN position ────────────────────────────────────────

test "TWO lambdas fix TWO type parameters, and the first does not fix the second's" {
    candidate := ContextualCandidateFor(ContextualToDictionary())
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 2, out binding)

    let keyInputs: Type[]? = null
    assert ColumnarContextualExtensionInference.TryGetLambdaInputTypes(binding, 0, out keyInputs)
    assert keyInputs.Length == 1
    assert keyInputs[0] == typeof(string)

    assert ColumnarContextualExtensionInference.TryUnifyLambdaReturn(binding, 0, typeof(string))

    // THE CENSUS BUG, PINNED: the second position is still OPEN after the first lambda answered.
    let elementReturn: Type? = null
    assert !ColumnarContextualExtensionInference.TryGetClosedDelegateReturn(binding, 1, out elementReturn)

    let elementInputs: Type[]? = null
    assert ColumnarContextualExtensionInference.TryGetLambdaInputTypes(binding, 1, out elementInputs)
    assert elementInputs[0] == typeof(string)
    assert ColumnarContextualExtensionInference.TryUnifyLambdaReturn(binding, 1, typeof(int))

    assert ColumnarContextualExtensionInference.IsFullyInferred(binding)
    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ReturnType == typeof(Dictionary<string, int>)
}

test "a return position that is already CLOSED is a match, not an inference site" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Count", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)

    // `Func<TSource, bool>` returns `bool` whatever `TSource` turns out to be, so the predicate's
    // body has to AGREE with it rather than decide it.
    let predicateReturn: Type? = null
    assert ColumnarContextualExtensionInference.TryGetClosedDelegateReturn(binding, 0, out predicateReturn)
    assert predicateReturn == typeof(bool)
    assert ColumnarContextualExtensionInference.IsFullyInferred(binding)
}

test "a position that wants no delegate is not a delegate position, whatever is written there" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Count", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)
    assert ColumnarContextualExtensionInference.IsDelegatePosition(binding, 0)

    contains := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Contains", 2))
    let containsBinding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(contains, typeof(List<string>), 1, out containsBinding)
    assert !ColumnarContextualExtensionInference.IsDelegatePosition(containsBinding, 0)
}

// ── a method group folds the same two positions a lambda does ─────────────────────────────────

test "a method group's whole signature folds into the delegate's positions" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Select", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)

    groupParameters := new Type[](1)
    groupParameters[0] = typeof(string)
    assert ColumnarContextualExtensionInference.TryUnifyMethodGroup(binding, 0, groupParameters, typeof(int))

    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ReturnType == typeof(IEnumerable<int>)
}

test "a method group whose arity disagrees with the delegate does not fold" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "Select", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)

    groupParameters := new Type[](2)
    groupParameters[0] = typeof(string)
    groupParameters[1] = typeof(int)
    assert !ColumnarContextualExtensionInference.TryUnifyMethodGroup(binding, 0, groupParameters, typeof(int))
}

// ── the ordinary (non-extension) shapes are the same walk with a different offset ─────────────

test "a direct binding spends no parameter on a receiver" {
    convertAll := typeof(Array).GetMethod("ConvertAll")
    assert convertAll != null

    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBeginDirect(convertAll, 2, out binding)
    assert binding.ParameterOffset == 0

    // Phase one: the array argument fixes `TInput`, and the lambda's inputs follow from it.
    assert ColumnarContextualExtensionInference.TryUnifyArgument(binding, 0, typeof(string[]))
    let inputs: Type[]? = null
    assert ColumnarContextualExtensionInference.TryGetLambdaInputTypes(binding, 1, out inputs)
    assert inputs.Length == 1
    assert inputs[0] == typeof(string)

    assert ColumnarContextualExtensionInference.TryUnifyLambdaReturn(binding, 1, typeof(int))
    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ReturnType == typeof(int[])
}

test "a partial inference never closes" {
    convertAll := typeof(Array).GetMethod("ConvertAll")
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBeginDirect(convertAll, 2, out binding)
    assert ColumnarContextualExtensionInference.TryUnifyArgument(binding, 0, typeof(string[]))

    assert !ColumnarContextualExtensionInference.IsFullyInferred(binding)
    let closed: ColumnarExtensionMethodCandidate? = null
    assert !ColumnarContextualExtensionInference.TryClose(binding, out closed)
}

// ── the delegate reading itself ───────────────────────────────────────────────────────────────

test "an expression-tree target names its delegate one level in" {
    expressionOfFunc := typeof(System.Linq.Expressions.Expression<Func<string, bool>>)
    assert ColumnarContextualExtensionInference.DelegateTargetType(expressionOfFunc) == typeof(Func<string, bool>)
    assert ColumnarContextualExtensionInference.DelegateTargetType(typeof(Func<string, bool>)) == typeof(Func<string, bool>)
    assert ColumnarContextualExtensionInference.DelegateTargetType(typeof(string)) == typeof(string)
}

test "a delegate's positions come from its own shape, and a non-delegate has none" {
    let funcParameters: Type[]? = null
    let funcReturn: Type? = null
    assert ColumnarContextualExtensionInference.TryReadOpenDelegateSignature(typeof(Func<string, bool>), out funcParameters, out funcReturn)
    assert funcParameters.Length == 1
    assert funcParameters[0] == typeof(string)
    assert funcReturn == typeof(bool)

    let actionParameters: Type[]? = null
    let actionReturn: Type? = null
    assert ColumnarContextualExtensionInference.TryReadOpenDelegateSignature(typeof(Action<string>), out actionParameters, out actionReturn)
    assert actionParameters.Length == 1
    assert actionReturn == ColumnarTypeOfPlanner.RequiredVoidType()

    // A delegate that is neither `Func` nor `Action` answers from `Invoke` — there is no name list.
    let predicateParameters: Type[]? = null
    let predicateReturn: Type? = null
    assert ColumnarContextualExtensionInference.TryReadOpenDelegateSignature(typeof(Predicate<string>), out predicateParameters, out predicateReturn)
    assert predicateParameters.Length == 1
    assert predicateParameters[0] == typeof(string)
    assert predicateReturn == typeof(bool)

    let noneParameters: Type[]? = null
    let noneReturn: Type? = null
    assert !ColumnarContextualExtensionInference.TryReadOpenDelegateSignature(typeof(List<string>), out noneParameters, out noneReturn)
}

// ── the unification rules ─────────────────────────────────────────────────────────────────────

test "an argument slot reads the actual type through its implementations too" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "SelectMany", 2))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 1, out binding)

    // The selector returns `IEnumerable<TResult>` and the lambda body answered `char[]`. An array is
    // not a generic type at all, so the slot has to read it through `IEnumerable<char>`.
    assert ColumnarContextualExtensionInference.TryUnifyLambdaReturn(binding, 0, typeof(char[]))
    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ReturnType == typeof(IEnumerable<char>)
}

test "a type parameter bound twice must agree with itself" {
    typeParameters := typeof(Array).GetMethod("ConvertAll").GetGenericArguments()
    inferred := new Type[](typeParameters.Length)
    assert ColumnarContextualExtensionInference.TryUnifySlot(typeParameters[0], typeof(string), typeParameters, inferred)
    assert ColumnarContextualExtensionInference.TryUnifySlot(typeParameters[0], typeof(string), typeParameters, inferred)
    assert !ColumnarContextualExtensionInference.TryUnifySlot(typeParameters[0], typeof(int), typeParameters, inferred)
}

test "a slot with nothing open in it carries no inference and refuses nothing" {
    typeParameters := typeof(Array).GetMethod("ConvertAll").GetGenericArguments()
    inferred := new Type[](typeParameters.Length)
    assert ColumnarContextualExtensionInference.TryUnifySlot(typeof(int), typeof(string), typeParameters, inferred)
    assert inferred[0] == null
}

// ── what closed shapes a receiver HAS, which is one question with one owner ────────────────────
test "an array is the sequence interfaces the CLR says a vector implements, closed over its element" {
    assert ColumnarContextualExtensionInference.FindClosedImplementation(typeof(string[]), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == typeof(IEnumerable<string>)
    assert ColumnarContextualExtensionInference.FindClosedArrayImplementation(typeof(string[]), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == typeof(IEnumerable<string>)
    assert ColumnarContextualExtensionInference.FindClosedArrayImplementation(typeof(string[]), typeof(IReadOnlyList<int>).GetGenericTypeDefinition()) == typeof(IReadOnlyList<string>)
    assert ColumnarContextualExtensionInference.FindClosedArrayImplementation(typeof(string[]), typeof(IList<int>).GetGenericTypeDefinition()) == typeof(IList<string>)
}

test "an interface a vector does NOT implement is not manufactured for it" {
    assert ColumnarContextualExtensionInference.FindClosedArrayImplementation(typeof(string[]), typeof(IDictionary<int, int>).GetGenericTypeDefinition()) == null
    assert ColumnarContextualExtensionInference.FindClosedArrayImplementation(typeof(string), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == null
    assert !ColumnarContextualExtensionInference.SzArrayImplementsDefinition(typeof(IDictionary<int, int>).GetGenericTypeDefinition())
    assert ColumnarContextualExtensionInference.SzArrayImplementsDefinition(typeof(IEnumerable<int>).GetGenericTypeDefinition())
}

test "a constructed type answers through its DEFINITION with its own arguments substituted" {
    // The fallback the builder-bound receivers need, exercised on a runtime instantiation where the
    // direct reading is also available: the two must agree, which is why one is the other's fallback.
    assert ColumnarContextualExtensionInference.FindClosedImplementationThroughDefinition(typeof(List<string>), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == typeof(IEnumerable<string>)
    assert ColumnarContextualExtensionInference.FindClosedImplementationThroughDefinition(typeof(Dictionary<string, int>), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == typeof(IEnumerable<KeyValuePair<string, int>>)
    assert ColumnarContextualExtensionInference.FindClosedImplementationThroughDefinition(typeof(string), typeof(IEnumerable<int>).GetGenericTypeDefinition()) == null
}

test "the closed signature is SUBSTITUTED from the declaration, not read back off the handle" {
    // A `MethodBuilderInstantiation` reports its DEFINITION's parameters, so reading them back would
    // answer `IEnumerable<TSource>` for every receiver. Substitution is the same answer for a runtime
    // instantiation, which is what makes one path correct for both.
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "First", 1))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(List<string>), 0, out binding)

    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ParameterTypes.Length == 1
    assert closed.ParameterTypes[0] == typeof(IEnumerable<string>)
    assert closed.ReturnType == typeof(string)
}

test "an array receiver reaches the sequence extension the same way a list does" {
    candidate := ContextualCandidateFor(ContextualMethod(typeof(Enumerable), "First", 1))
    let binding: ColumnarContextualExtensionBinding? = null
    assert ColumnarContextualExtensionInference.TryBegin(candidate, typeof(string[]), 0, out binding)

    let closed: ColumnarExtensionMethodCandidate? = null
    assert ColumnarContextualExtensionInference.TryClose(binding, out closed)
    assert closed.ReturnType == typeof(string)
    assert ColumnarExtensionMethodResolver.ReferenceAssignableFrom(closed.ParameterTypes[0], typeof(string[]))
}
