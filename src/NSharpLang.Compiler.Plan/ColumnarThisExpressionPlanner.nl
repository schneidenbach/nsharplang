namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// THE ONE OWNER OF A BARE `this` (node kind 82) AS A VALUE.
//
// `this.Member` never reaches here — the parser flattens it into an identifier the bound-identifier
// owner reads — so this is the keyword standing alone: `Describe(this)`, `me := this`, `return this`,
// `yield this`, `Changed?.Invoke(this, EventArgs.Empty)`. Where the instance lives is a fact of the
// BODY, and the bindings already carry every fact that decides it, so there are four answers:
//
//   a CAPTURED RECEIVER   an instance generator's state machine, the machine method a lambda in its
//                         body lowers onto, and a per-iteration display beside the machine each keep
//                         the object in one field of argument 0 (`bindings.CapturedReceiverField`):
//                         `ldarg.0; ldfld <>__this`. Argument 0 there is never the object.
//   a CLOSURE DISPLAY     a lambda's display keeps its lexical owner in `<>4__this`, and a display
//                         nested in another keeps the PARENT DISPLAY there, so the read follows one
//                         hop per display until it reaches the type that wrote `this` — the same walk
//                         `ColumnarBoundIdentifierPlanner` takes for a captured member.
//   a CLASS BODY          argument 0 is the instance: `ldarg.0`.
//   a STRUCT BODY         argument 0 is a managed pointer to the instance and the position asks for
//                         a value, so `this` is a COPY: `ldarg.0; ldobj T`. That is C#'s reading too,
//                         and it is why `me := this; me.X = 1` never writes the receiver.
//
// A static body has no current instance and declines: the analyzer has already reported NL327 there,
// and `ldarg.0` would silently hand out the first parameter.
class ColumnarThisExpressionPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.ThisExpression
    }

    // A parsed `this` root is terminal: no other owner can lower the keyword, so an unplannable one
    // declines the enclosing function rather than falling through.
    static func ClaimsRoot(nodes: ColumnarNodeTable, node: int): bool {
        return MayPlanRoot(nodes, node)
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(object)
            return false
        }
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "this expression")
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(object)
            return false
        }
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "this expression")
        return true
    }

    // The root-append sequence the facade's `Plan` runs and the method-body door enters directly, so
    // both produce the same rows by construction.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(object)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.ThisExpression {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.ThisExpression, candidate)
            if !TryAppend(nodes, candidate, bindings, plan, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            plan.CompleteFragment(fragment, resultType)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        if nodes == null || source == null || bindings == null || plan == null {
            throw new InvalidOperationException("This-expression planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("This-expression planning received an invalid root node index.")
        }

        plan.PrepareV3()
        resultType := typeof(object)
        if !TryAppendRoot(nodes, source, node, bindings, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // The value rows, into whatever fragment the caller opened: a v3 root, a nested argument or
    // receiver, or a statement tree of a method body.
    static func TryAppend(nodes: ColumnarNodeTable, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(object)
        if nodes.Kind(node) != ColumnarExpressionNodeKind.ThisExpression || nodes.ChildCount(node) != 0 {
            return false
        }

        capturedReceiver := bindings.CapturedReceiverField
        if capturedReceiver != null {
            return AppendCapturedReceiver(plan, capturedReceiver, out resultType)
        }

        instance := bindings.CurrentInstance
        if instance == null {
            return false
        }
        if instance.IsClosureDisplay {
            return TryAppendDisplayReceiver(instance, plan, out resultType)
        }

        // The same argument-0 facts the bound-identifier owner records for a current-instance member
        // read — the self-instantiated type, and an address exactly when the body is a struct's — so a
        // body that reads `this` and `this.X` pools argument 0 once.
        instanceType := ColumnarBoundIdentifierPlanner.OpenCurrentInstanceType(instance.ExactType)
        isStruct := !instance.IsReference
        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, instanceType, isStruct)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        if isStruct {
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldobj(), plan.AddType(instanceType))
        }
        resultType = instanceType
        return true
    }

    static func AppendCapturedReceiver(plan: ColumnarCodePlan, capturedReceiver: FieldInfo, out resultType: Type): bool {
        ownerType := capturedReceiver.DeclaringType
        if ownerType == null || ownerType.IsValueType || capturedReceiver.IsStatic {
            throw new InvalidOperationException("A captured receiver must be an instance field of a reference-type owner.")
        }

        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, ownerType, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), plan.AddField(capturedReceiver))
        resultType = capturedReceiver.FieldType
        return true
    }

    // One `ldfld <>4__this` per display, from argument 0 outward, ending at the first level that is a
    // real type. Only a reference enclosing instance is ever captured into a display, so every hop is
    // a plain reference load.
    static func TryAppendDisplayReceiver(display: ColumnarCurrentInstanceFacts, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(object)
        current := display.SourceDefinition
        if current == null {
            return false
        }

        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, display.ExactType, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        while current != null {
            enclosing := current.ClosureEnclosingDef
            receiverField: FieldBuilder? = null
            if enclosing == null || !enclosing.IsReference || !current.Fields.TryGetValue(ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName(), out receiverField) || receiverField == null {
                return false
            }

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), plan.AddField(receiverField))
            if !enclosing.IsClosureDisplay {
                resultType = receiverField.FieldType
                return true
            }
            current = enclosing
        }

        return false
    }
}
