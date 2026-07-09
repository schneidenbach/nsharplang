namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

public class ColumnarInterpolationHolePlan {
    public RootLocal: LocalBuilder?
    public RootOrdinal: int
    public RootThis: bool
    public RootGetter: MethodInfo?
    public RootType: Type?
    public RootIndexLocal: LocalBuilder?
    public RootIndexOrdinal: int
    public RootIndexConstant: int?
    public RootIndexElementType: Type?
    public Hops: List<ColumnarInterpolationMemberPlan>
    public CallBuilder: MethodBuilder?
    public BaseCallBuilder: MethodBuilder?
    public CallArgLocal: LocalBuilder?
    public CallArgOrdinal: int
    public CallArgType: Type?
    public ValueType: Type?
    public Format: string?
    public CoalesceRight: ColumnarInterpolationHolePlan?
    public ConstantInt: int?
    public CastSourceType: Type?
    public CastTargetType: Type?
    public BinaryOperator: string?
    public BinaryLeft: ColumnarInterpolationHolePlan?
    public BinaryRight: ColumnarInterpolationHolePlan?
    public ExpressionNodes: ColumnarNodeTable?
    public ExpressionSource: string?
    public ExpressionRoot: int

    constructor() {
        RootOrdinal = 0
        CallArgOrdinal = -1
        RootIndexOrdinal = -1
        ExpressionRoot = -1
        RootThis = false
        Hops = new List<ColumnarInterpolationMemberPlan>()
    }
}

public class ColumnarInterpolationMemberPlan {
    public Field: FieldInfo?
    public Getter: MethodInfo?
    public ValueType: Type?

    constructor(field: FieldInfo?, getter: MethodInfo?, valueType: Type) {
        Field = field
        Getter = getter
        ValueType = valueType
    }

}
