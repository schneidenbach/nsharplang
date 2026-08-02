namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// ONE EXPRESSION THE FINALISING WALK WANTS ANALYSED, AND EVERYTHING THE ANALYSIS NEEDS.
//
// The walk cannot analyse an expression itself — the expression walk is the analyzer's, and calling
// back into it would be a callback. So the walk ASKS instead: it hands out one request at a time,
// receives the answer, and folds it in. `Lambda` non-null means the answer must come from the
// lambda entry point with `IsExpressionTreeTarget` applied; otherwise it comes from the ordinary
// expected-type entry point. Nothing here is a policy the driver may reinterpret: which node,
// which entry point, which expected type and which tree flag are all decided here.
public class ReflectionAnalysisRequest {

    expressionValue: Expression
    lambdaValue: LambdaExpression?
    expectedTypeValue: TypeInfo
    isExpressionTreeTargetValue: bool

    Expression: Expression => expressionValue
    Lambda: LambdaExpression? => lambdaValue
    ExpectedType: TypeInfo => expectedTypeValue
    IsExpressionTreeTarget: bool => isExpressionTreeTargetValue

    constructor(
        expression: Expression,
        lambda: LambdaExpression?,
        expectedType: TypeInfo,
        isExpressionTreeTarget: bool) {
        expressionValue = expression
        lambdaValue = lambda
        expectedTypeValue = expectedType
        isExpressionTreeTargetValue = isExpressionTreeTarget
    }
}

// THE FINALISING WALK'S WHOLE STATE, SUSPENDED BETWEEN TWO ANALYSES.
//
// The walk is a two-phase fold and it CANNOT be flattened into a schedule computed up front. Phase
// one analyses every lambda argument in order and folds each answer back into the bindings, so a
// later lambda's expected signature is read from bindings an EARLIER lambda's answer produced —
// measured, not assumed: on the `Join` / `GroupBy` / `SelectMany` / `Aggregate` shapes the signature
// at analysis time differs from the signature the ENTRY bindings give. The dependency is strictly
// backward (each answer depends only on earlier answers), so the walk suspends at each analysis
// point and resumes with the answer instead of predicting it.
//
// PHASE TWO IS FROZEN AND THAT IS ALSO MEASURED. Once phase one ends, the generic method is closed
// and neither bindings dictionary is written again — every phase-two expected type is a function of
// the frozen bindings. What phase two still cannot do up front is STOP: an argument that does not
// assign ends the whole finalisation, and later arguments must then not be analysed at all. So the
// answer is fed back there too, and the verdict is taken here rather than by the driver.
//
// THE SAME LAMBDA IS ANALYSED TWICE ON PURPOSE. Phase one analyses it to infer, phase two analyses
// it again against the now-complete signature, and the second analysis's RESULT is not read at all —
// it runs for the diagnostics and the semantic-model records it leaves behind. Collapsing the two
// would delete user-visible diagnostics and change their order, so both are kept exactly.
public class ReflectionCallFinalizeState {

    runtimeMethodValue: MethodInfo
    openMethodValue: MethodInfo
    openParametersValue: ParameterInfo[]
    boundArgumentsValue: List<ReflectionBoundArgument>
    suppliedArgumentsValue: List<SuppliedReflectionBoundArgument>
    methodGroupArgumentsValue: Dictionary<int, FunctionTypeInfo>
    workingBindingsValue: Dictionary<Type, Type>
    workingTypeInfoBindingsValue: Dictionary<Type, TypeInfo>
    parameterTypesValue: List<TypeInfo>

    RuntimeMethod: MethodInfo => runtimeMethodValue
    OpenMethod: MethodInfo => openMethodValue
    OpenParameters: ParameterInfo[] => openParametersValue
    BoundArguments: List<ReflectionBoundArgument> => boundArgumentsValue
    SuppliedArguments: List<SuppliedReflectionBoundArgument> => suppliedArgumentsValue
    MethodGroupArguments: Dictionary<int, FunctionTypeInfo> => methodGroupArgumentsValue
    WorkingBindings: Dictionary<Type, Type> => workingBindingsValue
    WorkingTypeInfoBindings: Dictionary<Type, TypeInfo> => workingTypeInfoBindingsValue
    ParameterTypes: List<TypeInfo> => parameterTypesValue

    // 0 = phase one (the inferring lambda pre-pass), 1 = phase two (convert and validate), 2 = done.
    public Phase: int
    public PreIndex: int
    public MainIndex: int
    public ParamsIndex: int
    public HasTypeInfoOverrides: bool
    public Failed: bool

    // 0 = nothing outstanding, 1 = a phase-one lambda, 2 = a phase-two lambda, 3 = a phase-two
    // expression. The kind decides what the answer is folded into, so it is state rather than a
    // property of the request the driver holds.
    public PendingKind: int
    public PendingOpenParameterType: Type?
    public PendingExpectedType: TypeInfo?

    // The finalised call type, or null while the walk is unfinished and forever if it failed.
    public Result: FunctionTypeInfo?

    constructor(
        runtimeMethod: MethodInfo,
        openMethod: MethodInfo,
        openParameters: ParameterInfo[],
        boundArguments: List<ReflectionBoundArgument>,
        suppliedArguments: List<SuppliedReflectionBoundArgument>,
        methodGroupArguments: Dictionary<int, FunctionTypeInfo>,
        workingBindings: Dictionary<Type, Type>,
        workingTypeInfoBindings: Dictionary<Type, TypeInfo>) {
        runtimeMethodValue = runtimeMethod
        openMethodValue = openMethod
        openParametersValue = openParameters
        boundArgumentsValue = boundArguments
        suppliedArgumentsValue = suppliedArguments
        methodGroupArgumentsValue = methodGroupArguments
        workingBindingsValue = workingBindings
        workingTypeInfoBindingsValue = workingTypeInfoBindings
        parameterTypesValue = new List<TypeInfo>()
        Phase = 0
        PreIndex = 0
        MainIndex = 0
        ParamsIndex = 0
        HasTypeInfoOverrides = false
        Failed = false
        PendingKind = 0
        PendingOpenParameterType = null
        PendingExpectedType = null
        Result = null
    }

    // The runtime method is REPLACED by its closed construction, exactly as the walk this replaces
    // did. The closed method is never read again — but `MakeGenericMethod` validates the constraints
    // and throws when they are violated, so the call is the behaviour, not the assignment.
    func CloseRuntimeMethod(typeArguments: Type[]) {
        runtimeMethodValue = runtimeMethodValue.MakeGenericMethod(typeArguments)
    }
}
