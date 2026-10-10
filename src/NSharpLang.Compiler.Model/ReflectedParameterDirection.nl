namespace NSharpLang.Compiler

import System
import System.Reflection


// THE CALL-SITE RULE A REFLECTED BY-REFERENCE PARAMETER CARRIES.
//
// `ref`, `out`, `in` and `ref readonly` are all `&T` in a signature. Metadata tells `out` apart with
// `[Out]`, and marks BOTH read-only directions with `[In]`; only `RequiresLocationAttribute` separates
// `ref readonly` from `in`, and the two take different arguments. An `in` parameter takes its argument
// bare or written `in`, as the same declaration in source does -- a written `ref` asks for a writable
// alias the callee does not offer. A `ref readonly` parameter (`Volatile.Read(ref readonly bool)`) asks
// for a LOCATION, and takes it written `ref` or `in`; a bare value is refused, as it would need a
// temporary where the callee asked for the caller's own storage (C# only warns). Neither is written
// through by the callee.
class ReflectedParameterDirection {

    // A read-only by-reference parameter of either spelling: the callee reads the location and never
    // writes it.
    static func IsReadOnlyReference(parameter: ParameterInfo): bool {
        return parameter.ParameterType.IsByRef && parameter.IsIn && !parameter.IsOut
    }

    // `ref readonly` -- a read-only reference that also takes a written `ref`.
    static func IsReadOnlyLocation(parameter: ParameterInfo): bool {
        if !IsReadOnlyReference(parameter) {
            return false
        }

        // A parameter of a type still being built answers no attributes at all; it is read as `in`,
        // which is every such parameter this compilation declares.
        try {
            for attribute in parameter.GetCustomAttributesData() {
                if attribute.AttributeType.FullName == "System.Runtime.CompilerServices.RequiresLocationAttribute" {
                    return true
                }
            }
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }

        return false
    }
}
