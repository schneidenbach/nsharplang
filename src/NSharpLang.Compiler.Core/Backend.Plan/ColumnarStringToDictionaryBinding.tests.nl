namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

func StringToDictionaryTypeArguments(): string[] {
    values := new string[](3)
    values[0] = "System.String"
    values[1] = "System.String"
    values[2] = "System.String"
    return values
}

func StringToDictionaryArgumentNames(): string[] {
    values := new string[](4)
    values[0] = typeof(IEnumerable<string>).get_FullName() ?? ""
    values[1] = typeof(Func<string, string>).get_FullName() ?? ""
    values[2] = typeof(Func<string, string>).get_FullName() ?? ""
    values[3] = typeof(StringComparer).get_FullName() ?? ""
    return values
}

func StringToDictionaryEnumerableType(): Type {
    result := Type.GetType("System.Linq.Enumerable, System.Linq")
    if result == null {
        throw new InvalidOperationException("System.Linq.Enumerable was not found.")
    }

    return result
}

func StringToDictionaryBindingPlan(): ColumnarExternalCallPlan {
    return ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan(
        "Enumerable",
        "ToDictionary",
        StringToDictionaryTypeArguments(),
        StringToDictionaryArgumentNames()
    )
}

test "explicit generic static binding pins String ToDictionary with StringComparer conversion" {
    plan := StringToDictionaryBindingPlan()
    enumerableType := StringToDictionaryEnumerableType()

    assert plan.IsSupported, "String ToDictionary catalog row must own the exact source shape."
    assert plan.Kind == ColumnarExternalCallKind.Call, "String ToDictionary must be a direct static call."
    assert plan.DeclaringTypeName == "System.Linq.Enumerable, System.Linq", "String ToDictionary declaring identity must name System.Linq.Enumerable."
    assert plan.MemberName == "ToDictionary", "String ToDictionary member name must be exact."
    assert plan.TypeArgumentNames.Length == 3, "String ToDictionary requires three pinned generic arguments."
    assert plan.TypeArgumentNames[0] == "System.String, System.Private.CoreLib", "String ToDictionary TSource identity must use the catalog core-library spelling."
    assert plan.TypeArgumentNames[1] == "System.String, System.Private.CoreLib", "String ToDictionary TKey identity must use the catalog core-library spelling."
    assert plan.TypeArgumentNames[2] == "System.String, System.Private.CoreLib", "String ToDictionary TElement identity must use the catalog core-library spelling."
    assert plan.ParameterTypeNames.Length == 4, "String ToDictionary requires the four-argument overload."
    assert plan.ParameterTypeNames[0] == typeof(IEnumerable<string>).get_AssemblyQualifiedName(), "source parameter identity: actual=" + plan.ParameterTypeNames[0] + "; expected=" + (typeof(IEnumerable<string>).get_AssemblyQualifiedName() ?? "<none>")
    assert plan.ParameterTypeNames[1] == typeof(Func<string, string>).get_AssemblyQualifiedName(), "key selector identity: actual=" + plan.ParameterTypeNames[1] + "; expected=" + (typeof(Func<string, string>).get_AssemblyQualifiedName() ?? "<none>")
    assert plan.ParameterTypeNames[2] == typeof(Func<string, string>).get_AssemblyQualifiedName(), "value selector identity: actual=" + plan.ParameterTypeNames[2] + "; expected=" + (typeof(Func<string, string>).get_AssemblyQualifiedName() ?? "<none>")
    assert plan.ParameterTypeNames[3] == typeof(IEqualityComparer<string>).get_AssemblyQualifiedName(), "String ToDictionary comparer parameter must be IEqualityComparer<string>."
    assert plan.ReturnTypeName == typeof(Dictionary<string, string>).get_AssemblyQualifiedName(), "String ToDictionary return type must be Dictionary<string,string>."

    selection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(plan, enumerableType, true, out selection), "String ToDictionary plan must close one exact CLR generic method."
    method := selection.Method
    assert method != null, "String ToDictionary runtime selection must carry a method."
    assert method.get_IsStatic(), "String ToDictionary selected method must be static."
    assert method.get_IsGenericMethod(), "String ToDictionary selected method must be generic."
    assert !method.get_IsGenericMethodDefinition(), "String ToDictionary selected method must be closed."
    methodTypeArguments := method.GetGenericArguments()
    assert methodTypeArguments.Length == 3, "String ToDictionary selected method must have three type arguments."
    assert methodTypeArguments[0] == typeof(string), "String ToDictionary TSource must be string."
    assert methodTypeArguments[1] == typeof(string), "String ToDictionary TKey must be string."
    assert methodTypeArguments[2] == typeof(string), "String ToDictionary TElement must be string."
    assert selection.ParameterTypes.Length == 4, "String ToDictionary selection must retain four parameters."
    assert selection.ParameterTypes[0] == typeof(IEnumerable<string>), "String ToDictionary source parameter runtime type must be exact."
    assert selection.ParameterTypes[1] == typeof(Func<string, string>), "String ToDictionary key selector runtime type must be exact."
    assert selection.ParameterTypes[2] == typeof(Func<string, string>), "String ToDictionary value selector runtime type must be exact."
    assert selection.ParameterTypes[3] == typeof(IEqualityComparer<string>), "String ToDictionary comparer runtime type must be exact."
    assert selection.ReturnType == typeof(Dictionary<string, string>), "String ToDictionary runtime return type must be exact."
}

test "String ToDictionary explicit binding declines every noncanonical input shape" {
    arguments := StringToDictionaryArgumentNames()
    wrongTypeArguments := new string[](3)
    wrongTypeArguments[0] = "System.String"
    wrongTypeArguments[1] = "System.String"
    wrongTypeArguments[2] = "System.Int32"
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Enumerable", "ToDictionary", wrongTypeArguments, arguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Enumerable", "ToDictionary", StringToDictionaryTypeArguments(), new string[](3)).IsSupported
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Enumerable", "ToLookup", StringToDictionaryTypeArguments(), arguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("OtherEnumerable", "ToDictionary", StringToDictionaryTypeArguments(), arguments).IsSupported

    mismatchedComparerArguments := StringToDictionaryArgumentNames()
    mismatchedComparerArguments[3] = typeof(IEqualityComparer<string>).get_FullName() ?? ""
    assert !ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan("Enumerable", "ToDictionary", StringToDictionaryTypeArguments(), mismatchedComparerArguments).IsSupported
}

test "direct call planner selects String ToDictionary and converts StringComparer to its comparer parameter" {
    tree := DirectCallParsedTree("Enumerable.ToDictionary<string, string, string>(source, keySelector, valueSelector, StringComparer.OrdinalIgnoreCase)")
    ExternalStampScope(tree, "import System\nimport System.Collections.Generic\nimport System.Linq\n")

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "source", 0, typeof(IEnumerable<string>))
    ColumnarRangePlannerAddParameter(bindings, "keySelector", 1, typeof(Func<string, string>))
    ColumnarRangePlannerAddParameter(bindings, "valueSelector", 2, typeof(Func<string, string>))
    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(Dictionary<string, string>)
    assert plan.MethodCount >= 2
    callIndex := plan.MethodCount - 1
    assert plan.Methods[callIndex].get_Name() == "ToDictionary"
    assert plan.MethodDeclaringTypes[callIndex] == StringToDictionaryEnumerableType()
    assert plan.MethodIsStatic[callIndex]
    assert plan.MethodParameterTypes[callIndex].Length == 4
    assert plan.MethodParameterTypes[callIndex][0] == typeof(IEnumerable<string>)
    assert plan.MethodParameterTypes[callIndex][1] == typeof(Func<string, string>)
    assert plan.MethodParameterTypes[callIndex][2] == typeof(Func<string, string>)
    assert plan.MethodParameterTypes[callIndex][3] == typeof(IEqualityComparer<string>)
    assert plan.MethodReturnTypes[callIndex] == typeof(Dictionary<string, string>)
}

test "external static-member binding resolves ReferenceEqualityComparer Instance exactly" {
    runtimeType := Type.GetType("System.Collections.Generic.ReferenceEqualityComparer, System.Private.CoreLib")
    if runtimeType == null {
        throw new InvalidOperationException("System.Collections.Generic.ReferenceEqualityComparer was not found.")
    }

    catalogPlan := ColumnarExternalBindingPlans.GetStaticMemberPlan("ReferenceEqualityComparer", "Instance")
    assert catalogPlan.IsSupported, "ReferenceEqualityComparer.Instance catalog row must be supported."
    assert catalogPlan.Kind == ColumnarExternalStaticMemberKind.Property, "ReferenceEqualityComparer.Instance must bind as a property."
    assert catalogPlan.DeclaringTypeName == "System.Collections.Generic.ReferenceEqualityComparer, System.Private.CoreLib", "ReferenceEqualityComparer.Instance declaring identity must be exact."
    assert catalogPlan.ValueTypeName == "System.Collections.Generic.ReferenceEqualityComparer, System.Private.CoreLib", "ReferenceEqualityComparer.Instance value identity must be exact."

    tree := ExternalStaticMemberTree("ReferenceEqualityComparer", "Instance")
    ExternalStampScope(tree, "import System.Collections.Generic\n")
    plan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
    assert plan.ResultType == runtimeType, "ReferenceEqualityComparer.Instance planner result must preserve its concrete runtime type."
    assert plan.MethodCount == 1, "ReferenceEqualityComparer.Instance plan must contain one getter call."
    assert plan.Fields.Length == 0
    assert plan.Methods[0].get_Name() == "get_Instance", "ReferenceEqualityComparer.Instance must emit its getter."
    assert plan.Methods[0].get_DeclaringType() == runtimeType, "ReferenceEqualityComparer.Instance getter owner must be exact."
    assert plan.Methods[0].get_ReturnType() == runtimeType, "ReferenceEqualityComparer.Instance getter return type must be exact."
}
