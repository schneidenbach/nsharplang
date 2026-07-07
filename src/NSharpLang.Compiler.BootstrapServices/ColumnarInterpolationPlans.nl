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
    public Hops: List<ColumnarInterpolationMemberPlan>
    public CallBuilder: MethodBuilder?
    public ValueType: Type?
    public Format: string?
    public CoalesceRight: ColumnarInterpolationHolePlan?
    public ConstantInt: int?

    constructor() {
        RootOrdinal = 0
        RootThis = false
        Hops = new List<ColumnarInterpolationMemberPlan>()
    }
}

public class ColumnarInterpolationMemberPlan {
    public Field: FieldBuilder?
    public Getter: MethodBuilder?
    public ValueType: Type?

    constructor(field: FieldBuilder?, getter: MethodBuilder?, valueType: Type) {
        Field = field
        Getter = getter
        ValueType = valueType
    }

}
