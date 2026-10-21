namespace NSharpLang.Playground

import System
import System.Collections.Generic
import System.Globalization
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices
import System.Runtime.ExceptionServices
import System.Text
import System.Threading.Tasks
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

internal sealed class PlaygroundRunner {
    private units: List<CompilationUnit>
    private functions: Dictionary<string, FunctionDeclaration>
    private types: Dictionary<string, Declaration>
    private typeNamespaces: Dictionary<string, string?>
    private semanticModelsByDeclaration: IReadOnlyDictionary<object, SemanticModel>
    private stdout: StringBuilder
    private steps: int
    private outputLines: int

    constructor(sourceUnits: IEnumerable<CompilationUnit>, semanticModels: IReadOnlyDictionary<object, SemanticModel>) {
        units = sourceUnits.ToList()
        functions = new Dictionary<string, FunctionDeclaration>(StringComparer.Ordinal)
        types = new Dictionary<string, Declaration>(StringComparer.Ordinal)
        typeNamespaces = new Dictionary<string, string?>(StringComparer.Ordinal)
        semanticModelsByDeclaration = semanticModels
        stdout = new StringBuilder()
        steps = 0
        outputLines = 0

        for unit in units {
            for declaration in unit.Declarations {
                functionDeclaration := declaration as FunctionDeclaration
                if functionDeclaration != null {
                    functions[functionDeclaration.Name] = functionDeclaration
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
        entryPoint: FunctionDeclaration? = null
        for pair in functions {
            functionDeclaration := pair.Value
            if PlaygroundRunFacts.IsEntryPointFunctionName(functionDeclaration.Name) {
                entryPoint = functionDeclaration
                break
            }
        }
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

        awaited := expression as AwaitExpression
        if awaited != null {
            try {
                return await AwaitTaskValue(await EvaluateAsync(awaited.Expression, environment, depth))
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
            return await EvaluateAsyncCall(call, environment, depth)
        }

        member := expression as MemberAccessExpression
        if member != null {
            taskType := member.Object as IdentifierExpression
            if taskType != null && taskType.Name == "Task" && member.MemberName == "CompletedTask" {
                return Task.CompletedTask
            }
            valueTaskType := member.Object as IdentifierExpression
            if valueTaskType != null && valueTaskType.Name == "ValueTask" && member.MemberName == "CompletedTask" {
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
                argumentValue := await EvaluateAsync(newExpression.ConstructorArguments[i].Value, environment, depth)
                SetArrayElement(arguments, i, argumentValue)
                i += 1
            }
            created := EvaluateNewWithArguments(newExpression, arguments)
            if newExpression.Initializer != null {
                await ApplyAsyncInitializer(created, newExpression.Initializer, environment, depth)
            }
            return created
        }

        return Evaluate(expression, environment, depth)
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
                        return InvokeFunctionAsync(runtimeFunction.Declaration, arguments, runtimeFunction.Receiver, depth)
                    }
                    return InvokeFunction(runtimeFunction.Declaration, arguments, runtimeFunction.Receiver, depth)
                }
            }
            function: FunctionDeclaration? = null
            if functions.TryGetValue(identifier.Name, out function) {
                if AnalyzerAmbientContext.HasModifier(function, Modifiers.Async) {
                    return InvokeFunctionAsync(function, arguments, null, depth)
                }
                return InvokeFunction(function, arguments, null, depth)
            }
            throw Unsupported(PlaygroundRunFacts.UnknownFunction(identifier.Name))
        }

        member := call.Callee as MemberAccessExpression
        if member == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedCallee())
        }

        taskType := member.Object as IdentifierExpression
        if taskType != null && taskType.Name == "Task" {
            if member.MemberName == "Yield" && arguments.Length == 0 {
                return Task.Yield()
            }
            if member.MemberName == "Delay" && arguments.Length == 1 {
                return Task.Delay(ToInt(arguments[0]))
            }
            if member.MemberName == "FromResult" && arguments.Length == 1 {
                return Task.FromResult(arguments[0])
            }
            throw Unsupported(PlaygroundRunFacts.UnsupportedReceiverMember(member.MemberName))
        }
        valueTaskType := member.Object as IdentifierExpression
        if valueTaskType != null && valueTaskType.Name == "ValueTask" {
            if member.MemberName == "CompletedTask" && arguments.Length == 0 {
                return ValueTask.CompletedTask
            }
            if member.MemberName == "FromResult" && arguments.Length == 1 {
                return new ValueTask<object?>(arguments[0])
            }
            throw Unsupported(PlaygroundRunFacts.UnsupportedReceiverMember(member.MemberName))
        }

        target := await EvaluateAsync(member.Object, environment, depth)
        if member.MemberName == "ConfigureAwait" && arguments.Length == 1 {
            if target as Task != null {
                // There is no UI synchronization context in the hosted runner, so ConfigureAwait's
                // capture flag cannot change where its continuation runs. Keep the original Task.
                return target
            }
            if target != null {
                configuredValueTaskType := target.GetType()
                if configuredValueTaskType == typeof(ValueTask) || (configuredValueTaskType.IsGenericType && configuredValueTaskType.GetGenericTypeDefinition() == typeof(ValueTask<object?>).GetGenericTypeDefinition()) {
                    asTask := configuredValueTaskType.GetMethod("AsTask", BindingFlags.Public | BindingFlags.Instance)
                    if asTask != null {
                        try {
                            return asTask.Invoke(target, null)
                        } catch invocationFailure: TargetInvocationException {
                            RethrowInvocationFailure(invocationFailure)
                        }
                    }
                }
            }
        }
        runtimeObject := target as RuntimeObject
        if runtimeObject != null {
            method := FindMethod(runtimeObject.Declaration, member.MemberName, arguments.Length, false)
            if method == null {
                throw Unsupported(PlaygroundRunFacts.MethodNotFound(member.MemberName))
            }
            if AnalyzerAmbientContext.HasModifier(method, Modifiers.Async) {
                return InvokeFunctionAsync(method, arguments, runtimeObject, depth)
            }
            return InvokeFunction(method, arguments, runtimeObject, depth)
        }

        runtimeType := target as RuntimeType
        if runtimeType != null {
            method := FindMethod(runtimeType.Declaration, member.MemberName, arguments.Length, true)
            if method == null {
                throw Unsupported(PlaygroundRunFacts.StaticMethodNotFound(member.MemberName))
            }
            if AnalyzerAmbientContext.HasModifier(method, Modifiers.Async) {
                return InvokeFunctionAsync(method, arguments, null, depth)
            }
            return InvokeFunction(method, arguments, null, depth)
        }

        return CallClrLikeMember(target, member.MemberName, arguments)
    }

    async func AwaitTaskValue(value: object?): Task<object?> {
        if value == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand without a task value"))
        }

        runtimeObject := value as RuntimeObject
        if runtimeObject != null {
            return await AwaitSourceAwaitable(runtimeObject)
        }

        awaitableType := value.GetType()
        if awaitableType == typeof(YieldAwaitable) {
            // The browser linker does not preserve YieldAwaitable.GetAwaiter for reflection.
            // Task.Yield always suspends once, so model its await contract directly here.
            await Task.Yield()
            return null
        }
        pattern: AwaitablePatternBinding? = null
        if !AwaitablePatternBinder.TryBindReflection(awaitableType, out pattern) || pattern == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand has no accessible C# awaitable pattern"))
        }
        getAwaiter := pattern.GetAwaiter
        isCompletedGetter := pattern.IsCompletedGetter
        if getAwaiter == null || isCompletedGetter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand has no complete C# awaitable pattern"))
        }
        awaiter: object? = null
        try {
            awaiter = getAwaiter.Invoke(value, null)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        if awaiter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("GetAwaiter returned no awaiter"))
        }

        isCompleted := Convert.ToBoolean(isCompletedGetter.Invoke(awaiter, null))
        if !isCompleted {
            completion := new TaskCompletionSource<object?>(TaskCreationOptions.RunContinuationsAsynchronously)
            continuation := CreateAwaiterContinuation(completion)
            callbackArguments := new object?[](1)
            callbackArguments[0] = continuation
            try {
                pattern.CompletionSlot.Invoke(awaiter, callbackArguments)
            } catch invocationFailure: TargetInvocationException {
                RethrowInvocationFailure(invocationFailure)
            }
            await completion.Task
        }
        try {
            return pattern.GetResult.Invoke(awaiter, null)
        } catch invocationFailure: TargetInvocationException {
            RethrowInvocationFailure(invocationFailure)
        }
        return null
    }

    private async func AwaitSourceAwaitable(value: RuntimeObject): Task<object?> {
        getAwaiter := AwaitablePatternBinder.SelectSourceMethod(value.Declaration, "GetAwaiter", 0)
        if getAwaiter == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("await operand has no GetAwaiter method"))
        }
        awaiterValue := InvokeFunction(getAwaiter, new object?[](0), value, 0)
        awaiter := awaiterValue as RuntimeObject
        if awaiter == null {
            return await AwaitTaskValue(awaiterValue)
        }
        semanticModel: SemanticModel? = null
        sourcePattern: SourceAwaiterPatternBinding? = null
        if awaiter.Declaration == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("custom awaiter has no source declaration"))
        }
        if !semanticModelsByDeclaration.TryGetValue(awaiter.Declaration, out semanticModel) || semanticModel == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("custom awaiter has no bound source semantic model"))
        }
        failureReason: string = ""
        if !AwaitablePatternBinder.TryBindSourceAwaiter(awaiter.Declaration, semanticModel, out sourcePattern, out failureReason) {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression(failureReason))
        }
        if sourcePattern == null {
            throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("custom awaiter pattern binding returned no result"))
        }
        isCompletedValue := ReadRuntimeProperty(awaiter, sourcePattern.IsCompleted, 0)
        if !Convert.ToBoolean(isCompletedValue) {
            completion := new TaskCompletionSource<object?>(TaskCreationOptions.RunContinuationsAsynchronously)
            continuation := CreateAwaiterContinuation(completion)
            completionArguments := new object?[](1)
            completionArguments[0] = continuation
            InvokeFunction(sourcePattern.Completion, completionArguments, awaiter, 0)
            await completion.Task
        }
        return InvokeFunction(sourcePattern.GetResult, new object?[](0), awaiter, 0)
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
            return ResolveIdentifier(identifier.Name, environment)
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
        function: FunctionDeclaration? = null
        if functions.TryGetValue(name, out function) {
            return new RuntimeFunction(function, null)
        }
        declaration: Declaration? = null
        if types.TryGetValue(name, out declaration) {
            return new RuntimeType(declaration)
        }
        throw Unsupported(PlaygroundRunFacts.UnresolvedName(name))
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
            }
            return CallIdentifier(identifier.Name, arguments, depth)
        }
        member := call.Callee as MemberAccessExpression
        if member != null {
            return CallMember(member, arguments, environment, depth)
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedCallee())
    }

    private func CallIdentifier(name: string, arguments: IReadOnlyList<object?>, depth: int): object? {
        function: FunctionDeclaration? = null
        if functions.TryGetValue(name, out function) {
            return InvokeFunction(function, arguments, null, depth)
        }
        throw Unsupported(PlaygroundRunFacts.UnknownFunction(name))
    }

    private func CallMember(member: MemberAccessExpression, arguments: IReadOnlyList<object?>, environment: RuntimeEnvironment, depth: int): object? {
        target := Evaluate(member.Object, environment, depth)
        runtimeObject := target as RuntimeObject
        if runtimeObject != null {
            method := FindMethod(runtimeObject.Declaration, member.MemberName, arguments.Count, false)
            if method == null {
                throw Unsupported(PlaygroundRunFacts.MethodNotFound(member.MemberName))
            }
            return InvokeFunction(method, arguments, runtimeObject, depth)
        }
        runtimeType := target as RuntimeType
        if runtimeType != null {
            method := FindMethod(runtimeType.Declaration, member.MemberName, arguments.Count, true)
            if method == null {
                throw Unsupported(PlaygroundRunFacts.StaticMethodNotFound(member.MemberName))
            }
            return InvokeFunction(method, arguments, null, depth)
        }
        return CallClrLikeMember(target, member.MemberName, arguments)
    }

    private static func CallClrLikeMember(target: object?, memberName: string, arguments: IReadOnlyList<object?>): object? {
        callable := target as Delegate
        if callable != null {
            return callable.DynamicInvoke(ToInvocationArguments(arguments))
        }

        criticalAwaiter := target as ICriticalNotifyCompletion
        if criticalAwaiter != null && memberName == "UnsafeOnCompleted" && arguments.Count == 1 {
            continuation := arguments[0] as Action
            if continuation == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("awaiter continuation is not an Action"))
            }
            criticalAwaiter.UnsafeOnCompleted(continuation)
            return null
        }

        notifyAwaiter := target as INotifyCompletion
        if notifyAwaiter != null && memberName == "OnCompleted" && arguments.Count == 1 {
            continuation := arguments[0] as Action
            if continuation == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedExpression("awaiter continuation is not an Action"))
            }
            notifyAwaiter.OnCompleted(continuation)
            return null
        }

        text := target as string
        if text != null {
            if memberName == "ToUpper" && arguments.Count == 0 {
                return text.ToUpperInvariant()
            }
            if memberName == "ToLower" && arguments.Count == 0 {
                return text.ToLowerInvariant()
            }
            if memberName == "Contains" && arguments.Count == 1 {
                return text.Contains(FormatValue(arguments[0]), StringComparison.Ordinal)
            }
            if memberName == "StartsWith" && arguments.Count == 1 {
                return text.StartsWith(FormatValue(arguments[0]), StringComparison.Ordinal)
            }
            if memberName == "EndsWith" && arguments.Count == 1 {
                return text.EndsWith(FormatValue(arguments[0]), StringComparison.Ordinal)
            }
            if memberName == "IndexOf" && arguments.Count == 1 {
                return text.IndexOf(FormatValue(arguments[0]), StringComparison.Ordinal)
            }
            if memberName == "ToString" && arguments.Count == 0 {
                return text
            }
            throw Unsupported(PlaygroundRunFacts.UnsupportedStringMember(memberName))
        }

        if IsNumeric(target) {
            if memberName == "ToString" && arguments.Count == 0 {
                return FormatValue(target)
            }
            if memberName == "CompareTo" && arguments.Count == 1 {
                leftNumber := ToNumber(target)
                rightValue := arguments[0]
                rightNumber := ToNumber(rightValue)
                leftIsNaN := leftNumber != leftNumber
                rightIsNaN := rightNumber != rightNumber
                if leftIsNaN {
                    if rightIsNaN {
                        return 0
                    }
                    return -1
                }
                if rightIsNaN {
                    return 1
                }
                if leftNumber < rightNumber {
                    return -1
                }
                if leftNumber > rightNumber {
                    return 1
                }
                return 0
            }
            throw Unsupported(PlaygroundRunFacts.UnsupportedNumericMember(memberName))
        }

        if target != null {
            methods := target.GetType().GetMethods(BindingFlags.Public | BindingFlags.Instance)
            for method in methods {
                if method.Name != memberName || method.IsGenericMethodDefinition {
                    continue
                }
                parameters := method.GetParameters()
                if parameters.Length != arguments.Count {
                    continue
                }
                invocationArguments := ToInvocationArguments(arguments)
                matches := true
                parameterIndex := 0
                while parameterIndex < parameters.Length {
                    argument := invocationArguments[parameterIndex]
                    parameterType := parameters[parameterIndex].ParameterType
                    if argument == null {
                        if parameterType.IsValueType && Nullable.GetUnderlyingType(parameterType) == null {
                            matches = false
                            break
                        }
                    } else if !parameterType.IsInstanceOfType(argument) {
                        matches = false
                        break
                    }
                    parameterIndex += 1
                }
                if matches {
                    try {
                        return method.Invoke(target, invocationArguments)
                    } catch invocationFailure: TargetInvocationException {
                        RethrowInvocationFailure(invocationFailure)
                    }
                }
            }
        }
        throw Unsupported(PlaygroundRunFacts.UnsupportedReceiverMember(memberName))
    }

    private func EvaluateMemberAccess(member: MemberAccessExpression, environment: RuntimeEnvironment, depth: int): object? {
        target := Evaluate(member.Object, environment, depth)
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
            method := FindMethod(runtimeObject.Declaration, member.MemberName, null, false)
            if method != null {
                return new RuntimeFunction(method, runtimeObject)
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
            method := FindMethod(runtimeType.Declaration, member.MemberName, null, true)
            if method != null {
                return new RuntimeFunction(method, null)
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
            arguments[i] = Evaluate(newExpression.ConstructorArguments[i].Value, environment, depth)
            i = i + 1
        }
        created := EvaluateNewWithArguments(newExpression, arguments)
        if newExpression.Initializer != null {
            runtimeObject := created as RuntimeObject
            if runtimeObject == null {
                throw Unsupported(PlaygroundRunFacts.UnsupportedConstructionTarget())
            }
            ApplyInitializer(runtimeObject, newExpression.Initializer, environment, depth)
        }
        return created
    }

    private func EvaluateNewWithArguments(newExpression: NewExpression, arguments: IReadOnlyList<object?>): object {
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
            throw Unsupported(PlaygroundRunFacts.UnknownConstructedType(typeName))
        }
        namespaceName: string? = null
        typeNamespaces.TryGetValue(typeName, out namespaceName)
        runtimeObject := new RuntimeObject(declaration, new RuntimeEnvironment(null), namespaceName)
        ApplyPrimaryConstructorArguments(runtimeObject, arguments)
        return runtimeObject
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

    private func FindMethod(declaration: Declaration?, name: string, argumentCount: int?, requireStatic: bool): FunctionDeclaration? {
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
                } else {
                    interfaceDeclaration := declaration as InterfaceDeclaration
                    if interfaceDeclaration != null {
                        members = interfaceDeclaration.Members
                    }
                }
            }
        }
        if members == null {
            return null
        }
        for member in members {
            function := member as FunctionDeclaration
            if function != null && string.Equals(function.Name, name, StringComparison.Ordinal) {
                matchesArity := argumentCount == null || function.Parameters.Count == argumentCount.Value
                if matchesArity {
                    modifierValue := Convert.ToInt32(function.Modifiers)
                    isStatic := (modifierValue & Convert.ToInt32(Modifiers.Static)) != 0
                    if isStatic == requireStatic {
                        return function
                    }
                }
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

        constructor(parentEnvironment: RuntimeEnvironment?) {
            parent = parentEnvironment
            values = new Dictionary<string, object?>(StringComparer.Ordinal)
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

    private sealed record RuntimeFunction(Declaration: FunctionDeclaration, Receiver: RuntimeObject?) {
    }

    private sealed class RuntimeObject {
        Declaration: Declaration?
        Environment: RuntimeEnvironment
        NamespaceName: string?
        Fields: Dictionary<string, object?>

        constructor(declaration: Declaration?, environment: RuntimeEnvironment, namespaceName: string?) {
            Declaration = declaration
            Environment = environment
            NamespaceName = namespaceName
            Fields = new Dictionary<string, object?>(StringComparer.Ordinal)
        }

        func Clone(): RuntimeObject {
            copy := new RuntimeObject(Declaration, new RuntimeEnvironment(null), NamespaceName)
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
