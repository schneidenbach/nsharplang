using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class NamespaceQualifiedCompilationMerger
{
    public static CompilationUnit Merge(IReadOnlyList<CompilationUnit> orderedUnits)
    {
        if (orderedUnits.Count == 0)
        {
            return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1);
        }

        var projectTypes = orderedUnits
            .SelectMany(GetTopLevelTypeInfos)
            .GroupBy(info => info.SimpleName, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.ToList(), StringComparer.Ordinal);

        var transformedUnits = orderedUnits
            .Select(unit => new Transformer(unit, projectTypes).Transform())
            .ToList();

        var firstUnit = transformedUnits[0];
        var imports = transformedUnits
            .SelectMany(unit => unit.Imports)
            .DistinctBy(importDirective => (importDirective.Namespace, importDirective.Alias))
            .ToList();
        var fileImports = transformedUnits.SelectMany(unit => unit.FileImports).ToList();
        var declarations = transformedUnits.SelectMany(unit => unit.Declarations).ToList();

        return new CompilationUnit(
            null,
            imports,
            fileImports,
            transformedUnits.Select(unit => unit.Package).FirstOrDefault(packageDeclaration => packageDeclaration != null),
            declarations,
            firstUnit.Line,
            firstUnit.Column);
    }

    private static IEnumerable<TopLevelTypeInfo> GetTopLevelTypeInfos(CompilationUnit unit)
    {
        var namespaceName = GetNamespaceName(unit);
        foreach (var declaration in unit.Declarations)
        {
            var simpleName = GetDeclaredTypeName(declaration);
            if (simpleName == null)
            {
                continue;
            }

            yield return new TopLevelTypeInfo(
                namespaceName,
                simpleName,
                QualifyName(namespaceName, simpleName));
        }
    }

    private static string? GetDeclaredTypeName(Declaration declaration)
    {
        return declaration switch
        {
            ClassDeclaration classDeclaration => classDeclaration.Name,
            StructDeclaration structDeclaration => structDeclaration.Name,
            RecordDeclaration recordDeclaration => recordDeclaration.Name,
            InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Name,
            EnumDeclaration enumDeclaration => enumDeclaration.Name,
            UnionDeclaration unionDeclaration => unionDeclaration.Name,
            NewtypeDeclaration newtypeDeclaration => newtypeDeclaration.Name,
            _ => null
        };
    }

    private static string GetNamespaceName(CompilationUnit unit)
    {
        return unit.Namespace?.Name
            ?? unit.Package?.Name
            ?? string.Empty;
    }

    private static string QualifyName(string namespaceName, string name)
    {
        return string.IsNullOrWhiteSpace(namespaceName) || name.Contains('.', StringComparison.Ordinal)
            ? name
            : $"{namespaceName}.{name}";
    }

    private sealed record TopLevelTypeInfo(string Namespace, string SimpleName, string QualifiedName);

    private sealed class Transformer(CompilationUnit unit, IReadOnlyDictionary<string, List<TopLevelTypeInfo>> projectTypes)
    {
        private readonly CompilationUnit _unit = unit;
        private readonly IReadOnlyDictionary<string, List<TopLevelTypeInfo>> _projectTypes = projectTypes;
        private readonly string _namespaceName = GetNamespaceName(unit);
        private readonly HashSet<string> _importedNamespaces = unit.Imports
            .Where(importDirective => importDirective.Alias == null)
            .Select(importDirective => importDirective.Namespace)
            .ToHashSet(StringComparer.Ordinal);

        public CompilationUnit Transform()
        {
            return _unit with
            {
                Declarations = _unit.Declarations.Select(declaration => TransformDeclaration(declaration, isTopLevel: true)).ToList()
            };
        }

        private Declaration TransformDeclaration(Declaration declaration, bool isTopLevel)
        {
            return declaration switch
            {
                ClassDeclaration classDeclaration => classDeclaration with
                {
                    Name = TransformTopLevelTypeName(classDeclaration.Name, isTopLevel),
                    BaseClass = TransformTypeReference(classDeclaration.BaseClass),
                    Interfaces = classDeclaration.Interfaces.Select(typeReference => TransformTypeReference(typeReference)!).ToList(),
                    Members = classDeclaration.Members.Select(member => TransformDeclaration(member, isTopLevel: false)).ToList(),
                    PrimaryConstructorParameters = TransformParameters(classDeclaration.PrimaryConstructorParameters),
                    Attributes = TransformAttributes(classDeclaration.Attributes)
                },
                StructDeclaration structDeclaration => structDeclaration with
                {
                    Name = TransformTopLevelTypeName(structDeclaration.Name, isTopLevel),
                    Interfaces = structDeclaration.Interfaces.Select(typeReference => TransformTypeReference(typeReference)!).ToList(),
                    Members = structDeclaration.Members.Select(member => TransformDeclaration(member, isTopLevel: false)).ToList(),
                    PrimaryConstructorParameters = TransformParameters(structDeclaration.PrimaryConstructorParameters),
                    Attributes = TransformAttributes(structDeclaration.Attributes)
                },
                RecordDeclaration recordDeclaration => recordDeclaration with
                {
                    Name = TransformTopLevelTypeName(recordDeclaration.Name, isTopLevel),
                    Interfaces = recordDeclaration.Interfaces.Select(typeReference => TransformTypeReference(typeReference)!).ToList(),
                    Members = recordDeclaration.Members.Select(member => TransformDeclaration(member, isTopLevel: false)).ToList(),
                    PrimaryConstructorParameters = TransformParameters(recordDeclaration.PrimaryConstructorParameters),
                    Attributes = TransformAttributes(recordDeclaration.Attributes)
                },
                InterfaceDeclaration interfaceDeclaration => interfaceDeclaration with
                {
                    Name = TransformTopLevelTypeName(interfaceDeclaration.Name, isTopLevel),
                    BaseInterfaces = interfaceDeclaration.BaseInterfaces.Select(typeReference => TransformTypeReference(typeReference)!).ToList(),
                    Members = interfaceDeclaration.Members.Select(member => TransformDeclaration(member, isTopLevel: false)).ToList(),
                    Attributes = TransformAttributes(interfaceDeclaration.Attributes)
                },
                UnionDeclaration unionDeclaration => unionDeclaration with
                {
                    Name = TransformTopLevelTypeName(unionDeclaration.Name, isTopLevel),
                    Attributes = TransformAttributes(unionDeclaration.Attributes)
                },
                EnumDeclaration enumDeclaration => enumDeclaration with
                {
                    Name = TransformTopLevelTypeName(enumDeclaration.Name, isTopLevel),
                    Members = enumDeclaration.Members.Select(member => member with { Value = TransformExpression(member.Value) }).ToList(),
                    Attributes = TransformAttributes(enumDeclaration.Attributes)
                },
                NewtypeDeclaration newtypeDeclaration => newtypeDeclaration with
                {
                    Name = TransformTopLevelTypeName(newtypeDeclaration.Name, isTopLevel),
                    UnderlyingType = TransformTypeReference(newtypeDeclaration.UnderlyingType)!
                },
                FunctionDeclaration functionDeclaration => functionDeclaration with
                {
                    Parameters = TransformParameters(functionDeclaration.Parameters) ?? new List<Parameter>(),
                    ReturnType = TransformTypeReference(functionDeclaration.ReturnType),
                    Body = TransformBlock(functionDeclaration.Body),
                    ExpressionBody = TransformExpression(functionDeclaration.ExpressionBody),
                    Attributes = TransformAttributes(functionDeclaration.Attributes)
                },
                FieldDeclaration fieldDeclaration => fieldDeclaration with
                {
                    Type = TransformTypeReference(fieldDeclaration.Type),
                    Initializer = TransformExpression(fieldDeclaration.Initializer),
                    Attributes = TransformAttributes(fieldDeclaration.Attributes)
                },
                PropertyDeclaration propertyDeclaration => propertyDeclaration with
                {
                    Type = TransformTypeReference(propertyDeclaration.Type)!,
                    GetBody = TransformBlock(propertyDeclaration.GetBody),
                    SetBody = TransformBlock(propertyDeclaration.SetBody),
                    ExpressionBody = TransformExpression(propertyDeclaration.ExpressionBody),
                    Attributes = TransformAttributes(propertyDeclaration.Attributes)
                },
                ConstructorDeclaration constructorDeclaration => constructorDeclaration with
                {
                    Parameters = TransformParameters(constructorDeclaration.Parameters) ?? new List<Parameter>(),
                    Body = TransformBlock(constructorDeclaration.Body)!,
                    Initializer = TransformExpression(constructorDeclaration.Initializer),
                    Attributes = TransformAttributes(constructorDeclaration.Attributes)
                },
                IndexerDeclaration indexerDeclaration => indexerDeclaration with
                {
                    Parameters = TransformParameters(indexerDeclaration.Parameters) ?? new List<Parameter>(),
                    Type = TransformTypeReference(indexerDeclaration.Type)!,
                    GetBody = TransformBlock(indexerDeclaration.GetBody),
                    SetBody = TransformBlock(indexerDeclaration.SetBody),
                    Attributes = TransformAttributes(indexerDeclaration.Attributes)
                },
                TypeAliasDeclaration typeAliasDeclaration => typeAliasDeclaration with
                {
                    Type = TransformTypeReference(typeAliasDeclaration.Type)!
                },
                TestDeclaration testDeclaration => testDeclaration with
                {
                    Body = TransformBlock(testDeclaration.Body)!,
                    TableParameters = TransformParameters(testDeclaration.TableParameters),
                    TableCases = testDeclaration.TableCases?.Select(testCase => testCase.Select(expression => TransformExpression(expression)!).ToList()).ToList()
                },
                SetupDeclaration setupDeclaration => setupDeclaration with
                {
                    Body = TransformBlock(setupDeclaration.Body)!
                },
                TeardownDeclaration teardownDeclaration => teardownDeclaration with
                {
                    Body = TransformBlock(teardownDeclaration.Body)!
                },
                _ => declaration
            };
        }

        private string TransformTopLevelTypeName(string name, bool isTopLevel)
        {
            return isTopLevel ? QualifyName(_namespaceName, name) : name;
        }

        private List<Parameter>? TransformParameters(List<Parameter>? parameters)
        {
            return parameters?.Select(parameter => parameter with
            {
                Type = TransformTypeReference(parameter.Type)!,
                DefaultValue = TransformExpression(parameter.DefaultValue),
                Attributes = TransformAttributes(parameter.Attributes)
            }).ToList();
        }

        private List<AttributeNode> TransformAttributes(List<AttributeNode>? attributes)
        {
            return attributes?.Select(attribute => attribute with
            {
                Name = QualifyTypeName(attribute.Name),
                Arguments = attribute.Arguments.Select(argument => argument with { Value = TransformExpression(argument.Value)! }).ToList()
            }).ToList() ?? new List<AttributeNode>();
        }

        private BlockStatement? TransformBlock(BlockStatement? block)
        {
            if (block == null)
            {
                return null;
            }

            return block with
            {
                Statements = block.Statements.Select(TransformStatement).ToList()
            };
        }

        private Statement TransformStatement(Statement statement)
        {
            return statement switch
            {
                ExpressionStatement expressionStatement => expressionStatement with
                {
                    Expression = TransformExpression(expressionStatement.Expression)!
                },
                VariableDeclarationStatement variableDeclaration => variableDeclaration with
                {
                    Type = TransformTypeReference(variableDeclaration.Type),
                    Initializer = TransformExpression(variableDeclaration.Initializer)
                },
                TupleDeconstructionStatement tupleDeconstruction => tupleDeconstruction with
                {
                    Initializer = TransformExpression(tupleDeconstruction.Initializer)!
                },
                BlockStatement blockStatement => TransformBlock(blockStatement)!,
                IfStatement ifStatement => ifStatement with
                {
                    Condition = TransformExpression(ifStatement.Condition)!,
                    ThenStatement = TransformStatement(ifStatement.ThenStatement),
                    ElseStatement = ifStatement.ElseStatement != null ? TransformStatement(ifStatement.ElseStatement) : null
                },
                ForStatement forStatement => forStatement with
                {
                    Initializer = forStatement.Initializer != null ? TransformStatement(forStatement.Initializer) : null,
                    Condition = TransformExpression(forStatement.Condition),
                    Iterator = TransformExpression(forStatement.Iterator),
                    Body = TransformStatement(forStatement.Body)
                },
                ForeachStatement foreachStatement => foreachStatement with
                {
                    Collection = TransformExpression(foreachStatement.Collection)!,
                    Body = TransformStatement(foreachStatement.Body)
                },
                AwaitForEachStatement awaitForEachStatement => awaitForEachStatement with
                {
                    Collection = TransformExpression(awaitForEachStatement.Collection)!,
                    Body = TransformStatement(awaitForEachStatement.Body)
                },
                WhileStatement whileStatement => whileStatement with
                {
                    Condition = TransformExpression(whileStatement.Condition)!,
                    Body = TransformStatement(whileStatement.Body)
                },
                ReturnStatement returnStatement => returnStatement with
                {
                    Value = TransformExpression(returnStatement.Value)
                },
                YieldStatement yieldStatement => yieldStatement with
                {
                    Value = TransformExpression(yieldStatement.Value)
                },
                ThrowStatement throwStatement => throwStatement with
                {
                    Expression = TransformExpression(throwStatement.Expression)!
                },
                TryStatement tryStatement => tryStatement with
                {
                    TryBlock = TransformBlock(tryStatement.TryBlock)!,
                    CatchClauses = tryStatement.CatchClauses.Select(catchClause => catchClause with
                    {
                        ExceptionType = TransformTypeReference(catchClause.ExceptionType),
                        Block = TransformBlock(catchClause.Block)!
                    }).ToList(),
                    FinallyBlock = TransformBlock(tryStatement.FinallyBlock)
                },
                UsingStatement usingStatement => usingStatement with
                {
                    Declaration = usingStatement.Declaration != null ? (VariableDeclarationStatement)TransformStatement(usingStatement.Declaration) : null,
                    Expression = TransformExpression(usingStatement.Expression),
                    Body = usingStatement.Body != null ? TransformStatement(usingStatement.Body) : null
                },
                LockStatement lockStatement => lockStatement with
                {
                    LockObject = TransformExpression(lockStatement.LockObject)!,
                    Body = TransformBlock(lockStatement.Body)!
                },
                SwitchStatement switchStatement => switchStatement with
                {
                    Value = TransformExpression(switchStatement.Value)!,
                    Cases = switchStatement.Cases.Select(@case => @case with
                    {
                        Pattern = TransformPattern(@case.Pattern),
                        Statements = @case.Statements.Select(TransformStatement).ToList()
                    }).ToList()
                },
                PrintStatement printStatement => printStatement with
                {
                    Value = TransformExpression(printStatement.Value)!
                },
                AssertStatement assertStatement => assertStatement with
                {
                    Condition = TransformExpression(assertStatement.Condition)!,
                    Message = TransformExpression(assertStatement.Message)
                },
                AssertThrowsStatement assertThrowsStatement => assertThrowsStatement with
                {
                    ExceptionType = TransformTypeReference(assertThrowsStatement.ExceptionType)!,
                    Body = TransformBlock(assertThrowsStatement.Body)!
                },
                LocalFunctionStatement localFunctionStatement => localFunctionStatement with
                {
                    Function = (FunctionDeclaration)TransformDeclaration(localFunctionStatement.Function, isTopLevel: false)
                },
                _ => statement
            };
        }

        private Expression? TransformExpression(Expression? expression)
        {
            return expression switch
            {
                null => null,
                InterpolatedStringExpression interpolatedString => interpolatedString with
                {
                    Parts = interpolatedString.Parts.Select(TransformInterpolatedPart).ToList()
                },
                BinaryExpression binaryExpression => binaryExpression with
                {
                    Left = TransformExpression(binaryExpression.Left)!,
                    Right = TransformExpression(binaryExpression.Right)!
                },
                UnaryExpression unaryExpression => unaryExpression with
                {
                    Operand = TransformExpression(unaryExpression.Operand)!
                },
                MustExpression mustExpression => mustExpression with
                {
                    Expression = TransformExpression(mustExpression.Expression)!
                },
                MemberAccessExpression memberAccess => memberAccess with
                {
                    Object = TransformExpression(memberAccess.Object)!
                },
                IndexAccessExpression indexAccess => indexAccess with
                {
                    Object = TransformExpression(indexAccess.Object)!,
                    Index = TransformExpression(indexAccess.Index)!
                },
                CallExpression callExpression => callExpression with
                {
                    Callee = TransformExpression(callExpression.Callee)!,
                    Arguments = callExpression.Arguments.Select(argument => argument with
                    {
                        Value = TransformExpression(argument.Value)!
                    }).ToList(),
                    TypeArguments = callExpression.TypeArguments?.Select(typeReference => TransformTypeReference(typeReference)!).ToList()
                },
                AssignmentExpression assignmentExpression => assignmentExpression with
                {
                    Target = TransformExpression(assignmentExpression.Target)!,
                    Value = TransformExpression(assignmentExpression.Value)!
                },
                LambdaExpression lambdaExpression => lambdaExpression with
                {
                    Parameters = TransformParameters(lambdaExpression.Parameters) ?? new List<Parameter>(),
                    ExpressionBody = TransformExpression(lambdaExpression.ExpressionBody),
                    BlockBody = TransformBlock(lambdaExpression.BlockBody)
                },
                TernaryExpression ternaryExpression => ternaryExpression with
                {
                    Condition = TransformExpression(ternaryExpression.Condition)!,
                    ThenExpression = TransformExpression(ternaryExpression.ThenExpression)!,
                    ElseExpression = TransformExpression(ternaryExpression.ElseExpression)!
                },
                ArrayLiteralExpression arrayLiteral => arrayLiteral with
                {
                    Elements = arrayLiteral.Elements.Select(element => TransformExpression(element)!).ToList()
                },
                TupleExpression tupleExpression => tupleExpression with
                {
                    Elements = tupleExpression.Elements.Select(element => element with
                    {
                        Value = TransformExpression(element.Value)!
                    }).ToList()
                },
                ObjectInitializerExpression initializerExpression => initializerExpression with
                {
                    Properties = initializerExpression.Properties.Select(initializer => initializer with
                    {
                        IndexExpression = TransformExpression(initializer.IndexExpression),
                        Value = TransformExpression(initializer.Value)!
                    }).ToList()
                },
                NewExpression newExpression => newExpression with
                {
                    Type = TransformTypeReference(newExpression.Type),
                    ConstructorArguments = newExpression.ConstructorArguments.Select(argument => argument with
                    {
                        Value = TransformExpression(argument.Value)!
                    }).ToList(),
                    Initializer = (ObjectInitializerExpression?)TransformExpression(newExpression.Initializer)
                },
                CastExpression castExpression => castExpression with
                {
                    Expression = TransformExpression(castExpression.Expression)!,
                    TargetType = TransformTypeReference(castExpression.TargetType)!
                },
                IsExpression isExpression => isExpression with
                {
                    Expression = TransformExpression(isExpression.Expression)!,
                    Type = TransformTypeReference(isExpression.Type)!
                },
                MatchExpression matchExpression => matchExpression with
                {
                    Value = TransformExpression(matchExpression.Value)!,
                    Cases = matchExpression.Cases.Select(matchCase => matchCase with
                    {
                        Pattern = TransformPattern(matchCase.Pattern)!,
                        Guard = TransformExpression(matchCase.Guard),
                        Expression = TransformExpression(matchCase.Expression)!
                    }).ToList()
                },
                SpreadExpression spreadExpression => spreadExpression with
                {
                    Expression = TransformExpression(spreadExpression.Expression)!
                },
                WithExpression withExpression => withExpression with
                {
                    Target = TransformExpression(withExpression.Target)!,
                    Properties = withExpression.Properties.Select(initializer => initializer with
                    {
                        IndexExpression = TransformExpression(initializer.IndexExpression),
                        Value = TransformExpression(initializer.Value)!
                    }).ToList()
                },
                AwaitExpression awaitExpression => awaitExpression with
                {
                    Expression = TransformExpression(awaitExpression.Expression)!
                },
                ThrowExpression throwExpression => throwExpression with
                {
                    Expression = TransformExpression(throwExpression.Expression)!
                },
                TypeOfExpression typeOfExpression => typeOfExpression with
                {
                    Type = TransformTypeReference(typeOfExpression.Type)!
                },
                NameofExpression nameofExpression => nameofExpression with
                {
                    Target = TransformExpression(nameofExpression.Target)!
                },
                SizeOfExpression sizeOfExpression => sizeOfExpression with
                {
                    Type = TransformTypeReference(sizeOfExpression.Type)!
                },
                CheckedExpression checkedExpression => checkedExpression with
                {
                    Expression = TransformExpression(checkedExpression.Expression)!
                },
                UncheckedExpression uncheckedExpression => uncheckedExpression with
                {
                    Expression = TransformExpression(uncheckedExpression.Expression)!
                },
                ParenthesizedExpression parenthesizedExpression => parenthesizedExpression with
                {
                    Inner = TransformExpression(parenthesizedExpression.Inner)!
                },
                OutVariableDeclarationExpression outVariableDeclaration => outVariableDeclaration with
                {
                    Type = TransformTypeReference(outVariableDeclaration.Type)
                },
                RangeExpression rangeExpression => rangeExpression with
                {
                    Start = TransformExpression(rangeExpression.Start),
                    End = TransformExpression(rangeExpression.End)
                },
                _ => expression
            };
        }

        private InterpolatedStringPart TransformInterpolatedPart(InterpolatedStringPart part)
        {
            return part switch
            {
                InterpolatedStringHole hole => hole with
                {
                    Expression = TransformExpression(hole.Expression)!
                },
                _ => part
            };
        }

        private Pattern? TransformPattern(Pattern? pattern)
        {
            return pattern switch
            {
                null => null,
                LiteralPattern literalPattern => literalPattern with
                {
                    Literal = TransformExpression(literalPattern.Literal)!
                },
                UnionCasePattern unionCasePattern => unionCasePattern with
                {
                    Properties = unionCasePattern.Properties?.Select(propertyPattern => propertyPattern with
                    {
                        Pattern = TransformPattern(propertyPattern.Pattern)
                    }).ToList()
                },
                RelationalPattern relationalPattern => relationalPattern with
                {
                    Value = TransformExpression(relationalPattern.Value)!
                },
                AndPattern andPattern => andPattern with
                {
                    Left = TransformPattern(andPattern.Left)!,
                    Right = TransformPattern(andPattern.Right)!
                },
                OrPattern orPattern => orPattern with
                {
                    Left = TransformPattern(orPattern.Left)!,
                    Right = TransformPattern(orPattern.Right)!
                },
                NotPattern notPattern => notPattern with
                {
                    Pattern = TransformPattern(notPattern.Pattern)!
                },
                PositionalPattern positionalPattern => positionalPattern with
                {
                    Patterns = positionalPattern.Patterns.Select(candidate => TransformPattern(candidate)!).ToList()
                },
                ObjectPattern objectPattern => objectPattern with
                {
                    Properties = objectPattern.Properties.Select(propertyPattern => propertyPattern with
                    {
                        Pattern = TransformPattern(propertyPattern.Pattern)
                    }).ToList()
                },
                ListPattern listPattern => listPattern with
                {
                    Elements = listPattern.Elements.Select(candidate => TransformPattern(candidate)!).ToList()
                },
                TypePattern typePattern => typePattern with
                {
                    Type = TransformTypeReference(typePattern.Type)!
                },
                _ => pattern
            };
        }

        private TypeReference? TransformTypeReference(TypeReference? typeReference)
        {
            return typeReference switch
            {
                null => null,
                SimpleTypeReference simpleType => simpleType with
                {
                    Name = QualifyTypeName(simpleType.Name)
                },
                GenericTypeReference genericType => genericType with
                {
                    Name = QualifyTypeName(genericType.Name),
                    TypeArguments = genericType.TypeArguments.Select(argument => TransformTypeReference(argument)!).ToList()
                },
                ArrayTypeReference arrayType => arrayType with
                {
                    ElementType = TransformTypeReference(arrayType.ElementType)!
                },
                NullableTypeReference nullableType => nullableType with
                {
                    InnerType = TransformTypeReference(nullableType.InnerType)!
                },
                UnionTypeReference unionType => unionType with
                {
                    Arms = unionType.Arms.Select(arm => TransformTypeReference(arm)!).ToList()
                },
                TupleTypeReference tupleType => tupleType with
                {
                    Elements = tupleType.Elements.Select(element => element with
                    {
                        Type = TransformTypeReference(element.Type)!
                    }).ToList()
                },
                FunctionTypeReference functionType => functionType with
                {
                    ParameterTypes = functionType.ParameterTypes.Select(typeReference => TransformTypeReference(typeReference)!).ToList(),
                    ReturnType = TransformTypeReference(functionType.ReturnType)!
                },
                _ => typeReference
            };
        }

        private string QualifyTypeName(string name)
        {
            if (string.IsNullOrWhiteSpace(name) || name.Contains('.', StringComparison.Ordinal))
            {
                return name;
            }

            if (!_projectTypes.TryGetValue(name, out var candidates))
            {
                return name;
            }

            var scopedCandidates = candidates
                .Where(candidate =>
                    string.Equals(candidate.Namespace, _namespaceName, StringComparison.Ordinal)
                    || _importedNamespaces.Contains(candidate.Namespace))
                .ToList();

            if (scopedCandidates.Count == 1)
            {
                return scopedCandidates[0].QualifiedName;
            }

            if (scopedCandidates.Count == 0 && candidates.Count == 1)
            {
                return candidates[0].QualifiedName;
            }

            return name;
        }
    }
}
