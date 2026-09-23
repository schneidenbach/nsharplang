namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE SEMANTIC SHAPE OF A SOURCE TYPE AS A COMPLETION WALKS ITS INHERITANCE SURFACE.
//
// A completion receives an already-resolved `TypeInfo`, not the analyzer's declaration context. A
// constructed source type therefore has to carry two facts together while the walk follows its base
// and interface references: the declaration that WROTE those references, and the exact closed
// arguments with which the receiver reached that declaration. This owner keeps those facts together
// so the completion walker never falls back to a display-name lookup for either one.
class CompletionInheritanceFacts {

    // The source declaration a type instance names, plus the positional type-parameter binding its
    // constructed form induces. A non-generic declaration needs no binding. An external generic
    // deliberately answers false: reflection owns its inheritance surface.
    static func TryGetSourceDeclaration(typeInfo: TypeInfo, out declaration: TypeInfo?, out substitution: Dictionary<string, TypeInfo>?): bool {
        declaration = null
        substitution = null

        if CompletionDeclarationFacts.DeclaredMembersOfType(typeInfo) != null {
            declaration = typeInfo
            return true
        }

        generic := typeInfo as GenericTypeInfo
        if generic == null || generic.GenericDefinition == null || CompletionDeclarationFacts.DeclaredMembersOfType(generic.GenericDefinition) == null {
            return false
        }

        declaration = generic.GenericDefinition
        parameters := DeclaredTypeParameters(generic.GenericDefinition)
        arguments := generic.TypeArguments
        bindings := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        index := 0
        while index < parameters.Length && index < arguments.Count {
            bindings[parameters[index].Name] = arguments[index]
            index = index + 1
        }

        substitution = bindings
        return true
    }

    // The type parameters on the four declaration shapes that may contribute completion members.
    // They are read in declaration order, which is the generic instantiation's positional contract.
    static func DeclaredTypeParameters(declaration: TypeInfo): TypeParameter[] {
        classType := declaration as ClassTypeInfo
        if classType != null {
            return classType.TypeParameters
        }

        structType := declaration as StructTypeInfo
        if structType != null {
            return structType.TypeParameters
        }

        recordType := declaration as RecordTypeInfo
        if recordType != null {
            return recordType.TypeParameters
        }

        interfaceType := declaration as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.TypeParameters
        }

        return new TypeParameter[](0)
    }

    // The analyzer recorded the resolved `TypeInfo` at each written type reference. A declaration
    // owner makes this a file-local lookup: if that model has no usable record, a same-position
    // record from another file is not evidence and cannot answer. The ownerless overload has no
    // file identity, so it accepts a record only when every usable same-position record agrees on
    // its exact semantic type.
    static func RecordedTypeReferenceType(typeReference: TypeReference, semanticModels: IEnumerable<SemanticModel>, declarationOwner: TypeInfo?): TypeInfo? {
        span := TypeReferenceFacts.GetStartSpan(typeReference)
        if !span.IsValid {
            return null
        }

        key := (Line: span.StartLine, Column: span.StartColumn)
        if declarationOwner != null {
            for semanticModel in semanticModels {
                if SemanticModelOwnsDeclaration(semanticModel, declarationOwner) {
                    recorded: TypeInfo? = null
                    if semanticModel.TypeReferenceTypes.TryGetValue(key, out recorded) && recorded != null && !BuiltInTypes.IsUnknown(recorded) {
                        return recorded
                    }

                    return null
                }
            }

            return null
        }

        candidate: TypeInfo? = null
        for semanticModel in semanticModels {
            recorded: TypeInfo? = null
            if semanticModel.TypeReferenceTypes.TryGetValue(key, out recorded) && recorded != null && !BuiltInTypes.IsUnknown(recorded) {
                if candidate != null && !TypeInfoIdentityFacts.AreEqual(candidate, recorded) {
                    return null
                }

                candidate = recorded
            }
        }

        return candidate
    }

    static func SemanticModelOwnsDeclaration(semanticModel: SemanticModel, declarationOwner: TypeInfo): bool {
        seen := new List<TypeInfo>()
        for entry in semanticModel.Types {
            if TypeTreeContainsDeclaration(entry.Value, declarationOwner, seen) {
                return true
            }
        }

        // `Types` is keyed by written name, so a non-generic sibling owns the shared bare-name
        // slot. Its generic sibling remains reachable only through the identity table, which must
        // participate in the same nested-declaration ownership walk.
        for entry in semanticModel.TypesByIdentity {
            if TypeTreeContainsDeclaration(entry.Value, declarationOwner, seen) {
                return true
            }
        }

        return false
    }

    // A file model records its outer declarations. Nested declarations remain below those roots in
    // `NestedTypeInfo`, so reference identity must walk that source-declaration tree before saying
    // a model does not own a nested type.
    static func TypeTreeContainsDeclaration(candidate: TypeInfo, declarationOwner: TypeInfo, seen: List<TypeInfo>): bool {
        if Object.ReferenceEquals(candidate, declarationOwner) {
            return true
        }

        index := 0
        while index < seen.Count {
            if Object.ReferenceEquals(seen[index], candidate) {
                return false
            }

            index = index + 1
        }
        seen.Add(candidate)

        nestedTypes: NestedTypeInfo[]? = null
        classType := candidate as ClassTypeInfo
        if classType != null {
            nestedTypes = classType.NestedTypes
        }
        structType := candidate as StructTypeInfo
        if structType != null {
            nestedTypes = structType.NestedTypes
        }
        recordType := candidate as RecordTypeInfo
        if recordType != null {
            nestedTypes = recordType.NestedTypes
        }
        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType != null {
            nestedTypes = interfaceType.NestedTypes
        }

        if nestedTypes == null {
            return false
        }

        for nestedType in nestedTypes {
            if TypeTreeContainsDeclaration(nestedType.Type, declarationOwner, seen) {
                return true
            }
        }

        return false
    }

    // Rewrite a resolved type under the receiver's positional generic binding. This is semantic
    // substitution: a source declaration handle stays attached to a constructed generic, and only
    // the argument positions change. It is intentionally not a display-text replacement.
    static func ApplySubstitution(typeInfo: TypeInfo, substitution: Dictionary<string, TypeInfo>?): TypeInfo {
        if substitution == null || substitution.Count == 0 {
            return typeInfo
        }

        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            replacement: TypeInfo? = null
            if substitution.TryGetValue(simple.Name, out replacement) && replacement != null {
                return replacement
            }

            return typeInfo
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            arguments := new List<TypeInfo>()
            index := 0
            while index < generic.TypeArguments.Count {
                arguments.Add(ApplySubstitution(generic.TypeArguments[index], substitution))
                index = index + 1
            }

            return new GenericTypeInfo(generic.Name, arguments, generic.GenericDefinition)
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            return new ArrayTypeInfo(ApplySubstitution(array.ElementType, substitution))
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return new NullableTypeInfo(ApplySubstitution(nullable.InnerType, substitution))
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return new ObliviousTypeInfo(ApplySubstitution(oblivious.InnerType, substitution))
        }

        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            return new ByRefTypeInfo(ApplySubstitution(byRef.InnerType, substitution), byRef.IsOutArgument)
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            elements := new List<TupleTypeElementInfo>()
            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                element := tuple.Elements[elementIndex]
                elements.Add(new TupleTypeElementInfo(element.Name, ApplySubstitution(element.Type, substitution)))
                elementIndex = elementIndex + 1
            }

            return new TupleTypeInfo(elements)
        }

        function := typeInfo as FunctionTypeInfo
        if function != null {
            parameterTypes := function.ParameterTypes
            substitutedParameters: List<TypeInfo>? = null
            if parameterTypes != null {
                substitutedParameters = new List<TypeInfo>()
                parameterIndex := 0
                while parameterIndex < parameterTypes.Count {
                    substitutedParameters.Add(ApplySubstitution(parameterTypes[parameterIndex], substitution))
                    parameterIndex = parameterIndex + 1
                }
            }

            returnType := function.ReturnType
            substitutedReturn: TypeInfo? = null
            if returnType != null {
                substitutedReturn = ApplySubstitution(returnType, substitution)
            }

            return function.WithSignatureTypes(substitutedParameters, substitutedReturn)
        }

        return typeInfo
    }

    // A closure is a graph, not a base-class line. TypeInfoIdentityFacts keeps the exact generic
    // definition and every closed argument in the identity, so `IValue<int>` and `IValue<string>`
    // are distinct while the same node reached through a diamond is visited once.
    static func ContainsExactType(seen: List<TypeInfo>, candidate: TypeInfo): bool {
        index := 0
        while index < seen.Count {
            if TypeInfoIdentityFacts.AreEqual(seen[index], candidate) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func MemberMatchesFilter(item: CompletionItem, filter: CompletionMemberFilter): bool {
        if filter == CompletionMemberFilter.StaticOnly {
            return item.IsStatic
        }

        if filter == CompletionMemberFilter.InstanceOnly {
            return !item.IsStatic
        }

        return true
    }
}
