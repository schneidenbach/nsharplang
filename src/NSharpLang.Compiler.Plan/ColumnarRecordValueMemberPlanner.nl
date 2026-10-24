namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


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
// Equals/GetHashCode enter a plan type pool only when no field type is builder-bound, so each
// EqualityComparer<T> instantiation closes over a runtime type. `<Clone>$` touches no field type and
// is synthesized for generic records too; its small generic body is emitted directly because the
// plan type pool deliberately refuses an open generic record TypeBuilder.
class ColumnarRecordValueMemberPlanner {

    // PASS 0e owns the complete record value-member decision and emission sequence. The input row
    // remains the declaration selector, while the parallel definition row supplies the live builders
    // and registries populated by the preceding declaration passes.
    static func EmitRecordValueMembers(structs: IReadOnlyList<ColumnarStructInput>, definitions: ColumnarStructDef[], table: ColumnarStructuralTypeReferenceTable) {
        s := 0
        while s < structs.Count {
            input := structs[s]
            if input.IsRecord {
                def := definitions[s]
                if def.GenericParameters == null {
                    fieldsBaked := true
                    fieldNames := def.FieldOrder
                    fieldIndex := 0
                    while fieldIndex < fieldNames.Length {
                        fieldName := fieldNames[fieldIndex]
                        field := def.Fields[fieldName]
                        fieldType := field.FieldType
                        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(fieldType) {
                            fieldsBaked = false
                            break
                        }
                        fieldIndex = fieldIndex + 1
                    }

                    if fieldsBaked {
                        if !def.Methods.ContainsKey("Equals") {
                            equals := def.DefineSynthesizedRecordEquals()
                            equalsPlan := BuildEqualsPlan(def, table)
                            equalsIl := equals.GetILGenerator()
                            ColumnarCodePlanExecutor.Execute(equalsPlan, equalsIl)
                        }

                        if !def.Methods.ContainsKey("GetHashCode") {
                            hash := def.DefineSynthesizedRecordGetHashCode()
                            hashPlan := BuildGetHashCodePlan(def, table)
                            hashIl := hash.GetILGenerator()
                            ColumnarCodePlanExecutor.Execute(hashPlan, hashIl)
                        }
                    }
                }

                // Only a reference record carries the public clone wrapper used by `with`. Generic
                // records need it as well: the body copies the runtime object and casts to this
                // record, without reading any field whose type is still a builder.
                if def.IsReference && def.RecordClone == null {
                    recordType := def.Builder
                    cloneReturnType: System.Type = recordType
                    if def.GenericParameters != null {
                        genericArguments := new Type[def.GenericParameterNames.Length]
                        for i := 0; i < genericArguments.Length; i++ {
                            genericArguments[i] = def.GenericParameters[def.GenericParameterNames[i]]
                        }
                        // A member on Box<T> has the constructed self type Box<!0> in its signature;
                        // the open TypeBuilder itself is only the generic definition.
                        cloneReturnType = recordType.MakeGenericType(genericArguments)
                    }
                    clone := recordType.DefineMethod(
                        "<Clone>$",
                        MethodAttributes.Public | MethodAttributes.HideBySig,
                        cloneReturnType,
                        System.Type.EmptyTypes
                    )
                    if def.GenericParameters == null {
                        clonePlan := BuildClonePlan(def, table)
                        cloneIl := clone.GetILGenerator()
                        ColumnarCodePlanExecutor.Execute(clonePlan, cloneIl)
                    } else {
                        cloneIl := clone.GetILGenerator()
                        cloneIl.Emit(OpCodes.Ldarg_0)
                        cloneIl.Emit(OpCodes.Call, MemberwiseCloneMethod())
                        cloneIl.Emit(OpCodes.Castclass, cloneReturnType)
                        cloneIl.Emit(OpCodes.Ret)
                    }
                    def.RecordClone = clone
                }
            }
            s = s + 1
        }
    }

    // `ldarg.1; brfalse RF; ldarg.1; isinst T; dup; brtrue CF; pop; br RF;
    //  CF: [unbox.any T]; stloc other; {per field: call Default; ldarg.0; ldfld f; ldloc other;
    //  ldfld f; callvirt Equals; brfalse RF}; ldc.i4.1; ret; RF: ldc.i4.0; ret`
    //
    // A record STRUCT unboxes the `isinst` result before the typed store; a record CLASS stores the
    // reference directly. That single arm is the whole difference between the two shapes.
    static func BuildEqualsPlan(def: ColumnarStructDef, table: ColumnarStructuralTypeReferenceTable): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        isReference := def.IsReference
        fieldNames := def.FieldOrder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(table.SelectSourceDefinition(def.DeclaredTypeName, recordType), table)
        thisArgument := plan.AddArgument(0, recordTypeIndex, !isReference)
        otherArgument := plan.AddArgument(1, plan.AddType(table.SelectRuntimeType(typeof(object)), table), false)
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

        for fieldName in fieldNames {
            field := def.Fields[fieldName]
            fieldType := field.FieldType
            comparerType := ComparerTypeFor(fieldType)
            fieldPool := plan.AddField(field)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(ComparerDefaultGetter(comparerType)))
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArgument)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), otherLocal)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(ComparerEqualsMethod(comparerType, fieldType)))
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), returnFalse)
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
    static func BuildGetHashCodePlan(def: ColumnarStructDef, table: ColumnarStructuralTypeReferenceTable): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        isReference := def.IsReference
        fieldNames := def.FieldOrder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(table.SelectSourceDefinition(def.DeclaredTypeName, recordType), table)
        thisArgument := plan.AddArgument(0, recordTypeIndex, !isReference)
        accumulator := plan.DeclarePlanLocal(plan.AddType(table.SelectRuntimeType(typeof(int)), table))

        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(17))
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), accumulator)

        for fieldName in fieldNames {
            field := def.Fields[fieldName]
            fieldType := field.FieldType
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
    // record struct, carries none — calling an instance clone method through `callvirt` on a value is
    // unverifiable.
    static func BuildClonePlan(def: ColumnarStructDef, table: ColumnarStructuralTypeReferenceTable): ColumnarCodePlan {
        RequireRecordDef(def)
        recordType := def.Builder
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        recordTypeIndex := plan.AddType(table.SelectSourceDefinition(def.DeclaredTypeName, recordType), table)
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
        // The synthesis driver's guard keeps every TypeBuilder operand below a storable plan type, so
        // it is re-asserted here rather than assumed: ValidateStorableType refuses a generic type
        // definition. Generic records use the direct `<Clone>$` body and never enter these plans.
        if def.GenericParameters != null {
            throw new InvalidOperationException("A generic record definition never reaches record value-member synthesis.")
        }
    }

    static func ComparerTypeFor(fieldType: Type): Type {
        definition := RequiredRuntimeTypes.Find("System.Collections.Generic.EqualityComparer`1")
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
        for candidate in candidates {
            if candidate.Name == "MemberwiseClone" {
                parameters := candidate.GetParameters()
                if parameters.Length == 0 {
                    return candidate
                }
            }
        }
        throw new InvalidOperationException("System.Object.MemberwiseClone was not found.")
    }
}
