namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
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
        if candidate == null || !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
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
