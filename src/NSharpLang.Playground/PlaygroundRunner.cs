using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Playground;

internal sealed class PlaygroundRunner
{
    private readonly List<CompilationUnit> _units;
    private readonly Dictionary<string, FunctionDeclaration> _functions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Declaration> _types = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string?> _typeNamespaces = new(StringComparer.Ordinal);
    private readonly StringBuilder _stdout = new();
    private int _steps;
    private int _outputLines;

    public PlaygroundRunner(IEnumerable<CompilationUnit> units)
    {
        _units = units.ToList();
        foreach (var unit in _units)
        {
            foreach (var declaration in unit.Declarations)
            {
                switch (declaration)
                {
                    case FunctionDeclaration function:
                        _functions[function.Name] = function;
                        break;
                    case ClassDeclaration or StructDeclaration or RecordDeclaration or InterfaceDeclaration or UnionDeclaration or EnumDeclaration:
                        if (GetDeclarationName(declaration) is { } name)
                        {
                            _types[name] = declaration;
                            _typeNamespaces[name] = NSharpLang.Compiler.AnalyzerDeclarationFileFacts.GetUnitNamespace(unit);
                        }
                        break;
                }
            }
        }
    }

    public PlaygroundRunResult Run()
    {
        var entryPoint = _functions.Values.FirstOrDefault(function =>
            PlaygroundRunFacts.IsEntryPointFunctionName(function.Name));
        if (entryPoint == null)
        {
            throw Unsupported(PlaygroundRunFacts.NoEntryPoint());
        }

        try
        {
            _ = InvokeFunction(entryPoint, Array.Empty<object?>(), receiver: null, depth: 0);
            return new PlaygroundRunResult(_stdout.ToString(), null, 0);
        }
        catch (PlaygroundThrownException ex)
        {
            return new PlaygroundRunResult(_stdout.ToString(), FormatValue(ex.Value), 1);
        }
    }

    private object? InvokeFunction(FunctionDeclaration function, IReadOnlyList<object?> arguments, RuntimeObject? receiver, int depth)
    {
        if (depth > PlaygroundRunFacts.MaxCallDepth())
        {
            throw Unsupported(PlaygroundRunFacts.CallDepthExceeded());
        }

        if (function.Parameters.Count != arguments.Count)
        {
            throw Unsupported(PlaygroundRunFacts.WrongArgumentCount(function.Name, arguments.Count));
        }

        var environment = new RuntimeEnvironment(receiver?.Environment);
        if (receiver != null)
        {
            environment.Declare(PlaygroundRunFacts.ReceiverBindingName(), receiver);
        }

        for (var i = 0; i < function.Parameters.Count; i++)
        {
            environment.Declare(function.Parameters[i].Name, arguments[i]);
        }

        try
        {
            if (function.ExpressionBody != null)
            {
                return Evaluate(function.ExpressionBody, environment, depth + 1);
            }

            if (function.Body != null)
            {
                ExecuteBlock(function.Body, environment, depth + 1);
            }
        }
        catch (ReturnSignal signal)
        {
            return signal.Value;
        }

        return null;
    }

    private void ExecuteBlock(BlockStatement block, RuntimeEnvironment environment, int depth)
    {
        foreach (var statement in block.Statements)
        {
            ExecuteStatement(statement, environment, depth);
        }
    }

    private void ExecuteStatement(Statement statement, RuntimeEnvironment environment, int depth)
    {
        Step(statement);
        switch (statement)
        {
            case BlockStatement block:
                ExecuteBlock(block, new RuntimeEnvironment(environment), depth + 1);
                break;
            case VariableDeclarationStatement variable:
                environment.Declare(variable.Name, variable.Initializer == null ? null : Evaluate(variable.Initializer, environment, depth));
                break;
            case TupleDeconstructionStatement tuple:
                ExecuteTupleDeconstruction(tuple, environment, depth);
                break;
            case ExpressionStatement expression:
                _ = Evaluate(expression.Expression, environment, depth);
                break;
            case PrintStatement print:
                WriteLine(FormatValue(Evaluate(print.Value, environment, depth)));
                break;
            case ReturnStatement ret:
                throw new ReturnSignal(ret.Value == null ? null : Evaluate(ret.Value, environment, depth));
            case IfStatement ifStatement:
                if (IsTruthy(Evaluate(ifStatement.Condition, environment, depth)))
                {
                    ExecuteStatement(ifStatement.ThenStatement, environment, depth + 1);
                }
                else if (ifStatement.ElseStatement != null)
                {
                    ExecuteStatement(ifStatement.ElseStatement, environment, depth + 1);
                }
                break;
            case ForeachStatement foreachStatement:
                ExecuteForeach(foreachStatement, environment, depth);
                break;
            case ThrowStatement throwStatement:
                throw new PlaygroundThrownException(Evaluate(throwStatement.Expression, environment, depth));
            case EmptyStatement:
                break;
            default:
                throw Unsupported(PlaygroundRunFacts.UnsupportedStatement(statement.GetType().Name));
        }
    }

    private void ExecuteTupleDeconstruction(TupleDeconstructionStatement tuple, RuntimeEnvironment environment, int depth)
    {
        if (tuple.Names.Count == 2 && tuple.Initializer is CallExpression call)
        {
            try
            {
                var result = Evaluate(call, environment, depth);
                if (!PlaygroundRunFacts.IsDiscardName(tuple.Names[0]))
                {
                    environment.Declare(tuple.Names[0], result);
                }
                if (!PlaygroundRunFacts.IsDiscardName(tuple.Names[1]))
                {
                    environment.Declare(tuple.Names[1], null);
                }
            }
            catch (PlaygroundThrownException ex)
            {
                if (!PlaygroundRunFacts.IsDiscardName(tuple.Names[0]))
                {
                    environment.Declare(tuple.Names[0], null);
                }
                if (!PlaygroundRunFacts.IsDiscardName(tuple.Names[1]))
                {
                    environment.Declare(tuple.Names[1], ex.Value);
                }
            }
            return;
        }

        throw Unsupported(PlaygroundRunFacts.UnsupportedDeconstruction());
    }

    private void ExecuteForeach(ForeachStatement foreachStatement, RuntimeEnvironment environment, int depth)
    {
        var collection = Evaluate(foreachStatement.Collection, environment, depth);
        if (collection is not IReadOnlyList<object?> values)
        {
            throw Unsupported(PlaygroundRunFacts.UnsupportedForeachCollection());
        }

        foreach (var value in values)
        {
            var loopEnvironment = new RuntimeEnvironment(environment);
            loopEnvironment.Declare(foreachStatement.VariableName, value);
            ExecuteStatement(foreachStatement.Body, loopEnvironment, depth + 1);
        }
    }

    private object? Evaluate(Expression expression, RuntimeEnvironment environment, int depth)
    {
        Step(expression);
        return expression switch
        {
            IntLiteralExpression literal => int.Parse(literal.Value, CultureInfo.InvariantCulture),
            FloatLiteralExpression literal => double.Parse(literal.Value, CultureInfo.InvariantCulture),
            StringLiteralExpression literal => PlaygroundRunFacts.DecodeStringLiteralText(literal.Value),
            CharLiteralExpression literal => literal.Value.Length == 0 ? '\0' : literal.Value[0],
            BoolLiteralExpression literal => literal.Value,
            NullLiteralExpression => null,
            IdentifierExpression identifier => ResolveIdentifier(identifier.Name, environment),
            InterpolatedStringExpression interpolated => EvaluateInterpolatedString(interpolated, environment, depth),
            BinaryExpression binary => EvaluateBinary(binary, environment, depth),
            UnaryExpression unary => EvaluateUnary(unary, environment, depth),
            ParenthesizedExpression parenthesized => Evaluate(parenthesized.Inner, environment, depth),
            AssignmentExpression assignment => EvaluateAssignment(assignment, environment, depth),
            CallExpression call => EvaluateCall(call, environment, depth),
            MemberAccessExpression member => EvaluateMemberAccess(member, environment, depth),
            NewExpression newExpression => EvaluateNew(newExpression, environment, depth),
            ObjectInitializerExpression initializer => EvaluateObjectInitializer(initializer, environment, depth),
            ArrayLiteralExpression array => array.Elements.Select(element => Evaluate(element, environment, depth)).ToArray(),
            WithExpression with => EvaluateWith(with, environment, depth),
            MatchExpression match => EvaluateMatch(match, environment, depth),
            ThrowExpression throwExpression => throw new PlaygroundThrownException(Evaluate(throwExpression.Expression, environment, depth)),
            _ => throw Unsupported(PlaygroundRunFacts.UnsupportedExpression(expression.GetType().Name))
        };
    }

    private object? ResolveIdentifier(string name, RuntimeEnvironment environment)
    {
        if (environment.TryGet(name, out var value))
        {
            return value;
        }

        if (_functions.TryGetValue(name, out var function))
        {
            return new RuntimeFunction(function, null);
        }

        if (_types.TryGetValue(name, out var declaration))
        {
            return new RuntimeType(declaration);
        }

        throw Unsupported(PlaygroundRunFacts.UnresolvedName(name));
    }

    private string EvaluateInterpolatedString(InterpolatedStringExpression interpolated, RuntimeEnvironment environment, int depth)
    {
        var builder = new StringBuilder();
        foreach (var part in interpolated.Parts)
        {
            switch (part)
            {
                case InterpolatedStringText text:
                    builder.Append(text.Text);
                    break;
                case InterpolatedStringHole hole:
                    builder.Append(FormatValue(Evaluate(hole.Expression, environment, depth)));
                    break;
            }
        }

        return builder.ToString();
    }

    private object? EvaluateBinary(BinaryExpression binary, RuntimeEnvironment environment, int depth)
    {
        var left = Evaluate(binary.Left, environment, depth);
        var right = Evaluate(binary.Right, environment, depth);

        return binary.Operator switch
        {
            BinaryOperator.Add when left is string || right is string => FormatValue(left) + FormatValue(right),
            BinaryOperator.Add => ToNumber(left) + ToNumber(right),
            BinaryOperator.Subtract => ToNumber(left) - ToNumber(right),
            BinaryOperator.Multiply => ToNumber(left) * ToNumber(right),
            BinaryOperator.Divide => Divide(left, right),
            BinaryOperator.Modulo => ToInt(left) % ToInt(right),
            BinaryOperator.Equal => ValuesEqual(left, right),
            BinaryOperator.NotEqual => !ValuesEqual(left, right),
            BinaryOperator.Less => ToNumber(left) < ToNumber(right),
            BinaryOperator.LessOrEqual => ToNumber(left) <= ToNumber(right),
            BinaryOperator.Greater => ToNumber(left) > ToNumber(right),
            BinaryOperator.GreaterOrEqual => ToNumber(left) >= ToNumber(right),
            BinaryOperator.And => IsTruthy(left) && IsTruthy(right),
            BinaryOperator.Or => IsTruthy(left) || IsTruthy(right),
            _ => throw Unsupported(PlaygroundRunFacts.UnsupportedBinaryOperator(binary.Operator.ToString()))
        };
    }

    private object? EvaluateUnary(UnaryExpression unary, RuntimeEnvironment environment, int depth)
    {
        var value = Evaluate(unary.Operand, environment, depth);
        return unary.Operator switch
        {
            UnaryOperator.Negate => -ToNumber(value),
            UnaryOperator.Not => !IsTruthy(value),
            _ => throw Unsupported(PlaygroundRunFacts.UnsupportedUnaryOperator(unary.Operator.ToString()))
        };
    }

    private static object Divide(object? left, object? right)
    {
        var divisor = ToNumber(right);
        var useIntegerDivision = PlaygroundRunFacts.UseIntegerDivision(IsIntegral(left), IsIntegral(right));
        if (PlaygroundRunFacts.DivisionFaults(useIntegerDivision, divisor))
        {
            throw new PlaygroundThrownException(new RuntimeError(PlaygroundRunFacts.DivisionByZeroMessage()));
        }

        return useIntegerDivision ? ToInt(left) / ToInt(right) : ToNumber(left) / divisor;
    }

    private object? EvaluateAssignment(AssignmentExpression assignment, RuntimeEnvironment environment, int depth)
    {
        var value = Evaluate(assignment.Value, environment, depth);
        if (assignment.Operator != AssignmentOperator.Assign)
        {
            var current = assignment.Target switch
            {
                IdentifierExpression identifier => ResolveIdentifier(identifier.Name, environment),
                MemberAccessExpression member => EvaluateMemberAccess(member, environment, depth),
                _ => null
            };
            value = assignment.Operator switch
            {
                AssignmentOperator.AddAssign => ToNumber(current) + ToNumber(value),
                AssignmentOperator.SubtractAssign => ToNumber(current) - ToNumber(value),
                AssignmentOperator.MultiplyAssign => ToNumber(current) * ToNumber(value),
                AssignmentOperator.DivideAssign => Divide(current, value),
                _ => throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentOperator(assignment.Operator.ToString()))
            };
        }

        switch (assignment.Target)
        {
            case IdentifierExpression identifier:
                environment.Set(identifier.Name, value);
                break;
            case MemberAccessExpression member:
                SetMember(member, environment, depth, value);
                break;
            default:
                throw Unsupported(PlaygroundRunFacts.UnsupportedAssignmentTarget());
        }

        return value;
    }

    private object? EvaluateCall(CallExpression call, RuntimeEnvironment environment, int depth)
    {
        var arguments = call.Arguments.Select(argument => Evaluate(argument.Value, environment, depth)).ToArray();
        return call.Callee switch
        {
            IdentifierExpression identifier => CallIdentifier(identifier.Name, arguments, depth),
            MemberAccessExpression member => CallMember(member, arguments, environment, depth),
            _ => throw Unsupported(PlaygroundRunFacts.UnsupportedCallee())
        };
    }

    private object? CallIdentifier(string name, IReadOnlyList<object?> arguments, int depth)
    {
        if (_functions.TryGetValue(name, out var function))
        {
            return InvokeFunction(function, arguments, receiver: null, depth);
        }

        if (PlaygroundRunFacts.IsExceptionFactoryName(name) && arguments.Count <= 1)
        {
            return new RuntimeError(arguments.Count == 0 ? string.Empty : FormatValue(arguments[0]));
        }

        throw Unsupported(PlaygroundRunFacts.UnknownFunction(name));
    }

    private object? CallMember(MemberAccessExpression member, IReadOnlyList<object?> arguments, RuntimeEnvironment environment, int depth)
    {
        var target = Evaluate(member.Object, environment, depth);
        if (target is RuntimeObject runtimeObject)
        {
            var method = FindMethod(runtimeObject.Declaration, member.MemberName, arguments.Count, requireStatic: false);
            if (method == null)
            {
                throw Unsupported(PlaygroundRunFacts.MethodNotFound(member.MemberName));
            }

            return InvokeFunction(method, arguments, runtimeObject, depth);
        }

        if (target is RuntimeType runtimeType)
        {
            var method = FindMethod(runtimeType.Declaration, member.MemberName, arguments.Count, requireStatic: true);
            if (method == null)
            {
                throw Unsupported(PlaygroundRunFacts.StaticMethodNotFound(member.MemberName));
            }

            return InvokeFunction(method, arguments, receiver: null, depth);
        }

        return CallClrLikeMember(target, member.MemberName, arguments);
    }

    private object? CallClrLikeMember(object? target, string memberName, IReadOnlyList<object?> arguments)
    {
        if (target is string text)
        {
            return memberName switch
            {
                "ToUpper" when arguments.Count == 0 => text.ToUpperInvariant(),
                "ToLower" when arguments.Count == 0 => text.ToLowerInvariant(),
                "Contains" when arguments.Count == 1 => text.Contains(FormatValue(arguments[0]), StringComparison.Ordinal),
                "StartsWith" when arguments.Count == 1 => text.StartsWith(FormatValue(arguments[0]), StringComparison.Ordinal),
                "EndsWith" when arguments.Count == 1 => text.EndsWith(FormatValue(arguments[0]), StringComparison.Ordinal),
                "IndexOf" when arguments.Count == 1 => text.IndexOf(FormatValue(arguments[0]), StringComparison.Ordinal),
                "ToString" when arguments.Count == 0 => text,
                _ => throw Unsupported(PlaygroundRunFacts.UnsupportedStringMember(memberName))
            };
        }

        if (target is int or long or double or float or decimal)
        {
            return memberName switch
            {
                "ToString" when arguments.Count == 0 => FormatValue(target),
                "CompareTo" when arguments.Count == 1 => ToNumber(target).CompareTo(ToNumber(arguments[0])),
                _ => throw Unsupported(PlaygroundRunFacts.UnsupportedNumericMember(memberName))
            };
        }

        throw Unsupported(PlaygroundRunFacts.UnsupportedReceiverMember(memberName));
    }

    private object? EvaluateMemberAccess(MemberAccessExpression member, RuntimeEnvironment environment, int depth)
    {
        var target = Evaluate(member.Object, environment, depth);
        if (target is RuntimeObject runtimeObject)
        {
            if (runtimeObject.Fields.TryGetValue(member.MemberName, out var value))
            {
                return value;
            }

            if (FindMethod(runtimeObject.Declaration, member.MemberName, argumentCount: null, requireStatic: false) is { } method)
            {
                return new RuntimeFunction(method, runtimeObject);
            }
        }

        if (target is RuntimeError error && member.MemberName == PlaygroundRunFacts.ErrorMessageMemberName())
        {
            return error.Message;
        }

        if (target is string text && member.MemberName == PlaygroundRunFacts.LengthMemberName())
        {
            return text.Length;
        }

        if (target is IReadOnlyList<object?> values && member.MemberName == PlaygroundRunFacts.LengthMemberName())
        {
            return values.Count;
        }

        if (target is RuntimeType runtimeType)
        {
            if (runtimeType.Declaration is UnionDeclaration union && FindUnionCase(union, member.MemberName) != null)
            {
                return new RuntimeUnionCase(union, member.MemberName);
            }

            if (FindMethod(runtimeType.Declaration, member.MemberName, argumentCount: null, requireStatic: true) is { } method)
            {
                return new RuntimeFunction(method, null);
            }
        }

        throw Unsupported(PlaygroundRunFacts.UnresolvedMember(member.MemberName));
    }

    private void SetMember(MemberAccessExpression member, RuntimeEnvironment environment, int depth, object? value)
    {
        var target = Evaluate(member.Object, environment, depth);
        if (target is RuntimeObject runtimeObject)
        {
            runtimeObject.Fields[member.MemberName] = value;
            return;
        }

        throw Unsupported(PlaygroundRunFacts.UnassignableMember(member.MemberName));
    }

    private object EvaluateNew(NewExpression newExpression, RuntimeEnvironment environment, int depth)
    {
        var typeName = GetTypeName(newExpression.Type)
            ?? throw Unsupported(PlaygroundRunFacts.UnsupportedConstructionTarget());
        var arguments = newExpression.ConstructorArguments
            .Select(argument => Evaluate(argument.Value, environment, depth))
            .ToArray();

        if (PlaygroundRunFacts.IsExceptionTypeName(typeName))
        {
            return new RuntimeError(arguments.Length == 0 ? string.Empty : FormatValue(arguments[0]));
        }

        if (TryCreateUnionCase(typeName, arguments, out var unionValue))
        {
            return unionValue;
        }

        if (!_types.TryGetValue(typeName, out var declaration))
        {
            throw Unsupported(PlaygroundRunFacts.UnknownConstructedType(typeName));
        }

        var runtimeObject = new RuntimeObject(declaration, new RuntimeEnvironment(null), _typeNamespaces.GetValueOrDefault(typeName));
        ApplyPrimaryConstructorArguments(runtimeObject, arguments);
        if (newExpression.Initializer != null)
        {
            ApplyInitializer(runtimeObject, newExpression.Initializer, environment, depth);
        }

        return runtimeObject;
    }

    private object EvaluateObjectInitializer(ObjectInitializerExpression initializer, RuntimeEnvironment environment, int depth)
    {
        var runtimeObject = new RuntimeObject(null, new RuntimeEnvironment(null), null);
        ApplyInitializer(runtimeObject, initializer, environment, depth);
        return runtimeObject;
    }

    private void ApplyPrimaryConstructorArguments(RuntimeObject runtimeObject, IReadOnlyList<object?> arguments)
    {
        var parameters = runtimeObject.Declaration switch
        {
            ClassDeclaration declaration => declaration.PrimaryConstructorParameters,
            StructDeclaration declaration => declaration.PrimaryConstructorParameters,
            RecordDeclaration declaration => declaration.PrimaryConstructorParameters,
            _ => null
        };

        if (parameters == null)
        {
            if (arguments.Count > 0)
            {
                throw Unsupported(PlaygroundRunFacts.UnsupportedConstructorArguments());
            }

            return;
        }

        if (parameters.Count != arguments.Count)
        {
            throw Unsupported(PlaygroundRunFacts.WrongConstructorArgumentCount());
        }

        for (var i = 0; i < parameters.Count; i++)
        {
            runtimeObject.Fields[parameters[i].Name] = arguments[i];
            runtimeObject.Environment.Declare(parameters[i].Name, arguments[i]);
        }
    }

    private void ApplyInitializer(RuntimeObject runtimeObject, ObjectInitializerExpression initializer, RuntimeEnvironment environment, int depth)
    {
        foreach (var property in initializer.Properties)
        {
            if (property.Name == null)
            {
                throw Unsupported(PlaygroundRunFacts.UnsupportedIndexerInitializer());
            }

            runtimeObject.Fields[property.Name] = Evaluate(property.Value, environment, depth);
        }
    }

    private object EvaluateWith(WithExpression with, RuntimeEnvironment environment, int depth)
    {
        var target = Evaluate(with.Target, environment, depth);
        if (target is not RuntimeObject runtimeObject)
        {
            throw Unsupported(PlaygroundRunFacts.UnsupportedWithTarget());
        }

        var copy = runtimeObject.Clone();
        foreach (var property in with.Properties)
        {
            if (property.Name == null)
            {
                throw Unsupported(PlaygroundRunFacts.UnsupportedWithIndexer());
            }

            copy.Fields[property.Name] = Evaluate(property.Value, environment, depth);
        }

        return copy;
    }

    private object? EvaluateMatch(MatchExpression match, RuntimeEnvironment environment, int depth)
    {
        var value = Evaluate(match.Value, environment, depth);
        foreach (var matchCase in match.Cases)
        {
            var caseEnvironment = new RuntimeEnvironment(environment);
            if (PatternMatches(matchCase.Pattern, value, caseEnvironment) &&
                (matchCase.Guard == null || IsTruthy(Evaluate(matchCase.Guard, caseEnvironment, depth))))
            {
                return Evaluate(matchCase.Expression, caseEnvironment, depth);
            }
        }

        throw Unsupported(PlaygroundRunFacts.NoMatchingMatchArm());
    }

    private bool PatternMatches(Pattern pattern, object? value, RuntimeEnvironment environment)
    {
        switch (pattern)
        {
            case IdentifierPattern identifier when PlaygroundRunFacts.IsDiscardName(identifier.Name):
                return true;
            case IdentifierPattern identifier:
                environment.Declare(identifier.Name, value);
                return true;
            case LiteralPattern literal:
                object? literalValue = literal.Literal switch
                {
                    StringLiteralExpression stringLiteral => PlaygroundRunFacts.DecodeStringLiteralText(stringLiteral.Value),
                    IntLiteralExpression intLiteral => int.Parse(intLiteral.Value, CultureInfo.InvariantCulture),
                    BoolLiteralExpression boolLiteral => boolLiteral.Value,
                    NullLiteralExpression => null,
                    _ => throw Unsupported(PlaygroundRunFacts.UnsupportedLiteralPattern())
                };
                return ValuesEqual(value, literalValue);
            case UnionCasePattern unionPattern when value is RuntimeUnion union:
                if (!PlaygroundRunFacts.UnionCaseNamesMatch(unionPattern.CaseName, union.CaseName))
                {
                    return false;
                }

                foreach (var property in unionPattern.Properties ?? [])
                {
                    if (!union.Fields.TryGetValue(property.Name, out var propertyValue))
                    {
                        return false;
                    }

                    if (property.BindingName != null)
                    {
                        environment.Declare(property.BindingName, propertyValue);
                    }
                    else if (property.Pattern != null && !PatternMatches(property.Pattern, propertyValue, environment))
                    {
                        return false;
                    }
                }
                return true;
            default:
                throw Unsupported(PlaygroundRunFacts.UnsupportedPattern(pattern.GetType().Name));
        }
    }

    private bool TryCreateUnionCase(string typeName, IReadOnlyList<object?> arguments, out RuntimeUnion value)
    {
        value = null!;
        if (!PlaygroundRunFacts.IsQualifiedUnionCaseName(typeName))
        {
            return false;
        }

        var unionName = PlaygroundRunFacts.UnionOwnerNameOf(typeName);
        var caseName = PlaygroundRunFacts.UnionCaseNameOf(typeName);
        if (!_types.TryGetValue(unionName, out var declaration) || declaration is not UnionDeclaration union)
        {
            return false;
        }

        var unionCase = FindUnionCase(union, caseName)
            ?? throw Unsupported(PlaygroundRunFacts.UnknownUnionCase(caseName));
        var properties = unionCase.Properties ?? [];
        if (properties.Count != arguments.Count)
        {
            throw Unsupported(PlaygroundRunFacts.WrongUnionCaseArgumentCount());
        }

        var fields = new Dictionary<string, object?>(StringComparer.Ordinal);
        for (var i = 0; i < properties.Count; i++)
        {
            fields[properties[i].Name] = arguments[i];
        }

        value = new RuntimeUnion(_typeNamespaces.GetValueOrDefault(unionName), union.Name, unionCase.Name, fields);
        return true;
    }

    private static UnionCase? FindUnionCase(UnionDeclaration union, string caseName)
        => union.Cases.FirstOrDefault(candidate => PlaygroundRunFacts.UnionCaseNamesMatch(candidate.Name, caseName));

    private FunctionDeclaration? FindMethod(Declaration? declaration, string name, int? argumentCount, bool requireStatic)
    {
        var members = declaration switch
        {
            ClassDeclaration classDeclaration => classDeclaration.Members,
            StructDeclaration structDeclaration => structDeclaration.Members,
            RecordDeclaration recordDeclaration => recordDeclaration.Members,
            InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Members,
            _ => null
        };

        return members?
            .OfType<FunctionDeclaration>()
            .FirstOrDefault(function =>
                string.Equals(function.Name, name, StringComparison.Ordinal) &&
                (!argumentCount.HasValue || function.Parameters.Count == argumentCount.Value) &&
                function.Modifiers.HasFlag(Modifiers.Static) == requireStatic);
    }

    private static string? GetDeclarationName(Declaration declaration)
        => declaration switch
        {
            ClassDeclaration value => value.Name,
            StructDeclaration value => value.Name,
            RecordDeclaration value => value.Name,
            InterfaceDeclaration value => value.Name,
            UnionDeclaration value => value.Name,
            EnumDeclaration value => value.Name,
            _ => null
        };

    private static string? GetTypeName(TypeReference? type)
        => type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            NullableTypeReference nullable => GetTypeName(nullable.InnerType),
            ArrayTypeReference array => GetTypeName(array.ElementType) + "[]",
            _ => null
        };

    private void WriteLine(string value)
    {
        if (_outputLines >= PlaygroundRunFacts.MaxOutputLines())
        {
            throw Unsupported(PlaygroundRunFacts.OutputLineLimitReached());
        }

        _stdout.Append(value);
        _stdout.Append(PlaygroundRunFacts.OutputLineTerminator());
        _outputLines++;
    }

    private void Step(AstNode node)
    {
        _steps++;
        if (_steps > PlaygroundRunFacts.MaxSteps())
        {
            throw Unsupported(PlaygroundRunFacts.StepLimitReached());
        }
    }

    private static bool IsTruthy(object? value)
        => value switch
        {
            null => false,
            bool boolean => boolean,
            int integer => integer != 0,
            long integer => integer != 0,
            double number => Math.Abs(number) > double.Epsilon,
            string text => text.Length > 0,
            _ => true
        };

    private static bool ValuesEqual(object? left, object? right)
    {
        if (left == null || right == null)
        {
            return left == right;
        }

        if (IsNumeric(left) && IsNumeric(right))
        {
            return PlaygroundRunFacts.NumbersEqual(ToNumber(left), ToNumber(right));
        }

        return Equals(left, right);
    }

    private static bool IsIntegral(object? value)
        => value is int or long;

    private static bool IsNumeric(object? value)
        => value is int or long or float or double or decimal;

    private static double ToNumber(object? value)
        => value switch
        {
            int integer => integer,
            long integer => integer,
            float number => number,
            double number => number,
            decimal number => (double)number,
            _ => throw Unsupported(PlaygroundRunFacts.ExpectedNumber(FormatValue(value)))
        };

    private static int ToInt(object? value)
        => value switch
        {
            int integer => integer,
            long integer => checked((int)integer),
            double number => checked((int)number),
            _ => throw Unsupported(PlaygroundRunFacts.ExpectedInteger(FormatValue(value)))
        };

    private static string FormatValue(object? value)
        => value switch
        {
            null => PlaygroundRunFacts.NullDisplayText(),
            string text => text,
            bool boolean => PlaygroundRunFacts.BooleanDisplayText(boolean),
            RuntimeObject runtimeObject => runtimeObject.ToDisplayString(),
            RuntimeUnion union => union.ToDisplayString(),
            RuntimeError error => error.Message,
            double number => number.ToString(PlaygroundRunFacts.NumberFormatSpecifier(), CultureInfo.InvariantCulture),
            float number => number.ToString(PlaygroundRunFacts.NumberFormatSpecifier(), CultureInfo.InvariantCulture),
            decimal number => number.ToString(PlaygroundRunFacts.NumberFormatSpecifier(), CultureInfo.InvariantCulture),
            _ => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty
        };

    private static PlaygroundRunUnsupportedException Unsupported(PlaygroundRunFault fault)
        => new(fault.Code, fault.Message);

    private sealed class RuntimeEnvironment(RuntimeEnvironment? parent)
    {
        private readonly Dictionary<string, object?> _values = new(StringComparer.Ordinal);

        public void Declare(string name, object? value)
            => _values[name] = value;

        public bool TryGet(string name, out object? value)
        {
            if (_values.TryGetValue(name, out value))
            {
                return true;
            }

            if (parent != null)
            {
                return parent.TryGet(name, out value);
            }

            value = null;
            return false;
        }

        public void Set(string name, object? value)
        {
            if (_values.ContainsKey(name))
            {
                _values[name] = value;
                return;
            }

            if (parent != null && parent.Contains(name))
            {
                parent.Set(name, value);
                return;
            }

            _values[name] = value;
        }

        private bool Contains(string name)
            => _values.ContainsKey(name) || (parent?.Contains(name) ?? false);
    }

    private sealed record RuntimeType(Declaration Declaration);

    private sealed record RuntimeFunction(FunctionDeclaration Declaration, RuntimeObject? Receiver);

    private sealed class RuntimeObject(Declaration? declaration, RuntimeEnvironment environment, string? namespaceName)
    {
        public Declaration? Declaration { get; } = declaration;
        public RuntimeEnvironment Environment { get; } = environment;
        public string? NamespaceName { get; } = namespaceName;
        public Dictionary<string, object?> Fields { get; } = new(StringComparer.Ordinal);

        public RuntimeObject Clone()
        {
            var copy = new RuntimeObject(Declaration, new RuntimeEnvironment(null), NamespaceName);
            foreach (var (key, value) in Fields)
            {
                copy.Fields[key] = value;
                copy.Environment.Declare(key, value);
            }

            return copy;
        }

        public string ToDisplayString()
        {
            var typeName = (Declaration == null ? null : GetDeclarationName(Declaration)) ?? PlaygroundRunFacts.AnonymousObjectDisplayName();
            return PlaygroundRunFacts.ObjectDisplayText(NamespaceName, typeName);
        }
    }

    private sealed record RuntimeUnion(string? NamespaceName, string TypeName, string CaseName, Dictionary<string, object?> Fields)
    {
        public string ToDisplayString()
            => PlaygroundRunFacts.UnionDisplayText(NamespaceName, TypeName, CaseName);
    }

    private sealed record RuntimeUnionCase(UnionDeclaration Union, string CaseName);

    private sealed class ReturnSignal(object? value) : Exception
    {
        public object? Value { get; } = value;
    }

    private sealed class PlaygroundThrownException(object? value) : Exception
    {
        public object? Value { get; } = value;
    }
}

internal sealed class PlaygroundRunUnsupportedException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
