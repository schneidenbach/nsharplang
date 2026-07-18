namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func SourceOperatorOneType(valueType: Type): Type[] {
    result := new Type[](1)
    result[0] = valueType
    return result
}

func SourceOperatorTwoTypes(leftType: Type, rightType: Type): Type[] {
    result := new Type[](2)
    result[0] = leftType
    result[1] = rightType
    return result
}

func SourceOperatorDefinitions(
    first: ColumnarStructDef,
    second: ColumnarStructDef?): ColumnarStructDef[] {
    if second == null {
        result := new ColumnarStructDef[](1)
        result[0] = first
        return result
    }
    pair := new ColumnarStructDef[](2)
    pair[0] = first
    pair[1] = second
    return pair
}

func SourceOperatorDefine(
    owner: ColumnarStructDef,
    methodName: string,
    parameterTypes: Type[],
    returnType: Type): ColumnarStaticMethodDef {
    return SourceCallDefineStatic(
        owner,
        methodName,
        parameterTypes,
        new int[](parameterTypes.Length),
        returnType,
        (MethodAttributes)2198)
}

func AssertSelectedSourceOperator(
    selection: ColumnarSourceOperatorSelection,
    owner: ColumnarStructDef,
    definition: ColumnarStaticMethodDef,
    parameterCount: int) {
    assert selection.Status == ColumnarSourceOperatorStatus.Selected
    assert selection.IsSourceType
    assert selection.IsSelected
    assert ColumnarConstructionPlanner.SameObject(
        selection.SourceDefinition, owner)
    assert ColumnarConstructionPlanner.SameObject(
        selection.OperatorDefinition, definition)
    method := selection.Method
    if method == null {
        throw new InvalidOperationException(
            "Selected source operator has no method handle.")
    }
    assert ColumnarConstructionPlanner.SameObject(method, definition.Builder)
    assert ColumnarConstructionPlanner.SameObject(
        selection.DeclaringType, owner.Builder)
    assert selection.ParameterTypes.Length == parameterCount
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        selection.ReturnType, definition.ReturnType)
}

test "source operator resolver maps every admitted unary spelling to its exact declaration" {
    symbols := new string[](4)
    symbols[0] = "+"
    symbols[1] = "-"
    symbols[2] = "!"
    symbols[3] = "~"
    methodNames := new string[](4)
    methodNames[0] = "op_UnaryPlus"
    methodNames[1] = "op_UnaryNegation"
    methodNames[2] = "op_LogicalNot"
    methodNames[3] = "op_OnesComplement"

    index := 0
    while index < symbols.Length {
        owner := SourceCallDefinition(
            "SourceUnaryOperator" + index.ToString(), true)
        definition := SourceOperatorDefine(
            owner,
            methodNames[index],
            SourceOperatorOneType(owner.Builder),
            owner.Builder)
        selection := ColumnarSourceOperatorResolver.ResolveUnary(
            symbols[index], owner.Builder, SourceOperatorDefinitions(owner, null))
        AssertSelectedSourceOperator(selection, owner, definition, 1)
        index += 1
    }
}

test "source operator resolver maps every admitted binary spelling to its exact declaration" {
    symbols := new string[](16)
    symbols[0] = "+"
    symbols[1] = "-"
    symbols[2] = "*"
    symbols[3] = "/"
    symbols[4] = "%"
    symbols[5] = "=="
    symbols[6] = "!="
    symbols[7] = "<"
    symbols[8] = "<="
    symbols[9] = ">"
    symbols[10] = ">="
    symbols[11] = "&"
    symbols[12] = "|"
    symbols[13] = "^"
    symbols[14] = "<<"
    symbols[15] = ">>"
    methodNames := new string[](16)
    methodNames[0] = "op_Addition"
    methodNames[1] = "op_Subtraction"
    methodNames[2] = "op_Multiply"
    methodNames[3] = "op_Division"
    methodNames[4] = "op_Modulus"
    methodNames[5] = "op_Equality"
    methodNames[6] = "op_Inequality"
    methodNames[7] = "op_LessThan"
    methodNames[8] = "op_LessThanOrEqual"
    methodNames[9] = "op_GreaterThan"
    methodNames[10] = "op_GreaterThanOrEqual"
    methodNames[11] = "op_BitwiseAnd"
    methodNames[12] = "op_BitwiseOr"
    methodNames[13] = "op_ExclusiveOr"
    methodNames[14] = "op_LeftShift"
    methodNames[15] = "op_RightShift"

    index := 0
    while index < symbols.Length {
        owner := SourceCallDefinition(
            "SourceBinaryOperator" + index.ToString(), true)
        definition := SourceOperatorDefine(
            owner,
            methodNames[index],
            SourceOperatorTwoTypes(owner.Builder, owner.Builder),
            owner.Builder)
        selection := ColumnarSourceOperatorResolver.ResolveBinary(
            symbols[index],
            owner.Builder,
            owner.Builder,
            SourceOperatorDefinitions(owner, null))
        AssertSelectedSourceOperator(selection, owner, definition, 2)
        index += 1
    }
}

test "source binary operator resolver searches both exact owners once and rejects ambiguity" {
    left := SourceCallDefinition("SourceOperatorLeft", true)
    right := SourceCallDefinition("SourceOperatorRight", true)
    parameterTypes := SourceOperatorTwoTypes(left.Builder, right.Builder)
    rightDefinition := SourceOperatorDefine(
        right, "op_Addition", parameterTypes, right.Builder)
    definitions := SourceOperatorDefinitions(left, right)

    rightSelected := ColumnarSourceOperatorResolver.ResolveBinary(
        "+", left.Builder, right.Builder, definitions)
    AssertSelectedSourceOperator(rightSelected, right, rightDefinition, 2)

    sameOwner := SourceCallDefinition("SourceOperatorSameOwner", true)
    sameDefinition := SourceOperatorDefine(
        sameOwner,
        "op_Addition",
        SourceOperatorTwoTypes(sameOwner.Builder, sameOwner.Builder),
        sameOwner.Builder)
    sameSelected := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        sameOwner.Builder,
        sameOwner.Builder,
        SourceOperatorDefinitions(sameOwner, null))
    AssertSelectedSourceOperator(sameSelected, sameOwner, sameDefinition, 2)

    _leftDefinition := SourceOperatorDefine(
        left, "op_Addition", parameterTypes, left.Builder)
    ambiguous := ColumnarSourceOperatorResolver.ResolveBinary(
        "+", left.Builder, right.Builder, definitions)
    assert ambiguous.Status == ColumnarSourceOperatorStatus.Rejected
    assert ambiguous.IsSourceType
    assert !ambiguous.IsSelected
}

test "source operator resolver requires exact unmodified structural operand shapes" {
    owner := SourceCallDefinition("SourceOperatorExactShape", true)
    genericBuilder := TypeOfCreateSourceBuilder(
        "SourceOperatorExactShape.Generic", true)
    genericDefinition: Type = genericBuilder
    shapeArguments := new Type[](1)
    ownerType: Type = owner.Builder
    shapeArguments[0] = ownerType
    firstShape := genericDefinition.MakeGenericType(shapeArguments)
    secondShape := genericDefinition.MakeGenericType(shapeArguments)
    assert !ColumnarConstructionPlanner.SameObject(firstShape, secondShape)
    exactDefinition := SourceOperatorDefine(
        owner,
        "op_Addition",
        SourceOperatorTwoTypes(owner.Builder, firstShape),
        owner.Builder)
    exact := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        owner.Builder,
        secondShape,
        SourceOperatorDefinitions(owner, null))
    AssertSelectedSourceOperator(exact, owner, exactDefinition, 2)

    wrongArityOwner := SourceCallDefinition(
        "SourceOperatorWrongArity", true)
    SourceOperatorDefine(
        wrongArityOwner,
        "op_Addition",
        SourceOperatorOneType(wrongArityOwner.Builder),
        wrongArityOwner.Builder)
    wrongArity := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        wrongArityOwner.Builder,
        wrongArityOwner.Builder,
        SourceOperatorDefinitions(wrongArityOwner, null))
    assert wrongArity.Status == ColumnarSourceOperatorStatus.Rejected

    wrongTypeOwner := SourceCallDefinition(
        "SourceOperatorWrongType", true)
    SourceOperatorDefine(
        wrongTypeOwner,
        "op_Addition",
        SourceOperatorTwoTypes(wrongTypeOwner.Builder, typeof(string)),
        wrongTypeOwner.Builder)
    wrongType := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        wrongTypeOwner.Builder,
        wrongTypeOwner.Builder,
        SourceOperatorDefinitions(wrongTypeOwner, null))
    assert wrongType.Status == ColumnarSourceOperatorStatus.Rejected

    modifiedOwner := SourceCallDefinition("SourceOperatorModified", true)
    modifiedTypes := SourceOperatorTwoTypes(
        modifiedOwner.Builder, modifiedOwner.Builder)
    modifiedKinds := new int[](2)
    modifiedKinds[1] = 2
    SourceCallDefineStatic(
        modifiedOwner,
        "op_Addition",
        modifiedTypes,
        modifiedKinds,
        modifiedOwner.Builder,
        (MethodAttributes)2198)
    modified := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        modifiedOwner.Builder,
        modifiedOwner.Builder,
        SourceOperatorDefinitions(modifiedOwner, null))
    assert modified.Status == ColumnarSourceOperatorStatus.Rejected
}

test "source operator resolver rejects excluded declarations and non-source operands" {
    runtimeOnly := ColumnarSourceOperatorResolver.ResolveBinary(
        "+", typeof(int), typeof(int), new ColumnarStructDef[](0))
    assert runtimeOnly.Status == ColumnarSourceOperatorStatus.NotSourceType
    assert !runtimeOnly.IsSourceType

    owner := SourceCallDefinition("SourceOperatorUnsupported", true)
    unsupported := ColumnarSourceOperatorResolver.ResolveUnary(
        "++", owner.Builder, SourceOperatorDefinitions(owner, null))
    assert unsupported.Status == ColumnarSourceOperatorStatus.Rejected

    privateOwner := SourceCallDefinition("SourceOperatorPrivate", true)
    privateTypes := SourceOperatorTwoTypes(
        privateOwner.Builder, privateOwner.Builder)
    SourceCallDefineStatic(
        privateOwner,
        "op_Addition",
        privateTypes,
        new int[](2),
        privateOwner.Builder,
        (MethodAttributes)2193)
    privateSelection := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        privateOwner.Builder,
        privateOwner.Builder,
        SourceOperatorDefinitions(privateOwner, null))
    assert privateSelection.Status == ColumnarSourceOperatorStatus.Rejected

    ordinaryOwner := SourceCallDefinition("SourceOperatorOrdinary", true)
    ordinaryTypes := SourceOperatorTwoTypes(
        ordinaryOwner.Builder, ordinaryOwner.Builder)
    SourceCallDefineStatic(
        ordinaryOwner,
        "op_Addition",
        ordinaryTypes,
        new int[](2),
        ordinaryOwner.Builder,
        (MethodAttributes)150)
    ordinarySelection := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        ordinaryOwner.Builder,
        ordinaryOwner.Builder,
        SourceOperatorDefinitions(ordinaryOwner, null))
    assert ordinarySelection.Status == ColumnarSourceOperatorStatus.Rejected

    genericOwner := SourceCallDefinition("SourceOperatorGeneric", true)
    genericDefinition := SourceOperatorDefine(
        genericOwner,
        "op_Addition",
        SourceOperatorTwoTypes(genericOwner.Builder, genericOwner.Builder),
        genericOwner.Builder)
    SourceCallMakeGeneric(genericDefinition.Builder)
    genericSelection := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        genericOwner.Builder,
        genericOwner.Builder,
        SourceOperatorDefinitions(genericOwner, null))
    assert genericSelection.Status == ColumnarSourceOperatorStatus.Rejected

    closedOwner := SourceCallGenericDefinition("SourceOperatorClosed")
    closedDefinition: Type = closedOwner.Builder
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closedType := closedDefinition.MakeGenericType(closedArguments)
    closedSelection := ColumnarSourceOperatorResolver.ResolveUnary(
        "-", closedType, SourceOperatorDefinitions(closedOwner, null))
    assert closedSelection.Status == ColumnarSourceOperatorStatus.NotSourceType
}

test "source operator resolver deduplicates repeated facts and rejects corrupted ownership" {
    owner := SourceCallDefinition("SourceOperatorRepeated", true)
    definition := SourceOperatorDefine(
        owner,
        "op_Addition",
        SourceOperatorTwoTypes(owner.Builder, owner.Builder),
        owner.Builder)
    SourceCallAddStaticFact(owner, "op_Addition", definition)
    repeated := ColumnarSourceOperatorResolver.ResolveBinary(
        "+",
        owner.Builder,
        owner.Builder,
        SourceOperatorDefinitions(owner, null))
    AssertSelectedSourceOperator(repeated, owner, definition, 2)

    mappedOwner := SourceCallDefinition("SourceOperatorMappedOwner", true)
    foreignOwner := SourceCallDefinition("SourceOperatorForeignOwner", true)
    foreignDefinition := SourceOperatorDefine(
        foreignOwner,
        "op_Addition",
        SourceOperatorTwoTypes(mappedOwner.Builder, mappedOwner.Builder),
        mappedOwner.Builder)
    SourceCallAddStaticFact(mappedOwner, "op_Addition", foreignDefinition)
    assert throws InvalidOperationException {
        ColumnarSourceOperatorResolver.ResolveBinary(
            "+",
            mappedOwner.Builder,
            mappedOwner.Builder,
            SourceOperatorDefinitions(mappedOwner, null))
    }
}
