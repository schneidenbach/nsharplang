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
    private void EmitLambda(LambdaExpression lambda)
    {
        if (_currentIL == null || _programType == null || _moduleBuilder == null)
            throw new InvalidOperationException("No IL generator context");

        // Analyze lambda to determine if it captures variables
        var capturedVariables = AnalyzeCapturedVariables(lambda);

        if (capturedVariables.Count == 0)
        {
            // Simple lambda - no closures needed
            EmitSimpleLambda(lambda);
        }
        else
        {
            // Lambda with closures - need to create a display class
            EmitClosureLambda(lambda, capturedVariables);
        }
    }

    /// <summary>
    /// Analyze which variables are captured by a lambda expression
    /// </summary>
    private HashSet<string> AnalyzeCapturedVariables(LambdaExpression lambda)
    {
        var captured = new HashSet<string>();
        var parameterNames = new HashSet<string>(lambda.Parameters.Select(p => p.Name));

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

            case AssignmentExpression assignment:
                FindCapturedVariablesInExpression(assignment.Target, parameterNames, captured);
                FindCapturedVariablesInExpression(assignment.Value, parameterNames, captured);
                break;

            case NewExpression newExpr:
                foreach (var arg in newExpr.ConstructorArguments)
                    FindCapturedVariablesInExpression(arg.Value, parameterNames, captured);
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
        }
    }

    /// <summary>
    /// Emit a simple lambda (no closures) as a static method with a delegate
    /// </summary>
    private void EmitSimpleLambda(LambdaExpression lambda)
    {
        if (_currentIL == null || _programType == null)
            throw new InvalidOperationException("No IL generator context");

        // Determine parameter types and return type
        var parameterTypes = lambda.Parameters.Select(p =>
            p.Type != null ? ResolveType(p.Type) : typeof(object)).ToArray();

        // Determine return type from expression or block
        Type returnType;
        if (lambda.ExpressionBody != null)
        {
            // For expression lambdas, we'd ideally infer the type, but for now use object
            returnType = typeof(object);
        }
        else
        {
            // For block lambdas, assume void unless we analyze returns
            returnType = typeof(void);
        }

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

        // Set up lambda context
        _currentIL = il;
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();
        _parameterTypes = new Dictionary<string, Type>();

        // Register parameters
        for (int i = 0; i < lambda.Parameters.Count; i++)
        {
            _parameters[lambda.Parameters[i].Name] = i;
            _parameterTypes[lambda.Parameters[i].Name] = parameterTypes[i];
        }

        // Emit body
        if (lambda.ExpressionBody != null)
        {
            EmitExpression(lambda.ExpressionBody);
            il.Emit(OpCodes.Ret);
        }
        else if (lambda.BlockBody != null)
        {
            EmitStatement(lambda.BlockBody);
            // Ensure return if block doesn't end with one
            if (returnType == typeof(void))
            {
                il.Emit(OpCodes.Ret);
            }
        }

        // Restore context
        _currentIL = savedIL;
        _locals = savedLocals;
        _parameters = savedParameters;
        _parameterTypes = savedParameterTypes;

        // Create delegate instance
        // Determine appropriate delegate type based on parameters
        Type delegateType;
        if (returnType == typeof(void))
        {
            delegateType = parameterTypes.Length switch
            {
                0 => typeof(Action),
                1 => typeof(Action<>).MakeGenericType(parameterTypes),
                2 => typeof(Action<,>).MakeGenericType(parameterTypes),
                3 => typeof(Action<,,>).MakeGenericType(parameterTypes),
                4 => typeof(Action<,,,>).MakeGenericType(parameterTypes),
                _ => throw new NotImplementedException("Lambdas with more than 4 parameters not yet supported")
            };
        }
        else
        {
            var allTypes = parameterTypes.Concat(new[] { returnType }).ToArray();
            delegateType = parameterTypes.Length switch
            {
                0 => typeof(Func<>).MakeGenericType(returnType),
                1 => typeof(Func<,>).MakeGenericType(allTypes),
                2 => typeof(Func<,,>).MakeGenericType(allTypes),
                3 => typeof(Func<,,,>).MakeGenericType(allTypes),
                4 => typeof(Func<,,,,>).MakeGenericType(allTypes),
                _ => throw new NotImplementedException("Lambdas with more than 4 parameters not yet supported")
            };
        }

        // Emit delegate creation: ldnull, ldftn, newobj
        _currentIL.Emit(OpCodes.Ldnull);
        _currentIL.Emit(OpCodes.Ldftn, lambdaMethod);
        var delegateCtor = delegateType.GetConstructor(new[] { typeof(object), typeof(IntPtr) });
        _currentIL.Emit(OpCodes.Newobj, delegateCtor!);
    }

    /// <summary>
    /// Emit a lambda with closures using a display class
    /// </summary>
    private void EmitClosureLambda(LambdaExpression lambda, HashSet<string> capturedVariables)
    {
        if (_currentIL == null || _programType == null || _moduleBuilder == null)
            throw new InvalidOperationException("No IL generator context");

        // Create closure class (display class)
        var closureClass = _moduleBuilder.DefineType(
            $"<>c__DisplayClass{_closureCounter++}",
            TypeAttributes.NestedPrivate | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object));

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
            else if (_parameterTypes != null && _parameterTypes.TryGetValue(varName, out var paramType))
            {
                fieldType = paramType;
            }

            var field = closureClass.DefineField(varName, fieldType, FieldAttributes.Public);
            closureFields[varName] = field;
        }

        // Determine parameter types and return type
        var parameterTypes = lambda.Parameters.Select(p =>
            p.Type != null ? ResolveType(p.Type) : typeof(object)).ToArray();

        Type returnType;
        if (lambda.ExpressionBody != null)
        {
            returnType = typeof(object);
        }
        else
        {
            returnType = typeof(void);
        }

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
        var savedCurrentTypeBuilder = _currentTypeBuilder;
        var savedClosureFields = _closureFields;

        // Set up lambda context
        _currentIL = il;
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();
        _parameterTypes = new Dictionary<string, Type>();
        _currentTypeBuilder = closureClass;
        _closureFields = closureFields;

        // Register parameters (offset by 1 for 'this')
        for (int i = 0; i < lambda.Parameters.Count; i++)
        {
            _parameters[lambda.Parameters[i].Name] = i + 1; // +1 for 'this'
            _parameterTypes[lambda.Parameters[i].Name] = parameterTypes[i];
        }

        // Emit body - captured variables will be accessed as fields via 'this'
        if (lambda.ExpressionBody != null)
        {
            EmitExpression(lambda.ExpressionBody);
            il.Emit(OpCodes.Ret);
        }
        else if (lambda.BlockBody != null)
        {
            EmitStatement(lambda.BlockBody);
            if (returnType == typeof(void))
            {
                il.Emit(OpCodes.Ret);
            }
        }

        // Restore context
        _currentIL = savedIL;
        _locals = savedLocals;
        _parameters = savedParameters;
        _parameterTypes = savedParameterTypes;
        _currentTypeBuilder = savedCurrentTypeBuilder;
        _closureFields = savedClosureFields;

        // Create the closure class type
        var closureType = closureClass.CreateType();

        // Instantiate closure and set captured variable values
        _currentIL.Emit(OpCodes.Newobj, closureType!.GetConstructor(Type.EmptyTypes)!);

        // Duplicate the closure instance for each field assignment
        foreach (var varName in capturedVariables)
        {
            _currentIL.Emit(OpCodes.Dup);

            // Load the captured variable value
            if (_locals != null && _locals.TryGetValue(varName, out var local))
            {
                _currentIL.Emit(OpCodes.Ldloc, local);
            }
            else if (_parameters != null && _parameters.TryGetValue(varName, out var paramIndex))
            {
                EmitLoadArg(paramIndex);
            }

            // Store into field
            var field = closureType.GetField(varName)!;
            _currentIL.Emit(OpCodes.Stfld, field);
        }

        // Create delegate from the closure instance
        Type delegateType;
        if (returnType == typeof(void))
        {
            delegateType = parameterTypes.Length switch
            {
                0 => typeof(Action),
                1 => typeof(Action<>).MakeGenericType(parameterTypes),
                2 => typeof(Action<,>).MakeGenericType(parameterTypes),
                3 => typeof(Action<,,>).MakeGenericType(parameterTypes),
                4 => typeof(Action<,,,>).MakeGenericType(parameterTypes),
                _ => throw new NotImplementedException("Lambdas with more than 4 parameters not yet supported")
            };
        }
        else
        {
            var allTypes = parameterTypes.Concat(new[] { returnType }).ToArray();
            delegateType = parameterTypes.Length switch
            {
                0 => typeof(Func<>).MakeGenericType(returnType),
                1 => typeof(Func<,>).MakeGenericType(allTypes),
                2 => typeof(Func<,,>).MakeGenericType(allTypes),
                3 => typeof(Func<,,,>).MakeGenericType(allTypes),
                4 => typeof(Func<,,,,>).MakeGenericType(allTypes),
                _ => throw new NotImplementedException("Lambdas with more than 4 parameters not yet supported")
            };
        }

        // The closure instance is already on the stack
        var lambdaMethodInfo = closureType.GetMethod("<Lambda>")!;
        _currentIL.Emit(OpCodes.Ldftn, lambdaMethodInfo);
        var delegateCtor = delegateType.GetConstructor(new[] { typeof(object), typeof(IntPtr) });
        _currentIL.Emit(OpCodes.Newobj, delegateCtor!);
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
}
