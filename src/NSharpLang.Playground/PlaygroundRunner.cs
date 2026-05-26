using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Playground;

internal sealed class PlaygroundRunner
{
    private const int MaxSteps = 20_000;
    private const int MaxCallDepth = 128;
    private const int MaxOutputLines = 200;

    private readonly List<CompilationUnit> _units;
    private readonly Dictionary<string, FunctionDeclaration> _functions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Declaration> _types = new(StringComparer.Ordinal);
    private readonly StringBuilder _stdout = new();
    private int _steps;
    private int _outputLines;

    public PlaygroundRunner(IEnumerable<CompilationUnit> units)
    {
        _units = units.ToList();
        foreach (var declaration in _units.SelectMany(unit => unit.Declarations))
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
                    }
                    break;
            }
        }
    }

    public PlaygroundRunResult Run()
    {
        var entryPoint = _functions.Values.FirstOrDefault(function =>
            string.Equals(function.Name, "main", StringComparison.OrdinalIgnoreCase));
        if (entryPoint == null)
        {
            throw new PlaygroundRunUnsupportedException("PG201", "This sample does not declare a main function that the browser runner can execute.");
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
        if (depth > MaxCallDepth)
        {
            throw Unsupported("PG202", "The browser runner stopped this program because it exceeded the maximum call depth.");
        }

        if (function.Parameters.Count != arguments.Count)
        {
            throw Unsupported("PG203", $"The browser runner cannot call '{function.Name}' with {arguments.Count} argument(s).");
        }

        var environment = new RuntimeEnvironment(receiver?.Environment);
        if (receiver != null)
        {
            environment.Declare("this", receiver);
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
                throw Unsupported("PG204", $"The browser runner does not yet support {statement.GetType().Name}.");
        }
    }

    private void ExecuteTupleDeconstruction(TupleDeconstructionStatement tuple, RuntimeEnvironment environment, int depth)
    {
        if (tuple.Names.Count == 2 && tuple.Initializer is CallExpression call)
        {
            try
            {
                var result = Evaluate(call, environment, depth);
                if (tuple.Names[0] != "_")
                {
                    environment.Declare(tuple.Names[0], result);
                }
                if (tuple.Names[1] != "_")
                {
                    environment.Declare(tuple.Names[1], null);
                }
            }
            catch (PlaygroundThrownException ex)
            {
                if (tuple.Names[0] != "_")
                {
                    environment.Declare(tuple.Names[0], null);
                }
                if (tuple.Names[1] != "_")
                {
                    environment.Declare(tuple.Names[1], ex.Value);
                }
            }
            return;
        }

        throw Unsupported("PG205", "The browser runner only supports result, err := Function(...) deconstruction.");
    }

    private void ExecuteForeach(ForeachStatement foreachStatement, RuntimeEnvironment environment, int depth)
    {
        var collection = Evaluate(foreachStatement.Collection, environment, depth);
        if (collection is not IReadOnlyList<object?> values)
        {
            throw Unsupported("PG206", "The browser runner only supports foreach over array literals.");
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
            StringLiteralExpression literal => ParseStringLiteralValue(literal.Value),
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
            _ => throw Unsupported("PG207", $"The browser runner does not yet support {expression.GetType().Name}.")
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

        throw Unsupported("PG208", $"The browser runner could not resolve '{name}'.");
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
            _ => throw Unsupported("PG209", $"The browser runner does not yet support the {binary.Operator} operator.")
        };
    }

    private object? EvaluateUnary(UnaryExpression unary, RuntimeEnvironment environment, int depth)
    {
        var value = Evaluate(unary.Operand, environment, depth);
        return unary.Operator switch
        {
            UnaryOperator.Negate => -ToNumber(value),
            UnaryOperator.Not => !IsTruthy(value),
            _ => throw Unsupported("PG210", $"The browser runner does not yet support the {unary.Operator} operator.")
        };
    }

    private static object Divide(object? left, object? right)
    {
        var divisor = ToNumber(right);
        if (Math.Abs(divisor) < double.Epsilon)
        {
            throw new PlaygroundThrownException(new RuntimeError("division by zero"));
        }

        var dividend = ToNumber(left);
        return IsIntegral(left) && IsIntegral(right)
            ? ToInt(left) / ToInt(right)
            : dividend / divisor;
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
                _ => throw Unsupported("PG211", $"The browser runner does not yet support {assignment.Operator}.")
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
                throw Unsupported("PG212", "The browser runner only supports assignment to variables and object properties.");
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
            _ => throw Unsupported("PG213", "The browser runner only supports direct function and member calls.")
        };
    }

    private object? CallIdentifier(string name, IReadOnlyList<object?> arguments, int depth)
    {
        if (_functions.TryGetValue(name, out var function))
        {
            return InvokeFunction(function, arguments, receiver: null, depth);
        }

        if (string.Equals(name, "Exception", StringComparison.Ordinal) && arguments.Count <= 1)
        {
            return new RuntimeError(arguments.Count == 0 ? string.Empty : FormatValue(arguments[0]));
        }

        throw Unsupported("PG214", $"The browser runner cannot call '{name}'.");
    }

    private object? CallMember(MemberAccessExpression member, IReadOnlyList<object?> arguments, RuntimeEnvironment environment, int depth)
    {
        var target = Evaluate(member.Object, environment, depth);
        if (target is RuntimeObject runtimeObject)
        {
            var method = FindMethod(runtimeObject.Declaration, member.MemberName, arguments.Count, requireStatic: false);
            if (method == null)
            {
                throw Unsupported("PG215", $"The browser runner could not find method '{member.MemberName}'.");
            }

            return InvokeFunction(method, arguments, runtimeObject, depth);
        }

        if (target is RuntimeType runtimeType)
        {
            var method = FindMethod(runtimeType.Declaration, member.MemberName, arguments.Count, requireStatic: true);
            if (method == null)
            {
                throw Unsupported("PG216", $"The browser runner could not find static method '{member.MemberName}'.");
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
                _ => throw Unsupported("PG217", $"The browser runner does not yet support string.{memberName}.")
            };
        }

        if (target is int or long or double or float or decimal)
        {
            return memberName switch
            {
                "ToString" when arguments.Count == 0 => FormatValue(target),
                "CompareTo" when arguments.Count == 1 => ToNumber(target).CompareTo(ToNumber(arguments[0])),
                _ => throw Unsupported("PG218", $"The browser runner does not yet support numeric.{memberName}.")
            };
        }

        throw Unsupported("PG219", $"The browser runner cannot call member '{memberName}' on this receiver.");
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

        if (target is RuntimeError error && member.MemberName == "Message")
        {
            return error.Message;
        }

        if (target is string text && member.MemberName == "Length")
        {
            return text.Length;
        }

        if (target is IReadOnlyList<object?> values && member.MemberName == "Length")
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

        throw Unsupported("PG220", $"The browser runner cannot resolve member '{member.MemberName}'.");
    }

    private void SetMember(MemberAccessExpression member, RuntimeEnvironment environment, int depth, object? value)
    {
        var target = Evaluate(member.Object, environment, depth);
        if (target is RuntimeObject runtimeObject)
        {
            runtimeObject.Fields[member.MemberName] = value;
            return;
        }

        throw Unsupported("PG221", $"The browser runner cannot assign member '{member.MemberName}'.");
    }

    private object EvaluateNew(NewExpression newExpression, RuntimeEnvironment environment, int depth)
    {
        var typeName = GetTypeName(newExpression.Type)
            ?? throw Unsupported("PG222", "The browser runner only supports named object construction.");
        var arguments = newExpression.ConstructorArguments
            .Select(argument => Evaluate(argument.Value, environment, depth))
            .ToArray();

        if (typeName is "Exception" or "System.Exception")
        {
            return new RuntimeError(arguments.Length == 0 ? string.Empty : FormatValue(arguments[0]));
        }

        if (TryCreateUnionCase(typeName, arguments, out var unionValue))
        {
            return unionValue;
        }

        if (!_types.TryGetValue(typeName, out var declaration))
        {
            throw Unsupported("PG223", $"The browser runner cannot construct '{typeName}'.");
        }

        var runtimeObject = new RuntimeObject(declaration, new RuntimeEnvironment(null));
        ApplyPrimaryConstructorArguments(runtimeObject, arguments);
        if (newExpression.Initializer != null)
        {
            ApplyInitializer(runtimeObject, newExpression.Initializer, environment, depth);
        }

        return runtimeObject;
    }

    private object EvaluateObjectInitializer(ObjectInitializerExpression initializer, RuntimeEnvironment environment, int depth)
    {
        var runtimeObject = new RuntimeObject(null, new RuntimeEnvironment(null));
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
                throw Unsupported("PG224", "The browser runner only supports constructor arguments on primary constructors and union cases.");
            }

            return;
        }

        if (parameters.Count != arguments.Count)
        {
            throw Unsupported("PG225", "The browser runner received the wrong number of constructor arguments.");
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
                throw Unsupported("PG226", "The browser runner does not yet support indexer initializers.");
            }

            runtimeObject.Fields[property.Name] = Evaluate(property.Value, environment, depth);
        }
    }

    private object EvaluateWith(WithExpression with, RuntimeEnvironment environment, int depth)
    {
        var target = Evaluate(with.Target, environment, depth);
        if (target is not RuntimeObject runtimeObject)
        {
            throw Unsupported("PG227", "The browser runner only supports with expressions on records and objects.");
        }

        var copy = runtimeObject.Clone();
        foreach (var property in with.Properties)
        {
            if (property.Name == null)
            {
                throw Unsupported("PG228", "The browser runner does not yet support indexer values in with expressions.");
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

        throw Unsupported("PG229", "The browser runner reached a match expression without a matching arm.");
    }

    private bool PatternMatches(Pattern pattern, object? value, RuntimeEnvironment environment)
    {
        switch (pattern)
        {
            case IdentifierPattern identifier when identifier.Name == "_":
                return true;
            case IdentifierPattern identifier:
                environment.Declare(identifier.Name, value);
                return true;
            case LiteralPattern literal:
                object? literalValue = literal.Literal switch
                {
                    StringLiteralExpression stringLiteral => ParseStringLiteralValue(stringLiteral.Value),
                    IntLiteralExpression intLiteral => int.Parse(intLiteral.Value, CultureInfo.InvariantCulture),
                    BoolLiteralExpression boolLiteral => boolLiteral.Value,
                    NullLiteralExpression => null,
                    _ => throw Unsupported("PG230", "The browser runner only supports literal string, int, bool, and null match patterns.")
                };
                return ValuesEqual(value, literalValue);
            case UnionCasePattern unionPattern when value is RuntimeUnion union:
                if (!CaseNamesMatch(unionPattern.CaseName, union.CaseName))
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
                throw Unsupported("PG231", $"The browser runner does not yet support {pattern.GetType().Name}.");
        }
    }

    private bool TryCreateUnionCase(string typeName, IReadOnlyList<object?> arguments, out RuntimeUnion value)
    {
        value = null!;
        var lastDot = typeName.LastIndexOf('.');
        if (lastDot <= 0)
        {
            return false;
        }

        var unionName = typeName[..lastDot];
        var caseName = typeName[(lastDot + 1)..];
        if (!_types.TryGetValue(unionName, out var declaration) || declaration is not UnionDeclaration union)
        {
            return false;
        }

        var unionCase = FindUnionCase(union, caseName)
            ?? throw Unsupported("PG232", $"The browser runner could not find union case '{caseName}'.");
        var properties = unionCase.Properties ?? [];
        if (properties.Count != arguments.Count)
        {
            throw Unsupported("PG233", "The browser runner received the wrong number of union case arguments.");
        }

        var fields = new Dictionary<string, object?>(StringComparer.Ordinal);
        for (var i = 0; i < properties.Count; i++)
        {
            fields[properties[i].Name] = arguments[i];
        }

        value = new RuntimeUnion(union.Name, unionCase.Name, fields);
        return true;
    }

    private static UnionCase? FindUnionCase(UnionDeclaration union, string caseName)
        => union.Cases.FirstOrDefault(candidate => CaseNamesMatch(candidate.Name, caseName));

    private static bool CaseNamesMatch(string left, string right)
        => string.Equals(left, right, StringComparison.Ordinal) ||
           left.EndsWith("." + right, StringComparison.Ordinal) ||
           right.EndsWith("." + left, StringComparison.Ordinal);

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
        if (_outputLines >= MaxOutputLines)
        {
            throw Unsupported("PG234", $"The browser runner stopped this program after {MaxOutputLines} output lines.");
        }

        _stdout.Append(value);
        _stdout.Append('\n');
        _outputLines++;
    }

    private void Step(AstNode node)
    {
        _steps++;
        if (_steps > MaxSteps)
        {
            throw Unsupported("PG235", $"The browser runner stopped this program after {MaxSteps} execution steps.");
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
            return Math.Abs(ToNumber(left) - ToNumber(right)) < 0.0000001;
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
            _ => throw new PlaygroundRunUnsupportedException("PG236", $"The browser runner expected a number, but found {FormatValue(value)}.")
        };

    private static int ToInt(object? value)
        => value switch
        {
            int integer => integer,
            long integer => checked((int)integer),
            double number => checked((int)number),
            _ => throw new PlaygroundRunUnsupportedException("PG237", $"The browser runner expected an integer, but found {FormatValue(value)}.")
        };

    private static string FormatValue(object? value)
        => value switch
        {
            null => "null",
            string text => text,
            bool boolean => boolean ? "True" : "False",
            RuntimeObject runtimeObject => runtimeObject.ToDisplayString(),
            RuntimeUnion union => union.ToDisplayString(),
            RuntimeError error => error.Message,
            double number => number.ToString("G", CultureInfo.InvariantCulture),
            float number => number.ToString("G", CultureInfo.InvariantCulture),
            decimal number => number.ToString("G", CultureInfo.InvariantCulture),
            _ => Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty
        };

    private static string ParseStringLiteralValue(string value)
    {
        if (value.StartsWith("\"\"\"", StringComparison.Ordinal) &&
            value.EndsWith("\"\"\"", StringComparison.Ordinal) &&
            value.Length >= 6)
        {
            return value[3..^3];
        }

        if (value.StartsWith('"') && value.EndsWith('"') && value.Length >= 2)
        {
            value = value[1..^1];
        }

        return value
            .Replace("\\n", "\n", StringComparison.Ordinal)
            .Replace("\\r", "\r", StringComparison.Ordinal)
            .Replace("\\t", "\t", StringComparison.Ordinal)
            .Replace("\\\"", "\"", StringComparison.Ordinal)
            .Replace("\\\\", "\\", StringComparison.Ordinal);
    }

    private static PlaygroundRunUnsupportedException Unsupported(string code, string message)
        => new(code, message);

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

    private sealed class RuntimeObject(Declaration? declaration, RuntimeEnvironment environment)
    {
        public Declaration? Declaration { get; } = declaration;
        public RuntimeEnvironment Environment { get; } = environment;
        public Dictionary<string, object?> Fields { get; } = new(StringComparer.Ordinal);

        public RuntimeObject Clone()
        {
            var copy = new RuntimeObject(Declaration, new RuntimeEnvironment(null));
            foreach (var (key, value) in Fields)
            {
                copy.Fields[key] = value;
                copy.Environment.Declare(key, value);
            }

            return copy;
        }

        public string ToDisplayString()
        {
            var typeName = Declaration == null ? "object" : GetDeclarationName(Declaration) ?? "object";
            return $"{typeName} {{ {string.Join(", ", Fields.Select(field => $"{field.Key}: {FormatValue(field.Value)}"))} }}";
        }
    }

    private sealed record RuntimeUnion(string TypeName, string CaseName, Dictionary<string, object?> Fields)
    {
        public string ToDisplayString()
            => $"{TypeName}.{CaseName}({string.Join(", ", Fields.Select(field => $"{field.Key}: {FormatValue(field.Value)}"))})";
    }

    private sealed record RuntimeUnionCase(UnionDeclaration Union, string CaseName);

    private sealed record RuntimeError(string Message);

    private sealed class ReturnSignal(object? value) : Exception
    {
        public object? Value { get; } = value;
    }

    private sealed class PlaygroundThrownException(object? value) : Exception
    {
        public object? Value { get; } = value;
    }
}

internal sealed record PlaygroundRunResult(string Stdout, string? Stderr, int ExitCode);

internal sealed class PlaygroundRunUnsupportedException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
