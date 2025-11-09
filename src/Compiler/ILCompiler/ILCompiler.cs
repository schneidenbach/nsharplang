using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler.ILCompiler;

/// <summary>
/// Compiles N# AST directly to IL using System.Reflection.Emit
/// </summary>
public class ILCompiler
{
    private readonly CompilationUnit _compilationUnit;
    private readonly string _assemblyName;
    private readonly string _outputPath;

    // Context for current method being compiled
    private ILGenerator? _currentIL;
    private Dictionary<string, LocalBuilder>? _locals;
    private Dictionary<string, int>? _parameters;

    // Global context
    private TypeBuilder? _programType;
    private Dictionary<string, MethodBuilder> _methods = new();

    public ILCompiler(CompilationUnit compilationUnit, string assemblyName, string outputPath)
    {
        _compilationUnit = compilationUnit;
        _assemblyName = assemblyName;
        _outputPath = outputPath;
    }

    /// <summary>
    /// Compile the AST to an assembly file
    /// </summary>
    public void Compile()
    {
        // Create assembly builder using PersistedAssemblyBuilder for .NET 9+
        var assemblyName = new AssemblyName(_assemblyName);
        var assemblyBuilder = new PersistedAssemblyBuilder(
            assemblyName,
            typeof(object).Assembly);

        // Create module builder
        var moduleBuilder = assemblyBuilder.DefineDynamicModule(_assemblyName);

        // Create Program class (entry point container)
        _programType = moduleBuilder.DefineType(
            "Program",
            TypeAttributes.Public | TypeAttributes.Class);

        // First pass: declare all functions
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                DeclareFunction(_programType, funcDecl);
            }
        }

        // Second pass: emit all function bodies
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                EmitFunctionBody(funcDecl);
            }
        }

        // Create the type
        _programType.CreateType();

        // Save the assembly to disk using PersistedAssemblyBuilder (.NET 9+)
        using var stream = new FileStream(_outputPath, FileMode.Create, FileAccess.Write);
        assemblyBuilder.Save(stream);

        Console.WriteLine($"IL Compiler: Assembly '{_assemblyName}' compiled and saved to '{_outputPath}'");
    }

    /// <summary>
    /// Declare a function (method signature only, no body)
    /// </summary>
    private void DeclareFunction(TypeBuilder typeBuilder, FunctionDeclaration function)
    {
        // Determine return type
        var returnType = function.ReturnType != null
            ? ResolveType(function.ReturnType)
            : typeof(void);

        // Determine parameter types
        var parameterTypes = function.Parameters
            .Select(p => ResolveType(p.Type))
            .ToArray();

        // Create method
        var methodBuilder = typeBuilder.DefineMethod(
            function.Name,
            MethodAttributes.Public | MethodAttributes.Static,
            returnType,
            parameterTypes);

        // Define parameter names
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            methodBuilder.DefineParameter(i + 1, ParameterAttributes.None, function.Parameters[i].Name);
        }

        // Store method builder for later reference
        _methods[function.Name] = methodBuilder;
    }

    /// <summary>
    /// Emit the body of a function
    /// </summary>
    private void EmitFunctionBody(FunctionDeclaration function)
    {
        if (!_methods.TryGetValue(function.Name, out var methodBuilder))
        {
            throw new InvalidOperationException($"Method {function.Name} not declared");
        }

        // Determine return type
        var returnType = function.ReturnType != null
            ? ResolveType(function.ReturnType)
            : typeof(void);

        // Get IL generator
        _currentIL = methodBuilder.GetILGenerator();
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();

        // Map parameter names to indices
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            _parameters[function.Parameters[i].Name] = i;
        }

        // Emit function body
        if (function.Body != null)
        {
            EmitStatement(function.Body);
        }

        // Ensure function ends with a return
        if (returnType == typeof(void))
        {
            _currentIL.Emit(OpCodes.Ret);
        }

        // Clear context
        _currentIL = null;
        _locals = null;
        _parameters = null;
    }

    /// <summary>
    /// Emit IL for a statement
    /// </summary>
    private void EmitStatement(Statement statement)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (statement)
        {
            case BlockStatement block:
                foreach (var stmt in block.Statements)
                {
                    EmitStatement(stmt);
                }
                break;

            case VariableDeclarationStatement varDecl:
                EmitVariableDeclaration(varDecl);
                break;

            case ReturnStatement ret:
                EmitReturn(ret);
                break;

            case ExpressionStatement exprStmt:
                EmitExpression(exprStmt.Expression);
                // Pop the result if it's not used
                if (GetExpressionType(exprStmt.Expression) != typeof(void))
                {
                    _currentIL.Emit(OpCodes.Pop);
                }
                break;

            case IfStatement ifStmt:
                EmitIf(ifStmt);
                break;

            case WhileStatement whileStmt:
                EmitWhile(whileStmt);
                break;

            case PrintStatement printStmt:
                EmitPrint(printStmt);
                break;

            default:
                throw new NotImplementedException($"Statement type {statement.GetType().Name} not yet implemented in IL compiler");
        }
    }

    /// <summary>
    /// Emit IL for a print statement
    /// </summary>
    private void EmitPrint(PrintStatement printStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Emit the value to print
        EmitExpression(printStmt.Value);

        // Box value types if necessary
        var valueType = GetExpressionType(printStmt.Value);
        if (valueType.IsValueType)
        {
            _currentIL.Emit(OpCodes.Box, valueType);
        }

        // Call Console.WriteLine(object)
        var writeLineMethod = typeof(Console).GetMethod("WriteLine", new[] { typeof(object) });
        if (writeLineMethod != null)
        {
            _currentIL.Emit(OpCodes.Call, writeLineMethod);
        }
    }

    /// <summary>
    /// Emit IL for a variable declaration
    /// </summary>
    private void EmitVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Determine type from initializer or explicit type
        Type varType;
        if (varDecl.Type != null)
        {
            varType = ResolveType(varDecl.Type);
        }
        else if (varDecl.Initializer != null)
        {
            varType = GetExpressionType(varDecl.Initializer);
        }
        else
        {
            throw new InvalidOperationException("Variable must have either a type or an initializer");
        }

        // Declare local
        var local = _currentIL.DeclareLocal(varType);
        _locals[varDecl.Name] = local;

        // Emit initializer if present
        if (varDecl.Initializer != null)
        {
            EmitExpression(varDecl.Initializer);
            _currentIL.Emit(OpCodes.Stloc, local);
        }
    }

    /// <summary>
    /// Emit IL for a return statement
    /// </summary>
    private void EmitReturn(ReturnStatement ret)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (ret.Value != null)
        {
            EmitExpression(ret.Value);
        }
        _currentIL.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit IL for an if statement
    /// </summary>
    private void EmitIf(IfStatement ifStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var elseLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        // Emit condition
        EmitExpression(ifStmt.Condition);
        _currentIL.Emit(OpCodes.Brfalse, elseLabel);

        // Emit then branch
        EmitStatement(ifStmt.ThenStatement);
        if (ifStmt.ElseStatement != null)
        {
            _currentIL.Emit(OpCodes.Br, endLabel);
        }

        // Emit else branch
        _currentIL.MarkLabel(elseLabel);
        if (ifStmt.ElseStatement != null)
        {
            EmitStatement(ifStmt.ElseStatement);
            _currentIL.MarkLabel(endLabel);
        }
    }

    /// <summary>
    /// Emit IL for a while statement
    /// </summary>
    private void EmitWhile(WhileStatement whileStmt)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var conditionLabel = _currentIL.DefineLabel();
        var endLabel = _currentIL.DefineLabel();

        // Mark condition label
        _currentIL.MarkLabel(conditionLabel);

        // Emit condition
        EmitExpression(whileStmt.Condition);
        _currentIL.Emit(OpCodes.Brfalse, endLabel);

        // Emit body
        EmitStatement(whileStmt.Body);

        // Jump back to condition
        _currentIL.Emit(OpCodes.Br, conditionLabel);

        // Mark end label
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL for an expression
    /// </summary>
    private void EmitExpression(Expression expression)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (expression)
        {
            case IntLiteralExpression intLit:
                EmitIntLiteral(intLit);
                break;

            case StringLiteralExpression strLit:
                EmitStringLiteral(strLit);
                break;

            case BoolLiteralExpression boolLit:
                _currentIL.Emit(boolLit.Value ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0);
                break;

            case IdentifierExpression ident:
                EmitIdentifier(ident);
                break;

            case BinaryExpression binary:
                EmitBinaryExpression(binary);
                break;

            case CallExpression call:
                EmitCall(call);
                break;

            case AssignmentExpression assignment:
                EmitAssignment(assignment);
                break;

            default:
                throw new NotImplementedException($"Expression type {expression.GetType().Name} not yet implemented in IL compiler");
        }
    }

    /// <summary>
    /// Emit IL for an integer literal
    /// </summary>
    private void EmitIntLiteral(IntLiteralExpression intLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var value = int.Parse(intLit.Value);

        // Use optimized opcodes for small values
        switch (value)
        {
            case -1: _currentIL.Emit(OpCodes.Ldc_I4_M1); break;
            case 0: _currentIL.Emit(OpCodes.Ldc_I4_0); break;
            case 1: _currentIL.Emit(OpCodes.Ldc_I4_1); break;
            case 2: _currentIL.Emit(OpCodes.Ldc_I4_2); break;
            case 3: _currentIL.Emit(OpCodes.Ldc_I4_3); break;
            case 4: _currentIL.Emit(OpCodes.Ldc_I4_4); break;
            case 5: _currentIL.Emit(OpCodes.Ldc_I4_5); break;
            case 6: _currentIL.Emit(OpCodes.Ldc_I4_6); break;
            case 7: _currentIL.Emit(OpCodes.Ldc_I4_7); break;
            case 8: _currentIL.Emit(OpCodes.Ldc_I4_8); break;
            default:
                if (value >= sbyte.MinValue && value <= sbyte.MaxValue)
                {
                    _currentIL.Emit(OpCodes.Ldc_I4_S, (sbyte)value);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ldc_I4, value);
                }
                break;
        }
    }

    /// <summary>
    /// Emit IL for a string literal
    /// </summary>
    private void EmitStringLiteral(StringLiteralExpression strLit)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Remove quotes from string value
        var value = strLit.Value.Trim('"');
        _currentIL.Emit(OpCodes.Ldstr, value);
    }

    /// <summary>
    /// Emit IL for an identifier (variable or parameter)
    /// </summary>
    private void EmitIdentifier(IdentifierExpression ident)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        // Check if it's a local variable
        if (_locals.TryGetValue(ident.Name, out var local))
        {
            _currentIL.Emit(OpCodes.Ldloc, local);
        }
        // Check if it's a parameter
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            switch (paramIndex)
            {
                case 0: _currentIL.Emit(OpCodes.Ldarg_0); break;
                case 1: _currentIL.Emit(OpCodes.Ldarg_1); break;
                case 2: _currentIL.Emit(OpCodes.Ldarg_2); break;
                case 3: _currentIL.Emit(OpCodes.Ldarg_3); break;
                default:
                    if (paramIndex <= 255)
                    {
                        _currentIL.Emit(OpCodes.Ldarg_S, (byte)paramIndex);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldarg, paramIndex);
                    }
                    break;
            }
        }
        else
        {
            throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
        }
    }

    /// <summary>
    /// Emit IL for a binary expression
    /// </summary>
    private void EmitBinaryExpression(BinaryExpression binary)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Emit left and right operands
        EmitExpression(binary.Left);
        EmitExpression(binary.Right);

        // Emit operator
        switch (binary.Operator)
        {
            case BinaryOperator.Add:
                _currentIL.Emit(OpCodes.Add);
                break;
            case BinaryOperator.Subtract:
                _currentIL.Emit(OpCodes.Sub);
                break;
            case BinaryOperator.Multiply:
                _currentIL.Emit(OpCodes.Mul);
                break;
            case BinaryOperator.Divide:
                _currentIL.Emit(OpCodes.Div);
                break;
            case BinaryOperator.Modulo:
                _currentIL.Emit(OpCodes.Rem);
                break;
            case BinaryOperator.Equal:
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.NotEqual:
                _currentIL.Emit(OpCodes.Ceq);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.Less:
                _currentIL.Emit(OpCodes.Clt);
                break;
            case BinaryOperator.Greater:
                _currentIL.Emit(OpCodes.Cgt);
                break;
            case BinaryOperator.LessOrEqual:
                _currentIL.Emit(OpCodes.Cgt);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.GreaterOrEqual:
                _currentIL.Emit(OpCodes.Clt);
                _currentIL.Emit(OpCodes.Ldc_I4_0);
                _currentIL.Emit(OpCodes.Ceq);
                break;
            case BinaryOperator.And:
                _currentIL.Emit(OpCodes.And);
                break;
            case BinaryOperator.Or:
                _currentIL.Emit(OpCodes.Or);
                break;
            default:
                throw new NotImplementedException($"Binary operator {binary.Operator} not yet implemented in IL compiler");
        }
    }

    /// <summary>
    /// Emit IL for a function call
    /// </summary>
    private void EmitCall(CallExpression call)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Handle special built-in functions
        if (call.Callee is IdentifierExpression ident)
        {
            if (ident.Name == "print")
            {
                // Emit arguments
                foreach (var arg in call.Arguments)
                {
                    EmitExpression(arg.Value);
                }

                // Call Console.WriteLine
                var writeLineMethod = typeof(Console).GetMethod("WriteLine", new[] { typeof(object) });
                if (writeLineMethod != null)
                {
                    _currentIL.Emit(OpCodes.Call, writeLineMethod);
                }
                return;
            }

            // Check if it's a user-defined function
            if (_methods.TryGetValue(ident.Name, out var methodBuilder))
            {
                // Emit arguments
                foreach (var arg in call.Arguments)
                {
                    EmitExpression(arg.Value);
                }

                // Call the method
                _currentIL.Emit(OpCodes.Call, methodBuilder);
                return;
            }
        }

        throw new NotImplementedException($"Function call {call.Callee} not yet fully implemented in IL compiler");
    }

    /// <summary>
    /// Emit IL for an assignment expression
    /// </summary>
    private void EmitAssignment(AssignmentExpression assignment)
    {
        if (_currentIL == null || _locals == null || _parameters == null)
            throw new InvalidOperationException("No IL generator context");

        // For now, only support simple identifier assignments
        if (assignment.Target is not IdentifierExpression ident)
        {
            throw new NotImplementedException("Only simple variable assignments are supported in IL compiler");
        }

        // Handle compound assignment operators
        if (assignment.Operator != AssignmentOperator.Assign)
        {
            // For compound assignments like +=, -=, etc., we need to:
            // 1. Load the current value
            // 2. Load the right-hand side
            // 3. Perform the operation
            // 4. Store the result

            // Load current value
            EmitIdentifier(ident);

            // Load right-hand side
            EmitExpression(assignment.Value);

            // Perform the operation based on the assignment operator
            switch (assignment.Operator)
            {
                case AssignmentOperator.AddAssign:
                    _currentIL.Emit(OpCodes.Add);
                    break;
                case AssignmentOperator.SubtractAssign:
                    _currentIL.Emit(OpCodes.Sub);
                    break;
                case AssignmentOperator.MultiplyAssign:
                    _currentIL.Emit(OpCodes.Mul);
                    break;
                case AssignmentOperator.DivideAssign:
                    _currentIL.Emit(OpCodes.Div);
                    break;
                case AssignmentOperator.NullCoalesceAssign:
                    throw new NotImplementedException("Null coalesce assign not yet implemented in IL compiler");
                default:
                    throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented in IL compiler");
            }
        }
        else
        {
            // Simple assignment: just emit the value
            EmitExpression(assignment.Value);
        }

        // Store the value
        if (_locals.TryGetValue(ident.Name, out var local))
        {
            _currentIL.Emit(OpCodes.Stloc, local);
        }
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            // Store to parameter
            if (paramIndex <= 255)
            {
                _currentIL.Emit(OpCodes.Starg_S, (byte)paramIndex);
            }
            else
            {
                _currentIL.Emit(OpCodes.Starg, paramIndex);
            }
        }
        else
        {
            throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
        }

        // Assignment expressions also return the assigned value, so we need to load it back
        // This allows things like: x = y = 5
        if (_locals.TryGetValue(ident.Name, out local))
        {
            _currentIL.Emit(OpCodes.Ldloc, local);
        }
        else if (_parameters.TryGetValue(ident.Name, out var paramIndex))
        {
            switch (paramIndex)
            {
                case 0: _currentIL.Emit(OpCodes.Ldarg_0); break;
                case 1: _currentIL.Emit(OpCodes.Ldarg_1); break;
                case 2: _currentIL.Emit(OpCodes.Ldarg_2); break;
                case 3: _currentIL.Emit(OpCodes.Ldarg_3); break;
                default:
                    if (paramIndex <= 255)
                    {
                        _currentIL.Emit(OpCodes.Ldarg_S, (byte)paramIndex);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldarg, paramIndex);
                    }
                    break;
            }
        }
    }

    /// <summary>
    /// Get the .NET type of an expression (simplified type inference)
    /// </summary>
    private Type GetExpressionType(Expression expression)
    {
        return expression switch
        {
            IntLiteralExpression => typeof(int),
            FloatLiteralExpression => typeof(double),
            StringLiteralExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            IdentifierExpression ident => GetIdentifierType(ident),
            BinaryExpression binary => GetBinaryExpressionType(binary),
            AssignmentExpression assignment => GetExpressionType(assignment.Value),
            CallExpression => typeof(object), // Simplified
            _ => typeof(object)
        };
    }

    /// <summary>
    /// Get the type of an identifier
    /// </summary>
    private Type GetIdentifierType(IdentifierExpression ident)
    {
        if (_locals != null && _locals.TryGetValue(ident.Name, out var local))
        {
            return local.LocalType;
        }

        // TODO: Look up parameter types
        return typeof(object);
    }

    /// <summary>
    /// Get the type of a binary expression
    /// </summary>
    private Type GetBinaryExpressionType(BinaryExpression binary)
    {
        return binary.Operator switch
        {
            BinaryOperator.Equal or BinaryOperator.NotEqual or
            BinaryOperator.Less or BinaryOperator.LessOrEqual or
            BinaryOperator.Greater or BinaryOperator.GreaterOrEqual => typeof(bool),
            _ => GetExpressionType(binary.Left)
        };
    }

    /// <summary>
    /// Resolve a type reference to a System.Type
    /// </summary>
    private Type ResolveType(TypeReference typeRef)
    {
        if (typeRef is SimpleTypeReference simpleType)
        {
            return simpleType.Name switch
            {
                "int" => typeof(int),
                "long" => typeof(long),
                "float" => typeof(float),
                "double" => typeof(double),
                "bool" => typeof(bool),
                "string" => typeof(string),
                "void" => typeof(void),
                "object" => typeof(object),
                _ => typeof(object) // Default to object for unknown types
            };
        }

        // TODO: Handle generic types, array types, etc.
        return typeof(object);
    }
}
