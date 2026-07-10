namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// Live raw facts for recursive N# fragment planning. The legacy emitter may pass these existing
// maps mechanically; N# alone decides lookup order, shadowing, and which bindings E0 can own.
public class ColumnarFragmentBindings {
    public ParameterOrdinals: Dictionary<string, int>
    public ParameterTypes: Dictionary<string, Type>
    public Locals: Dictionary<string, LocalBuilder>
    public Enums: Dictionary<string, ColumnarEnumDef>
    blockedNames: HashSet<string>
    callableNames: HashSet<string>

    constructor(
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedNames: IEnumerable<string>,
        boxedNames: IEnumerable<string>,
        enclosingNames: IEnumerable<string>,
        callableBindingNames: IEnumerable<string>) {
        if parameterOrdinals == null || parameterTypes == null || locals == null || enums == null
            || liftedNames == null || boxedNames == null || enclosingNames == null
            || callableBindingNames == null {
            throw new InvalidOperationException("Columnar fragment binding facts cannot be null.")
        }

        ParameterOrdinals = parameterOrdinals
        ParameterTypes = parameterTypes
        Locals = locals
        Enums = enums
        blockedNames = new HashSet<string>(StringComparer.Ordinal)
        callableNames = new HashSet<string>(StringComparer.Ordinal)
        AddNames(blockedNames, liftedNames)
        AddNames(blockedNames, boxedNames)
        AddNames(blockedNames, enclosingNames)
        AddNames(callableNames, callableBindingNames)
    }

    public func IsBlocked(name: string): bool {
        return blockedNames.Contains(name)
    }

    public func IsCallable(name: string): bool {
        return callableNames.Contains(name)
    }

    public func IsValueBinding(name: string): bool {
        return Locals.ContainsKey(name)
            || ParameterOrdinals.ContainsKey(name)
            || IsBlocked(name)
    }

    static func AddNames(target: HashSet<string>, values: IEnumerable<string>) {
        for value in values {
            target.Add(value)
        }
    }
}
