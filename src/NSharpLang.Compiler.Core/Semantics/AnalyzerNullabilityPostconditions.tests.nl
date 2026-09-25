namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what a call leaves behind.
//
// THE ASYMMETRY IS THE POINT AND IT IS PINNED BOTH WAYS. `[NotNull]` on an INPUT parameter is a
// postcondition — it is the whole of `Assert.NotNull` — while `[MaybeNull]` on one is a statement
// about what the callee does with the value and proves nothing about the caller's variable. Getting
// that backwards would narrow a name the program never checked.
//
// A CONDITIONAL ATTRIBUTE SPEAKS FOR ONE BRANCH, AND THE DECLARATION ANSWERS FOR THE OTHER. That is
// what makes `[MaybeNullWhen(false)] out TValue` mean "present when true": the attribute names the
// false side, and the true side falls back to the parameter's own non-nullable type. The fallback is
// only owed for a BY-REF position — an input parameter's argument keeps whatever the caller's flow
// already knew — and it is owed for neither branch when the declaration says nothing (an oblivious
// reference read out of un-annotated metadata).
//
// THE READERS ARE PINNED AGAINST REAL METADATA, not against a hand-built attribute list, because the
// whole point of the reflection half is that it survives the boxing and the projected `System.Boolean`
// a MetadataLoadContext hands back.
func PostconditionOwner(): AnalyzerNullabilityPostconditions {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return new AnalyzerNullabilityPostconditions(scopes, context)
}

func PostconditionArgument(name: string): Argument {
    return new Argument(null, new IdentifierExpression(name, 1, 1), ArgumentModifier.Out)
}

func PostconditionFacts(): List<NullabilityPostcondition> {
    return new List<NullabilityPostcondition>()
}

func PostconditionFactAt(facts: List<NullabilityPostcondition>, condition: int): NullabilityPostcondition? {
    index := 0
    while index < facts.Count {
        fact := facts[index]
        index = index + 1
        if fact.Condition == condition {
            return fact
        }
    }

    return null
}

func PostconditionNullableString(): TypeInfo {
    result: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    return result
}

func PostconditionSourceAttributes(name: string, argument: Expression?): List<AttributeNode> {
    arguments := new List<Argument>()
    if argument != null {
        arguments.Add(new Argument(null, argument, ArgumentModifier.None))
    }

    attributes := new List<AttributeNode>()
    attributes.Add(new AttributeNode(name, arguments, 1, 1))
    return attributes
}

test "an out parameter with no attributes leaves the parameter's own nullability" {
    owner := PostconditionOwner()
    notNull := PostconditionFacts()
    owner.AddArgumentFacts(notNull, PostconditionArgument("value"), BuiltInTypes.String, true, NullabilityFlowFacts.None())
    assert notNull.Count == 1
    assert notNull[0].Path == "value"
    assert notNull[0].Condition == 0
    assert notNull[0].State == NullState.NotNull

    maybeNull := PostconditionFacts()
    owner.AddArgumentFacts(maybeNull, PostconditionArgument("value"), PostconditionNullableString(), true, NullabilityFlowFacts.None())
    assert maybeNull.Count == 1
    assert maybeNull[0].Condition == 0
    assert maybeNull[0].State == NullState.MaybeNull
}

test "an ordinary argument position with no attributes proves nothing" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), PostconditionNullableString(), false, NullabilityFlowFacts.None())
    assert facts.Count == 0
}

test "NotNull is a postcondition on an input parameter and MaybeNull is not" {
    owner := PostconditionOwner()
    notNull := PostconditionFacts()
    owner.AddArgumentFacts(notNull, PostconditionArgument("value"), PostconditionNullableString(), false, NullabilityFlowFacts.NotNull())
    assert notNull.Count == 1
    assert notNull[0].Condition == 0
    assert notNull[0].State == NullState.NotNull

    maybeNull := PostconditionFacts()
    owner.AddArgumentFacts(maybeNull, PostconditionArgument("value"), BuiltInTypes.String, false, NullabilityFlowFacts.MaybeNull())
    assert maybeNull.Count == 0
}

test "MaybeNull on a by-ref parameter leaves the variable maybe-null" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), BuiltInTypes.String, true, NullabilityFlowFacts.MaybeNull())
    assert facts.Count == 1
    assert facts[0].Condition == 0
    assert facts[0].State == NullState.MaybeNull
}

test "MaybeNullWhen(false) on a non-nullable out is present in the true branch" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), BuiltInTypes.String, true, NullabilityFlowFacts.MaybeNullWhenFalse())
    assert facts.Count == 2

    whenTrue := PostconditionFactAt(facts, 1)
    whenFalse := PostconditionFactAt(facts, 2)
    assert whenTrue != null
    assert whenFalse != null
    assert whenTrue.State == NullState.NotNull
    assert whenFalse.State == NullState.MaybeNull
    assert PostconditionFactAt(facts, 0) == null
}

test "NotNullWhen(false) on an input parameter speaks only for that branch" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("text"), PostconditionNullableString(), false, NullabilityFlowFacts.NotNullWhenFalse())
    assert facts.Count == 1
    assert facts[0].Condition == 2
    assert facts[0].State == NullState.NotNull
}

test "a declaration that says nothing owes neither branch a fallback" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), BuiltInTypes.Unknown, true, NullabilityFlowFacts.MaybeNullWhenFalse())
    assert facts.Count == 1
    assert facts[0].Condition == 2
}

test "un-annotated metadata answers OBLIVIOUS, which is safe to read and not a confident not-null" {
    owner := PostconditionOwner()
    reflected: TypeInfo = new ReflectionTypeInfo(typeof(List<int>))
    assert owner.DeclaredParameterState(reflected) == NullState.Oblivious
    assert owner.DeclaredParameterState(BuiltInTypes.String) == NullState.NotNull
    assert owner.DeclaredParameterState(PostconditionNullableString()) == NullState.MaybeNull
    assert owner.DeclaredParameterState(BuiltInTypes.Unknown) == NullState.Unknown

    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), reflected, true, NullabilityFlowFacts.MaybeNullWhenFalse())
    assert facts.Count == 2
    whenTrue := PostconditionFactAt(facts, 1)
    assert whenTrue != null
    assert whenTrue.State == NullState.Oblivious
}

test "an argument with no stable path proves nothing about anything" {
    owner := PostconditionOwner()
    facts := PostconditionFacts()
    literal := new Argument(null, new IntLiteralExpression("1", 1, 1), ArgumentModifier.Out)
    owner.AddArgumentFacts(facts, literal, BuiltInTypes.String, true, NullabilityFlowFacts.None())
    assert facts.Count == 0
}

test "committing files the conditional facts against the call and applies the rest" {
    owner := PostconditionOwner()
    call := new CallExpression(new IdentifierExpression("TryGet", 1, 1), new List<Argument>(), null, 1, 1)
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), BuiltInTypes.String, true, NullabilityFlowFacts.MaybeNullWhenFalse())
    owner.Commit(call, facts)

    whenTrue := owner.BranchNarrowings(call, true)
    whenFalse := owner.BranchNarrowings(call, false)
    assert whenTrue != null
    assert whenFalse != null
    assert whenTrue.Count == 1
    assert whenTrue[0].Path == "value"
    assert whenTrue[0].NullState == NullState.NotNull
    assert whenFalse[0].NullState == NullState.MaybeNull
}

test "a call that established nothing conditional is not filed at all" {
    owner := PostconditionOwner()
    call := new CallExpression(new IdentifierExpression("TryGet", 1, 1), new List<Argument>(), null, 1, 1)
    facts := PostconditionFacts()
    owner.AddArgumentFacts(facts, PostconditionArgument("value"), BuiltInTypes.String, true, NullabilityFlowFacts.None())
    owner.Commit(call, facts)
    assert owner.BranchNarrowings(call, true) == null
    assert owner.BranchNarrowings(call, false) == null
}

test "a source attribute list yields the bits its names and literals spell" {
    assert NullabilityFlowFacts.FromSourceAttributes(null) == NullabilityFlowFacts.None()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNull", null)) == NullabilityFlowFacts.NotNull()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("MaybeNullAttribute", null)) == NullabilityFlowFacts.MaybeNull()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("System.Diagnostics.CodeAnalysis.NotNull", null)) == NullabilityFlowFacts.NotNull()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNullWhen", new BoolLiteralExpression(true, 1, 1))) == NullabilityFlowFacts.NotNullWhenTrue()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("MaybeNullWhen", new BoolLiteralExpression(false, 1, 1))) == NullabilityFlowFacts.MaybeNullWhenFalse()
}

test "a conditional attribute whose argument is not a literal proves nothing" {
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNullWhen", new IdentifierExpression("flag", 1, 1))) == NullabilityFlowFacts.None()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNullWhen", null)) == NullabilityFlowFacts.None()
}

test "a name that merely starts the same is not the attribute" {
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNullWhenAttribute", new BoolLiteralExpression(true, 1, 1))) == NullabilityFlowFacts.NotNullWhenTrue()
    assert NullabilityFlowFacts.FromSourceAttributes(PostconditionSourceAttributes("NotNullish", null)) == NullabilityFlowFacts.None()
}

test "the reflection reader finds MaybeNullWhen(false) on Dictionary's TryGetValue" {
    method := typeof(Dictionary<string, string>).GetMethod("TryGetValue")
    assert method != null

    parameters := method.GetParameters()
    assert parameters.Length == 2
    assert NullabilityFlowAttributeReflection.FromParameter(parameters[0]) == NullabilityFlowFacts.None()
    assert NullabilityFlowAttributeReflection.FromParameter(parameters[1]) == NullabilityFlowFacts.MaybeNullWhenFalse()
}

test "the reflection reader finds NotNullWhen(false) on string.IsNullOrEmpty" {
    method := typeof(string).GetMethod("IsNullOrEmpty")
    assert method != null
    assert NullabilityFlowAttributeReflection.FromParameter(method.GetParameters()[0]) == NullabilityFlowFacts.NotNullWhenFalse()
}

test "the reflection reader finds the parameter a NotNullIfNotNull return names" {
    method := typeof(System.IO.Path).GetMethod("GetFileName", AnalyzerNullabilityPostconditionsStringArgument())
    assert method != null
    assert NullabilityFlowAttributeReflection.NotNullIfNotNull(method.get_ReturnParameter().GetCustomAttributesData()) == "path"
    assert NullabilityFlowAttributeReflection.NotNullIfNotNull(typeof(string).GetMethod("IsNullOrEmpty").get_ReturnParameter().GetCustomAttributesData()) == null
}

func AnalyzerNullabilityPostconditionsStringArgument(): Type[] {
    types := new Type[](1)
    types[0] = typeof(string)
    return types
}
