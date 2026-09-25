namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// THE EXTERNAL TYPE A SOURCE RECEIVER INHERITS FROM — one walk, for every emission owner that needs
// it.
//
// A source type's `:` clause may name a type this compilation is not writing: `class Names:
// List<string>` is a `List<string>`, and every member `List<string>` declares is a member `Names`
// has. Emission sees the derived side as a `TypeBuilder` (or a `TypeBuilderInstantiation` of one),
// which answers almost no reflection question, so the owners that bind a member — the instance
// member planner, the direct-call planner, the indexer lowering, the constructor chain — each need
// the same answer: which fully baked `Type`, if any, sits at the end of this receiver's source base
// chain, expressed with THIS receiver's type arguments.
//
// THE WALK IS THE DECLARED CHAIN, NOT THE CLR ONE. `Deeper : Names : List<string>` has two source
// links before the external one, and neither has a CLR base the runtime can be asked for while the
// builders are open. Each link carries `ExactBaseType` — the base as the emitter resolved it — and
// `BaseDef` — the sibling source definition when the base is also source. `BaseDef == null` with a
// non-builder `ExactBaseType` is the terminal external base; `BaseDef == null` with no
// `ExactBaseType` is the implicit `System.Object` base, which contributes no inherited surface
// beyond what `object` itself already answers for and is reported as no answer.
//
// SUBSTITUTION IS PER LINK. A source generic's base template is written in the LINK's own type
// parameters, so the arguments the receiver carries are pushed down one link at a time; a closed
// `Box<string> : List<T>` therefore answers `List<string>` and never the open `List<T>`.
class ColumnarInheritedExternalBase {

    // The external base of one definition, given the exact receiver type the caller holds. A
    // receiver that is the bare definition carries no arguments and substitutes nothing.
    static func Resolve(definition: ColumnarStructDef?, exactReceiverType: Type?): Type? {
        return ResolveWithArguments(definition, ArgumentsOf(exactReceiverType))
    }

    // A PUBLIC STATIC FIELD OR PROPERTY OF THE EXTERNAL BASE, the member a source type inherits and a
    // bare name inside it, or `Derived.Member` outside it, reads. The member is chosen by ordinary
    // reflection on the base and must be DECLARED there or above it, so a name the base itself
    // inherits is answered by that base's own metadata rather than re-derived here. A `const` is not
    // a storage read and is left to the literal owners.
    static func TryResolveStaticMember(definition: ColumnarStructDef?, memberName: string, out field: FieldInfo?, out getter: MethodInfo?, out memberType: Type?): bool {
        field = null
        getter = null
        memberType = null
        if memberName.Length == 0 {
            return false
        }

        externalBase := Resolve(definition, null)
        if externalBase == null {
            return false
        }

        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(externalBase) {
            return TryResolveBuilderBoundStaticMember(externalBase, memberName, out field, out getter, out memberType)
        }

        staticFlags := BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy
        externalField := externalBase.GetField(memberName, staticFlags)
        if externalField != null && externalField.IsPublic && externalField.IsStatic && !externalField.IsLiteral {
            field = externalField
            memberType = externalField.FieldType
            return true
        }

        externalProperty := externalBase.GetProperty(memberName, staticFlags)
        if externalProperty == null {
            return false
        }

        externalGetter := externalProperty.GetGetMethod()
        if externalGetter == null || !externalGetter.IsPublic || !externalGetter.IsStatic || externalGetter.GetParameters().Length != 0 {
            return false
        }

        getter = externalGetter
        memberType = externalGetter.ReturnType
        return true
    }

    // THE SAME QUESTION OF A BASE CLOSED OVER A TYPE THIS COMPILATION IS WRITING. `List<Tag>`, while
    // `Tag` is being emitted, is a builder instantiation that answers no member query — `GetField` on
    // it throws — and the bindings ask this owner about EVERY bare name inside the derived type, so
    // the throw took down any bare call there (`Add(tag)` inside `class Tags: List<Tag>`). The member
    // is read off the generic DEFINITION instead and rebound onto this instantiation, exactly as a
    // value-tuple field is (`ColumnarRuntimeInstanceMemberResolver.TrySelectValueTupleField`).
    //
    // A member the definition declares binds through `TypeBuilder` with its type substituted; one it
    // inherits from a NON-generic ancestor is already closed and binds as it is. One inherited from a
    // GENERIC ancestor would need that ancestor's own instantiation, and is not answered.
    static func TryResolveBuilderBoundStaticMember(externalBase: Type, memberName: string, out field: FieldInfo?, out getter: MethodInfo?, out memberType: Type?): bool {
        field = null
        getter = null
        memberType = null
        if !externalBase.IsGenericType || externalBase.IsGenericTypeDefinition {
            return false
        }

        definitionType := externalBase.GetGenericTypeDefinition()
        closedArguments := externalBase.GetGenericArguments()
        staticFlags := BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy
        openField := definitionType.GetField(memberName, staticFlags)
        if openField != null && openField.IsPublic && openField.IsStatic && !openField.IsLiteral {
            fieldOwner := openField.DeclaringType
            if fieldOwner == definitionType {
                field = TypeBuilder.GetField(externalBase, openField)
                memberType = ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openField.FieldType, closedArguments)
                return true
            }

            if fieldOwner != null && !fieldOwner.IsGenericType {
                field = openField
                memberType = openField.FieldType
                return true
            }

            return false
        }

        openProperty := definitionType.GetProperty(memberName, staticFlags)
        if openProperty == null {
            return false
        }

        openGetter := openProperty.GetGetMethod()
        if openGetter == null || !openGetter.IsPublic || !openGetter.IsStatic || openGetter.GetParameters().Length != 0 {
            return false
        }

        getterOwner := openGetter.DeclaringType
        if getterOwner == definitionType {
            getter = TypeBuilder.GetMethod(externalBase, openGetter)
            memberType = ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(openGetter.ReturnType, closedArguments)
            return true
        }

        if getterOwner != null && !getterOwner.IsGenericType {
            getter = openGetter
            memberType = openGetter.ReturnType
            return true
        }

        return false
    }

    // The same walk driven by the receiver's type ARGUMENTS rather than by a constructed receiver
    // type, for the callers that hold the arguments alone. A source type's builder cannot always be
    // closed into a `Type` on demand, so the arguments are the portable form of the question.
    static func ResolveWithArguments(definition: ColumnarStructDef?, arguments: Type[]): Type? {
        current := definition
        currentArguments := arguments
        guard := 0
        while current != null {
            baseTemplate := current.ExactBaseType
            baseDefinition := current.BaseDef
            if baseDefinition == null {
                if baseTemplate == null || baseTemplate is TypeBuilder {
                    return null
                }

                return Substitute(baseTemplate, currentArguments)
            }

            if baseTemplate == null {
                return null
            }

            currentArguments = ArgumentsOf(Substitute(baseTemplate, currentArguments))
            current = baseDefinition
            guard = guard + 1
            if guard > 200 {
                return null
            }
        }

        return null
    }

    static func ArgumentsOf(candidate: Type?): Type[] {
        if candidate == null || !candidate.IsGenericType || candidate.IsGenericTypeDefinition {
            return Type.EmptyTypes
        }

        return candidate.GetGenericArguments()
    }

    // The same answer starting from a RECEIVER TYPE rather than from a definition: the registry is
    // scanned for the definition this builder (or this closed instantiation of one) belongs to, and
    // the receiver's own arguments drive the walk. A receiver that is not a source shape at all has
    // no source base chain and answers nothing.
    static func ResolveForReceiver(receiverType: Type?, definitions: IEnumerable<ColumnarStructDef>): Type? {
        if receiverType == null {
            return null
        }

        definition: ColumnarStructDef? = null
        if !ColumnarSourceDefinitionResolver.TryResolveStruct(receiverType, definitions, out definition) || definition == null {
            return null
        }

        return Resolve(definition, receiverType)
    }

    static func Substitute(signatureType: Type, arguments: Type[]): Type {
        if arguments.Length == 0 {
            return signatureType
        }

        return ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(signatureType, arguments)
    }
}
