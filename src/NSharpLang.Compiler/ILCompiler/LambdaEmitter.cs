using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// Lambda emission support for IL compiler
/// </summary>
public partial class ILCompiler
{
    /// <summary>
    /// Emit IL for a lambda expression
    /// </summary>
    private void EmitLambda(LambdaExpression lambda, Type? contextualDelegateType = null)
    {
        if (_currentIL == null || _programType == null || _moduleBuilder == null)
            throw new InvalidOperationException("No IL generator context");

        contextualDelegateType ??= _expectedExpressionType;

        if (contextualDelegateType != null && TryGetExpressionTreeDelegateType(contextualDelegateType, out var expressionDelegateType))
        {
            EmitExpressionTreeLambda(lambda, contextualDelegateType, expressionDelegateType);
            return;
        }

        // Analyze lambda to determine if it captures variables
        var capturedVariables = AnalyzeCapturedVariables(lambda);

        if (capturedVariables.Count == 0)
        {
            // Simple lambda - no closures needed
            EmitSimpleLambda(lambda, contextualDelegateType);
        }
        else
        {
            // Lambda with closures - need to create a display class
            EmitClosureLambda(lambda, capturedVariables, contextualDelegateType);
        }
    }

    /// <summary>
    /// Analyze which variables are captured by a lambda expression
    /// </summary>
    private HashSet<string> AnalyzeCapturedVariables(LambdaExpression lambda)
    {
        var captured = new HashSet<string>();
        var parameterNames = new HashSet<string>(lambda.Parameters.Select(p => p.Name));

        if (_currentHasThis)
        {
            captured.Add(ThisCaptureName);
        }

        // Find all referenced variables that are not parameters
        if (lambda.ExpressionBody != null)
        {
            FindCapturedVariablesInExpression(lambda.ExpressionBody, parameterNames, captured);
        }
        else if (lambda.BlockBody != null)
        {
            FindCapturedVariablesInStatement(lambda.BlockBody, parameterNames, captured);
        }

        return captured;
    }

    private void FindCapturedVariablesInExpression(Expression expr, HashSet<string> parameterNames, HashSet<string> captured)
    {
        switch (expr)
        {
            case IdentifierExpression ident:
                // If it's not a parameter and exists in our local or parameter scope, it's captured
                if (!parameterNames.Contains(ident.Name))
                {
                    if (_locals != null && _locals.ContainsKey(ident.Name))
                    {
                        captured.Add(ident.Name);
                    }
                    else if (_parameters != null && _parameters.ContainsKey(ident.Name))
                    {
                        captured.Add(ident.Name);
                    }
                    else if (_closureFields != null && _closureFields.ContainsKey(ident.Name))
                    {
                        captured.Add(ident.Name);
                    }
                }
                break;

            case BinaryExpression binary:
                FindCapturedVariablesInExpression(binary.Left, parameterNames, captured);
                FindCapturedVariablesInExpression(binary.Right, parameterNames, captured);
                break;

            case CallExpression call:
                FindCapturedVariablesInExpression(call.Callee, parameterNames, captured);
                foreach (var arg in call.Arguments)
                    FindCapturedVariablesInExpression(arg.Value, parameterNames, captured);
                break;

            case MemberAccessExpression member:
                FindCapturedVariablesInExpression(member.Object, parameterNames, captured);
                break;

            case IndexAccessExpression indexAccess:
                FindCapturedVariablesInExpression(indexAccess.Object, parameterNames, captured);
                FindCapturedVariablesInExpression(indexAccess.Index, parameterNames, captured);
                break;

            case AssignmentExpression assignment:
                FindCapturedVariablesInExpression(assignment.Target, parameterNames, captured);
                FindCapturedVariablesInExpression(assignment.Value, parameterNames, captured);
                break;

            case NewExpression newExpr:
                foreach (var arg in newExpr.ConstructorArguments)
                    FindCapturedVariablesInExpression(arg.Value, parameterNames, captured);
                if (newExpr.Initializer != null)
                {
                    foreach (var property in newExpr.Initializer.Properties)
                    {
                        if (property.IndexExpression != null)
                            FindCapturedVariablesInExpression(property.IndexExpression, parameterNames, captured);
                        FindCapturedVariablesInExpression(property.Value, parameterNames, captured);
                    }
                }
                break;

            case LambdaExpression nestedLambda:
                // Nested lambdas - parameters shadow outer scope
                var nestedParams = new HashSet<string>(parameterNames);
                foreach (var p in nestedLambda.Parameters)
                    nestedParams.Add(p.Name);
                if (nestedLambda.ExpressionBody != null)
                    FindCapturedVariablesInExpression(nestedLambda.ExpressionBody, nestedParams, captured);
                else if (nestedLambda.BlockBody != null)
                    FindCapturedVariablesInStatement(nestedLambda.BlockBody, nestedParams, captured);
                break;

            case ParenthesizedExpression paren:
                FindCapturedVariablesInExpression(paren.Inner, parameterNames, captured);
                break;

            case TernaryExpression ternary:
                FindCapturedVariablesInExpression(ternary.Condition, parameterNames, captured);
                FindCapturedVariablesInExpression(ternary.ThenExpression, parameterNames, captured);
                FindCapturedVariablesInExpression(ternary.ElseExpression, parameterNames, captured);
                break;

            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                    FindCapturedVariablesInExpression(element, parameterNames, captured);
                break;

            case SpreadExpression spread:
                FindCapturedVariablesInExpression(spread.Expression, parameterNames, captured);
                break;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                    FindCapturedVariablesInExpression(element.Value, parameterNames, captured);
                break;

            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                    FindCapturedVariablesInExpression(hole.Expression, parameterNames, captured);
                break;

            case RangeExpression range:
                if (range.Start != null)
                    FindCapturedVariablesInExpression(range.Start, parameterNames, captured);
                if (range.End != null)
                    FindCapturedVariablesInExpression(range.End, parameterNames, captured);
                break;

            case IsExpression isExpression:
                FindCapturedVariablesInExpression(isExpression.Expression, parameterNames, captured);
                break;

            case WithExpression withExpression:
                FindCapturedVariablesInExpression(withExpression.Target, parameterNames, captured);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                        FindCapturedVariablesInExpression(property.IndexExpression, parameterNames, captured);
                    FindCapturedVariablesInExpression(property.Value, parameterNames, captured);
                }
                break;

            case AwaitExpression awaitExpression:
                FindCapturedVariablesInExpression(awaitExpression.Expression, parameterNames, captured);
                break;

            case ThrowExpression throwExpression:
                FindCapturedVariablesInExpression(throwExpression.Expression, parameterNames, captured);
                break;

            case CastExpression castExpression:
                FindCapturedVariablesInExpression(castExpression.Expression, parameterNames, captured);
                break;

            case CheckedExpression checkedExpression:
                FindCapturedVariablesInExpression(checkedExpression.Expression, parameterNames, captured);
                break;

            case UncheckedExpression uncheckedExpression:
                FindCapturedVariablesInExpression(uncheckedExpression.Expression, parameterNames, captured);
                break;

            case MatchExpression matchExpression:
                FindCapturedVariablesInExpression(matchExpression.Value, parameterNames, captured);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                        FindCapturedVariablesInExpression(matchCase.Guard, parameterNames, captured);
                    FindCapturedVariablesInExpression(matchCase.Expression, parameterNames, captured);
                }
                break;
        }
    }

    private void FindCapturedVariablesInStatement(Statement stmt, HashSet<string> parameterNames, HashSet<string> captured)
    {
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                FindCapturedVariablesInExpression(exprStmt.Expression, parameterNames, captured);
                break;

            case BlockStatement block:
                foreach (var s in block.Statements)
                    FindCapturedVariablesInStatement(s, parameterNames, captured);
                break;

            case VariableDeclarationStatement variableDeclaration when variableDeclaration.Initializer != null:
                FindCapturedVariablesInExpression(variableDeclaration.Initializer, parameterNames, captured);
                break;

            case TupleDeconstructionStatement tupleDeconstruction:
                FindCapturedVariablesInExpression(tupleDeconstruction.Initializer, parameterNames, captured);
                break;

            case ReturnStatement ret:
                if (ret.Value != null)
                    FindCapturedVariablesInExpression(ret.Value, parameterNames, captured);
                break;

            case IfStatement ifStmt:
                FindCapturedVariablesInExpression(ifStmt.Condition, parameterNames, captured);
                FindCapturedVariablesInStatement(ifStmt.ThenStatement, parameterNames, captured);
                if (ifStmt.ElseStatement != null)
                    FindCapturedVariablesInStatement(ifStmt.ElseStatement, parameterNames, captured);
                break;

            case WhileStatement whileStmt:
                FindCapturedVariablesInExpression(whileStmt.Condition, parameterNames, captured);
                FindCapturedVariablesInStatement(whileStmt.Body, parameterNames, captured);
                break;

            case ForStatement forStmt:
                if (forStmt.Initializer != null)
                    FindCapturedVariablesInStatement(forStmt.Initializer, parameterNames, captured);
                if (forStmt.Condition != null)
                    FindCapturedVariablesInExpression(forStmt.Condition, parameterNames, captured);
                if (forStmt.Iterator != null)
                    FindCapturedVariablesInExpression(forStmt.Iterator, parameterNames, captured);
                FindCapturedVariablesInStatement(forStmt.Body, parameterNames, captured);
                break;

            case ForeachStatement foreachStatement:
                FindCapturedVariablesInExpression(foreachStatement.Collection, parameterNames, captured);
                FindCapturedVariablesInStatement(foreachStatement.Body, parameterNames, captured);
                break;

            case AwaitForEachStatement awaitForEachStatement:
                FindCapturedVariablesInExpression(awaitForEachStatement.Collection, parameterNames, captured);
                FindCapturedVariablesInStatement(awaitForEachStatement.Body, parameterNames, captured);
                break;

            case ThrowStatement throwStatement:
                FindCapturedVariablesInExpression(throwStatement.Expression, parameterNames, captured);
                break;

            case TryStatement tryStatement:
                FindCapturedVariablesInStatement(tryStatement.TryBlock, parameterNames, captured);
                foreach (var catchClause in tryStatement.CatchClauses)
                    FindCapturedVariablesInStatement(catchClause.Block, parameterNames, captured);
                if (tryStatement.FinallyBlock != null)
                    FindCapturedVariablesInStatement(tryStatement.FinallyBlock, parameterNames, captured);
                break;

            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                    FindCapturedVariablesInExpression(usingStatement.Declaration.Initializer, parameterNames, captured);
                if (usingStatement.Expression != null)
                    FindCapturedVariablesInExpression(usingStatement.Expression, parameterNames, captured);
                if (usingStatement.Body != null)
                    FindCapturedVariablesInStatement(usingStatement.Body, parameterNames, captured);
                break;

            case LockStatement lockStatement:
                FindCapturedVariablesInExpression(lockStatement.LockObject, parameterNames, captured);
                FindCapturedVariablesInStatement(lockStatement.Body, parameterNames, captured);
                break;

            case SwitchStatement switchStatement:
                FindCapturedVariablesInExpression(switchStatement.Value, parameterNames, captured);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                        FindCapturedVariablesInStatement(caseStatement, parameterNames, captured);
                }
                break;

            case PrintStatement printStatement:
                FindCapturedVariablesInExpression(printStatement.Value, parameterNames, captured);
                break;

            case AssertStatement assertStatement:
                FindCapturedVariablesInExpression(assertStatement.Condition, parameterNames, captured);
                if (assertStatement.Message != null)
                    FindCapturedVariablesInExpression(assertStatement.Message, parameterNames, captured);
                break;

            case AssertThrowsStatement assertThrowsStatement:
                FindCapturedVariablesInStatement(assertThrowsStatement.Body, parameterNames, captured);
                break;

            case LocalFunctionStatement localFunctionStatement:
                if (localFunctionStatement.Function.ExpressionBody != null)
                    FindCapturedVariablesInExpression(localFunctionStatement.Function.ExpressionBody, parameterNames, captured);
                if (localFunctionStatement.Function.Body != null)
                    FindCapturedVariablesInStatement(localFunctionStatement.Function.Body, parameterNames, captured);
                break;
        }
    }

    /// <summary>
    /// Emit a simple lambda (no closures) as a static method with a delegate
    /// </summary>
    private void EmitSimpleLambda(LambdaExpression lambda, Type? contextualDelegateType)
    {
        if (_currentIL == null || _programType == null)
            throw new InvalidOperationException("No IL generator context");

        GetLambdaSignature(lambda, out var parameterTypes, out var returnType);

        // Create a static method for the lambda
        var lambdaMethod = _programType.DefineMethod(
            $"<Lambda>_{_lambdaCounter++}",
            MethodAttributes.Private | MethodAttributes.Static,
            returnType,
            parameterTypes);

        // Emit the lambda body
        var il = lambdaMethod.GetILGenerator();

        // Save current context
        var savedIL = _currentIL;
        var savedLocals = _locals;
        var savedParameters = _parameters;
        var savedParameterTypes = _parameterTypes;
        var savedByRefParameters = _byRefParameters;
        var savedInferredLocalTypes = _inferredLocalTypes;
        var savedCurrentReturnType = _currentReturnType;
        var savedCurrentAsyncReturnType = _currentAsyncReturnType;
        var savedCurrentAsyncResultType = _currentAsyncResultType;
        var savedCurrentAsyncReturnsValueTask = _currentAsyncReturnsValueTask;
        var savedCurrentGeneratorReturnType = _currentGeneratorReturnType;
        var savedCurrentYieldElementType = _currentYieldElementType;
        var savedCurrentYieldListLocal = _currentYieldListLocal;
        var savedCurrentYieldBreakLabel = _currentYieldBreakLabel;
        var savedExpectedExpressionType = _expectedExpressionType;
        var savedLiftLocalsIntoBoxes = _liftLocalsIntoBoxes;
        var savedLiftedIdentifiers = _liftedIdentifiers;
        var savedLiftedClosureFields = _liftedClosureFields;
        var savedCurrentHasThis = _currentHasThis;
        var localFunctionDefinition = _pendingLocalFunctionDefinition;

        // Set up lambda context
        _currentIL = il;
        var bodyReturnType = returnType;
        if (localFunctionDefinition?.Modifiers.HasFlag(Modifiers.Async) == true
            && TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
        {
            _currentAsyncReturnType = returnType;
            _currentAsyncResultType = asyncResultType;
            _currentAsyncReturnsValueTask = returnsValueTask;
            bodyReturnType = asyncResultType ?? typeof(void);
        }

        InitializeBodyContext(bodyReturnType, ContainsNestedFunction(lambda.BlockBody)
            || (lambda.ExpressionBody != null && ContainsNestedFunction(lambda.ExpressionBody)));
        _inferredLocalTypes = null;
        _currentHasThis = false;
        _expectedExpressionType = null;

        if (localFunctionDefinition?.Modifiers.HasFlag(Modifiers.Generator) == true)
        {
            if (!TryGetSequenceElementType(returnType, out var yieldElementType, out _))
            {
                throw new InvalidOperationException($"Generator local function must return a sequence type, but got {returnType}");
            }

            _currentGeneratorReturnType = returnType;
            _currentYieldElementType = yieldElementType;
            _currentYieldBreakLabel = _currentIL.DefineLabel();
            var listType = typeof(List<>).MakeGenericType(yieldElementType);
            _currentYieldListLocal = _currentIL.DeclareLocal(listType);
            var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
                ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
            _currentIL.Emit(OpCodes.Newobj, listCtor);
            _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
        }

        RegisterParameterContext(lambda.Parameters, parameterTypes, 0);

        // Emit body
        if (lambda.ExpressionBody != null)
        {
            if (_currentAsyncReturnType != null)
            {
                if (_currentAsyncResultType != null)
                {
                    EmitExpressionWithExpectedType(lambda.ExpressionBody, _currentAsyncResultType);
                }
                else
                {
                    EmitExpression(lambda.ExpressionBody);
                    if (GetExpressionType(lambda.ExpressionBody) != typeof(void))
                    {
                        il.Emit(OpCodes.Pop);
                    }
                }

                EmitWrapCurrentAsyncReturn();
            }
            else
            {
                EmitExpressionWithExpectedType(lambda.ExpressionBody, returnType);
            }

            il.Emit(OpCodes.Ret);
        }
        else if (lambda.BlockBody != null)
        {
            EmitStatement(lambda.BlockBody);

            if (_currentGeneratorReturnType != null)
            {
                il.MarkLabel(_currentYieldBreakLabel!.Value);
                EmitGeneratorReturnValue(_currentGeneratorReturnType, _currentYieldListLocal!);
                il.Emit(OpCodes.Ret);
            }
            else if (_currentAsyncReturnType != null && _currentAsyncResultType == null)
            {
                EmitWrapCurrentAsyncReturn();
                il.Emit(OpCodes.Ret);
            }
            else if (returnType == typeof(void))
            {
                il.Emit(OpCodes.Ret);
            }
        }

        // Restore context
        _currentIL = savedIL;
        _locals = savedLocals;
        _parameters = savedParameters;
        _parameterTypes = savedParameterTypes;
        _byRefParameters = savedByRefParameters;
        _inferredLocalTypes = savedInferredLocalTypes;
        _currentReturnType = savedCurrentReturnType;
        _currentAsyncReturnType = savedCurrentAsyncReturnType;
        _currentAsyncResultType = savedCurrentAsyncResultType;
        _currentAsyncReturnsValueTask = savedCurrentAsyncReturnsValueTask;
        _currentGeneratorReturnType = savedCurrentGeneratorReturnType;
        _currentYieldElementType = savedCurrentYieldElementType;
        _currentYieldListLocal = savedCurrentYieldListLocal;
        _currentYieldBreakLabel = savedCurrentYieldBreakLabel;
        _expectedExpressionType = savedExpectedExpressionType;
        _liftLocalsIntoBoxes = savedLiftLocalsIntoBoxes;
        _liftedIdentifiers = savedLiftedIdentifiers;
        _liftedClosureFields = savedLiftedClosureFields;
        _currentHasThis = savedCurrentHasThis;

        var delegateType = ResolveLambdaDelegateType(parameterTypes, returnType, contextualDelegateType ?? savedExpectedExpressionType);

        // Emit delegate creation: ldnull, ldftn, newobj
        _currentIL.Emit(OpCodes.Ldnull);
        _currentIL.Emit(OpCodes.Ldftn, lambdaMethod);
        _currentIL.Emit(OpCodes.Newobj, GetDelegateConstructor(delegateType));
    }

    /// <summary>
    /// Emit a lambda with closures using a display class
    /// </summary>
    private void EmitClosureLambda(LambdaExpression lambda, HashSet<string> capturedVariables, Type? contextualDelegateType)
    {
        if (_currentIL == null || _programType == null || _moduleBuilder == null)
            throw new InvalidOperationException("No IL generator context");

        // Create closure class (display class)
        var closureClass = _moduleBuilder.DefineType(
            $"<>c__DisplayClass{_closureCounter++}",
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object));
        var closureCtor = closureClass.DefineDefaultConstructor(MethodAttributes.Public);
        _closureTypes.Add(closureClass);

        // Add fields for captured variables
        var closureFields = new Dictionary<string, FieldBuilder>();
        foreach (var varName in capturedVariables)
        {
            Type fieldType = typeof(object); // Default to object

            // Try to get actual type from locals or parameters
            if (_locals != null && _locals.TryGetValue(varName, out var local))
            {
                fieldType = local.LocalType;
            }
            else if (_closureFields != null && _closureFields.TryGetValue(varName, out var outerClosureField))
            {
                fieldType = outerClosureField.FieldType;
            }
            else if (_parameterTypes != null && _parameterTypes.TryGetValue(varName, out var paramType))
            {
                fieldType = paramType;
            }
            else if (varName == ThisCaptureName && _currentTypeBuilder != null)
            {
                fieldType = _currentTypeBuilder;
            }

            var field = closureClass.DefineField(varName, fieldType, FieldAttributes.Public);
            closureFields[varName] = field;
        }

        GetLambdaSignature(lambda, out var parameterTypes, out var returnType);

        // Create lambda method on closure class
        var lambdaMethod = closureClass.DefineMethod(
            "<Lambda>",
            MethodAttributes.Public,
            returnType,
            parameterTypes);

        // Emit lambda body
        var il = lambdaMethod.GetILGenerator();

        // Save current context
        var savedIL = _currentIL;
        var savedLocals = _locals;
        var savedParameters = _parameters;
        var savedParameterTypes = _parameterTypes;
        var savedByRefParameters = _byRefParameters;
        var savedCurrentReturnType = _currentReturnType;
        var savedCurrentAsyncReturnType = _currentAsyncReturnType;
        var savedCurrentAsyncResultType = _currentAsyncResultType;
        var savedCurrentAsyncReturnsValueTask = _currentAsyncReturnsValueTask;
        var savedCurrentGeneratorReturnType = _currentGeneratorReturnType;
        var savedCurrentYieldElementType = _currentYieldElementType;
        var savedCurrentYieldListLocal = _currentYieldListLocal;
        var savedCurrentYieldBreakLabel = _currentYieldBreakLabel;
        var savedExpectedExpressionType = _expectedExpressionType;
        var savedCurrentTypeBuilder = _currentTypeBuilder;
        var savedClosureFields = _closureFields;
        var savedLiftLocalsIntoBoxes = _liftLocalsIntoBoxes;
        var savedLiftedIdentifiers = _liftedIdentifiers;
        var savedLiftedClosureFields = _liftedClosureFields;
        var savedCurrentHasThis = _currentHasThis;
        var localFunctionDefinition = _pendingLocalFunctionDefinition;

        var liftedClosureFields = new HashSet<string>(capturedVariables.Where(varName =>
            IsLiftedIdentifier(varName) || IsLiftedClosureField(varName)));

        // Set up lambda context
        _currentIL = il;
        var bodyReturnType = returnType;
        if (localFunctionDefinition?.Modifiers.HasFlag(Modifiers.Async) == true
            && TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
        {
            _currentAsyncReturnType = returnType;
            _currentAsyncResultType = asyncResultType;
            _currentAsyncReturnsValueTask = returnsValueTask;
            bodyReturnType = asyncResultType ?? typeof(void);
        }

        InitializeBodyContext(bodyReturnType, ContainsNestedFunction(lambda.BlockBody)
            || (lambda.ExpressionBody != null && ContainsNestedFunction(lambda.ExpressionBody)));
        _currentHasThis = true;
        _expectedExpressionType = null;
        _currentTypeBuilder = closureClass;
        _closureFields = closureFields;
        _liftedClosureFields = liftedClosureFields;

        if (localFunctionDefinition?.Modifiers.HasFlag(Modifiers.Generator) == true)
        {
            if (!TryGetSequenceElementType(returnType, out var yieldElementType, out _))
            {
                throw new InvalidOperationException($"Generator local function must return a sequence type, but got {returnType}");
            }

            _currentGeneratorReturnType = returnType;
            _currentYieldElementType = yieldElementType;
            _currentYieldBreakLabel = _currentIL.DefineLabel();
            var listType = typeof(List<>).MakeGenericType(yieldElementType);
            _currentYieldListLocal = _currentIL.DeclareLocal(listType);
            var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
                ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
            _currentIL.Emit(OpCodes.Newobj, listCtor);
            _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
        }

        // Register parameters (offset by 1 for 'this')
        RegisterParameterContext(lambda.Parameters, parameterTypes, 1);

        // Emit body - captured variables will be accessed as fields via 'this'
        if (lambda.ExpressionBody != null)
        {
            if (_currentAsyncReturnType != null)
            {
                if (_currentAsyncResultType != null)
                {
                    EmitExpressionWithExpectedType(lambda.ExpressionBody, _currentAsyncResultType);
                }
                else
                {
                    EmitExpression(lambda.ExpressionBody);
                    if (GetExpressionType(lambda.ExpressionBody) != typeof(void))
                    {
                        il.Emit(OpCodes.Pop);
                    }
                }

                EmitWrapCurrentAsyncReturn();
            }
            else
            {
                EmitExpressionWithExpectedType(lambda.ExpressionBody, returnType);
            }

            il.Emit(OpCodes.Ret);
        }
        else if (lambda.BlockBody != null)
        {
            EmitStatement(lambda.BlockBody);

            if (_currentGeneratorReturnType != null)
            {
                il.MarkLabel(_currentYieldBreakLabel!.Value);
                EmitGeneratorReturnValue(_currentGeneratorReturnType, _currentYieldListLocal!);
                il.Emit(OpCodes.Ret);
            }
            else if (_currentAsyncReturnType != null && _currentAsyncResultType == null)
            {
                EmitWrapCurrentAsyncReturn();
                il.Emit(OpCodes.Ret);
            }
            else if (returnType == typeof(void))
            {
                il.Emit(OpCodes.Ret);
            }
        }

        // Restore context
        _currentIL = savedIL;
        _locals = savedLocals;
        _parameters = savedParameters;
        _parameterTypes = savedParameterTypes;
        _byRefParameters = savedByRefParameters;
        _currentReturnType = savedCurrentReturnType;
        _currentAsyncReturnType = savedCurrentAsyncReturnType;
        _currentAsyncResultType = savedCurrentAsyncResultType;
        _currentAsyncReturnsValueTask = savedCurrentAsyncReturnsValueTask;
        _currentGeneratorReturnType = savedCurrentGeneratorReturnType;
        _currentYieldElementType = savedCurrentYieldElementType;
        _currentYieldListLocal = savedCurrentYieldListLocal;
        _currentYieldBreakLabel = savedCurrentYieldBreakLabel;
        _expectedExpressionType = savedExpectedExpressionType;
        _currentTypeBuilder = savedCurrentTypeBuilder;
        _closureFields = savedClosureFields;
        _liftLocalsIntoBoxes = savedLiftLocalsIntoBoxes;
        _liftedIdentifiers = savedLiftedIdentifiers;
        _liftedClosureFields = savedLiftedClosureFields;
        _currentHasThis = savedCurrentHasThis;

        // Instantiate closure and set captured variable values
        _currentIL.Emit(OpCodes.Newobj, closureCtor);

        // Duplicate the closure instance for each field assignment
        foreach (var varName in capturedVariables)
        {
            _currentIL.Emit(OpCodes.Dup);

            // Load the captured variable value
            if (varName == ThisCaptureName)
            {
                _currentIL.Emit(OpCodes.Ldarg_0);
            }
            else if (_locals != null && _locals.TryGetValue(varName, out var local))
            {
                _currentIL.Emit(OpCodes.Ldloc, local);
            }
            else if (_closureFields != null && _closureFields.TryGetValue(varName, out var outerClosureField))
            {
                var capturedValueLocal = _currentIL.DeclareLocal(outerClosureField.FieldType);
                _currentIL.Emit(OpCodes.Ldarg_0);
                _currentIL.Emit(OpCodes.Ldfld, outerClosureField);
                _currentIL.Emit(OpCodes.Stloc, capturedValueLocal);
                _currentIL.Emit(OpCodes.Ldloc, capturedValueLocal);
            }
            else if (_parameters != null && _parameters.TryGetValue(varName, out var paramIndex))
            {
                EmitLoadArg(paramIndex);
            }

            // Store into field
            _currentIL.Emit(OpCodes.Stfld, closureFields[varName]);
        }

        var delegateType = ResolveLambdaDelegateType(parameterTypes, returnType, contextualDelegateType ?? savedExpectedExpressionType);

        // The closure instance is already on the stack
        _currentIL.Emit(OpCodes.Ldftn, lambdaMethod);
        _currentIL.Emit(OpCodes.Newobj, GetDelegateConstructor(delegateType));
    }

    private Type ResolveLambdaDelegateType(Type[] parameterTypes, Type returnType, Type? expectedType)
    {
        if (expectedType != null
            && TryGetExpressionTreeDelegateType(expectedType, out var expressionDelegateType))
        {
            expectedType = expressionDelegateType;
        }

        if (expectedType != null
            && typeof(Delegate).IsAssignableFrom(expectedType)
            && TryGetDelegateInvokeMethod(expectedType, out var invokeMethod)
            && invokeMethod != null)
        {
            var expectedParameterTypes = GetDelegateInvokeParameterTypes(expectedType, invokeMethod);
            var expectedReturnType = GetDelegateInvokeReturnType(expectedType, invokeMethod);

            if (expectedParameterTypes.Length == parameterTypes.Length
                && expectedParameterTypes.Zip(parameterTypes, AreTypeIdentitiesEquivalent).All(matches => matches)
                && AreLambdaReturnTypesCompatible(expectedReturnType, returnType))
            {
                return expectedType;
            }
        }

        return CreateDelegateType(parameterTypes, returnType);
    }

    private static bool AreLambdaReturnTypesCompatible(Type expectedReturnType, Type actualReturnType)
    {
        if (AreTypeIdentitiesEquivalent(expectedReturnType, actualReturnType))
        {
            return true;
        }

        if (expectedReturnType == typeof(void) || actualReturnType == typeof(void))
        {
            return false;
        }

        return expectedReturnType.IsAssignableFrom(actualReturnType);
    }

    private void GetLambdaSignature(LambdaExpression lambda, out Type[] parameterTypes, out Type returnType)
    {
        if (_pendingLocalFunctionDefinition != null)
        {
            parameterTypes = _pendingLocalFunctionDefinition.Parameters
                .Select(parameter => ResolveParameterType(parameter, _currentGenericParameters))
                .ToArray();
            returnType = GetLocalFunctionReturnType(_pendingLocalFunctionDefinition);
            return;
        }

        MethodInfo? expectedInvokeMethod = null;
        Type[]? expectedParameterTypes = null;
        Type? expectedReturnType = null;
        var expectedDelegateType = _expectedExpressionType != null
            && TryGetExpressionTreeDelegateType(_expectedExpressionType, out var expressionDelegateType)
                ? expressionDelegateType
                : _expectedExpressionType;

        if (expectedDelegateType != null && TryGetDelegateInvokeMethod(expectedDelegateType, out var invokeMethod) && invokeMethod != null)
        {
            expectedInvokeMethod = invokeMethod;
            expectedParameterTypes = GetDelegateInvokeParameterTypes(expectedDelegateType, invokeMethod);
            expectedReturnType = GetDelegateInvokeReturnType(expectedDelegateType, invokeMethod);
        }

        var canUseExpectedParameters = expectedParameterTypes != null && expectedParameterTypes.Length == lambda.Parameters.Count;

        parameterTypes = lambda.Parameters.Select((parameter, index) =>
        {
            var hasExplicitType = parameter.Type is not null
                && parameter.Type is not SimpleTypeReference { Name: "var" };

            if (hasExplicitType)
            {
                return ResolveType(parameter.Type!, _currentGenericParameters);
            }

            if (canUseExpectedParameters)
            {
                return GetByRefElementType(expectedParameterTypes![index]);
            }

            return typeof(object);
        }).ToArray();

        if (expectedReturnType != null)
        {
            returnType = GetByRefElementType(expectedReturnType);
            return;
        }

        if (lambda.ExpressionBody != null)
        {
            var savedExpectedExpressionType = _expectedExpressionType;
            if (expectedInvokeMethod == null)
            {
                _expectedExpressionType = null;
            }

            try
            {
                returnType = GetExpressionType(lambda.ExpressionBody);
                return;
            }
            finally
            {
                _expectedExpressionType = savedExpectedExpressionType;
            }
        }

        if (lambda.BlockBody != null)
        {
            returnType = InferLambdaBlockReturnType(lambda.BlockBody);
            return;
        }

        returnType = typeof(void);
    }

    private Type InferLambdaBlockReturnType(BlockStatement block)
    {
        List<Type>? returnTypes = null;
        CollectLambdaReturnTypes(block, ref returnTypes);

        if (returnTypes == null || returnTypes.Count == 0)
        {
            return typeof(void);
        }

        var inferredType = returnTypes[0];
        foreach (var returnType in returnTypes.Skip(1))
        {
            if (returnType == inferredType)
            {
                continue;
            }

            if (inferredType.IsAssignableFrom(returnType))
            {
                continue;
            }

            if (returnType.IsAssignableFrom(inferredType))
            {
                inferredType = returnType;
                continue;
            }

            return typeof(object);
        }

        return inferredType;
    }

    private void CollectLambdaReturnTypes(Statement statement, ref List<Type>? returnTypes)
    {
        switch (statement)
        {
            case ReturnStatement { Value: not null } returnStatement:
                returnTypes ??= new List<Type>();
                returnTypes.Add(GetExpressionType(returnStatement.Value));
                break;

            case BlockStatement block:
                var savedInferredLocalTypes = _inferredLocalTypes != null
                    ? new Dictionary<string, Type>(_inferredLocalTypes)
                    : null;
                try
                {
                    foreach (var child in block.Statements)
                    {
                        CollectLambdaReturnTypes(child, ref returnTypes);
                    }
                }
                finally
                {
                    if (_inferredLocalTypes != null && savedInferredLocalTypes != null)
                    {
                        _inferredLocalTypes.Clear();
                        foreach (var (name, type) in savedInferredLocalTypes)
                        {
                            _inferredLocalTypes[name] = type;
                        }
                    }
                }
                break;

            case VariableDeclarationStatement variableDeclaration:
                if (_inferredLocalTypes != null)
                {
                    _inferredLocalTypes[variableDeclaration.Name] = variableDeclaration.Type != null
                        ? ResolveType(variableDeclaration.Type, _currentGenericParameters)
                        : variableDeclaration.Initializer != null
                            ? GetExpressionType(variableDeclaration.Initializer)
                            : typeof(object);
                }
                break;

            case TupleDeconstructionStatement tupleDeconstruction:
                if (_inferredLocalTypes != null)
                {
                    for (int i = 0; i < tupleDeconstruction.Names.Count; i++)
                    {
                        var name = tupleDeconstruction.Names[i];
                        if (name == "_")
                        {
                            continue;
                        }

                        _inferredLocalTypes[name] = TryGetTupleDeconstructionElementType(tupleDeconstruction, i, out var elementType)
                            ? elementType
                            : typeof(object);
                    }
                }
                break;

            case IfStatement ifStatement:
                CollectLambdaReturnTypes(ifStatement.ThenStatement, ref returnTypes);
                if (ifStatement.ElseStatement != null)
                {
                    CollectLambdaReturnTypes(ifStatement.ElseStatement, ref returnTypes);
                }
                break;

            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    CollectLambdaReturnTypes(forStatement.Initializer, ref returnTypes);
                }
                CollectLambdaReturnTypes(forStatement.Body, ref returnTypes);
                break;

            case WhileStatement whileStatement:
                CollectLambdaReturnTypes(whileStatement.Body, ref returnTypes);
                break;

            case ForeachStatement foreachStatement:
                CollectLambdaReturnTypes(foreachStatement.Body, ref returnTypes);
                break;

            case AwaitForEachStatement awaitForEachStatement:
                CollectLambdaReturnTypes(awaitForEachStatement.Body, ref returnTypes);
                break;

            case TryStatement tryStatement:
                CollectLambdaReturnTypes(tryStatement.TryBlock, ref returnTypes);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    CollectLambdaReturnTypes(catchClause.Block, ref returnTypes);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    CollectLambdaReturnTypes(tryStatement.FinallyBlock, ref returnTypes);
                }
                break;

            case UsingStatement usingStatement when usingStatement.Body != null:
                CollectLambdaReturnTypes(usingStatement.Body, ref returnTypes);
                break;

            case LockStatement lockStatement:
                CollectLambdaReturnTypes(lockStatement.Body, ref returnTypes);
                break;

            case SwitchStatement switchStatement:
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        CollectLambdaReturnTypes(caseStatement, ref returnTypes);
                    }
                }
                break;
        }
    }

    private void EmitLoadArg(int index)
    {
        if (_currentIL == null)
            throw new InvalidOperationException("No IL generator context");

        switch (index)
        {
            case 0: _currentIL.Emit(OpCodes.Ldarg_0); break;
            case 1: _currentIL.Emit(OpCodes.Ldarg_1); break;
            case 2: _currentIL.Emit(OpCodes.Ldarg_2); break;
            case 3: _currentIL.Emit(OpCodes.Ldarg_3); break;
            default:
                if (index <= 255)
                    _currentIL.Emit(OpCodes.Ldarg_S, (byte)index);
                else
                    _currentIL.Emit(OpCodes.Ldarg, index);
                break;
        }
    }

    private void EmitExpressionTreeLambda(LambdaExpression lambda, Type expressionType, Type delegateType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (!TryGetDelegateInvokeMethod(delegateType, out var invokeMethod) || invokeMethod == null)
        {
            throw new InvalidOperationException($"Could not resolve Invoke for expression-tree delegate {delegateType}");
        }

        var parameterTypes = GetDelegateInvokeParameterTypes(delegateType, invokeMethod);
        if (parameterTypes.Length != lambda.Parameters.Count)
        {
            throw new InvalidOperationException($"Lambda parameter count does not match expression-tree delegate {delegateType}");
        }

        var returnType = GetDelegateInvokeReturnType(delegateType, invokeMethod);
        var parameterLocals = new Dictionary<string, LocalBuilder>(StringComparer.Ordinal);
        var parameterClrTypes = new Dictionary<string, Type>(StringComparer.Ordinal);
        var parameterExpressionType = typeof(System.Linq.Expressions.ParameterExpression);

        for (int i = 0; i < lambda.Parameters.Count; i++)
        {
            var parameter = lambda.Parameters[i];
            var parameterLocal = _currentIL.DeclareLocal(parameterExpressionType);
            EmitRuntimeTypeOf(parameterTypes[i]);
            _currentIL.Emit(OpCodes.Ldstr, parameter.Name);
            _currentIL.Emit(OpCodes.Call, ResolveExpressionParameterMethod());
            _currentIL.Emit(OpCodes.Stloc, parameterLocal);
            parameterLocals[parameter.Name] = parameterLocal;
            parameterClrTypes[parameter.Name] = parameterTypes[i];
        }

        if (lambda.ExpressionBody == null)
        {
            throw new NotSupportedException("Expression-tree lambdas with block bodies are not supported by the IL backend yet");
        }

        EmitExpressionTreeNode(lambda.ExpressionBody, parameterLocals, parameterClrTypes, returnType);
        var bodyType = GetExpressionTreeNodeClrType(lambda.ExpressionBody, parameterClrTypes);
        if (returnType != typeof(void)
            && bodyType != returnType
            && bodyType.IsValueType
            && IsParameterTypeCompatible(returnType, bodyType))
        {
            EmitRuntimeTypeOf(returnType);
            _currentIL.Emit(OpCodes.Call, ResolveExpressionConvertMethod());
        }

        _currentIL.Emit(OpCodes.Ldc_I4, lambda.Parameters.Count);
        _currentIL.Emit(OpCodes.Newarr, parameterExpressionType);
        for (int i = 0; i < lambda.Parameters.Count; i++)
        {
            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Ldc_I4, i);
            _currentIL.Emit(OpCodes.Ldloc, parameterLocals[lambda.Parameters[i].Name]);
            _currentIL.Emit(OpCodes.Stelem_Ref);
        }

        _currentIL.Emit(OpCodes.Call, ResolveExpressionLambdaMethod(delegateType));
        if (_expectedExpressionType != null && expressionType != _expectedExpressionType)
        {
            EmitValueCoercion(expressionType, _expectedExpressionType, allowExplicitUserDefinedConversions: false);
        }
    }

    private void EmitExpressionTreeNode(
        Expression expression,
        IReadOnlyDictionary<string, LocalBuilder> parameterLocals,
        IReadOnlyDictionary<string, Type> parameterClrTypes,
        Type expectedType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        switch (expression)
        {
            case IdentifierExpression identifier when parameterLocals.TryGetValue(identifier.Name, out var parameterLocal):
                _currentIL.Emit(OpCodes.Ldloc, parameterLocal);
                return;

            case MemberAccessExpression memberAccess:
                EmitExpressionTreeNode(memberAccess.Object, parameterLocals, parameterClrTypes, typeof(object));
                _currentIL.Emit(OpCodes.Ldstr, memberAccess.MemberName);
                _currentIL.Emit(OpCodes.Call, ResolveExpressionPropertyOrFieldMethod());
                return;

            case ParenthesizedExpression parenthesized:
                EmitExpressionTreeNode(parenthesized.Inner, parameterLocals, parameterClrTypes, expectedType);
                return;

            case UnaryExpression unary when unary.Operator == UnaryOperator.Not:
                EmitExpressionTreeNode(unary.Operand, parameterLocals, parameterClrTypes, typeof(bool));
                _currentIL.Emit(OpCodes.Call, ResolveUnaryExpressionMethod(nameof(System.Linq.Expressions.Expression.Not)));
                return;

            case NewExpression newExpression when IsAnonymousObjectCreation(newExpression):
                EmitAnonymousObjectExpressionTreeNode(newExpression, parameterLocals, parameterClrTypes);
                return;

            default:
                throw new NotSupportedException($"Expression-tree lambda body '{expression.GetType().Name}' is not supported by the IL backend yet");
        }
    }

    private Type GetExpressionTreeNodeClrType(
        Expression expression,
        IReadOnlyDictionary<string, Type> parameterClrTypes)
    {
        return expression switch
        {
            IdentifierExpression identifier when parameterClrTypes.TryGetValue(identifier.Name, out var parameterType) => parameterType,
            ParenthesizedExpression parenthesized => GetExpressionTreeNodeClrType(parenthesized.Inner, parameterClrTypes),
            MemberAccessExpression memberAccess => ResolveExpressionTreeMemberType(memberAccess, parameterClrTypes),
            _ => GetExpressionType(expression)
        };
    }

    private Type ResolveExpressionTreeMemberType(
        MemberAccessExpression memberAccess,
        IReadOnlyDictionary<string, Type> parameterClrTypes)
    {
        var receiverType = GetExpressionTreeNodeClrType(memberAccess.Object, parameterClrTypes);
        if (receiverType is TypeBuilder receiverTypeBuilder)
        {
            if (_fields.TryGetValue(GetFieldKey(receiverTypeBuilder, memberAccess.MemberName), out var fieldBuilder))
            {
                return fieldBuilder.FieldType;
            }

            if (_methods.TryGetValue(GetMethodKey(receiverTypeBuilder, $"get_{memberAccess.MemberName}"), out var getterMethod))
            {
                return getterMethod.ReturnType;
            }
        }

        var runtimeProperty = ResolveRuntimeProperty(
            receiverType,
            memberAccess.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        if (runtimeProperty != null)
        {
            return runtimeProperty.PropertyType;
        }

        var field = ResolveRuntimeField(
            receiverType,
            memberAccess.MemberName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        return field?.FieldType ?? typeof(object);
    }

    private void EmitAnonymousObjectExpressionTreeNode(
        NewExpression newExpression,
        IReadOnlyDictionary<string, LocalBuilder> parameterLocals,
        IReadOnlyDictionary<string, Type> parameterClrTypes)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var anonymousType = GetAnonymousObjectType(
            newExpression,
            expression => GetExpressionTreeNodeClrType(expression, parameterClrTypes));
        var constructor = _constructors[GetConstructorKey(anonymousType)];
        var properties = newExpression.Initializer!.Properties;

        EmitRuntimeConstructorInfo(constructor);
        _currentIL.Emit(OpCodes.Call, ResolveExpressionNewMethod());

        _currentIL.Emit(OpCodes.Ldc_I4, properties.Count);
        _currentIL.Emit(OpCodes.Newarr, typeof(System.Linq.Expressions.MemberBinding));
        for (int i = 0; i < properties.Count; i++)
        {
            var property = properties[i];
            var setter = _methods[GetMethodKey(anonymousType, $"set_{property.Name}")];

            _currentIL.Emit(OpCodes.Dup);
            _currentIL.Emit(OpCodes.Ldc_I4, i);
            EmitRuntimeMethodInfo(setter);
            EmitExpressionTreeNode(
                property.Value,
                parameterLocals,
                parameterClrTypes,
                GetExpressionTreeNodeClrType(property.Value, parameterClrTypes));
            _currentIL.Emit(OpCodes.Call, ResolveExpressionBindMethod());
            _currentIL.Emit(OpCodes.Stelem_Ref);
        }

        _currentIL.Emit(OpCodes.Call, ResolveExpressionMemberInitMethod());
    }

    private void EmitRuntimeTypeOf(Type type)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        _currentIL.Emit(OpCodes.Ldtoken, type);
        _currentIL.Emit(OpCodes.Call, typeof(Type).GetMethod(nameof(Type.GetTypeFromHandle))!);
    }

    private void EmitRuntimeConstructorInfo(ConstructorInfo constructor)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        EmitRuntimeTypeOf(constructor.DeclaringType ?? throw new InvalidOperationException("Constructor has no declaring type"));
        _currentIL.Emit(OpCodes.Ldsfld, typeof(Type).GetField(nameof(Type.EmptyTypes))!);
        _currentIL.Emit(OpCodes.Callvirt, typeof(Type).GetMethod(
            nameof(Type.GetConstructor),
            new[] { typeof(Type[]) })!);
    }

    private void EmitRuntimeMethodInfo(MethodInfo method)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        EmitRuntimeTypeOf(method.DeclaringType ?? throw new InvalidOperationException("Method has no declaring type"));
        _currentIL.Emit(OpCodes.Ldstr, method.Name);
        _currentIL.Emit(OpCodes.Callvirt, typeof(Type).GetMethod(
            nameof(Type.GetMethod),
            new[] { typeof(string) })!);
    }

    private static MethodInfo ResolveExpressionParameterMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.Parameter),
            new[] { typeof(Type), typeof(string) })
        ?? throw new InvalidOperationException("Could not resolve Expression.Parameter(Type, string)");

    private static MethodInfo ResolveExpressionPropertyOrFieldMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.PropertyOrField),
            new[] { typeof(System.Linq.Expressions.Expression), typeof(string) })
        ?? throw new InvalidOperationException("Could not resolve Expression.PropertyOrField(Expression, string)");

    private static MethodInfo ResolveExpressionConvertMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.Convert),
            new[] { typeof(System.Linq.Expressions.Expression), typeof(Type) })
        ?? throw new InvalidOperationException("Could not resolve Expression.Convert(Expression, Type)");

    private static MethodInfo ResolveExpressionNewMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.New),
            new[] { typeof(ConstructorInfo) })
        ?? throw new InvalidOperationException("Could not resolve Expression.New(ConstructorInfo)");

    private static MethodInfo ResolveExpressionBindMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.Bind),
            new[] { typeof(MethodInfo), typeof(System.Linq.Expressions.Expression) })
        ?? throw new InvalidOperationException("Could not resolve Expression.Bind(MethodInfo, Expression)");

    private static MethodInfo ResolveExpressionMemberInitMethod()
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            nameof(System.Linq.Expressions.Expression.MemberInit),
            new[] { typeof(System.Linq.Expressions.NewExpression), typeof(System.Linq.Expressions.MemberBinding[]) })
        ?? throw new InvalidOperationException("Could not resolve Expression.MemberInit(NewExpression, MemberBinding[])");

    private static MethodInfo ResolveUnaryExpressionMethod(string methodName)
        => typeof(System.Linq.Expressions.Expression).GetMethod(
            methodName,
            new[] { typeof(System.Linq.Expressions.Expression) })
        ?? throw new InvalidOperationException($"Could not resolve Expression.{methodName}(Expression)");

    private static MethodInfo ResolveExpressionLambdaMethod(Type delegateType)
    {
        var lambdaMethod = typeof(System.Linq.Expressions.Expression)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(method =>
            {
                if (method.Name != nameof(System.Linq.Expressions.Expression.Lambda) || !method.IsGenericMethodDefinition)
                {
                    return false;
                }

                var parameters = method.GetParameters();
                return parameters.Length == 2
                    && parameters[0].ParameterType == typeof(System.Linq.Expressions.Expression)
                    && parameters[1].ParameterType == typeof(System.Linq.Expressions.ParameterExpression[]);
            });

        return (lambdaMethod ?? throw new InvalidOperationException("Could not resolve Expression.Lambda<TDelegate>(Expression, ParameterExpression[])"))
            .MakeGenericMethod(delegateType);
    }
}
