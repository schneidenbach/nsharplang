namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// The ROOT of a write-receiver chain is one of three things: a LOCAL (`RootLocal`), a PARAMETER
// (`RootParamOrdinal`, when `RootLocal` is null and `RootExpression` is -1), or an EXPRESSION node
// (`RootExpression` >= 0) — an array element, a call result, or any other receiver evaluated once
// for the write. An expression root with `RootElementAddress` set is an array element of a VALUE
// type, located by address (`ldelema`) so the write lands in the array's own storage.
struct ColumnarMemberWriteChain(rootLocal: LocalBuilder?, rootParamOrdinal: int, rootType: Type, hops: List<FieldBuilder>, receiverType: Type, rootExpression: int, rootElementAddress: bool) {
    RootLocal: LocalBuilder? = rootLocal
    RootParamOrdinal: int = rootParamOrdinal
    RootType: Type = rootType
    Hops: List<FieldBuilder> = hops
    ReceiverType: Type = receiverType
    RootExpression: int = rootExpression
    RootElementAddress: bool = rootElementAddress
}
