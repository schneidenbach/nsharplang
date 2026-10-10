namespace NSharpLang.Compiler

import System

class VisibilityConventions {
    static func IsExportedIdentifier(name: string?): bool {
        if name == null || name.Length == 0 {
            return false
        }

        return char.IsUpper(name[0])
    }

    static func IsExportedIdentifier(name: string?, modifiers: object): bool {
        return IsExportedIdentifierWithFlags(name, VisibilityModifierValue(modifiers))
    }

    // THE SAME RULE, TAKING THE WORD AS AN INT. Callers that already hold the modifier bits — the
    // columnar owners, which carry them in an `int` column — read this one, so the decision has one
    // owner and no caller has to box its word to ask.
    static func IsExportedIdentifierWithFlags(name: string?, modifierValue: int): bool {
        if VisibilityHasFlag(modifierValue, 1) {
            return true
        }

        if VisibilityHasFlag(modifierValue, 2) || VisibilityHasFlag(modifierValue, 8) || VisibilityHasFlag(modifierValue, 4) {
            return false
        }

        return IsExportedIdentifier(name)
    }

    static func HasExplicitVisibility(modifiers: object): bool {
        modifierValue := VisibilityModifierValue(modifiers)
        return VisibilityHasFlag(modifierValue, 1) || VisibilityHasFlag(modifierValue, 2) || VisibilityHasFlag(modifierValue, 8) || VisibilityHasFlag(modifierValue, 4)
    }

    static func VisibilityModifierValue(modifiers: object): int {
        if modifiers == null {
            return 0
        }

        return Convert.ToInt32(modifiers)
    }

    static func VisibilityHasFlag(value: int, flag: int): bool {
        return (value & flag) == flag
    }
}
