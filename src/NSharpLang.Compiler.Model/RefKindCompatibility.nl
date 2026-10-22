namespace NSharpLang.Compiler

import System.Reflection
import NSharpLang.Compiler.Ast


enum RefKindCompatibilityResult {
    Incompatible,
    Compatible,
    RefEquivalentToIn
}

// One call-site rule for source signatures, reflected signatures, planning, emission and the
// playground. `ref` may bind to `in` since C# 12, but that pair remains distinguishable so the
// analyzer can report CS9191-equivalent advice after overload selection.
class RefKindCompatibilityFacts {
    static func Classify(parameterModifier: Ast.ParameterModifier, argumentModifier: ArgumentModifier, requiresLocation: bool = false): RefKindCompatibilityResult {
        if parameterModifier == Ast.ParameterModifier.Params {
            parameterModifier = Ast.ParameterModifier.None
        }

        // `ref readonly` is a location contract rather than an `in` value contract. Both explicit
        // spellings name storage, and neither gets the `in` warning.
        if requiresLocation {
            if argumentModifier == ArgumentModifier.Ref || argumentModifier == ArgumentModifier.In {
                return RefKindCompatibilityResult.Compatible
            }
            return RefKindCompatibilityResult.Incompatible
        }

        if argumentModifier == ArgumentModifier.None {
            if parameterModifier == Ast.ParameterModifier.None || parameterModifier == Ast.ParameterModifier.In {
                return RefKindCompatibilityResult.Compatible
            }
            return RefKindCompatibilityResult.Incompatible
        }

        if argumentModifier == ArgumentModifier.In {
            return parameterModifier == Ast.ParameterModifier.In ? RefKindCompatibilityResult.Compatible : RefKindCompatibilityResult.Incompatible
        }

        if argumentModifier == ArgumentModifier.Ref {
            if parameterModifier == Ast.ParameterModifier.Ref {
                return RefKindCompatibilityResult.Compatible
            }
            if parameterModifier == Ast.ParameterModifier.In {
                return RefKindCompatibilityResult.RefEquivalentToIn
            }
            return RefKindCompatibilityResult.Incompatible
        }

        if argumentModifier == ArgumentModifier.Out {
            return parameterModifier == Ast.ParameterModifier.Out ? RefKindCompatibilityResult.Compatible : RefKindCompatibilityResult.Incompatible
        }

        return RefKindCompatibilityResult.Incompatible
    }

    static func ClassifyReflectedParameter(parameter: ParameterInfo, argumentModifier: ArgumentModifier): RefKindCompatibilityResult {
        if parameter == null {
            return RefKindCompatibilityResult.Incompatible
        }

        parameterModifier := Ast.ParameterModifier.None
        if parameter.ParameterType.IsByRef {
            if parameter.IsOut {
                parameterModifier = Ast.ParameterModifier.Out
            } else if parameter.IsIn {
                parameterModifier = Ast.ParameterModifier.In
            } else {
                parameterModifier = Ast.ParameterModifier.Ref
            }
        }

        return RefKindCompatibilityFacts.Classify(parameterModifier, argumentModifier, ReflectedParameterDirection.IsReadOnlyLocation(parameter))
    }

    static func IsApplicable(parameterModifier: Ast.ParameterModifier, argumentModifier: ArgumentModifier): bool {
        return RefKindCompatibilityFacts.Classify(parameterModifier, argumentModifier) != RefKindCompatibilityResult.Incompatible
    }

    static func ClassifyColumnarDirection(parameterModifierKind: int, argumentModifierKind: int, parameterIsByRef: bool): RefKindCompatibilityResult {
        if parameterModifierKind == 0 && parameterIsByRef {
            // A raw CLR by-ref signature with no source direction fact keeps its existing permissive
            // behavior. N# source and reflected declarations with a known direction take the exact
            // cases below; a by-value parameter passes false and rejects an explicit direction.
            return RefKindCompatibilityResult.Compatible
        }

        parameterModifier := Ast.ParameterModifier.None
        requiresLocation := parameterModifierKind == 6
        if parameterModifierKind == 1 {
            parameterModifier = Ast.ParameterModifier.Ref
        } else if parameterModifierKind == 2 {
            parameterModifier = Ast.ParameterModifier.Out
        } else if parameterModifierKind == 3 {
            parameterModifier = Ast.ParameterModifier.Params
        } else if parameterModifierKind == 5 || parameterModifierKind == 6 {
            parameterModifier = Ast.ParameterModifier.In
        }

        argumentModifier := ArgumentModifier.None
        if argumentModifierKind == 1 {
            argumentModifier = ArgumentModifier.Ref
        } else if argumentModifierKind == 2 {
            argumentModifier = ArgumentModifier.Out
        } else if argumentModifierKind == 5 {
            argumentModifier = ArgumentModifier.In
        }

        return RefKindCompatibilityFacts.Classify(parameterModifier, argumentModifier, requiresLocation)
    }
}
