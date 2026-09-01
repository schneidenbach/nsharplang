namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// Exact external static fields and properties are selected, resolved, validated, and encoded by
// N#. An unstamped node table or any nearer lexical/type/member binding makes this owner decline.
class ColumnarExternalStaticMemberPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.MemberAccessExpression()
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        resultType := typeof(int)
        if !TryAppendRoot(nodes, source, node, bindings, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B15) — the factoring `015-B7` applied to the
    // direct-call owner, `015-B9` to the primitive-binary owner and `015-B14` to the instance-member
    // owner, for the same reason and for the LAST of door kind 8's two owners. An external
    // static-member root is a kind test, a checkpoint, a root fragment, the append and the fragment's
    // completion; whether the plan around it is a standalone schema-v3 expression (`Plan` wraps this
    // between `PrepareV3` and `CompleteV3`) or an open schema-v4 METHOD BODY
    // (`ColumnarMethodBodyPlanner`'s expression door calls it directly) is the wrapper's business, not
    // the sequence's. Both callers therefore produce the SAME row sequence, which is the whole of
    // producing the same bytes.
    //
    // ⚠ THIS IS THE CASCADE'S **SEVENTH** ARM, AND IT IS THE ONE THAT FALLS THROUGH.
    // `ColumnarRangeIndexPlanner.TryEmitFromFacts` asks this owner before `ColumnarInstanceMemberPlanner`
    // and, unlike arms one to six, does NOT return on a decline — it drops into the eighth arm. It also
    // never sets `nsharpOwned`. So a caller reproducing the cascade must offer the SAME open plan to
    // the next owner after a decline here, and `ColumnarCodePlan.Rollback` is what makes that legal: it
    // restores every pool count and both fragment counts, nulls `ResultType` and sets `Status` back to
    // `NotOwned` — the state the next owner's input gate demands.
    //
    // ⚠ AND IT DELIBERATELY CARRIES NO `try`/`catch`, WHICH IS WHERE THIS FACTORING DIFFERS FROM
    // `015-B14`'s. `ColumnarInstanceMemberPlanner.TryAppendRoot` has one because that owner's `Plan`
    // already had one before the factoring; this owner's `Plan` does not, and its only
    // rollback-on-throw lives inside `TryAppendStaticMember`, around the reflection block. Adding one
    // here would make the door's sequence differ from the sequence `Plan` runs, which is the one
    // property the factoring exists to preserve.
    //
    // The null contract is the softer one the second caller needs: `Plan` still THROWS through
    // `ValidateInputs` before it gets here, so its behaviour is unchanged, and a door that hands this
    // a null table declines instead of crashing.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.MemberAccessExpression() {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.MemberAccessExpression(), candidate)

        if !TryAppendStaticMember(nodes, source, candidate, bindings, plan, out resultType) {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(fragment, resultType)
        return true
    }

    static func TryAppendStaticMember(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // It appends a static load and recurses into nothing, but its callers are composites.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("External static-member append requires an open schema-v3 or method-body plan.")
        }

        ownerName := ""
        rootName := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), 0, out ownerName, out rootName) || bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || bindings.Enums.ContainsKey(ownerName) || bindings.Enums.ContainsKey(rootName) {
            return false
        }

        memberName := nodes.Text(source, node)
        selection := ColumnarExternalBindingPlans.GetStaticMemberPlan(ownerName, memberName)
        if !selection.IsSupported {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            scope := nodes.BindingScope
            declaringType := typeof(object)
            if nodes.HasAdditionalRootBinding(rootName) || scope == null || !scope.TryResolveExternalStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, selection.DeclaringTypeName, out declaringType) {
                plan.Rollback(checkpoint)
                return false
            }

            if selection.Kind == ColumnarExternalStaticMemberKind.Field {
                field := declaringType.GetField(selection.MemberName)
                fieldType := typeof(object)
                if field != null {
                    fieldType = field.get_FieldType()
                }

                if field == null || !field.get_IsStatic() || field.get_DeclaringType() != declaringType || !ExternalAssemblyScan.HasExactTypeIdentity(fieldType, selection.ValueTypeName) {
                    plan.Rollback(checkpoint)
                    return false
                }

                if field.get_IsLiteral() {
                    if !TryAppendLiteralField(plan, field, fieldType, selection.MemberName) {
                        plan.Rollback(checkpoint)
                        return false
                    }
                    resultType = fieldType
                    return true
                }

                fieldIndex := plan.AddField(field)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsfld(), fieldIndex)
                resultType = fieldType
                return true
            }

            if selection.Kind == ColumnarExternalStaticMemberKind.Property {
                property := declaringType.GetProperty(selection.MemberName)
                propertyType := typeof(object)
                if property != null {
                    propertyType = property.get_PropertyType()
                }

                if property == null || !ExternalAssemblyScan.HasExactTypeIdentity(propertyType, selection.ValueTypeName) {
                    plan.Rollback(checkpoint)
                    return false
                }

                getter := property.GetGetMethod()
                if getter == null || !getter.get_IsStatic() || getter.get_DeclaringType() != declaringType || getter.get_ReturnType() != propertyType || getter.GetParameters().Length != 0 {
                    plan.Rollback(checkpoint)
                    return false
                }

                methodIndex := plan.AddMethod(getter)
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
                resultType = propertyType
                return true
            }
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }

        plan.Rollback(checkpoint)
        return false
    }

    static func TryAppendLiteralField(plan: ColumnarCodePlan, field: FieldInfo, fieldType: Type, memberName: string): bool {
        value := field.GetValue(null)
        if value == null {
            return false
        }

        if fieldType.get_IsEnum() {
            intValue := Convert.ToInt32(value)
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }

        isMaximum := memberName == "MaxValue"
        if fieldType == typeof(int) {
            intValue := -2147483648
            if isMaximum {
                intValue = 2147483647
            }
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        if fieldType == typeof(uint) {
            intValue := 0
            if isMaximum {
                intValue = -1
            }
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        if fieldType == typeof(short) || fieldType == typeof(ushort) || fieldType == typeof(byte) || fieldType == typeof(sbyte) {
            intValue := 0
            if fieldType == typeof(short) {
                intValue = -32768
                if isMaximum {
                    intValue = 32767
                }
            } else if fieldType == typeof(ushort) {
                if isMaximum {
                    intValue = 65535
                }
            } else if fieldType == typeof(byte) {
                if isMaximum {
                    intValue = 255
                }
            } else {
                intValue = -128
                if isMaximum {
                    intValue = 127
                }
            }
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        if fieldType == typeof(long) {
            longValue := -9223372036854775807L
            if isMaximum {
                longValue = 9223372036854775807L
            } else {
                longValue = longValue - 1L
            }
            valueIndex := plan.AddInt64(longValue)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
            return true
        }
        if fieldType == typeof(ulong) {
            longValue := 0L
            if isMaximum {
                longValue = -1L
            }
            valueIndex := plan.AddInt64(longValue)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
            return true
        }
        return false
    }

    static func TryGetQualifiedName(nodes: ColumnarNodeTable, source: string, node: int, depth: int, out qualifiedName: string, out rootName: string): bool {
        qualifiedName = ""
        rootName = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ChildCount(node) != 0 || ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node) {
                return false
            }

            rootName = nodes.Text(source, node)
            qualifiedName = rootName
            return rootName.Length > 0
        }

        if kind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        prefix := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), depth + 1, out prefix, out rootName) {
            return false
        }

        member := nodes.Text(source, node)
        if member.Length == 0 {
            return false
        }

        qualifiedName = prefix + "." + member
        return true
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }

            node = nodes.Child(node, 0)
            depth = depth + 1
        }

        return node
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null {
            throw new InvalidOperationException("External static-member planning inputs cannot be null.")
        }

        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("External static-member planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned external static-member expression has no result type.")
        }

        return resultType
    }
}
