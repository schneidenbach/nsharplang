namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ClosedGenericMemberSingleType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func ClosedGenericMemberRequiredOpenMethod(
    genericDefinition: Type,
    memberName: string,
    parameterCount: int
): MethodInfo {
    candidates := genericDefinition.GetMethods()
    selected: MethodInfo? = null
    count := 0
    index := 0
    while index < candidates.Length {
        candidate := candidates[index]
        if candidate != null && candidate.get_Name() == memberName && !candidate.get_IsGenericMethod() {
            parameters := candidate.GetParameters()
            if parameters.Length == parameterCount {
                selected = candidate
                count += 1
            }
        }
        index += 1
    }
    if selected == null || count != 1 {
        throw new InvalidOperationException(
            "The closed generic member fixture did not find one open method: " + memberName
        )
    }
    return selected
}

func ClosedGenericMemberFirstMethodParameter(
    method: MethodBuilder,
    parameterName: string
): Type {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(MethodBuilder),
        "DefineGenericParameters",
        parameterTypes
    )
    names := new string[](1)
    names[0] = parameterName
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    invocation := TypeOfRequiredInvocation(defineParameters, method, arguments)
    if invocation == null {
        throw new InvalidOperationException(
            "The closed generic member fixture did not define a method parameter."
        )
    }
    parameters := method.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException(
            "The closed generic member fixture did not retain one method parameter."
        )
    }
    return parameters[0]
}

func ClosedGenericMemberSubstitute(
    memberType: Type,
    closedContext: Type
): Type {
    return ColumnarClosedGenericMemberResolver.SubstituteInterfaceMemberType(
        memberType,
        closedContext
    )
}

test "closed generic member substitution keeps nongeneric and open contexts while using ordinal-only closure" {
    owner := TypeOfCreateBuilder(
        "ClosedGenericMemberOwner",
        "ColumnarClosedGenericMember.Owner",
        2
    )
    ownerType: Type = owner
    ownerParameters := owner.GetGenericArguments()
    assert ownerParameters.Length == 2

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(int)
    closedArguments[1] = typeof(string)
    closedContext := ownerType.MakeGenericType(closedArguments)

    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(ownerParameters[0], typeof(string)),
        ownerParameters[0]
    )
    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(ownerParameters[1], ownerType),
        ownerParameters[1]
    )
    assert ClosedGenericMemberSubstitute(ownerParameters[0], closedContext) == typeof(int)
    assert ClosedGenericMemberSubstitute(ownerParameters[1], closedContext) == typeof(string)

    foreignOwner := TypeOfCreateBuilder(
        "ClosedGenericMemberForeignOwner",
        "ColumnarClosedGenericMember.ForeignOwner",
        3
    )
    foreignParameters := foreignOwner.GetGenericArguments()
    assert ClosedGenericMemberSubstitute(foreignParameters[1], closedContext) == typeof(string)
    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(foreignParameters[2], closedContext),
        foreignParameters[2]
    )

    methodOwner := TypeOfCreateBuilder(
        "ClosedGenericMemberMethodOwner",
        "ColumnarClosedGenericMember.MethodOwner",
        0
    )
    method := methodOwner.DefineMethod(
        "Map",
        (MethodAttributes)22,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    methodParameter := ClosedGenericMemberFirstMethodParameter(method, "M0")
    assert methodParameter.get_IsGenericMethodParameter()
    assert ClosedGenericMemberSubstitute(methodParameter, closedContext) == typeof(int)
}

test "closed generic member substitution recurses through SZ arrays byrefs and nested generic arguments" {
    contextDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    parameters := contextDefinition.GetGenericArguments()
    closedContext := typeof(Dictionary<int, string>)

    arrayResult := ClosedGenericMemberSubstitute(
        parameters[0].MakeArrayType(),
        closedContext
    )
    assert arrayResult.get_IsSZArray()
    assert arrayResult.GetElementType() == typeof(int)

    byRefResult := ClosedGenericMemberSubstitute(
        parameters[1].MakeByRefType(),
        closedContext
    )
    assert byRefResult.get_IsByRef()
    assert byRefResult.GetElementType() == typeof(string)

    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    listArguments := new Type[](1)
    listArguments[0] = parameters[1].MakeArrayType()
    nestedList := listDefinition.MakeGenericType(listArguments)
    dictionaryDefinition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    dictionaryArguments := new Type[](2)
    dictionaryArguments[0] = parameters[0]
    dictionaryArguments[1] = nestedList
    nestedDictionary := dictionaryDefinition.MakeGenericType(dictionaryArguments)

    substituted := ClosedGenericMemberSubstitute(nestedDictionary, closedContext)
    assert substituted.GetGenericTypeDefinition() == dictionaryDefinition
    substitutedArguments := substituted.GetGenericArguments()
    assert substitutedArguments.Length == 2
    assert substitutedArguments[0] == typeof(int)
    assert substitutedArguments[1].GetGenericTypeDefinition() == listDefinition
    nestedArguments := substitutedArguments[1].GetGenericArguments()
    assert nestedArguments.Length == 1
    assert nestedArguments[0].get_IsSZArray()
    assert nestedArguments[0].GetElementType() == typeof(string)
}

test "closed generic member substitution preserves closed and unsupported reflection shapes by identity" {
    contextDefinition := typeof(List<int>).GetGenericTypeDefinition()
    closedContext := typeof(List<string>)

    fullyClosed := typeof(Dictionary<int, string>)
    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(fullyClosed, closedContext),
        fullyClosed
    )

    contextParameter := contextDefinition.GetGenericArguments()[0]
    pointer := contextParameter.MakePointerType()
    assert !pointer.get_IsSZArray()
    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(pointer, closedContext),
        pointer
    )
    assert pointer.GetElementType() == contextParameter

    rankTwo := contextParameter.MakeArrayType(2)
    assert !rankTwo.get_IsSZArray()
    assert Object.ReferenceEquals(
        ClosedGenericMemberSubstitute(rankTwo, closedContext),
        rankTwo
    )
    assert rankTwo.GetElementType() == contextParameter
}

test "closed generic member resolver rebinds runtime and builder-bound method handles" {
    runtimeDefinition := typeof(List<int>).GetGenericTypeDefinition()
    runtimeOpenAdd := ClosedGenericMemberRequiredOpenMethod(runtimeDefinition, "Add", 1)
    runtimeClosed := typeof(List<int>)
    runtimeBound := ColumnarClosedGenericMemberResolver.ResolveMethod(
        runtimeClosed,
        runtimeOpenAdd
    )
    assert runtimeBound.get_DeclaringType() == runtimeClosed
    assert runtimeBound.get_ReturnType() == ColumnarTypeOfPlanner.RequiredVoidType()
    runtimeParameters := runtimeBound.GetParameters()
    assert runtimeParameters.Length == 1
    assert runtimeParameters[0].get_ParameterType() == typeof(int)

    builderDefinition := TypeOfCreateBuilder(
        "ClosedGenericMemberBuilderOwner",
        "ColumnarClosedGenericMember.BuilderOwner",
        1
    )
    builderDefinitionType: Type = builderDefinition
    builderParameter := builderDefinition.GetGenericArguments()[0]
    builderParameters := ClosedGenericMemberSingleType(builderParameter)
    builderOpen := builderDefinition.DefineMethod(
        "Echo",
        (MethodAttributes)22,
        builderParameter,
        builderParameters
    )
    builderClosed := builderDefinitionType.MakeGenericType(
        ClosedGenericMemberSingleType(typeof(int))
    )
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(builderClosed)
    builderBound := ColumnarClosedGenericMemberResolver.ResolveMethod(
        builderClosed,
        builderOpen
    )
    // A MethodOnTypeBuilderInstantiation need not expose closed reflection signatures while its
    // owner remains unbaked. The binding's name and exact closed declaring context are the stable
    // reflection facts this shared dispatch helper must preserve.
    assert builderBound.get_Name() == "Echo"
    assert builderBound.get_DeclaringType() == builderClosed
}

test "closed generic member resolver preserves the raw incompatible runtime owner failure" {
    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    openAdd := ClosedGenericMemberRequiredOpenMethod(listDefinition, "Add", 1)
    incompatibleClosed := typeof(Dictionary<int, string>)
    assert throws ArgumentException {
        ColumnarClosedGenericMemberResolver.ResolveMethod(incompatibleClosed, openAdd)
    }
}
