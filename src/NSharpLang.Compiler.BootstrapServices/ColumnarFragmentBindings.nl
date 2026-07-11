namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Live raw facts for recursive N# fragment planning. The legacy emitter may pass these existing
// maps mechanically; N# alone decides lookup order, shadowing, and which bindings E0 can own.
class ColumnarFragmentBindings {
    public ParameterOrdinals: Dictionary<string, int>
    public ParameterTypes: Dictionary<string, Type>
    public Locals: Dictionary<string, LocalBuilder>
    public Enums: Dictionary<string, ColumnarEnumDef>
    public LiftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>
    public BoxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>
    public CurrentInstance: ColumnarCurrentInstanceFacts?
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
        LiftedLocals = new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
        BoxedCaptures = new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
        CurrentInstance = null
        this.liftedNames = liftedNames
        this.boxedNames = boxedNames
        this.enclosingNames = enclosingNames
        this.declaredCallableNames = declaredCallableNames
        this.visibleLocalCallableNames = visibleLocalCallableNames
    }

    public static func FromRawFacts(
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?,
        currentInstance: ColumnarStructDef?,
        enclosingNames: IEnumerable<string>,
        declaredCallableNames: IEnumerable<string>,
        visibleLocalCallableNames: IEnumerable<string>): ColumnarFragmentBindings {
        emptyNames := new string[](0)
        result := new ColumnarFragmentBindings(
            parameterOrdinals,
            parameterTypes,
            locals,
            enums,
            emptyNames,
            emptyNames,
            enclosingNames,
            declaredCallableNames,
            visibleLocalCallableNames)
        if liftedLocals == null {
            throw new InvalidOperationException("Lifted-local binding facts cannot be null.")
        }
        result.LiftedLocals = liftedLocals
        if boxedCaptures != null {
            result.BoxedCaptures = boxedCaptures
        }
        if currentInstance != null {
            result.CurrentInstance =
                ColumnarCurrentInstanceFacts.FromSourceDefinition(currentInstance)
        }
        return result
    }

    public func IsBlocked(name: string): bool {
        return LiftedLocals.ContainsKey(name)
            || BoxedCaptures.ContainsKey(name)
            || ContainsName(liftedNames, name)
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
            || HasCurrentInstanceValue(name)
    }

    func HasCurrentInstanceValue(name: string): bool {
        if CurrentInstance == null {
            return false
        }
        field: FieldInfo? = null
        declaringType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindField(
            CurrentInstance, name, out field, out declaringType) {
            return true
        }
        getter: MethodInfo? = null
        propertyType := typeof(object)
        return ColumnarCurrentInstanceFacts.TryFindProperty(
            CurrentInstance,
            name,
            out getter,
            out propertyType,
            out declaringType)
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
