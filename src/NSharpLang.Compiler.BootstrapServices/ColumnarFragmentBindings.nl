namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// Live raw facts for recursive N# fragment planning. The legacy emitter may pass these existing
// maps mechanically; N# alone decides lookup order, shadowing, and which bindings E0 can own.
class ColumnarFragmentBindings {
    public ParameterOrdinals: Dictionary<string, int>
    public ParameterTypes: Dictionary<string, Type>
    public Locals: Dictionary<string, LocalBuilder>
    public Enums: Dictionary<string, ColumnarEnumDef>
    liftedNames: IEnumerable<string>
    boxedNames: IEnumerable<string>
    enclosingNames: IEnumerable<string>
    declaredCallableNames: IEnumerable<string>
    visibleLocalCallableNames: IEnumerable<string>

    constructor(
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedNames: IEnumerable<string>,
        boxedNames: IEnumerable<string>,
        enclosingNames: IEnumerable<string>,
        declaredCallableNames: IEnumerable<string>,
        visibleLocalCallableNames: IEnumerable<string>) {
        if parameterOrdinals == null || parameterTypes == null || locals == null || enums == null
            || liftedNames == null || boxedNames == null || enclosingNames == null
            || declaredCallableNames == null || visibleLocalCallableNames == null {
            throw new InvalidOperationException("Columnar fragment binding facts cannot be null.")
        }

        ParameterOrdinals = parameterOrdinals
        ParameterTypes = parameterTypes
        Locals = locals
        Enums = enums
        this.liftedNames = liftedNames
        this.boxedNames = boxedNames
        this.enclosingNames = enclosingNames
        this.declaredCallableNames = declaredCallableNames
        this.visibleLocalCallableNames = visibleLocalCallableNames
    }

    public func IsBlocked(name: string): bool {
        return ContainsName(liftedNames, name)
            || ContainsName(boxedNames, name)
            || ContainsName(enclosingNames, name)
    }

    public func IsCallable(name: string): bool {
        return ContainsName(declaredCallableNames, name)
            || ContainsName(visibleLocalCallableNames, name)
    }

    public func IsValueBinding(name: string): bool {
        return Locals.ContainsKey(name)
            || ParameterOrdinals.ContainsKey(name)
            || ParameterTypes.ContainsKey(name)
            || IsBlocked(name)
    }

    static func ContainsName(values: IEnumerable<string>, name: string): bool {
        for value in values {
            if String.Equals(value, name, StringComparison.Ordinal) {
                return true
            }
        }
        return false
    }
}
