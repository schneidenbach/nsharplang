namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// A record `with` expression is non-destructive mutation: it yields a fresh instance that copies the
// receiver and replaces the named members. The CLR shape of that copy is a semantic decision that turns
// entirely on whether the record is a reference type or a value type, and N# owns it here:
//
//   * ReferenceClone — a record CLASS. The fresh instance is produced by the synthesized `<Clone>$`
//     virtual (a MemberwiseClone downcast) called on the receiver object reference. Each replacement
//     targets the cloned reference directly (ldloc; <value>; stfld), and the modified reference is the
//     result.
//   * ValueCopy — a record STRUCT. A value type is copied by plain assignment, so the fresh instance is
//     just a local initialised to the receiver value (stloc). There is NO clone virtual: `callvirt` on a
//     value type is unverifiable, and a value receiver is not an object reference, so an instance call
//     would need the value's ADDRESS, not the value. Each replacement instead targets the copy's address
//     (ldloca; <value>; stfld), and the modified copy value is the result.
//
// The host emitter evaluates the receiver and each replacement value through its recursive sub-emitter and
// applies the exact opcode shape this plan prescribes; it never re-derives clone-versus-copy, the receiver
// address-versus-value shape, the member set and its order, the readonly rule, the exact call form, or the
// result type.
enum ColumnarRecordWithStrategy {
    ReferenceClone,
    ValueCopy
}

// The resolved lowering for one record `with` expression. The host consumes Strategy to choose the copy
// opcode and the per-member receiver shape, CloneMethod as the exact reference-clone call target, Fields as
// the ordered replacement targets aligned with its replacement value nodes, and ResultType as the value the
// expression leaves on the stack.
class ColumnarRecordWithPlan {
    Strategy: ColumnarRecordWithStrategy
    // The synthesized `<Clone>$` virtual for a reference record; null for a value record, which is copied
    // by assignment and has no clone method.
    CloneMethod: MethodBuilder?
    // The record type the expression produces — the receiver's own type.
    ResultType: Type
    // The replacement target fields, resolved in source order and aligned with the host's replacement value
    // nodes.
    Fields: FieldBuilder[]

    constructor(strategy: ColumnarRecordWithStrategy, cloneMethod: MethodBuilder?, resultType: Type, fields: FieldBuilder[]) {
        if resultType == null || fields == null {
            throw new InvalidOperationException("A record-with plan requires a result type and its resolved replacement fields.")
        }
        Strategy = strategy
        CloneMethod = cloneMethod
        ResultType = resultType
        Fields = fields
    }
}

class ColumnarRecordWithPlanner {

    // Select the clone/copy strategy, receiver shape, ordered replacement set, and result type for one
    // record `with` expression. Returns null to decline — so the mechanical host reports the standard
    // with-expression decline — when the receiver is not a modelled record, when a reference record is
    // missing its `<Clone>$` synthesis, when a named member is not a field of the receiver, or when a
    // target field is initonly (a readonly member cannot be rewritten by stfld outside its declaring
    // constructor, so that shape routes to the residual). fieldNames are the replacement member names in
    // source order, already validated as syntactic identifiers by the host.
    static func PlanRecordWith(receiverDef: ColumnarStructDef?, fieldNames: string[]): ColumnarRecordWithPlan? {
        if fieldNames == null {
            throw new InvalidOperationException("Record-with planning requires the replacement member names.")
        }
        if receiverDef == null || !receiverDef.IsRecord {
            return null
        }

        strategy := ColumnarRecordWithStrategy.ValueCopy
        cloneMethod: MethodBuilder? = null
        if receiverDef.IsReference {
            // A reference record clones through its synthesized `<Clone>$` virtual; without that synthesis
            // there is no verifiable reference copy, so decline.
            if receiverDef.RecordClone == null {
                return null
            }
            strategy = ColumnarRecordWithStrategy.ReferenceClone
            cloneMethod = receiverDef.RecordClone
        }

        fields := new FieldBuilder[](fieldNames.Length)
        index := 0
        while index < fieldNames.Length {
            name := fieldNames[index]
            if name == null {
                return null
            }
            field: FieldBuilder? = null
            if !receiverDef.Fields.TryGetValue(name, out field) || field == null {
                return null
            }
            if field.get_IsInitOnly() {
                return null
            }
            fields[index] = field
            index = index + 1
        }

        return new ColumnarRecordWithPlan(strategy, cloneMethod, receiverDef.Builder, fields)
    }
}
