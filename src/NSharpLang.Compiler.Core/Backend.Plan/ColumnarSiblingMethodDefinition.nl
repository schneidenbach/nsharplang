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

// THE CHILD LAYOUT OF THE PARSER'S kind-38 GenericCallee, read in one place.
//
// The node's children are [the callee EXPRESSION, typeArg0, typeArg1, ...]: child 0 is the kind-6
// identifier or kind-8 member access the type arguments were written on, and the rest are
// TYPE-kernel roots. Every consumer that wants a type argument goes through here, so the ordinal
// shift the callee child introduces is stated once rather than spelled at each of the dozen call
// sites.
//
// This replaced a TEXT reading of the receiver, which split the node's value span on its last dot
// and refused any spelling containing `(`, `)`, `[` or `]`. That refusal was not a shortcut: the
// receiver was not in the tree at all, so it could only be re-resolved name by name, and a chain
// carrying a call would have been EVALUATED TWICE by that re-resolution. With the receiver in the
// tree its type is read by preflight and its value emitted once, so `MakeList().OfType<string>()`
// and `services.AddSingleton<A>().AddSingleton<B>()` are ordinary receivers.
class ColumnarGenericCalleeFacts {

    // The callee expression the type arguments were written on — kind 6 (`Pick<int>(…)`) or kind 8
    // (`values.OfType<string>()`), never a type-argument root.
    static func CalleeExpressionNode(nodes: ColumnarNodeTable, callee: int): int {
        return nodes.Child(callee, 0)
    }

    // The RECEIVER of a dotted generic call: child 0 of the kind-8 callee expression. Answers -1 for
    // a bare-name callee, which has no receiver to load.
    static func ReceiverNode(nodes: ColumnarNodeTable, callee: int): int {
        calleeExpression := nodes.Child(callee, 0)
        if nodes.Kind(calleeExpression) != ColumnarExpressionNodeKind.MemberAccessExpression || nodes.ChildCount(calleeExpression) != 1 {
            return -1
        }
        return nodes.Child(calleeExpression, 0)
    }

    static func TypeArgumentCount(nodes: ColumnarNodeTable, callee: int): int {
        return nodes.ChildCount(callee) - 1
    }

    static func TypeArgumentNode(nodes: ColumnarNodeTable, callee: int, ordinal: int): int {
        return nodes.Child(callee, ordinal + 1)
    }
}
