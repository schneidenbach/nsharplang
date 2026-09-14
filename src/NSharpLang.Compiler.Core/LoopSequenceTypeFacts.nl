namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE PURE FACTS BEHIND "WHAT DOES ITERATING THIS PRODUCE" — the half of the question that needs no
// collaborator. `AnalyzerLoopSequence` owns the half that does (the scope stack, the type resolver,
// the substitution walk); everything here is a function of a CLR `Type` or of a DECLARATION.
//
// THE NAME TABLE THIS OWNER USED TO BE IS GONE. It answered `List`, `HashSet`, `Queue`, `Span`,
// `Dictionary` and eleven more by their unqualified spelling, which meant a `Stack<int>` iterated
// and a `JsonElement.ArrayEnumerator`, a `Dictionary<K,V>.KeyCollection`, a `StringBuilder.
// ChunkEnumerator` and every user type carrying the pattern did not. The rule is now the C# one and
// it is structural: ask the type for the enumerator pattern, then for `IEnumerable<T>`, then for the
// non-generic `IEnumerable` — see `ForeachPatternFacts` for why every identity test in that lookup
// is by `FullName`.
//
// THE OPEN AND CLOSED FORMS ARE ONE WALK ASKED TWICE. A CLOSED type answers with a closed element
// type. An OPEN DEFINITION — `List<>` reached through a `GenericTypeInfo`'s `GenericDefinition` —
// answers with the element type SPELLED IN ITS OWN PARAMETERS (`T`, or `KeyValuePair<TKey,TValue>`),
// which the caller then rewrites through `AnalyzerReflectionTypeOverride.ForGenericArguments`. That
// is how `Dictionary<string, Widget>` produces `KeyValuePair<string, Widget>` over a source `Widget`
// the CLR has no handle for: the substitution is by POSITION, and no name is involved.
class LoopSequenceTypeFacts {

    // The element type of a CLOSED reflected type, expressed as a CLR type, or null when the type
    // does not iterate. Arrays and `string` are NOT answered here — their lowering is an index loop
    // and only the caller knows it is emitting one.
    static func SequenceElementType(clrType: Type, requireAsync: bool): Type? {
        if clrType == null {
            return null
        }

        if requireAsync {
            asyncInterface := ForeachPatternFacts.FindAsyncSequenceInterface(clrType)
            if asyncInterface == null {
                return null
            }

            return SingleTypeArgument(asyncInterface)
        }

        pattern := ForeachPatternFacts.FindPattern(clrType)
        if pattern != null {
            return pattern.ElementType
        }

        sequenceInterface := ForeachPatternFacts.FindSequenceInterface(clrType)
        if sequenceInterface != null {
            return SingleTypeArgument(sequenceInterface)
        }

        if ForeachPatternFacts.ImplementsNonGenericSequence(clrType) {
            return typeof(object)
        }

        return null
    }

    static func SingleTypeArgument(constructed: Type): Type? {
        arguments := constructed.GetGenericArguments()
        if arguments.Length != 1 {
            return null
        }

        return arguments[0]
    }

    // THE MOST DERIVED DECLARED FUNCTION OF THIS NAME TAKING NO ARGUMENTS. Source members are flat
    // arrays on the declaration, so this is the declaration's own answer; the caller walks the base
    // chain, because only it can resolve a base reference to another declaration.
    static func FindDeclaredParameterlessFunction(members: DeclaredMemberInfo[], name: string): DeclaredMemberInfo? {
        index := 0
        while index < members.Length {
            candidate := members[index]
            if candidate.Kind == DeclaredMemberKind.Function && candidate.Name == name && !candidate.IsStatic && candidate.ParameterCount == 0 && candidate.TypeParameterCount == 0 && candidate.ReturnType != null {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    static func FindDeclaredReadableProperty(members: DeclaredMemberInfo[], name: string): DeclaredMemberInfo? {
        index := 0
        while index < members.Length {
            candidate := members[index]
            if candidate.Name == name && !candidate.IsStatic && (candidate.Kind == DeclaredMemberKind.Property || candidate.Kind == DeclaredMemberKind.Field) && candidate.Type != null {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // THE DECLARED MEMBERS OF WHATEVER SHAPE THIS IS, or an empty array when it is not a declaration.
    // Four shapes carry members and they do not share a base that exposes them, so the fan-out lives
    // here once rather than at each of the three places that asks.
    static func DeclaredMembersOf(candidate: TypeInfo): DeclaredMemberInfo[] {
        classType := candidate as ClassTypeInfo
        if classType != null {
            return classType.DeclaredMembers
        }

        structType := candidate as StructTypeInfo
        if structType != null {
            return structType.DeclaredMembers
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return recordType.DeclaredMembers
        }

        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.DeclaredMembers
        }

        return new DeclaredMemberInfo[](0)
    }

    // The interface references a declaration names, in declaration order. An interface names its
    // BASE interfaces, which is the same question asked of a shape that has no separate base class.
    static func DeclaredInterfacesOf(candidate: TypeInfo): TypeReference[] {
        classType := candidate as ClassTypeInfo
        if classType != null {
            return classType.Interfaces
        }

        structType := candidate as StructTypeInfo
        if structType != null {
            return structType.Interfaces
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return recordType.Interfaces
        }

        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.BaseInterfaces
        }

        return new TypeReference[](0)
    }

    // The base CLASS a declaration names, or null. Only a class has one; a struct, a record and an
    // interface answer null, and the walk that asks stops there.
    static func DeclaredBaseClassOf(candidate: TypeInfo): TypeReference? {
        classType := candidate as ClassTypeInfo
        if classType != null {
            return classType.BaseClass
        }

        return null
    }

    static func IsDeclaredShape(candidate: TypeInfo): bool {
        return candidate as ClassTypeInfo != null || candidate as StructTypeInfo != null || candidate as RecordTypeInfo != null || candidate as InterfaceTypeInfo != null
    }
}
