namespace NSharpLang.Compiler


// THE FLAT `where` ROWS, FOLDED INTO THE TWO COLUMNS THE EMITTER READS.
//
// Both parsers answer the same flat shape — one row per constraint ITEM, carrying the owner
// type-parameter's name and either a special sentinel (-2 `class`, -3 `struct`, -4 `new()`) or a
// constraint type's canonical text. The emitter wants the transpose: one special-flag word PER TYPE
// PARAMETER, and one array of type texts per type parameter. That fold is this file, so the host
// builder does not carry it three more times — once per declaration keyword.
//
// The special flags are `SpecialConstraintKind`'s own bits (Class 1, Struct 2, New 4), which is what
// `ColumnarFunctionInput.TypeParamSpecialConstraints` has always held.
class ColumnarConstraintColumns {
    static func ClassFlag(): int {
        return 1
    }

    static func StructFlag(): int {
        return 2
    }

    static func NewFlag(): int {
        return 4
    }

    // A row whose owner names no declared type parameter is DROPPED rather than refused: the parser
    // does not compare source text, so an owner that matches nothing is a source error the analyzer
    // reports with a position. Emitting a constraint against a parameter that does not exist would be
    // the worse answer.
    static func OwnerIndex(typeParamNames: string[], owner: string): int {
        i := 0
        while i < typeParamNames.Length {
            if typeParamNames[i] == owner {
                return i
            }

            i = i + 1
        }

        return -1
    }

    static func BuildSpecials(ownerTexts: string[], itemCodes: int[], typeParamNames: string[], rowCount: int): int[] {
        specials := new int[](typeParamNames.Length)
        row := 0
        while row < rowCount {
            owner := OwnerIndex(typeParamNames, ownerTexts[row])
            if owner >= 0 {
                code := itemCodes[row]
                if code == -2 {
                    specials[owner] = specials[owner] | ClassFlag()
                } else if code == -3 {
                    specials[owner] = specials[owner] | StructFlag()
                } else if code == -4 {
                    specials[owner] = specials[owner] | NewFlag()
                }
            }

            row = row + 1
        }

        return specials
    }

    static func BuildTypeConstraints(ownerTexts: string[], itemCodes: int[], typeTexts: string[], typeParamNames: string[], rowCount: int): string[][] {
        counts := new int[](typeParamNames.Length)
        row := 0
        while row < rowCount {
            if itemCodes[row] == 0 {
                owner := OwnerIndex(typeParamNames, ownerTexts[row])
                if owner >= 0 {
                    counts[owner] = counts[owner] + 1
                }
            }

            row = row + 1
        }

        result := new string[][](typeParamNames.Length)
        t := 0
        while t < typeParamNames.Length {
            result[t] = new string[](counts[t])
            counts[t] = 0
            t = t + 1
        }

        row = 0
        while row < rowCount {
            if itemCodes[row] == 0 {
                owner := OwnerIndex(typeParamNames, ownerTexts[row])
                if owner >= 0 {
                    slot := counts[owner]
                    result[owner][slot] = typeTexts[row]
                    counts[owner] = slot + 1
                }
            }

            row = row + 1
        }

        return result
    }

    // The flat out-arrays every declaration ABI writes are sized to the token count; the input wants an
    // exactly-sized copy. Three C# call sites open-coded the same loop, once per declaration keyword.
    static func TrimTexts(texts: string[], count: int): string[] {
        trimmed := new string[](count)
        i := 0
        while i < count {
            trimmed[i] = texts[i]
            i = i + 1
        }

        return trimmed
    }

    // The two defaulting helpers the inputs call, so an unconstrained declaration allocates the same
    // empty shape a function's does rather than a null the emitter has to test for.
    static func SpecialsOrEmpty(specials: int[]?, typeParamCount: int): int[] {
        if specials != null {
            return specials
        }

        return new int[](typeParamCount)
    }

    static func TypesOrEmpty(types: string[][]?, typeParamCount: int): string[][] {
        if types != null {
            return types
        }

        empty := new string[][](typeParamCount)
        t := 0
        while t < typeParamCount {
            empty[t] = new string[](0)
            t = t + 1
        }

        return empty
    }
}
