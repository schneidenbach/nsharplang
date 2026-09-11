namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// The resolved placement of a reference type's instance field initializers. A class/record field
// initializer (`readonly Pi: double = 3.14159`) is parsed into a synthesized zero-parameter initializer
// constructor whose body is a list of top-level `field = value` assignments. Where each of those stores is
// emitted is a semantic decision turning entirely on the CLR verification rule that an initonly (readonly)
// instance field may be stored ONLY inside a constructor of its declaring type — a store from any other
// method (the shared `<InitializeFields>$` helper) is unverifiable (ILVerify IL:InitOnly). N# owns that
// decision here:
//
//   * InlineOrdinals — the block-child ordinals of the initializer body whose top-level assignment targets
//     an initonly field. These stores must run INLINE in every base-reaching constructor, because that is
//     the only place a readonly store verifies.
//   * HelperOrdinals — the block-child ordinals whose target is a mutable field, or any statement that is
//     not a clean own-field assignment. These may keep the shared `<InitializeFields>$` helper method that
//     every base-reaching constructor calls; a mutable-field store verifies from the helper.
//   * InitializedFieldNames — every own-field name a top-level assignment initializes (readonly and
//     mutable), the seed for the constructor all-fields-assigned check.
//   * NeedsHelper — true iff a `<InitializeFields>$` helper method must be synthesized, i.e. HelperOrdinals
//     is non-empty. A type whose only initializers are readonly gets NO helper at all.
//
// The host emitter consumes InlineOrdinals to emit the readonly stores directly into each constructor body,
// HelperOrdinals to emit the mutable stores into the helper it synthesizes only when NeedsHelper, and
// InitializedFieldNames to seed the assigned-field set; it never re-derives which stores are readonly or
// where each store is placed.
class ColumnarFieldInitPlan {
    InlineOrdinals: int[]
    HelperOrdinals: int[]
    InitializedFieldNames: string[]
    NeedsHelper: bool

    constructor(inlineOrdinals: int[], helperOrdinals: int[], initializedFieldNames: string[]) {
        if inlineOrdinals == null || helperOrdinals == null || initializedFieldNames == null {
            throw new InvalidOperationException("A field-initialization plan requires its resolved ordinals and field names.")
        }
        InlineOrdinals = inlineOrdinals
        HelperOrdinals = helperOrdinals
        InitializedFieldNames = initializedFieldNames
        NeedsHelper = helperOrdinals.Length > 0
    }
}

class ColumnarFieldInitPlanner {

    // Partition a synthesized instance-field-initializer body into the readonly stores that must run inline
    // in every constructor and the mutable stores that may keep the shared helper. `def.Fields` already
    // carries the exact FieldBuilder for each own instance field with its initonly attribute resolved, so
    // readonly classification reads directly off the field handle — no re-derivation.
    static func PlanFieldInitialization(body: ColumnarFunctionInput, source: string, def: ColumnarStructDef): ColumnarFieldInitPlan {
        if body == null || source == null || def == null {
            throw new InvalidOperationException("Field-initialization planning requires the initializer body, its source, and the type.")
        }

        inline := new List<int>()
        helper := new List<int>()
        names := new List<string>()

        nodes := body.BodyNodes
        bodyRoot := body.BodyRoot
        if bodyRoot >= 0 && nodes.Kind(bodyRoot) == 25 {
            childCount := nodes.ChildCount(bodyRoot)
            n := 0
            while n < childCount {
                stmt := nodes.Child(bodyRoot, n)
                fieldName := TopLevelFieldAssignmentTarget(nodes, source, stmt)
                isReadonly := false
                if fieldName != null {
                    names.Add(fieldName)
                    field: FieldBuilder? = null
                    if def.Fields.TryGetValue(fieldName, out field) && field != null && field.get_IsInitOnly() {
                        isReadonly = true
                    }
                }

                if isReadonly {
                    inline.Add(n)
                } else {
                    helper.Add(n)
                }
                n = n + 1
            }
        }

        return new ColumnarFieldInitPlan(inline.ToArray(), helper.ToArray(), names.ToArray())
    }

    // A top-level field-initializer statement is an expression statement (kind 23, one child) whose child is
    // a simple `=` assignment (kind 14, operator text `=`, two children) with an identifier target (kind 6
    // carrying a value span). Returns the target identifier text, or null when the statement is not that
    // shape (in which case the host keeps it in the helper, preserving the pre-partition behavior).
    static func TopLevelFieldAssignmentTarget(nodes: ColumnarNodeTable, source: string, stmt: int): string? {
        if nodes.Kind(stmt) != 23 || nodes.ChildCount(stmt) != 1 {
            return null
        }
        expr := nodes.Child(stmt, 0)
        if nodes.Kind(expr) != 14 || nodes.Text(source, expr) != "=" || nodes.ChildCount(expr) != 2 {
            return null
        }
        target := nodes.Child(expr, 0)
        if nodes.Kind(target) == 6 && nodes.ValueStart(target) >= 0 {
            return nodes.Text(source, target)
        }
        return null
    }
}
