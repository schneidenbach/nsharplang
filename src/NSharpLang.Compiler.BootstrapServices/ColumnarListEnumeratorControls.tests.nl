namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

func ListEnumeratorControlExactType(element: Type): Type {
    noTypes := new Type[](0)
    getEnumerator := typeof(List<ColumnarStructDef>).GetMethod(
        "GetEnumerator",
        noTypes
    )
    if getEnumerator == null {
        throw new InvalidOperationException("List<T>.GetEnumerator was not found.")
    }

    definition := getEnumerator.get_ReturnType().GetGenericTypeDefinition()
    arguments := new Type[](1)
    arguments[0] = element
    return definition.MakeGenericType(arguments)
}

func ListEnumeratorControlDefineNested(
    enclosing: TypeBuilder,
    name: string,
    genericParameterCount: int
): TypeBuilder {
    attributesType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder),
        "System.Reflection.TypeAttributes"
    )
    nestedSignature := new Type[](2)
    nestedSignature[0] = typeof(string)
    nestedSignature[1] = attributesType
    defineNested := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "DefineNestedType",
        nestedSignature
    )
    nestedArguments := new object[](2)
    ExecutorSetObject(nestedArguments, 0, name)
    ExecutorSetObject(
        nestedArguments,
        1,
        TypeOfRequiredStaticField(attributesType, "NestedPublic")
    )
    nestedValue := TypeOfRequiredInvocation(
        defineNested,
        enclosing,
        nestedArguments
    )
    nested := nestedValue as TypeBuilder
    if nested == null {
        throw new InvalidOperationException("Reflection.Emit did not return a nested TypeBuilder.")
    }

    if genericParameterCount > 0 {
        parameterSignature := new Type[](1)
        parameterSignature[0] = typeof(string[])
        defineParameters := ExecutorRequiredMethod(
            typeof(TypeBuilder),
            "DefineGenericParameters",
            parameterSignature
        )
        names := new string[](genericParameterCount)
        index := 0
        while index < names.Length {
            names[index] = "T" + index.ToString()
            index += 1
        }
        parameterArguments := new object[](1)
        ExecutorSetObject(parameterArguments, 0, names)
        TypeOfRequiredInvocation(defineParameters, nested, parameterArguments)
    }

    return nested
}

func ListEnumeratorControlForeignSameName(element: Type): Type {
    list := TypeOfCreateBuilder(
        "System.Collections.Generic.List`1",
        "ColumnarListEnumeratorControls.Foreign",
        1
    )
    enumerator := ListEnumeratorControlDefineNested(
        list,
        "Enumerator",
        1
    )
    foreignOpen := IdentityBake(enumerator)
    arguments := new Type[](1)
    arguments[0] = element
    return foreignOpen.MakeGenericType(arguments)
}

test "list enumerator admission requires the exact closed BCL nested definition" {
    exact := ListEnumeratorControlExactType(typeof(ColumnarStructDef))
    open := exact.GetGenericTypeDefinition()
    foreign := ListEnumeratorControlForeignSameName(typeof(ColumnarStructDef))
    list := typeof(List<ColumnarStructDef>)

    assert exact.get_IsGenericType()
    assert !exact.get_IsGenericTypeDefinition()
    assert exact.GetGenericArguments().Length == 1
    assert open.get_IsGenericTypeDefinition()
    foreignName := foreign.GetGenericTypeDefinition().get_FullName() ?? ""
    openName := open.get_FullName() ?? ""
    if foreignName != openName {
        throw new InvalidOperationException(
            "Foreign nested list enumerator identity shape differed: expected " + openName + "; actual " + foreignName
        )
    }
    assert !Object.ReferenceEquals(foreign.get_Assembly(), open.get_Assembly())

    assert ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(exact)
    assert ColumnarTypeOfPlanner.IsSupportedType(exact)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(open)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(list)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(foreign)
}

test "list enumerator admission retains the existing list element boundary" {
    sourceBuilder := TypeOfCreateBuilder(
        "ListEnumeratorControls.Source",
        "ColumnarListEnumeratorControls.Source",
        0
    )
    sourceEnumerator := ListEnumeratorControlExactType(sourceBuilder)
    runtimeEnumerator := ListEnumeratorControlExactType(typeof(Type))
    rankTwoEnumerator := ListEnumeratorControlExactType(
        typeof(string).MakeArrayType(2)
    )

    genericOwner := TypeOfCreateBuilder(
        "ListEnumeratorControls.Generic",
        "ColumnarListEnumeratorControls.Generic",
        1
    )
    parameters := genericOwner.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected one generic parameter.")
    }
    openEnumerator := ListEnumeratorControlExactType(parameters[0])

    sourceGenericDefinition := TypeOfCreateBuilder(
        "ListEnumeratorControls.Box`1",
        "ColumnarListEnumeratorControls.SourceGeneric",
        1
    )
    sourceGenericDefinitionType: Type = sourceGenericDefinition
    genericArguments := new Type[](1)
    genericArguments[0] = typeof(int)
    sourceGeneric := sourceGenericDefinitionType.MakeGenericType(genericArguments)
    sourceGenericEnumerator := ListEnumeratorControlExactType(sourceGeneric)

    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(sourceEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(sourceEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceEnumerator)
    assert !ColumnarTypeOfPlanner.ContainsBuilderBoundType(runtimeEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(runtimeEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(runtimeEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(rankTwoEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(openEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedListEnumeratorType(sourceGenericEnumerator)
}
