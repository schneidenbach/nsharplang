namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// THE CAPTURE DECISION, ASKED DIRECTLY. The emitter consumes this plan before a body emits, so the
// answers below are what chooses each local function's OWNER — a plain static, an instance method of
// the body's display, or an instance method of the enclosing type. Executable coverage of the IL
// that decision produces lives in `tests/native/census-local-functions`; this file pins the decision.
//
// The trees are built with raw node kinds: 25 is a statement block and 24 a `:=` declaration, which
// is the same numbering the planner reads.
func LocalFunctionPlannerNames(values: string[]): HashSet<string> {
    names := new HashSet<string>(StringComparer.Ordinal)
    for value in values {
        names.Add(value)
    }

    return names
}

class LocalFunctionPlannerFixture {
    Builder: ColumnarRangePlannerNodeBuilder
    Declarations: List<ColumnarLocalFunctionInput>

    constructor() {
        Builder = new ColumnarRangePlannerNodeBuilder()
        Declarations = new List<ColumnarLocalFunctionInput>()
    }

    // One local function whose body reads exactly `reads`, with the parameters it declares itself.
    func Declare(name: string, reads: string[], parameters: string[]) {
        children := new int[](reads.Length)
        index := 0
        while index < reads.Length {
            children[index] = Builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), reads[index])
            index = index + 1
        }

        root := Builder.AddNode(25, -1, 0, 0, Builder.Source.Length, children)
        parameterTypes := new string[](parameters.Length)
        typeIndex := 0
        while typeIndex < parameterTypes.Length {
            parameterTypes[typeIndex] = "int"
            typeIndex = typeIndex + 1
        }

        nodes := Builder.Build(root)
        Declarations.Add(new ColumnarLocalFunctionInput(Declarations.Count, new ColumnarFunctionInput(name, "void", parameters, parameterTypes, nodes.Nodes, root, false, new string[](0))))
    }

    // One explicit generic call. GenericCallee's value is the callee name; its child 0 is the callee
    // EXPRESSION and the type-syntax children follow it, and the type children must never enter
    // capture-name collection.
    func DeclareGenericCall(name: string, callee: string, typeArgument: string, parameter: string) {
        calleeStart := Builder.AddToken(callee)
        calleeExpression := Builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), calleeStart, callee.Length, calleeStart, callee.Length, new int[](0))
        typeNode := Builder.AddLeaf(0, typeArgument)
        calleeChildren: int[] = [calleeExpression, typeNode]
        genericCallee := Builder.AddNode(38, calleeStart, callee.Length, calleeStart, callee.Length, calleeChildren)
        argument := Builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), parameter)
        callChildren: int[] = [genericCallee, argument]
        call := Builder.AddNode(ColumnarExpressionNodeKind.CallExpression(), -1, 0, calleeStart, Builder.Source.Length - calleeStart, callChildren)
        blockChildren: int[] = [call]
        root := Builder.AddNode(25, -1, 0, calleeStart, Builder.Source.Length - calleeStart, blockChildren)
        nodes := Builder.Build(root)
        parameters: string[] = [parameter]
        parameterTypes: string[] = ["int"]
        typeParameters: string[] = [typeArgument]
        Declarations.Add(new ColumnarLocalFunctionInput(Declarations.Count, new ColumnarFunctionInput(name, "void", parameters, parameterTypes, nodes.Nodes, root, false, typeParameters)))
    }

    // The plan, read against the tree as it stands now — the builder's table is rebuilt per call, so
    // every declaration is asked against the SAME finished table and source.
    func Plan(scopeBindings: string[], instanceNames: string[]): ColumnarLocalFunctionClosurePlan {
        finished := Builder.Build(0)
        rebuilt := new List<ColumnarLocalFunctionInput>()
        index := 0
        while index < Declarations.Count {
            declaration := Declarations[index].Function
            rebuilt.Add(new ColumnarLocalFunctionInput(index, new ColumnarFunctionInput(declaration.Name, "void", declaration.ParamNames, declaration.ParamCanonicals, finished.Nodes, declaration.BodyRoot, false, new string[](0))))
            index = index + 1
        }

        return ColumnarLocalFunctionClosurePlanner.Plan(rebuilt, finished.Source, LocalFunctionPlannerNames(scopeBindings), LocalFunctionPlannerNames(instanceNames))
    }
}

test "a local function that reads nothing of the enclosing scope stays a plain method" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("twice", ["Console"], [])

    plan := fixture.Plan(["total"], [])

    assert !plan.NeedsLowering()
    assert !plan.NeedsDisplay()
    assert !plan.IsDisplayMethod("twice")
    assert !plan.IsInstanceMethod("twice")
    assert plan.CaptureNames.Count == 0
}

test "a local function that reads an enclosing binding runs on the display and names the capture" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("add", ["total"], [])

    plan := fixture.Plan(["total"], [])

    assert plan.NeedsDisplay()
    assert plan.IsDisplayMethod("add")
    assert !plan.IsInstanceMethod("add")
    assert plan.CaptureNames.Count == 1
    assert plan.CaptureNames.Contains("total")
    assert !plan.ReadsEnclosingInstance
}

test "a local function's own parameter is not a capture" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("add", ["total"], ["total"])

    plan := fixture.Plan(["total"], [])

    assert !plan.NeedsLowering()
    assert plan.CaptureNames.Count == 0
}

test "a capture-free local function that calls a capturing sibling joins the display" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("outer", ["add"], [])
    fixture.Declare("add", ["total"], [])

    plan := fixture.Plan(["total"], [])

    // `outer` captures nothing itself, but it cannot call `add` without the receiver `add` runs on.
    assert plan.IsDisplayMethod("add")
    assert plan.IsDisplayMethod("outer")
    assert plan.CaptureNames.Count == 1
    assert plan.CaptureNames.Contains("total")
}

test "an explicit generic sibling call propagates capture without treating type arguments as values" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.DeclareGenericCall("outer", "add", "V", "other")
    fixture.Declare("add", ["total"], [])

    plan := fixture.Plan(["total", "V"], [])

    assert plan.IsDisplayMethod("add")
    assert plan.IsDisplayMethod("outer")
    assert plan.CaptureNames.Count == 1
    assert plan.CaptureNames.Contains("total")
    assert !plan.CaptureNames.Contains("V")
}

test "a qualified explicit generic callee is not a local sibling edge by short name" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.DeclareGenericCall("outer", "Other.add", "V", "other")
    fixture.Declare("add", ["total"], [])

    plan := fixture.Plan(["total", "V"], [])

    assert plan.IsDisplayMethod("add")
    assert !plan.IsDisplayMethod("outer")
    assert plan.CaptureNames.Count == 1
    assert plan.CaptureNames.Contains("total")
}

test "mutual recursion settles in the fixpoint rather than recursing" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("even", ["steps", "odd"], [])
    fixture.Declare("odd", ["steps", "even"], [])

    plan := fixture.Plan(["steps"], [])

    assert plan.IsDisplayMethod("even")
    assert plan.IsDisplayMethod("odd")
    assert plan.CaptureNames.Count == 1
}

test "a local function that reads only an enclosing member is placed on the enclosing type" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("bump", ["Count"], [])

    plan := fixture.Plan(["total"], ["Count"])

    assert plan.NeedsLowering()
    assert !plan.NeedsDisplay()
    assert plan.IsInstanceMethod("bump")
    assert !plan.IsDisplayMethod("bump")
    assert !plan.ReadsEnclosingInstance
}

test "a local function that reads a member AND a local runs on a display that carries the instance" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("bump", ["Count", "total"], [])

    plan := fixture.Plan(["total"], ["Count"])

    assert plan.IsDisplayMethod("bump")
    assert !plan.IsInstanceMethod("bump")
    assert plan.ReadsEnclosingInstance
    assert plan.CaptureNames.Contains("total")
}

test "a local function that calls a `this`-reading sibling needs the same receiver" {
    fixture := new LocalFunctionPlannerFixture()
    fixture.Declare("caller", ["bump"], [])
    fixture.Declare("bump", ["Count"], [])

    plan := fixture.Plan(["total"], ["Count"])

    assert plan.IsInstanceMethod("bump")
    assert plan.IsInstanceMethod("caller")
    assert !plan.NeedsDisplay()
}

test "the scope a local function is written in is the enclosing parameters and the root block only" {
    builder := new ColumnarRangePlannerNodeBuilder()
    rootDeclaration := builder.AddLeaf(24, "total")
    nestedDeclaration := builder.AddLeaf(24, "inner")
    nestedChildren := new int[](1)
    nestedChildren[0] = nestedDeclaration
    nestedBlock := builder.AddNode(25, -1, 0, 0, builder.Source.Length, nestedChildren)
    rootChildren := new int[](2)
    rootChildren[0] = rootDeclaration
    rootChildren[1] = nestedBlock
    root := builder.AddNode(25, -1, 0, 0, builder.Source.Length, rootChildren)
    tree := builder.Build(root)

    names := new HashSet<string>(StringComparer.Ordinal)
    ColumnarLocalFunctionClosurePlanner.CollectDeclaringScopeBindingNames(tree.Nodes, tree.Source, tree.Root, names)

    assert names.Contains("total")
    // A name bound by a NESTED block is not in scope where a root-block local function is written,
    // so it is neither a capture nor a shadowing conflict.
    assert !names.Contains("inner")
}
