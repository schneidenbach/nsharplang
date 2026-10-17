namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Build a lambda-literal node whose children are [param identifiers..., body]. The parameter leaves
// take the supplied kinds (kind 6 = identifier for a real parameter; anything else exercises the
// non-identifier decline). The body is an int-literal leaf. Nodes are appended in order, so the body
// leaf lands at index paramNames.Length and the lambda node at paramNames.Length + 1.
func LambdaSignatureTree(paramNames: string[], paramKinds: int[], out lambdaNode: int): ColumnarRangePlannerTestTree {
    if paramNames.Length != paramKinds.Length {
        throw new InvalidOperationException("Lambda signature fixture requires matching parameter name and kind counts.")
    }

    builder := new ColumnarRangePlannerNodeBuilder()
    childArray := new int[](paramNames.Length + 1)
    index := 0
    while index < paramNames.Length {
        childArray[index] = builder.AddLeaf(paramKinds[index], paramNames[index])
        index = index + 1
    }

    childArray[paramNames.Length] = builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression, "1")
    // Kind 39 is the parser's lambda node; the signature planner never reads the lambda node's own
    // text, so a -1 value span is fine, matching the emitter's contract.
    lambdaNode = builder.AddNode(39, -1, 0, 0, builder.Source.Length, childArray)
    return builder.Build(lambdaNode)
}

func LambdaSignatureIdentifierKinds(count: int): int[] {
    kinds := new int[](count)
    index := 0
    while index < count {
        kinds[index] = ColumnarExpressionNodeKind.IdentifierExpression
        index = index + 1
    }

    return kinds
}

func LambdaSignatureNoBindings(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

test "contextual-lambda signature binds a single parameter to the delegate parameter type" {
    names := new string[](1)
    names[0] = "x"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(1), out lambdaNode)

    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    if signature == null {
        throw new InvalidOperationException("Expected a bound single-parameter lambda signature.")
    }

    assert signature.Ordinals.Count == 1
    ordinal := -1
    assert signature.Ordinals.TryGetValue("x", out ordinal)
    assert ordinal == 0

    boundType := typeof(object)
    assert signature.ParameterTypesByName.TryGetValue("x", out boundType)
    assert boundType == typeof(int)

    // The body is the child after the single parameter.
    assert signature.BodyNode == 1
}

test "contextual-lambda signature binds multiple parameters positionally" {
    names := new string[](2)
    names[0] = "a"
    names[1] = "b"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(2), out lambdaNode)

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(string)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    if signature == null {
        throw new InvalidOperationException("Expected a bound two-parameter lambda signature.")
    }

    assert signature.Ordinals.Count == 2
    firstOrdinal := -1
    assert signature.Ordinals.TryGetValue("a", out firstOrdinal)
    assert firstOrdinal == 0
    secondOrdinal := -1
    assert signature.Ordinals.TryGetValue("b", out secondOrdinal)
    assert secondOrdinal == 1

    firstType := typeof(object)
    assert signature.ParameterTypesByName.TryGetValue("a", out firstType)
    assert firstType == typeof(int)
    secondType := typeof(object)
    assert signature.ParameterTypesByName.TryGetValue("b", out secondType)
    assert secondType == typeof(string)

    assert signature.BodyNode == 2
}

test "contextual-lambda signature binds a zero-parameter lambda" {
    names := new string[](0)
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(0), out lambdaNode)

    parameterTypes := new Type[](0)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    if signature == null {
        throw new InvalidOperationException("Expected a bound zero-parameter lambda signature.")
    }

    assert signature.Ordinals.Count == 0
    assert signature.BodyNode == 0
}

test "contextual-lambda signature declines on delegate-arity mismatch" {
    names := new string[](1)
    names[0] = "x"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(1), out lambdaNode)

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(int)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    assert signature == null
}

test "contextual-lambda signature declines a non-identifier parameter node" {
    names := new string[](1)
    names[0] = "1"
    kinds := new int[](1)
    kinds[0] = ColumnarExpressionNodeKind.IntLiteralExpression
    lambdaNode := 0
    tree := LambdaSignatureTree(names, kinds, out lambdaNode)

    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    assert signature == null
}

test "contextual-lambda signature declines a duplicate parameter name" {
    names := new string[](2)
    names[0] = "x"
    names[1] = "x"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(2), out lambdaNode)

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(int)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        LambdaSignatureNoBindings()
    )
    assert signature == null
}

test "contextual-lambda signature declines a parameter that shadows an enclosing binding" {
    names := new string[](1)
    names[0] = "x"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(1), out lambdaNode)

    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)

    visible := new HashSet<string>(StringComparer.Ordinal)
    visible.Add("x")

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes,
        tree.Source,
        lambdaNode,
        parameterTypes,
        visible
    )
    assert signature == null
}

// ── the synthesized method's `Param` rows (issue #216) ─────────────────────────────────────────────
//
// A lambda's synthesized method is its delegate's `Method`, and ASP.NET Core binds a Minimal-API
// handler BY PARAMETER NAME. The signature keeps the written names in DECLARATION order — not the
// ordinal map's iteration order — so the rows below use names that do not sort into place.

test "contextual-lambda signature keeps the source parameter names in declaration order" {
    names := new string[](3)
    names[0] = "zeta"
    names[1] = "alpha"
    names[2] = "mid"
    lambdaNode := 0
    tree := LambdaSignatureTree(names, LambdaSignatureIdentifierKinds(3), out lambdaNode)

    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(string)
    parameterTypes[2] = typeof(bool)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
    if signature == null {
        throw new InvalidOperationException("Expected a bound three-parameter lambda signature.")
    }

    assert string.Join(",", signature.ParameterNames) == "zeta,alpha,mid"
}

test "a zero-parameter lambda signature carries no parameter names" {
    lambdaNode := 0
    tree := LambdaSignatureTree(new string[](0), new int[](0), out lambdaNode)
    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(tree.Nodes, tree.Source, lambdaNode, Type.EmptyTypes, LambdaSignatureNoBindings())
    if signature == null {
        throw new InvalidOperationException("Expected a bound zero-parameter lambda signature.")
    }

    assert signature.ParameterNames.Length == 0
}

func LambdaParameterNameOwner(name: string): TypeBuilder {
    assemblyName := "NSharpTests." + name
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(assemblyName), AssemblyBuilderAccess.Run)
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    return dynamicModule.DefineType(assemblyName + ".Owner", TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)
}

func LambdaParameterNamesOf(method: MethodInfo?): string {
    if method == null {
        throw new InvalidOperationException("The baked fixture lost its synthesized method.")
    }

    names := new List<string>()
    for parameter in method.GetParameters() {
        names.Add((parameter.Position + 1).ToString() + ":" + (parameter.Name ?? "<null>"))
    }
    return string.Join(",", names)
}

test "a synthesized lambda method defined with its signature gets one named row per parameter" {
    owner := LambdaParameterNameOwner("LambdaParameterNamesWithSignature")
    method := owner.DefineMethod("<Lambda>_0", ColumnarLambdaPlacementPlanner.StaticLambdaAttributes(), typeof(string), [typeof(int), typeof(string)])
    ColumnarLambdaPlacementPlanner.DefineSourceParameterNames(method, ["id", "label"])
    method.GetILGenerator().Emit(OpCodes.Ldarg_1)
    method.GetILGenerator().Emit(OpCodes.Ret)

    baked := PlanFixtureBake(owner)
    synthesized := baked.GetMethod("<Lambda>_0", BindingFlags.NonPublic | BindingFlags.Static)
    assert LambdaParameterNamesOf(synthesized) == "1:id,2:label"
}

// The inferred (`:=`) path defines its method signature-less and sets the parameters after the body
// has decided the return type; the names are written after `SetParameters`, which is the only order
// `DefineParameter` accepts.
test "a signature-less synthesized lambda method is named after its parameters are set" {
    owner := LambdaParameterNameOwner("LambdaParameterNamesAfterSetParameters")
    method := owner.DefineMethod("<Lambda>_1", ColumnarLambdaPlacementPlanner.StaticLambdaAttributes())
    method.GetILGenerator().Emit(OpCodes.Ldarg_0)
    method.GetILGenerator().Emit(OpCodes.Ret)
    method.SetReturnType(typeof(int))
    method.SetParameters([typeof(int)])
    ColumnarLambdaPlacementPlanner.DefineSourceParameterNames(method, ["quantity"])

    baked := PlanFixtureBake(owner)
    synthesized := baked.GetMethod("<Lambda>_1", BindingFlags.NonPublic | BindingFlags.Static)
    assert LambdaParameterNamesOf(synthesized) == "1:quantity"
}

// A display-class method's receiver is `this`, not a parameter, so its user parameters still start
// at sequence one.
test "an instance synthesized lambda method numbers its named rows from one" {
    owner := LambdaParameterNameOwner("LambdaParameterNamesInstance")
    method := owner.DefineMethod("<Lambda>", MethodAttributes.Public | MethodAttributes.HideBySig, typeof(int), [typeof(int)])
    ColumnarLambdaPlacementPlanner.DefineSourceParameterNames(method, ["input"])
    method.GetILGenerator().Emit(OpCodes.Ldarg_1)
    method.GetILGenerator().Emit(OpCodes.Ret)

    baked := PlanFixtureBake(owner)
    synthesized := baked.GetMethod("<Lambda>", BindingFlags.Public | BindingFlags.Instance)
    assert LambdaParameterNamesOf(synthesized) == "1:input"
}
