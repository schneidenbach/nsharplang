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
    // The production emitter passes this live view. Registry aliases may expose the same
    // definition more than once, so member selection deduplicates by definition identity.
    public SourceTypeDefinitions: IEnumerable<ColumnarStructDef>
    // Union aliases may likewise expose the same definition more than once. Type-expression
    // owners consume the live builders and deduplicate by base identity.
    public SourceUnionDefinitions: IEnumerable<ColumnarUnionDef>
    // CLR ValueTuple erases element names; N# consumes the live per-binding name metadata.
    public TupleNames: Dictionary<string, string[]>
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
        SourceTypeDefinitions = new List<ColumnarStructDef>()
        SourceUnionDefinitions = new List<ColumnarUnionDef>()
        TupleNames = new Dictionary<string, string[]>(StringComparer.Ordinal)
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
        sourceTypeDefinitions: IEnumerable<ColumnarStructDef>,
        sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>,
        tupleNames: Dictionary<string, string[]>,
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
        if liftedLocals == null || sourceTypeDefinitions == null
            || sourceUnionDefinitions == null || tupleNames == null {
            throw new InvalidOperationException(
                "Columnar recursive binding collections cannot be null.")
        }
        result.LiftedLocals = liftedLocals
        if boxedCaptures != null {
            result.BoxedCaptures = boxedCaptures
        }
        if currentInstance != null {
            result.CurrentInstance =
                ColumnarCurrentInstanceFacts.FromSourceDefinition(currentInstance)
        }
        result.SourceTypeDefinitions = sourceTypeDefinitions
        result.SourceUnionDefinitions = sourceUnionDefinitions
        result.TupleNames = tupleNames
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
