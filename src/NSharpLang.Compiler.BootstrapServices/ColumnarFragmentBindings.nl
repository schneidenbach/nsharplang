namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Live raw facts for recursive N# fragment planning. The legacy emitter may pass these existing
// maps mechanically; N# alone decides lookup order, shadowing, and which bindings E0 can own.
class ColumnarFragmentBindings {
    ParameterOrdinals: Dictionary<string, int>
    ParameterTypes: Dictionary<string, Type>
    Locals: Dictionary<string, LocalBuilder>
    Enums: Dictionary<string, ColumnarEnumDef>
    LiftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>
    BoxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>
    CurrentInstance: ColumnarCurrentInstanceFacts?
    // Exact live handles for every method/type generic parameter visible to this body. Method
    // parameters are installed first; an enclosing type parameter with the same name must never
    // replace that more-local binding.
    typeParameters: Dictionary<string, Type>
    // The production emitter passes this live view. Registry aliases may expose the same
    // definition more than once, so member selection deduplicates by definition identity.
    SourceTypeDefinitions: IEnumerable<ColumnarStructDef>
    // Metadata resolution supplies an immutable exact declaration-name index so generic heads
    // and aliases do not rescan every live definition.
    ExactSourceTypes: Dictionary<string, Type>
    // Unlike CurrentInstance, this remains populated in static member bodies and anchors bare
    // static method calls on the enclosing source type.
    EnclosingTypeDefinition: ColumnarStructDef?
    // Live checked/unchecked context routed mechanically from the emitter. Only checked integral
    // add/sub/mul select the overflow opcode variants; every other family ignores this flag.
    OverflowCheckingEnabled: bool
    // Union aliases may likewise expose the same definition more than once. Type-expression
    // owners consume the live builders and deduplicate by base identity.
    SourceUnionDefinitions: IEnumerable<ColumnarUnionDef>
    // CLR ValueTuple erases element names; N# consumes the live per-binding name metadata.
    TupleNames: Dictionary<string, string[]>
    liftedNames: IEnumerable<string>
    boxedNames: IEnumerable<string>
    enclosingNames: IEnumerable<string>
    declaredCallableNames: IEnumerable<string>
    visibleLocalCallableNames: IEnumerable<string>
    // Exact plannable facts for each top-level sibling function, keyed by name. The mechanical
    // host routes these; direct-call planning consults them to own a bare sibling invocation.
    // declaredCallableNames still carries the same name set for the callable-root guards.
    SiblingCallables: Dictionary<string, ColumnarSiblingCallFacts>

    constructor(parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedNames: IEnumerable<string>, boxedNames: IEnumerable<string>, enclosingNames: IEnumerable<string>, declaredCallableNames: IEnumerable<string>, visibleLocalCallableNames: IEnumerable<string>) {
        if parameterOrdinals == null || parameterTypes == null || locals == null || enums == null || liftedNames == null || boxedNames == null || enclosingNames == null || declaredCallableNames == null || visibleLocalCallableNames == null {
            throw new InvalidOperationException("Columnar fragment binding facts cannot be null.")
        }

        ParameterOrdinals = parameterOrdinals
        ParameterTypes = parameterTypes
        Locals = locals
        Enums = enums
        LiftedLocals = new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
        BoxedCaptures = new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
        CurrentInstance = null
        typeParameters = new Dictionary<string, Type>(StringComparer.Ordinal)
        SourceTypeDefinitions = new List<ColumnarStructDef>()
        ExactSourceTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
        EnclosingTypeDefinition = null
        OverflowCheckingEnabled = false
        SourceUnionDefinitions = new List<ColumnarUnionDef>()
        TupleNames = new Dictionary<string, string[]>(StringComparer.Ordinal)
        this.liftedNames = liftedNames
        this.boxedNames = boxedNames
        this.enclosingNames = enclosingNames
        this.declaredCallableNames = declaredCallableNames
        this.visibleLocalCallableNames = visibleLocalCallableNames
        SiblingCallables = new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
    }

    // Metadata declaration passes need exact source/runtime type identity without value-flow
    // bindings. Keep that mechanical bridge narrow: only semantic type facts enter, and every
    // parameter/local/capture/callable/tuple map is created empty.
    static func CreateTypeResolutionBindings(enums: Dictionary<string, ColumnarEnumDef>, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, typeParameters: Dictionary<string, Type>): ColumnarFragmentBindings {
        if enums == null || sourceTypeDefinitions == null || sourceUnionDefinitions == null || typeParameters == null {
            throw new InvalidOperationException("Columnar type-resolution binding collections cannot be null.")
        }

        emptyNames := new string[](0)
        result := new ColumnarFragmentBindings(new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), new Dictionary<string, LocalBuilder>(StringComparer.Ordinal), enums, emptyNames, emptyNames, emptyNames, emptyNames, emptyNames)

        for pair in typeParameters {
            ValidateTypeParameter(pair.Key, pair.Value)
        }

        for pair in typeParameters {
            result.typeParameters.Add(pair.Key, pair.Value)
        }

        result.SourceTypeDefinitions = sourceTypeDefinitions
        result.SourceUnionDefinitions = sourceUnionDefinitions
        return result
    }

    static func CreateTypeResolutionBindings(enums: Dictionary<string, ColumnarEnumDef>, sourceTypeDefinitions: Dictionary<string, ColumnarStructDef>, sourceUnionDefinitions: Dictionary<string, ColumnarUnionDef>, typeParameters: Dictionary<string, Type>): ColumnarFragmentBindings {
        structs := new ColumnarStructDef[](sourceTypeDefinitions.Count)
        structIndex := 0
        for pair in sourceTypeDefinitions {
            structs[structIndex] = pair.Value
            structIndex += 1
        }
        unions := new ColumnarUnionDef[](sourceUnionDefinitions.Count)
        unionIndex := 0
        for pair in sourceUnionDefinitions {
            unions[unionIndex] = pair.Value
            unionIndex += 1
        }
        return CreateTypeResolutionBindings(enums, structs, unions, typeParameters)
    }

    // Erased source types (notably string-backed enums) cannot be distinguished by CLR Type.
    // Exact-scope consumers can probe one semantic enum definition at a time without exposing
    // or reconstructing this binding set's live type-parameter handles.
    func CreateSingleEnumTypeResolutionBindings(definition: ColumnarEnumDef): ColumnarFragmentBindings {
        if definition == null || definition.DeclaredTypeName == null || definition.DeclaredTypeName.Length == 0 {
            throw new InvalidOperationException("Exact enum-definition selection requires a declared type name.")
        }
        enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
        enums[definition.DeclaredTypeName] = definition
        copiedTypeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        for pair in typeParameters {
            copiedTypeParameters[pair.Key] = pair.Value
        }
        return CreateTypeResolutionBindings(enums, new ColumnarStructDef[](0), new ColumnarUnionDef[](0), copiedTypeParameters)
    }

    func CreateEmptySourceTypeResolutionBindings(): ColumnarFragmentBindings {
        copiedTypeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        for pair in typeParameters {
            copiedTypeParameters[pair.Key] = pair.Value
        }
        return CreateTypeResolutionBindings(new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal), new ColumnarStructDef[](0), new ColumnarUnionDef[](0), copiedTypeParameters)
    }

    static func FromRawFacts(parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, declaredCallableNames: IEnumerable<string>, visibleLocalCallableNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>): ColumnarFragmentBindings {
        emptyNames := new string[](0)
        result := new ColumnarFragmentBindings(parameterOrdinals, parameterTypes, locals, enums, emptyNames, emptyNames, enclosingNames, declaredCallableNames, visibleLocalCallableNames)

        if liftedLocals == null || sourceTypeDefinitions == null || sourceUnionDefinitions == null || tupleNames == null || typeParameters == null {
            throw new InvalidOperationException("Columnar recursive binding collections cannot be null.")
        }

        result.LiftedLocals = liftedLocals
        if boxedCaptures != null {
            result.BoxedCaptures = boxedCaptures
        }

        if currentInstance != null {
            result.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(currentInstance)
        }

        for pair in typeParameters {
            ValidateTypeParameter(pair.Key, pair.Value)
        }

        for pair in typeParameters {
            result.typeParameters.Add(pair.Key, pair.Value)
        }

        result.SourceTypeDefinitions = sourceTypeDefinitions
        result.SourceUnionDefinitions = sourceUnionDefinitions
        result.TupleNames = tupleNames
        return result
    }

    func SetEnclosingTypeDefinition(enclosingTypeDefinition: ColumnarStructDef?) {
        if enclosingTypeDefinition != null {
            enclosingTypeParameters := enclosingTypeDefinition.GenericParameters
            if enclosingTypeParameters != null {
                for pair in enclosingTypeParameters {
                    ValidateTypeParameter(pair.Key, pair.Value)
                }

                for pair in enclosingTypeParameters {
                    if !typeParameters.ContainsKey(pair.Key) {
                        typeParameters.Add(pair.Key, pair.Value)
                    }
                }
            }
        }

        EnclosingTypeDefinition = enclosingTypeDefinition
    }

    func TryGetTypeParameter(name: string, out parameterType: Type): bool {
        if name == null {
            throw new InvalidOperationException("Columnar type-parameter lookup name cannot be null.")
        }

        parameterType = typeof(object)
        return typeParameters.TryGetValue(name, out parameterType)
    }

    // The binding scope selects one semantic source declaration before this live-handle bridge
    // runs. Registry aliases may repeat that declaration, so identity deduplication is required.
    // Only the selected exact declaration name may participate; short CLR/display-name bridges
    // are not semantic identity.
    func TryResolveSelectedSourceType(exactName: string, declarationName: string, out selectedType: Type): bool {
        if exactName == null || exactName.Length == 0 || declarationName == null || declarationName.Length == 0 || Enums == null || SourceTypeDefinitions == null || SourceUnionDefinitions == null || ExactSourceTypes == null {
            throw new InvalidOperationException("Selected source-type lookup facts cannot be null or empty.")
        }

        selectedType = typeof(object)
        if ExactSourceTypes.TryGetValue(exactName, out selectedType) {
            return true
        }

        identities := new List<object>()
        types := new List<Type>()
        CollectSelectedDeclaredTypeCandidates(exactName, identities, types)

        if identities.Count != 1 {
            return false
        }

        selectedType = types[0]
        return true
    }

    func CollectSelectedDeclaredTypeCandidates(name: string, identities: List<object>, types: List<Type>) {
        for pair in Enums {
            definition := pair.Value
            if definition == null {
                throw new InvalidOperationException("Selected source enum facts cannot contain null definitions.")
            }

            if definition.DeclaredTypeName == name {
                AddDistinctSourceTypeCandidate(definition, definition.EnumType, identities, types)
            }
        }

        for definition in SourceTypeDefinitions {
            if definition == null {
                throw new InvalidOperationException("Selected source type facts cannot contain null definitions.")
            }

            if definition.DeclaredTypeName == name {
                AddDistinctSourceTypeCandidate(definition, definition.Builder, identities, types)
            }
        }

        for definition in SourceUnionDefinitions {
            if definition == null {
                throw new InvalidOperationException("Selected source union facts cannot contain null definitions.")
            }

            if definition.DeclaredTypeName == name {
                AddDistinctSourceTypeCandidate(definition, definition.Base, identities, types)
            }
        }
    }

    static func AddDistinctSourceTypeCandidate(identity: object, candidateType: Type, identities: List<object>, types: List<Type>) {
        index := 0
        while index < identities.Count {
            if Object.ReferenceEquals(identities[index], identity) {
                return
            }

            index = index + 1
        }

        identities.Add(identity)
        types.Add(candidateType)
    }

    static func ValidateTypeParameter(name: string, parameterType: Type) {
        if name == null || name.Length == 0 || parameterType == null || !parameterType.get_IsGenericParameter() || parameterType.Name != name {
            throw new InvalidOperationException("Columnar type-parameter facts must map each non-empty name to its exact generic parameter handle.")
        }
    }

    func IsBlocked(name: string): bool {
        return LiftedLocals.ContainsKey(name) || BoxedCaptures.ContainsKey(name) || ContainsName(liftedNames, name) || ContainsName(boxedNames, name) || ContainsName(enclosingNames, name)
    }

    func IsCallable(name: string): bool {
        return ContainsName(declaredCallableNames, name) || ContainsName(visibleLocalCallableNames, name)
    }

    // A visible local function stays on the legacy delegate/closure tier; direct-call planning
    // never owns it and must decline so the mechanical host can plan it.
    func IsVisibleLocalCallable(name: string): bool {
        return ContainsName(visibleLocalCallableNames, name)
    }

    // A top-level sibling function with routed plannable facts. Only these participate in the
    // direct-call planner's sibling-ownership path.
    func HasSiblingCallable(name: string): bool {
        return SiblingCallables.ContainsKey(name)
    }

    // A value binding of the same name shadows the sibling. The mechanical host's bare-call arm
    // matches exactly this set (locals, parameters, lifted locals, boxed captures) before it emits
    // a delegate invoke or reports the ambiguous method/value collision, so the direct-call planner
    // must yield the whole subtree for that legacy handling.
    func IsSiblingShadowedByValue(name: string): bool {
        return Locals.ContainsKey(name) || ParameterOrdinals.ContainsKey(name) || LiftedLocals.ContainsKey(name) || BoxedCaptures.ContainsKey(name)
    }

    func HasParameterOrdinal(ordinal: int): bool {
        for pair in ParameterOrdinals {
            if pair.Value == ordinal {
                return true
            }
        }

        return false
    }

    func IsValueBinding(name: string): bool {
        return Locals.ContainsKey(name) || ParameterOrdinals.ContainsKey(name) || ParameterTypes.ContainsKey(name) || IsBlocked(name) || HasCurrentInstanceValue(name)
    }

    func HasCurrentInstanceValue(name: string): bool {
        if CurrentInstance == null {
            return false
        }

        field: FieldInfo? = null
        declaringType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindField(CurrentInstance, name, out field, out declaringType) {
            return true
        }

        getter: MethodInfo? = null
        propertyType := typeof(object)
        return ColumnarCurrentInstanceFacts.TryFindProperty(CurrentInstance, name, out getter, out propertyType, out declaringType)
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
