namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// The live sibling registry previously used an eight-field CLR tuple. This N# owner carries those
// same handles and arrays by reference, with no validation or projection at construction time.
class ColumnarSiblingMethodDefinition {
    Method: MethodInfo
    ParamTypes: Type[]
    ParamModifierKinds: int[]
    ReturnType: Type
    TypeParams: Type[]
    SpecialConstraints: int[]
    BaseConstraints: Type?[]
    InterfaceConstraints: Type[][]

    constructor(
        method: MethodInfo,
        paramTypes: Type[],
        paramModifierKinds: int[],
        returnType: Type,
        typeParams: Type[],
        specialConstraints: int[],
        baseConstraints: Type?[],
        interfaceConstraints: Type[][]
    ) {
        Method = method
        ParamTypes = paramTypes
        ParamModifierKinds = paramModifierKinds
        ReturnType = returnType
        TypeParams = typeParams
        SpecialConstraints = specialConstraints
        BaseConstraints = baseConstraints
        InterfaceConstraints = interfaceConstraints
    }
}

// A generic extension method's receiver is written as a dotted chain of plain names. Only that
// shape can be re-resolved name by name; a chain carrying a call or an index has already evaluated
// something the re-resolution would evaluate twice.
class ColumnarGenericExtensionReceiverChain {
    static func IsSimpleIdentifierText(text: string): bool {
        if text.Length == 0 || (!char.IsLetter(text[0]) && text[0] != '_') {
            return false
        }
        index := 1
        while index < text.Length {
            ch := text[index]
            if !char.IsLetterOrDigit(ch) && ch != '_' {
                return false
            }
            index += 1
        }
        return true
    }

    static func IsSupportedText(
        receiverChain: string,
        out names: string[]
    ): bool {
        names = System.Array.Empty<string>()
        if receiverChain.Length == 0 || receiverChain.Contains('(') || receiverChain.Contains(')') || receiverChain.Contains('[') || receiverChain.Contains(']') {
            return false
        }

        names = receiverChain.Split('.')
        if names.Length == 0 {
            return false
        }
        index := 0
        while index < names.Length {
            if !IsSimpleIdentifierText(names[index]) {
                return false
            }
            index += 1
        }
        return true
    }
}
