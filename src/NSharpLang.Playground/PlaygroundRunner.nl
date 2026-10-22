namespace NSharpLang.Playground

import System
import System.Collections.Generic
import System.Globalization
import System.IO
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices
import System.Runtime.ExceptionServices
import System.Text
import System.Threading
import System.Threading.Tasks
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

internal sealed class PlaygroundRunner {
    private units: List<CompilationUnit>
    private entryPointValue: FunctionDeclaration?
    private types: Dictionary<string, Declaration>
    private typeNamespaces: Dictionary<string, string?>
    private semanticModelsByDeclaration: IReadOnlyDictionary<object, SemanticModel>
    private asyncDefaultFamilyValue: AsyncTaskFamily
    private configuredTaskAwaitables: Dictionary<object, RuntimeConfiguredTaskAwaitable>
    private stdout: StringBuilder
    private steps: int
    private outputLines: int

    constructor(sourceUnits: IEnumerable<CompilationUnit>, semanticModels: IReadOnlyDictionary<object, SemanticModel>, asyncDefaultFamily: AsyncTaskFamily) {
        units = sourceUnits.ToList()
        entryPointValue = null
        types = new Dictionary<string, Declaration>(StringComparer.Ordinal)
        typeNamespaces = new Dictionary<string, string?>(StringComparer.Ordinal)
        semanticModelsByDeclaration = semanticModels
        asyncDefaultFamilyValue = asyncDefaultFamily
        configuredTaskAwaitables = new Dictionary<object, RuntimeConfiguredTaskAwaitable>(ReferenceEqualityComparer.Instance)
        stdout = new StringBuilder()
        steps = 0
        outputLines = 0

        for unit in units {
            for declaration in unit.Declarations {
                functionDeclaration := declaration as FunctionDeclaration
                if functionDeclaration != null {
                    if PlaygroundRunFacts.IsEntryPointFunctionName(functionDeclaration.Name) {
                        entryPointValue = functionDeclaration
                    }
                } else {
                    name := PlaygroundRunFacts.DeclarationName(declaration)
                    if name != null {
                        types[name] = declaration
                        typeNamespaces[name] = AnalyzerDeclarationFileFacts.GetUnitNamespace(unit)
                    }
                }
            }
        }
    }

    // Browser execution is a bounded interpreter rather than emitted user assemblies. Its async
    // entry path uses CLR tasks for suspension so the WebAssembly export can return a JavaScript
    // Promise instead of holding the browser thread until an await completes.
    async func RunAsync(): Task<PlaygroundRunResult> {
        entryPoint := entryPointValue
        if entryPoint == null {
            throw Unsupported(PlaygroundRunFacts.NoEntryPoint())
        }

        try {
            emptyArguments := new object?[](0)
            await InvokeFunctionAsync(entryPoint, emptyArguments, null, 0)
            return new PlaygroundRunResult(stdout.ToString(), null, 0)
        } catch caught: Exception {
            thrown := caught as PlaygroundThrownException
            if thrown != null {
                return new PlaygroundRunResult(stdout.ToString(), FormatValue(thrown.Value), 1)
            }
            throw caught
        }
    }

    async func InvokeFunctionAsync(function: FunctionDeclaration, arguments: IReadOnlyList<object?>, receiver: RuntimeObject?, depth: int): Task<object?> {
        if depth > PlaygroundRunFacts.MaxCallDepth() {
            throw Unsupported(PlaygroundRunFacts.CallDepthExceeded())
        }
        if function.Parameters.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.WrongArgumentCount(function.Name, arguments.Count))
        }

        parentEnvironment: RuntimeEnvironment? = null
        if receiver != null {
            parentEnvironment = receiver.Environment
        }
        environment := new RuntimeEnvironment(parentEnvironment)
        semanticModel: SemanticModel? = null
        if semanticModelsByDeclaration.TryGetValue(function, out semanticModel) {
            environment.SetSemanticModel(semanticModel)
        }
        if receiver != null {
            environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), receiver)
        }

        i := 0
        while i < function.Parameters.Count {
            environment.Declare(function.Parameters[i].Name, arguments[i])
            i = i + 1
        }

        try {
            if function.ExpressionBody != null {
                return await EvaluateAsync(function.ExpressionBody, environment, depth + 1)
            }
            if function.Body != null {
                await ExecuteAsyncBlock(function.Body, environment, depth + 1)
            }
        } catch caught: Exception {
            signal := caught as ReturnSignal
            if signal != null {
                return signal.Value
            }
            throw caught
        }
        return null
    }

    async func ExecuteAsyncBlock(block: BlockStatement, environment: RuntimeEnvironment, depth: int): Task {
        for statement in block.Statements {
            await ExecuteAsyncStatement(statement, environment, depth)
        }
    }

    async func ExecuteAsyncStatement(statement: Statement, environment: RuntimeEnvironment, depth: int): Task {
        Step(statement)

        block := statement as BlockStatement
        variable := statement as VariableDeclarationStatement
        tuple := statement as TupleDeconstructionStatement
        expressionStatement := statement as ExpressionStatement
        printStatement := statement as PrintStatement
        returnStatement := statement as ReturnStatement
        ifStatement := statement as IfStatement
        foreachStatement := statement as ForeachStatement
        tryStatement := statement as TryStatement
        throwStatement := statement as ThrowStatement
        if block != null {
            await ExecuteAsyncBlock(block, new RuntimeEnvironment(environment), depth + 1)
        } else if statement as EmptyStatement != null {
            // Empty statements complete without an interpreter action.
        } else if variable != null {
            declaredValue: object? = null
            if variable.Initializer != null {
                declaredValue = await EvaluateAsync(variable.Initializer, environment, depth)
            }
            environment.Declare(variable.Name, declaredValue)
        } else if tuple != null {
            await ExecuteAsyncTupleDeconstruction(tuple, environment, depth)
        } else if expressionStatement != null {
            await EvaluateAsync(expressionStatement.Expression, environment, depth)
        } else if printStatement != null {
            printValue := await EvaluateAsync(printStatement.Value, environment, depth)
            WriteLine(FormatValue(printValue))
        } else if returnStatement != null {
            returnValue: object? = null
            if returnStatement.Value != null {
                returnValue = await EvaluateAsync(returnStatement.Value, environment, depth)
            }
            throw new ReturnSignal(returnValue)
        } else if ifStatement != null {
            if IsTruthy(await EvaluateAsync(ifStatement.Condition, environment, depth)) {
                await ExecuteAsyncStatement(ifStatement.ThenStatement, environment, depth + 1)
            } else if ifStatement.ElseStatement != null {
                await ExecuteAsyncStatement(ifStatement.ElseStatement, environment, depth + 1)
            }
        } else if foreachStatement != null {
            collection := await EvaluateAsync(foreachStatement.Collection, environment, depth)
            foreachValues := collection as IReadOnlyList<object?>
            if foreachValues == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedForeachCollection())
            }
            for foreachValue in foreachValues {
                loopEnvironment := new RuntimeEnvironment(environment)
                loopEnvironment.Declare(foreachStatement.VariableName, foreachValue)
                await ExecuteAsyncStatement(foreachStatement.Body, loopEnvironment, depth + 1)
            }
        } else if tryStatement != null {
            await ExecuteAsyncTry(tryStatement, environment, depth + 1)
        } else if throwStatement != null {
            thrown := throwStatement.Expression
            if thrown == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedStatement("a bare rethrow"))
            }
            thrownValue := await EvaluateAsync(thrown, environment, depth)
            throw new PlaygroundThrownException(thrownValue)
        } else {
            throw Unsupported(PlaygroundRunFacts.UnsupportedStatement(statement.GetType().Name))
        }
    }

    private async func ExecuteAsyncTupleDeconstruction(tuple: TupleDeconstructionStatement, environment: RuntimeEnvironment, depth: int): Task {
        call := tuple.Initializer as CallExpression
        if tuple.Names.Count != 2 || call == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedDeconstruction())
        }

        try {
            result := await EvaluateAsync(call, environment, depth)
            if !PlaygroundRunFacts.IsDiscardName(tuple.Names[0]) {
                environment.Declare(tuple.Names[0], result)
            }
            if !PlaygroundRunFacts.IsDiscardName(tuple.Names[1]) {
                environment.Declare(tuple.Names[1], null)
            }
        } catch caught: Exception {
            thrown := caught as PlaygroundThrownException
            if thrown == null {
                throw caught
            }
            if !PlaygroundRunFacts.IsDiscardName(tuple.Names[0]) {
                environment.Declare(tuple.Names[0], null)
            }
            if !PlaygroundRunFacts.IsDiscardName(tuple.Names[1]) {
                environment.Declare(tuple.Names[1], thrown.Value)
            }
        }
    }

    private async func ExecuteAsyncTry(statement: TryStatement, environment: RuntimeEnvironment, depth: int): Task {
        try {
            try {
                await ExecuteAsyncBlock(statement.TryBlock, new RuntimeEnvironment(environment), depth + 1)
            } catch caught: Exception {
                signal := caught as ReturnSignal
                unsupported := caught as PlaygroundRunUnsupportedException
                if signal != null || unsupported != null {
                    throw caught
                }

                thrown := caught as PlaygroundThrownException
                handled := false
                for clause in statement.CatchClauses {
                    if !CatchMatches(clause, caught, thrown) {
                        continue
                    }
                    catchEnvironment := new RuntimeEnvironment(environment)
                    if clause.VariableName != null {
                        caughtValue: object? = caught
                        if thrown != null {
                            caughtValue = thrown.Value
                        }
                        catchEnvironment.Declare(clause.VariableName, caughtValue)
                    }
                    if clause.Filter != null {
                        filterPassed := CatchFilterMatches(clause, catchEnvironment, depth + 1)
                        if !filterPassed {
                            continue
                        }
                    }
                    await ExecuteAsyncBlock(clause.Block, catchEnvironment, depth + 1)
                    handled = true
                    break
                }
                if !handled {
                    throw caught
                }
            }
        } finally {
            if statement.FinallyBlock != null {
                await ExecuteAsyncBlock(statement.FinallyBlock, new RuntimeEnvironment(environment), depth + 1)
            }
        }
    }

    private static func CatchMatches(clause: CatchClause, caught: Exception, thrown: PlaygroundThrownException?): bool {
        if clause.ExceptionType == null {
            return true
        }
        catchName := GetTypeName(clause.ExceptionType) ?? ""
        if catchName == "Exception" || catchName == "System.Exception" {
            return true
        }
        if thrown != null {
            runtimeError := thrown.Value as RuntimeError
            if runtimeError != null {
                return catchName == "RuntimeError"
            }
            runtimeObject := thrown.Value as RuntimeObject
            return runtimeObject != null && runtimeObject.Declaration != null && PlaygroundRunFacts.DeclarationName(runtimeObject.Declaration) == catchName
        }
        return caught.GetType().Name == catchName || caught.GetType().FullName == catchName
    }

    private func CatchFilterMatches(clause: CatchClause, environment: RuntimeEnvironment, depth: int): bool {
        if clause.Filter == null {
            return true
        }
        return IsTruthy(Evaluate(clause.Filter, environment, depth))
    }

    async func EvaluateAsync(expression: Expression, environment: RuntimeEnvironment, depth: int): Task<object?> {
        Step(expression)

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return ResolveIdentifier(PlaygroundRunFacts.ReceiverBindingName(), environment)
        }

        awaited := expression as AwaitExpression
        if awaited != null {
            try {
                return await AwaitTaskValue(await EvaluateAsync(awaited.Expression, environment, depth), awaited, environment.SemanticModel)
            } catch unsupported: PlaygroundRunUnsupportedException {
                if unsupported.Line > 0 {
                    throw unsupported
                }
                throw new PlaygroundRunUnsupportedException(unsupported.Code, unsupported.Message, awaited.Line, awaited.Column, 1)
            }
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return await EvaluateAsync(parenthesized.Inner, environment, depth)
        }

        binary := expression as BinaryExpression
        if binary != null {
            left := await EvaluateAsync(binary.Left, environment, depth)
            if binary.Operator == BinaryOperator.And && !IsTruthy(left) {
                return false
            }
            if binary.Operator == BinaryOperator.Or && IsTruthy(left) {
                return true
            }
            right := await EvaluateAsync(binary.Right, environment, depth)
            return EvaluateBinaryValues(binary, left, right)
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            return await EvaluateAsyncAssignment(assignment, environment, depth)
        }

        unary := expression as UnaryExpression
        if unary != null {
            unaryValue := await EvaluateAsync(unary.Operand, environment, depth)
            if unary.Operator == UnaryOperator.Negate {
                return -ToNumber(unaryValue)
            }
            if unary.Operator == UnaryOperator.Not {
                return !IsTruthy(unaryValue)
            }
            unaryOperatorValue := unary.Operator as object
            throw Unsupported(PlaygroundRunFacts.UnsupportedUnaryOperator(unaryOperatorValue.ToString() ?? ""))
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            builder := new StringBuilder()
            for part in interpolated.Parts {
                textPart := part as InterpolatedStringText
                if textPart != null {
                    builder.Append(textPart.Text)
                } else {
                    hole := part as InterpolatedStringHole
                    if hole != null {
                        builder.Append(FormatValue(await EvaluateAsync(hole.Expression, environment, depth)))
                    }
                }
            }
            return builder.ToString()
        }

        call := expression as CallExpression
        if call != null {
            try {
                return await EvaluateAsyncCall(call, environment, depth)
            } catch unsupported: PlaygroundRunUnsupportedException {
                if unsupported.Line > 0 {
                    throw unsupported
                }
                throw new PlaygroundRunUnsupportedException(unsupported.Code, unsupported.Message, call.Line, call.Column, 1)
            }
        }

        member := expression as MemberAccessExpression
        if member != null {
            taskType := member.Object as IdentifierExpression
            if member.MemberName == "CompletedTask" && IsStaticFrameworkTypeIdentifier(taskType, environment.SemanticModel, typeof(Task)) {
                return Task.CompletedTask
            }
            valueTaskType := member.Object as IdentifierExpression
            if member.MemberName == "CompletedTask" && IsStaticFrameworkTypeIdentifier(valueTaskType, environment.SemanticModel, typeof(ValueTask)) {
                return ValueTask.CompletedTask
            }
            target := await EvaluateAsync(member.Object, environment, depth)
            runtimeObject := target as RuntimeObject
            if runtimeObject != null {
                fieldValue: object? = null
                if runtimeObject.Fields.TryGetValue(member.MemberName, out fieldValue) {
                    return fieldValue
                }
                property := FindProperty(runtimeObject.Declaration, member.MemberName)
                if property != null {
                    return ReadRuntimeProperty(runtimeObject, property, depth)
                }
            }
            if target != null {
                propertyResult: object?[] = ReadClrProperty(target, member.MemberName)
                if Convert.ToBoolean(propertyResult[0]) {
                    return propertyResult[1]
                }
            }
            return EvaluateMemberAccess(member, environment, depth)
        }

        array := expression as ArrayLiteralExpression
        if array != null {
            values := new object?[](array.Elements.Count)
            i := 0
            while i < array.Elements.Count {
                arrayElement := await EvaluateAsync(array.Elements[i], environment, depth)
                SetArrayElement(values, i, arrayElement)
                i = i + 1
            }
            return values
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            arguments := new object?[](newExpression.ConstructorArguments.Count)
            i := 0
            while i < arguments.Length {
                constructorArgument := newExpression.ConstructorArguments[i]
                if constructorArgument.Modifier != ArgumentModifier.Out {
                    argumentValue := await EvaluateAsync(constructorArgument.Value, environment, depth)
                    SetArrayElement(arguments, i, argumentValue)
                }
                i += 1
            }
            created := EvaluateNewWithArguments(newExpression, arguments, environment.SemanticModel, environment, depth)
            if newExpression.Initializer != null {
                await ApplyAsyncInitializer(created, newExpression.Initializer, environment, depth)
            }
            return created
        }

        return Evaluate(expression, environment, depth)
    }

    private async func EvaluateAsyncAssignment(assignment: AssignmentExpression, environment: RuntimeEnvironment, depth: int): Task<object?> {
        value := await EvaluateAsync(assignment.Value, environment, depth)
        if assignment.Operator != AssignmentOperator.Assign {
            current := await EvaluateAsync(assignment.Target, environment, depth)
            if assignment.Operator == AssignmentOperator.AddAssign {
                value = ToNumber(current) + ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.SubtractAssign {
                value = ToNumber(current) - ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.MultiplyAssign {
                value = ToNumber(current) * ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.DivideAssign {
                value = Divide(current, value)
            } else if assignment.Operator == AssignmentOperator.NullCoalesceAssign {
                if current != null {
                    value = current
                }
            } else {
                assignmentOperatorValue := assignment.Operator as object
                throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentOperator(assignmentOperatorValue.ToString() ?? ""))
            }
        }

        identifier := assignment.Target as IdentifierExpression
        if identifier != null {
            environment.Set(identifier.Name, value)
            return value
        }
        member := assignment.Target as MemberAccessExpression
        if member != null {
            target := await EvaluateAsync(member.Object, environment, depth)
            runtimeObject := target as RuntimeObject
            if runtimeObject != null {
                runtimeObject.Fields[member.MemberName] = value
                return value
            }
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentTarget())
    }

    async func EvaluateAsyncCall(call: CallExpression, environment: RuntimeEnvironment, depth: int): Task<object?> {
        arguments := new object?[](call.Arguments.Count)
        i := 0
        while i < call.Arguments.Count {
            callArgument := await EvaluateAsync(call.Arguments[i].Value, environment, depth)
            SetArrayElement(arguments, i, callArgument)
            i = i + 1
        }

        identifier := call.Callee as IdentifierExpression
        if identifier != null {
            boundValue := ReadBoundValue(environment, identifier.Name)
            if boundValue != null {
                callable := boundValue as Delegate
                if callable != null {
                    return callable.DynamicInvoke(ToInvocationArguments(arguments))
                }
                runtimeFunction := boundValue as RuntimeFunction
                if runtimeFunction != null {
                    if AnalyzerAmbientContext.HasModifier(runtimeFunction.Declaration, Modifiers.Async) {
                        return InvokeAsyncFunctionValue(runtimeFunction.Declaration, arguments, runtimeFunction.Receiver, depth)
                    }
                    return InvokeFunction(runtimeFunction.Declaration, arguments, runtimeFunction.Receiver, depth)
                }
                runtimeLambda := boundValue as RuntimeLambda
                if runtimeLambda != null {
                    return InvokeLambda(runtimeLambda, arguments, depth)
                }
            }
            selectedBinding: AnalyzerInvocationBinding? = null
            semanticModel := environment.SemanticModel
            if semanticModel != null && semanticModel.TryGetInvocationBindingAt(call.Line, call.Column, out selectedBinding) && selectedBinding != null {
                return InvokeBoundInvocation(selectedBinding, BoundInvocationReceiver(selectedBinding, null, environment), arguments, depth, call)
            }
            throw Unsupported(PlaygroundRunFacts.UnknownFunction(identifier.Name))
        }

        member := call.Callee as MemberAccessExpression
        if member == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedCallee())
        }

        selectedBinding: AnalyzerInvocationBinding? = null
        semanticModel := environment.SemanticModel
        if semanticModel != null {
            semanticModel.TryGetInvocationBindingAt(call.Line, call.Column, out selectedBinding)
        }
        if IsFrameworkTaskStaticInvocation(selectedBinding) || selectedBinding == null && IsFrameworkTaskStaticIdentifier(member.Object, semanticModel) {
            if selectedBinding == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer did not select a Task or ValueTask overload"))
            }
            return InvokeBoundInvocation(selectedBinding, null, arguments, depth, call)
        }

        target := await EvaluateAsync(member.Object, environment, depth)
        if member.MemberName == "ConfigureAwait" {
            if selectedBinding == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("ConfigureAwait has no analyzer-selected invocation binding"))
            }
            return InvokeBoundConfigureAwait(selectedBinding, target, arguments, depth, call)
        }
        if selectedBinding != null {
            return InvokeBoundInvocation(selectedBinding, target, arguments, depth, call)
        }
        if member.MemberName == "GetAwaiter" {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("GetAwaiter call lacks an analyzer binding"))
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser runner has no analyzer-selected method for this call"))
    }

    private func InvokeBoundConfigureAwait(binding: AnalyzerInvocationBinding, target: object?, arguments: object?[], depth: int, call: CallExpression): object? {
        if !BoundInvocationRefKindsAreCompatible(binding, call) {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected ConfigureAwait binding has incompatible argument directions"))
        }

        sourceFunctionType := binding.SourceFunction
        if sourceFunctionType != null {
            function := sourceFunctionType.SourceDeclaration
            if function == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected source ConfigureAwait has no declaration"))
            }
            invocationArguments := binding.IsExtension ? PrependRuntimeArgument(target, arguments) : arguments
            receiver := binding.IsExtension ? null : target as RuntimeObject
            if !binding.IsExtension && receiver == null && !sourceFunctionType.SourceIsStatic {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected source ConfigureAwait has no runtime receiver"))
            }
            if AnalyzerAmbientContext.HasModifier(function, Modifiers.Async) {
                return InvokeAsyncFunctionValue(function, invocationArguments, receiver, depth)
            }
            return InvokeFunction(function, invocationArguments, receiver, depth)
        }

        selectedMethod := binding.ReflectedMethod
        if selectedMethod == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("ConfigureAwait has no selected method"))
        }
        runtimeMethod: MethodInfo? = null
        invocationReceiver: object? = target
        invocationArguments := arguments
        if binding.IsExtension {
            runtimeMethod = SelectedRuntimeClosedExtensionMethodFor(selectedMethod)
            invocationReceiver = null
            invocationArguments = PrependRuntimeArgument(target, arguments)
        } else if target != null {
            runtimeMethod = SelectedRuntimeMethodFor(selectedMethod, target.GetType())
        }
        if runtimeMethod == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected ConfigureAwait method has no runtime metadata match"))
        }
        try {
            configuredValue := runtimeMethod.Invoke(invocationReceiver, invocationArguments)
            if configuredValue != null && IsNonGenericTaskConfigureAwait(binding, selectedMethod) && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(configuredValue.GetType(), typeof(ConfiguredTaskAwaitable)) {
                task := target as Task
                if task != null {
                    RegisterRuntimeConfiguredTaskAwaitable(configuredValue, task, (bool)arguments[0])
                }
            } else if configuredValue != null && IsNonGenericValueTaskConfigureAwait(binding, selectedMethod, target) && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(configuredValue.GetType(), typeof(ConfiguredValueTaskAwaitable)) {
                RegisterRuntimeConfiguredTaskAwaitable(configuredValue, ((ValueTask)target).AsTask(), (bool)arguments[0])
            }
            return configuredValue
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    private static func IsNonGenericTaskConfigureAwait(binding: AnalyzerInvocationBinding, selectedMethod: MethodInfo): bool {
        if binding == null || binding.IsExtension || selectedMethod == null || selectedMethod.DeclaringType == null || selectedMethod.IsStatic || selectedMethod.Name != "ConfigureAwait" || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selectedMethod.DeclaringType, typeof(Task)) || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selectedMethod.ReturnType, typeof(ConfiguredTaskAwaitable)) {
            return false
        }
        return HasSingleBooleanParameter(selectedMethod)
    }

    private static func IsNonGenericValueTaskConfigureAwait(binding: AnalyzerInvocationBinding, selectedMethod: MethodInfo, target: object?): bool {
        if binding == null || binding.IsExtension || selectedMethod == null || selectedMethod.DeclaringType == null || selectedMethod.IsStatic || selectedMethod.Name != "ConfigureAwait" || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selectedMethod.DeclaringType, typeof(ValueTask)) || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selectedMethod.ReturnType, typeof(ConfiguredValueTaskAwaitable)) || target == null || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(target.GetType(), typeof(ValueTask)) {
            return false
        }
        return HasSingleBooleanParameter(selectedMethod)
    }

    private static func HasSingleBooleanParameter(method: MethodInfo): bool {
        if method == null {
            return false
        }
        parameters := method.GetParameters()
        return parameters.Length == 1 && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(parameters[0].ParameterType, typeof(bool))
    }

    private static func PrependRuntimeArgument(receiver: object?, arguments: object?[]): object?[] {
        result := new object?[](arguments.Length + 1)
        result[0] = receiver
        index := 0
        while index < arguments.Length {
            result[index + 1] = arguments[index]
            index += 1
        }
        return result
    }

    private func InvokeAsyncFunctionValue(function: FunctionDeclaration, arguments: IReadOnlyList<object?>, receiver: RuntimeObject?, depth: int): object {
        task := InvokeFunctionAsync(function, arguments, receiver, depth)
        return WrapAsyncFunctionTaskValue(function.Name, function.ReturnType, task, asyncDefaultFamilyValue)
    }

    private static func WrapAsyncFunctionTaskValue(functionName: string, returnType: TypeReference?, task: Task<object?>, defaultAsyncFamily: AsyncTaskFamily): object {
        generic := returnType as GenericTypeReference
        if generic != null && TaskLikeTypeFacts.IsTaskLikeName(generic.Name) {
            if TaskLikeTypeFacts.IsValueTaskName(generic.Name) {
                return new ValueTask<object?>(task)
            }
            return task
        }
        simple := returnType as SimpleTypeReference
        if simple != null && TaskLikeTypeFacts.IsTaskLikeName(simple.Name) {
            if TaskLikeTypeFacts.IsValueTaskName(simple.Name) {
                return new ValueTask(task)
            }
            return task
        }
        if AsyncTaskFamilyFacts.EffectiveFamily(functionName, defaultAsyncFamily) == AsyncTaskFamily.ValueTask {
            if returnType == null {
                return new ValueTask(task)
            }
            return new ValueTask<object?>(task)
        }
        return task
    }

    async func AwaitTaskValue(value: object?, awaitNode: AwaitExpression? = null, semanticModel: SemanticModel? = null): Task<object?> {
        if value == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand without a task value"))
        }

        runtimeObject := value as RuntimeObject
        if runtimeObject != null {
            sourceBinding := AwaitablePatternAt(semanticModel, awaitNode)
            if sourceBinding == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await has no shared source awaitable binding"))
            }
            return await AwaitSourceAwaitable(runtimeObject, sourceBinding)
        }

        awaitableType := value.GetType()
        if awaitableType == typeof(YieldAwaitable) {
            // The browser linker does not preserve YieldAwaitable.GetAwaiter for reflection.
            // Task.Yield always suspends once, so model its await contract directly here.
            await Task.Yield()
            return null
        }
        if semanticModel == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await has no semantic model"))
        }
        if awaitNode == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await has no source node"))
        }
        semanticBinding := AwaitablePatternAt(semanticModel, awaitNode)
        if semanticBinding == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await has no shared awaitable binding"))
        }
        if semanticBinding.ReflectedAwaiter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("shared awaitable binding has no reflected awaiter pattern"))
        }
        configuredTask: RuntimeConfiguredTaskAwaitable? = null
        if value != null && configuredTaskAwaitables.TryGetValue(value, out configuredTask) && configuredTask != null {
            return await AwaitConfiguredTaskOperation(configuredTask)
        }
        pattern := semanticBinding.ReflectedAwaiter
        getAwaiter := pattern.GetAwaiter
        if getAwaiter != null {
            if pattern.GetAwaiterIsExtension {
                getAwaiter = SelectedRuntimeExtensionMethodFor(getAwaiter, semanticBinding.GetAwaiterTypeArguments)
            } else {
                getAwaiter = SelectedRuntimeMethodFor(getAwaiter, value.GetType())
            }
        }
        isCompletedGetter := pattern.IsCompletedGetter
        if getAwaiter == null || isCompletedGetter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand has no complete C# awaitable pattern"))
        }
        awaiter: object? = null
        try {
            if pattern.GetAwaiterIsExtension {
                extensionArguments := new object?[](1)
                extensionArguments[0] = value
                awaiter = getAwaiter.Invoke(null, extensionArguments)
            } else {
                awaiter = getAwaiter.Invoke(value, null)
            }
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        if awaiter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("GetAwaiter returned no awaiter"))
        }
        return await AwaitReflectedAwaiter(awaiter, pattern)
    }

    private func RegisterRuntimeConfiguredTaskAwaitable(value: object?, task: Task, continueOnCapturedContext: bool): void {
        if value == null {
            return
        }
        configuredTaskAwaitables[value] = new RuntimeConfiguredTaskAwaitable(task, continueOnCapturedContext)
    }

    private func AwaitConfiguredTaskOperation(value: RuntimeConfiguredTaskAwaitable): Task<object?> {
        return AwaitTaskOperation(value.Task, value.ContinueOnCapturedContext)
    }

    private static func AwaitTaskOperation(task: Task, continueOnCapturedContext: bool): Task<object?> {
        completion := new TaskCompletionSource<object?>(TaskCreationOptions.RunContinuationsAsynchronously)
        continuation := PlaygroundTaskCompletionSignal.CreateAction(task, completion)
        if continueOnCapturedContext {
            task.GetAwaiter().OnCompleted(continuation)
        } else {
            task.GetAwaiter().UnsafeOnCompleted(continuation)
        }
        return completion.Task
    }

    private static func SelectedRuntimeMethodFor(selected: MethodInfo?, runtimeOwner: Type): MethodInfo? {
        if selected == null || runtimeOwner == null {
            return null
        }
        selectedOwner := selected.DeclaringType
        if selectedOwner == null {
            return null
        }
        if selectedOwner.IsInterface {
            return SelectedRuntimeInterfaceMethodFor(selected, selectedOwner, runtimeOwner)
        }
        // Reference assemblies and runtime assemblies can assign different metadata tokens. The
        // shared binder already selected this exact member; map its declaring type and signature
        // to the execution assembly without running overload resolution again.
        selectedOpen := selected.IsGenericMethod ? selected.GetGenericMethodDefinition() : selected
        for candidate in runtimeOwner.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if RuntimeTypeDefinitionsMatch(selectedOwner, candidate.DeclaringType) && RuntimeMethodSignaturesMatch(selectedOpen, candidate) {
                return CloseRuntimeMethodForSelected(selected, candidate)
            }
        }
        // Never invoke a reference-assembly member from the analyzer's MetadataLoadContext. A
        // missing runtime mapping is surfaced to the playground's bounded-run path instead.
        return null
    }

    private static func CloseRuntimeMethodForSelected(selected: MethodInfo, runtimeMethod: MethodInfo): MethodInfo? {
        if selected == null || runtimeMethod == null || !selected.IsGenericMethod {
            return runtimeMethod
        }
        if selected.IsGenericMethodDefinition {
            return runtimeMethod.IsGenericMethodDefinition ? runtimeMethod : null
        }

        selectedArguments := selected.GetGenericArguments()
        if !runtimeMethod.IsGenericMethodDefinition || selectedArguments.Length != runtimeMethod.GetGenericArguments().Length {
            return null
        }
        runtimeArguments := new Type[selectedArguments.Length]
        index := 0
        while index < runtimeArguments.Length {
            resolved: Type = null
            if !TryResolvePlaygroundRuntimeTypeFromMetadata(selectedArguments[index], out resolved) {
                return null
            }
            runtimeArguments[index] = resolved
            index += 1
        }
        try {
            return runtimeMethod.MakeGenericMethod(runtimeArguments)
        } catch failure: ArgumentException {
            return null
        }
    }

    // The shared binder selected a reflected extension and retained its inferred generic arguments.
    // Resolve that exact declaration on the executable assembly, then close it with those arguments;
    // never invoke the analyzer's MetadataLoadContext method or redo extension overload selection.
    private static func SelectedRuntimeExtensionMethodFor(selected: MethodInfo?, boundTypeArguments: NSharpLang.Compiler.TypeInfo[]): MethodInfo? {
        if selected == null || !selected.IsStatic || selected.DeclaringType == null {
            return null
        }
        selectedOwner := selected.DeclaringType
        runtimeOwner: Type = null
        if !TryResolvePlaygroundRuntimeTypeFromMetadata(selectedOwner, out runtimeOwner) {
            return null
        }

        selectedOpen := selected.IsGenericMethod ? selected.GetGenericMethodDefinition() : selected
        for candidate in runtimeOwner.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static) {
            if !RuntimeMethodSignaturesMatch(selectedOpen, candidate) {
                continue
            }
            if !selectedOpen.IsGenericMethodDefinition {
                return candidate
            }
            if boundTypeArguments == null || boundTypeArguments.Length != selectedOpen.GetGenericArguments().Length {
                return null
            }
            runtimeTypeArguments := new Type[boundTypeArguments.Length]
            index := 0
            while index < runtimeTypeArguments.Length {
                runtimeTypeArgument: Type = null
                if !TryResolvePlaygroundRuntimeType(boundTypeArguments[index], out runtimeTypeArgument) {
                    return null
                }
                runtimeTypeArguments[index] = runtimeTypeArgument
                index += 1
            }
            try {
                return candidate.MakeGenericMethod(runtimeTypeArguments)
            } catch failure: ArgumentException {
                return null
            }
        }
        return null
    }

    private static func SelectedRuntimeClosedExtensionMethodFor(selected: MethodInfo?): MethodInfo? {
        if selected == null || !selected.IsStatic {
            return null
        }
        if !selected.IsGenericMethod {
            return SelectedRuntimeExtensionMethodFor(selected, new NSharpLang.Compiler.TypeInfo[](0))
        }
        if selected.IsGenericMethodDefinition {
            return null
        }
        genericArguments := selected.GetGenericArguments()
        typeArguments := new NSharpLang.Compiler.TypeInfo[](genericArguments.Length)
        index := 0
        while index < genericArguments.Length {
            typeArguments[index] = new NSharpLang.Compiler.ReflectionTypeInfo(genericArguments[index])
            index += 1
        }
        return SelectedRuntimeExtensionMethodFor(selected.GetGenericMethodDefinition(), typeArguments)
    }

    private static func TryResolvePlaygroundRuntimeType(typeInfo: NSharpLang.Compiler.TypeInfo, out runtimeType: Type): bool {
        runtimeType = null
        if typeInfo == null {
            return false
        }
        obliviousType := typeInfo as ObliviousTypeInfo
        if obliviousType != null {
            return TryResolvePlaygroundRuntimeType(obliviousType.InnerType, out runtimeType)
        }
        nullableType := typeInfo as NullableTypeInfo
        if nullableType != null {
            underlyingType: Type = null
            if !TryResolvePlaygroundRuntimeType(nullableType.InnerType, out underlyingType) {
                return false
            }
            if !underlyingType.IsValueType {
                runtimeType = underlyingType
                return true
            }
            try {
                arguments := new Type[](1)
                arguments[0] = underlyingType
                runtimeType = typeof(Nullable<int>).GetGenericTypeDefinition().MakeGenericType(arguments)
                return true
            } catch failure: ArgumentException {
                return false
            }
        }
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            return TryResolvePlaygroundRuntimeTypeFromMetadata(reflected.Type, out runtimeType)
        }
        constructed := typeInfo as GenericTypeInfo
        if constructed != null {
            definition := constructed.GenericDefinition as ReflectionTypeInfo
            if definition == null || !TryResolvePlaygroundRuntimeTypeFromMetadata(definition.Type, out runtimeType) || !runtimeType.IsGenericTypeDefinition || constructed.TypeArguments.Count != runtimeType.GetGenericArguments().Length {
                runtimeType = null
                return false
            }
            arguments := new Type[constructed.TypeArguments.Count]
            index := 0
            while index < arguments.Length {
                runtimeArgument: Type = null
                if !TryResolvePlaygroundRuntimeType(constructed.TypeArguments[index], out runtimeArgument) {
                    runtimeType = null
                    return false
                }
                arguments[index] = runtimeArgument
                index += 1
            }
            try {
                runtimeType = runtimeType.MakeGenericType(arguments)
                return true
            } catch failure: ArgumentException {
                runtimeType = null
                return false
            }
        }
        arrayType := typeInfo as ArrayTypeInfo
        if arrayType != null {
            elementType: Type = null
            if !TryResolvePlaygroundRuntimeType(arrayType.ElementType, out elementType) {
                return false
            }
            runtimeType = elementType.MakeArrayType()
            return true
        }
        simpleType := typeInfo as SimpleTypeInfo
        if simpleType != null {
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Bool) {
                runtimeType = typeof(bool)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Byte) {
                runtimeType = typeof(byte)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.SByte) {
                runtimeType = typeof(sbyte)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Short) {
                runtimeType = typeof(short)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.UShort) {
                runtimeType = typeof(ushort)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Int) {
                runtimeType = typeof(int)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.UInt) {
                runtimeType = typeof(uint)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Long) {
                runtimeType = typeof(long)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.ULong) {
                runtimeType = typeof(ulong)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Float) {
                runtimeType = typeof(float)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Double) {
                runtimeType = typeof(double)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Decimal) {
                runtimeType = typeof(decimal)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Char) {
                runtimeType = typeof(char)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.String) {
                runtimeType = typeof(string)
                return true
            }
            if BuiltInTypes.Is(simpleType, BuiltInTypes.Object) {
                runtimeType = typeof(object)
                return true
            }
        }
        // Source and unresolved external names do not carry a CLR Type handle. Do not turn their
        // display text into a runtime lookup: source declarations are interpreted directly, and an
        // external type without resolved metadata is unsupported at this execution boundary.
        return false
    }

    private static func TryResolvePlaygroundRuntimeTypeFromMetadata(metadataType: Type, out runtimeType: Type): bool {
        runtimeType = null
        if metadataType == null || metadataType.IsGenericParameter || metadataType.FullName == null {
            return false
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(bool)) {
            runtimeType = typeof(bool)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(byte)) {
            runtimeType = typeof(byte)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(sbyte)) {
            runtimeType = typeof(sbyte)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(short)) {
            runtimeType = typeof(short)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(ushort)) {
            runtimeType = typeof(ushort)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(int)) {
            runtimeType = typeof(int)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(uint)) {
            runtimeType = typeof(uint)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(long)) {
            runtimeType = typeof(long)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(ulong)) {
            runtimeType = typeof(ulong)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(float)) {
            runtimeType = typeof(float)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(double)) {
            runtimeType = typeof(double)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(decimal)) {
            runtimeType = typeof(decimal)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(char)) {
            runtimeType = typeof(char)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(string)) {
            runtimeType = typeof(string)
            return true
        }
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, typeof(object)) {
            runtimeType = typeof(object)
            return true
        }
        if metadataType.IsArray {
            elementType: Type = null
            metadataElement := metadataType.GetElementType()
            if metadataElement == null || !TryResolvePlaygroundRuntimeTypeFromMetadata(metadataElement, out elementType) {
                return false
            }
            if metadataType.GetArrayRank() == 1 {
                runtimeType = metadataType.IsSZArray ? elementType.MakeArrayType() : elementType.MakeArrayType(1)
            } else {
                runtimeType = elementType.MakeArrayType(metadataType.GetArrayRank())
            }
            return true
        }
        if metadataType.IsGenericType && !metadataType.IsGenericTypeDefinition {
            genericDefinition: Type = null
            if !TryResolvePlaygroundRuntimeTypeFromMetadata(metadataType.GetGenericTypeDefinition(), out genericDefinition) {
                return false
            }
            metadataArguments := metadataType.GetGenericArguments()
            runtimeArguments := new Type[metadataArguments.Length]
            index := 0
            while index < metadataArguments.Length {
                runtimeArgument: Type = null
                if !TryResolvePlaygroundRuntimeTypeFromMetadata(metadataArguments[index], out runtimeArgument) {
                    return false
                }
                runtimeArguments[index] = runtimeArgument
                index += 1
            }
            try {
                runtimeType = genericDefinition.MakeGenericType(runtimeArguments)
                return true
            } catch failure: ArgumentException {
                return false
            }
        }
        metadataName := metadataType.FullName
        if metadataName == null {
            return false
        }
        resolvedMetadataType := Type.GetType(metadataName)
        if resolvedMetadataType != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, resolvedMetadataType) {
            runtimeType = resolvedMetadataType
            return true
        }
        assemblyName := metadataType.Assembly.GetName().Name
        if assemblyName == null {
            return false
        }
        for runtimeAssembly in AppDomain.CurrentDomain.GetAssemblies() {
            if runtimeAssembly.GetName().Name == assemblyName {
                resolvedAssemblyType := runtimeAssembly.GetType(metadataName)
                if resolvedAssemblyType != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, resolvedAssemblyType) {
                    runtimeType = resolvedAssemblyType
                    return true
                }
            }
        }
        runtimeAssemblyPath := Path.Combine(AppContext.BaseDirectory, assemblyName + ".dll")
        if File.Exists(runtimeAssemblyPath) {
            try {
                runtimeAssembly := Assembly.Load(File.ReadAllBytes(runtimeAssemblyPath))
                resolvedAssemblyType := runtimeAssembly.GetType(metadataName)
                if resolvedAssemblyType != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(metadataType, resolvedAssemblyType) {
                    runtimeType = resolvedAssemblyType
                    return true
                }
            } catch loadFailure: Exception {
                runtimeType = null
                return false
            }
        }
        return false
    }

    private static func SelectedRuntimeInterfaceMethodFor(selected: MethodInfo, selectedOwner: Type, runtimeOwner: Type): MethodInfo? {
        runtimeSelectedOwner: Type = null
        if !TryResolvePlaygroundRuntimeTypeFromMetadata(selectedOwner, out runtimeSelectedOwner) {
            return null
        }
        for runtimeInterface in runtimeOwner.GetInterfaces() {
            if !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(runtimeSelectedOwner, runtimeInterface) {
                continue
            }
            mapping := runtimeOwner.GetInterfaceMap(runtimeInterface)
            index := 0
            while index < mapping.InterfaceMethods.Length {
                interfaceMethod := mapping.InterfaceMethods[index]
                if RuntimeMethodSignaturesMatch(selected, interfaceMethod) {
                    return mapping.TargetMethods[index]
                }
                index += 1
            }
        }
        return null
    }

    private static func RuntimeMethodSignaturesMatch(selected: MethodInfo, runtimeMethod: MethodInfo): bool {
        if selected == null || runtimeMethod == null || selected.Name != runtimeMethod.Name || selected.IsStatic != runtimeMethod.IsStatic || selected.GetParameters().Length != runtimeMethod.GetParameters().Length || selected.GetGenericArguments().Length != runtimeMethod.GetGenericArguments().Length {
            return false
        }
        selectedOwner := selected.DeclaringType
        runtimeOwner := runtimeMethod.DeclaringType
        if !RuntimeSignatureTypesMatch(selected.ReturnType, runtimeMethod.ReturnType, selectedOwner, runtimeOwner) {
            return false
        }
        selectedParameters := selected.GetParameters()
        runtimeParameters := runtimeMethod.GetParameters()
        index := 0
        while index < selectedParameters.Length {
            if !RuntimeSignatureTypesMatch(selectedParameters[index].ParameterType, runtimeParameters[index].ParameterType, selectedOwner, runtimeOwner) {
                return false
            }
            index += 1
        }
        return true
    }

    private static func RuntimeSignatureTypesMatch(selected: Type, runtimeType: Type, selectedOwner: Type?, runtimeOwner: Type?): bool {
        if selected == null || runtimeType == null {
            return selected == runtimeType
        }
        if selected.IsGenericParameter {
            if selected.DeclaringMethod != null {
                return runtimeType.IsGenericParameter && runtimeType.DeclaringMethod != null && selected.GenericParameterPosition == runtimeType.GenericParameterPosition
            }
            if selectedOwner != null && runtimeOwner != null && selectedOwner.IsGenericType && runtimeOwner.IsGenericType {
                selectedArguments := selectedOwner.GetGenericArguments()
                runtimeArguments := runtimeOwner.GetGenericArguments()
                position := selected.GenericParameterPosition
                if position >= 0 && position < selectedArguments.Length && position < runtimeArguments.Length {
                    return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(runtimeArguments[position], runtimeType)
                }
            }
            return runtimeType.IsGenericParameter && selected.GenericParameterPosition == runtimeType.GenericParameterPosition
        }
        // Use the compiler's shared reflection-identity comparison for identical closed shapes. It
        // compares array rank and SZ-array identity recursively through generic arguments, by-ref,
        // and pointer types. The structural path below is only needed when the interpreter's
        // constructed owner substitutes a different runtime type argument.
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selected, runtimeType) {
            return true
        }
        // The interpreter represents an async `Task<T>` result as `Task<object?>`. Its await
        // members still come from the same generic method definition, with the owner type argument
        // substituted to object at runtime. Match those substitutions by owner-parameter position
        // so the selected reference-assembly method maps to the execution handle without doing a
        // second overload lookup.
        if selectedOwner != null && runtimeOwner != null && selectedOwner.IsGenericType && runtimeOwner.IsGenericType {
            selectedArguments := selectedOwner.GetGenericArguments()
            runtimeArguments := runtimeOwner.GetGenericArguments()
            if selectedArguments.Length == runtimeArguments.Length {
                index := 0
                while index < selectedArguments.Length {
                    if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selectedArguments[index], selected) && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(runtimeArguments[index], runtimeType) {
                        return true
                    }
                    index += 1
                }
            }
        }
        if selected.HasElementType || runtimeType.HasElementType {
            selectedElement: Type? = selected.GetElementType()
            runtimeElement: Type? = runtimeType.GetElementType()
            if selected.IsArray || runtimeType.IsArray {
                if !selected.IsArray || !runtimeType.IsArray || selected.GetArrayRank() != runtimeType.GetArrayRank() || selected.IsSZArray != runtimeType.IsSZArray {
                    return false
                }
            }
            return selected.HasElementType && runtimeType.HasElementType && selected.IsArray == runtimeType.IsArray && selected.IsByRef == runtimeType.IsByRef && selected.IsPointer == runtimeType.IsPointer && selectedElement != null && runtimeElement != null && RuntimeSignatureTypesMatch(selectedElement, runtimeElement, selectedOwner, runtimeOwner)
        }
        if selected.IsGenericType || runtimeType.IsGenericType {
            if !selected.IsGenericType || !runtimeType.IsGenericType || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selected.GetGenericTypeDefinition(), runtimeType.GetGenericTypeDefinition()) {
                return false
            }
            selectedArguments := selected.GetGenericArguments()
            runtimeArguments := runtimeType.GetGenericArguments()
            if selectedArguments.Length != runtimeArguments.Length {
                return false
            }
            index := 0
            while index < selectedArguments.Length {
                if !RuntimeSignatureTypesMatch(selectedArguments[index], runtimeArguments[index], selectedOwner, runtimeOwner) {
                    return false
                }
                index += 1
            }
            return true
        }
        return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(selected, runtimeType)
    }

    private static func RuntimeTypeDefinitionsMatch(left: Type?, right: Type?): bool {
        if left == null || right == null {
            return left == right
        }
        leftDefinition := left.IsGenericType ? left.GetGenericTypeDefinition() : left
        rightDefinition := right.IsGenericType ? right.GetGenericTypeDefinition() : right
        return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(leftDefinition, rightDefinition)
    }

    private async func AwaitReflectedAwaiter(awaiter: object, pattern: AwaitablePatternBinding): Task<object?> {
        isCompletedGetter := SelectedRuntimeMethodFor(pattern.IsCompletedGetter, awaiter.GetType())
        getResult := SelectedRuntimeMethodFor(pattern.GetResult, awaiter.GetType())
        completionSlot := pattern.CompletionSlot
        if isCompletedGetter == null || getResult == null || completionSlot == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected awaiter members do not match the runtime awaiter"))
        }
        isCompleted := Convert.ToBoolean(isCompletedGetter.Invoke(awaiter, null))
        if !isCompleted {
            completion := new TaskCompletionSource<object?>(TaskCreationOptions.RunContinuationsAsynchronously)
            continuation := CreateAwaiterContinuation(completion)
            if !RegisterReflectedAwaiterContinuation(awaiter, pattern, continuation) {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected awaiter completion interface is unavailable at runtime"))
            }
            await completion.Task
        }
        try {
            return getResult.Invoke(awaiter, null)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    // The shared binder's slot is resolved from the reference model, which can be a
    // MetadataLoadContext. Invoke the matching CLR interface contract on the runtime awaiter so
    // dispatch follows the runtime interface map (including explicit implementations) without
    // invoking a metadata-only MethodInfo.
    private static func RegisterReflectedAwaiterContinuation(awaiter: object, pattern: AwaitablePatternBinding, continuation: Action): bool {
        if awaiter == null || pattern == null || pattern.CompletionSlot == null || continuation == null {
            return false
        }
        if pattern.IsCritical {
            criticalAwaiter := awaiter as ICriticalNotifyCompletion
            if criticalAwaiter == null {
                return false
            }
            criticalAwaiter.UnsafeOnCompleted(continuation)
            return true
        }
        notifyAwaiter := awaiter as INotifyCompletion
        if notifyAwaiter == null {
            return false
        }
        notifyAwaiter.OnCompleted(continuation)
        return true
    }

    private static func AwaitablePatternAt(semanticModel: SemanticModel?, awaitNode: AwaitExpression?): AnalyzerAwaitablePatternBinding? {
        if semanticModel == null || awaitNode == null {
            return null
        }
        selected: AnalyzerAwaitablePatternBinding? = null
        if AwaitablePatternBinder.TryGetAnalyzerBindingAt(semanticModel, awaitNode.Line, awaitNode.Column, out selected) {
            return selected
        }
        return null
    }

    // A source method can be interpreted under a model entry selected by its declaration while its
    // nested construction was recorded in the containing file's model. Search the already-bound
    // semantic models by the exact source position; this retrieves the analyzer's answer and does
    // not perform constructor or interface matching in the playground.
    private func ConstructionBindingAt(line: int, column: int, preferredModel: SemanticModel?): AnalyzerConstructionBinding? {
        selected: AnalyzerConstructionBinding? = null
        if preferredModel != null && preferredModel.TryGetConstructionBindingAt(line, column, out selected) && selected != null {
            return selected
        }
        for modelEntry in semanticModelsByDeclaration {
            if modelEntry.Value.TryGetConstructionBindingAt(line, column, out selected) && selected != null {
                return selected
            }
        }
        return null
    }

    private async func AwaitSourceAwaitable(value: RuntimeObject, pattern: AnalyzerAwaitablePatternBinding): Task<object?> {
        getAwaiter := pattern.GetAwaiterDeclaration
        if getAwaiter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("shared source awaitable binding has no GetAwaiter declaration"))
        }
        awaiterValue: object? = null
        if pattern.GetAwaiterIsExtension {
            arguments := new object?[](1)
            arguments[0] = value
            awaiterValue = InvokeFunction(getAwaiter, arguments, null, 0)
        } else {
            awaiterValue = InvokeFunction(getAwaiter, new object?[](0), value, 0)
        }
        awaiter := awaiterValue as RuntimeObject
        if awaiter == null {
            reflectedPattern := pattern.ReflectedAwaiter
            if reflectedPattern == null || awaiterValue == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("shared source awaitable binding has no reflected awaiter pattern"))
            }
            return await AwaitReflectedAwaiter(awaiterValue, reflectedPattern)
        }
        sourcePattern := pattern.SourceAwaiter
        if sourcePattern == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("shared source awaitable binding has no source awaiter pattern"))
        }
        isCompletedValue := ReadSourceAwaiterIsCompleted(awaiter, pattern, sourcePattern)
        if !Convert.ToBoolean(isCompletedValue) {
            completion := new TaskCompletionSource<object?>(TaskCreationOptions.RunContinuationsAsynchronously)
            continuation := CreateAwaiterContinuation(completion)
            completionArguments := new object?[](1)
            completionArguments[0] = continuation
            completionFunction := sourcePattern.Completion
            if completionFunction == null && awaiter.ConstructionBinding != null {
                contractType: NSharpLang.Compiler.TypeInfo? = null
                if sourcePattern.CompletionSlot.DeclaringType != null {
                    contractType = new ReflectionTypeInfo(sourcePattern.CompletionSlot.DeclaringType)
                }
                implementation := awaiter.ConstructionBinding.FindInterfaceImplementation(null, sourcePattern.CompletionSlot, contractType)
                completionFunction = implementation as FunctionDeclaration
            }
            if completionFunction == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no implementation for its selected completion interface slot"))
            }
            InvokeFunction(completionFunction, completionArguments, awaiter, 0)
            await completion.Task
        }
        getResultFunction := sourcePattern.GetResult
        if getResultFunction.Body == null && getResultFunction.ExpressionBody == null && awaiter.ConstructionBinding != null {
            implementation := awaiter.ConstructionBinding.FindInterfaceImplementation(sourcePattern.GetResult, null, pattern.AwaiterType)
            mappedGetResult := implementation as FunctionDeclaration
            if mappedGetResult != null {
                getResultFunction = mappedGetResult
            }
        }
        if getResultFunction.Body == null && getResultFunction.ExpressionBody == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no implementation for its selected GetResult interface slot"))
        }
        return InvokeFunction(getResultFunction, new object?[](0), awaiter, 0)
    }

    private func ReadSourceAwaiterIsCompleted(awaiter: RuntimeObject, pattern: AnalyzerAwaitablePatternBinding, sourcePattern: SourceAwaiterPatternBinding): object? {
        if awaiter == null || pattern == null || sourcePattern == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no selected IsCompleted slot"))
        }
        selected := pattern.IsCompleted
        if selected == null || selected.Member == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no selected IsCompleted member"))
        }
        slot: Declaration? = sourcePattern.IsCompleted
        if AwaitablePatternBinder.IsSourceInterfaceTypeInfo(selected.Owner) {
            if awaiter.ConstructionBinding == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no analyzer-bound interface implementation map"))
            }
            implementation := awaiter.ConstructionBinding.FindInterfaceImplementation(slot, null, pattern.AwaiterType)
            property := implementation as PropertyDeclaration
            if property != null {
                return ReadRuntimeProperty(awaiter, property, 0)
            }
            field := implementation as FieldDeclaration
            if field != null {
                value: object? = null
                if awaiter.Fields.TryGetValue(field.Name, out value) {
                    return value
                }
            }
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no implementation for its selected IsCompleted interface slot"))
        }
        property := slot as PropertyDeclaration
        if property != null {
            return ReadRuntimeProperty(awaiter, property, 0)
        }
        field := slot as FieldDeclaration
        if field != null {
            value: object? = null
            if awaiter.Fields.TryGetValue(field.Name, out value) {
                return value
            }
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("source awaiter has no selected IsCompleted implementation"))
    }

    private static func RethrowInvocationFailure(failure: TargetInvocationException) {
        if failure.InnerException != null {
            ExceptionDispatchInfo.Capture(failure.InnerException).Throw()
        }
        throw failure
    }

    private static func CreateAwaiterContinuation(completion: TaskCompletionSource<object?>): Action {
        return PlaygroundAwaiterCompletionSignal.CreateAction(completion)
    }

    private static func ReadClrProperty(target: object, name: string): object?[] {
        result := new object?[](2)
        result[0] = false
        result[1] = null
        property := target.GetType().GetProperty(name, BindingFlags.Public | BindingFlags.Instance)
        if property == null || property.GetIndexParameters().Length != 0 {
            return result
        }
        try {
            result[0] = true
            result[1] = property.GetValue(target)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return result
    }

    private static func ReadBoundValue(environment: RuntimeEnvironment, name: string): object? {
        value: object? = null
        environment.TryGet(name, out value)
        return value
    }

    private func InvokeFunction(function: FunctionDeclaration, arguments: IReadOnlyList<object?>, receiver: RuntimeObject?, depth: int): object? {
        if depth > PlaygroundRunFacts.MaxCallDepth() {
            throw Unsupported(PlaygroundRunFacts.CallDepthExceeded())
        }
        if function.Parameters.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.WrongArgumentCount(function.Name, arguments.Count))
        }

        parentEnvironment: RuntimeEnvironment? = null
        if receiver != null {
            parentEnvironment = receiver.Environment
        }
        environment := new RuntimeEnvironment(parentEnvironment)
        semanticModel: SemanticModel? = null
        if semanticModelsByDeclaration.TryGetValue(function, out semanticModel) {
            environment.SetSemanticModel(semanticModel)
        }
        if receiver != null {
            environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), receiver)
        }

        i := 0
        while i < function.Parameters.Count {
            environment.Declare(function.Parameters[i].Name, arguments[i])
            i = i + 1
        }

        try {
            if function.ExpressionBody != null {
                return Evaluate(function.ExpressionBody, environment, depth + 1)
            }
            if function.Body != null {
                ExecuteBlock(function.Body, environment, depth + 1)
            }
        } catch caught: Exception {
            signal := caught as ReturnSignal
            if signal != null {
                return signal.Value
            }
            throw caught
        }
        return null
    }

    private func InvokeLambda(runtimeLambda: RuntimeLambda, arguments: IReadOnlyList<object?>, depth: int): object? {
        lambda := runtimeLambda.Declaration
        if depth > PlaygroundRunFacts.MaxCallDepth() {
            throw Unsupported(PlaygroundRunFacts.CallDepthExceeded())
        }
        if lambda.Parameters.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.WrongArgumentCount("lambda", arguments.Count))
        }
        environment := new RuntimeEnvironment(runtimeLambda.Closure)
        index := 0
        while index < lambda.Parameters.Count {
            environment.Declare(lambda.Parameters[index].Name, arguments[index])
            index += 1
        }
        try {
            if lambda.ExpressionBody != null {
                return Evaluate(lambda.ExpressionBody, environment, depth + 1)
            }
            if lambda.BlockBody != null {
                ExecuteBlock(lambda.BlockBody, environment, depth + 1)
            }
        } catch caught: Exception {
            signal := caught as ReturnSignal
            if signal != null {
                return signal.Value
            }
            throw caught
        }
        return null
    }

    private func ExecuteBlock(block: BlockStatement, environment: RuntimeEnvironment, depth: int) {
        for statement in block.Statements {
            ExecuteStatement(statement, environment, depth)
        }
    }

    private func ExecuteStatement(statement: Statement, environment: RuntimeEnvironment, depth: int) {
        Step(statement)

        block := statement as BlockStatement
        if block != null {
            ExecuteBlock(block, new RuntimeEnvironment(environment), depth + 1)
            return
        }

        variable := statement as VariableDeclarationStatement
        if variable != null {
            value: object? = null
            if variable.Initializer != null {
                value = Evaluate(variable.Initializer, environment, depth)
            }
            environment.Declare(variable.Name, value)
            return
        }

        tuple := statement as TupleDeconstructionStatement
        if tuple != null {
            ExecuteTupleDeconstruction(tuple, environment, depth)
            return
        }

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            Evaluate(expressionStatement.Expression, environment, depth)
            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            value := Evaluate(printStatement.Value, environment, depth)
            WriteLine(FormatValue(value))
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            value: object? = null
            if returnStatement.Value != null {
                value = Evaluate(returnStatement.Value, environment, depth)
            }
            throw new ReturnSignal(value)
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            if IsTruthy(Evaluate(ifStatement.Condition, environment, depth)) {
                ExecuteStatement(ifStatement.ThenStatement, environment, depth + 1)
            } else if ifStatement.ElseStatement != null {
                ExecuteStatement(ifStatement.ElseStatement, environment, depth + 1)
            }
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            ExecuteForeach(foreachStatement, environment, depth)
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            thrown := throwStatement.Expression
            if thrown == null {
                // A bare `throw` rethrows the exception a catch is handling, and the runner runs no
                // catch; before, it reached `Evaluate` with no expression at all.
                throw Unsupported(PlaygroundRunFacts.UnsupportedStatement("a bare rethrow"))
            }
            throw new PlaygroundThrownException(Evaluate(thrown, environment, depth))
        }

        emptyStatement := statement as EmptyStatement
        if emptyStatement != null {
            return
        }

        statementType := statement.GetType()
        statementTypeName := statementType.Name
        unsupportedFault := PlaygroundRunFacts.UnsupportedStatement(statementTypeName)
        throw Unsupported(unsupportedFault)
    }

    private func ExecuteTupleDeconstruction(tuple: TupleDeconstructionStatement, environment: RuntimeEnvironment, depth: int) {
        call := tuple.Initializer as CallExpression
        if tuple.Names.Count == 2 && call != null {
            try {
                result := Evaluate(call, environment, depth)
                if !PlaygroundRunFacts.IsDiscardName(tuple.Names[0]) {
                    environment.Declare(tuple.Names[0], result)
                }
                if !PlaygroundRunFacts.IsDiscardName(tuple.Names[1]) {
                    environment.Declare(tuple.Names[1], null)
                }
            } catch caught: Exception {
                thrown := caught as PlaygroundThrownException
                if thrown == null {
                    throw caught
                }
                if !PlaygroundRunFacts.IsDiscardName(tuple.Names[0]) {
                    environment.Declare(tuple.Names[0], null)
                }
                if !PlaygroundRunFacts.IsDiscardName(tuple.Names[1]) {
                    environment.Declare(tuple.Names[1], thrown.Value)
                }
            }
            return
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedDeconstruction())
    }

    private func ExecuteForeach(foreachStatement: ForeachStatement, environment: RuntimeEnvironment, depth: int) {
        collection := Evaluate(foreachStatement.Collection, environment, depth)
        values := collection as IReadOnlyList<object?>
        if values == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedForeachCollection())
        }
        for value in values {
            loopEnvironment := new RuntimeEnvironment(environment)
            loopEnvironment.Declare(foreachStatement.VariableName, value)
            ExecuteStatement(foreachStatement.Body, loopEnvironment, depth + 1)
        }
    }

    private func Evaluate(expression: Expression, environment: RuntimeEnvironment, depth: int): object? {
        Step(expression)

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return ResolveIdentifier(PlaygroundRunFacts.ReceiverBindingName(), environment)
        }

        literal := expression as IntLiteralExpression
        if literal != null {
            return int.Parse(literal.Value)
        }
        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return Double.Parse(floatLiteral.Value, CultureInfo.InvariantCulture)
        }
        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return PlaygroundRunFacts.DecodeStringLiteralText(stringLiteral.Value, stringLiteral.IsRaw)
        }
        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            if charLiteral.Value.Length == 0 {
                return '\0'
            }
            return charLiteral.Value[0]
        }
        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return boolLiteral.Value
        }
        if expression as NullLiteralExpression != null {
            return null
        }
        identifier := expression as IdentifierExpression
        if identifier != null {
            return ResolveIdentifierExpression(identifier, environment)
        }
        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return EvaluateInterpolatedString(interpolated, environment, depth)
        }
        binary := expression as BinaryExpression
        if binary != null {
            return EvaluateBinary(binary, environment, depth)
        }
        unary := expression as UnaryExpression
        if unary != null {
            return EvaluateUnary(unary, environment, depth)
        }
        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return Evaluate(parenthesized.Inner, environment, depth)
        }
        lambda := expression as LambdaExpression
        if lambda != null {
            return new RuntimeLambda(lambda, environment)
        }
        assignment := expression as AssignmentExpression
        if assignment != null {
            return EvaluateAssignment(assignment, environment, depth)
        }
        call := expression as CallExpression
        if call != null {
            return EvaluateCall(call, environment, depth)
        }
        member := expression as MemberAccessExpression
        if member != null {
            return EvaluateMemberAccess(member, environment, depth)
        }
        newExpression := expression as NewExpression
        if newExpression != null {
            return EvaluateNew(newExpression, environment, depth)
        }
        initializer := expression as ObjectInitializerExpression
        if initializer != null {
            return EvaluateObjectInitializer(initializer, environment, depth)
        }
        array := expression as ArrayLiteralExpression
        if array != null {
            values := new object?[](array.Elements.Count)
            i := 0
            while i < array.Elements.Count {
                values[i] = Evaluate(array.Elements[i], environment, depth)
                i = i + 1
            }
            return values
        }
        withExpression := expression as WithExpression
        if withExpression != null {
            return EvaluateWith(withExpression, environment, depth)
        }
        matchExpression := expression as MatchExpression
        if matchExpression != null {
            return EvaluateMatch(matchExpression, environment, depth)
        }
        throwExpression := expression as ThrowExpression
        if throwExpression != null {
            throw new PlaygroundThrownException(Evaluate(throwExpression.Expression, environment, depth))
        }
        expressionTypeName := expression.GetType().Name
        throw Unsupported(PlaygroundRunFacts.UnsupportedExpression(expressionTypeName))
    }

    private func ResolveIdentifier(name: string, environment: RuntimeEnvironment): object? {
        value: object? = null
        if environment.TryGet(name, out value) {
            return value
        }
        declaration: Declaration? = null
        if types.TryGetValue(name, out declaration) {
            return new RuntimeType(declaration)
        }
        throw Unsupported(PlaygroundRunFacts.UnresolvedName(name))
    }

    private func ResolveIdentifierExpression(identifier: IdentifierExpression, environment: RuntimeEnvironment): object? {
        value: object? = null
        if environment.TryGet(identifier.Name, out value) {
            return value
        }

        semanticModel := environment.SemanticModel
        selected: FunctionTypeInfo? = null
        if semanticModel != null && semanticModel.TryGetCallableReferenceBindingAt(identifier.Line, identifier.Column, out selected) && selected != null {
            function := selected.SourceDeclaration as FunctionDeclaration
            if function == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected source method group has no declaration"))
            }
            return new RuntimeFunction(function, null)
        }

        return ResolveIdentifier(identifier.Name, environment)
    }

    private func EvaluateInterpolatedString(interpolated: InterpolatedStringExpression, environment: RuntimeEnvironment, depth: int): string {
        builder := new StringBuilder()
        for part in interpolated.Parts {
            textPart := part as InterpolatedStringText
            if textPart != null {
                builder.Append(textPart.Text)
            } else {
                hole := part as InterpolatedStringHole
                if hole != null {
                    builder.Append(FormatValue(Evaluate(hole.Expression, environment, depth)))
                }
            }
        }
        return builder.ToString()
    }

    private func EvaluateBinary(binary: BinaryExpression, environment: RuntimeEnvironment, depth: int): object? {
        left := Evaluate(binary.Left, environment, depth)
        right := Evaluate(binary.Right, environment, depth)
        return EvaluateBinaryValues(binary, left, right)
    }

    private func EvaluateBinaryValues(binary: BinaryExpression, left: object?, right: object?): object? {
        if binary.Operator == BinaryOperator.Add {
            if left as string != null || right as string != null {
                return FormatValue(left) + FormatValue(right)
            }
            return ToNumber(left) + ToNumber(right)
        }
        if binary.Operator == BinaryOperator.Subtract {
            return ToNumber(left) - ToNumber(right)
        }
        if binary.Operator == BinaryOperator.Multiply {
            return ToNumber(left) * ToNumber(right)
        }
        if binary.Operator == BinaryOperator.Divide {
            return Divide(left, right)
        }
        if binary.Operator == BinaryOperator.Modulo {
            return ToInt(left) % ToInt(right)
        }
        if binary.Operator == BinaryOperator.Equal {
            return ValuesEqual(left, right)
        }
        if binary.Operator == BinaryOperator.NotEqual {
            return !ValuesEqual(left, right)
        }
        if binary.Operator == BinaryOperator.Less {
            return ToNumber(left) < ToNumber(right)
        }
        if binary.Operator == BinaryOperator.LessOrEqual {
            return ToNumber(left) <= ToNumber(right)
        }
        if binary.Operator == BinaryOperator.Greater {
            return ToNumber(left) > ToNumber(right)
        }
        if binary.Operator == BinaryOperator.GreaterOrEqual {
            return ToNumber(left) >= ToNumber(right)
        }
        if binary.Operator == BinaryOperator.And {
            return IsTruthy(left) && IsTruthy(right)
        }
        if binary.Operator == BinaryOperator.Or {
            return IsTruthy(left) || IsTruthy(right)
        }
        binaryOperatorValue := binary.Operator as object
        binaryOperatorName := binaryOperatorValue.ToString() ?? ""
        throw Unsupported(PlaygroundRunFacts.UnsupportedBinaryOperator(binaryOperatorName))
    }

    private func EvaluateUnary(unary: UnaryExpression, environment: RuntimeEnvironment, depth: int): object? {
        value := Evaluate(unary.Operand, environment, depth)
        if unary.Operator == UnaryOperator.Negate {
            return -ToNumber(value)
        }
        if unary.Operator == UnaryOperator.Not {
            return !IsTruthy(value)
        }
        unaryOperatorValue := unary.Operator as object
        unaryOperatorName := unaryOperatorValue.ToString() ?? ""
        throw Unsupported(PlaygroundRunFacts.UnsupportedUnaryOperator(unaryOperatorName))
    }

    private static func Divide(left: object?, right: object?): object {
        divisor := ToNumber(right)
        useIntegerDivision := PlaygroundRunFacts.UseIntegerDivision(IsIntegral(left), IsIntegral(right))
        if PlaygroundRunFacts.DivisionFaults(useIntegerDivision, divisor) {
            throw new PlaygroundThrownException(new RuntimeError(PlaygroundRunFacts.DivisionByZeroMessage()))
        }
        if useIntegerDivision {
            return ToInt(left) / ToInt(right)
        }
        return ToNumber(left) / divisor
    }

    private func EvaluateAssignment(assignment: AssignmentExpression, environment: RuntimeEnvironment, depth: int): object? {
        value := Evaluate(assignment.Value, environment, depth)
        if assignment.Operator != AssignmentOperator.Assign {
            current: object? = null
            identifier := assignment.Target as IdentifierExpression
            if identifier != null {
                current = ResolveIdentifier(identifier.Name, environment)
            } else {
                member := assignment.Target as MemberAccessExpression
                if member != null {
                    current = EvaluateMemberAccess(member, environment, depth)
                }
            }
            if assignment.Operator == AssignmentOperator.AddAssign {
                value = ToNumber(current) + ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.SubtractAssign {
                value = ToNumber(current) - ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.MultiplyAssign {
                value = ToNumber(current) * ToNumber(value)
            } else if assignment.Operator == AssignmentOperator.DivideAssign {
                value = Divide(current, value)
            } else {
                assignmentOperatorValue := assignment.Operator as object
                assignmentOperatorName := assignmentOperatorValue.ToString() ?? ""
                throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentOperator(assignmentOperatorName))
            }
        }

        identifier := assignment.Target as IdentifierExpression
        if identifier != null {
            environment.Set(identifier.Name, value)
            return value
        }
        member := assignment.Target as MemberAccessExpression
        if member != null {
            SetMember(member, environment, depth, value)
            return value
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentTarget())
    }

    private func EvaluateCall(call: CallExpression, environment: RuntimeEnvironment, depth: int): object? {
        arguments := new object?[](call.Arguments.Count)
        i := 0
        while i < call.Arguments.Count {
            arguments[i] = Evaluate(call.Arguments[i].Value, environment, depth)
            i = i + 1
        }
        identifier := call.Callee as IdentifierExpression
        if identifier != null {
            boundValue: object? = null
            if environment.TryGet(identifier.Name, out boundValue) {
                callable := boundValue as Delegate
                if callable != null {
                    return callable.DynamicInvoke(ToInvocationArguments(arguments))
                }
                runtimeFunction := boundValue as RuntimeFunction
                if runtimeFunction != null {
                    return InvokeFunction(runtimeFunction.Declaration, arguments, runtimeFunction.Receiver, depth)
                }
                runtimeLambda := boundValue as RuntimeLambda
                if runtimeLambda != null {
                    return InvokeLambda(runtimeLambda, arguments, depth)
                }
            }
            selectedBinding: AnalyzerInvocationBinding? = null
            semanticModel := environment.SemanticModel
            if semanticModel != null && semanticModel.TryGetInvocationBindingAt(call.Line, call.Column, out selectedBinding) && selectedBinding != null {
                return InvokeBoundInvocation(selectedBinding, BoundInvocationReceiver(selectedBinding, null, environment), arguments, depth, call)
            }
            throw Unsupported(PlaygroundRunFacts.UnknownFunction(identifier.Name))
        }
        member := call.Callee as MemberAccessExpression
        if member != null {
            return CallMember(member, arguments, environment, depth, call)
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedCallee())
    }

    private func CallMember(member: MemberAccessExpression, arguments: IReadOnlyList<object?>, environment: RuntimeEnvironment, depth: int, call: CallExpression): object? {
        selectedBinding: AnalyzerInvocationBinding? = null
        semanticModel := environment.SemanticModel
        if semanticModel != null {
            semanticModel.TryGetInvocationBindingAt(call.Line, call.Column, out selectedBinding)
        }
        if IsFrameworkTaskStaticInvocation(selectedBinding) || selectedBinding == null && IsFrameworkTaskStaticIdentifier(member.Object, semanticModel) {
            if selectedBinding == null {
                throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("the analyzer did not select a Task or ValueTask overload"), call)
            }
            return InvokeBoundInvocation(selectedBinding, null, arguments, depth, call)
        }
        target := Evaluate(member.Object, environment, depth)
        if selectedBinding != null {
            return InvokeBoundInvocation(selectedBinding, target, arguments, depth, call)
        }
        if member.MemberName == "GetAwaiter" {
            throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("GetAwaiter call lacks an analyzer binding"), call)
        }
        throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("the browser runner has no analyzer-selected method for '" + member.MemberName + "'"), call)
    }

    private func BoundInvocationReceiver(binding: AnalyzerInvocationBinding, explicitReceiver: object?, environment: RuntimeEnvironment): object? {
        if explicitReceiver != null || binding == null || binding.IsExtension || binding.SourceFunction == null || binding.SourceFunction.SourceIsStatic || string.IsNullOrEmpty(binding.SourceFunction.SourceContainingType) {
            return explicitReceiver
        }
        receiverValue: object? = null
        if environment != null && environment.TryGet(PlaygroundRunFacts.ReceiverBindingName(), out receiverValue) {
            return receiverValue
        }
        return explicitReceiver
    }

    // The analyzer binding owns both overload selection and argument placement. The playground only
    // checks the selected parameter's direction through the same shared C# ref-kind rule before it
    // invokes that bound member.
    private func BoundInvocationRefKindsAreCompatible(binding: AnalyzerInvocationBinding, call: CallExpression): bool {
        if binding == null || call == null || binding.ParameterIndexByArgument == null || binding.ParameterIndexByArgument.Length != call.Arguments.Count {
            return false
        }

        sourceFunction := binding.SourceFunction
        sourceModifiers := sourceFunction == null ? null : sourceFunction.ParameterModifiers
        reflectedParameters: ParameterInfo[]? = null
        if sourceFunction == null {
            reflectedMethod := binding.ReflectedMethod
            if reflectedMethod == null {
                return false
            }
            reflectedParameters = reflectedMethod.GetParameters()
        }

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            parameterIndex := binding.ParameterIndexByArgument[argumentIndex]
            if parameterIndex < 0 {
                return false
            }

            argumentModifier := call.Arguments[argumentIndex].Modifier
            if sourceFunction != null {
                parameterModifier := NSharpLang.Compiler.Ast.ParameterModifier.None
                if sourceModifiers != null && parameterIndex < sourceModifiers.Count {
                    parameterModifier = sourceModifiers[parameterIndex]
                }
                if RefKindCompatibilityFacts.Classify(parameterModifier, argumentModifier) == RefKindCompatibilityResult.Incompatible {
                    return false
                }
            } else {
                parameters := reflectedParameters
                if parameters == null || parameterIndex >= parameters.Length || RefKindCompatibilityFacts.ClassifyReflectedParameter(parameters[parameterIndex], argumentModifier) == RefKindCompatibilityResult.Incompatible {
                    return false
                }
            }

            argumentIndex += 1
        }

        return true
    }

    private func InvokeBoundInvocation(binding: AnalyzerInvocationBinding, target: object?, arguments: IReadOnlyList<object?>, depth: int, call: CallExpression): object? {
        if binding == null || arguments == null || !BoundInvocationRefKindsAreCompatible(binding, call) {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected invocation could not be executed"))
        }
        runtimeArguments := new object?[](arguments.Count)
        index := 0
        while index < arguments.Count {
            runtimeArguments[index] = arguments[index]
            index += 1
        }

        sourceFunctionType := binding.SourceFunction
        if sourceFunctionType != null {
            function := sourceFunctionType.SourceDeclaration
            if function == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected source method has no declaration"))
            }
            executionFunction := function
            executionReceiver := target as RuntimeObject
            if !binding.IsExtension && executionReceiver != null && executionReceiver.ConstructionBinding != null && AwaitablePatternBinder.IsVirtualSourceFunction(function) {
                implementation := executionReceiver.ConstructionBinding.FindVirtualImplementation(function) as FunctionDeclaration
                if implementation == null {
                    throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected source virtual slot has no implementation mapping"))
                }
                if implementation != null && implementation.Body != null {
                    executionFunction = implementation
                }
            }
            // An interface call binds to its declared slot, while the runtime receiver supplies
            // that slot's source implementation. Keep the analyzer's selected slot, then dispatch
            // it on the concrete source object the same way a CLR callvirt does.
            if !binding.IsExtension && executionReceiver != null && function.Body == null {
                constructionBinding := executionReceiver.ConstructionBinding
                if constructionBinding != null {
                    implementation := constructionBinding.FindInterfaceImplementation(function, null, binding.SourceSlotOwnerType) as FunctionDeclaration
                    if implementation != null && implementation.Body != null {
                        executionFunction = implementation
                    }
                }
                if Object.ReferenceEquals(executionFunction, function) {
                    throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected source interface slot has no implementation mapping"))
                }
            }
            invocationArguments := binding.IsExtension ? PrependRuntimeArgument(target, runtimeArguments) : runtimeArguments
            receiver := binding.IsExtension ? null : executionReceiver
            if !binding.IsExtension && !sourceFunctionType.SourceIsStatic && !string.IsNullOrEmpty(sourceFunctionType.SourceContainingType) && receiver == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected source method has no runtime receiver"))
            }
            if AnalyzerAmbientContext.HasModifier(executionFunction, Modifiers.Async) {
                return InvokeAsyncFunctionValue(executionFunction, invocationArguments, receiver, depth)
            }
            return InvokeFunction(executionFunction, invocationArguments, receiver, depth)
        }

        selectedMethod := binding.ReflectedMethod
        if selectedMethod == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected reflected method is unavailable"))
        }
        if IsTaskRunMethod(selectedMethod) && runtimeArguments.Length > 0 {
            callback := runtimeArguments[0]
            if callback as RuntimeFunction != null || callback as RuntimeLambda != null {
                shape := SelectedTaskRunDelegateShape(selectedMethod)
                if shape == 0 || !TaskRunArgumentsMatch(selectedMethod, runtimeArguments) {
                    throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run overload has a source callable shape the browser runner does not support"), call)
                }
                return InvokeSelectedTaskRun(selectedMethod, callback, runtimeArguments, depth)
            }
        }
        runtimeMethod: MethodInfo? = null
        invocationReceiver: object? = target
        invocationArguments := runtimeArguments
        if binding.IsExtension {
            runtimeMethod = SelectedRuntimeClosedExtensionMethodFor(selectedMethod)
            invocationReceiver = null
            invocationArguments = PrependRuntimeArgument(target, runtimeArguments)
        } else if target != null {
            runtimeMethod = SelectedRuntimeMethodFor(selectedMethod, target.GetType())
        } else {
            selectedOwner := selectedMethod.DeclaringType
            runtimeOwner: Type = null
            if selectedOwner != null && TryResolvePlaygroundRuntimeTypeFromMetadata(selectedOwner, out runtimeOwner) {
                runtimeMethod = SelectedRuntimeMethodFor(selectedMethod, runtimeOwner)
            }
        }
        if runtimeMethod == null {
            throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected method '" + selectedMethod.ToString() + "' has no runtime metadata match for its exact signature"), call)
        }
        if runtimeMethod.IsStatic != (invocationReceiver == null) {
            throw UnsupportedAt(PlaygroundRunFacts.UnsupportedExpression("the selected method '" + selectedMethod.ToString() + "' maps to a runtime method with an incompatible static/instance receiver"), call)
        }
        try {
            return runtimeMethod.Invoke(invocationReceiver, invocationArguments)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    private static func IsTaskRunMethod(selectedMethod: MethodInfo): bool {
        if selectedMethod == null || selectedMethod.Name != "Run" || selectedMethod.ContainsGenericParameters {
            return false
        }
        owner := selectedMethod.DeclaringType
        return owner != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(owner, typeof(Task))
    }

    // The analyzer has already chosen the Task.Run overload. Classify that exact closed signature
    // to build a matching CLR delegate around the interpreter callable; no overload resolution is
    // repeated here. Shapes: Action, Func<TResult>, Func<Task>, Func<Task<TResult>>.
    private static func SelectedTaskRunDelegateShape(selectedMethod: MethodInfo): int {
        if !IsTaskRunMethod(selectedMethod) {
            return 0
        }
        parameters := selectedMethod.GetParameters()
        if parameters.Length < 1 || parameters.Length > 2 || parameters.Length == 2 && !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(parameters[1].ParameterType, typeof(CancellationToken)) {
            return 0
        }
        delegateType := parameters[0].ParameterType
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(delegateType, typeof(Action)) {
            return IsTaskType(selectedMethod.ReturnType) ? 1 : 0
        }
        if !delegateType.IsGenericType || !TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(delegateType.GetGenericTypeDefinition(), typeof(Func<int>).GetGenericTypeDefinition()) {
            return 0
        }
        delegateResult := delegateType.GetGenericArguments()[0]
        if TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(delegateResult, typeof(Task)) {
            return IsTaskType(selectedMethod.ReturnType) ? 3 : 0
        }
        if IsConstructedTaskType(delegateResult) {
            return IsConstructedTaskType(selectedMethod.ReturnType) ? 4 : 0
        }
        return IsConstructedTaskType(selectedMethod.ReturnType) ? 2 : 0
    }

    private static func IsConstructedTaskType(candidate: Type): bool {
        return candidate != null && candidate.IsGenericType && !candidate.IsGenericTypeDefinition && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(candidate.GetGenericTypeDefinition(), typeof(Task<int>).GetGenericTypeDefinition())
    }

    private static func IsTaskType(candidate: Type): bool {
        return candidate != null && TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(candidate, typeof(Task))
    }

    private static func TaskRunArgumentsMatch(selectedMethod: MethodInfo, arguments: object?[]): bool {
        parameters := selectedMethod.GetParameters()
        if parameters.Length != arguments.Length {
            return false
        }
        if parameters.Length == 2 {
            return arguments[1] is CancellationToken
        }
        return true
    }

    private func InvokeSelectedTaskRun(selectedMethod: MethodInfo, callback: object, arguments: object?[], depth: int): object {
        shape := SelectedTaskRunDelegateShape(selectedMethod)
        hasCancellationToken := arguments.Length == 2
        cancellationToken := CancellationToken.None
        if hasCancellationToken {
            cancellationToken = (CancellationToken)arguments[1]
        }

        if shape == 1 {
            work := CreateTaskRunAction(callback, depth)
            if hasCancellationToken {
                return Task.Run(work, cancellationToken)
            }
            return Task.Run(work)
        }
        if shape == 2 {
            return InvokeTaskRunFuncResult(selectedMethod, callback, depth, cancellationToken, hasCancellationToken)
        }
        if shape == 3 {
            work := CreateTaskRunTaskFunction(callback, depth)
            if hasCancellationToken {
                return Task.Run(work, cancellationToken)
            }
            return Task.Run(work)
        }
        if shape == 4 {
            return InvokeTaskRunFuncTaskResult(selectedMethod, callback, depth, cancellationToken, hasCancellationToken)
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run overload cannot be adapted to a browser source callable"))
    }

    private func CreateTaskRunAction(callback: object, depth: int): Action {
        action := CreateTaskRunDelegate(callback, depth, typeof(Action), "InvokeAction") as Action
        if action == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run Action adapter"))
        }
        return action
    }

    private func CreateTaskRunTaskFunction(callback: object, depth: int): Func<Task> {
        function := CreateTaskRunDelegate(callback, depth, typeof(Func<Task>), "InvokeTask") as Func<Task>
        if function == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run Func<Task> adapter"))
        }
        return function
    }

    private func CreateTaskRunDelegate(callback: object, depth: int, delegateType: Type, methodName: string): Delegate {
        adapter := new RuntimeTaskRunCallback(this, callback, depth)
        method := typeof(RuntimeTaskRunCallback).GetMethod(methodName, BindingFlags.Public | BindingFlags.Instance)
        if method == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run delegate adapter"))
        }
        created := Delegate.CreateDelegate(delegateType, adapter, method)
        if created == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run delegate adapter"))
        }
        return created
    }

    private func InvokeTaskRunFuncResult(selectedMethod: MethodInfo, callback: object, depth: int, cancellationToken: CancellationToken, hasCancellationToken: bool): object {
        runtimeMethod := SelectedRuntimeMethodFor(selectedMethod, typeof(Task))
        if runtimeMethod == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<TResult>) overload has no runtime method mapping"))
        }
        runtimeParameters := runtimeMethod.GetParameters()
        if runtimeParameters.Length < 1 || runtimeParameters.Length > 2 {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<TResult>) overload has an unsupported runtime signature"))
        }
        delegateType := runtimeParameters[0].ParameterType
        resultTypeArguments := delegateType.GetGenericArguments()
        if resultTypeArguments.Length != 1 {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<TResult>) overload has an unsupported delegate type"))
        }
        adapter := new RuntimeTaskRunCallback(this, callback, depth)
        callbackMethod := typeof(RuntimeTaskRunCallback).GetMethod("InvokeResult", BindingFlags.Public | BindingFlags.Instance)
        if callbackMethod == null || !callbackMethod.IsGenericMethodDefinition {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not find the Task.Run generic result adapter"))
        }
        closedCallbackMethod := callbackMethod.MakeGenericMethod(resultTypeArguments)
        callbackDelegate := Delegate.CreateDelegate(delegateType, adapter, closedCallbackMethod)
        if callbackDelegate == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run Func<TResult> adapter"))
        }
        runtimeArguments := new object?[](runtimeParameters.Length)
        runtimeArguments[0] = callbackDelegate
        if runtimeParameters.Length == 2 {
            if !hasCancellationToken {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run overload requires a cancellation token"))
            }
            runtimeArguments[1] = cancellationToken
        }
        try {
            return runtimeMethod.Invoke(null, runtimeArguments)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    private func InvokeTaskRunFuncTaskResult(selectedMethod: MethodInfo, callback: object, depth: int, cancellationToken: CancellationToken, hasCancellationToken: bool): object {
        runtimeMethod := SelectedRuntimeMethodFor(selectedMethod, typeof(Task))
        if runtimeMethod == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task<TResult>>) overload has no runtime method mapping"))
        }
        runtimeParameters := runtimeMethod.GetParameters()
        if runtimeParameters.Length < 1 || runtimeParameters.Length > 2 {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task<TResult>>) overload has an unsupported runtime signature"))
        }
        delegateType := runtimeParameters[0].ParameterType
        delegateArguments := delegateType.GetGenericArguments()
        if delegateArguments.Length != 1 || !delegateArguments[0].IsGenericType {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task<TResult>>) overload has an unsupported delegate type"))
        }
        resultTypeArguments := delegateArguments[0].GetGenericArguments()
        if resultTypeArguments.Length != 1 {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task<TResult>>) overload has an unsupported task result type"))
        }
        adapter := new RuntimeTaskRunCallback(this, callback, depth)
        callbackMethod := typeof(RuntimeTaskRunCallback).GetMethod("InvokeTaskResult", BindingFlags.Public | BindingFlags.Instance)
        if callbackMethod == null || !callbackMethod.IsGenericMethodDefinition {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not find the Task.Run generic result adapter"))
        }
        closedCallbackMethod := callbackMethod.MakeGenericMethod(resultTypeArguments)
        callbackDelegate := Delegate.CreateDelegate(delegateType, adapter, closedCallbackMethod)
        if callbackDelegate == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the Task.Run Func<Task<TResult>> adapter"))
        }
        runtimeArguments := new object?[](runtimeParameters.Length)
        runtimeArguments[0] = callbackDelegate
        if runtimeParameters.Length == 2 {
            if !hasCancellationToken {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run overload requires a cancellation token"))
            }
            runtimeArguments[1] = cancellationToken
        }
        try {
            return runtimeMethod.Invoke(null, runtimeArguments)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    func InvokeTaskRunCallable(callback: object, depth: int): object? {
        emptyArguments := new object?[](0)
        runtimeFunction := callback as RuntimeFunction
        if runtimeFunction != null {
            if runtimeFunction.Declaration.Parameters.Count != 0 {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("Task.Run source callables must take no arguments"))
            }
            if AnalyzerAmbientContext.HasModifier(runtimeFunction.Declaration, Modifiers.Async) {
                return InvokeAsyncFunctionValue(runtimeFunction.Declaration, emptyArguments, runtimeFunction.Receiver, depth)
            }
            return InvokeFunction(runtimeFunction.Declaration, emptyArguments, runtimeFunction.Receiver, depth)
        }
        runtimeLambda := callback as RuntimeLambda
        if runtimeLambda != null {
            if runtimeLambda.Declaration.Parameters.Count != 0 || runtimeLambda.Declaration.IsAsync {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("Task.Run browser lambdas must take no arguments and use the synchronous lambda form"))
            }
            return InvokeLambda(runtimeLambda, emptyArguments, depth)
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("Task.Run requires a source function or lambda in the browser runner"))
    }

    func TaskRunCallableTask(callback: object, depth: int): Task {
        value := InvokeTaskRunCallable(callback, depth)
        task := value as Task
        if task == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task>) callable did not return Task"))
        }
        return task
    }

    func TaskRunCallableTaskResult<T>(callback: object, depth: int): Task<T> {
        completion := new TaskCompletionSource<T>()
        _completionWork := CompleteTaskRunCallableTaskResult<T>(callback, depth, completion)
        taskProperty := completion.GetType().GetProperty("Task", BindingFlags.Public | BindingFlags.Instance)
        if taskProperty == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not read the Task.Run result completion task"))
        }
        resultTask := taskProperty.GetValue(completion) as Task<T>
        if resultTask == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not construct the selected Task.Run result task"))
        }
        return resultTask
    }

    private async func CompleteTaskRunCallableTaskResult<T>(callback: object, depth: int, completion: object): Task {
        try {
            task := TaskRunCallableTask(callback, depth)
            await task
            resultProperty := task.GetType().GetProperty("Result", BindingFlags.Public | BindingFlags.Instance)
            if resultProperty == null || resultProperty.GetIndexParameters().Length != 0 {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the selected Task.Run(Func<Task<TResult>>) callable returned a task without a result"))
            }
            completionType := completion.GetType()
            setResult := completionType.GetMethod("TrySetResult", BindingFlags.Public | BindingFlags.Instance)
            if setResult == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the browser could not complete the selected Task.Run result task"))
            }
            resultArguments := new object?[](1)
            resultArguments[0] = resultProperty.GetValue(task)
            setResult.Invoke(completion, resultArguments)
        } catch failure: Exception {
            completionType := completion.GetType()
            exceptionParameterTypes := new Type[](1)
            exceptionParameterTypes[0] = typeof(Exception)
            setException := completionType.GetMethod("TrySetException", exceptionParameterTypes)
            if setException == null {
                throw failure
            }
            exceptionValue := failure as TargetInvocationException
            completionFailure := exceptionValue != null && exceptionValue.InnerException != null ? exceptionValue.InnerException : failure
            exceptionArguments := new object?[](1)
            exceptionArguments[0] = completionFailure
            setException.Invoke(completion, exceptionArguments)
        }
    }

    private static func IsFrameworkTaskStaticInvocation(binding: AnalyzerInvocationBinding?): bool {
        if binding == null || binding.ReflectedMethod == null || binding.ReflectedMethod.DeclaringType == null {
            return false
        }
        owner := binding.ReflectedMethod.DeclaringType
        return binding.ReflectedMethod.IsStatic && (TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(owner, typeof(Task)) || TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(owner, typeof(ValueTask)))
    }

    private static func IsFrameworkTaskStaticIdentifier(expression: Expression?, semanticModel: SemanticModel?): bool {
        identifier := expression as IdentifierExpression
        if identifier == null || semanticModel == null {
            return false
        }
        return IsStaticFrameworkTypeIdentifier(identifier, semanticModel, typeof(Task)) || IsStaticFrameworkTypeIdentifier(identifier, semanticModel, typeof(ValueTask))
    }

    private static func IsStaticFrameworkTypeIdentifier(identifier: IdentifierExpression?, semanticModel: SemanticModel?, expectedType: Type): bool {
        if identifier == null || semanticModel == null || expectedType == null {
            return false
        }
        resolved: NSharpLang.Compiler.TypeInfo? = null
        if !semanticModel.ExpressionTypes.TryGetValue((Line: identifier.Line, Column: identifier.Column), out resolved) || resolved == null {
            return false
        }
        return TypeInfoMatchesRuntimeDefinition(resolved, expectedType)
    }

    private static func TypeInfoMatchesRuntimeDefinition(typeInfo: NSharpLang.Compiler.TypeInfo?, runtimeType: Type): bool {
        if typeInfo == null || runtimeType == null {
            return false
        }
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return TypeInfoMatchesRuntimeDefinition(oblivious.InnerType, runtimeType)
        }
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return TypeInfoMatchesRuntimeDefinition(nullable.InnerType, runtimeType)
        }

        actualType: Type? = null
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null {
            actualType = reflected.Type
        } else {
            generic := typeInfo as GenericTypeInfo
            if generic != null {
                genericDefinition := generic.GenericDefinition as ReflectionTypeInfo
                if genericDefinition != null {
                    actualType = genericDefinition.Type
                }
            }
        }
        if actualType == null {
            return false
        }
        actualDefinition := actualType.IsGenericType ? actualType.GetGenericTypeDefinition() : actualType
        runtimeDefinition := runtimeType.IsGenericType ? runtimeType.GetGenericTypeDefinition() : runtimeType
        return TypeInfoIdentityFacts.HaveSameRuntimeAndReferenceTypeIdentity(actualDefinition, runtimeDefinition)
    }

    private func EvaluateMemberAccess(member: MemberAccessExpression, environment: RuntimeEnvironment, depth: int): object? {
        target := Evaluate(member.Object, environment, depth)
        semanticModel := environment.SemanticModel
        selectedCallable: FunctionTypeInfo? = null
        if semanticModel != null && semanticModel.TryGetCallableReferenceBindingAt(member.Line, member.Column, out selectedCallable) && selectedCallable != null {
            function := selectedCallable.SourceDeclaration as FunctionDeclaration
            if function == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("the analyzer-selected source method group has no declaration"))
            }
            receiver := target as RuntimeObject
            selectedFunction := new RuntimeFunction(function, receiver)
            return selectedFunction
        }
        runtimeObject := target as RuntimeObject
        if runtimeObject != null {
            value: object? = null
            if runtimeObject.Fields.TryGetValue(member.MemberName, out value) {
                return value
            }
            property := FindProperty(runtimeObject.Declaration, member.MemberName)
            if property != null {
                return ReadRuntimeProperty(runtimeObject, property, depth)
            }
        }

        error := target as RuntimeError
        if error != null && member.MemberName == PlaygroundRunFacts.ErrorMessageMemberName() {
            return error.Message
        }
        text := target as string
        if text != null && member.MemberName == PlaygroundRunFacts.LengthMemberName() {
            return text.Length
        }
        values := target as IReadOnlyList<object?>
        if values != null && member.MemberName == PlaygroundRunFacts.LengthMemberName() {
            return values.Count
        }
        runtimeType := target as RuntimeType
        if runtimeType != null {
            runtimeUnion := runtimeType.Declaration as UnionDeclaration
            if runtimeUnion != null && FindUnionCase(runtimeUnion, member.MemberName) != null {
                return new RuntimeUnionCase(runtimeUnion, member.MemberName)
            }
        }
        if target != null {
            property := target.GetType().GetProperty(member.MemberName, BindingFlags.Public | BindingFlags.Instance)
            if property != null && property.GetIndexParameters().Length == 0 {
                try {
                    return property.GetValue(target)
                } catch invocationFailure: TargetInvocationException {
                    RethrowInvocationFailure(invocationFailure)
                }
            }
        }
        throw Unsupported(PlaygroundRunFacts.UnresolvedMember(member.MemberName))
    }

    private func FindProperty(declaration: Declaration?, name: string): PropertyDeclaration? {
        if declaration == null {
            return null
        }
        members: List<Declaration>? = null
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            members = classDeclaration.Members
        } else {
            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                members = structDeclaration.Members
            } else {
                recordDeclaration := declaration as RecordDeclaration
                if recordDeclaration != null {
                    members = recordDeclaration.Members
                }
            }
        }
        if members == null {
            return null
        }
        for member in members {
            property := member as PropertyDeclaration
            if property != null && string.Equals(property.Name, name, StringComparison.Ordinal) {
                return property
            }
        }
        return null
    }

    private func ReadRuntimeProperty(runtimeObject: RuntimeObject, name: string, depth: int): object? {
        value: object? = null
        if runtimeObject.Fields.TryGetValue(name, out value) {
            return value
        }
        property := FindProperty(runtimeObject.Declaration, name)
        if property == null {
            throw Unsupported(PlaygroundRunFacts.UnresolvedMember(name))
        }
        return ReadRuntimeProperty(runtimeObject, property, depth)
    }

    private func ReadRuntimeProperty(runtimeObject: RuntimeObject, property: PropertyDeclaration, depth: int): object? {
        environment := new RuntimeEnvironment(runtimeObject.Environment)
        semanticModel: SemanticModel? = null
        if semanticModelsByDeclaration.TryGetValue(property, out semanticModel) && semanticModel != null {
            environment.SetSemanticModel(semanticModel)
        }
        environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), runtimeObject)
        try {
            if property.ExpressionBody != null {
                return Evaluate(property.ExpressionBody, environment, depth + 1)
            }
            if property.GetBody != null {
                ExecuteBlock(property.GetBody, environment, depth + 1)
            }
        } catch returned: ReturnSignal {
            return returned.Value
        }
        return null
    }

    private func SetMember(member: MemberAccessExpression, environment: RuntimeEnvironment, depth: int, value: object?) {
        target := Evaluate(member.Object, environment, depth)
        runtimeObject := target as RuntimeObject
        if runtimeObject != null {
            runtimeObject.Fields[member.MemberName] = value
            return
        }
        throw Unsupported(PlaygroundRunFacts.UnassignableMember(member.MemberName))
    }

    private func EvaluateNew(newExpression: NewExpression, environment: RuntimeEnvironment, depth: int): object {
        arguments := new object?[](newExpression.ConstructorArguments.Count)
        i := 0
        while i < newExpression.ConstructorArguments.Count {
            constructorArgument := newExpression.ConstructorArguments[i]
            if constructorArgument.Modifier != ArgumentModifier.Out {
                arguments[i] = Evaluate(constructorArgument.Value, environment, depth)
            }
            i = i + 1
        }
        created := EvaluateNewWithArguments(newExpression, arguments, environment.SemanticModel, environment, depth)
        if newExpression.Initializer != null {
            runtimeObject := created as RuntimeObject
            if runtimeObject == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedConstructionTarget())
            }
            ApplyInitializer(runtimeObject, newExpression.Initializer, environment, depth)
        }
        return created
    }

    private func EvaluateNewWithArguments(newExpression: NewExpression, arguments: IReadOnlyList<object?>, semanticModel: SemanticModel?, environment: RuntimeEnvironment, depth: int): object {
        hostConstructionBinding := ConstructionBindingAt(newExpression.Line, newExpression.Column, semanticModel)
        constructedType: NSharpLang.Compiler.TypeInfo? = hostConstructionBinding == null ? null : hostConstructionBinding.ConstructedType
        if TypeInfoMatchesRuntimeDefinition(constructedType, typeof(TaskCompletionSource)) || TypeInfoMatchesRuntimeDefinition(constructedType, typeof(TaskCompletionSource<object?>).GetGenericTypeDefinition()) {
            genericType := newExpression.Type as GenericTypeReference
            if genericType != null {
                // The interpreter carries generic task values as object-valued tasks. This still
                // gives pending await tests a real CLR completion source; the bound await pattern
                // determines the source result type and the set result remains boxed unchanged.
                return new TaskCompletionSource<object?>()
            }
            return new TaskCompletionSource()
        }
        if TypeInfoMatchesRuntimeDefinition(constructedType, typeof(ValueTask)) || TypeInfoMatchesRuntimeDefinition(constructedType, typeof(ValueTask<int>).GetGenericTypeDefinition()) {
            genericType := newExpression.Type as GenericTypeReference
            if genericType != null {
                if arguments.Count == 1 {
                    taskValue := arguments[0] as Task<object?>
                    if taskValue != null {
                        return new ValueTask<object?>(taskValue)
                    }
                    return new ValueTask<object?>(arguments[0])
                }
                return new ValueTask<object?>(null)
            }
            if arguments.Count == 1 {
                taskValue := arguments[0] as Task
                if taskValue != null {
                    return new ValueTask(taskValue)
                }
            }
            return ValueTask.CompletedTask
        }
        typeName := GetTypeName(newExpression.Type)
        if typeName == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedConstructionTarget())
        }
        if PlaygroundRunFacts.IsExceptionTypeName(typeName) {
            if arguments.Count == 0 {
                return new RuntimeError("")
            }
            return new RuntimeError(FormatValue(arguments[0]))
        }
        createdUnion: RuntimeUnion? = null
        if TryCreateUnionCase(typeName, arguments, out createdUnion) {
            return createdUnion
        }
        declaration: Declaration? = null
        if !types.TryGetValue(typeName, out declaration) || declaration == null {
            reflectedObject := TryCreateReflectedObject(newExpression, arguments, semanticModel, environment)
            if reflectedObject != null {
                return reflectedObject
            }
            throw Unsupported(PlaygroundRunFacts.UnknownConstructedType(typeName))
        }
        namespaceName: string? = null
        typeNamespaces.TryGetValue(typeName, out namespaceName)
        constructionBinding := ConstructionBindingAt(newExpression.Line, newExpression.Column, semanticModel)
        runtimeObject := new RuntimeObject(declaration, new RuntimeEnvironment(null), namespaceName, constructionBinding)
        InitializeSourceFields(runtimeObject, depth)
        if constructionBinding != null {
            sourceConstructor := constructionBinding.SourceConstructor as ConstructorDeclaration
            if sourceConstructor != null {
                constructorArguments: object?[] = null
                failureReason := "analyzer-bound source constructor arguments could not be materialized"
                if !BuildBoundSourceConstructorArguments(constructionBinding, newExpression, arguments, out constructorArguments, out failureReason) || constructorArguments == null {
                    throw Unsupported(PlaygroundRunFacts.UnsupportedExpression(failureReason))
                }
                InvokeSourceConstructor(sourceConstructor, constructorArguments, runtimeObject, semanticModel, depth)
            } else {
                ApplyPrimaryConstructorArguments(runtimeObject, arguments)
            }
        } else {
            ApplyPrimaryConstructorArguments(runtimeObject, arguments)
        }
        return runtimeObject
    }

    private func InitializeSourceFields(runtimeObject: RuntimeObject, depth: int) {
        if runtimeObject == null || runtimeObject.Declaration == null {
            return
        }
        members: List<Declaration>? = null
        classDeclaration := runtimeObject.Declaration as ClassDeclaration
        if classDeclaration != null {
            members = classDeclaration.Members
        } else {
            structDeclaration := runtimeObject.Declaration as StructDeclaration
            if structDeclaration != null {
                members = structDeclaration.Members
            } else {
                recordDeclaration := runtimeObject.Declaration as RecordDeclaration
                if recordDeclaration != null {
                    members = recordDeclaration.Members
                }
            }
        }
        if members == null {
            return
        }
        for member in members {
            field := member as FieldDeclaration
            if field == null || field.Initializer == null || (Convert.ToInt32(field.Modifiers) & Convert.ToInt32(Modifiers.Static)) != 0 {
                continue
            }
            environment := new RuntimeEnvironment(runtimeObject.Environment)
            semanticModel: SemanticModel? = null
            if semanticModelsByDeclaration.TryGetValue(field, out semanticModel) && semanticModel != null {
                environment.SetSemanticModel(semanticModel)
            }
            environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), runtimeObject)
            value := Evaluate(field.Initializer, environment, depth + 1)
            runtimeObject.Fields[field.Name] = value
            runtimeObject.Environment.Declare(field.Name, value)
        }
    }

    private func BuildBoundSourceConstructorArguments(binding: AnalyzerConstructionBinding, newExpression: NewExpression, arguments: IReadOnlyList<object?>, out invocationArguments: object?[], out failureReason: string): bool {
        invocationArguments = null
        failureReason = "analyzer-bound source constructor arguments could not be materialized"
        if binding == null || newExpression == null || arguments == null || binding.ParameterCount < 0 {
            return false
        }
        sourceConstructor := binding.SourceConstructor as ConstructorDeclaration
        if sourceConstructor == null || sourceConstructor.Parameters.Count != binding.ParameterCount {
            failureReason = "the analyzer-selected source constructor has an unsupported parameter shape"
            return false
        }

        values := new object?[](binding.ParameterCount)
        assigned := new bool[](binding.ParameterCount)
        for bound in binding.ArgumentBindings {
            if bound.ParameterIndex < 0 || bound.ParameterIndex >= binding.ParameterCount {
                failureReason = "analyzer-bound source constructor argument refers to an invalid parameter slot"
                return false
            }
            if bound.Kind == 2 {
                values[bound.ParameterIndex] = bound.DefaultValue
                assigned[bound.ParameterIndex] = true
                continue
            }
            if bound.Kind == 1 {
                arrayType: Type = null
                elementType: Type = null
                if !TryResolvePlaygroundConstructorValueType(bound.ParameterType, out arrayType) || !arrayType.IsArray || !TryResolvePlaygroundConstructorValueType(bound.ConversionType, out elementType) {
                    failureReason = "the analyzer-selected source params parameter is unavailable in the playground runtime"
                    return false
                }
                array := values[bound.ParameterIndex] as Array
                if array == null {
                    array = Array.CreateInstance(elementType, 0)
                    values[bound.ParameterIndex] = array
                }
                if bound.ArgumentIndex >= 0 {
                    if bound.ArgumentIndex >= arguments.Count {
                        failureReason = "an analyzer-bound expanded source argument index is outside the evaluated arguments"
                        return false
                    }
                    converted: object? = null
                    if !ConvertBoundConstructorArgument(arguments[bound.ArgumentIndex], elementType, out converted) {
                        failureReason = "an expanded source constructor argument could not be converted to the selected params element type"
                        return false
                    }
                    resized := Array.CreateInstance(elementType, array.Length + 1)
                    index := 0
                    while index < array.Length {
                        resized.SetValue(array.GetValue(index), index)
                        index += 1
                    }
                    resized.SetValue(converted, array.Length)
                    values[bound.ParameterIndex] = resized
                }
                assigned[bound.ParameterIndex] = true
                continue
            }
            if bound.ArgumentIndex < 0 || bound.ArgumentIndex >= arguments.Count || bound.ArgumentIndex >= newExpression.ConstructorArguments.Count {
                failureReason = "analyzer-bound source constructor argument has no evaluated source value"
                return false
            }
            targetType: Type = null
            if !TryResolvePlaygroundConstructorValueType(bound.ConversionType, out targetType) {
                failureReason = "the analyzer-selected source constructor conversion type is unavailable in the playground runtime"
                return false
            }
            converted: object? = null
            if !ConvertBoundConstructorArgument(arguments[bound.ArgumentIndex], targetType, out converted) {
                failureReason = "a source constructor argument could not be converted to its analyzer-selected parameter type"
                return false
            }
            values[bound.ParameterIndex] = converted
            assigned[bound.ParameterIndex] = true
        }

        index := 0
        while index < binding.ParameterCount {
            if !assigned[index] {
                failureReason = "the analyzer-bound source constructor omitted a required parameter value"
                return false
            }
            index += 1
        }
        invocationArguments = values
        return true
    }

    private func InvokeSourceConstructor(constructor: ConstructorDeclaration, arguments: IReadOnlyList<object?>, receiver: RuntimeObject, semanticModel: SemanticModel?, depth: int) {
        if constructor == null || receiver == null || arguments == null || constructor.Parameters.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.UnsupportedConstructorArguments())
        }
        environment := new RuntimeEnvironment(receiver.Environment)
        if semanticModel != null {
            environment.SetSemanticModel(semanticModel)
        }
        environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), receiver)
        index := 0
        while index < constructor.Parameters.Count {
            environment.Declare(constructor.Parameters[index].Name, arguments[index])
            index += 1
        }
        ExecuteBlock(constructor.Body, environment, depth + 1)
    }

    private func TryCreateReflectedObject(newExpression: NewExpression, arguments: IReadOnlyList<object?>, semanticModel: SemanticModel?, environment: RuntimeEnvironment): object? {
        if newExpression == null || newExpression.Type == null || semanticModel == null {
            return null
        }
        line := 0
        column := 0
        genericReference := newExpression.Type as GenericTypeReference
        if genericReference != null {
            line = genericReference.Line
            column = genericReference.Column
        } else {
            simpleReference := newExpression.Type as SimpleTypeReference
            if simpleReference == null {
                return null
            }
            line = simpleReference.Line
            column = simpleReference.Column
        }
        reflectedTypeInfo := semanticModel.LookupTypeReferenceAtPosition(line, column)
        runtimeType: Type = null
        if reflectedTypeInfo == null || !TryResolvePlaygroundRuntimeType(reflectedTypeInfo, out runtimeType) {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected reflected constructor type is not available to the playground runtime"))
        }
        selectedBinding := ConstructionBindingAt(newExpression.Line, newExpression.Column, semanticModel)
        if selectedBinding == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("analyzer did not retain the selected constructor binding for '" + runtimeType.ToString() + "'"))
        }
        if selectedBinding.ReflectedConstructor == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("analyzer did not select a reflected constructor for this external type"))
        }
        constructor := ResolveRuntimeConstructor(selectedBinding.ReflectedConstructor, runtimeType)
        if constructor == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("selected reflected constructor has no runtime metadata match"))
        }
        invocationArguments: object?[] = null
        writeBacks: List<RuntimeConstructorWriteBack> = null
        argumentFailure := "analyzer-bound reflected constructor arguments could not be materialized"
        if !BuildBoundConstructorArguments(selectedBinding, newExpression, arguments, environment, out invocationArguments, out writeBacks, out argumentFailure) || invocationArguments == null || writeBacks == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression(argumentFailure))
        }
        instance: object? = null
        try {
            instance = constructor.Invoke(invocationArguments)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        } finally {
            ApplyConstructorWriteBacks(invocationArguments, writeBacks)
        }
        return instance
    }

    private static func ResolveRuntimeConstructor(selected: ConstructorInfo, runtimeType: Type): ConstructorInfo? {
        if selected == null || runtimeType == null {
            return null
        }
        selectedOwner := selected.DeclaringType
        if selectedOwner == null || !RuntimeTypeDefinitionsMatch(selectedOwner, runtimeType) {
            return null
        }
        for candidate in runtimeType.GetConstructors(BindingFlags.Public | BindingFlags.Instance) {
            if RuntimeConstructorSignaturesMatch(selected, candidate) {
                return candidate
            }
        }
        return null
    }

    private static func RuntimeConstructorSignaturesMatch(selected: ConstructorInfo, runtimeConstructor: ConstructorInfo): bool {
        if selected == null || runtimeConstructor == null {
            return false
        }
        selectedParameters := selected.GetParameters()
        runtimeParameters := runtimeConstructor.GetParameters()
        if selectedParameters.Length != runtimeParameters.Length {
            return false
        }
        selectedOwner := selected.DeclaringType
        runtimeOwner := runtimeConstructor.DeclaringType
        index := 0
        while index < selectedParameters.Length {
            if !RuntimeSignatureTypesMatch(selectedParameters[index].ParameterType, runtimeParameters[index].ParameterType, selectedOwner, runtimeOwner) {
                return false
            }
            index += 1
        }
        return true
    }

    private func BuildBoundConstructorArguments(binding: AnalyzerConstructionBinding, newExpression: NewExpression, arguments: IReadOnlyList<object?>, environment: RuntimeEnvironment, out invocationArguments: object?[], out writeBacks: List<RuntimeConstructorWriteBack>, out failureReason: string): bool {
        invocationArguments = null
        writeBacks = null
        failureReason = "analyzer-bound reflected constructor arguments could not be materialized"
        if binding == null || newExpression == null || arguments == null || environment == null || binding.ParameterCount < 0 {
            return false
        }
        selectedConstructor := binding.ReflectedConstructor
        if selectedConstructor == null {
            failureReason = "the analyzer did not retain the selected reflected constructor"
            return false
        }
        reflectedParameters := selectedConstructor.GetParameters()
        values := new object?[](binding.ParameterCount)
        assigned := new bool[](binding.ParameterCount)
        pendingWriteBacks := new List<RuntimeConstructorWriteBack>()
        for bound in binding.ArgumentBindings {
            if bound.ParameterIndex < 0 || bound.ParameterIndex >= binding.ParameterCount {
                failureReason = "analyzer-bound constructor argument refers to an invalid parameter slot"
                return false
            }
            parameterIndex := bound.ParameterIndex
            if bound.Kind == 2 {
                values[parameterIndex] = bound.DefaultValue
                assigned[parameterIndex] = true
                continue
            }
            if bound.Kind == 1 {
                parameterType: Type = null
                elementType: Type = null
                if !TryResolvePlaygroundRuntimeType(bound.ParameterType, out parameterType) {
                    failureReason = "the selected params parameter type '" + bound.ParameterType.ToString() + "' is unavailable in the playground runtime"
                    return false
                }
                if !TryResolvePlaygroundRuntimeType(bound.ConversionType, out elementType) {
                    failureReason = "the selected params element type '" + bound.ConversionType.ToString() + "' is unavailable in the playground runtime"
                    return false
                }
                if !parameterType.IsArray {
                    failureReason = "the analyzer marked an expanded argument for a non-array params parameter"
                    return false
                }
                array := values[parameterIndex] as Array
                if array == null {
                    array = Array.CreateInstance(elementType, 0)
                    values[parameterIndex] = array
                }
                if bound.ArgumentIndex >= 0 {
                    if bound.ArgumentIndex >= arguments.Count {
                        failureReason = "an expanded constructor argument index is outside the evaluated arguments"
                        return false
                    }
                    converted: object? = null
                    if !ConvertBoundConstructorArgument(arguments[bound.ArgumentIndex], elementType, out converted) {
                        failureReason = "an expanded constructor argument could not be converted to the selected params element type"
                        return false
                    }
                    resized := Array.CreateInstance(elementType, array.Length + 1)
                    index := 0
                    while index < array.Length {
                        resized.SetValue(array.GetValue(index), index)
                        index += 1
                    }
                    resized.SetValue(converted, array.Length)
                    values[parameterIndex] = resized
                }
                assigned[parameterIndex] = true
                continue
            }
            if bound.ArgumentIndex < 0 || bound.ArgumentIndex >= arguments.Count {
                failureReason = "analyzer-bound constructor argument has no evaluated source argument"
                return false
            }
            if bound.ArgumentIndex >= newExpression.ConstructorArguments.Count {
                failureReason = "analyzer-bound constructor argument has no matching source argument"
                return false
            }
            sourceArgument := newExpression.ConstructorArguments[bound.ArgumentIndex]
            byRefParameter := bound.ParameterType as ByRefTypeInfo
            if bound.ParameterIndex >= reflectedParameters.Length {
                failureReason = "analyzer-bound constructor parameter is missing from the selected reflected constructor"
                return false
            }
            reflectedParameter := reflectedParameters[bound.ParameterIndex]
            isByRefParameter := byRefParameter != null || reflectedParameter.ParameterType.IsByRef
            hasByRefModifier := sourceArgument.Modifier == ArgumentModifier.Ref || sourceArgument.Modifier == ArgumentModifier.Out || sourceArgument.Modifier == ArgumentModifier.In
            if hasByRefModifier && !isByRefParameter {
                failureReason = "the source argument modifier does not match the selected reflected constructor parameter"
                return false
            }
            if sourceArgument.Modifier == ArgumentModifier.Ref && (reflectedParameter.IsOut || reflectedParameter.IsIn) || sourceArgument.Modifier == ArgumentModifier.Out && !reflectedParameter.IsOut || sourceArgument.Modifier == ArgumentModifier.In && !reflectedParameter.IsIn {
                failureReason = "the source argument direction does not match the selected reflected constructor parameter"
                return false
            }
            if isByRefParameter {
                targetType: Type = null
                if !TryResolvePlaygroundConstructorValueType(bound.ConversionType, out targetType) {
                    failureReason = "the selected by-reference constructor parameter type is unavailable in the playground runtime"
                    return false
                }
                converted: object? = null
                if sourceArgument.Modifier == ArgumentModifier.Out {
                    converted = DefaultPlaygroundValue(targetType)
                } else if !ConvertBoundConstructorArgument(arguments[bound.ArgumentIndex], targetType, out converted) {
                    failureReason = "a by-reference constructor argument could not be converted to its parameter type"
                    return false
                }
                values[parameterIndex] = converted
                if sourceArgument.Modifier == ArgumentModifier.Ref || sourceArgument.Modifier == ArgumentModifier.Out {
                    storage: RuntimeConstructorStorage = null
                    if !TryCreateConstructorStorage(sourceArgument.Value, environment, out storage) || storage == null {
                        failureReason = "the by-reference constructor argument does not have a supported caller storage location"
                        return false
                    }
                    pendingWriteBacks.Add(new RuntimeConstructorWriteBack(parameterIndex, sourceArgument.Modifier, storage))
                }
                assigned[parameterIndex] = true
                continue
            }
            targetType: Type = null
            if !TryResolvePlaygroundConstructorValueType(bound.ConversionType, out targetType) {
                failureReason = "the selected constructor parameter conversion type is unavailable in the playground runtime"
                return false
            }
            converted: object? = null
            if !ConvertBoundConstructorArgument(arguments[bound.ArgumentIndex], targetType, out converted) {
                failureReason = "a constructor argument could not be converted to its analyzer-selected parameter type"
                return false
            }
            values[parameterIndex] = converted
            assigned[parameterIndex] = true
        }
        index := 0
        while index < binding.ParameterCount {
            if !assigned[index] {
                failureReason = "the analyzer-bound constructor omitted a required parameter value"
                return false
            }
            index += 1
        }
        invocationArguments = values
        writeBacks = pendingWriteBacks
        return true
    }

    private static func TryResolvePlaygroundConstructorValueType(typeInfo: NSharpLang.Compiler.TypeInfo, out runtimeType: Type): bool {
        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            typeInfo = byRef.InnerType
        }
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return TryResolvePlaygroundConstructorValueType(oblivious.InnerType, out runtimeType)
        }
        reflected := typeInfo as ReflectionTypeInfo
        if reflected != null && reflected.Type.IsByRef {
            elementType := reflected.Type.GetElementType()
            if elementType == null {
                runtimeType = null
                return false
            }
            return TryResolvePlaygroundRuntimeTypeFromMetadata(elementType, out runtimeType)
        }
        if !TryResolvePlaygroundRuntimeType(typeInfo, out runtimeType) {
            return false
        }
        if runtimeType.IsByRef {
            elementType := runtimeType.GetElementType()
            if elementType == null {
                runtimeType = null
                return false
            }
            runtimeType = elementType
        }
        return true
    }


    private static func DefaultPlaygroundValue(runtimeType: Type): object? {
        if runtimeType != null && runtimeType.IsValueType {
            return Activator.CreateInstance(runtimeType)
        }
        return null
    }

    private func TryCreateConstructorStorage(expression: Expression, environment: RuntimeEnvironment, out storage: RuntimeConstructorStorage): bool {
        storage = null
        identifier := expression as IdentifierExpression
        if identifier != null {
            storage = new RuntimeConstructorStorage(environment, identifier.Name, null, null, null, null)
            return true
        }
        member := expression as MemberAccessExpression
        if member == null {
            return false
        }
        owner := Evaluate(member.Object, environment, 0)
        runtimeOwner := owner as RuntimeObject
        if runtimeOwner != null {
            storage = new RuntimeConstructorStorage(null, null, runtimeOwner, null, null, member.MemberName)
            return true
        }
        if owner != null {
            field := owner.GetType().GetField(member.MemberName, BindingFlags.Public | BindingFlags.Instance)
            if field != null {
                storage = new RuntimeConstructorStorage(null, null, null, owner, field, member.MemberName)
                return true
            }
        }
        return false
    }

    private static func ApplyConstructorWriteBacks(invocationArguments: object?[], writeBacks: List<RuntimeConstructorWriteBack>) {
        if invocationArguments == null || writeBacks == null {
            return
        }
        for writeBack in writeBacks {
            if (writeBack.Modifier == ArgumentModifier.Ref || writeBack.Modifier == ArgumentModifier.Out) && writeBack.ParameterIndex >= 0 && writeBack.ParameterIndex < invocationArguments.Length {
                writeBack.Storage.Write(invocationArguments[writeBack.ParameterIndex])
            }
        }
    }

    private static func ConvertBoundConstructorArgument(value: object?, parameterType: Type, out converted: object?): bool {
        converted = value
        if parameterType == null {
            return false
        }
        sourceArray := value as Array
        if sourceArray != null && parameterType.IsArray {
            elementType := parameterType.GetElementType()
            if elementType == null {
                return false
            }
            convertedArray := Array.CreateInstance(elementType, sourceArray.Length)
            index := 0
            while index < sourceArray.Length {
                elementValue: object? = null
                elementConverted: object? = null
                if !ConvertBoundConstructorArgument(sourceArray.GetValue(index), elementType, out elementConverted) {
                    return false
                }
                elementValue = elementConverted
                convertedArray.SetValue(elementValue, index)
                index += 1
            }
            converted = convertedArray
            return true
        }
        if value == null {
            return !parameterType.IsValueType || Nullable.GetUnderlyingType(parameterType) != null
        }
        if parameterType.IsInstanceOfType(value) {
            return true
        }
        targetType := Nullable.GetUnderlyingType(parameterType)
        if targetType == null {
            targetType = parameterType
        }
        try {
            if value is IConvertible && typeof(IConvertible).IsAssignableFrom(targetType) {
                converted = Convert.ChangeType(value, targetType, CultureInfo.InvariantCulture)
                return converted != null
            }
        } catch failure: InvalidCastException {
            return false
        } catch failure: FormatException {
            return false
        } catch failure: OverflowException {
            return false
        }
        return false
    }

    private async func ApplyAsyncInitializer(value: object, initializer: ObjectInitializerExpression, environment: RuntimeEnvironment, depth: int): Task {
        runtimeObject := value as RuntimeObject
        if runtimeObject == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedConstructionTarget())
        }
        for property in initializer.Properties {
            if property.Name == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedIndexerInitializer())
            }
            propertyValue := await EvaluateAsync(property.Value, environment, depth)
            SetRuntimeObjectField(runtimeObject, property.Name, propertyValue)
        }
    }

    private static func SetArrayElement(values: object?[], index: int, value: object?) {
        values[index] = value
    }

    private static func SetRuntimeObjectField(runtimeObject: RuntimeObject, name: string, value: object?) {
        runtimeObject.Fields[name] = value
        runtimeObject.Environment.Declare(name, value)
    }

    private func EvaluateObjectInitializer(initializer: ObjectInitializerExpression, environment: RuntimeEnvironment, depth: int): object {
        runtimeObject := new RuntimeObject(null, new RuntimeEnvironment(null), null)
        ApplyInitializer(runtimeObject, initializer, environment, depth)
        return runtimeObject
    }

    private func ApplyPrimaryConstructorArguments(runtimeObject: RuntimeObject, arguments: IReadOnlyList<object?>) {
        parameters: List<Parameter>? = null
        classDeclaration := runtimeObject.Declaration as ClassDeclaration
        if classDeclaration != null {
            parameters = classDeclaration.PrimaryConstructorParameters
        } else {
            structDeclaration := runtimeObject.Declaration as StructDeclaration
            if structDeclaration != null {
                parameters = structDeclaration.PrimaryConstructorParameters
            } else {
                recordDeclaration := runtimeObject.Declaration as RecordDeclaration
                if recordDeclaration != null {
                    parameters = recordDeclaration.PrimaryConstructorParameters
                }
            }
        }
        if parameters == null {
            if arguments.Count > 0 {
                throw Unsupported(PlaygroundRunFacts.UnsupportedConstructorArguments())
            }
            return
        }
        if parameters.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.WrongConstructorArgumentCount())
        }
        i := 0
        while i < parameters.Count {
            runtimeObject.Fields[parameters[i].Name] = arguments[i]
            runtimeObject.Environment.Declare(parameters[i].Name, arguments[i])
            i = i + 1
        }
    }

    private func ApplyInitializer(runtimeObject: RuntimeObject, initializer: ObjectInitializerExpression, environment: RuntimeEnvironment, depth: int) {
        for property in initializer.Properties {
            if property.Name == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedIndexerInitializer())
            }
            value := Evaluate(property.Value, environment, depth)
            runtimeObject.Fields[property.Name] = value
            runtimeObject.Environment.Declare(property.Name, value)
        }
    }

    private func EvaluateWith(withExpression: WithExpression, environment: RuntimeEnvironment, depth: int): object {
        target := Evaluate(withExpression.Target, environment, depth)
        runtimeObject := target as RuntimeObject
        if runtimeObject == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedWithTarget())
        }
        copy := runtimeObject.Clone()
        for property in withExpression.Properties {
            if property.Name == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedWithIndexer())
            }
            copy.Fields[property.Name] = Evaluate(property.Value, environment, depth)
        }
        return copy
    }

    private func EvaluateMatch(matchExpression: MatchExpression, environment: RuntimeEnvironment, depth: int): object? {
        value := Evaluate(matchExpression.Value, environment, depth)
        for matchCase in matchExpression.Cases {
            caseEnvironment := new RuntimeEnvironment(environment)
            if PatternMatches(matchCase.Pattern, value, caseEnvironment) {
                if matchCase.Guard == null || IsTruthy(Evaluate(matchCase.Guard, caseEnvironment, depth)) {
                    return Evaluate(matchCase.Expression, caseEnvironment, depth)
                }
            }
        }
        throw Unsupported(PlaygroundRunFacts.NoMatchingMatchArm())
    }

    private func PatternMatches(pattern: Pattern, value: object?, environment: RuntimeEnvironment): bool {
        identifier := pattern as IdentifierPattern
        if identifier != null {
            if PlaygroundRunFacts.IsDiscardName(identifier.Name) {
                return true
            }
            environment.Declare(identifier.Name, value)
            return true
        }

        literal := pattern as LiteralPattern
        if literal != null {
            literalValue: object? = null
            stringLiteral := literal.Literal as StringLiteralExpression
            if stringLiteral != null {
                literalValue = PlaygroundRunFacts.DecodeStringLiteralText(stringLiteral.Value, stringLiteral.IsRaw)
            } else {
                intLiteral := literal.Literal as IntLiteralExpression
                if intLiteral != null {
                    literalValue = int.Parse(intLiteral.Value)
                } else {
                    boolLiteral := literal.Literal as BoolLiteralExpression
                    if boolLiteral != null {
                        literalValue = boolLiteral.Value
                    } else if literal.Literal as NullLiteralExpression != null {
                        literalValue = null
                    } else {
                        throw Unsupported(PlaygroundRunFacts.UnsupportedLiteralPattern())
                    }
                }
            }
            return ValuesEqual(value, literalValue)
        }

        unionCasePattern := pattern as UnionCasePattern
        runtimeUnion := value as RuntimeUnion
        if unionCasePattern != null && runtimeUnion != null {
            if !PlaygroundRunFacts.UnionCaseNamesMatch(unionCasePattern.CaseName, runtimeUnion.CaseName) {
                return false
            }
            if unionCasePattern.Properties != null {
                for property in unionCasePattern.Properties {
                    propertyValue: object? = null
                    if !runtimeUnion.Fields.TryGetValue(property.Name, out propertyValue) {
                        return false
                    }
                    if property.Pattern == null {
                        environment.Declare(AnalyzerPropertyPatternBinding.BoundName(property), propertyValue)
                    } else if !PatternMatches(property.Pattern, propertyValue, environment) {
                        return false
                    }
                }
            }
            return true
        }

        patternTypeName := pattern.GetType().Name
        throw Unsupported(PlaygroundRunFacts.UnsupportedPattern(patternTypeName))
    }

    private func TryCreateUnionCase(typeName: string, arguments: IReadOnlyList<object?>, out value: RuntimeUnion?): bool {
        value = null
        if !PlaygroundRunFacts.IsQualifiedUnionCaseName(typeName) {
            return false
        }
        unionName := PlaygroundRunFacts.UnionOwnerNameOf(typeName)
        caseName := PlaygroundRunFacts.UnionCaseNameOf(typeName)
        declaration: Declaration? = null
        types.TryGetValue(unionName, out declaration)
        runtimeUnion := declaration as UnionDeclaration
        if runtimeUnion == null {
            return false
        }
        unionCase := FindUnionCase(runtimeUnion, caseName)
        if unionCase == null {
            throw Unsupported(PlaygroundRunFacts.UnknownUnionCase(caseName))
        }
        properties := unionCase.Properties
        if properties == null {
            if arguments.Count != 0 {
                throw Unsupported(PlaygroundRunFacts.WrongUnionCaseArgumentCount())
            }
        } else if properties.Count != arguments.Count {
            throw Unsupported(PlaygroundRunFacts.WrongUnionCaseArgumentCount())
        }
        fields := new Dictionary<string, object?>(StringComparer.Ordinal)
        if properties != null {
            i := 0
            while i < properties.Count {
                fields[properties[i].Name] = arguments[i]
                i = i + 1
            }
        }
        namespaceName: string? = null
        typeNamespaces.TryGetValue(unionName, out namespaceName)
        value = new RuntimeUnion(namespaceName, runtimeUnion.Name, unionCase.Name, fields)
        return true
    }

    private static func FindUnionCase(unionDeclaration: UnionDeclaration, caseName: string): UnionCase? {
        for candidate in unionDeclaration.Cases {
            if PlaygroundRunFacts.UnionCaseNamesMatch(candidate.Name, caseName) {
                return candidate
            }
        }
        return null
    }

    private static func GetTypeName(typeReference: TypeReference?): string? {
        if typeReference == null {
            return null
        }
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return simple.Name
        }
        generic := typeReference as GenericTypeReference
        if generic != null {
            return generic.Name
        }
        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return GetTypeName(nullable.InnerType)
        }
        array := typeReference as ArrayTypeReference
        if array != null {
            elementName := GetTypeName(array.ElementType)
            return (elementName ?? "") + "[]"
        }
        return null
    }

    private func WriteLine(value: string) {
        if outputLines >= PlaygroundRunFacts.MaxOutputLines() {
            throw Unsupported(PlaygroundRunFacts.OutputLineLimitReached())
        }
        stdout.Append(value)
        stdout.Append(PlaygroundRunFacts.OutputLineTerminator())
        outputLines = outputLines + 1
    }

    private func Step(_node: AstNode) {
        steps = steps + 1
        if steps > PlaygroundRunFacts.MaxSteps() {
            throw Unsupported(PlaygroundRunFacts.StepLimitReached())
        }
    }

    private static func IsTruthy(value: object?): bool {
        if value == null {
            return false
        }
        valueType := value.GetType()
        if valueType == typeof(bool) {
            return Convert.ToBoolean(value)
        }
        if valueType == typeof(int) {
            return Convert.ToInt32(value) != 0
        }
        if valueType == typeof(long) {
            return Convert.ToInt64(value) != 0
        }
        if valueType == typeof(double) {
            number := Convert.ToDouble(value)
            magnitude := Math.Abs(number)
            epsilon := BitConverter.Int64BitsToDouble(1L)
            return magnitude > epsilon
        }
        text := value as string
        if text != null {
            return text.Length > 0
        }
        return true
    }

    private static func ValuesEqual(left: object?, right: object?): bool {
        if left == null || right == null {
            return Object.Equals(left, right)
        }
        if IsNumeric(left) && IsNumeric(right) {
            return PlaygroundRunFacts.NumbersEqual(ToNumber(left), ToNumber(right))
        }
        return Object.Equals(left, right)
    }

    private static func IsIntegral(value: object?): bool {
        if value == null {
            return false
        }
        valueType := value.GetType()
        return valueType == typeof(int) || valueType == typeof(long)
    }

    private static func IsNumeric(value: object?): bool {
        if value == null {
            return false
        }
        valueType := value.GetType()
        return valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(float) || valueType == typeof(double) || valueType == typeof(decimal)
    }

    private static func ToNumber(value: object?): double {
        if value != null {
            valueType := value.GetType()
            if valueType == typeof(int) {
                return Convert.ToDouble(value)
            }
            if valueType == typeof(long) {
                return Convert.ToDouble(value)
            }
            if valueType == typeof(float) {
                return Convert.ToDouble(value)
            }
            if valueType == typeof(double) {
                return Convert.ToDouble(value)
            }
            if valueType == typeof(decimal) {
                return Convert.ToDouble(value)
            }
        }
        throw Unsupported(PlaygroundRunFacts.ExpectedNumber(FormatValue(value)))
    }

    private static func ToInt(value: object?): int {
        if value != null {
            valueType := value.GetType()
            if valueType == typeof(int) {
                return Convert.ToInt32(value)
            }
            if valueType == typeof(long) {
                longValue := Convert.ToInt64(value)
                return checked((int)longValue)
            }
            if valueType == typeof(double) {
                number := Convert.ToDouble(value)
                return checked((int)number)
            }
        }
        throw Unsupported(PlaygroundRunFacts.ExpectedInteger(FormatValue(value)))
    }

    private static func FormatValue(value: object?): string {
        if value == null {
            return PlaygroundRunFacts.NullDisplayText()
        }
        text := value as string
        if text != null {
            return text
        }
        valueType := value.GetType()
        if valueType == typeof(bool) {
            booleanValue := Convert.ToBoolean(value)
            return PlaygroundRunFacts.BooleanDisplayText(booleanValue)
        }
        runtimeObject := value as RuntimeObject
        if runtimeObject != null {
            return runtimeObject.ToDisplayString()
        }
        runtimeUnion := value as RuntimeUnion
        if runtimeUnion != null {
            return runtimeUnion.ToDisplayString()
        }
        error := value as RuntimeError
        if error != null {
            return error.Message
        }
        if valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(decimal) {
            formattedNumber := Convert.ToString(value, CultureInfo.InvariantCulture)
            return formattedNumber ?? ""
        }
        converted := Convert.ToString(value, CultureInfo.InvariantCulture)
        return converted ?? ""
    }

    private static func Unsupported(fault: PlaygroundRunFault): PlaygroundRunUnsupportedException {
        return new PlaygroundRunUnsupportedException(fault.Code, fault.Message)
    }

    private static func UnsupportedAt(fault: PlaygroundRunFault, call: CallExpression): PlaygroundRunUnsupportedException {
        return new PlaygroundRunUnsupportedException(fault.Code, fault.Message, call.Line, call.Column, 1)
    }

    private static func ToInvocationArguments(arguments: IReadOnlyList<object?>): object?[] {
        values := new object?[](arguments.Count)
        i := 0
        while i < values.Length {
            values[i] = arguments[i]
            i += 1
        }
        return values
    }

    private sealed class RuntimeEnvironment {
        private parent: RuntimeEnvironment?
        private values: Dictionary<string, object?>
        SemanticModel: SemanticModel?

        constructor(parentEnvironment: RuntimeEnvironment?) {
            parent = parentEnvironment
            values = new Dictionary<string, object?>(StringComparer.Ordinal)
            SemanticModel = parentEnvironment == null ? null : parentEnvironment.SemanticModel
        }

        func SetSemanticModel(model: SemanticModel) {
            SemanticModel = model
        }

        func Declare(name: string, value: object?) {
            values[name] = value
        }

        func TryGet(name: string, out value: object?): bool {
            if values.TryGetValue(name, out value) {
                return true
            }
            if parent != null {
                return parent.TryGet(name, out value)
            }
            value = null
            return false
        }

        func Set(name: string, value: object?) {
            if values.ContainsKey(name) {
                values[name] = value
                return
            }
            if parent != null && parent.Contains(name) {
                parent.Set(name, value)
                return
            }
            values[name] = value
        }

        private func Contains(name: string): bool {
            if values.ContainsKey(name) {
                return true
            }
            return parent != null && parent.Contains(name)
        }
    }

    private sealed record RuntimeType(Declaration: Declaration) {
    }

    private sealed class RuntimeConstructorStorage {
        private variableEnvironment: RuntimeEnvironment?
        private variableName: string?
        private runtimeOwner: RuntimeObject?
        private reflectedOwner: object?
        private reflectedField: FieldInfo?
        private memberName: string?

        constructor(environment: RuntimeEnvironment?, name: string?, sourceOwner: RuntimeObject?, externalOwner: object?, field: FieldInfo?, member: string?) {
            variableEnvironment = environment
            variableName = name
            runtimeOwner = sourceOwner
            reflectedOwner = externalOwner
            reflectedField = field
            memberName = member
        }

        func Write(value: object?) {
            if variableName != null && variableEnvironment != null {
                variableEnvironment.Set(variableName, value)
                return
            }
            if runtimeOwner != null && memberName != null {
                runtimeOwner.Fields[memberName] = value
                runtimeOwner.Environment.Set(memberName, value)
                return
            }
            if reflectedOwner != null && reflectedField != null {
                reflectedField.SetValue(reflectedOwner, value)
            }
        }
    }

    private sealed class RuntimeConstructorWriteBack {
        ParameterIndex: int
        Modifier: ArgumentModifier
        Storage: RuntimeConstructorStorage

        constructor(parameterIndex: int, modifier: ArgumentModifier, storage: RuntimeConstructorStorage) {
            ParameterIndex = parameterIndex
            Modifier = modifier
            Storage = storage
        }
    }

    private sealed record RuntimeFunction(Declaration: FunctionDeclaration, Receiver: RuntimeObject?) {
    }

    private sealed record RuntimeLambda(Declaration: LambdaExpression, Closure: RuntimeEnvironment) {
    }

    private sealed class RuntimeTaskRunCallback {
        Owner: PlaygroundRunner
        Callback: object
        Depth: int

        constructor(owner: PlaygroundRunner, callback: object, depth: int) {
            Owner = owner
            Callback = callback
            Depth = depth
        }

        func InvokeAction(): void {
            Owner.InvokeTaskRunCallable(Callback, Depth)
        }

        func InvokeResult<T>(): T {
            return (T)Owner.InvokeTaskRunCallable(Callback, Depth)
        }

        func InvokeTask(): Task {
            return Owner.TaskRunCallableTask(Callback, Depth)
        }

        func InvokeTaskResult<T>(): Task<T> {
            return Owner.TaskRunCallableTaskResult<T>(Callback, Depth)
        }
    }

    private sealed class RuntimeConfiguredTaskAwaitable {
        Task: Task
        ContinueOnCapturedContext: bool

        constructor(task: Task, continueOnCapturedContext: bool) {
            Task = task
            ContinueOnCapturedContext = continueOnCapturedContext
        }
    }

    private sealed class RuntimeObject {
        Declaration: Declaration?
        Environment: RuntimeEnvironment
        NamespaceName: string?
        Fields: Dictionary<string, object?>
        ConstructionBinding: AnalyzerConstructionBinding?

        constructor(declaration: Declaration?, environment: RuntimeEnvironment, namespaceName: string?, constructionBinding: AnalyzerConstructionBinding? = null) {
            Declaration = declaration
            Environment = environment
            NamespaceName = namespaceName
            Fields = new Dictionary<string, object?>(StringComparer.Ordinal)
            ConstructionBinding = constructionBinding
        }

        func Clone(): RuntimeObject {
            copy := new RuntimeObject(Declaration, new RuntimeEnvironment(null), NamespaceName, ConstructionBinding)
            for pair in Fields {
                copy.Fields[pair.Key] = pair.Value
                copy.Environment.Declare(pair.Key, pair.Value)
            }
            return copy
        }

        func ToDisplayString(): string {
            typeName := ""
            if Declaration != null {
                declaration := Declaration
                declarationName := PlaygroundRunFacts.DeclarationName(declaration)
                if declarationName != null {
                    typeName = declarationName
                } else {
                    typeName = PlaygroundRunFacts.AnonymousObjectDisplayName()
                }
            } else {
                typeName = PlaygroundRunFacts.AnonymousObjectDisplayName()
            }
            return PlaygroundRunFacts.ObjectDisplayText(NamespaceName, typeName)
        }
    }

    private sealed class RuntimeUnion {
        NamespaceName: string?
        TypeName: string
        CaseName: string
        Fields: Dictionary<string, object?>

        constructor(namespaceName: string?, typeName: string, caseName: string, fields: Dictionary<string, object?>) {
            NamespaceName = namespaceName
            TypeName = typeName
            CaseName = caseName
            Fields = fields
        }

        func ToDisplayString(): string {
            return PlaygroundRunFacts.UnionDisplayText(NamespaceName, TypeName, CaseName)
        }
    }

    private sealed record RuntimeUnionCase(Union: UnionDeclaration, CaseName: string) {
    }

    private sealed class ReturnSignal: Exception {
        Value: object?

        constructor(value: object?) {
            Value = value
        }
    }

    private sealed class PlaygroundThrownException: Exception {
        Value: object?

        constructor(value: object?) {
            Value = value
        }
    }
}

internal sealed class PlaygroundAwaiterCompletionSignal {
    Completion: TaskCompletionSource<object?>

    constructor(completion: TaskCompletionSource<object?>) {
        Completion = completion
    }

    func Signal(): void {
        Completion.TrySetResult(null)
    }

    static func CreateAction(completion: TaskCompletionSource<object?>): Action {
        signal := new PlaygroundAwaiterCompletionSignal(completion)
        method := typeof(PlaygroundAwaiterCompletionSignal).GetMethod("Signal", BindingFlags.Public | BindingFlags.Instance)
        if method == null {
            throw new InvalidOperationException("The playground await continuation signal method is missing.")
        }
        callback := Delegate.CreateDelegate(typeof(Action), signal, method)
        action := callback as Action
        if action == null {
            throw new InvalidOperationException("The playground await continuation could not be bound to Action.")
        }
        return action
    }
}

internal sealed class PlaygroundTaskCompletionSignal {
    Source: Task
    Completion: TaskCompletionSource<object?>

    constructor(source: Task, completion: TaskCompletionSource<object?>) {
        Source = source
        Completion = completion
    }

    func Signal(): void {
        if !Source.IsCompleted {
            Completion.TrySetException(new InvalidOperationException("A configured Task continuation ran before its source Task completed."))
            return
        }
        try {
            Source.GetAwaiter().GetResult()
            Completion.TrySetResult(null)
        } catch canceled: OperationCanceledException {
            Completion.TrySetCanceled()
        } catch failure: Exception {
            Completion.TrySetException(failure)
        }
    }

    static func CreateAction(source: Task, completion: TaskCompletionSource<object?>): Action {
        signal := new PlaygroundTaskCompletionSignal(source, completion)
        method := typeof(PlaygroundTaskCompletionSignal).GetMethod("Signal", BindingFlags.Public | BindingFlags.Instance)
        if method == null {
            throw new InvalidOperationException("The configured Task completion signal method is missing.")
        }
        callback := Delegate.CreateDelegate(typeof(Action), signal, method)
        action := callback as Action
        if action == null {
            throw new InvalidOperationException("The configured Task completion signal could not be bound to Action.")
        }
        return action
    }
}

internal sealed class PlaygroundRunUnsupportedException: Exception {
    Code: string
    Line: int
    Column: int
    Length: int
    private messageValue: string
    Message: string => messageValue

    constructor(code: string, message: string, line: int = 0, column: int = 0, length: int = 0) {
        Code = code
        Line = line
        Column = column
        Length = length
        messageValue = message
    }
}
