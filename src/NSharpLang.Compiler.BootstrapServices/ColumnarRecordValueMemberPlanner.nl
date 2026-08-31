namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// PASS 0e — the synthesized record value members: `Equals(object)`, `GetHashCode()` and `<Clone>$`.
//
// THESE ARE THE PLAN-ROW IR's FIRST `this`-BEARING METHOD BODIES. B1 planned the one non-iterator body
// that needed no argument row at all (a static parameterless shim); every body here begins `ldarg.0`,
// which is why it had to wait for the emitter's modeled `OpCodes` surface to admit the short-form
// argument loads and for the toolset carrying that surface to be republished. `Emit(OpCode, short)`
// never narrows `Ldarg`, so before the widening a planned body would have been three bytes larger per
// load than the hand-written IL it replaces.
//
// The bodies are SYNTHESIZED rather than parsed, so coverage is total by construction: there is no user
// syntax to decline and the planner claims a whole body or nothing.
//
// TWO UPSTREAM GUARDS MAKE THE TYPE POOL LEGAL, and both are re-verified at the emitter's call site.
// A generic record never reaches synthesis, so the record's `TypeBuilder` is never a generic type
// definition — which is the one shape `ValidateStorableType` refuses among the three that could apply.
// And `Equals`/`GetHashCode` are synthesized only when no field type is builder-bound, so every
// `EqualityComparer<T>` instantiation below closes over a runtime type. `<Clone>$` is reached on BOTH
// paths, including the builder-bound one, and it is sound there precisely because it touches no field
// type at all.
class ColumnarRecordValueMemberPlanner {

    // `ldarg.1; brfalse RF; ldarg.1; isinst T; dup; brtrue CF; pop; br RF;
    //  CF: [unbox.any T]; stloc other; {per field: call Default; ldarg.0; ldfld f; ldloc other;
    //  ldfld f; callvirt Equals; brfalse RF}; ldc.i4.1; ret; RF: ldc.i4.0; ret`
    //
    // A record STRUCT unboxes the `isinst` result before the typed store; a record CLASS stores the
    // reference directly. That single arm is the whole difference between the two shapes.
    static func BuildEqualsPlan(def: ColumnarStructDef): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        isReference := def.IsReference
        fieldNames := def.FieldOrder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(recordType)
        thisArgument := plan.AddArgument(0, recordTypeIndex, !isReference)
        otherArgument := plan.AddArgument(1, plan.AddType(typeof(object)), false)
        otherLocal := plan.DeclarePlanLocal(recordTypeIndex)
        returnFalse := plan.DefineLabel()
        compareFields := plan.DefineLabel()

        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), otherArgument)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), returnFalse)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), otherArgument)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), recordTypeIndex)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), compareFields)
        // The `dup` kept a copy alive for the test; the failing path discards it. A body is a statement
        // sequence, so the discard has to be explicit — this is the `pop` row B1 added.
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), returnFalse)

        plan.AppendMarkLabel(compareFields)
        if !isReference {
            plan.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), recordTypeIndex)
        }
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), otherLocal)

        i := 0
        while i < fieldNames.Length {
            fieldName := fieldNames[i]
            field := def.Fields[fieldName]
            fieldType := field.get_FieldType()
            comparerType := ComparerTypeFor(fieldType)
            fieldPool := plan.AddField(field)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(ComparerDefaultGetter(comparerType)))
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArgument)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), otherLocal)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(ComparerEqualsMethod(comparerType, fieldType)))
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), returnFalse)
            i = i + 1
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.AppendMarkLabel(returnFalse)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(bool))
        return plan
    }

    // `ldc.i4 17; stloc acc; {per field: ldloc acc; ldc.i4 23; mul; call Default; ldarg.0; ldfld f;
    //  callvirt GetHashCode; add; stloc acc}; ldloc acc; ret`
    //
    // The two constants take the FULL `ldc.i4` form, not `ldc.i4.s`: `ILGenerator.Emit(OpCode, int)`
    // does not narrow, so the plan reproduces the hand-written encoding exactly.
    static func BuildGetHashCodePlan(def: ColumnarStructDef): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        isReference := def.IsReference
        fieldNames := def.FieldOrder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(recordType)
        thisArgument := plan.AddArgument(0, recordTypeIndex, !isReference)
        accumulator := plan.DeclarePlanLocal(plan.AddType(typeof(int)))

        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(17))
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), accumulator)

        i := 0
        while i < fieldNames.Length {
            fieldName := fieldNames[i]
            field := def.Fields[fieldName]
            fieldType := field.get_FieldType()
            comparerType := ComparerTypeFor(fieldType)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), accumulator)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(23))
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Mul())
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(ComparerDefaultGetter(comparerType)))
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArgument)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), plan.AddField(field))
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(ComparerHashMethod(comparerType, fieldType)))
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), accumulator)
            i = i + 1
        }

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), accumulator)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(int))
        return plan
    }

    // `ldarg.0; call object::MemberwiseClone; castclass T; ret`
    //
    // Only a record CLASS gets a `<Clone>$`: it is the copy source for the ReferenceClone strategy of a
    // record-class `with`. A record STRUCT is copied by plain value assignment and, exactly like a C#
    // record struct, carries none — a value-type clone virtual would be called through `callvirt` on a
    // value, which is unverifiable.
    static func BuildClonePlan(def: ColumnarStructDef): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(recordType)
        thisArgument := plan.AddArgument(0, recordTypeIndex, false)

        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArgument)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(MemberwiseCloneMethod()))
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Castclass(), recordTypeIndex)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(recordType)
        return plan
    }

    static func RequireRecordDef(def: ColumnarStructDef) {
        if def == null {
            throw new InvalidOperationException("A record value-member plan needs its record definition.")
        }
        // The emitter's own guard (a generic record never reaches synthesis) is what keeps every
        // TypeBuilder operand below a storable plan type, so it is re-asserted here rather than assumed:
        // ValidateStorableType refuses a generic type definition, and this is the shape that would
        // produce one.
        if def.GenericParameters != null {
            throw new InvalidOperationException("A generic record definition never reaches record value-member synthesis.")
        }
    }

    static func ComparerTypeFor(fieldType: Type): Type {
        definition := Type.GetType("System.Collections.Generic.EqualityComparer`1")
        if definition == null {
            throw new InvalidOperationException("System.Collections.Generic.EqualityComparer`1 was not found.")
        }
        arguments := new Type[](1)
        arguments[0] = fieldType
        return definition.MakeGenericType(arguments)
    }

    static func ComparerDefaultGetter(comparerType: Type): MethodInfo {
        property := comparerType.GetProperty("Default")
        if property == null {
            throw new InvalidOperationException("EqualityComparer<T> exposes no Default property.")
        }
        getter := property.GetGetMethod()
        if getter == null {
            throw new InvalidOperationException("EqualityComparer<T>.Default exposes no getter.")
        }
        return getter
    }

    static func ComparerEqualsMethod(comparerType: Type, fieldType: Type): MethodInfo {
        parameterTypes := new Type[](2)
        parameterTypes[0] = fieldType
        parameterTypes[1] = fieldType
        method := comparerType.GetMethod("Equals", parameterTypes)
        if method == null {
            throw new InvalidOperationException("EqualityComparer<T> exposes no Equals(T, T).")
        }
        return method
    }

    static func ComparerHashMethod(comparerType: Type, fieldType: Type): MethodInfo {
        parameterTypes := new Type[](1)
        parameterTypes[0] = fieldType
        method := comparerType.GetMethod("GetHashCode", parameterTypes)
        if method == null {
            throw new InvalidOperationException("EqualityComparer<T> exposes no GetHashCode(T).")
        }
        return method
    }

    // `MemberwiseClone` is PROTECTED, so the public `GetMethod(name)` lookup cannot see it and the
    // `(name, BindingFlags)` overload is not part of the emitter's modeled reflection surface. The
    // non-public instance method list is, so the member is found by name in that list.
    static func MemberwiseCloneMethod(): MethodInfo {
        candidates := typeof(object).GetMethods(BindingFlags.Instance | BindingFlags.NonPublic)
        i := 0
        while i < candidates.Length {
            candidate := candidates[i]
            if candidate.get_Name() == "MemberwiseClone" {
                parameters := candidate.GetParameters()
                if parameters.Length == 0 {
                    return candidate
                }
            }
            i = i + 1
        }
        throw new InvalidOperationException("System.Object.MemberwiseClone was not found.")
    }
}
