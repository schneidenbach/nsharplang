namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

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

    childArray[paramNames.Length] = builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    // Kind 39 is the parser's lambda node; the signature planner never reads the lambda node's own
    // text, so a -1 value span is fine, matching the emitter's contract.
    lambdaNode = builder.AddNode(39, -1, 0, 0, builder.Source.Length, childArray)
    return builder.Build(lambdaNode)
}

func LambdaSignatureIdentifierKinds(count: int): int[] {
    kinds := new int[](count)
    index := 0
    while index < count {
        kinds[index] = ColumnarExpressionNodeKind.IdentifierExpression()
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
    assert signature == null
}

test "contextual-lambda signature declines a non-identifier parameter node" {
    names := new string[](1)
    names[0] = "1"
    kinds := new int[](1)
    kinds[0] = ColumnarExpressionNodeKind.IntLiteralExpression()
    lambdaNode := 0
    tree := LambdaSignatureTree(names, kinds, out lambdaNode)

    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)

    signature := ColumnarLambdaPlacementPlanner.PlanContextualSignature(
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, LambdaSignatureNoBindings())
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
        tree.Nodes, tree.Source, lambdaNode, parameterTypes, visible)
    assert signature == null
}
