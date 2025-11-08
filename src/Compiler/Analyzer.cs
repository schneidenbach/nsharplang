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
    private bool _inConstructor;
    private ClassDeclaration? _currentClass;

    public AnalysisResult Analyze(CompilationUnit unit)
    {
        _errors.Clear();
        _scopes.Clear();
        _usingNamespaces.Clear();
        _usingAliases.Clear();
        _currentReturnType = null;
        _inLoop = false;
        _inConstructor = false;

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
        else if (func.ExpressionBody != null)
        {
            // Expression-bodied method: check expression type matches return type
            var exprType = AnalyzeExpression(func.ExpressionBody);
            if (_currentReturnType != BuiltInTypes.Void && !IsAssignable(_currentReturnType, exprType))
            {
                Error($"Expression body type '{exprType}' does not match return type '{_currentReturnType}'", func.Line, func.Column);
            }
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

        var propType = ResolveType(prop.Type!);
        DeclareSymbol(prop.Name, propType, prop.Line, prop.Column);

        // Expression-bodied property: validate expression type matches property type
        if (prop.ExpressionBody != null)
        {
            var exprType = AnalyzeExpression(prop.ExpressionBody);
            if (!IsAssignable(propType, exprType))
            {
                Error($"Cannot assign '{exprType}' to '{propType}' in expression-bodied property", prop.Line, prop.Column);
            }
        }

        // Analyze getter
        if (prop.GetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            var prevReturnType = _currentReturnType;
            _currentReturnType = propType; // Getter should return the property type
            AnalyzeStatement(prop.GetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }

        // Analyze setter
        if (prop.SetBody != null)
        {
            PushScope(new Scope(ScopeKind.Function));
            var prevReturnType = _currentReturnType;
            _currentReturnType = BuiltInTypes.Void; // Setter returns void
            // Implicitly declare 'value' parameter
            DeclareSymbol("value", propType, prop.Line, prop.Column);
            AnalyzeStatement(prop.SetBody);
            _currentReturnType = prevReturnType;
            PopScope();
        }
    }

    private void AnalyzeConstructorDeclaration(ConstructorDeclaration ctor)
    {
        _inConstructor = true;
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
        _inConstructor = false;
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
            case PrintStatement printStmt:
                AnalyzeExpression(printStmt.Value);
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
        // Check if this is error handling pattern: (result, err := Function())
        bool isErrorHandling = tupleDecl.Names.Count == 2 && tupleDecl.Names[1] == "err";

        if (isErrorHandling)
        {
            // Error handling pattern
            var resultVar = tupleDecl.Names[0];
            var errVar = tupleDecl.Names[1];

            // Analyze the initializer expression to ensure it's valid
            var initType = AnalyzeExpression(tupleDecl.Initializer);

            // Declare result variable with inferred type (or Unknown if can't infer)
            if (resultVar != "_")
            {
                DeclareSymbol(resultVar, initType, tupleDecl.Line, tupleDecl.Column);
            }

            // Declare err variable as nullable Exception
            if (errVar != "_")
            {
                var exceptionType = new ExternalTypeInfo("Exception?");
                DeclareSymbol(errVar, exceptionType, tupleDecl.Line, tupleDecl.Column);
            }
        }
        else
        {
            // Normal tuple deconstruction
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
        switch (pattern)
        {
            case IdentifierPattern identPattern:
                // Check if this is a qualified union case name (e.g., "Result.Success")
                if (valueType is UnionTypeInfo ut && identPattern.Name.Contains('.'))
                {
                    var caseName = identPattern.Name.Contains('.')
                        ? identPattern.Name.Substring(identPattern.Name.LastIndexOf('.') + 1)
                        : identPattern.Name;

                    var matchingCase = ut.Declaration.Cases
                        .FirstOrDefault(c => c.Name == caseName);

                    if (matchingCase == null)
                    {
                        Error($"Union type '{ut}' does not have a case '{identPattern.Name}'",
                            pattern.Line, pattern.Column);
                    }
                    // For union cases without properties, no variables to bind
                }
                else
                {
                    // Regular identifier pattern - bind the identifier to the value type
                    DeclareSymbol(identPattern.Name, valueType, identPattern.Line, identPattern.Column);
                }
                break;

            case LiteralPattern literalPattern:
                // Just analyze the literal expression for type checking
                AnalyzeExpression(literalPattern.Literal);
                break;

            case UnionCasePattern unionPattern:
                // Verify the union case exists if matching against a union type
                if (valueType is UnionTypeInfo unionType)
                {
                    // Extract just the case name (after the last dot if qualified)
                    var caseName = unionPattern.CaseName.Contains('.')
                        ? unionPattern.CaseName.Substring(unionPattern.CaseName.LastIndexOf('.') + 1)
                        : unionPattern.CaseName;

                    var matchingCase = unionType.Declaration.Cases
                        .FirstOrDefault(c => c.Name == caseName);

                    if (matchingCase == null)
                    {
                        Error($"Union type '{unionType}' does not have a case '{unionPattern.CaseName}'",
                            pattern.Line, pattern.Column);
                    }
                    else if (unionPattern.Properties != null)
                    {
                        // Bind property patterns to their types
                        if (matchingCase.Properties == null)
                        {
                            Error($"Union case '{caseName}' has no properties (Properties is null)",
                                pattern.Line, pattern.Column);
                        }
                        else if (matchingCase.Properties.Count == 0)
                        {
                            Error($"Union case '{caseName}' has no properties (Properties is empty)",
                                pattern.Line, pattern.Column);
                        }
                        else
                        {
                            foreach (var propPattern in unionPattern.Properties)
                            {
                                var caseProperty = matchingCase.Properties
                                    .FirstOrDefault(p => p.Name == propPattern.Name);

                                if (caseProperty != null)
                                {
                                    var propType = ResolveType(caseProperty.Type);
                                    var bindingName = propPattern.BindingName ?? propPattern.Name;
                                    DeclareSymbol(bindingName, propType, pattern.Line, pattern.Column);
                                }
                                else
                                {
                                    Error($"Union case '{caseName}' does not have property '{propPattern.Name}'",
                                        pattern.Line, pattern.Column);
                                }
                            }
                        }
                    }
                }
                break;
        }
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
            MatchExpression match => AnalyzeMatchExpression(match),
            TypeOfExpression typeofExpr => AnalyzeTypeofExpression(typeofExpr),
            NameofExpression nameofExpr => AnalyzeNameofExpression(nameofExpr),
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
            BinaryOperator.NullCoalesce => AnalyzeNullCoalesceOp(leftType, rightType, binary),
            _ => BuiltInTypes.Unknown
        };
    }

    private TypeInfo AnalyzeNullCoalesceOp(TypeInfo leftType, TypeInfo rightType, BinaryExpression expr)
    {
        // If right side is a throw expression, the result type is the left type
        // e.g., string? ?? throw => string (C# infers this correctly)
        if (expr.Right is ThrowExpression)
        {
            return leftType;
        }

        // Otherwise, the result is the right type (the fallback value)
        // In C#: T? ?? T returns T
        return rightType;
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
            // If we have the function declaration, check parameter types
            if (funcType.Declaration != null)
            {
                var parameters = funcType.Declaration.Parameters;

                // Check argument count
                if (argTypes.Count != parameters.Count)
                {
                    Error($"Function '{funcType.Declaration.Name}' expects {parameters.Count} arguments but got {argTypes.Count}",
                        call.Line, call.Column);
                }
                else
                {
                    // Check each parameter type
                    for (int i = 0; i < parameters.Count; i++)
                    {
                        var paramType = ResolveType(parameters[i].Type);
                        var argType = argTypes[i];

                        if (!IsAssignable(paramType, argType))
                        {
                            Error($"Argument {i + 1} of type '{argType}' is not assignable to parameter '{parameters[i].Name}' of type '{paramType}'",
                                call.Line, call.Column);
                        }
                    }
                }

                // Return the declared return type
                if (funcType.Declaration.ReturnType != null)
                {
                    return ResolveType(funcType.Declaration.ReturnType);
                }
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

        // Check for readonly field assignment outside constructor
        CheckReadonlyFieldAssignment(assignment.Target, assignment.Line, assignment.Column);

        if (!IsAssignable(targetType, valueType))
        {
            Error($"Cannot assign '{valueType}' to '{targetType}'", assignment.Line, assignment.Column);
        }

        return targetType;
    }

    private void CheckReadonlyFieldAssignment(Expression target, int line, int column)
    {
        // Only check if we're not in a constructor
        if (_inConstructor)
            return;

        // Check if target is a field access on 'this'
        string? fieldName = null;
        if (target is MemberAccessExpression { Object: ThisExpression } memberAccess)
        {
            fieldName = memberAccess.MemberName;
        }
        else if (target is IdentifierExpression ident)
        {
            // Direct field assignment (implicitly on 'this' in class context)
            fieldName = ident.Name;
        }

        if (fieldName != null && _currentClass != null)
        {
            // Check if this is a readonly field
            var field = _currentClass.Members.OfType<FieldDeclaration>()
                .FirstOrDefault(f => f.Name == fieldName);

            if (field != null && field.Modifiers.HasFlag(Modifiers.Readonly))
            {
                Error($"Cannot assign to readonly field '{fieldName}' outside of a constructor", line, column);
            }
        }
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

        // Special case: if the type is a qualified name like "Result.Success",
        // it might be a union case. Check if the base type is a union.
        if (newExpr.Type is SimpleTypeReference simpleRef && simpleRef.Name.Contains('.'))
        {
            var parts = simpleRef.Name.Split('.');
            if (parts.Length == 2)
            {
                var baseTypeName = parts[0];
                var baseType = LookupType(baseTypeName);
                if (baseType is UnionTypeInfo)
                {
                    // This is a union case instantiation - the variable should have the union type
                    type = baseType;
                }
            }
        }

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

    private TypeInfo AnalyzeTypeofExpression(TypeOfExpression typeofExpr)
    {
        // Validate the type exists
        ResolveType(typeofExpr.Type);
        // typeof always returns System.Type
        return new ReflectionTypeInfo(typeof(Type));
    }

    private TypeInfo AnalyzeNameofExpression(NameofExpression nameofExpr)
    {
        // Analyze the target expression to ensure it's valid
        AnalyzeExpression(nameofExpr.Target);
        // nameof always returns string
        return BuiltInTypes.String;
    }

    private TypeInfo AnalyzeMatchExpression(MatchExpression match)
    {
        // Analyze the value being matched
        var valueType = AnalyzeExpression(match.Value);

        // Analyze each case and track variable bindings
        TypeInfo? resultType = null;
        foreach (var matchCase in match.Cases)
        {
            // Create new scope for pattern bindings
            PushScope(new Scope(ScopeKind.Block));

            // Analyze pattern and bind variables
            AnalyzePattern(matchCase.Pattern, valueType);

            // Analyze guard expression if present
            if (matchCase.Guard != null)
            {
                var guardType = AnalyzeExpression(matchCase.Guard);
                if (!IsAssignable(BuiltInTypes.Bool, guardType))
                {
                    Error($"Guard expression must be of type 'bool', but got '{guardType}'",
                        matchCase.Guard.Line, matchCase.Guard.Column);
                }
            }

            // Analyze the case expression
            var caseType = AnalyzeExpression(matchCase.Expression);

            // Ensure all cases return compatible types
            if (resultType == null)
            {
                resultType = caseType;
            }
            else if (!IsAssignable(resultType, caseType) && !IsAssignable(caseType, resultType))
            {
                Error($"Match case has incompatible type '{caseType}', expected '{resultType}'",
                    matchCase.Expression.Line, matchCase.Expression.Column);
            }

            PopScope();
        }

        // Check exhaustiveness for union types (after analyzing patterns to report specific errors first)
        // Note: Skip exhaustiveness check if any guards are present, as guards can make patterns conditional
        if (valueType is UnionTypeInfo unionType && !match.Cases.Any(c => c.Guard != null))
        {
            CheckMatchExhaustiveness(match, unionType);
        }

        return resultType ?? BuiltInTypes.Unknown;
    }

    private void CheckMatchExhaustiveness(MatchExpression match, UnionTypeInfo unionType)
    {
        // Collect all union case names that are covered in the match
        var coveredCases = new HashSet<string>();

        foreach (var matchCase in match.Cases)
        {
            if (matchCase.Pattern is UnionCasePattern unionPattern)
            {
                // Extract just the case name (after the last dot if qualified)
                var caseName = unionPattern.CaseName.Contains('.')
                    ? unionPattern.CaseName.Substring(unionPattern.CaseName.LastIndexOf('.') + 1)
                    : unionPattern.CaseName;
                coveredCases.Add(caseName);
            }
            else if (matchCase.Pattern is IdentifierPattern identPattern)
            {
                if (identPattern.Name == "_")
                {
                    // Wildcard pattern covers all remaining cases
                    return;
                }
                else if (identPattern.Name.Contains('.'))
                {
                    // Qualified union case name without properties
                    var caseName = identPattern.Name.Substring(identPattern.Name.LastIndexOf('.') + 1);
                    coveredCases.Add(caseName);
                }
            }
        }

        // Check if all union cases are covered
        var allCases = unionType.Declaration.Cases.Select(c => c.Name).ToHashSet();
        var missingCases = allCases.Except(coveredCases).ToList();

        if (missingCases.Any())
        {
            Error($"Match expression is not exhaustive. Missing cases: {string.Join(", ", missingCases)}",
                match.Line, match.Column);
        }
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
        // Resolve type aliases
        var resolvedTarget = ResolveTypeAlias(target);
        var resolvedSource = ResolveTypeAlias(source);

        if (resolvedTarget == resolvedSource) return true;
        if (resolvedSource == BuiltInTypes.Null && resolvedTarget is NullableTypeInfo) return true;
        if (resolvedSource == BuiltInTypes.Never) return true;
        if (resolvedSource == BuiltInTypes.Unknown || resolvedTarget == BuiltInTypes.Unknown) return true;

        // Handle external types (assume compatible if we can't resolve)
        if (resolvedSource is ExternalTypeInfo || resolvedTarget is ExternalTypeInfo) return true;
        if (resolvedSource is ReflectionTypeInfo || resolvedTarget is ReflectionTypeInfo) return true;
        if (resolvedSource is ReflectionMethodInfo || resolvedTarget is ReflectionMethodInfo) return true;
        if (resolvedSource is ReflectionMethodGroupInfo || resolvedTarget is ReflectionMethodGroupInfo) return true;

        // Same type name
        if (resolvedTarget.ToString() == resolvedSource.ToString()) return true;

        // Duck interface structural typing
        if (resolvedTarget is InterfaceTypeInfo iface && iface.Declaration.IsDuckInterface)
        {
            return ImplementsDuckInterface(resolvedSource, iface);
        }

        // TODO: More sophisticated type compatibility checking
        return false;
    }

    private TypeInfo ResolveTypeAlias(TypeInfo type)
    {
        if (type is AliasTypeInfo alias)
        {
            // Resolve the aliased type reference to a TypeInfo
            var resolved = ResolveType(alias.AliasedType);
            // Recursively resolve in case of nested aliases
            return ResolveTypeAlias(resolved);
        }
        return type;
    }

    private bool ImplementsDuckInterface(TypeInfo source, InterfaceTypeInfo duckInterface)
    {
        // Get the source type's members
        List<Declaration>? sourceMembers = null;

        if (source is ClassTypeInfo classType)
            sourceMembers = classType.Declaration.Members;
        else if (source is StructTypeInfo structType)
            sourceMembers = structType.Declaration.Members;
        else if (source is RecordTypeInfo recordType)
            sourceMembers = recordType.Declaration.Members;
        else
            return false; // Can't check structural compatibility for other types

        // For each method in the duck interface, check if source has a matching method
        foreach (var interfaceMember in duckInterface.Declaration.Members)
        {
            if (interfaceMember is not FunctionDeclaration interfaceMethod)
                continue; // Skip non-method members

            // Look for a matching method in the source type
            var found = false;
            foreach (var sourceMember in sourceMembers)
            {
                if (sourceMember is not FunctionDeclaration sourceMethod)
                    continue;

                // Check if method signatures match
                if (MethodSignaturesMatch(sourceMethod, interfaceMethod))
                {
                    found = true;
                    break;
                }
            }

            if (!found)
                return false; // Source doesn't implement this interface method
        }

        return true; // Source implements all interface methods
    }

    private bool MethodSignaturesMatch(FunctionDeclaration method1, FunctionDeclaration method2)
    {
        // Must have same name
        if (method1.Name != method2.Name)
            return false;

        // Must have same number of parameters
        if (method1.Parameters.Count != method2.Parameters.Count)
            return false;

        // Check parameter types match
        for (int i = 0; i < method1.Parameters.Count; i++)
        {
            var type1 = ResolveType(method1.Parameters[i].Type);
            var type2 = ResolveType(method2.Parameters[i].Type);

            // Simple type name comparison (could be more sophisticated)
            if (type1.ToString() != type2.ToString())
                return false;
        }

        // Check return types match
        var returnType1 = method1.ReturnType != null ? ResolveType(method1.ReturnType) : BuiltInTypes.Void;
        var returnType2 = method2.ReturnType != null ? ResolveType(method2.ReturnType) : BuiltInTypes.Void;

        if (returnType1.ToString() != returnType2.ToString())
            return false;

        return true;
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
