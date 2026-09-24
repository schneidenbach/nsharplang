namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// The resolved placement of a reference type's instance field initializers. A class/record field
// initializer (`readonly Pi: double = 3.14159`) is parsed into a synthesized zero-parameter initializer
// constructor whose body is a list of top-level `field = value` assignments, and EVERY one of those
// stores is emitted INLINE, in each base-reaching constructor, ahead of the base constructor call.
// Two CLR rules decide that and neither leaves a choice: an initonly instance field may be stored only
// inside a constructor of its declaring type, and an instance method may not be called on `this` before
// the base constructor has run. So a shared `<InitializeFields>$` helper cannot hold a readonly store
// (ILVerify IL:InitOnly) and cannot be CALLED at the point C# runs the initializers. C#'s own lowering
// is the same one: it repeats the initializers in every constructor that does not chain to `this(...)`.
//
//   * InlineOrdinals — every block-child ordinal of the initializer body, in source order.
//   * InitializedFieldNames — every own-field name a top-level assignment initializes (readonly and
//     mutable), the seed for the constructor all-fields-assigned check.
//
// The host emitter consumes InlineOrdinals to emit the stores directly into each constructor body and
// InitializedFieldNames to seed the assigned-field set; it never re-derives where a store is placed.
class ColumnarFieldInitPlan {
    InlineOrdinals: int[]
    InitializedFieldNames: string[]

    constructor(inlineOrdinals: int[], initializedFieldNames: string[]) {
        if inlineOrdinals == null || initializedFieldNames == null {
            throw new InvalidOperationException("A field-initialization plan requires its resolved ordinals and field names.")
        }
        InlineOrdinals = inlineOrdinals
        InitializedFieldNames = initializedFieldNames
    }
}

class ColumnarFieldInitPlanner {

    // Read a synthesized instance-field-initializer body as the ordered run of stores every
    // base-reaching constructor runs inline, and the own-field names those stores initialize.
    static func PlanFieldInitialization(body: ColumnarFunctionInput, source: string, def: ColumnarStructDef): ColumnarFieldInitPlan {
        if body == null || source == null || def == null {
            throw new InvalidOperationException("Field-initialization planning requires the initializer body, its source, and the type.")
        }

        inline := new List<int>()
        names := new List<string>()

        nodes := body.BodyNodes
        bodyRoot := body.BodyRoot
        if bodyRoot >= 0 && nodes.Kind(bodyRoot) == ColumnarStatementNodeKind.BlockStatement {
            childCount := nodes.ChildCount(bodyRoot)
            n := 0
            while n < childCount {
                stmt := nodes.Child(bodyRoot, n)
                fieldName := TopLevelFieldAssignmentTarget(nodes, source, stmt)
                if fieldName != null {
                    names.Add(fieldName)
                }

                inline.Add(n)
                n = n + 1
            }
        }

        return new ColumnarFieldInitPlan(inline.ToArray(), names.ToArray())
    }

    // A top-level field-initializer statement is an expression statement (kind 23, one child) whose child is
    // a simple `=` assignment (kind 14, operator text `=`, two children) with an identifier target (kind 6
    // carrying a value span). Returns the target identifier text, or null when the statement is not that
    // shape, in which case the statement is still emitted inline but seeds no assigned-field name.
    //
    // NOT EVERY ASSIGNMENT IN THIS BODY WAS WRITTEN DOWN. The synthesized instance initializer also
    // carries stores the source never spelled — a nullable field with no initializer is stored `null`,
    // and a primary-constructor parameter with no field of its own is stored from its parameter — and
    // those nodes carry NO operator span, because there is no `=` token behind them. Reading text out
    // of an absent span used to throw `ArgumentOutOfRangeException` out of `nlc check` (a class with
    // one nullable field and one initialized field was enough). A synthesized store is always a simple
    // `=`, so an absent span reads as `=` and the field it assigns is named like any other.
    static func TopLevelFieldAssignmentTarget(nodes: ColumnarNodeTable, source: string, stmt: int): string? {
        if nodes.Kind(stmt) != ColumnarStatementNodeKind.ExpressionStatement || nodes.ChildCount(stmt) != 1 {
            return null
        }
        expr := nodes.Child(stmt, 0)
        if nodes.Kind(expr) != ColumnarExpressionNodeKind.AssignmentExpression || nodes.ChildCount(expr) != 2 {
            return null
        }
        if nodes.ValueStart(expr) >= 0 && nodes.Text(source, expr) != "=" {
            return null
        }
        target := nodes.Child(expr, 0)
        if nodes.Kind(target) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(target) >= 0 {
            return nodes.Text(source, target)
        }
        return null
    }
}
