namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit


// A record `with` expression is non-destructive mutation: it yields a fresh instance that copies the
// receiver and replaces the named members. The CLR shape of that copy is a semantic decision that turns
// entirely on whether the record is a reference type or a value type, and N# owns it here:
//
//   * ReferenceClone — a record CLASS. The fresh instance is produced by the synthesized `<Clone>$`
//     virtual (a MemberwiseClone downcast) called on the receiver object reference. Each replacement
//     targets the cloned reference directly (ldloc; <value>; stfld), and the modified reference is the
//     result. A `virtual` auto-property is replaced through its SETTER (ldloc; <value>; callvirt), as
//     C#'s `with` does: the clone has the receiver's runtime type, and an override — a runtime proxy's
//     included — owns that member's storage.
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
    // The replacement targets, resolved in source order and aligned with the host's replacement value
    // nodes: at each position exactly one of `Fields` (a stored member) and `Setters` (a dispatched
    // property) is set, and `MemberTypes` is the value's type either way.
    Fields: FieldBuilder?[]
    Setters: MethodBuilder?[]
    MemberTypes: Type[]
    MemberNames: string[]

    constructor(strategy: ColumnarRecordWithStrategy, cloneMethod: MethodBuilder?, resultType: Type, fields: FieldBuilder?[], setters: MethodBuilder?[], memberTypes: Type[], memberNames: string[]) {
        if resultType == null || fields == null || setters == null || memberTypes == null || memberNames == null || fields.Length != setters.Length || fields.Length != memberTypes.Length || fields.Length != memberNames.Length {
            throw new InvalidOperationException("A record-with plan requires a result type and its resolved replacement targets.")
        }
        Strategy = strategy
        CloneMethod = cloneMethod
        ResultType = resultType
        Fields = fields
        Setters = setters
        MemberTypes = memberTypes
        MemberNames = memberNames
    }
}

class ColumnarRecordWithPlanner {

    // Select the clone/copy strategy, receiver shape, ordered replacement set, and result type for one
    // record `with` expression. Returns null to decline — so the mechanical host reports the standard
    // with-expression decline — when the receiver is not a modelled record, when a reference record is
    // missing its `<Clone>$` synthesis, when a named member is neither a field of the receiver nor a
    // settable property of a reference record, or when a target field is initonly (a readonly member cannot be rewritten by stfld outside its declaring
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

        fields := new FieldBuilder?[](fieldNames.Length)
        setters := new MethodBuilder?[](fieldNames.Length)
        memberTypes := new Type[](fieldNames.Length)
        index := 0
        while index < fieldNames.Length {
            name := fieldNames[index]
            if name == null {
                return null
            }
            field: FieldBuilder? = null
            property: ColumnarPropertyDef? = null
            if receiverDef.Fields.TryGetValue(name, out field) && field != null {
                if field.IsInitOnly {
                    return null
                }
                fields[index] = field
                memberTypes[index] = field.FieldType
            } else if receiverDef.IsReference && receiverDef.Properties.TryGetValue(name, out property) && property != null && property.Setter != null && !property.IsInitOnly {
                setters[index] = property.Setter
                memberTypes[index] = property.PropertyType
            } else {
                return null
            }
            index = index + 1
        }

        return new ColumnarRecordWithPlan(strategy, cloneMethod, receiverDef.Builder, fields, setters, memberTypes, fieldNames)
    }
}
