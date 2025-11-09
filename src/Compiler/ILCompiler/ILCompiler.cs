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
    private Dictionary<string, Type>? _parameterTypes;
    private GenericTypeParameterBuilder[]? _currentGenericParameters;

    // Global context
    private TypeBuilder? _programType;
    private Dictionary<string, MethodBuilder> _methods = new();
    private Dictionary<string, ConstructorBuilder> _constructors = new();
    private Dictionary<string, TypeBuilder> _types = new();
    private Dictionary<string, FieldBuilder> _fields = new();
    private TypeBuilder? _currentTypeBuilder;

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

        // First pass: declare all types (classes, structs, etc.)
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is ClassDeclaration classDecl)
            {
                DeclareClass(moduleBuilder, classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                DeclareStruct(moduleBuilder, structDecl);
            }
        }

        // Second pass: declare all top-level functions and class members
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                DeclareFunction(_programType, funcDecl);
            }
            else if (declaration is ClassDeclaration classDecl)
            {
                DeclareClassMembers(classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                DeclareStructMembers(structDecl);
            }
        }

        // Third pass: emit all function bodies
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                EmitFunctionBody(funcDecl);
            }
            else if (declaration is ClassDeclaration classDecl)
            {
                EmitClassBodies(classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                EmitStructBodies(structDecl);
            }
        }

        // Create all types
        foreach (var typeBuilder in _types.Values)
        {
            typeBuilder.CreateType();
        }
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
        // Create method (without return type and parameter types yet if generic)
        var methodBuilder = typeBuilder.DefineMethod(
            function.Name,
            MethodAttributes.Public | MethodAttributes.Static);

        // Define generic parameters if present
        GenericTypeParameterBuilder[]? genericParameters = null;
        if (function.TypeParameters != null && function.TypeParameters.Count > 0)
        {
            var typeParamNames = function.TypeParameters.Select(tp => tp.Name).ToArray();
            genericParameters = methodBuilder.DefineGenericParameters(typeParamNames);

            // Apply constraints if present
            if (function.Constraints != null)
            {
                foreach (var constraint in function.Constraints)
                {
                    var typeParam = genericParameters.FirstOrDefault(gp => gp.Name == constraint.TypeParameter);
                    if (typeParam != null)
                    {
                        ApplyGenericConstraints(typeParam, constraint.Constraints);
                    }
                }
            }
        }

        // Determine return type (may reference generic parameters)
        var returnType = function.ReturnType != null
            ? ResolveType(function.ReturnType, genericParameters)
            : typeof(void);

        // Determine parameter types (may reference generic parameters)
        var parameterTypes = function.Parameters
            .Select(p => ResolveType(p.Type, genericParameters))
            .ToArray();

        // Set return type and parameter types
        methodBuilder.SetReturnType(returnType);
        methodBuilder.SetParameters(parameterTypes);

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

        // Get generic parameters if the method is generic
        _currentGenericParameters = null;
        if (methodBuilder.IsGenericMethodDefinition)
        {
            _currentGenericParameters = methodBuilder.GetGenericArguments()
                .Cast<GenericTypeParameterBuilder>()
                .ToArray();
        }

        // Determine return type
        var returnType = function.ReturnType != null
            ? ResolveType(function.ReturnType, _currentGenericParameters)
            : typeof(void);

        // Get IL generator
        _currentIL = methodBuilder.GetILGenerator();
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();
        _parameterTypes = new Dictionary<string, Type>();

        // Map parameter names to indices and types
        for (int i = 0; i < function.Parameters.Count; i++)
        {
            _parameters[function.Parameters[i].Name] = i;
            _parameterTypes[function.Parameters[i].Name] = ResolveType(function.Parameters[i].Type, _currentGenericParameters);
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
        _parameterTypes = null;
        _currentGenericParameters = null;
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
            varType = ResolveType(varDecl.Type, _currentGenericParameters);
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

            case NewExpression newExpr:
                EmitNewObject(newExpr);
                break;

            case MemberAccessExpression memberAccess:
                EmitMemberAccess(memberAccess);
                break;

            case ThisExpression:
                // 'this' is always at argument 0 for instance methods and constructors
                _currentIL.Emit(OpCodes.Ldarg_0);
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

        // Handle instance method calls (obj.Method())
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            // Emit the object (this will be the first argument to the instance method)
            EmitExpression(memberAccess.Object);

            var objectType = GetExpressionType(memberAccess.Object);

            // Emit arguments
            foreach (var arg in call.Arguments)
            {
                EmitExpression(arg.Value);
            }

            // Check if it's a user-defined type first
            if (objectType is TypeBuilder typeBuilder)
            {
                // Check if it's a user-defined method
                if (_methods.TryGetValue($"{typeBuilder.Name}.{memberAccess.MemberName}", out var methodBuilder))
                {
                    _currentIL.Emit(OpCodes.Callvirt, methodBuilder);
                    return;
                }

                throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on type {typeBuilder.Name}");
            }

            // Handle constrained calls on generic type parameters
            if (objectType.IsGenericParameter)
            {
                // For generic type parameters, we need to find the method on the constraint
                MethodInfo? method = null;

                // Try to find the method on the constraints
                var constraints = objectType.GetGenericParameterConstraints();
                foreach (var constraint in constraints)
                {
                    // Get all methods with the matching name
                    var methods = constraint.GetMethods().Where(m => m.Name == memberAccess.MemberName).ToArray();

                    // For now, just take the first one with matching argument count
                    method = methods.FirstOrDefault(m => m.GetParameters().Length == call.Arguments.Count);

                    if (method != null)
                        break;
                }

                if (method != null)
                {
                    // Use constrained callvirt for generic type parameters
                    _currentIL.Emit(OpCodes.Constrained, objectType);
                    _currentIL.Emit(OpCodes.Callvirt, method);
                    return;
                }

                throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on generic type parameter {objectType.Name}");
            }

            // Find the method using reflection for built-in types
            var argTypes = call.Arguments
                .Select(arg => GetExpressionType(arg.Value))
                .ToArray();

            MethodInfo? methodInfo = objectType.GetMethod(memberAccess.MemberName, argTypes);

            if (methodInfo != null)
            {
                if (methodInfo.IsVirtual)
                {
                    _currentIL.Emit(OpCodes.Callvirt, methodInfo);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Call, methodInfo);
                }
                return;
            }

            throw new InvalidOperationException($"Method {memberAccess.MemberName} not found on type {objectType.Name}");
        }

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

        // Handle member access assignments (obj.Field = value)
        if (assignment.Target is MemberAccessExpression memberAccess)
        {
            // Emit the object
            EmitExpression(memberAccess.Object);

            var objectType = GetExpressionType(memberAccess.Object);

            // Handle compound assignment
            if (assignment.Operator != AssignmentOperator.Assign)
            {
                // For compound assignments, we need to load the current value first
                _currentIL.Emit(OpCodes.Dup); // Duplicate object reference

                // Load current field/property value
                if (objectType is TypeBuilder typeBuilder)
                {
                    if (_fields.TryGetValue($"{typeBuilder.Name}.{memberAccess.MemberName}", out var fieldBuilder))
                    {
                        _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                    }
                    else if (_methods.TryGetValue($"{typeBuilder.Name}.get_{memberAccess.MemberName}", out var getterMethod))
                    {
                        _currentIL.Emit(OpCodes.Callvirt, getterMethod);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {typeBuilder.Name}");
                    }
                }
                else
                {
                    var property = objectType.GetProperty(memberAccess.MemberName);
                    if (property != null && property.GetMethod != null)
                    {
                        _currentIL.Emit(OpCodes.Callvirt, property.GetMethod);
                    }
                    else
                    {
                        var field = objectType.GetField(memberAccess.MemberName);
                        if (field != null)
                        {
                            _currentIL.Emit(OpCodes.Ldfld, field);
                        }
                        else
                        {
                            throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
                        }
                    }
                }

                // Emit right-hand side
                EmitExpression(assignment.Value);

                // Perform operation
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
                    default:
                        throw new NotImplementedException($"Assignment operator {assignment.Operator} not yet implemented");
                }
            }
            else
            {
                // Simple assignment - just emit the value
                EmitExpression(assignment.Value);
            }

            // Store to field/property
            if (objectType is TypeBuilder tb)
            {
                if (_fields.TryGetValue($"{tb.Name}.{memberAccess.MemberName}", out var fb))
                {
                    _currentIL.Emit(OpCodes.Stfld, fb);
                }
                else if (_methods.TryGetValue($"{tb.Name}.set_{memberAccess.MemberName}", out var setterMethod))
                {
                    _currentIL.Emit(OpCodes.Callvirt, setterMethod);
                }
                else
                {
                    throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {tb.Name}");
                }
            }
            else
            {
                var prop = objectType.GetProperty(memberAccess.MemberName);
                if (prop != null && prop.SetMethod != null)
                {
                    _currentIL.Emit(OpCodes.Callvirt, prop.SetMethod);
                }
                else
                {
                    var fld = objectType.GetField(memberAccess.MemberName);
                    if (fld != null)
                    {
                        _currentIL.Emit(OpCodes.Stfld, fld);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
                    }
                }
            }

            // Assignment expressions return the assigned value
            // For member assignments, we need to reload the value
            EmitExpression(memberAccess.Object);
            EmitMemberAccess(memberAccess);

            return;
        }

        // Handle simple identifier assignments
        if (assignment.Target is not IdentifierExpression ident)
        {
            throw new NotImplementedException("Only simple variable and member assignments are supported in IL compiler");
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
    /// Emit IL for a new object expression
    /// </summary>
    private void EmitNewObject(NewExpression newExpr)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (newExpr.Type == null)
        {
            throw new NotImplementedException("Target-typed new not yet supported in IL compiler");
        }

        var type = ResolveType(newExpr.Type, _currentGenericParameters);

        // Emit arguments first
        foreach (var arg in newExpr.ConstructorArguments)
        {
            EmitExpression(arg.Value);
        }

        // Find the constructor
        ConstructorInfo? constructor = null;

        // Check if it's a user-defined type
        if (type is TypeBuilder typeBuilder)
        {
            // Look up constructor in our dictionary
            var ctorKey = $"{typeBuilder.Name}..ctor";
            if (_constructors.TryGetValue(ctorKey, out var ctorBuilder))
            {
                constructor = ctorBuilder;
            }
            else
            {
                throw new InvalidOperationException($"No matching constructor found for type {type.Name}");
            }
        }
        else
        {
            // Built-in type - use reflection
            var parameterTypes = newExpr.ConstructorArguments
                .Select(arg => GetExpressionType(arg.Value))
                .ToArray();

            if (parameterTypes.Length == 0)
            {
                // Default constructor
                constructor = type.GetConstructor(Type.EmptyTypes);
            }
            else
            {
                // Constructor with parameters
                constructor = type.GetConstructor(parameterTypes);
            }

            if (constructor == null)
            {
                throw new InvalidOperationException($"No matching constructor found for type {type.Name}");
            }
        }

        // Call constructor
        _currentIL.Emit(OpCodes.Newobj, constructor);

        // Handle object initializer if present
        if (newExpr.Initializer != null)
        {
            // Duplicate the object reference for each property assignment
            foreach (var propInit in newExpr.Initializer.Properties)
            {
                if (propInit.Name == null)
                {
                    throw new NotImplementedException("Indexer initializers not yet supported in IL compiler");
                }

                // Duplicate object reference
                _currentIL.Emit(OpCodes.Dup);

                // Emit property value
                EmitExpression(propInit.Value);

                // Find and call property setter or set field
                var property = type.GetProperty(propInit.Name);
                if (property != null && property.SetMethod != null)
                {
                    _currentIL.Emit(OpCodes.Callvirt, property.SetMethod);
                }
                else
                {
                    var field = type.GetField(propInit.Name);
                    if (field != null)
                    {
                        _currentIL.Emit(OpCodes.Stfld, field);
                    }
                    else
                    {
                        throw new InvalidOperationException($"Property or field {propInit.Name} not found on type {type.Name}");
                    }
                }
            }
        }
    }

    /// <summary>
    /// Emit IL for member access (field or property)
    /// </summary>
    private void EmitMemberAccess(MemberAccessExpression memberAccess)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (memberAccess.IsNullConditional)
        {
            throw new NotImplementedException("Null-conditional member access not yet supported in IL compiler");
        }

        // Emit the object
        EmitExpression(memberAccess.Object);

        // Get the object type
        var objectType = GetExpressionType(memberAccess.Object);

        // Check if it's a user-defined type
        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue($"{typeBuilder.Name}.{memberAccess.MemberName}", out var fieldBuilder))
            {
                _currentIL.Emit(OpCodes.Ldfld, fieldBuilder);
                return;
            }

            // Check for property getter
            if (_methods.TryGetValue($"{typeBuilder.Name}.get_{memberAccess.MemberName}", out var getterMethod))
            {
                _currentIL.Emit(OpCodes.Callvirt, getterMethod);
                return;
            }

            throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {typeBuilder.Name}");
        }

        // Try to find a property first
        var property = objectType.GetProperty(memberAccess.MemberName);
        if (property != null && property.GetMethod != null)
        {
            _currentIL.Emit(OpCodes.Callvirt, property.GetMethod);
            return;
        }

        // Try to find a field
        var field = objectType.GetField(memberAccess.MemberName);
        if (field != null)
        {
            if (field.IsStatic)
            {
                _currentIL.Emit(OpCodes.Ldsfld, field);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldfld, field);
            }
            return;
        }

        throw new InvalidOperationException($"Member {memberAccess.MemberName} not found on type {objectType.Name}");
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
            NewExpression newExpr => newExpr.Type != null ? ResolveType(newExpr.Type, _currentGenericParameters) : typeof(object),
            MemberAccessExpression memberAccess => GetMemberAccessType(memberAccess),
            CallExpression call => GetCallExpressionType(call),
            ThisExpression => _currentTypeBuilder ?? typeof(object),
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

        if (_parameterTypes != null && _parameterTypes.TryGetValue(ident.Name, out var paramType))
        {
            return paramType;
        }

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
    /// Get the type of a member access expression
    /// </summary>
    private Type GetMemberAccessType(MemberAccessExpression memberAccess)
    {
        var objectType = GetExpressionType(memberAccess.Object);

        // Check user-defined types first
        if (objectType is TypeBuilder typeBuilder)
        {
            if (_fields.TryGetValue($"{typeBuilder.Name}.{memberAccess.MemberName}", out var fieldBuilder))
            {
                return fieldBuilder.FieldType;
            }

            // Check for property via getter
            if (_methods.TryGetValue($"{typeBuilder.Name}.get_{memberAccess.MemberName}", out var getterMethod))
            {
                return getterMethod.ReturnType;
            }

            return typeof(object);
        }

        // Try to find a property
        var property = objectType.GetProperty(memberAccess.MemberName);
        if (property != null)
        {
            return property.PropertyType;
        }

        // Try to find a field
        var field = objectType.GetField(memberAccess.MemberName);
        if (field != null)
        {
            return field.FieldType;
        }

        return typeof(object);
    }

    /// <summary>
    /// Get the type of a call expression
    /// </summary>
    private Type GetCallExpressionType(CallExpression call)
    {
        // Handle instance method calls
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            var objectType = GetExpressionType(memberAccess.Object);

            // Check user-defined methods first
            if (objectType is TypeBuilder typeBuilder)
            {
                if (_methods.TryGetValue($"{typeBuilder.Name}.{memberAccess.MemberName}", out var methodBuilder))
                {
                    return methodBuilder.ReturnType;
                }

                return typeof(object);
            }

            // Use reflection for built-in types
            var parameterTypes = call.Arguments
                .Select(arg => GetExpressionType(arg.Value))
                .ToArray();

            var method = objectType.GetMethod(memberAccess.MemberName, parameterTypes);
            if (method != null)
            {
                return method.ReturnType;
            }

            return typeof(object);
        }

        // Handle static/global function calls
        if (call.Callee is IdentifierExpression ident)
        {
            if (_methods.TryGetValue(ident.Name, out var methodBuilder))
            {
                return methodBuilder.ReturnType;
            }
        }

        return typeof(object);
    }

    /// <summary>
    /// Resolve a type reference to a System.Type
    /// </summary>
    private Type ResolveType(TypeReference typeRef)
    {
        return ResolveType(typeRef, null);
    }

    /// <summary>
    /// Resolve a type reference to a System.Type, with optional generic parameters
    /// </summary>
    private Type ResolveType(TypeReference typeRef, GenericTypeParameterBuilder[]? genericParameters)
    {
        if (typeRef is SimpleTypeReference simpleType)
        {
            // Check for generic type parameters first
            if (genericParameters != null)
            {
                var genericParam = genericParameters.FirstOrDefault(gp => gp.Name == simpleType.Name);
                if (genericParam != null)
                    return genericParam;
            }

            // Check for built-in types
            var builtInType = simpleType.Name switch
            {
                "int" => typeof(int),
                "long" => typeof(long),
                "float" => typeof(float),
                "double" => typeof(double),
                "bool" => typeof(bool),
                "string" => typeof(string),
                "void" => typeof(void),
                "object" => typeof(object),
                _ => null
            };

            if (builtInType != null)
                return builtInType;

            // Check for user-defined types
            if (_types.TryGetValue(simpleType.Name, out var typeBuilder))
            {
                return typeBuilder;
            }

            // Default to object for unknown types
            return typeof(object);
        }

        if (typeRef is GenericTypeReference genericType)
        {
            // Resolve the base type by name
            // The genericType.Name is the base generic type (e.g., "List", "IComparable")
            Type? baseType = null;

            // Try to resolve known generic types from System namespace
            baseType = genericType.Name switch
            {
                "List" => typeof(System.Collections.Generic.List<>),
                "IEnumerable" => typeof(System.Collections.Generic.IEnumerable<>),
                "ICollection" => typeof(System.Collections.Generic.ICollection<>),
                "IList" => typeof(System.Collections.Generic.IList<>),
                "Dictionary" => typeof(System.Collections.Generic.Dictionary<,>),
                "IDictionary" => typeof(System.Collections.Generic.IDictionary<,>),
                "IComparable" => typeof(System.IComparable<>),
                "Task" => typeof(System.Threading.Tasks.Task<>),
                "ValueTask" => typeof(System.Threading.Tasks.ValueTask<>),
                _ => null
            };

            // If not a known system type, try to resolve from user-defined types
            if (baseType == null && _types.TryGetValue(genericType.Name, out var typeBuilder))
            {
                baseType = typeBuilder;
            }

            if (baseType == null)
            {
                // Unknown generic type, default to object
                return typeof(object);
            }

            // Resolve type arguments
            var typeArgs = genericType.TypeArguments
                .Select(ta => ResolveType(ta, genericParameters))
                .ToArray();

            // Make the generic type
            return baseType.MakeGenericType(typeArgs);
        }

        // TODO: Handle array types, nullable types, etc.
        return typeof(object);
    }

    /// <summary>
    /// Apply generic constraints to a generic type parameter
    /// </summary>
    private void ApplyGenericConstraints(GenericTypeParameterBuilder typeParam, List<TypeReference> constraints)
    {
        var interfaceConstraints = new List<Type>();
        Type? baseClassConstraint = null;

        foreach (var constraint in constraints)
        {
            var constraintType = ResolveType(constraint, null);

            if (constraintType.IsClass)
            {
                // Base class constraint (can only have one)
                baseClassConstraint = constraintType;
            }
            else if (constraintType.IsInterface)
            {
                // Interface constraint (can have multiple)
                interfaceConstraints.Add(constraintType);
            }
        }

        // Set base class constraint
        if (baseClassConstraint != null)
        {
            typeParam.SetBaseTypeConstraint(baseClassConstraint);
        }

        // Set interface constraints
        if (interfaceConstraints.Count > 0)
        {
            typeParam.SetInterfaceConstraints(interfaceConstraints.ToArray());
        }

        // TODO: Handle other constraint types (struct, class, new(), unmanaged)
    }

    /// <summary>
    /// Declare a class type (first pass)
    /// </summary>
    private void DeclareClass(ModuleBuilder moduleBuilder, ClassDeclaration classDecl)
    {
        var typeAttributes = TypeAttributes.Public | TypeAttributes.Class;

        if (classDecl.Modifiers.HasFlag(Modifiers.Abstract))
            typeAttributes |= TypeAttributes.Abstract;
        if (classDecl.Modifiers.HasFlag(Modifiers.Sealed))
            typeAttributes |= TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            classDecl.Name,
            typeAttributes);

        _types[classDecl.Name] = typeBuilder;
    }

    /// <summary>
    /// Declare a struct type (first pass)
    /// </summary>
    private void DeclareStruct(ModuleBuilder moduleBuilder, StructDeclaration structDecl)
    {
        var typeAttributes = TypeAttributes.Public | TypeAttributes.Sealed;

        var typeBuilder = moduleBuilder.DefineType(
            structDecl.Name,
            typeAttributes,
            typeof(ValueType));

        _types[structDecl.Name] = typeBuilder;
    }

    /// <summary>
    /// Declare class members (second pass)
    /// </summary>
    private void DeclareClassMembers(ClassDeclaration classDecl)
    {
        if (!_types.TryGetValue(classDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {classDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Check if there's any constructor declared
        bool hasConstructor = classDecl.Members.Any(m => m is ConstructorDeclaration);

        // If no constructor is declared, create a default parameterless constructor
        if (!hasConstructor)
        {
            var defaultCtor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);

            _constructors[$"{typeBuilder.Name}..ctor"] = defaultCtor;
        }

        foreach (var member in classDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    DeclareConstructor(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    DeclareMethod(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    DeclareProperty(typeBuilder, propDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare struct members (second pass)
    /// </summary>
    private void DeclareStructMembers(StructDeclaration structDecl)
    {
        if (!_types.TryGetValue(structDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {structDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        foreach (var member in structDecl.Members)
        {
            switch (member)
            {
                case FieldDeclaration fieldDecl:
                    DeclareField(typeBuilder, fieldDecl);
                    break;
                case ConstructorDeclaration ctorDecl:
                    DeclareConstructor(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    DeclareMethod(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    DeclareProperty(typeBuilder, propDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare a field
    /// </summary>
    private void DeclareField(TypeBuilder typeBuilder, FieldDeclaration fieldDecl)
    {
        if (fieldDecl.Type == null)
        {
            throw new InvalidOperationException($"Field {fieldDecl.Name} must have an explicit type in IL compiler");
        }

        var fieldType = ResolveType(fieldDecl.Type);
        var fieldAttributes = FieldAttributes.Public;

        if (fieldDecl.Modifiers.HasFlag(Modifiers.Static))
            fieldAttributes |= FieldAttributes.Static;
        if (fieldDecl.Modifiers.HasFlag(Modifiers.Private))
        {
            fieldAttributes &= ~FieldAttributes.Public;
            fieldAttributes |= FieldAttributes.Private;
        }

        var fieldBuilder = typeBuilder.DefineField(
            fieldDecl.Name,
            fieldType,
            fieldAttributes);

        // Store field with qualified name (TypeName.FieldName)
        _fields[$"{typeBuilder.Name}.{fieldDecl.Name}"] = fieldBuilder;

        // If there's an initializer, we'll handle it in the constructor
        // For now, just declare the field
    }

    /// <summary>
    /// Declare a property (auto-property or with custom get/set)
    /// </summary>
    private void DeclareProperty(TypeBuilder typeBuilder, PropertyDeclaration propDecl)
    {
        var propertyType = ResolveType(propDecl.Type);

        // Define the property
        var propertyBuilder = typeBuilder.DefineProperty(
            propDecl.Name,
            PropertyAttributes.None,
            propertyType,
            null);

        // For now, we'll implement simple auto-properties with a backing field
        var backingFieldName = $"<{propDecl.Name}>k__BackingField";
        var backingField = typeBuilder.DefineField(
            backingFieldName,
            propertyType,
            FieldAttributes.Private);

        // Define get method
        if (propDecl.GetBody != null || propDecl.ExpressionBody != null)
        {
            var getMethod = typeBuilder.DefineMethod(
                $"get_{propDecl.Name}",
                MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                propertyType,
                Type.EmptyTypes);

            propertyBuilder.SetGetMethod(getMethod);

            // Store the method for later body emission
            _methods[$"{typeBuilder.Name}.get_{propDecl.Name}"] = getMethod;
        }

        // Define set method
        if (propDecl.SetBody != null && !propDecl.PropertyModifier.HasFlag(PropertyModifier.Readonly))
        {
            var setMethod = typeBuilder.DefineMethod(
                $"set_{propDecl.Name}",
                MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                typeof(void),
                new[] { propertyType });

            propertyBuilder.SetSetMethod(setMethod);

            // Store the method for later body emission
            _methods[$"{typeBuilder.Name}.set_{propDecl.Name}"] = setMethod;
        }

        // Store the backing field
        _fields[$"{typeBuilder.Name}.{backingFieldName}"] = backingField;
    }

    /// <summary>
    /// Declare a constructor
    /// </summary>
    private void DeclareConstructor(TypeBuilder typeBuilder, ConstructorDeclaration ctorDecl)
    {
        var parameterTypes = ctorDecl.Parameters
            .Select(p => ResolveType(p.Type))
            .ToArray();

        var ctorBuilder = typeBuilder.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            parameterTypes);

        // Define parameter names
        for (int i = 0; i < ctorDecl.Parameters.Count; i++)
        {
            ctorBuilder.DefineParameter(i + 1, ParameterAttributes.None, ctorDecl.Parameters[i].Name);
        }

        // Store constructor for later body emission
        _constructors[$"{typeBuilder.Name}..ctor"] = ctorBuilder;
    }

    /// <summary>
    /// Declare a method (instance or static)
    /// </summary>
    private void DeclareMethod(TypeBuilder typeBuilder, FunctionDeclaration funcDecl)
    {
        var returnType = funcDecl.ReturnType != null
            ? ResolveType(funcDecl.ReturnType)
            : typeof(void);

        var parameterTypes = funcDecl.Parameters
            .Select(p => ResolveType(p.Type))
            .ToArray();

        var methodAttributes = MethodAttributes.Public;

        if (funcDecl.Modifiers.HasFlag(Modifiers.Static))
            methodAttributes |= MethodAttributes.Static;
        else
            methodAttributes |= MethodAttributes.HideBySig;

        if (funcDecl.Modifiers.HasFlag(Modifiers.Virtual))
            methodAttributes |= MethodAttributes.Virtual;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Abstract))
            methodAttributes |= MethodAttributes.Abstract;
        if (funcDecl.Modifiers.HasFlag(Modifiers.Override))
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.ReuseSlot;

        var methodBuilder = typeBuilder.DefineMethod(
            funcDecl.Name,
            methodAttributes,
            returnType,
            parameterTypes);

        // Define parameter names
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            methodBuilder.DefineParameter(i + 1, ParameterAttributes.None, funcDecl.Parameters[i].Name);
        }

        // Store method for later body emission
        _methods[$"{typeBuilder.Name}.{funcDecl.Name}"] = methodBuilder;
    }

    /// <summary>
    /// Emit class method bodies (third pass)
    /// </summary>
    private void EmitClassBodies(ClassDeclaration classDecl)
    {
        if (!_types.TryGetValue(classDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {classDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Check if there's any constructor declared
        bool hasConstructor = classDecl.Members.Any(m => m is ConstructorDeclaration);

        // If no constructor was declared, emit the default constructor body
        if (!hasConstructor)
        {
            EmitDefaultConstructorBody(typeBuilder);
        }

        foreach (var member in classDecl.Members)
        {
            switch (member)
            {
                case ConstructorDeclaration ctorDecl:
                    EmitConstructorBody(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    EmitMethodBody(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    EmitPropertyBody(typeBuilder, propDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit struct method bodies (third pass)
    /// </summary>
    private void EmitStructBodies(StructDeclaration structDecl)
    {
        if (!_types.TryGetValue(structDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {structDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        foreach (var member in structDecl.Members)
        {
            switch (member)
            {
                case ConstructorDeclaration ctorDecl:
                    EmitConstructorBody(typeBuilder, ctorDecl);
                    break;
                case FunctionDeclaration funcDecl:
                    EmitMethodBody(typeBuilder, funcDecl);
                    break;
                case PropertyDeclaration propDecl:
                    EmitPropertyBody(typeBuilder, propDecl);
                    break;
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit default constructor body (when no explicit constructor is defined)
    /// </summary>
    private void EmitDefaultConstructorBody(TypeBuilder typeBuilder)
    {
        if (!_constructors.TryGetValue($"{typeBuilder.Name}..ctor", out var constructorBuilder))
        {
            throw new InvalidOperationException($"Default constructor for {typeBuilder.Name} not declared");
        }

        _currentIL = constructorBuilder.GetILGenerator();

        // Call base constructor (object..ctor)
        _currentIL.Emit(OpCodes.Ldarg_0); // Load 'this'
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
        if (objectCtor != null)
        {
            _currentIL.Emit(OpCodes.Call, objectCtor);
        }

        // Return
        _currentIL.Emit(OpCodes.Ret);

        _currentIL = null;
    }

    /// <summary>
    /// Emit constructor body
    /// </summary>
    private void EmitConstructorBody(TypeBuilder typeBuilder, ConstructorDeclaration ctorDecl)
    {
        if (!_constructors.TryGetValue($"{typeBuilder.Name}..ctor", out var constructorBuilder))
        {
            throw new InvalidOperationException($"Constructor for {typeBuilder.Name} not declared");
        }

        _currentIL = constructorBuilder.GetILGenerator();
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();

        // Map parameter names to indices (parameters start at index 1 for instance methods, 0 is 'this')
        for (int i = 0; i < ctorDecl.Parameters.Count; i++)
        {
            _parameters[ctorDecl.Parameters[i].Name] = i + 1;
        }

        // Call base constructor
        _currentIL.Emit(OpCodes.Ldarg_0); // Load 'this'
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes);
        if (objectCtor != null)
        {
            _currentIL.Emit(OpCodes.Call, objectCtor);
        }

        // Emit constructor body
        EmitStatement(ctorDecl.Body);

        // Ensure constructor ends with a return
        _currentIL.Emit(OpCodes.Ret);

        // Clear context
        _currentIL = null;
        _locals = null;
        _parameters = null;
    }

    /// <summary>
    /// Emit method body (instance or static)
    /// </summary>
    private void EmitMethodBody(TypeBuilder typeBuilder, FunctionDeclaration funcDecl)
    {
        if (!_methods.TryGetValue($"{typeBuilder.Name}.{funcDecl.Name}", out var methodBuilder))
        {
            throw new InvalidOperationException($"Method {typeBuilder.Name}.{funcDecl.Name} not declared");
        }

        var returnType = funcDecl.ReturnType != null
            ? ResolveType(funcDecl.ReturnType)
            : typeof(void);

        _currentIL = methodBuilder.GetILGenerator();
        _locals = new Dictionary<string, LocalBuilder>();
        _parameters = new Dictionary<string, int>();

        // Map parameter names to indices
        // For instance methods, parameters start at index 1 (0 is 'this')
        // For static methods, parameters start at index 0
        int startIndex = funcDecl.Modifiers.HasFlag(Modifiers.Static) ? 0 : 1;
        for (int i = 0; i < funcDecl.Parameters.Count; i++)
        {
            _parameters[funcDecl.Parameters[i].Name] = startIndex + i;
        }

        // Emit method body
        if (funcDecl.Body != null)
        {
            EmitStatement(funcDecl.Body);
        }
        else if (funcDecl.ExpressionBody != null)
        {
            EmitExpression(funcDecl.ExpressionBody);
            _currentIL.Emit(OpCodes.Ret);
        }

        // Ensure method ends with a return
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
    /// Emit property getter/setter bodies
    /// </summary>
    private void EmitPropertyBody(TypeBuilder typeBuilder, PropertyDeclaration propDecl)
    {
        var propertyType = ResolveType(propDecl.Type);
        var backingFieldName = $"<{propDecl.Name}>k__BackingField";

        // Emit getter
        if (propDecl.GetBody != null || propDecl.ExpressionBody != null)
        {
            if (!_methods.TryGetValue($"{typeBuilder.Name}.get_{propDecl.Name}", out var getMethod))
            {
                throw new InvalidOperationException($"Getter for {typeBuilder.Name}.{propDecl.Name} not declared");
            }

            _currentIL = getMethod.GetILGenerator();
            _locals = new Dictionary<string, LocalBuilder>();
            _parameters = new Dictionary<string, int>();

            if (propDecl.GetBody != null)
            {
                EmitStatement(propDecl.GetBody);
            }
            else if (propDecl.ExpressionBody != null)
            {
                EmitExpression(propDecl.ExpressionBody);
                _currentIL.Emit(OpCodes.Ret);
            }

            // Ensure getter ends with a return
            _currentIL.Emit(OpCodes.Ret);

            _currentIL = null;
            _locals = null;
            _parameters = null;
        }

        // Emit setter
        if (propDecl.SetBody != null)
        {
            if (!_methods.TryGetValue($"{typeBuilder.Name}.set_{propDecl.Name}", out var setMethod))
            {
                throw new InvalidOperationException($"Setter for {typeBuilder.Name}.{propDecl.Name} not declared");
            }

            _currentIL = setMethod.GetILGenerator();
            _locals = new Dictionary<string, LocalBuilder>();
            _parameters = new Dictionary<string, int>();
            _parameters["value"] = 1; // 'value' parameter is always at index 1 (0 is 'this')

            EmitStatement(propDecl.SetBody);

            // Ensure setter ends with a return
            _currentIL.Emit(OpCodes.Ret);

            _currentIL = null;
            _locals = null;
            _parameters = null;
        }
    }
}
