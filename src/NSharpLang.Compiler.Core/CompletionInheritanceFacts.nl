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

    // The analyzer recorded the resolved `TypeInfo` at each written type reference. Prefer the model
    // that owns the declaration before considering a hand-built or incomplete model: spans are file
    // local, so a same-line reference in another source file is not evidence about this declaration.
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
                }
            }
        }

        for semanticModel in semanticModels {
            recorded: TypeInfo? = null
            if semanticModel.TypeReferenceTypes.TryGetValue(key, out recorded) && recorded != null && !BuiltInTypes.IsUnknown(recorded) {
                return recorded
            }
        }

        return null
    }

    static func SemanticModelOwnsDeclaration(semanticModel: SemanticModel, declarationOwner: TypeInfo): bool {
        for entry in semanticModel.Types {
            if Object.ReferenceEquals(entry.Value, declarationOwner) {
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
