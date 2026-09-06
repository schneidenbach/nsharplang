namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System

func GenericTypeParameterBindingRequire(condition: bool, description: string) {
    if !condition {
        throw new InvalidOperationException(description)
    }
}

test "TypeBuilder declares generic parameters as Type values consumed by fields and a closed runtime type" {
    evidence := GenericTypeParameterBindingEmitFacts.EmitAndConsume()
    GenericTypeParameterBindingRequire(evidence.ParameterCount == 2, "DefineGenericParameters did not return two elements.")
    GenericTypeParameterBindingRequire(!Object.ReferenceEquals(evidence.ReturnedParameters, evidence.TypeViews), "The base Type[] view replaced the actual return array.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.ReturnedParameters.GetType(), evidence.ReturnArrayType), "The retained return array did not retain its runtime type.")
    GenericTypeParameterBindingRequire(evidence.ReturnArrayType.get_IsSZArray(), "DefineGenericParameters did not return an SZ array.")
    GenericTypeParameterBindingRequire(evidence.DeclaredReturnArrayType.get_IsSZArray(), "The DefineGenericParameters API did not declare an SZ return array.")
    GenericTypeParameterBindingRequire(evidence.DeclaredReturnElementType.get_FullName() == "System.Reflection.Emit.GenericTypeParameterBuilder", "The DefineGenericParameters API did not declare GenericTypeParameterBuilder[].")
    GenericTypeParameterBindingRequire(evidence.DeclaredReturnArrayType.IsAssignableFrom(evidence.ReturnArrayType), "The actual returned array was not assignable to the BCL return array type.")
    GenericTypeParameterBindingRequire(evidence.DeclaredReturnElementType.IsAssignableFrom(evidence.ReturnElementType), "The actual returned array element was not assignable to GenericTypeParameterBuilder.")
    GenericTypeParameterBindingRequire(evidence.FirstType.get_Name() == "T", "The first declared parameter name was not retained.")
    GenericTypeParameterBindingRequire(evidence.SecondType.get_Name() == "U", "The second declared parameter name was not retained.")
    GenericTypeParameterBindingRequire(evidence.FirstType.get_IsGenericParameter(), "The first declared parameter was not generic.")
    GenericTypeParameterBindingRequire(evidence.FirstType.get_IsGenericTypeParameter(), "The first declared parameter was not a type parameter.")
    GenericTypeParameterBindingRequire(!evidence.FirstType.get_IsGenericMethodParameter(), "The first declared parameter was incorrectly a method parameter.")
    GenericTypeParameterBindingRequire(evidence.SecondType.get_IsGenericParameter(), "The second declared parameter was not generic.")
    GenericTypeParameterBindingRequire(evidence.SecondType.get_IsGenericTypeParameter(), "The second declared parameter was not a type parameter.")
    GenericTypeParameterBindingRequire(!evidence.SecondType.get_IsGenericMethodParameter(), "The second declared parameter was incorrectly a method parameter.")
    GenericTypeParameterBindingRequire(evidence.FirstType.get_GenericParameterPosition() == 0, "The first declared parameter ordinal was not zero.")
    GenericTypeParameterBindingRequire(evidence.SecondType.get_GenericParameterPosition() == 1, "The second declared parameter ordinal was not one.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.FirstBuilder, evidence.FirstType), "The first returned element did not upcast to the same Type instance.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.SecondBuilder, evidence.SecondType), "The second returned element did not upcast to the same Type instance.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.TypeViews[0], evidence.FirstType), "The first Type[] base view did not retain its returned element.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.TypeViews[1], evidence.SecondType), "The second Type[] base view did not retain its returned element.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.FirstOwner, evidence.Owner), "The first declared parameter did not retain the TypeBuilder owner.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.SecondOwner, evidence.Owner), "The second declared parameter did not retain the TypeBuilder owner.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.OpenValueType, evidence.FirstType), "The open Value field did not consume the first parameter.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.OpenOtherType, evidence.SecondType), "The open Other field did not consume the second parameter.")
    GenericTypeParameterBindingRequire(evidence.OpenValuesType.get_IsSZArray(), "The open Values field did not consume an SZ array.")
    GenericTypeParameterBindingRequire(Object.ReferenceEquals(evidence.OpenValuesType.GetElementType(), evidence.FirstType), "The open Values field did not retain the first parameter as its element.")
    GenericTypeParameterBindingRequire(evidence.BakedDefinition.get_IsGenericTypeDefinition(), "The baked owner was not a generic type definition.")
    GenericTypeParameterBindingRequire(evidence.ClosedValueType == typeof(int), "The closed Value field did not consume Int32.")
    GenericTypeParameterBindingRequire(evidence.ClosedValuesType == typeof(int[]), "The closed Values field did not consume Int32[].")
    GenericTypeParameterBindingRequire(evidence.ClosedOtherType == typeof(string), "The closed Other field did not consume String.")
}
