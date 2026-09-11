namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

class ColumnarInterpolationHolePlan {
    RootLocal: LocalBuilder?
    RootOrdinal: int
    RootThis: bool
    RootGetter: MethodInfo?
    RootType: Type?
    RootIndexLocal: LocalBuilder?
    RootIndexOrdinal: int
    RootIndexConstant: int?
    RootIndexElementType: Type?
    Hops: List<ColumnarInterpolationMemberPlan>
    CallBuilder: MethodBuilder?
    BaseCallBuilder: MethodBuilder?
    CallArgLocal: LocalBuilder?
    CallArgOrdinal: int
    CallArgType: Type?
    ValueType: Type?
    Format: string?
    CoalesceRight: ColumnarInterpolationHolePlan?
    ConstantInt: int?
    CastSourceType: Type?
    CastTargetType: Type?
    BinaryOperator: string?
    BinaryLeft: ColumnarInterpolationHolePlan?
    BinaryRight: ColumnarInterpolationHolePlan?
    ExpressionNodes: ColumnarNodeTable?
    ExpressionSource: string?
    ExpressionRoot: int

    constructor() {
        RootOrdinal = 0
        CallArgOrdinal = -1
        RootIndexOrdinal = -1
        ExpressionRoot = -1
        RootThis = false
        Hops = new List<ColumnarInterpolationMemberPlan>()
    }
}

class ColumnarInterpolationMemberPlan {
    Field: FieldInfo?
    Getter: MethodInfo?
    ValueType: Type?

    constructor(field: FieldInfo?, getter: MethodInfo?, valueType: Type) {
        Field = field
        Getter = getter
        ValueType = valueType
    }
}
