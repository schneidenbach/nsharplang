namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// THE EMIT SESSION'S AMBIENT ENVIRONMENT, OWNED ONCE PER ASSEMBLY PASS.
//
// Everything a body emitter needs that is NOT about the body it is writing — the declaration
// registries, the type-resolution universe, the free-function scope, the shared lambda counter and
// display-class list, the reference paths, the repair ledger — used to be re-passed by hand at every
// construction site: thirteen `new ColumnarIlEmitter(...)` calls spelling the same fourteen
// arguments. That threading is why `ColumnarIlEmitter` has no seam in it — the emitter and the
// planners can only talk through an argument list, so neither can move without the other.
//
// This object IS the seam. It carries no body state — no locals, no `ILGenerator`, no node table —
// so one instance serves every body of an assembly pass, and the parts that legitimately vary per
// body are DERIVED rather than re-threaded: `ForSourceFile`/`ForSourceFileBody` for the file's
// sibling view, labelled return canonicals and `Program` holder slot; `WithTypeResolution` and
// `ForSynthesizedMethod`/`ForLambdaBody` for the enum/struct/union resolution triple. Every
// derivation returns a NEW context and mutates nothing, so a sub-emitter cannot disturb the
// environment its parent is still reading, and each one carries exactly what the arguments it
// replaced carried — emission is unchanged, byte for byte.
sealed class ColumnarEmitContext {
    private static readonly s_noSiblings: Dictionary<string, ColumnarSiblingMethodDefinition> = new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
    Enums: Dictionary<string, ColumnarEnumDef>
    Structs: IReadOnlyDictionary<string, ColumnarStructDef>
    Unions: IReadOnlyDictionary<string, ColumnarUnionDef>
    UnionCases: IReadOnlyDictionary<string, ColumnarUnionCaseDef>
    TypeResolutionEnums: ColumnarSemanticRegistry<ColumnarEnumDef>?
    TypeResolutionStructs: ColumnarSemanticRegistry<ColumnarStructDef>?
    TypeResolutionUnions: ColumnarSemanticRegistry<ColumnarUnionDef>?
    ReferenceAssemblyPaths: IReadOnlyList<string>?
    GenericInterfaceConstraints: IReadOnlyDictionary<Type, Type[]>?
    ModifiedMemberReferences: ColumnarModifiedMemberReferenceLedger?
    LambdaCounter: int[]?
    DisplayClasses: List<TypeBuilder>?
    // The sibling free functions this body can call by bare name, and their labelled return
    // spellings. Both are a FILE's view, so both come from `ForSourceFile`.
    Siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    SiblingReturnLabeledCanonicals: IReadOnlyDictionary<string, string>?
    // The namespace `Program` holder this file's free functions are placed on, NOT YET CREATED.
    ProgramHolder: ColumnarFreeFunctionHolderSlot?
    private freeFunctions: ColumnarFreeFunctionScope?
    private holders: ColumnarFreeFunctionHolders?

    constructor(enums: Dictionary<string, ColumnarEnumDef>, structs: IReadOnlyDictionary<string, ColumnarStructDef>, unions: IReadOnlyDictionary<string, ColumnarUnionDef>, unionCases: IReadOnlyDictionary<string, ColumnarUnionCaseDef>, freeFunctionScope: ColumnarFreeFunctionScope? = null, freeFunctionHolders: ColumnarFreeFunctionHolders? = null, lambdaCounter: int[]? = null, displayClasses: List<TypeBuilder>? = null, referenceAssemblyPaths: IReadOnlyList<string>? = null, genericInterfaceConstraints: IReadOnlyDictionary<Type, Type[]>? = null, modifiedMemberReferences: ColumnarModifiedMemberReferenceLedger? = null) {
        Enums = enums
        Structs = structs
        Unions = unions
        UnionCases = unionCases
        freeFunctions = freeFunctionScope
        holders = freeFunctionHolders
        LambdaCounter = lambdaCounter
        DisplayClasses = displayClasses
        ReferenceAssemblyPaths = referenceAssemblyPaths
        GenericInterfaceConstraints = genericInterfaceConstraints
        ModifiedMemberReferences = modifiedMemberReferences
        TypeResolutionEnums = null
        TypeResolutionStructs = null
        TypeResolutionUnions = null
        Siblings = s_noSiblings
        SiblingReturnLabeledCanonicals = null
        ProgramHolder = null
    }

    private func Copy(): ColumnarEmitContext {
        clone := new ColumnarEmitContext(Enums, Structs, Unions, UnionCases, freeFunctions, holders, LambdaCounter, DisplayClasses, ReferenceAssemblyPaths, GenericInterfaceConstraints, ModifiedMemberReferences)
        clone.TypeResolutionEnums = TypeResolutionEnums
        clone.TypeResolutionStructs = TypeResolutionStructs
        clone.TypeResolutionUnions = TypeResolutionUnions
        clone.Siblings = Siblings
        clone.SiblingReturnLabeledCanonicals = SiblingReturnLabeledCanonicals
        clone.ProgramHolder = ProgramHolder
        return clone
    }

    // THE REGISTRIES A DIFFERENT PROGRAM PASS OWNS. The member-body pass builds its own registry
    // dictionaries per job rather than reusing the program-wide ones.
    func WithRegistries(enums: Dictionary<string, ColumnarEnumDef>, structs: IReadOnlyDictionary<string, ColumnarStructDef>, unions: IReadOnlyDictionary<string, ColumnarUnionDef>, unionCases: IReadOnlyDictionary<string, ColumnarUnionCaseDef>): ColumnarEmitContext {
        clone := Copy()
        clone.Enums = enums
        clone.Structs = structs
        clone.Unions = unions
        clone.UnionCases = unionCases
        return clone
    }

    // ONE FILE ID REPLACES TWO ARGUMENTS: the file's sibling view and the `Program` holder its free
    // functions are placed on. A holder slot is allocated per derivation exactly as the hand-threaded
    // `new ColumnarFreeFunctionHolderSlot(holders, id)` was. The labelled RETURN canonicals are NOT
    // carried here — a constructor body and an inline initializer body were handed `null` for them —
    // so a body that wants them asks `ForSourceFileBody`.
    func ForSourceFile(sourceFileId: int): ColumnarEmitContext {
        clone := Copy()
        clone.SiblingReturnLabeledCanonicals = null
        if freeFunctions != null {
            clone.Siblings = freeFunctions.ViewFor(sourceFileId)
        }
        if holders != null {
            clone.ProgramHolder = new ColumnarFreeFunctionHolderSlot(holders, sourceFileId)
        }
        return clone
    }

    // ONE FILE ID REPLACES THREE ARGUMENTS — `ForSourceFile` plus the file's labelled return
    // canonicals, which a FUNCTION body reads to type a bare sibling call's tuple element names.
    func ForSourceFileBody(sourceFileId: int): ColumnarEmitContext {
        clone := ForSourceFile(sourceFileId)
        if freeFunctions != null {
            clone.SiblingReturnLabeledCanonicals = freeFunctions.ReturnLabeledCanonicalsFor(sourceFileId)
        }
        return clone
    }

    // A SIBLING VIEW WITHOUT A HOLDER. A member body calls its file's free functions but is not
    // placed on that file's `Program` holder.
    func WithSiblings(siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>, returnLabeledCanonicals: IReadOnlyDictionary<string, string>?): ColumnarEmitContext {
        clone := Copy()
        clone.Siblings = siblings
        clone.SiblingReturnLabeledCanonicals = returnLabeledCanonicals
        return clone
    }

    func WithProgramHolder(programHolder: ColumnarFreeFunctionHolderSlot?): ColumnarEmitContext {
        clone := Copy()
        clone.ProgramHolder = programHolder
        return clone
    }

    func WithTypeResolution(resolution: ColumnarSemanticTypeResolution): ColumnarEmitContext {
        clone := Copy()
        clone.TypeResolutionEnums = resolution.Enums
        clone.TypeResolutionStructs = resolution.Structs
        clone.TypeResolutionUnions = resolution.Unions
        return clone
    }

    func WithTypeResolutionRegistries(enums: ColumnarSemanticRegistry<ColumnarEnumDef>?, structs: ColumnarSemanticRegistry<ColumnarStructDef>?, unions: ColumnarSemanticRegistry<ColumnarUnionDef>?): ColumnarEmitContext {
        clone := Copy()
        clone.TypeResolutionEnums = enums
        clone.TypeResolutionStructs = structs
        clone.TypeResolutionUnions = unions
        return clone
    }

    // THE SAME UNIVERSE, RE-ANCHORED ON A SYNTHESIZED METHOD'S DECLARING BUILDER — a lambda's
    // `<Lambda>_n`, a display class's method, an iterator's `MoveNext`.
    func ForSynthesizedMethod(declaringType: TypeBuilder): ColumnarEmitContext {
        clone := Copy()
        if TypeResolutionEnums != null {
            clone.TypeResolutionEnums = TypeResolutionEnums.ForSynthesizedMethod(declaringType)
        }
        if TypeResolutionStructs != null {
            clone.TypeResolutionStructs = TypeResolutionStructs.ForSynthesizedMethod(declaringType)
        }
        if TypeResolutionUnions != null {
            clone.TypeResolutionUnions = TypeResolutionUnions.ForSynthesizedMethod(declaringType)
        }
        return clone
    }

    // A SYNTHESIZED BODY PLACED ON A LAMBDA'S OR DISPLAY CLASS'S OWN BUILDER. It sees this body's
    // sibling free functions but NOT their labelled return spellings: a lambda body's returns are
    // typed by the delegate it is being converted to, not by a sibling `func`'s written return.
    func ForLambdaBody(declaringType: TypeBuilder): ColumnarEmitContext {
        clone := ForSynthesizedMethod(declaringType)
        clone.SiblingReturnLabeledCanonicals = null
        return clone
    }

    func WithGenericInterfaceConstraints(constraints: IReadOnlyDictionary<Type, Type[]>?): ColumnarEmitContext {
        clone := Copy()
        clone.GenericInterfaceConstraints = constraints
        return clone
    }

    func WithModifiedMemberReferences(ledger: ColumnarModifiedMemberReferenceLedger?): ColumnarEmitContext {
        clone := Copy()
        clone.ModifiedMemberReferences = ledger
        return clone
    }

    func Module(): ModuleBuilder? {
        if holders == null {
            return null
        }
        return holders.Module()
    }
}
