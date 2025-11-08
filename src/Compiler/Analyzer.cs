using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

/// <summary>
/// Semantic analyzer for NewCLILang
/// Performs type checking, name resolution, and definite assignment analysis
/// </summary>
public class Analyzer
{
    private readonly List<CompilerError> _errors = new();
    private readonly Stack<Scope> _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private TypeInfo? _currentReturnType;
    private bool _inLoop;
    private ClassDeclaration? _currentClass;

    public AnalysisResult Analyze(CompilationUnit unit)
    {
        _errors.Clear();
        _scopes.Clear();
        _usingNamespaces.Clear();
        _usingAliases.Clear();
        _currentReturnType = null;
        _inLoop = false;

        // Process using statements
        foreach (var usingStmt in unit.Usings)
        {
            if (usingStmt.Alias != null)
            {
                _usingAliases[usingStmt.Alias] = usingStmt.Namespace;
            }
            else
            {
                _usingNamespaces.Add(usingStmt.Namespace);
            }
        }

        // Create global scope
        PushScope(new Scope(ScopeKind.Global));

        // First pass: collect all type declarations
        foreach (var decl in unit.Declarations)
        {
            if (decl is ClassDeclaration classDecl)
                DeclareType(classDecl.Name, new ClassTypeInfo(classDecl), decl.Line, decl.Column);
            else if (decl is StructDeclaration structDecl)
                DeclareType(structDecl.Name, new StructTypeInfo(structDecl), decl.Line, decl.Column);
            else if (decl is RecordDeclaration recordDecl)
                DeclareType(recordDecl.Name, new RecordTypeInfo(recordDecl), decl.Line, decl.Column);
            else if (decl is InterfaceDeclaration interfaceDecl)
                DeclareType(interfaceDecl.Name, new InterfaceTypeInfo(interfaceDecl), decl.Line, decl.Column);
            else if (decl is UnionDeclaration unionDecl)
                DeclareType(unionDecl.Name, new UnionTypeInfo(unionDecl), decl.Line, decl.Column);
            else if (decl is EnumDeclaration enumDecl)
                DeclareType(enumDecl.Name, new EnumTypeInfo(enumDecl), decl.Line, decl.Column);
            else if (decl is TypeAliasDeclaration aliasDecl)
                DeclareType(aliasDecl.Name, new AliasTypeInfo(aliasDecl.Type), decl.Line, decl.Column);
        }

        // Second pass: analyze all declarations
        foreach (var decl in unit.Declarations)
        {
            AnalyzeDeclaration(decl);
        }

        PopScope();

        return new AnalysisResult(_errors);
    }

    private void AnalyzeDeclaration(Declaration decl)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
                AnalyzeFunctionDeclaration(func);
                break;
            case ClassDeclaration classDecl:
                AnalyzeClassDeclaration(classDecl);
                break;
            case StructDeclaration structDecl:
                AnalyzeStructDeclaration(structDecl);
                break;
            case RecordDeclaration recordDecl:
                AnalyzeRecordDeclaration(recordDecl);
                break;
            case InterfaceDeclaration interfaceDecl:
                AnalyzeInterfaceDeclaration(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                AnalyzeUnionDeclaration(unionDecl);
                break;
            case EnumDeclaration enumDecl:
                AnalyzeEnumDeclaration(enumDecl);
                break;
            case FieldDeclaration field:
                AnalyzeFieldDeclaration(field);
                break;
            case PropertyDeclaration prop:
                AnalyzePropertyDeclaration(prop);
                break;
            case ConstructorDeclaration ctor:
                AnalyzeConstructorDeclaration(ctor);
                break;
        }
    }

    private void AnalyzeFunctionDeclaration(FunctionDeclaration func)
    {
        // Declare function in current scope
        var funcType = new FunctionTypeInfo(func);
        DeclareSymbol(func.Name, funcType, func.Line, func.Column);

        // Check visibility convention
        CheckVisibilityConvention(func.Name, func.Modifiers, func.Line, func.Column);

        PushScope(new Scope(ScopeKind.Function));

        // Add parameters to scope
        foreach (var param in func.Parameters)
        {
            var paramType = ResolveType(param.Type);
            DeclareSymbol(param.Name, paramType, func.Line, func.Column);
        }

        // Set expected return type
        _currentReturnType = func.ReturnType != null ? ResolveType(func.ReturnType) : BuiltInTypes.Void;

        // Analyze body
        if (func.Body != null)
        {
            AnalyzeStatement(func.Body);
        }

        _currentReturnType = null;
        PopScope();
    }

    private void AnalyzeClassDeclaration(ClassDeclaration classDecl)
    {
        var previousClass = _currentClass;
        _currentClass = classDecl;

        CheckVisibilityConvention(classDecl.Name, classDecl.Modifiers, classDecl.Line, classDecl.Column);

        PushScope(new Scope(ScopeKind.Class));

        // Add 'this' to scope
        var classType = new ClassTypeInfo(classDecl);
        DeclareSymbol("this", classType, classDecl.Line, classDecl.Column);

        // Analyze members
        foreach (var member in classDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
        _currentClass = previousClass;
    }

    private void AnalyzeStructDeclaration(StructDeclaration structDecl)
    {
        CheckVisibilityConvention(structDecl.Name, structDecl.Modifiers, structDecl.Line, structDecl.Column);

        PushScope(new Scope(ScopeKind.Struct));

        var structType = new StructTypeInfo(structDecl);
        DeclareSymbol("this", structType, structDecl.Line, structDecl.Column);

        foreach (var member in structDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
    }

    private void AnalyzeRecordDeclaration(RecordDeclaration recordDecl)
    {
        CheckVisibilityConvention(recordDecl.Name, recordDecl.Modifiers, recordDecl.Line, recordDecl.Column);

        PushScope(new Scope(ScopeKind.Record));

        var recordType = new RecordTypeInfo(recordDecl);
        DeclareSymbol("this", recordType, recordDecl.Line, recordDecl.Column);

        foreach (var member in recordDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
    }

    private void AnalyzeInterfaceDeclaration(InterfaceDeclaration interfaceDecl)
    {
        CheckVisibilityConvention(interfaceDecl.Name, interfaceDecl.Modifiers, interfaceDecl.Line, interfaceDecl.Column);

        PushScope(new Scope(ScopeKind.Interface));

        foreach (var member in interfaceDecl.Members)
        {
            AnalyzeDeclaration(member);
        }

        PopScope();
    }

    private void AnalyzeUnionDeclaration(UnionDeclaration unionDecl)
    {
        CheckVisibilityConvention(unionDecl.Name, unionDecl.Modifiers, unionDecl.Line, unionDecl.Column);

        // Validate union cases
        var caseNames = new HashSet<string>();
        foreach (var unionCase in unionDecl.Cases)
        {
            if (!caseNames.Add(unionCase.Name))
            {
                Error($"Duplicate union case '{unionCase.Name}'", unionDecl.Line, unionDecl.Column);
            }
        }
    }

    private void AnalyzeEnumDeclaration(EnumDeclaration enumDecl)
    {
        CheckVisibilityConvention(enumDecl.Name, enumDecl.Modifiers, enumDecl.Line, enumDecl.Column);

        // Validate enum members
        var memberNames = new HashSet<string>();
        foreach (var member in enumDecl.Members)
        {
            if (!memberNames.Add(member.Name))
            {
                Error($"Duplicate enum member '{member.Name}'", enumDecl.Line, enumDecl.Column);
            }

            // Type check initializers
            if (member.Value != null)
            {
                var valueType = AnalyzeExpression(member.Value);
                if (enumDecl.Type == EnumType.Int && !IsNumericType(valueType))
                {
                    Error($"Enum member value must be numeric", enumDecl.Line, enumDecl.Column);
                }
                else if (enumDecl.Type == EnumType.String && !IsStringType(valueType))
                {
                    Error($"Enum member value must be string", enumDecl.Line, enumDecl.Column);
                }
            }
        }
    }

    private void AnalyzeFieldDeclaration(FieldDeclaration field)
    {
        CheckVisibilityConvention(field.Name, field.Modifiers, field.Line, field.Column);

        var fieldType = ResolveType(field.Type);
        DeclareSymbol(field.Name, fieldType, field.Line, field.Column);

        if (field.Initializer != null)
        {
            var initType = AnalyzeExpression(field.Initializer);
            if (!IsAssignable(fieldType, initType))
            {
                Error($"Cannot assign '{initType}' to '{fieldType}'", field.Line, field.Column);
            }
        }
    }

    private void AnalyzePropertyDeclaration(PropertyDeclaration prop)
    {
        CheckVisibilityConvention(prop.Name, prop.Modifiers, prop.Line, prop.Column);

        var propType = ResolveType(prop.Type);
        DeclareSymbol(prop.Name, propType, prop.Line, prop.Column);

        // Analyze getter
        if (prop.GetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            AnalyzeStatement(prop.GetBody);
            // TODO: Verify getter returns the property type
            PopScope();
        }

        // Analyze setter
        if (prop.SetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            // Implicitly declare 'value' parameter
            DeclareSymbol("value", propType, prop.Line, prop.Column);
            AnalyzeStatement(prop.SetBody);
            PopScope();
        }
    }

    private void AnalyzeConstructorDeclaration(ConstructorDeclaration ctor)
    {
        PushScope(new Scope(ScopeKind.Function));

        // Add parameters to scope
        foreach (var param in ctor.Parameters)
        {
            var paramType = ResolveType(param.Type);
            DeclareSymbol(param.Name, paramType, ctor.Line, ctor.Column);
        }

        // Analyze body
        AnalyzeStatement(ctor.Body);

        // TODO: Definite assignment analysis - check all non-nullable fields are assigned
        if (_currentClass != null)
        {
            CheckDefiniteAssignment(ctor, _currentClass);
        }

        PopScope();
    }

    private void CheckDefiniteAssignment(ConstructorDeclaration ctor, ClassDeclaration classDecl)
    {
        // Collect all non-nullable fields without initializers
        var uninitializedFields = new HashSet<string>();
        foreach (var member in classDecl.Members)
        {
            if (member is FieldDeclaration field)
            {
                if (field.Initializer == null && !IsNullableType(ResolveType(field.Type)))
                {
                    uninitializedFields.Add(field.Name);
                }
            }
        }

        // Check if constructor assigns all required fields
        var assignedFields = GetAssignedFields(ctor.Body);
        foreach (var field in uninitializedFields)
        {
            if (!assignedFields.Contains(field))
            {
                Error($"Non-nullable field '{field}' must be assigned in constructor", ctor.Line, ctor.Column);
            }
        }
    }

    private HashSet<string> GetAssignedFields(BlockStatement block)
    {
        var assigned = new HashSet<string>();
        foreach (var stmt in block.Statements)
        {
            if (stmt is ExpressionStatement { Expression: AssignmentExpression assignment })
            {
                if (assignment.Target is MemberAccessExpression { Object: ThisExpression } memberAccess)
                {
                    assigned.Add(memberAccess.MemberName);
                }
                else if (assignment.Target is IdentifierExpression ident)
                {
                    assigned.Add(ident.Name);
                }
            }
        }
        return assigned;
    }

    private void AnalyzeStatement(Statement stmt)
    {
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                AnalyzeExpression(exprStmt.Expression);
                break;
            case VariableDeclarationStatement varDecl:
                AnalyzeVariableDeclaration(varDecl);
                break;
            case TupleDeconstructionStatement tupleDecl:
                AnalyzeTupleDeconstruction(tupleDecl);
                break;
            case BlockStatement block:
                PushScope(new Scope(ScopeKind.Block));
                foreach (var s in block.Statements)
                    AnalyzeStatement(s);
                PopScope();
                break;
            case IfStatement ifStmt:
                AnalyzeIfStatement(ifStmt);
                break;
            case ForStatement forStmt:
                AnalyzeForStatement(forStmt);
                break;
            case ForeachStatement foreachStmt:
                AnalyzeForeachStatement(foreachStmt);
                break;
            case WhileStatement whileStmt:
                var condType = AnalyzeExpression(whileStmt.Condition);
                if (!IsBoolType(condType))
                {
                    Error($"While condition must be boolean", whileStmt.Line, whileStmt.Column);
                }
                var wasInLoop = _inLoop;
                _inLoop = true;
                AnalyzeStatement(whileStmt.Body);
                _inLoop = wasInLoop;
                break;
            case ReturnStatement returnStmt:
                AnalyzeReturnStatement(returnStmt);
                break;
            case BreakStatement:
                if (!_inLoop)
                {
                    Error("Break statement outside of loop", stmt.Line, stmt.Column);
                }
                break;
            case ContinueStatement:
                if (!_inLoop)
                {
                    Error("Continue statement outside of loop", stmt.Line, stmt.Column);
                }
                break;
            case ThrowStatement throwStmt:
                AnalyzeExpression(throwStmt.Expression);
                break;
            case TryStatement tryStmt:
                AnalyzeTryStatement(tryStmt);
                break;
            case UsingStatement usingStmt:
                AnalyzeUsingStatement(usingStmt);
                break;
            case SwitchStatement switchStmt:
                AnalyzeSwitchStatement(switchStmt);
                break;
        }
    }

    private void AnalyzeVariableDeclaration(VariableDeclarationStatement varDecl)
    {
        TypeInfo? declaredType = varDecl.Type != null ? ResolveType(varDecl.Type) : null;
        TypeInfo? inferredType = null;

        if (varDecl.Initializer != null)
        {
            inferredType = AnalyzeExpression(varDecl.Initializer);
        }

        // Determine final type
        TypeInfo finalType;
        if (declaredType != null && inferredType != null)
        {
            // Both specified - check compatibility
            if (!IsAssignable(declaredType, inferredType))
            {
                Error($"Cannot assign '{inferredType}' to '{declaredType}'", varDecl.Line, varDecl.Column);
            }
            finalType = declaredType;
        }
        else if (declaredType != null)
        {
            // Type specified but no initializer
            if (varDecl.Kind == VariableKind.Const)
            {
                Error("Const variables must have an initializer", varDecl.Line, varDecl.Column);
            }
            finalType = declaredType;
        }
        else if (inferredType != null)
        {
            // Inferred from initializer
            finalType = inferredType;
        }
        else
        {
            Error("Variable must have either a type annotation or an initializer", varDecl.Line, varDecl.Column);
            finalType = BuiltInTypes.Unknown;
        }

        DeclareSymbol(varDecl.Name, finalType, varDecl.Line, varDecl.Column);
    }

    private void AnalyzeTupleDeconstruction(TupleDeconstructionStatement tupleDecl)
    {
        // Analyze the initializer expression
        var initType = AnalyzeExpression(tupleDecl.Initializer);

        // TODO: Check if initType is a tuple type and has the right number of elements
        // For now, just declare all variables with Unknown type
        foreach (var name in tupleDecl.Names)
        {
            if (name != "_")  // Skip discard
            {
                DeclareSymbol(name, BuiltInTypes.Unknown, tupleDecl.Line, tupleDecl.Column);
            }
        }
    }

    private void AnalyzeIfStatement(IfStatement ifStmt)
    {
        var condType = AnalyzeExpression(ifStmt.Condition);
        if (!IsBoolType(condType))
        {
            Error($"If condition must be boolean", ifStmt.Line, ifStmt.Column);
        }

        AnalyzeStatement(ifStmt.ThenStatement);
        if (ifStmt.ElseStatement != null)
        {
            AnalyzeStatement(ifStmt.ElseStatement);
        }
    }

    private void AnalyzeForStatement(ForStatement forStmt)
    {
        PushScope(new Scope(ScopeKind.Block));

        if (forStmt.Initializer != null)
            AnalyzeStatement(forStmt.Initializer);

        if (forStmt.Condition != null)
        {
            var condType = AnalyzeExpression(forStmt.Condition);
            if (!IsBoolType(condType))
            {
                Error($"For condition must be boolean", forStmt.Line, forStmt.Column);
            }
        }

        if (forStmt.Iterator != null)
            AnalyzeExpression(forStmt.Iterator);

        var wasInLoop = _inLoop;
        _inLoop = true;
        AnalyzeStatement(forStmt.Body);
        _inLoop = wasInLoop;

        PopScope();
    }

    private void AnalyzeForeachStatement(ForeachStatement foreachStmt)
    {
        var collectionType = AnalyzeExpression(foreachStmt.Collection);

        // Check if collection is enumerable
        // For now, just check if it's an array or has a known collection type
        // TODO: More sophisticated enumerable checking

        PushScope(new Scope(ScopeKind.Block));

        // Infer element type (simplified)
        TypeInfo elementType = BuiltInTypes.Unknown;
        if (collectionType is ArrayTypeInfo arrayType)
        {
            elementType = arrayType.ElementType;
        }

        DeclareSymbol(foreachStmt.VariableName, elementType, foreachStmt.Line, foreachStmt.Column);

        var wasInLoop = _inLoop;
        _inLoop = true;
        AnalyzeStatement(foreachStmt.Body);
        _inLoop = wasInLoop;

        PopScope();
    }

    private void AnalyzeReturnStatement(ReturnStatement returnStmt)
    {
        if (_currentReturnType == null)
        {
            Error("Return statement outside of function", returnStmt.Line, returnStmt.Column);
            return;
        }

        if (returnStmt.Value != null)
        {
            var returnedType = AnalyzeExpression(returnStmt.Value);
            if (!IsAssignable(_currentReturnType, returnedType))
            {
                Error($"Cannot return '{returnedType}' from function returning '{_currentReturnType}'",
                    returnStmt.Line, returnStmt.Column);
            }
        }
        else
        {
            if (_currentReturnType != BuiltInTypes.Void)
            {
                Error($"Function must return a value of type '{_currentReturnType}'", returnStmt.Line, returnStmt.Column);
            }
        }
    }

    private void AnalyzeTryStatement(TryStatement tryStmt)
    {
        AnalyzeStatement(tryStmt.TryBlock);

        foreach (var catchClause in tryStmt.CatchClauses)
        {
            PushScope(new Scope(ScopeKind.Block));

            if (catchClause.VariableName != null)
            {
                var exceptionType = catchClause.ExceptionType != null
                    ? ResolveType(catchClause.ExceptionType)
                    : new SimpleTypeInfo("Exception");
                DeclareSymbol(catchClause.VariableName, exceptionType, tryStmt.Line, tryStmt.Column);
            }

            AnalyzeStatement(catchClause.Block);
            PopScope();
        }

        if (tryStmt.FinallyBlock != null)
        {
            AnalyzeStatement(tryStmt.FinallyBlock);
        }
    }

    private void AnalyzeUsingStatement(UsingStatement usingStmt)
    {
        PushScope(new Scope(ScopeKind.Block));

        if (usingStmt.Declaration != null)
        {
            AnalyzeVariableDeclaration(usingStmt.Declaration);
            // TODO: Check if type implements IDisposable
        }
        else if (usingStmt.Expression != null)
        {
            AnalyzeExpression(usingStmt.Expression);
            // TODO: Check if type implements IDisposable
        }

        if (usingStmt.Body != null)
        {
            AnalyzeStatement(usingStmt.Body);
        }

        PopScope();
    }

    private void AnalyzeSwitchStatement(SwitchStatement switchStmt)
    {
        var valueType = AnalyzeExpression(switchStmt.Value);

        foreach (var switchCase in switchStmt.Cases)
        {
            PushScope(new Scope(ScopeKind.Block));

            // Analyze pattern if present
            if (switchCase.Pattern != null)
            {
                AnalyzePattern(switchCase.Pattern, valueType);
            }

            foreach (var stmt in switchCase.Statements)
            {
                AnalyzeStatement(stmt);
            }

            PopScope();
        }
    }

    private void AnalyzePattern(Pattern pattern, TypeInfo valueType)
    {
        // Simplified pattern analysis
        // TODO: More sophisticated pattern matching
    }

    private TypeInfo AnalyzeExpression(Expression expr)
    {
        return expr switch
        {
            IntLiteralExpression => BuiltInTypes.Int,
            FloatLiteralExpression => BuiltInTypes.Double,
            StringLiteralExpression => BuiltInTypes.String,
            BoolLiteralExpression => BuiltInTypes.Bool,
            NullLiteralExpression => BuiltInTypes.Null,
            IdentifierExpression ident => ResolveIdentifier(ident.Name, ident.Line, ident.Column),
            BinaryExpression binary => AnalyzeBinaryExpression(binary),
            UnaryExpression unary => AnalyzeUnaryExpression(unary),
            MemberAccessExpression member => AnalyzeMemberAccess(member),
            CallExpression call => AnalyzeCall(call),
            AssignmentExpression assignment => AnalyzeAssignment(assignment),
            LambdaExpression lambda => AnalyzeLambda(lambda),
            TernaryExpression ternary => AnalyzeTernary(ternary),
            ArrayLiteralExpression array => AnalyzeArrayLiteral(array),
            NewExpression newExpr => AnalyzeNewExpression(newExpr),
            CastExpression cast => ResolveType(cast.TargetType),
            IsExpression isExpr => BuiltInTypes.Bool,
            AwaitExpression await => AnalyzeAwaitExpression(await),
            ThrowExpression => BuiltInTypes.Never,
            ThisExpression => GetCurrentTypeScope() ?? BuiltInTypes.Unknown,
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeBinaryExpression(BinaryExpression binary)
    {
        var leftType = AnalyzeExpression(binary.Left);
        var rightType = AnalyzeExpression(binary.Right);

        return binary.Operator switch
        {
            BinaryOperator.Add or BinaryOperator.Subtract or BinaryOperator.Multiply
                or BinaryOperator.Divide or BinaryOperator.Modulo => AnalyzeArithmeticOp(leftType, rightType, binary),
            BinaryOperator.Equal or BinaryOperator.NotEqual or BinaryOperator.Less
                or BinaryOperator.LessOrEqual or BinaryOperator.Greater or BinaryOperator.GreaterOrEqual => BuiltInTypes.Bool,
            BinaryOperator.And or BinaryOperator.Or => AnalyzeLogicalOp(leftType, rightType, binary),
            BinaryOperator.NullCoalesce => leftType, // Simplified
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeArithmeticOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        // Special case: string concatenation
        if (expr.Operator == BinaryOperator.Add && (IsStringType(left) || IsStringType(right)))
        {
            return BuiltInTypes.String;
        }

        // If either operand is Unknown, we can't check but assume it's okay
        if (left == BuiltInTypes.Unknown || right == BuiltInTypes.Unknown)
        {
            return BuiltInTypes.Unknown;
        }

        if (!IsNumericType(left) || !IsNumericType(right))
        {
            Error($"Operator '{expr.Operator}' cannot be applied to '{left}' and '{right}'",
                expr.Line, expr.Column);
            return BuiltInTypes.Unknown;
        }

        // Return wider type
        return GetWiderType(left, right);
    }

    private TypeInfo AnalyzeLogicalOp(TypeInfo left, TypeInfo right, BinaryExpression expr)
    {
        if (!IsBoolType(left) || !IsBoolType(right))
        {
            Error($"Logical operator '{expr.Operator}' requires boolean operands", expr.Line, expr.Column);
        }
        return BuiltInTypes.Bool;
    }

    private TypeInfo AnalyzeUnaryExpression(UnaryExpression unary)
    {
        var operandType = AnalyzeExpression(unary.Operand);

        return unary.Operator switch
        {
            UnaryOperator.Negate => operandType,
            UnaryOperator.Not => BuiltInTypes.Bool,
            UnaryOperator.PreIncrement or UnaryOperator.PreDecrement
                or UnaryOperator.PostIncrement or UnaryOperator.PostDecrement => operandType,
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeMemberAccess(MemberAccessExpression member)
    {
        var objectType = AnalyzeExpression(member.Object);

        // Resolve member on type
        return ResolveMember(objectType, member.MemberName);
    }

    private TypeInfo ResolveMember(TypeInfo objectType, string memberName)
    {
        // Handle reflection-based types
        if (objectType is ReflectionTypeInfo reflectionType)
        {
            var type = reflectionType.Type;

            // Try property
            var property = type.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
            if (property != null)
                return ConvertReflectionType(property.PropertyType);

            // Try field
            var field = type.GetField(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
            if (field != null)
                return ConvertReflectionType(field.FieldType);

            // Try methods (get all matching methods to handle overloads)
            var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                .Where(m => m.Name == memberName)
                .ToArray();

            if (methods.Length > 0)
            {
                // Return a special type that represents overloaded methods
                return new ReflectionMethodGroupInfo(methods);
            }

            // Also check extension methods (simplified - just return Unknown for now)
            return BuiltInTypes.Unknown;
        }

        // Handle declared types
        if (objectType is ClassTypeInfo classType)
        {
            var member = classType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return ResolveType(field.Type);
            if (member is FunctionDeclaration func)
                return new FunctionTypeInfo(func);
        }

        if (objectType is StructTypeInfo structType)
        {
            var member = structType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return ResolveType(field.Type);
            if (member is FunctionDeclaration func)
                return new FunctionTypeInfo(func);
        }

        if (objectType is RecordTypeInfo recordType)
        {
            var member = recordType.Declaration.Members.FirstOrDefault(m =>
                (m is FieldDeclaration fd && fd.Name == memberName) ||
                (m is FunctionDeclaration func && func.Name == memberName));

            if (member is FieldDeclaration field)
                return ResolveType(field.Type);
            if (member is FunctionDeclaration func)
                return new FunctionTypeInfo(func);
        }

        // Handle array types
        if (objectType is ArrayTypeInfo arrayType)
        {
            if (memberName == "Length")
                return BuiltInTypes.Int;
        }

        return BuiltInTypes.Unknown;
    }

    private TypeInfo ConvertReflectionType(Type type)
    {
        // Handle primitive types
        if (type == typeof(int)) return BuiltInTypes.Int;
        if (type == typeof(long)) return BuiltInTypes.Long;
        if (type == typeof(float)) return BuiltInTypes.Float;
        if (type == typeof(double)) return BuiltInTypes.Double;
        if (type == typeof(bool)) return BuiltInTypes.Bool;
        if (type == typeof(string)) return BuiltInTypes.String;
        if (type == typeof(void)) return BuiltInTypes.Void;
        if (type == typeof(object)) return BuiltInTypes.Object;

        // Handle arrays
        if (type.IsArray)
        {
            var elementType = ConvertReflectionType(type.GetElementType()!);
            return new ArrayTypeInfo(elementType);
        }

        // Handle generics
        if (type.IsGenericType)
        {
            var genericArgs = type.GetGenericArguments().Select(ConvertReflectionType).ToList();
            var genericName = type.Name.Substring(0, type.Name.IndexOf('`'));
            return new GenericTypeInfo(genericName, genericArgs);
        }

        // Default to reflection type
        return new ReflectionTypeInfo(type);
    }

    private TypeInfo AnalyzeCall(CallExpression call)
    {
        var calleeType = AnalyzeExpression(call.Callee);

        // Analyze arguments
        var argTypes = new List<TypeInfo>();
        foreach (var arg in call.Arguments)
        {
            argTypes.Add(AnalyzeExpression(arg.Value));
        }

        // Resolve return type from function type
        if (calleeType is FunctionTypeInfo funcType)
        {
            // If we have the function declaration, get its return type
            if (funcType.Declaration != null && funcType.Declaration.ReturnType != null)
            {
                return ResolveType(funcType.Declaration.ReturnType);
            }
            return funcType.ReturnType ?? BuiltInTypes.Void;
        }

        // Handle reflection method calls
        if (calleeType is ReflectionMethodInfo methodInfo)
        {
            return ConvertReflectionType(methodInfo.Method.ReturnType);
        }

        // Handle method group (overloaded methods)
        if (calleeType is ReflectionMethodGroupInfo methodGroup)
        {
            // Try to resolve overload based on argument count
            // For now, just pick the first compatible method
            var compatibleMethods = methodGroup.Methods
                .Where(m => m.GetParameters().Length == argTypes.Count)
                .ToArray();

            if (compatibleMethods.Length > 0)
            {
                return ConvertReflectionType(compatibleMethods[0].ReturnType);
            }

            // If no exact match, just return the first method's return type
            if (methodGroup.Methods.Length > 0)
            {
                return ConvertReflectionType(methodGroup.Methods[0].ReturnType);
            }
        }

        return BuiltInTypes.Unknown;
    }

    private TypeInfo AnalyzeAssignment(AssignmentExpression assignment)
    {
        var targetType = AnalyzeExpression(assignment.Target);
        var valueType = AnalyzeExpression(assignment.Value);

        if (!IsAssignable(targetType, valueType))
        {
            Error($"Cannot assign '{valueType}' to '{targetType}'", assignment.Line, assignment.Column);
        }

        return targetType;
    }

    private TypeInfo AnalyzeLambda(LambdaExpression lambda)
    {
        PushScope(new Scope(ScopeKind.Function));

        foreach (var param in lambda.Parameters)
        {
            // If the parameter has an explicit type, use it
            // Otherwise, use Unknown for now (will be inferred from context in full implementation)
            var paramType = param.Type != null ? ResolveType(param.Type) : BuiltInTypes.Unknown;
            DeclareSymbol(param.Name, paramType, lambda.Line, lambda.Column);
        }

        TypeInfo returnType;
        if (lambda.ExpressionBody != null)
        {
            returnType = AnalyzeExpression(lambda.ExpressionBody);
        }
        else if (lambda.BlockBody != null)
        {
            AnalyzeStatement(lambda.BlockBody);
            returnType = BuiltInTypes.Void; // TODO: Infer from return statements
        }
        else
        {
            returnType = BuiltInTypes.Unknown;
        }

        PopScope();

        return new FunctionTypeInfo(null) { ReturnType = returnType };
    }

    private TypeInfo AnalyzeTernary(TernaryExpression ternary)
    {
        var condType = AnalyzeExpression(ternary.Condition);
        if (!IsBoolType(condType))
        {
            Error("Ternary condition must be boolean", ternary.Line, ternary.Column);
        }

        var thenType = AnalyzeExpression(ternary.ThenExpression);
        var elseType = AnalyzeExpression(ternary.ElseExpression);

        // Return common type
        return GetCommonType(thenType, elseType);
    }

    private TypeInfo AnalyzeArrayLiteral(ArrayLiteralExpression array)
    {
        if (array.Elements.Count == 0)
        {
            return new ArrayTypeInfo(BuiltInTypes.Unknown);
        }

        var firstType = AnalyzeExpression(array.Elements[0]);
        foreach (var elem in array.Elements.Skip(1))
        {
            var elemType = AnalyzeExpression(elem);
            if (!IsAssignable(firstType, elemType))
            {
                Error($"Array element type mismatch", array.Line, array.Column);
            }
        }

        return new ArrayTypeInfo(firstType);
    }

    private TypeInfo AnalyzeNewExpression(NewExpression newExpr)
    {
        var type = ResolveType(newExpr.Type);

        // Analyze constructor arguments
        foreach (var arg in newExpr.ConstructorArguments)
        {
            AnalyzeExpression(arg.Value);
        }

        // Analyze initializer
        if (newExpr.Initializer != null)
        {
            foreach (var prop in newExpr.Initializer.Properties)
            {
                AnalyzeExpression(prop.Value);
            }
        }

        return type;
    }

    private TypeInfo AnalyzeAwaitExpression(AwaitExpression await)
    {
        var exprType = AnalyzeExpression(await.Expression);
        // TODO: Unwrap Task<T> to get T
        return BuiltInTypes.Unknown;
    }

    // Type resolution
    private TypeInfo ResolveType(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference simple => ResolveSimpleType(simple.Name),
            GenericTypeReference generic => new GenericTypeInfo(generic.Name,
                generic.TypeArguments.Select(ResolveType).ToList()),
            ArrayTypeReference array => new ArrayTypeInfo(ResolveType(array.ElementType)),
            NullableTypeReference nullable => new NullableTypeInfo(ResolveType(nullable.InnerType)),
            TupleTypeReference tuple => new TupleTypeInfo(
                tuple.Elements.Select(e => (e.Name, ResolveType(e.Type))).ToList()),
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo ResolveSimpleType(string name)
    {
        // Check built-in types
        var builtInType = name switch
        {
            "int" => BuiltInTypes.Int,
            "long" => BuiltInTypes.Long,
            "float" => BuiltInTypes.Float,
            "double" => BuiltInTypes.Double,
            "bool" => BuiltInTypes.Bool,
            "string" => BuiltInTypes.String,
            "void" => BuiltInTypes.Void,
            "object" => BuiltInTypes.Object,
            "var" => BuiltInTypes.Unknown, // Treat 'var' as unknown for type inference
            _ => null
        };

        if (builtInType != null)
            return builtInType;

        // Check local type declarations
        var localType = LookupType(name);
        if (localType != null)
            return localType;

        // Check using aliases
        if (_usingAliases.TryGetValue(name, out var fullName))
        {
            var aliasedType = TryResolveExternalType(fullName);
            if (aliasedType != null)
                return aliasedType;
        }

        // Try to resolve as external type
        var externalType = TryResolveExternalType(name);
        if (externalType != null)
            return externalType;

        // Return unknown type (not an error - might be from C# library)
        return new ExternalTypeInfo(name);
    }

    private TypeInfo? TryResolveExternalType(string name)
    {
        // Try direct type lookup in common assemblies
        var type = Type.GetType(name);
        if (type != null)
            return new ReflectionTypeInfo(type);

        // Try with using namespaces
        foreach (var ns in _usingNamespaces)
        {
            var fullName = $"{ns}.{name}";

            // Try core library
            type = Type.GetType($"{fullName}, System.Runtime");
            if (type != null)
                return new ReflectionTypeInfo(type);

            // Try System.Private.CoreLib
            type = Type.GetType($"{fullName}, System.Private.CoreLib");
            if (type != null)
                return new ReflectionTypeInfo(type);

            // Try without assembly qualification
            type = Type.GetType(fullName);
            if (type != null)
                return new ReflectionTypeInfo(type);

            // Try common assemblies
            var assemblies = new[]
            {
                Assembly.Load("System.Runtime"),
                Assembly.Load("System.Console"),
                Assembly.Load("System.Linq"),
                typeof(object).Assembly // mscorlib/System.Private.CoreLib
            };

            foreach (var assembly in assemblies)
            {
                type = assembly.GetType(fullName);
                if (type != null)
                    return new ReflectionTypeInfo(type);
            }
        }

        return null;
    }

    private TypeInfo? LookupType(string name)
    {
        foreach (var scope in _scopes)
        {
            if (scope.Types.TryGetValue(name, out var type))
                return type;
        }
        return null;
    }

    private TypeInfo ResolveIdentifier(string name, int line, int column)
    {
        // Check local symbols first
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.TryGetValue(name, out var type))
                return type;
        }

        // Try to resolve as external type (for static class access like Console)
        var externalType = TryResolveExternalType(name);
        if (externalType != null)
            return externalType;

        // Check if it's a type name
        var typeInfo = LookupType(name);
        if (typeInfo != null)
            return typeInfo;

        Error($"Undefined identifier '{name}'", line, column);
        return BuiltInTypes.Unknown;
    }

    private TypeInfo? GetCurrentTypeScope()
    {
        foreach (var scope in _scopes)
        {
            if (scope.Symbols.TryGetValue("this", out var type))
                return type;
        }
        return null;
    }

    // Convention-based visibility checking
    private void CheckVisibilityConvention(string name, Modifiers modifiers, int line, int column)
    {
        bool isPascalCase = char.IsUpper(name[0]);
        bool isCamelCase = char.IsLower(name[0]);

        bool hasExplicitVisibility = modifiers.HasFlag(Modifiers.Public)
            || modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Internal)
            || modifiers.HasFlag(Modifiers.Protected);

        // If explicit modifiers are present, don't check convention
        if (hasExplicitVisibility)
            return;

        // Check convention: PascalCase = public, camelCase = private
        if (isPascalCase)
        {
            // Should be public (convention)
        }
        else if (isCamelCase)
        {
            // Should be private (convention)
        }
        else
        {
            Warning($"Identifier '{name}' doesn't follow naming convention (PascalCase for public, camelCase for private)",
                line, column);
        }
    }

    // Type checking helpers
    private bool IsAssignable(TypeInfo target, TypeInfo source)
    {
        if (target == source) return true;
        if (source == BuiltInTypes.Null && target is NullableTypeInfo) return true;
        if (source == BuiltInTypes.Never) return true;
        if (source == BuiltInTypes.Unknown || target == BuiltInTypes.Unknown) return true;

        // Handle external types (assume compatible if we can't resolve)
        if (source is ExternalTypeInfo || target is ExternalTypeInfo) return true;
        if (source is ReflectionTypeInfo || target is ReflectionTypeInfo) return true;
        if (source is ReflectionMethodInfo || target is ReflectionMethodInfo) return true;
        if (source is ReflectionMethodGroupInfo || target is ReflectionMethodGroupInfo) return true;

        // Same type name
        if (target.ToString() == source.ToString()) return true;

        // TODO: More sophisticated type compatibility checking
        return false;
    }

    private bool IsNumericType(TypeInfo type)
    {
        return type == BuiltInTypes.Int || type == BuiltInTypes.Long
            || type == BuiltInTypes.Float || type == BuiltInTypes.Double;
    }

    private bool IsBoolType(TypeInfo type)
    {
        return type == BuiltInTypes.Bool;
    }

    private bool IsStringType(TypeInfo type)
    {
        return type == BuiltInTypes.String;
    }

    private bool IsNullableType(TypeInfo type)
    {
        return type is NullableTypeInfo;
    }

    private TypeInfo GetWiderType(TypeInfo left, TypeInfo right)
    {
        if (left == BuiltInTypes.Double || right == BuiltInTypes.Double) return BuiltInTypes.Double;
        if (left == BuiltInTypes.Float || right == BuiltInTypes.Float) return BuiltInTypes.Float;
        if (left == BuiltInTypes.Long || right == BuiltInTypes.Long) return BuiltInTypes.Long;
        return BuiltInTypes.Int;
    }

    private TypeInfo GetCommonType(TypeInfo left, TypeInfo right)
    {
        if (left == right) return left;
        if (IsNumericType(left) && IsNumericType(right)) return GetWiderType(left, right);
        return BuiltInTypes.Unknown;
    }

    // Scope management
    private void PushScope(Scope scope)
    {
        _scopes.Push(scope);
    }

    private void PopScope()
    {
        _scopes.Pop();
    }

    private void DeclareSymbol(string name, TypeInfo type, int line, int column)
    {
        var currentScope = _scopes.Peek();
        if (currentScope.Symbols.ContainsKey(name))
        {
            Error($"Symbol '{name}' is already declared in this scope", line, column);
        }
        else
        {
            currentScope.Symbols[name] = type;
        }
    }

    private void DeclareType(string name, TypeInfo type, int line, int column)
    {
        var currentScope = _scopes.Peek();
        if (currentScope.Types.ContainsKey(name))
        {
            Error($"Type '{name}' is already declared", line, column);
        }
        else
        {
            currentScope.Types[name] = type;
        }
    }

    // Error reporting
    private void Error(string message, int line, int column)
    {
        _errors.Add(new CompilerError(message, line, column, ErrorSeverity.Error));
    }

    private void Warning(string message, int line, int column)
    {
        _errors.Add(new CompilerError(message, line, column, ErrorSeverity.Warning));
    }
}

// Supporting types
public record CompilerError(string Message, int Line, int Column, ErrorSeverity Severity);

public enum ErrorSeverity
{
    Warning,
    Error
}

public record AnalysisResult(List<CompilerError> Errors)
{
    public bool HasErrors => Errors.Any(e => e.Severity == ErrorSeverity.Error);
}

public class Scope
{
    public ScopeKind Kind { get; }
    public Dictionary<string, TypeInfo> Symbols { get; } = new();
    public Dictionary<string, TypeInfo> Types { get; } = new();

    public Scope(ScopeKind kind)
    {
        Kind = kind;
    }
}

public enum ScopeKind
{
    Global,
    Class,
    Struct,
    Record,
    Interface,
    Function,
    Block
}

// Type system
public abstract record TypeInfo
{
    public override string ToString() => GetType().Name;
}

public record SimpleTypeInfo(string Name) : TypeInfo
{
    public override string ToString() => Name;
}

public record GenericTypeInfo(string Name, List<TypeInfo> TypeArguments) : TypeInfo
{
    public override string ToString() => $"{Name}<{string.Join(", ", TypeArguments)}>";
}

public record ArrayTypeInfo(TypeInfo ElementType) : TypeInfo
{
    public override string ToString() => $"{ElementType}[]";
}

public record NullableTypeInfo(TypeInfo InnerType) : TypeInfo
{
    public override string ToString() => $"{InnerType}?";
}

public record TupleTypeInfo(List<(string? Name, TypeInfo Type)> Elements) : TypeInfo;

public record FunctionTypeInfo(FunctionDeclaration? Declaration) : TypeInfo
{
    public TypeInfo? ReturnType { get; set; }
}

public record ClassTypeInfo(ClassDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record StructTypeInfo(StructDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record RecordTypeInfo(RecordDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record InterfaceTypeInfo(InterfaceDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record UnionTypeInfo(UnionDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record EnumTypeInfo(EnumDeclaration Declaration) : TypeInfo
{
    public override string ToString() => Declaration.Name;
}

public record AliasTypeInfo(TypeReference AliasedType) : TypeInfo;

/// <summary>
/// Represents a type resolved via .NET reflection (external types like System.Console)
/// </summary>
public record ReflectionTypeInfo(Type Type) : TypeInfo
{
    public override string ToString() => Type.Name;
}

/// <summary>
/// Represents a method resolved via .NET reflection
/// </summary>
public record ReflectionMethodInfo(MethodInfo Method) : TypeInfo
{
    public override string ToString() => $"{Method.Name}(...)";
}

/// <summary>
/// Represents a group of overloaded methods resolved via .NET reflection
/// </summary>
public record ReflectionMethodGroupInfo(MethodInfo[] Methods) : TypeInfo
{
    public override string ToString() => Methods.Length > 0 ? $"{Methods[0].Name}(...)" : "method group";
}

/// <summary>
/// Represents an external type that couldn't be fully resolved
/// </summary>
public record ExternalTypeInfo(string Name) : TypeInfo
{
    public override string ToString() => Name;
}

public static class BuiltInTypes
{
    public static readonly SimpleTypeInfo Int = new("int");
    public static readonly SimpleTypeInfo Long = new("long");
    public static readonly SimpleTypeInfo Float = new("float");
    public static readonly SimpleTypeInfo Double = new("double");
    public static readonly SimpleTypeInfo Bool = new("bool");
    public static readonly SimpleTypeInfo String = new("string");
    public static readonly SimpleTypeInfo Void = new("void");
    public static readonly SimpleTypeInfo Object = new("object");
    public static readonly SimpleTypeInfo Null = new("null");
    public static readonly SimpleTypeInfo Never = new("never");
    public static readonly SimpleTypeInfo Unknown = new("unknown");
}
