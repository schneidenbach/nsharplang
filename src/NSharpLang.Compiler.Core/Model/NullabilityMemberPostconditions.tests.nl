namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

func MemberPostconditionArgument(value: Expression): Argument {
    return new Argument(null, value, ArgumentModifier.None)
}

func MemberPostconditionAttribute(name: string, arguments: List<Argument>): AttributeNode {
    return new AttributeNode(name, arguments, 1, 1, null)
}

func MemberPostconditionReflection(method: MethodInfo): NullabilityMemberPostcondition[] {
    return NullabilityMemberPostconditions.FromReflectionAttributes(method.GetCustomAttributesData())
}

func MemberPostconditionCensus(facts: NullabilityMemberPostcondition[]): string {
    census := ""
    for fact in facts {
        census = census + fact.MemberName + "=" + fact.Condition.ToString() + ";"
    }

    return census
}

func ReflectedMethod(owner: Type, name: string, flags: BindingFlags): MethodInfo {
    method := owner.GetMethod(name, flags)
    if method == null {
        throw new InvalidOperationException(owner.FullName + "." + name + " was not found")
    }

    return method
}

func LazyInitializerAllowNullParameter(): ParameterInfo {
    methods := typeof(System.Threading.LazyInitializer).GetMethods(BindingFlags.Public | BindingFlags.Static)
    for method in methods {
        if method.Name != "EnsureInitialized" {
            continue
        }

        parameters := method.GetParameters()
        if parameters.Length == 4 && NullabilityFlowAttributeReflection.FromParameter(parameters[0]) == NullabilityFlowFacts.AllowNull() {
            return parameters[0]
        }
    }

    throw new InvalidOperationException("LazyInitializer.EnsureInitialized with [AllowNull] was not found")
}

test "MemberNotNull source attributes name every guaranteed member" {
    arguments := new List<Argument>()
    arguments.Add(MemberPostconditionArgument(new StringLiteralExpression("Value", 1, 1)))
    arguments.Add(MemberPostconditionArgument(new StringLiteralExpression("Other", 1, 1)))
    attributes := new List<AttributeNode>()
    attributes.Add(MemberPostconditionAttribute("System.Diagnostics.CodeAnalysis.MemberNotNullAttribute", arguments))

    facts := NullabilityMemberPostconditions.FromSourceAttributes(attributes)
    assert facts.Length == 2
    assert facts[0].MemberName == "Value"
    assert facts[0].Condition == NullabilityMemberPostconditions.Always()
    assert facts[1].MemberName == "Other"

    sourceMethod := new FunctionDeclaration("EnsureValue", new List<Parameter>(), null, null, null, null, null, Modifiers.None, attributes, false, null, false, false, 1, 1)
    declaredFacts := NominalTypeInfoFactory.GetMemberNullabilityPostconditionArray(sourceMethod as object)
    assert declaredFacts.Length == 2, MemberPostconditionCensus(declaredFacts)
}

test "MemberNotNullWhen carries only its literal boolean branch" {
    arguments := new List<Argument>()
    arguments.Add(MemberPostconditionArgument(new BoolLiteralExpression(false, 1, 1)))
    arguments.Add(MemberPostconditionArgument(new StringLiteralExpression("Value", 1, 1)))
    attributes := new List<AttributeNode>()
    attributes.Add(MemberPostconditionAttribute("MemberNotNullWhen", arguments))

    facts := NullabilityMemberPostconditions.FromSourceAttributes(attributes)
    assert facts.Length == 1
    assert facts[0].MemberName == "Value"
    assert facts[0].Condition == NullabilityMemberPostconditions.WhenFalse()

    arguments[0] = MemberPostconditionArgument(new IdentifierExpression("flag", 1, 1))
    attributes[0] = MemberPostconditionAttribute("MemberNotNullWhen", arguments)
    assert NullabilityMemberPostconditions.FromSourceAttributes(attributes).Length == 0
}

test "the reflection reader handles both member postcondition constructors" {
    bufferedStreamMethod := ReflectedMethod(typeof(System.IO.BufferedStream), "EnsureBufferAllocated", BindingFlags.Instance | BindingFlags.NonPublic)
    always := MemberPostconditionReflection(bufferedStreamMethod)
    assert always.Length == 1, "BufferedStream facts: " + MemberPostconditionCensus(always)
    assert always[0].MemberName == "_buffer", MemberPostconditionCensus(always)
    assert always[0].Condition == NullabilityMemberPostconditions.Always(), MemberPostconditionCensus(always)

    bddType := Type.GetType("System.Text.RegularExpressions.Symbolic.BDD, System.Text.RegularExpressions")
    assert bddType != null
    leafProperty := bddType.GetProperty("IsLeaf", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
    assert leafProperty != null
    conditional := MemberPostconditionReflection(leafProperty.GetMethod)
    assert conditional.Length == 2, "BDD.IsLeaf facts: " + MemberPostconditionCensus(conditional)
    assert conditional[0].Condition == NullabilityMemberPostconditions.WhenFalse(), MemberPostconditionCensus(conditional)
    assert conditional[1].Condition == NullabilityMemberPostconditions.WhenFalse(), MemberPostconditionCensus(conditional)
}

test "AllowNull and DisallowNull source and reflected parameter facts share one bit owner" {
    allowParameter := LazyInitializerAllowNullParameter()
    allowFacts := NullabilityFlowAttributeReflection.FromParameter(allowParameter)
    comparerMethod := ReflectedMethod(typeof(IEqualityComparer<string>), "GetHashCode", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
    disallowFacts := NullabilityFlowAttributeReflection.FromParameter(comparerMethod.GetParameters()[0])
    assert allowFacts == NullabilityFlowFacts.AllowNull(), allowFacts.ToString()
    assert disallowFacts == NullabilityFlowFacts.DisallowNull(), disallowFacts.ToString()

    assert NullabilityFlowFacts.FromSourceAttributes(NullabilityFlowFactsTestAttributes("AllowNull")) == NullabilityFlowFacts.AllowNull(), "source AllowNull was not read"
    assert NullabilityFlowFacts.FromSourceAttributes(NullabilityFlowFactsTestAttributes("DisallowNull")) == NullabilityFlowFacts.DisallowNull(), "source DisallowNull was not read"

    allowed := NullabilityMetadataCore.ApplyInputFlowFacts(BuiltInTypes.String, NullabilityFlowFacts.AllowNull())
    disallowed := NullabilityMetadataCore.ApplyInputFlowFacts(NNullabilityString(), NullabilityFlowFacts.DisallowNull())
    assert (allowed as NullableTypeInfo) != null, "[AllowNull] did not permit a nullable reference input"
    assert (disallowed as NullableTypeInfo) == null, "[DisallowNull] did not require a non-null reference input"
    valueTypeInput := NullabilityMetadataCore.ApplyInputFlowFacts(BuiltInTypes.Int, NullabilityFlowFacts.AllowNull())
    assert (valueTypeInput as NullableTypeInfo) == null, "[AllowNull] changed a value type"
}

test "NotNull and MaybeNull reflection facts keep their existing shared reader" {
    throwIfNull: MethodInfo? = null
    for method in typeof(ArgumentNullException).GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if method.Name == "ThrowIfNull" && method.GetParameters().Length > 0 && method.GetParameters()[0].ParameterType == typeof(object) {
            throwIfNull = method
            break
        }
    }
    assert throwIfNull != null, "ArgumentNullException.ThrowIfNull(object) was not found"
    assert NullabilityFlowAttributeReflection.FromParameter(throwIfNull.GetParameters()[0]) == NullabilityFlowFacts.NotNull()

    valueProperty := typeof(System.Threading.AsyncLocal<string>).GetProperty("Value")
    assert valueProperty != null
    getter := valueProperty.GetMethod
    assert getter != null
    facts := NullabilityFlowAttributeReflection.FromAttributes(getter.ReturnParameter.GetCustomAttributesData())
    assert NullabilityFlowFacts.Has(facts, NullabilityFlowFacts.MaybeNull()), "AsyncLocal.Value getter facts: " + facts.ToString()
    converted := NullabilityMetadataReflection.ConvertReturn(getter)
    assert converted is NullableTypeInfo, "AsyncLocal.Value getter return: " + NullabilityMetadataReflection.FormatTypeInfo(converted)
}

func NNullabilityString(): TypeInfo {
    return new NullableTypeInfo(BuiltInTypes.String)
}

func NullabilityFlowFactsTestAttributes(name: string): List<AttributeNode> {
    attributes := new List<AttributeNode>()
    attributes.Add(new AttributeNode(name, new List<Argument>(), 1, 1, null))
    return attributes
}
