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
        modifierValue := VisibilityModifierValue(modifiers)
        if VisibilityHasFlag(modifierValue, 1) {
            return true
        }

        if VisibilityHasFlag(modifierValue, 2) || VisibilityHasFlag(modifierValue, 8) || VisibilityHasFlag(modifierValue, 4) || VisibilityHasFlag(modifierValue, 32768) {
            return false
        }

        return IsExportedIdentifier(name)
    }

    static func HasExplicitVisibility(modifiers: object): bool {
        modifierValue := VisibilityModifierValue(modifiers)
        return VisibilityHasFlag(modifierValue, 1) || VisibilityHasFlag(modifierValue, 2) || VisibilityHasFlag(modifierValue, 8) || VisibilityHasFlag(modifierValue, 4) || VisibilityHasFlag(modifierValue, 32768)
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
