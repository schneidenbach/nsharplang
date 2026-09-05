namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection

func SynthesizedRecordCallDefinition(name: string, isReference: bool): ColumnarStructDef {
    definition := SourceCallDefinition(name, isReference)
    definition.IsRecord = true
    return definition
}

test "synthesized record members publish exact ordinary source method facts" {
    referenceRecord := SynthesizedRecordCallDefinition("SynthesizedReferenceRecordFacts", true)
    referenceEquals := referenceRecord.DefineSynthesizedRecordEquals()
    referenceHash := referenceRecord.DefineSynthesizedRecordGetHashCode()

    storedEquals := referenceRecord.RecordEquals
    storedHash := referenceRecord.RecordGetHashCode
    if storedEquals == null || storedHash == null {
        throw new InvalidOperationException("Synthesized record method handles were not retained.")
    }

    referenceEqualsInfo: MethodInfo = referenceEquals
    referenceHashInfo: MethodInfo = referenceHash
    storedEqualsInfo: MethodInfo = storedEquals
    storedHashInfo: MethodInfo = storedHash
    registeredEqualsInfo: MethodInfo = referenceRecord.Methods["Equals"].Builder
    registeredHashInfo: MethodInfo = referenceRecord.Methods["GetHashCode"].Builder
    assert Object.ReferenceEquals(referenceEqualsInfo, storedEqualsInfo)
    assert Object.ReferenceEquals(referenceHashInfo, storedHashInfo)
    assert Object.ReferenceEquals(referenceEqualsInfo, registeredEqualsInfo)
    assert referenceRecord.Methods["Equals"].ParamTypes.Length == 1
    assert referenceRecord.Methods["Equals"].ParamTypes[0] == typeof(object)
    assert referenceRecord.Methods["Equals"].ReturnType == typeof(bool)
    assert Object.ReferenceEquals(referenceHashInfo, registeredHashInfo)
    assert referenceRecord.Methods["GetHashCode"].ParamTypes.Length == 0
    assert referenceRecord.Methods["GetHashCode"].ReturnType == typeof(int)
    assert referenceRecord.MethodOverloads["Equals"].Count == 1
    assert referenceRecord.MethodOverloads["GetHashCode"].Count == 1

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    noParameters := new Type[](0)
    referenceDefinitions := SourceCallDefinitions(referenceRecord)
    referenceRecordType: Type = referenceRecord.Builder
    selectedEquals := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(referenceRecordType, "Equals", oneInt, referenceDefinitions)
    selectedHash := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(referenceRecordType, "GetHashCode", noParameters, referenceDefinitions)

    assert selectedEquals.IsSelected
    assert selectedEquals.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual
    selectedEqualsMethod := selectedEquals.Method
    if selectedEqualsMethod == null {
        throw new InvalidOperationException("Synthesized reference Equals selection lost its exact handle.")
    }

    assert Object.ReferenceEquals(selectedEqualsMethod, referenceEqualsInfo)
    assert selectedEqualsMethod.get_Name() == "Equals"
    assert selectedEqualsMethod.get_DeclaringType() == referenceRecordType
    assert selectedEquals.ParameterTypes.Length == 1
    assert selectedEquals.ParameterTypes[0] == typeof(object)
    assert selectedEquals.ReturnType == typeof(bool)
    assert selectedHash.IsSelected
    assert selectedHash.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual
    selectedHashMethod := selectedHash.Method
    if selectedHashMethod == null {
        throw new InvalidOperationException("Synthesized reference GetHashCode selection lost its exact handle.")
    }

    assert Object.ReferenceEquals(selectedHashMethod, referenceHashInfo)
    assert selectedHashMethod.get_Name() == "GetHashCode"
    assert selectedHashMethod.get_DeclaringType() == referenceRecordType
    assert selectedHash.ReturnType == typeof(int)

    valueRecord := SynthesizedRecordCallDefinition("SynthesizedValueRecordFacts", false)
    valueEquals := valueRecord.DefineSynthesizedRecordEquals()
    valueHash := valueRecord.DefineSynthesizedRecordGetHashCode()
    valueEqualsInfo: MethodInfo = valueEquals
    valueHashInfo: MethodInfo = valueHash
    valueDefinitions := SourceCallDefinitions(valueRecord)
    valueRecordType: Type = valueRecord.Builder
    selectedValueEquals := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(valueRecordType, "Equals", oneInt, valueDefinitions)
    selectedValueHash := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(valueRecordType, "GetHashCode", noParameters, valueDefinitions)

    assert selectedValueEquals.IsSelected
    assert selectedValueEquals.Dispatch == ColumnarSourceDirectCallDispatch.Call
    selectedValueEqualsMethod := selectedValueEquals.Method
    if selectedValueEqualsMethod == null {
        throw new InvalidOperationException("Synthesized value Equals selection lost its exact handle.")
    }

    assert Object.ReferenceEquals(selectedValueEqualsMethod, valueEqualsInfo)
    assert selectedValueEqualsMethod.get_Name() == "Equals"
    assert selectedValueEqualsMethod.get_DeclaringType() == valueRecordType
    assert selectedValueHash.IsSelected
    assert selectedValueHash.Dispatch == ColumnarSourceDirectCallDispatch.Call
    selectedValueHashMethod := selectedValueHash.Method
    if selectedValueHashMethod == null {
        throw new InvalidOperationException("Synthesized value GetHashCode selection lost its exact handle.")
    }

    assert Object.ReferenceEquals(selectedValueHashMethod, valueHashInfo)
    assert selectedValueHashMethod.get_Name() == "GetHashCode"
    assert selectedValueHashMethod.get_DeclaringType() == valueRecordType

    assert throws InvalidOperationException {
        referenceRecord.DefineSynthesizedRecordEquals()
    }

    nonRecord := SourceCallDefinition("SynthesizedMemberNonRecord", true)
    assert throws InvalidOperationException {
        nonRecord.DefineSynthesizedRecordGetHashCode()
    }
}

test "direct-call planner lowers synthesized record dispatch boxing and value addresses" {
    referenceRecord := SynthesizedRecordCallDefinition("SynthesizedReferenceRecordPlan", true)
    referenceEquals := referenceRecord.DefineSynthesizedRecordEquals()
    _referenceHash := referenceRecord.DefineSynthesizedRecordGetHashCode()
    referenceBindings := DirectCallSingleDefinitionBindings(referenceRecord)
    referenceRecordType: Type = referenceRecord.Builder
    ColumnarRangePlannerAddParameter(referenceBindings, "receiver", 0, referenceRecordType)
    referenceTree := DirectCallInstanceTree("receiver", "Equals", DirectCallOneText("17"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    referencePlan := DirectCallPlan(referenceTree, referenceBindings)

    assert referencePlan.ResultType == typeof(bool)
    assert referencePlan.OperationCount == 4
    assert referencePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4()
    assert referencePlan.OpCodeValues[2] == ColumnarCodePlanContract.Box()
    assert referencePlan.Types[referencePlan.OperandIndices[2]] == typeof(int)
    assert referencePlan.OpCodeValues[3] == ColumnarCodePlanContract.Callvirt()
    referenceMethodIndex := referencePlan.OperandIndices[3]
    referencePlanMethod := referencePlan.Methods[referenceMethodIndex]
    referenceEqualsInfo: MethodInfo = referenceEquals
    assert Object.ReferenceEquals(referencePlanMethod, referenceEqualsInfo)
    assert referencePlan.MethodDeclaringTypes[referenceMethodIndex] == referenceRecordType
    assert referencePlan.MethodParameterTypes[referenceMethodIndex].Length == 1
    assert referencePlan.MethodParameterTypes[referenceMethodIndex][0] == typeof(object)
    assert referencePlan.MethodReturnTypes[referenceMethodIndex] == typeof(bool)

    valueRecord := SynthesizedRecordCallDefinition("SynthesizedValueRecordPlan", false)
    _valueEquals := valueRecord.DefineSynthesizedRecordEquals()
    valueHash := valueRecord.DefineSynthesizedRecordGetHashCode()
    valueBindings := DirectCallSingleDefinitionBindings(valueRecord)
    valueRecordType: Type = valueRecord.Builder
    ColumnarRangePlannerAddParameter(valueBindings, "receiver", 0, valueRecordType)
    valueTree := DirectCallInstanceTree("receiver", "GetHashCode", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    valuePlan := DirectCallPlan(valueTree, valueBindings)

    assert valuePlan.ResultType == typeof(int)
    assert valuePlan.OperationCount == 2
    assert valuePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarga()
    assert valuePlan.ArgumentOrdinals[valuePlan.OperandIndices[0]] == 0
    assert valuePlan.PlanLocalCount == 0
    assert valuePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    valueMethodIndex := valuePlan.OperandIndices[1]
    valuePlanMethod := valuePlan.Methods[valueMethodIndex]
    valueHashInfo: MethodInfo = valueHash
    assert Object.ReferenceEquals(valuePlanMethod, valueHashInfo)
    assert valuePlan.MethodDeclaringTypes[valueMethodIndex] == valueRecordType
    assert valuePlan.MethodParameterTypes[valueMethodIndex].Length == 0
    assert valuePlan.MethodReturnTypes[valueMethodIndex] == typeof(int)
}
