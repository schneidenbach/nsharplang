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
    // Whether the declaration carried `[DoesNotReturn]`. A call to it ends the path it is written
    // on, and the fact travels with the signature because a `MethodBuilder` cannot be asked for it.
    DoesNotReturn: bool
    // The `[DoesNotReturnIf(bool)]` each parameter carries, in declaration order.
    ParameterDoesNotReturnIf: int[]
    // THE PARAMETER NAMES THE DECLARATION WROTE, in declaration order. A named argument
    // (`Retry(attempts: 3)`) binds by this list, and a `MethodBuilder` cannot be asked for it before
    // its owner is baked -- the same reason every other signature fact here is carried rather than
    // reflected. Empty when the registration site had no names to carry, which simply means no call
    // on this sibling can name a parameter.
    ParamNames: string[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    // A synthesized generic local method copies its enclosing method parameters ahead of the
    // parameters written on the local declaration. Calls supply this prefix from their current
    // generic scope; inference and explicit arity apply only to the written suffix.
    EnclosingTypeParameterNames: string[]
    GenericDeclaringTypeDefinition: Type?

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
        DoesNotReturn = false
        ParameterDoesNotReturnIf = new int[](0)
        ParamNames = new string[](0)
        ParamDefaultKinds = new int[](0)
        ParamDefaultTexts = new string[](0)
        EnclosingTypeParameterNames = new string[](0)
        GenericDeclaringTypeDefinition = null
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

// ONE METHOD OF THE TYPE WHOSE BODY IS BEING EMITTED, offered as a method-group candidate. A name
// written inside a type body may resolve to that type's own method, and naming one where a delegate
// is expected makes it a method group — so the delegate builder needs the same three facts it needs
// from a top-level `func`: the handle to take the address of, the parameter types and the return
// type. Nothing else about the declaration matters to the conversion, which is why this is not the
// full sibling record: generic and modified-parameter methods are filtered out before a candidate is
// ever built, because neither has a fixed handle a delegate can be made over.
class ColumnarEnclosingMethodGroupCandidate {
    Method: MethodInfo
    ParamTypes: Type[]
    ReturnType: Type

    constructor(method: MethodInfo, paramTypes: Type[], returnType: Type) {
        Method = method
        ParamTypes = paramTypes
        ReturnType = returnType
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
