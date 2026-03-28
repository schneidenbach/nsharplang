using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// Compiles N# AST directly to IL using System.Reflection.Emit
/// </summary>
public partial class ILCompiler
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
    private ModuleBuilder? _moduleBuilder;
    private Dictionary<string, MethodBuilder> _methods = new();
    private Dictionary<string, ConstructorBuilder> _constructors = new();
    private Dictionary<string, TypeBuilder> _types = new();
    private Dictionary<string, FieldBuilder> _fields = new();
    private TypeBuilder? _currentTypeBuilder;

    // Lambda and closure support
    private int _lambdaCounter = 0;
    private int _closureCounter = 0;
    private Dictionary<string, FieldBuilder>? _closureFields;

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
        _moduleBuilder = assemblyBuilder.DefineDynamicModule(_assemblyName);

        // Create Program class (entry point container)
        _programType = _moduleBuilder.DefineType(
            "Program",
            TypeAttributes.Public | TypeAttributes.Class);

        // First pass: declare all types (classes, structs, interfaces, etc.)
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is ClassDeclaration classDecl)
            {
                DeclareClass(_moduleBuilder, classDecl);
            }
            else if (declaration is StructDeclaration structDecl)
            {
                DeclareStruct(_moduleBuilder, structDecl);
            }
            else if (declaration is RecordDeclaration recordDecl)
            {
                DeclareRecord(_moduleBuilder, recordDecl);
            }
            else if (declaration is InterfaceDeclaration interfaceDecl)
            {
                DeclareInterface(_moduleBuilder, interfaceDecl);
            }
        }

        // Second pass: declare all top-level functions and class/interface members
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
            else if (declaration is RecordDeclaration recordDecl)
            {
                DeclareRecordMembers(recordDecl);
            }
            else if (declaration is InterfaceDeclaration interfaceDecl)
            {
                DeclareInterfaceMembers(interfaceDecl);
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
            else if (declaration is RecordDeclaration recordDecl)
            {
                EmitRecordBodies(recordDecl);
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

        Console.Error.WriteLine($"IL Compiler: Assembly '{_assemblyName}' compiled and saved to '{_outputPath}'");
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

            case ForeachStatement foreachStmt:
                EmitForeach(foreachStmt);
                break;

            case TryStatement tryStmt:
                EmitTry(tryStmt);
                break;

            case UsingStatement usingStmt:
                EmitUsing(usingStmt);
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
    /// Emit IL for a foreach statement
    /// </summary>
    private void EmitForeach(ForeachStatement foreachStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Get the collection type
        var collectionType = GetExpressionType(foreachStmt.Collection);

        // Determine the element type from the collection
        Type elementType;
        Type? enumerableInterface = null;

        if (collectionType.IsArray)
        {
            // Handle arrays
            elementType = collectionType.GetElementType()!;
        }
        else
        {
            // Try to find IEnumerable<T>
            enumerableInterface = collectionType.GetInterfaces()
                .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>));

            if (enumerableInterface == null && collectionType.IsGenericType &&
                collectionType.GetGenericTypeDefinition() == typeof(System.Collections.Generic.IEnumerable<>))
            {
                enumerableInterface = collectionType;
            }

            if (enumerableInterface != null)
            {
                elementType = enumerableInterface.GetGenericArguments()[0];
            }
            else
            {
                // Fall back to non-generic IEnumerable (element type is object)
                elementType = typeof(object);
            }
        }

        // Emit the collection expression
        EmitExpression(foreachStmt.Collection);

        // Get the enumerator
        MethodInfo? getEnumeratorMethod;
        Type enumeratorType;

        if (collectionType.IsArray)
        {
            // For arrays, we need to use a different approach
            // Arrays don't have GetEnumerator in a straightforward way for IL
            // We'll implement this as a for loop over array indices instead
            EmitForeachForArray(foreachStmt, collectionType, elementType);
            return;
        }
        else if (enumerableInterface != null)
        {
            // Get IEnumerable<T>.GetEnumerator()
            getEnumeratorMethod = enumerableInterface.GetMethod("GetEnumerator");
            enumeratorType = typeof(System.Collections.Generic.IEnumerator<>).MakeGenericType(elementType);
        }
        else
        {
            // Fall back to non-generic IEnumerable
            getEnumeratorMethod = typeof(System.Collections.IEnumerable).GetMethod("GetEnumerator");
            enumeratorType = typeof(System.Collections.IEnumerator);
        }

        if (getEnumeratorMethod == null)
        {
            throw new InvalidOperationException($"Cannot find GetEnumerator method for type {collectionType}");
        }

        // Store the collection in a local temporarily (already on stack)
        // Call GetEnumerator on the collection
        _currentIL.Emit(OpCodes.Callvirt, getEnumeratorMethod);

        // Store the enumerator in a local variable
        var enumeratorLocal = _currentIL.DeclareLocal(enumeratorType);
        _currentIL.Emit(OpCodes.Stloc, enumeratorLocal);

        // Create a try-finally block for proper disposal
        _currentIL.BeginExceptionBlock();

        // Define labels for loop control
        var loopStart = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        // Mark the start of the loop
        _currentIL.MarkLabel(loopStart);

        // Load the enumerator and call MoveNext()
        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        var moveNextMethod = enumeratorType.GetMethod("MoveNext") ?? typeof(System.Collections.IEnumerator).GetMethod("MoveNext");
        if (moveNextMethod == null)
        {
            throw new InvalidOperationException("Cannot find MoveNext method");
        }
        _currentIL.Emit(OpCodes.Callvirt, moveNextMethod);

        // If MoveNext returns false, exit the loop
        _currentIL.Emit(OpCodes.Brfalse, loopEnd);

        // Get the current element
        _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
        var currentProperty = enumeratorType.GetProperty("Current");
        if (currentProperty == null)
        {
            throw new InvalidOperationException("Cannot find Current property");
        }
        var getCurrentMethod = currentProperty.GetGetMethod();
        if (getCurrentMethod == null)
        {
            throw new InvalidOperationException("Cannot find get_Current method");
        }
        _currentIL.Emit(OpCodes.Callvirt, getCurrentMethod);

        // Declare the loop variable and store the current element
        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingLocal))
        {
            loopVar = existingLocal;
        }
        else
        {
            loopVar = _currentIL.DeclareLocal(elementType);
            _locals[foreachStmt.VariableName] = loopVar;
        }
        _currentIL.Emit(OpCodes.Stloc, loopVar);

        // Emit the loop body
        EmitStatement(foreachStmt.Body);

        // Jump back to the loop start
        _currentIL.Emit(OpCodes.Br, loopStart);

        // Mark the end of the loop
        _currentIL.MarkLabel(loopEnd);

        // Begin the finally block to dispose the enumerator
        _currentIL.BeginFinallyBlock();

        // Check if enumerator is IDisposable and dispose it
        if (typeof(IDisposable).IsAssignableFrom(enumeratorType))
        {
            _currentIL.Emit(OpCodes.Ldloc, enumeratorLocal);
            var disposeMethod = typeof(IDisposable).GetMethod("Dispose");
            if (disposeMethod != null)
            {
                _currentIL.Emit(OpCodes.Callvirt, disposeMethod);
            }
        }

        // End the exception block
        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for foreach over an array (using index-based iteration)
    /// </summary>
    private void EmitForeachForArray(ForeachStatement foreachStmt, Type arrayType, Type elementType)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Store the array in a local
        var arrayLocal = _currentIL.DeclareLocal(arrayType);
        _currentIL.Emit(OpCodes.Stloc, arrayLocal);

        // Create index variable (int)
        var indexLocal = _currentIL.DeclareLocal(typeof(int));

        // Initialize index to 0
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // Define labels
        var loopStart = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        // Mark loop start
        _currentIL.MarkLabel(loopStart);

        // Check if index < array.Length
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldlen);
        _currentIL.Emit(OpCodes.Conv_I4);
        _currentIL.Emit(OpCodes.Bge, loopEnd);  // Branch if index >= length

        // Load array element: array[index]
        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);

        // Use appropriate array element load instruction
        if (elementType == typeof(int))
            _currentIL.Emit(OpCodes.Ldelem_I4);
        else if (elementType == typeof(long))
            _currentIL.Emit(OpCodes.Ldelem_I8);
        else if (elementType == typeof(bool) || elementType == typeof(byte))
            _currentIL.Emit(OpCodes.Ldelem_U1);
        else if (elementType == typeof(double))
            _currentIL.Emit(OpCodes.Ldelem_R8);
        else if (elementType == typeof(float))
            _currentIL.Emit(OpCodes.Ldelem_R4);
        else if (elementType.IsValueType)
            _currentIL.Emit(OpCodes.Ldelem, elementType);
        else
            _currentIL.Emit(OpCodes.Ldelem_Ref);

        // Declare loop variable and store element
        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingLocal))
        {
            loopVar = existingLocal;
        }
        else
        {
            loopVar = _currentIL.DeclareLocal(elementType);
            _locals[foreachStmt.VariableName] = loopVar;
        }
        _currentIL.Emit(OpCodes.Stloc, loopVar);

        // Emit loop body
        EmitStatement(foreachStmt.Body);

        // Increment index
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // Jump back to loop start
        _currentIL.Emit(OpCodes.Br, loopStart);

        // Mark loop end
        _currentIL.MarkLabel(loopEnd);
    }

    /// <summary>
    /// Emit IL for a try/catch/finally statement
    /// </summary>
    private void EmitTry(TryStatement tryStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        // Begin exception block
        _currentIL.BeginExceptionBlock();

        // Emit the try block
        EmitStatement(tryStmt.TryBlock);

        // Emit catch clauses
        foreach (var catchClause in tryStmt.CatchClauses)
        {
            // Determine exception type
            Type exceptionType = typeof(Exception);
            if (catchClause.ExceptionType != null)
            {
                exceptionType = ResolveType(catchClause.ExceptionType, _currentGenericParameters);
            }

            // Begin catch block
            _currentIL.BeginCatchBlock(exceptionType);

            // If there's a variable name, store the exception in a local
            if (catchClause.VariableName != null)
            {
                LocalBuilder exceptionLocal;
                if (_locals.TryGetValue(catchClause.VariableName, out var existingLocal))
                {
                    exceptionLocal = existingLocal;
                }
                else
                {
                    exceptionLocal = _currentIL.DeclareLocal(exceptionType);
                    _locals[catchClause.VariableName] = exceptionLocal;
                }
                _currentIL.Emit(OpCodes.Stloc, exceptionLocal);
            }
            else
            {
                // If no variable name, pop the exception from the stack
                _currentIL.Emit(OpCodes.Pop);
            }

            // Emit the catch block
            EmitStatement(catchClause.Block);
        }

        // Emit finally block if present
        if (tryStmt.FinallyBlock != null)
        {
            _currentIL.BeginFinallyBlock();
            EmitStatement(tryStmt.FinallyBlock);
        }

        // End exception block
        _currentIL.EndExceptionBlock();
    }

    /// <summary>
    /// Emit IL for a using statement
    /// </summary>
    private void EmitUsing(UsingStatement usingStmt)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        LocalBuilder? resourceLocal = null;

        // Handle using with declaration: using (var x = expr) { ... }
        if (usingStmt.Declaration != null)
        {
            // Emit the variable declaration
            EmitVariableDeclaration(usingStmt.Declaration);
            resourceLocal = _locals[usingStmt.Declaration.Name];
        }
        // Handle using with expression: using (expr) { ... }
        else if (usingStmt.Expression != null)
        {
            // Evaluate the expression and store in a temp local
            EmitExpression(usingStmt.Expression);
            var exprType = GetExpressionType(usingStmt.Expression);
            resourceLocal = _currentIL.DeclareLocal(exprType);
            _currentIL.Emit(OpCodes.Stloc, resourceLocal);
        }

        if (resourceLocal == null)
        {
            throw new InvalidOperationException("Using statement must have either a declaration or an expression");
        }

        // Begin try-finally block
        _currentIL.BeginExceptionBlock();

        // Emit the body
        if (usingStmt.Body != null)
        {
            EmitStatement(usingStmt.Body);
        }

        // Emit finally block to dispose the resource
        _currentIL.BeginFinallyBlock();

        // Check if resource is null before calling Dispose
        // We need to call Dispose() on IDisposable
        var disposeMethod = typeof(IDisposable).GetMethod("Dispose");
        if (disposeMethod != null)
        {
            var endLabel = _currentIL.DefineLabel();

            // Load the resource
            _currentIL.Emit(OpCodes.Ldloc, resourceLocal);

            // If it's a value type, box it
            if (resourceLocal.LocalType.IsValueType)
            {
                _currentIL.Emit(OpCodes.Box, resourceLocal.LocalType);
            }

            // Duplicate for null check
            _currentIL.Emit(OpCodes.Dup);

            // Check if null
            _currentIL.Emit(OpCodes.Brfalse_S, endLabel);

            // Cast to IDisposable if needed
            if (resourceLocal.LocalType != typeof(IDisposable) && !resourceLocal.LocalType.IsValueType)
            {
                _currentIL.Emit(OpCodes.Castclass, typeof(IDisposable));
            }

            // Call Dispose
            _currentIL.Emit(OpCodes.Callvirt, disposeMethod);
            _currentIL.Emit(OpCodes.Br_S, endLabel);

            // End label (for null case or after dispose)
            _currentIL.MarkLabel(endLabel);

            // If we duplicated for null check, we might have a value on the stack
            // The MSIL verification should handle this, but we need to be careful
        }

        // End exception block
        _currentIL.EndExceptionBlock();
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

            case InterpolatedStringExpression interpolated:
                // For IL compilation, emit interpolated strings using string.Format or string.Concat
                // For now, concatenate the parts as a simple approach
                EmitInterpolatedString(interpolated);
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

            case MatchExpression match:
                EmitMatchExpression(match);
                break;

            case LambdaExpression lambda:
                EmitLambda(lambda);
                break;

            case ParenthesizedExpression paren:
                EmitExpression(paren.Inner);
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
    /// Emit IL for an interpolated string using string.Concat
    /// </summary>
    private void EmitInterpolatedString(InterpolatedStringExpression interpolated)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // Simple approach: convert each part to a string and concatenate
        var parts = new List<InterpolatedStringPart>(interpolated.Parts);
        if (parts.Count == 0)
        {
            _currentIL.Emit(OpCodes.Ldstr, "");
            return;
        }

        // Emit each part
        foreach (var part in parts)
        {
            switch (part)
            {
                case InterpolatedStringText text:
                    _currentIL.Emit(OpCodes.Ldstr, text.Text);
                    break;
                case InterpolatedStringHole hole:
                    EmitExpression(hole.Expression);
                    // Convert to string if not already
                    var exprType = GetExpressionType(hole.Expression);
                    if (exprType != typeof(string))
                    {
                        if (exprType.IsValueType)
                        {
                            _currentIL.Emit(OpCodes.Box, exprType);
                        }
                        var toStringMethod = typeof(object).GetMethod("ToString", Type.EmptyTypes)!;
                        _currentIL.Emit(OpCodes.Callvirt, toStringMethod);
                    }
                    break;
            }
        }

        // Concatenate all parts
        if (parts.Count > 1)
        {
            var concatMethod = typeof(string).GetMethod("Concat", new[] { typeof(string), typeof(string) })!;
            for (int i = 1; i < parts.Count; i++)
            {
                _currentIL.Emit(OpCodes.Call, concatMethod);
            }
        }
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
        // Check if it's a closure field
        else if (_closureFields != null && _closureFields.TryGetValue(ident.Name, out var closureField))
        {
            // Load 'this' (closure instance at arg 0)
            _currentIL.Emit(OpCodes.Ldarg_0);
            // Load the field
            _currentIL.Emit(OpCodes.Ldfld, closureField);
        }
        // Check if it's an instance field (in current class or base classes)
        else if (_currentTypeBuilder != null)
        {
            var fieldInfo = FindField(_currentTypeBuilder, ident.Name);
            if (fieldInfo != null)
            {
                // Load 'this' pointer
                _currentIL.Emit(OpCodes.Ldarg_0);
                // Load the field
                _currentIL.Emit(OpCodes.Ldfld, fieldInfo);
            }
            else
            {
                throw new InvalidOperationException($"Undefined variable, parameter, or field: {ident.Name}");
            }
        }
        else
        {
            throw new InvalidOperationException($"Undefined variable or parameter: {ident.Name}");
        }
    }

    /// <summary>
    /// Find a field in the current type or its base types
    /// </summary>
    private FieldInfo? FindField(TypeBuilder typeBuilder, string fieldName)
    {
        // Check in declared fields of current type
        var fieldKey = $"{typeBuilder.Name}.{fieldName}";
        if (_fields.TryGetValue(fieldKey, out var fieldBuilder))
        {
            return fieldBuilder;
        }

        // Check in base type
        var baseType = typeBuilder.BaseType;
        if (baseType != null && baseType != typeof(object))
        {
            // If base type is also a TypeBuilder in our compilation unit, check our fields dictionary
            if (baseType is TypeBuilder baseTypeBuilder)
            {
                var baseFieldKey = $"{baseTypeBuilder.Name}.{fieldName}";
                if (_fields.TryGetValue(baseFieldKey, out var baseFieldBuilder))
                {
                    return baseFieldBuilder;
                }
            }
            else
            {
                // External type - use reflection
                var field = baseType.GetField(fieldName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
                if (field != null)
                {
                    return field;
                }
            }
        }

        return null;
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
            InterpolatedStringExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            IdentifierExpression ident => GetIdentifierType(ident),
            BinaryExpression binary => GetBinaryExpressionType(binary),
            ParenthesizedExpression paren => GetExpressionType(paren.Inner),
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

        // Collect all potential base types (base class and interfaces)
        var allBaseTypes = new List<Type>();

        if (classDecl.BaseClass != null)
        {
            var resolvedType = ResolveType(classDecl.BaseClass);
            allBaseTypes.Add(resolvedType);
        }

        if (classDecl.Interfaces != null && classDecl.Interfaces.Count > 0)
        {
            allBaseTypes.AddRange(classDecl.Interfaces.Select(ResolveType));
        }

        // Separate base class from interfaces
        // A class can only have one base class, but multiple interfaces
        Type? baseType = null;
        var interfacesList = new List<Type>();

        foreach (var type in allBaseTypes)
        {
            if (type.IsInterface)
            {
                interfacesList.Add(type);
            }
            else if (type.IsClass)
            {
                if (baseType != null)
                {
                    throw new InvalidOperationException($"Class {classDecl.Name} cannot have multiple base classes");
                }
                baseType = type;
            }
        }

        // Define the type with base class and interfaces
        var interfaces = interfacesList.Count > 0 ? interfacesList.ToArray() : null;
        var typeBuilder = moduleBuilder.DefineType(
            classDecl.Name,
            typeAttributes,
            baseType,
            interfaces);

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
    /// Declare an interface type (first pass)
    /// </summary>
    private void DeclareInterface(ModuleBuilder moduleBuilder, InterfaceDeclaration interfaceDecl)
    {
        // Skip duck interfaces - they are type-erased
        if (interfaceDecl.IsDuckInterface)
            return;

        var typeAttributes = TypeAttributes.Public | TypeAttributes.Interface | TypeAttributes.Abstract;

        // Determine base interfaces
        Type[]? baseInterfaces = null;
        if (interfaceDecl.BaseInterfaces != null && interfaceDecl.BaseInterfaces.Count > 0)
        {
            baseInterfaces = interfaceDecl.BaseInterfaces
                .Select(ResolveType)
                .ToArray();
        }

        // Define the interface type
        var typeBuilder = moduleBuilder.DefineType(
            interfaceDecl.Name,
            typeAttributes,
            null,  // Interfaces have no base class
            baseInterfaces);

        _types[interfaceDecl.Name] = typeBuilder;
    }

    /// <summary>
    /// Declare interface members (second pass)
    /// </summary>
    private void DeclareInterfaceMembers(InterfaceDeclaration interfaceDecl)
    {
        // Skip duck interfaces - they are type-erased
        if (interfaceDecl.IsDuckInterface)
            return;

        if (!_types.TryGetValue(interfaceDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Interface {interfaceDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        foreach (var member in interfaceDecl.Members)
        {
            if (member is FunctionDeclaration funcDecl)
            {
                // Interface methods are abstract by default
                DeclareInterfaceMethod(typeBuilder, funcDecl);
            }
        }

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Declare an interface method
    /// </summary>
    private void DeclareInterfaceMethod(TypeBuilder typeBuilder, FunctionDeclaration funcDecl)
    {
        var returnType = funcDecl.ReturnType != null
            ? ResolveType(funcDecl.ReturnType)
            : typeof(void);

        var parameterTypes = funcDecl.Parameters
            .Select(p => ResolveType(p.Type))
            .ToArray();

        // Interface methods are always public, abstract, and virtual
        var methodAttributes = MethodAttributes.Public | MethodAttributes.Abstract | MethodAttributes.Virtual | MethodAttributes.HideBySig | MethodAttributes.NewSlot;

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

        // Store method for reference (interface methods don't have bodies)
        _methods[$"{typeBuilder.Name}.{funcDecl.Name}"] = methodBuilder;
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
            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.NewSlot;
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

    /// <summary>
    /// Emit IL for a match expression (pattern matching)
    /// </summary>
    private void EmitMatchExpression(MatchExpression match)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var endLabel = _currentIL.DefineLabel();
        var caseLabels = new Label[match.Cases.Count];
        var nextCaseLabels = new Label[match.Cases.Count];

        // Define labels for each case
        for (int i = 0; i < match.Cases.Count; i++)
        {
            caseLabels[i] = _currentIL.DefineLabel();
            nextCaseLabels[i] = _currentIL.DefineLabel();
        }

        // Store the matched value in a local (we'll need it for multiple comparisons)
        var matchValueType = GetExpressionType(match.Value);
        EmitExpression(match.Value);
        var matchLocal = _currentIL.DeclareLocal(matchValueType);
        _currentIL.Emit(OpCodes.Stloc, matchLocal);

        // Generate code for each case
        for (int i = 0; i < match.Cases.Count; i++)
        {
            var matchCase = match.Cases[i];

            // Emit pattern matching test
            _currentIL.Emit(OpCodes.Ldloc, matchLocal);
            EmitPatternTest(matchCase.Pattern, matchValueType, caseLabels[i], nextCaseLabels[i]);

            // Check guard if present
            if (matchCase.Guard != null)
            {
                EmitExpression(matchCase.Guard);
                _currentIL.Emit(OpCodes.Brfalse, nextCaseLabels[i]); // If guard is false, try next case
            }

            // Mark the label for this case body
            _currentIL.MarkLabel(caseLabels[i]);

            // Emit the case body
            EmitExpression(matchCase.Expression);
            _currentIL.Emit(OpCodes.Br, endLabel); // Jump to end after executing case

            // Mark the label for the next case
            _currentIL.MarkLabel(nextCaseLabels[i]);
        }

        // If no case matched, throw MatchException
        _currentIL.Emit(OpCodes.Ldstr, "No matching case in match expression");
        var matchExceptionCtor = typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) });
        if (matchExceptionCtor != null)
        {
            _currentIL.Emit(OpCodes.Newobj, matchExceptionCtor);
            _currentIL.Emit(OpCodes.Throw);
        }

        // Mark the end label
        _currentIL.MarkLabel(endLabel);
    }

    /// <summary>
    /// Emit IL to test if a pattern matches, jumping to successLabel if it does, otherwise falling through to failLabel
    /// </summary>
    private void EmitPatternTest(Pattern pattern, Type matchValueType, Label successLabel, Label failLabel)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        switch (pattern)
        {
            case LiteralPattern literalPattern:
                // Compare value with literal
                // Stack: [value]
                EmitExpression(literalPattern.Literal);
                // Stack: [value, literal]

                // Use appropriate comparison based on type
                if (matchValueType == typeof(string))
                {
                    var stringEquals = typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) });
                    if (stringEquals != null)
                    {
                        _currentIL.Emit(OpCodes.Call, stringEquals);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                    }
                }
                else if (matchValueType.IsValueType)
                {
                    _currentIL.Emit(OpCodes.Ceq);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Ceq);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                }
                break;

            case IdentifierPattern identPattern:
                // Wildcard pattern or variable binding - always matches
                if (identPattern.Name == "_")
                {
                    // Discard pattern - pop the value and jump to success
                    _currentIL.Emit(OpCodes.Pop);
                    _currentIL.Emit(OpCodes.Br, successLabel);
                }
                else
                {
                    // Variable binding - store the value in a local and jump to success
                    if (_locals == null)
                    {
                        _locals = new Dictionary<string, LocalBuilder>();
                    }

                    var local = _currentIL.DeclareLocal(matchValueType);
                    _locals[identPattern.Name] = local;
                    _currentIL.Emit(OpCodes.Stloc, local);
                    _currentIL.Emit(OpCodes.Br, successLabel);
                }
                break;

            case UnionCasePattern unionPattern:
                // Union case pattern - check if value is instance of the union case type
                // This requires the union to be compiled as a class hierarchy
                // For now, we'll do a simple type check

                // Assuming union cases are compiled as subclasses, we can use isinst
                // to check if the value is an instance of the case type

                // Get the union case type (this would be the subclass name)
                var unionCaseTypeName = unionPattern.CaseName;

                // For now, just emit a placeholder that checks type by name
                // In a full implementation, we'd need to resolve the actual union case type
                _currentIL.Emit(OpCodes.Dup);
                _currentIL.Emit(OpCodes.Callvirt, typeof(object).GetMethod("GetType")!);
                _currentIL.Emit(OpCodes.Callvirt, typeof(Type).GetProperty("Name")!.GetGetMethod()!);
                _currentIL.Emit(OpCodes.Ldstr, unionCaseTypeName);
                var stringEqualsMethod = typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) });
                if (stringEqualsMethod != null)
                {
                    _currentIL.Emit(OpCodes.Call, stringEqualsMethod);
                    _currentIL.Emit(OpCodes.Brtrue, successLabel);
                }
                _currentIL.Emit(OpCodes.Pop); // Pop the original value
                break;

            case RelationalPattern relationalPattern:
                // Relational pattern (< value, >= value, etc.)
                // Stack: [value]
                EmitExpression(relationalPattern.Value);
                // Stack: [value, relational_value]

                switch (relationalPattern.Operator)
                {
                    case "<":
                        _currentIL.Emit(OpCodes.Clt);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        break;
                    case ">":
                        _currentIL.Emit(OpCodes.Cgt);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        break;
                    case "<=":
                        _currentIL.Emit(OpCodes.Cgt);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        break;
                    case ">=":
                        _currentIL.Emit(OpCodes.Clt);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        break;
                    case "==":
                        _currentIL.Emit(OpCodes.Ceq);
                        _currentIL.Emit(OpCodes.Brtrue, successLabel);
                        break;
                    case "!=":
                        _currentIL.Emit(OpCodes.Ceq);
                        _currentIL.Emit(OpCodes.Brfalse, successLabel);
                        break;
                }
                break;

            case AndPattern andPattern:
                // Both patterns must match
                var andNextLabel = _currentIL.DefineLabel();

                // Test first pattern
                _currentIL.Emit(OpCodes.Dup); // Duplicate value for second test
                EmitPatternTest(andPattern.Left, matchValueType, andNextLabel, failLabel);

                // First pattern didn't match, clean up and fail
                _currentIL.Emit(OpCodes.Pop);
                _currentIL.Emit(OpCodes.Br, failLabel);

                // First pattern matched, test second
                _currentIL.MarkLabel(andNextLabel);
                EmitPatternTest(andPattern.Right, matchValueType, successLabel, failLabel);
                break;

            case OrPattern orPattern:
                // Either pattern can match
                var orNextLabel = _currentIL.DefineLabel();

                // Test first pattern
                _currentIL.Emit(OpCodes.Dup); // Duplicate value for second test
                EmitPatternTest(orPattern.Left, matchValueType, successLabel, orNextLabel);

                // First pattern didn't match, try second
                _currentIL.MarkLabel(orNextLabel);
                EmitPatternTest(orPattern.Right, matchValueType, successLabel, failLabel);
                break;

            case NotPattern notPattern:
                // Pattern must NOT match
                var notMatchLabel = _currentIL.DefineLabel();

                // Test the inner pattern
                _currentIL.Emit(OpCodes.Dup);
                EmitPatternTest(notPattern.Pattern, matchValueType, notMatchLabel, successLabel);

                // Pattern matched, so not pattern fails
                _currentIL.MarkLabel(notMatchLabel);
                _currentIL.Emit(OpCodes.Pop);
                _currentIL.Emit(OpCodes.Br, failLabel);
                break;

            case TypePattern typePatternWithName:
                // Type pattern with variable binding
                var type = ResolveType(typePatternWithName.Type);
                _currentIL.Emit(OpCodes.Isinst, type);
                _currentIL.Emit(OpCodes.Dup);
                var notNullLabel = _currentIL.DefineLabel();
                _currentIL.Emit(OpCodes.Brtrue, notNullLabel);
                _currentIL.Emit(OpCodes.Pop);
                _currentIL.Emit(OpCodes.Br, failLabel);

                _currentIL.MarkLabel(notNullLabel);
                if (typePatternWithName.BindingName != null)
                {
                    if (_locals == null)
                    {
                        _locals = new Dictionary<string, LocalBuilder>();
                    }
                    var local = _currentIL.DeclareLocal(type);
                    _locals[typePatternWithName.BindingName] = local;
                    _currentIL.Emit(OpCodes.Stloc, local);
                }
                else
                {
                    _currentIL.Emit(OpCodes.Pop);
                }
                _currentIL.Emit(OpCodes.Br, successLabel);
                break;

            default:
                throw new NotImplementedException($"Pattern type {pattern.GetType().Name} not yet implemented in IL compiler");
        }
    }

    /// <summary>
    /// Declare a record type (first pass)
    /// </summary>
    private void DeclareRecord(ModuleBuilder moduleBuilder, RecordDeclaration recordDecl)
    {
        // Records can be either classes (record class, default) or structs (record struct)
        TypeAttributes typeAttributes;
        Type? baseType;

        if (recordDecl.IsStruct)
        {
            // Record struct: value type, sealed
            typeAttributes = TypeAttributes.Public | TypeAttributes.Sealed;
            baseType = typeof(ValueType);
        }
        else
        {
            // Record class: reference type, sealed by default
            typeAttributes = TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.Sealed;
            baseType = typeof(object);
        }

        // Handle interfaces
        Type[]? interfaces = null;
        if (recordDecl.Interfaces != null && recordDecl.Interfaces.Count > 0)
        {
            interfaces = recordDecl.Interfaces.Select(ResolveType).ToArray();
        }

        var typeBuilder = moduleBuilder.DefineType(
            recordDecl.Name,
            typeAttributes,
            baseType,
            interfaces);

        _types[recordDecl.Name] = typeBuilder;
    }

    /// <summary>
    /// Declare record members (second pass)
    /// </summary>
    private void DeclareRecordMembers(RecordDeclaration recordDecl)
    {
        if (!_types.TryGetValue(recordDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {recordDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Declare fields for primary constructor parameters (as backing fields for auto-properties)
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var fieldType = ResolveType(param.Type);

                // Define backing field
                var backingFieldName = $"<{param.Name}>k__BackingField";
                var backingField = typeBuilder.DefineField(
                    backingFieldName,
                    fieldType,
                    FieldAttributes.Private | FieldAttributes.InitOnly);

                _fields[$"{recordDecl.Name}.{backingFieldName}"] = backingField;

                // Define property
                var property = typeBuilder.DefineProperty(
                    param.Name,
                    PropertyAttributes.None,
                    fieldType,
                    null);

                // Define getter
                var getter = typeBuilder.DefineMethod(
                    $"get_{param.Name}",
                    MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
                    fieldType,
                    Type.EmptyTypes);

                _methods[$"{recordDecl.Name}.get_{param.Name}"] = getter;
                property.SetGetMethod(getter);
            }

            // Declare primary constructor
            var paramTypes = recordDecl.PrimaryConstructorParameters
                .Select(p => ResolveType(p.Type))
                .ToArray();

            var constructor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                paramTypes);

            _constructors[$"{recordDecl.Name}..ctor"] = constructor;
        }
        else
        {
            // No primary constructor - create default parameterless constructor
            var defaultCtor = typeBuilder.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);

            _constructors[$"{recordDecl.Name}..ctor"] = defaultCtor;
        }

        // Declare other members
        foreach (var member in recordDecl.Members)
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

        // Declare Equals(object) override
        var equalsMethod = typeBuilder.DefineMethod(
            "Equals",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(bool),
            new[] { typeof(object) });

        _methods[$"{recordDecl.Name}.Equals"] = equalsMethod;

        // Declare GetHashCode override
        var getHashCodeMethod = typeBuilder.DefineMethod(
            "GetHashCode",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(int),
            Type.EmptyTypes);

        _methods[$"{recordDecl.Name}.GetHashCode"] = getHashCodeMethod;

        // Declare ToString override
        var toStringMethod = typeBuilder.DefineMethod(
            "ToString",
            MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
            typeof(string),
            Type.EmptyTypes);

        _methods[$"{recordDecl.Name}.ToString"] = toStringMethod;

        _currentTypeBuilder = null;
    }

    /// <summary>
    /// Emit record method bodies (third pass)
    /// </summary>
    private void EmitRecordBodies(RecordDeclaration recordDecl)
    {
        if (!_types.TryGetValue(recordDecl.Name, out var typeBuilder))
        {
            throw new InvalidOperationException($"Type {recordDecl.Name} not declared");
        }

        _currentTypeBuilder = typeBuilder;

        // Emit property getters for primary constructor parameters
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var getterKey = $"{recordDecl.Name}.get_{param.Name}";
                if (_methods.TryGetValue(getterKey, out var getter))
                {
                    var il = getter.GetILGenerator();
                    var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                    if (_fields.TryGetValue(backingFieldKey, out var backingField))
                    {
                        il.Emit(OpCodes.Ldarg_0);
                        il.Emit(OpCodes.Ldfld, backingField);
                        il.Emit(OpCodes.Ret);
                    }
                }
            }

            // Emit primary constructor body
            var ctorKey = $"{recordDecl.Name}..ctor";
            if (_constructors.TryGetValue(ctorKey, out var constructor))
            {
                var il = constructor.GetILGenerator();

                // Call base constructor
                il.Emit(OpCodes.Ldarg_0);
                var baseType = typeBuilder.BaseType;
                var baseCtor = baseType?.GetConstructor(Type.EmptyTypes);
                if (baseCtor != null)
                {
                    il.Emit(OpCodes.Call, baseCtor);
                }

                // Initialize backing fields from parameters
                for (int i = 0; i < recordDecl.PrimaryConstructorParameters.Count; i++)
                {
                    var param = recordDecl.PrimaryConstructorParameters[i];
                    var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                    if (_fields.TryGetValue(backingFieldKey, out var backingField))
                    {
                        il.Emit(OpCodes.Ldarg_0);
                        il.Emit(OpCodes.Ldarg, i + 1); // +1 because arg_0 is 'this'
                        il.Emit(OpCodes.Stfld, backingField);
                    }
                }

                il.Emit(OpCodes.Ret);
            }
        }
        else
        {
            // Emit default parameterless constructor
            var ctorKey = $"{recordDecl.Name}..ctor";
            if (_constructors.TryGetValue(ctorKey, out var constructor))
            {
                var il = constructor.GetILGenerator();

                // Call base constructor
                il.Emit(OpCodes.Ldarg_0);
                var baseType = typeBuilder.BaseType;
                var baseCtor = baseType?.GetConstructor(Type.EmptyTypes);
                if (baseCtor != null)
                {
                    il.Emit(OpCodes.Call, baseCtor);
                }

                il.Emit(OpCodes.Ret);
            }
        }

        // Emit Equals method
        EmitRecordEquals(recordDecl, typeBuilder);

        // Emit GetHashCode method
        EmitRecordGetHashCode(recordDecl, typeBuilder);

        // Emit ToString method
        EmitRecordToString(recordDecl, typeBuilder);

        // Emit other member bodies
        foreach (var member in recordDecl.Members)
        {
            switch (member)
            {
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
    /// Emit Equals method for record
    /// </summary>
    private void EmitRecordEquals(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var equalsKey = $"{recordDecl.Name}.Equals";
        if (!_methods.TryGetValue(equalsKey, out var equalsMethod))
            return;

        var il = equalsMethod.GetILGenerator();
        var returnFalse = il.DefineLabel();
        var compareFields = il.DefineLabel();

        // if (obj == null) return false;
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Brfalse, returnFalse);

        // if (!(obj is RecordType)) return false;
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Isinst, typeBuilder);
        il.Emit(OpCodes.Dup);
        il.Emit(OpCodes.Brtrue, compareFields);
        il.Emit(OpCodes.Pop);
        il.Emit(OpCodes.Br, returnFalse);

        // RecordType other = (RecordType)obj;
        il.MarkLabel(compareFields);
        var otherLocal = il.DeclareLocal(typeBuilder);
        il.Emit(OpCodes.Stloc, otherLocal);

        // Compare each field
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                if (_fields.TryGetValue(backingFieldKey, out var backingField))
                {
                    var fieldType = backingField.FieldType;

                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Ldfld, backingField);
                    il.Emit(OpCodes.Ldloc, otherLocal);
                    il.Emit(OpCodes.Ldfld, backingField);

                    // Use Equals for reference types and == for value types
                    if (fieldType.IsValueType)
                    {
                        il.Emit(OpCodes.Ceq);
                        il.Emit(OpCodes.Brfalse, returnFalse);
                    }
                    else
                    {
                        // Call static Object.Equals for proper null handling
                        var objectEqualsMethod = typeof(object).GetMethod("Equals", new[] { typeof(object), typeof(object) });
                        if (objectEqualsMethod != null)
                        {
                            il.Emit(OpCodes.Call, objectEqualsMethod);
                            il.Emit(OpCodes.Brfalse, returnFalse);
                        }
                    }
                }
            }
        }

        // All fields are equal, return true
        il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(OpCodes.Ret);

        // Return false
        il.MarkLabel(returnFalse);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit GetHashCode method for record
    /// </summary>
    private void EmitRecordGetHashCode(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var getHashCodeKey = $"{recordDecl.Name}.GetHashCode";
        if (!_methods.TryGetValue(getHashCodeKey, out var getHashCodeMethod))
            return;

        var il = getHashCodeMethod.GetILGenerator();
        var hashCodeLocal = il.DeclareLocal(typeof(int));

        // int hash = 17;
        il.Emit(OpCodes.Ldc_I4, 17);
        il.Emit(OpCodes.Stloc, hashCodeLocal);

        // Combine hash codes from all fields
        if (recordDecl.PrimaryConstructorParameters != null && recordDecl.PrimaryConstructorParameters.Count > 0)
        {
            foreach (var param in recordDecl.PrimaryConstructorParameters)
            {
                var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";
                if (_fields.TryGetValue(backingFieldKey, out var backingField))
                {
                    var fieldType = backingField.FieldType;

                    // hash = hash * 23 + field.GetHashCode();
                    il.Emit(OpCodes.Ldloc, hashCodeLocal);
                    il.Emit(OpCodes.Ldc_I4, 23);
                    il.Emit(OpCodes.Mul);

                    il.Emit(OpCodes.Ldarg_0);
                    il.Emit(OpCodes.Ldfld, backingField);

                    if (fieldType.IsValueType)
                    {
                        // For value types, box and call GetHashCode
                        il.Emit(OpCodes.Box, fieldType);
                    }

                    // Call GetHashCode (handles null for reference types)
                    var getHashCodeMethodInfo = typeof(object).GetMethod("GetHashCode", Type.EmptyTypes);
                    if (getHashCodeMethodInfo != null)
                    {
                        il.Emit(OpCodes.Callvirt, getHashCodeMethodInfo);
                    }

                    il.Emit(OpCodes.Add);
                    il.Emit(OpCodes.Stloc, hashCodeLocal);
                }
            }
        }

        il.Emit(OpCodes.Ldloc, hashCodeLocal);
        il.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Emit ToString method for record
    /// </summary>
    private void EmitRecordToString(RecordDeclaration recordDecl, TypeBuilder typeBuilder)
    {
        var toStringKey = $"{recordDecl.Name}.ToString";
        if (!_methods.TryGetValue(toStringKey, out var toStringMethod))
            return;

        var il = toStringMethod.GetILGenerator();

        // Build string: "RecordName { Prop1 = value1, Prop2 = value2 }"
        if (recordDecl.PrimaryConstructorParameters == null || recordDecl.PrimaryConstructorParameters.Count == 0)
        {
            // No properties, just return the type name
            il.Emit(OpCodes.Ldstr, recordDecl.Name);
            il.Emit(OpCodes.Ret);
            return;
        }

        // Use StringBuilder for efficient string concatenation
        var stringBuilderType = typeof(System.Text.StringBuilder);
        var sbCtor = stringBuilderType.GetConstructor(Type.EmptyTypes);
        var appendStringMethod = stringBuilderType.GetMethod("Append", new[] { typeof(string) });
        var appendObjectMethod = stringBuilderType.GetMethod("Append", new[] { typeof(object) });
        var toStringMethodInfo = stringBuilderType.GetMethod("ToString", Type.EmptyTypes);

        if (sbCtor == null || appendStringMethod == null || appendObjectMethod == null || toStringMethodInfo == null)
        {
            // Fallback: just return type name
            il.Emit(OpCodes.Ldstr, recordDecl.Name);
            il.Emit(OpCodes.Ret);
            return;
        }

        var sbLocal = il.DeclareLocal(stringBuilderType);
        il.Emit(OpCodes.Newobj, sbCtor);
        il.Emit(OpCodes.Stloc, sbLocal);

        // Append "RecordName { "
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Ldstr, $"{recordDecl.Name} {{ ");
        il.Emit(OpCodes.Callvirt, appendStringMethod);
        il.Emit(OpCodes.Pop);

        // Append each property
        for (int i = 0; i < recordDecl.PrimaryConstructorParameters.Count; i++)
        {
            var param = recordDecl.PrimaryConstructorParameters[i];
            var backingFieldKey = $"{recordDecl.Name}.<{param.Name}>k__BackingField";

            if (_fields.TryGetValue(backingFieldKey, out var backingField))
            {
                // Append "PropName = "
                il.Emit(OpCodes.Ldloc, sbLocal);
                il.Emit(OpCodes.Ldstr, $"{param.Name} = ");
                il.Emit(OpCodes.Callvirt, appendStringMethod);
                il.Emit(OpCodes.Pop);

                // Append value
                il.Emit(OpCodes.Ldloc, sbLocal);
                il.Emit(OpCodes.Ldarg_0);
                il.Emit(OpCodes.Ldfld, backingField);

                // Box value types
                if (backingField.FieldType.IsValueType)
                {
                    il.Emit(OpCodes.Box, backingField.FieldType);
                }

                il.Emit(OpCodes.Callvirt, appendObjectMethod);
                il.Emit(OpCodes.Pop);

                // Append ", " if not last property
                if (i < recordDecl.PrimaryConstructorParameters.Count - 1)
                {
                    il.Emit(OpCodes.Ldloc, sbLocal);
                    il.Emit(OpCodes.Ldstr, ", ");
                    il.Emit(OpCodes.Callvirt, appendStringMethod);
                    il.Emit(OpCodes.Pop);
                }
            }
        }

        // Append " }"
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Ldstr, " }");
        il.Emit(OpCodes.Callvirt, appendStringMethod);
        il.Emit(OpCodes.Pop);

        // Return sb.ToString()
        il.Emit(OpCodes.Ldloc, sbLocal);
        il.Emit(OpCodes.Callvirt, toStringMethodInfo);
        il.Emit(OpCodes.Ret);
    }
}
