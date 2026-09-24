namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

struct ColumnarMemberWriteChain(rootLocal: LocalBuilder?, rootParamOrdinal: int, rootType: Type, hops: List<FieldBuilder>, receiverType: Type) {
    RootLocal: LocalBuilder? = rootLocal
    RootParamOrdinal: int = rootParamOrdinal
    RootType: Type = rootType
    Hops: List<FieldBuilder> = hops
    ReceiverType: Type = receiverType
}
