using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace NSharpLang.Cli;

public sealed class CSharpToNSharpConverter
{
    public CSharpConversionResult Convert(string source, string? filePath = null)
    {
        var tree = CSharpSyntaxTree.ParseText(source, path: filePath ?? "");
        var root = tree.GetCompilationUnitRoot();
        var diagnostics = tree.GetDiagnostics()
            .Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error)
            .Select(diagnostic => diagnostic.ToString())
            .ToArray();

        if (diagnostics.Length > 0)
        {
            return new CSharpConversionResult(false, string.Empty, diagnostics);
        }

        var emitter = new Emitter();
        return new CSharpConversionResult(true, emitter.Emit(root), emitter.Warnings);
    }

    private sealed class Emitter
    {
        private readonly StringBuilder _builder = new();
        private readonly List<string> _warnings = new();
        private readonly Stack<Dictionary<string, string>> _memberNameAliases = new();
        private int _indent;

        public IReadOnlyList<string> Warnings => _warnings;

        public string Emit(CompilationUnitSyntax root)
        {
            foreach (var usingDirective in root.Usings)
            {
                WriteLine($"import {usingDirective.Name}");
            }

            if (root.Usings.Count > 0 && root.Members.Count > 0)
            {
                WriteLine();
            }

            for (var i = 0; i < root.Members.Count; i++)
            {
                EmitTopLevelMember(root.Members[i]);
                if (i < root.Members.Count - 1)
                {
                    WriteLine();
                }
            }

            return _builder.ToString();
        }

        private void EmitTopLevelMember(MemberDeclarationSyntax member)
        {
            EmitLeadingComments(member);
            switch (member)
            {
                case FileScopedNamespaceDeclarationSyntax fileNamespace:
                    WriteLine($"package {fileNamespace.Name}");
                    WriteLine();
                    EmitUsings(fileNamespace.Usings);
                    EmitTopLevelMembers(fileNamespace.Members);
                    break;
                case NamespaceDeclarationSyntax namespaceDeclaration:
                    WriteLine($"package {namespaceDeclaration.Name}");
                    WriteLine();
                    EmitUsings(namespaceDeclaration.Usings);
                    EmitTopLevelMembers(namespaceDeclaration.Members);
                    break;
                case ClassDeclarationSyntax classDeclaration:
                    EmitClass(classDeclaration);
                    break;
                case StructDeclarationSyntax structDeclaration:
                    AddWarning(structDeclaration, "C# struct converted to class; review value semantics manually.");
                    EmitTypeLike("class", structDeclaration.Identifier.Text, structDeclaration.Modifiers, structDeclaration.TypeParameterList, structDeclaration.Members);
                    break;
                case RecordDeclarationSyntax recordDeclaration:
                    EmitRecord(recordDeclaration);
                    break;
                case InterfaceDeclarationSyntax interfaceDeclaration:
                    EmitTypeLike("interface", interfaceDeclaration.Identifier.Text, interfaceDeclaration.Modifiers, interfaceDeclaration.TypeParameterList, interfaceDeclaration.Members);
                    break;
                case EnumDeclarationSyntax enumDeclaration:
                    EmitEnum(enumDeclaration);
                    break;
                case MethodDeclarationSyntax methodDeclaration:
                    EmitMethod(methodDeclaration);
                    break;
                case GlobalStatementSyntax globalStatement:
                    EmitStatement(globalStatement.Statement);
                    break;
                default:
                    EmitUnsupported(member, "member");
                    break;
            }
        }

        private void EmitUsings(SyntaxList<UsingDirectiveSyntax> usings)
        {
            foreach (var usingDirective in usings)
            {
                WriteLine($"import {usingDirective.Name}");
            }

            if (usings.Count > 0)
            {
                WriteLine();
            }
        }

        private void EmitTopLevelMembers(SyntaxList<MemberDeclarationSyntax> members)
        {
            for (var i = 0; i < members.Count; i++)
            {
                EmitTopLevelMember(members[i]);
                if (i < members.Count - 1)
                {
                    WriteLine();
                }
            }
        }

        private void EmitClass(ClassDeclarationSyntax declaration)
        {
            EmitTypeLike("class", declaration.Identifier.Text, declaration.Modifiers, declaration.TypeParameterList, declaration.Members);
        }

        private void EmitRecord(RecordDeclarationSyntax declaration)
        {
            var name = declaration.Identifier.Text + TypeParameters(declaration.TypeParameterList);
            WriteLine($"{Modifiers(declaration.Modifiers)}record {name} {{".TrimStart());
            _indent++;

            if (declaration.ParameterList != null)
            {
                foreach (var parameter in declaration.ParameterList.Parameters)
                {
                    WriteLine($"{ToPascalCase(parameter.Identifier.Text)}: {TypeName(parameter.Type)}");
                }
            }

            foreach (var member in declaration.Members)
            {
                EmitTypeMember(member);
            }

            _indent--;
            WriteLine("}");
        }

        private void EmitTypeLike(
            string keyword,
            string name,
            SyntaxTokenList modifiers,
            TypeParameterListSyntax? typeParameterList,
            SyntaxList<MemberDeclarationSyntax> members)
        {
            _memberNameAliases.Push(BuildMemberNameAliases(members));
            WriteLine($"{Modifiers(modifiers)}{keyword} {name}{TypeParameters(typeParameterList)} {{".TrimStart());
            _indent++;
            for (var i = 0; i < members.Count; i++)
            {
                EmitTypeMember(members[i]);
                if (i < members.Count - 1)
                {
                    WriteLine();
                }
            }

            _indent--;
            WriteLine("}");
            _memberNameAliases.Pop();
        }

        private void EmitEnum(EnumDeclarationSyntax declaration)
        {
            WriteLine($"{Modifiers(declaration.Modifiers)}enum {declaration.Identifier.Text} {{".TrimStart());
            _indent++;
            for (var i = 0; i < declaration.Members.Count; i++)
            {
                var member = declaration.Members[i];
                var value = member.EqualsValue != null ? $" = {Expression(member.EqualsValue.Value)}" : string.Empty;
                WriteLine($"{member.Identifier.Text}{value}{(i < declaration.Members.Count - 1 ? "," : string.Empty)}");
            }

            _indent--;
            WriteLine("}");
        }

        private void EmitTypeMember(MemberDeclarationSyntax member)
        {
            EmitLeadingComments(member);
            switch (member)
            {
                case ConstructorDeclarationSyntax constructor:
                    EmitConstructor(constructor);
                    break;
                case MethodDeclarationSyntax method:
                    EmitMethod(method);
                    break;
                case PropertyDeclarationSyntax property:
                    EmitProperty(property);
                    break;
                case FieldDeclarationSyntax field:
                    EmitField(field);
                    break;
                case ClassDeclarationSyntax classDeclaration:
                    EmitClass(classDeclaration);
                    break;
                case EnumDeclarationSyntax enumDeclaration:
                    EmitEnum(enumDeclaration);
                    break;
                default:
                    EmitUnsupported(member, "member");
                    break;
            }
        }

        private void EmitConstructor(ConstructorDeclarationSyntax constructor)
        {
            var initializer = constructor.Initializer != null
                ? $": {constructor.Initializer.ThisOrBaseKeyword.ValueText}({Arguments(constructor.Initializer.ArgumentList.Arguments)})"
                : string.Empty;
            WriteLine($"constructor({Parameters(constructor.ParameterList.Parameters)}){initializer} {{");
            _indent++;
            EmitBlockStatements(constructor.Body?.Statements ?? default);
            _indent--;
            WriteLine("}");
        }

        private void EmitMethod(MethodDeclarationSyntax method)
        {
            var modifiers = Modifiers(method.Modifiers);
            var returnType = TypeName(method.ReturnType);
            var prefix = method.Modifiers.Any(SyntaxKind.AsyncKeyword) ? "async " : string.Empty;
            var signature = $"{modifiers}{prefix}func {method.Identifier.Text}{TypeParameters(method.TypeParameterList)}({Parameters(method.ParameterList.Parameters)})";
            if (returnType != "void")
            {
                signature += $": {returnType}";
            }

            if (method.ExpressionBody != null)
            {
                WriteLine($"{signature} => {Expression(method.ExpressionBody.Expression)}");
                return;
            }

            WriteLine($"{signature} {{");
            _indent++;
            EmitBlockStatements(method.Body?.Statements ?? default);
            _indent--;
            WriteLine("}");
        }

        private void EmitProperty(PropertyDeclarationSyntax property)
        {
            var name = property.Identifier.Text;
            var type = TypeName(property.Type);
            var value = property.Initializer != null ? $" = {Expression(property.Initializer.Value)}" : string.Empty;
            if (property.ExpressionBody != null)
            {
                WriteLine($"{Modifiers(property.Modifiers)}{name}: {type} => {Expression(property.ExpressionBody.Expression)}".TrimStart());
            }
            else
            {
                WriteLine($"{Modifiers(property.Modifiers)}{name}: {type}{value}".TrimStart());
            }
        }

        private void EmitField(FieldDeclarationSyntax field)
        {
            foreach (var variable in field.Declaration.Variables)
            {
                var value = variable.Initializer != null ? $" = {Expression(variable.Initializer.Value)}" : string.Empty;
                WriteLine($"{StaticModifier(field.Modifiers)}{ConvertMemberName(variable.Identifier.Text)}: {TypeName(field.Declaration.Type)}{value}".TrimStart());
            }
        }

        private void EmitBlockStatements(SyntaxList<StatementSyntax> statements)
        {
            foreach (var statement in statements)
            {
                EmitStatement(statement);
            }
        }

        private void EmitStatement(StatementSyntax statement)
        {
            EmitLeadingComments(statement);
            switch (statement)
            {
                case BlockSyntax block:
                    WriteLine("{");
                    _indent++;
                    EmitBlockStatements(block.Statements);
                    _indent--;
                    WriteLine("}");
                    break;
                case LocalDeclarationStatementSyntax local:
                    foreach (var variable in local.Declaration.Variables)
                    {
                        var initializer = variable.Initializer != null ? Expression(variable.Initializer.Value) : DefaultFor(local.Declaration.Type);
                        if (local.Declaration.Type is IdentifierNameSyntax { Identifier.Text: "var" })
                        {
                            WriteLine($"{variable.Identifier.Text} := {initializer}");
                        }
                        else
                        {
                            WriteLine($"{variable.Identifier.Text}: {TypeName(local.Declaration.Type)} = {initializer}");
                        }
                    }
                    break;
                case ExpressionStatementSyntax expressionStatement:
                    WriteLine(Expression(expressionStatement.Expression));
                    break;
                case ReturnStatementSyntax returnStatement:
                    WriteLine(returnStatement.Expression == null ? "return" : $"return {Expression(returnStatement.Expression)}");
                    break;
                case IfStatementSyntax ifStatement:
                    EmitIf(ifStatement);
                    break;
                case ForStatementSyntax forStatement:
                    EmitFor(forStatement);
                    break;
                case ForEachStatementSyntax foreachStatement:
                    WriteLine($"foreach {foreachStatement.Identifier.Text} in {Expression(foreachStatement.Expression)} {{");
                    _indent++;
                    EmitEmbeddedStatement(foreachStatement.Statement);
                    _indent--;
                    WriteLine("}");
                    break;
                case WhileStatementSyntax whileStatement:
                    WriteLine($"while {Expression(whileStatement.Condition)} {{");
                    _indent++;
                    EmitEmbeddedStatement(whileStatement.Statement);
                    _indent--;
                    WriteLine("}");
                    break;
                case BreakStatementSyntax:
                    WriteLine("break");
                    break;
                case ContinueStatementSyntax:
                    WriteLine("continue");
                    break;
                case ThrowStatementSyntax throwStatement:
                    WriteLine(throwStatement.Expression == null ? "throw" : $"throw {Expression(throwStatement.Expression)}");
                    break;
                case TryStatementSyntax tryStatement:
                    EmitTry(tryStatement);
                    break;
                default:
                    EmitUnsupported(statement, "statement");
                    break;
            }
        }

        private void EmitIf(IfStatementSyntax ifStatement)
        {
            WriteLine($"if {Expression(ifStatement.Condition)} {{");
            _indent++;
            EmitEmbeddedStatement(ifStatement.Statement);
            _indent--;
            if (ifStatement.Else == null)
            {
                WriteLine("}");
                return;
            }

            WriteLine("} else {");
            _indent++;
            EmitEmbeddedStatement(ifStatement.Else.Statement);
            _indent--;
            WriteLine("}");
        }

        private void EmitFor(ForStatementSyntax forStatement)
        {
            var declaration = forStatement.Declaration?.Variables.FirstOrDefault();
            var initializer = declaration != null
                ? $"{declaration.Identifier.Text} := {Expression(declaration.Initializer!.Value)}"
                : string.Join(", ", forStatement.Initializers.Select(Expression));
            var condition = forStatement.Condition != null ? Expression(forStatement.Condition) : "true";
            var incrementors = string.Join(", ", forStatement.Incrementors.Select(Expression));
            WriteLine($"for {initializer}; {condition}; {incrementors} {{");
            _indent++;
            EmitEmbeddedStatement(forStatement.Statement);
            _indent--;
            WriteLine("}");
        }

        private void EmitTry(TryStatementSyntax tryStatement)
        {
            WriteLine("try {");
            _indent++;
            EmitBlockStatements(tryStatement.Block.Statements);
            _indent--;

            foreach (var catchClause in tryStatement.Catches)
            {
                if (catchClause.Declaration != null || catchClause.Filter != null)
                {
                    AddWarning(catchClause, "C# catch declarations/filters are converted to a plain N# catch block; review exception handling manually.");
                }

                WriteLine("} catch {");
                _indent++;
                EmitBlockStatements(catchClause.Block.Statements);
                _indent--;
            }

            if (tryStatement.Finally != null)
            {
                WriteLine("} finally {");
                _indent++;
                EmitBlockStatements(tryStatement.Finally.Block.Statements);
                _indent--;
            }

            WriteLine("}");
        }

        private void EmitEmbeddedStatement(StatementSyntax statement)
        {
            if (statement is BlockSyntax block)
            {
                EmitBlockStatements(block.Statements);
                return;
            }

            EmitStatement(statement);
        }

        private string Expression(ExpressionSyntax expression)
        {
            return expression switch
            {
                LiteralExpressionSyntax literal => literal.Token.Text,
                PredefinedTypeSyntax predefined => TypeName(predefined),
                IdentifierNameSyntax identifier when TryMemberAlias(identifier.Identifier.Text, out var alias) => alias,
                IdentifierNameSyntax identifier => identifier.Identifier.Text,
                GenericNameSyntax generic => $"{generic.Identifier.Text}<{string.Join(", ", generic.TypeArgumentList.Arguments.Select(TypeName))}>",
                ThisExpressionSyntax => "this",
                BaseExpressionSyntax => "base",
                MemberAccessExpressionSyntax member => $"{Expression(member.Expression)}.{member.Name}",
                ConditionalAccessExpressionSyntax conditional => $"{Expression(conditional.Expression)}?.{Expression(conditional.WhenNotNull)}",
                MemberBindingExpressionSyntax binding => binding.Name.ToString(),
                InvocationExpressionSyntax invocation => Invocation(invocation),
                ObjectCreationExpressionSyntax creation => ObjectCreation(creation),
                ImplicitObjectCreationExpressionSyntax creation => $"new({Arguments(creation.ArgumentList?.Arguments ?? default)}){InitializerOrEmpty(creation.Initializer)}",
                AssignmentExpressionSyntax assignment => Assignment(assignment),
                BinaryExpressionSyntax binary => $"{Expression(binary.Left)} {binary.OperatorToken.Text} {Expression(binary.Right)}",
                PrefixUnaryExpressionSyntax unary => $"{unary.OperatorToken.Text}{Expression(unary.Operand)}",
                PostfixUnaryExpressionSyntax unary when unary.IsKind(SyntaxKind.SuppressNullableWarningExpression) => Expression(unary.Operand),
                PostfixUnaryExpressionSyntax unary => $"{Expression(unary.Operand)}{unary.OperatorToken.Text}",
                ParenthesizedExpressionSyntax parenthesized => $"({Expression(parenthesized.Expression)})",
                ElementAccessExpressionSyntax element => $"{Expression(element.Expression)}[{Arguments(element.ArgumentList.Arguments)}]",
                ConditionalExpressionSyntax conditional => $"{Expression(conditional.Condition)} ? {Expression(conditional.WhenTrue)} : {Expression(conditional.WhenFalse)}",
                DeclarationExpressionSyntax declaration => DeclarationExpressionToString(declaration),
                CastExpressionSyntax cast => $"({TypeName(cast.Type)}){Expression(cast.Expression)}",
                IsPatternExpressionSyntax isPattern => $"{Expression(isPattern.Expression)} is {isPattern.Pattern}",
                AwaitExpressionSyntax awaitExpression => $"await {Expression(awaitExpression.Expression)}",
                InterpolatedStringExpressionSyntax interpolated => interpolated.ToString(),
                SimpleLambdaExpressionSyntax lambda => $"{lambda.Parameter.Identifier.Text} => {LambdaBody(lambda.Body)}",
                ParenthesizedLambdaExpressionSyntax lambda => $"({string.Join(", ", lambda.ParameterList.Parameters.Select(Parameter))}) => {LambdaBody(lambda.Body)}",
                AnonymousObjectCreationExpressionSyntax anonymous => AnonymousObject(anonymous),
                ArrayCreationExpressionSyntax array => ArrayCreation(array),
                ImplicitArrayCreationExpressionSyntax array => InitializerExpression(array.Initializer),
                InitializerExpressionSyntax initializer => Initializer(initializer),
                SwitchExpressionSyntax switchExpression => SwitchExpression(switchExpression),
                TupleExpressionSyntax tuple => $"({Arguments(tuple.Arguments)})",
                TypeOfExpressionSyntax typeOf => $"typeof({TypeName(typeOf.Type)})",
                DefaultExpressionSyntax => "default",
                _ => UnsupportedExpression(expression)
            };
        }

        private string Assignment(AssignmentExpressionSyntax assignment)
        {
            if (assignment.Left is IdentifierNameSyntax leftIdentifier
                && TryMemberAlias(leftIdentifier.Identifier.Text, out var alias)
                && assignment.Right is IdentifierNameSyntax rightIdentifier
                && string.Equals(alias, rightIdentifier.Identifier.Text, StringComparison.Ordinal))
            {
                return $"this.{alias} {assignment.OperatorToken.Text} {Expression(assignment.Right)}";
            }

            return $"{Expression(assignment.Left)} {assignment.OperatorToken.Text} {Expression(assignment.Right)}";
        }

        private string SwitchExpression(SwitchExpressionSyntax switchExpression)
        {
            var arms = switchExpression.Arms.Select((arm, index) =>
                $"{Pattern(arm.Pattern)} => {Expression(arm.Expression)}{(index < switchExpression.Arms.Count - 1 ? "," : string.Empty)}");
            return $"match {Expression(switchExpression.GoverningExpression)} {{ {string.Join(" ", arms)} }}";
        }

        private string Pattern(PatternSyntax pattern)
        {
            return pattern switch
            {
                DiscardPatternSyntax => "_",
                ConstantPatternSyntax constant => Expression(constant.Expression),
                DeclarationPatternSyntax declaration => TypeName(declaration.Type),
                VarPatternSyntax varPattern => varPattern.Designation.ToString(),
                RecursivePatternSyntax recursive when recursive.Type != null => TypeName(recursive.Type),
                _ => pattern.ToString()
            };
        }

        private string Invocation(InvocationExpressionSyntax invocation)
        {
            if (invocation.Expression is MemberAccessExpressionSyntax
                {
                    Expression: IdentifierNameSyntax { Identifier.Text: "Console" },
                    Name.Identifier.Text: "WriteLine"
                })
            {
                return invocation.ArgumentList.Arguments.Count == 1
                    ? $"print {Expression(invocation.ArgumentList.Arguments[0].Expression)}"
                    : $"Console.WriteLine({Arguments(invocation.ArgumentList.Arguments)})";
            }

            return $"{Expression(invocation.Expression)}({Arguments(invocation.ArgumentList.Arguments)})";
        }

        private string ObjectCreation(ObjectCreationExpressionSyntax creation)
        {
            return $"new {TypeName(creation.Type)}({Arguments(creation.ArgumentList?.Arguments ?? default)}){InitializerOrEmpty(creation.Initializer)}";
        }

        private string ArrayCreation(ArrayCreationExpressionSyntax array)
        {
            return array.Initializer != null
                ? InitializerExpression(array.Initializer)
                : $"new {TypeName(array.Type)}";
        }

        private string InitializerExpression(InitializerExpressionSyntax initializer)
        {
            return $"[{string.Join(", ", initializer.Expressions.Select(Expression))}]";
        }

        private string DeclarationExpressionToString(DeclarationExpressionSyntax declaration)
        {
            return declaration.Designation switch
            {
                SingleVariableDesignationSyntax single => single.Identifier.Text,
                ParenthesizedVariableDesignationSyntax parenthesized => $"({string.Join(", ", parenthesized.Variables.Select(variable => variable.ToString()))})",
                DiscardDesignationSyntax => "_",
                _ => declaration.Designation.ToString()
            };
        }

        private string AnonymousObject(AnonymousObjectCreationExpressionSyntax anonymous)
        {
            return $"new() {{ {string.Join(", ", anonymous.Initializers.Select(initializer => $"{initializer.NameEquals?.Name ?? initializer.Expression}: {Expression(initializer.Expression)}"))} }}";
        }

        private static Dictionary<string, string> BuildMemberNameAliases(SyntaxList<MemberDeclarationSyntax> members)
        {
            var aliases = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var field in members.OfType<FieldDeclarationSyntax>())
            {
                foreach (var variable in field.Declaration.Variables)
                {
                    var original = variable.Identifier.Text;
                    var converted = ConvertMemberName(original);
                    if (!string.Equals(original, converted, StringComparison.Ordinal))
                    {
                        aliases[original] = converted;
                    }
                }
            }

            return aliases;
        }

        private static string ConvertMemberName(string name)
        {
            if (name.Length > 1 && name[0] == '_' && char.IsLetter(name[1]))
            {
                return char.ToLowerInvariant(name[1]) + name[2..];
            }

            return name;
        }

        private bool TryMemberAlias(string name, out string alias)
        {
            foreach (var aliases in _memberNameAliases)
            {
                if (aliases.TryGetValue(name, out alias!))
                {
                    return true;
                }
            }

            alias = string.Empty;
            return false;
        }

        private string InitializerOrEmpty(InitializerExpressionSyntax? initializer)
        {
            if (initializer == null)
            {
                return string.Empty;
            }

            return Initializer(initializer);
        }

        private string Initializer(InitializerExpressionSyntax initializer)
        {
            var parts = initializer.Expressions.Select(expression =>
            {
                if (expression is AssignmentExpressionSyntax assignment)
                {
                    return $"{Expression(assignment.Left)}: {Expression(assignment.Right)}";
                }

                return Expression(expression);
            });
            return $" {{ {string.Join(", ", parts)} }}";
        }

        private string LambdaBody(CSharpSyntaxNode body)
        {
            return body switch
            {
                ExpressionSyntax expression => Expression(expression),
                BlockSyntax block => "{ " + string.Join(" ", block.Statements.Select(StatementInline)) + " }",
                _ => UnsupportedNode(body, "lambda body")
            };
        }

        private string StatementInline(StatementSyntax statement)
        {
            return statement switch
            {
                BlockSyntax block => string.Join(" ", block.Statements.Select(StatementInline)),
                ReturnStatementSyntax returnStatement => returnStatement.Expression == null ? "return" : $"return {Expression(returnStatement.Expression)}",
                IfStatementSyntax ifStatement => IfInline(ifStatement),
                ForEachStatementSyntax foreachStatement => $"foreach {foreachStatement.Identifier.Text} in {Expression(foreachStatement.Expression)} {{ {StatementInline(foreachStatement.Statement)} }}",
                ExpressionStatementSyntax expressionStatement => Expression(expressionStatement.Expression),
                LocalDeclarationStatementSyntax local => string.Join(" ", local.Declaration.Variables.Select(variable =>
                {
                    var initializer = variable.Initializer != null ? Expression(variable.Initializer.Value) : DefaultFor(local.Declaration.Type);
                    return local.Declaration.Type is IdentifierNameSyntax { Identifier.Text: "var" }
                        ? $"{variable.Identifier.Text} := {initializer}"
                        : $"{variable.Identifier.Text}: {TypeName(local.Declaration.Type)} = {initializer}";
                })),
                _ => UnsupportedNode(statement, "lambda statement")
            };
        }

        private string IfInline(IfStatementSyntax ifStatement)
        {
            var value = $"if {Expression(ifStatement.Condition)} {{ {StatementInline(ifStatement.Statement)} }}";
            if (ifStatement.Else != null)
            {
                value += $" else {{ {StatementInline(ifStatement.Else.Statement)} }}";
            }

            return value;
        }

        private string Arguments(SeparatedSyntaxList<ArgumentSyntax> arguments)
        {
            return string.Join(", ", arguments.Select(argument =>
            {
                var namePrefix = argument.NameColon != null ? $"{argument.NameColon.Name}: " : string.Empty;
                if (!argument.RefKindKeyword.IsKind(SyntaxKind.None))
                {
                    AddWarning(argument, $"C# {argument.RefKindKeyword.ValueText} argument requires manual migration to an N# tuple/result-returning API.");
                    return namePrefix + $"manualReview(\"{argument.RefKindKeyword.ValueText} argument\", {Expression(argument.Expression)})";
                }

                return namePrefix + Expression(argument.Expression);
            }));
        }

        private string Parameters(SeparatedSyntaxList<ParameterSyntax> parameters)
        {
            return string.Join(", ", parameters.Select(Parameter));
        }

        private string Parameter(ParameterSyntax parameter)
        {
            return $"{parameter.Identifier.Text}: {TypeName(parameter.Type)}";
        }

        private static string TypeParameters(TypeParameterListSyntax? typeParameterList)
        {
            return typeParameterList == null
                ? string.Empty
                : $"<{string.Join(", ", typeParameterList.Parameters.Select(parameter => parameter.Identifier.Text))}>";
        }

        private string TypeName(TypeSyntax? type)
        {
            return type switch
            {
                null => "var",
                PredefinedTypeSyntax predefined => predefined.Keyword.ValueText switch
                {
                    "bool" => "bool",
                    "byte" => "byte",
                    "decimal" => "decimal",
                    "double" => "double",
                    "float" => "float",
                    "int" => "int",
                    "long" => "long",
                    "object" => "object",
                    "short" => "short",
                    "string" => "string",
                    "void" => "void",
                    _ => predefined.Keyword.ValueText
                },
                IdentifierNameSyntax identifier => MapTypeName(identifier.Identifier.Text),
                QualifiedNameSyntax qualified => $"{TypeName(qualified.Left)}.{TypeName(qualified.Right)}",
                AliasQualifiedNameSyntax aliasQualified => $"{aliasQualified.Alias}.{TypeName(aliasQualified.Name)}",
                GenericNameSyntax generic => GenericTypeName(generic),
                ArrayTypeSyntax array => $"{TypeName(array.ElementType)}{string.Concat(array.RankSpecifiers.Select(rank => "[" + new string(',', rank.Rank - 1) + "]"))}",
                NullableTypeSyntax nullable => $"{TypeName(nullable.ElementType)}?",
                TupleTypeSyntax tuple => $"({string.Join(", ", tuple.Elements.Select(element => element.Identifier.IsKind(SyntaxKind.None) ? TypeName(element.Type) : $"{element.Identifier.Text}: {TypeName(element.Type)}"))})",
                _ => type.ToString()
            };
        }

        private string GenericTypeName(GenericNameSyntax generic)
        {
            var name = MapTypeName(generic.Identifier.Text);
            return $"{name}<{string.Join(", ", generic.TypeArgumentList.Arguments.Select(TypeName))}>";
        }

        private static string MapTypeName(string name)
        {
            return name switch
            {
                "IActionResult" => "Result",
                "ActionResult" => "Result",
                _ => name
            };
        }

        private string Modifiers(SyntaxTokenList modifiers)
        {
            var parts = modifiers
                .Where(modifier => modifier.IsKind(SyntaxKind.StaticKeyword)
                    || modifier.IsKind(SyntaxKind.AbstractKeyword)
                    || modifier.IsKind(SyntaxKind.OverrideKeyword)
                    || modifier.IsKind(SyntaxKind.SealedKeyword)
                    || modifier.IsKind(SyntaxKind.PartialKeyword)
                    || modifier.IsKind(SyntaxKind.FileKeyword))
                .Select(modifier => modifier.ValueText);

            var value = string.Join(" ", parts);
            return value.Length == 0 ? string.Empty : value + " ";
        }

        private string StaticModifier(SyntaxTokenList modifiers)
        {
            return modifiers.Any(SyntaxKind.StaticKeyword) ? "static " : string.Empty;
        }

        private string DefaultFor(TypeSyntax type)
        {
            return type switch
            {
                PredefinedTypeSyntax predefined when predefined.Keyword.IsKind(SyntaxKind.BoolKeyword) => "false",
                PredefinedTypeSyntax predefined when predefined.Keyword.IsKind(SyntaxKind.StringKeyword) => "\"\"",
                PredefinedTypeSyntax predefined when predefined.Keyword.IsKind(SyntaxKind.IntKeyword)
                    || predefined.Keyword.IsKind(SyntaxKind.LongKeyword)
                    || predefined.Keyword.IsKind(SyntaxKind.ShortKeyword)
                    || predefined.Keyword.IsKind(SyntaxKind.ByteKeyword) => "0",
                PredefinedTypeSyntax predefined when predefined.Keyword.IsKind(SyntaxKind.FloatKeyword)
                    || predefined.Keyword.IsKind(SyntaxKind.DoubleKeyword)
                    || predefined.Keyword.IsKind(SyntaxKind.DecimalKeyword) => "0",
                _ => "null"
            };
        }

        private static string ToPascalCase(string text)
        {
            return text.Length == 0 ? text : char.ToUpperInvariant(text[0]) + text[1..];
        }

        private void EmitLeadingComments(SyntaxNode node)
        {
            foreach (var trivia in node.GetLeadingTrivia())
            {
                if (trivia.IsKind(SyntaxKind.SingleLineCommentTrivia) || trivia.IsKind(SyntaxKind.MultiLineCommentTrivia))
                {
                    WriteLine(trivia.ToString());
                }
            }
        }

        private string UnsupportedExpression(SyntaxNode node)
        {
            AddWarning(node, $"Unsupported expression '{node.Kind()}'. Kept as source text for manual review.");
            return node.ToString();
        }

        private string UnsupportedNode(SyntaxNode node, string label)
        {
            AddWarning(node, $"Unsupported {label} '{node.Kind()}'. Kept as source text for manual review.");
            return node.ToString();
        }

        private void EmitUnsupported(SyntaxNode node, string label)
        {
            AddWarning(node, $"Unsupported {label} '{node.Kind()}'.");
            WriteLine($"// TODO(nlc convert): unsupported {label}: {node.Kind()}");
            foreach (var line in node.ToString().Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
            {
                WriteLine($"// {line}");
            }
        }

        private void AddWarning(SyntaxNode node, string message)
        {
            var lineSpan = node.SyntaxTree.GetLineSpan(node.Span);
            _warnings.Add($"{lineSpan.Path}:{lineSpan.StartLinePosition.Line + 1}:{lineSpan.StartLinePosition.Character + 1}: {message}");
        }

        private void WriteLine(string value = "")
        {
            if (value.Length > 0)
            {
                _builder.Append(new string(' ', _indent * 4));
            }

            _builder.AppendLine(value);
        }
    }
}

public sealed record CSharpConversionResult(bool Success, string Output, IReadOnlyList<string> Diagnostics);
