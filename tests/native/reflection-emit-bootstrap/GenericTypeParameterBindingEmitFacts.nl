namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection
import System.Reflection.Emit

// This is the smallest executable use of TypeBuilder.DefineGenericParameters that consumes the
// returned GenericTypeParameterBuilder[] as real CLR Type values. It keeps the declaration itself
// direct: the existing reflection helpers only create the dynamic assembly and bake the finished
// type.
class GenericTypeParameterBindingEvidence {
    Owner: Type
    ParameterCount: int
    ReturnedParameters: object
    ReturnArrayType: Type
    ReturnElementType: Type
    DeclaredReturnArrayType: Type
    DeclaredReturnElementType: Type
    TypeViews: Type[]
    FirstBuilder: object
    SecondBuilder: object
    FirstType: Type
    SecondType: Type
    FirstOwner: Type
    SecondOwner: Type
    OpenValueType: Type
    OpenValuesType: Type
    OpenOtherType: Type
    BakedDefinition: Type
    ClosedValueType: Type
    ClosedValuesType: Type
    ClosedOtherType: Type

    constructor(
        owner: Type,
        parameterCount: int,
        returnedParameters: object,
        returnArrayType: Type,
        returnElementType: Type,
        declaredReturnArrayType: Type,
        declaredReturnElementType: Type,
        typeViews: Type[],
        firstBuilder: object,
        secondBuilder: object,
        firstType: Type,
        secondType: Type,
        firstOwner: Type,
        secondOwner: Type,
        openValueType: Type,
        openValuesType: Type,
        openOtherType: Type,
        bakedDefinition: Type,
        closedValueType: Type,
        closedValuesType: Type,
        closedOtherType: Type
    ) {
        Owner = owner
        ParameterCount = parameterCount
        ReturnedParameters = returnedParameters
        ReturnArrayType = returnArrayType
        ReturnElementType = returnElementType
        DeclaredReturnArrayType = declaredReturnArrayType
        DeclaredReturnElementType = declaredReturnElementType
        TypeViews = typeViews
        FirstBuilder = firstBuilder
        SecondBuilder = secondBuilder
        FirstType = firstType
        SecondType = secondType
        FirstOwner = firstOwner
        SecondOwner = secondOwner
        OpenValueType = openValueType
        OpenValuesType = openValuesType
        OpenOtherType = openOtherType
        BakedDefinition = bakedDefinition
        ClosedValueType = closedValueType
        ClosedValuesType = closedValuesType
        ClosedOtherType = closedOtherType
    }
}

class GenericTypeParameterBindingEmitFacts {
    static func RequiredField(owner: Type, name: string): FieldInfo {
        field := owner.GetField(name)
        if field == null {
            throw new InvalidOperationException("The generic parameter fixture field '" + name + "' was not found.")
        }

        return field
    }

    // Keep the setter call direct so this fixture proves the compiler can bind and execute the exact
    // Reflection.Emit surface used when an N# `where` clause names interfaces. The baked parameter
    // then lets the test read the metadata through the ordinary Type API.
    static func EmitInterfaceConstraints(): Type[] {
        owner := LdftnContinuationEmitFacts.CreateOwner("GenericInterfaceConstraintOwner`1")
        names := new string[](1)
        names[0] = "T"
        parameters := owner.DefineGenericParameters(names)
        constraints := new Type[](2)
        constraints[0] = typeof(IComparable)
        constraints[1] = typeof(IFormattable)
        builder := parameters[0]
        builder.SetInterfaceConstraints(constraints)

        baked := LdftnContinuationEmitFacts.Bake(owner)
        bakedParameters := baked.GetGenericArguments()
        if bakedParameters.Length != 1 {
            throw new InvalidOperationException("The interface-constraint fixture did not retain one generic parameter.")
        }
        return bakedParameters[0].GetGenericParameterConstraints()
    }

    static func EmitAndConsume(): GenericTypeParameterBindingEvidence {
        owner := LdftnContinuationEmitFacts.CreateOwner("GenericTypeParameterBindingOwner`2")
        ownerType: Type = owner
        names := new string[](2)
        names[0] = "T"
        names[1] = "U"
        signature := new Type[](1)
        signature[0] = typeof(string[])
        declaration := LdftnContinuationEmitFacts.RequiredMethod(
            typeof(TypeBuilder),
            "DefineGenericParameters",
            signature
        )
        declaredReturnArrayType := declaration.get_ReturnType()
        declaredReturnElementType := declaredReturnArrayType.GetElementType()
        if declaredReturnElementType == null {
            throw new InvalidOperationException("The DefineGenericParameters API signature did not expose an array element type.")
        }

        // Keep this BCL call direct. The j1 binding must admit its exact String[] argument and
        // GenericTypeParameterBuilder[] result; reflection would not prove that compiler surface.
        parameters := owner.DefineGenericParameters(names)
        if parameters.Length != 2 {
            throw new InvalidOperationException("The generic parameter fixture did not declare two parameters.")
        }

        firstBuilder := parameters[0]
        secondBuilder := parameters[1]
        firstBuilderObject: object = firstBuilder
        secondBuilderObject: object = secondBuilder
        firstType: Type = firstBuilder
        secondType: Type = secondBuilder
        returnedParameters: object = parameters
        typeViews := new Type[](2)
        typeViews[0] = firstType
        typeViews[1] = secondType
        firstOwner := firstType.get_DeclaringType()
        secondOwner := secondType.get_DeclaringType()
        if firstOwner == null || secondOwner == null {
            throw new InvalidOperationException("A declared generic parameter did not retain its TypeBuilder owner.")
        }

        returnArrayType := returnedParameters.GetType()
        returnElementType := returnArrayType.GetElementType()
        if returnElementType == null {
            throw new InvalidOperationException("DefineGenericParameters did not return an array with an element type.")
        }

        valuesType := firstType.MakeArrayType()
        valueBuilder := owner.DefineField("Value", firstType, FieldAttributes.Public)
        valuesBuilder := owner.DefineField("Values", valuesType, FieldAttributes.Public)
        otherBuilder := owner.DefineField("Other", secondType, FieldAttributes.Public)
        valueField: FieldInfo = valueBuilder
        valuesField: FieldInfo = valuesBuilder
        otherField: FieldInfo = otherBuilder

        openValueType := valueField.get_FieldType()
        openValuesType := valuesField.get_FieldType()
        openOtherType := otherField.get_FieldType()
        bakedDefinition := LdftnContinuationEmitFacts.Bake(owner)
        closedArguments := new Type[](2)
        closedArguments[0] = typeof(int)
        closedArguments[1] = typeof(string)
        closed := bakedDefinition.MakeGenericType(closedArguments)
        closedValueType := RequiredField(closed, "Value").get_FieldType()
        closedValuesType := RequiredField(closed, "Values").get_FieldType()
        closedOtherType := RequiredField(closed, "Other").get_FieldType()

        return new GenericTypeParameterBindingEvidence(
            ownerType,
            parameters.Length,
            returnedParameters,
            returnArrayType,
            returnElementType,
            declaredReturnArrayType,
            declaredReturnElementType,
            typeViews,
            firstBuilderObject,
            secondBuilderObject,
            firstType,
            secondType,
            firstOwner,
            secondOwner,
            openValueType,
            openValuesType,
            openOtherType,
            bakedDefinition,
            closedValueType,
            closedValuesType,
            closedOtherType
        )
    }
}
