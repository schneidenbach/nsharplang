using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CompilerTypeInfo = NSharpLang.Compiler.TypeInfo;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles signature help (parameter info when typing method calls).
/// Supports both .NET types (via reflection) and user-defined N# functions (via AST).
/// </summary>
public class SignatureHelpHandler : SignatureHelpHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly XmlDocReader _xmlDocReader;
    private readonly ILogger<SignatureHelpHandler> _logger;

    public SignatureHelpHandler(
        DocumentManager documentManager,
        TypeResolver typeResolver,
        XmlDocReader xmlDocReader,
        ILogger<SignatureHelpHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
        _xmlDocReader = xmlDocReader;
        _logger = logger;
    }

    public override Task<SignatureHelp?> Handle(SignatureHelpParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<SignatureHelp?>(null);
        }

        try
        {
            var lines = doc.Text.Split('\n');
            if (request.Position.Line >= lines.Length)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            var lineText = lines[request.Position.Line];
            var beforeCursor = lineText.Substring(0, Math.Min(request.Position.Character, lineText.Length));

            _logger.LogDebug("Signature help for: {Text}", beforeCursor);

            var callInfo = ExtractMethodCall(beforeCursor);
            if (callInfo == null)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            var argumentText = beforeCursor.Substring(beforeCursor.LastIndexOf('(') + 1);
            var activeParameter = CountCommas(argumentText);
            var argumentCount = GetArgumentCount(argumentText);

            // Constructor call (new TypeName(...)) — look up constructors for the type
            if (callInfo.Value.IsConstructor)
            {
                var ctorSignatures = BuildNSharpConstructorSignatures(doc, callInfo.Value.MethodName);
                if (ctorSignatures.Count > 0)
                {
                    _logger.LogDebug("Found N# constructor for {Type} with {Count} signature(s)",
                        callInfo.Value.MethodName, ctorSignatures.Count);

                    return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                        ctorSignatures,
                        activeParameter,
                        argumentCount));
                }

                // Fall back to reflection for .NET types
                var ctorType = _typeResolver.ResolveType(callInfo.Value.MethodName);
                if (ctorType != null)
                {
                    var reflectionCtors = BuildReflectionConstructorSignatures(ctorType);
                    if (reflectionCtors != null && reflectionCtors.Count > 0)
                    {
                        return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                            reflectionCtors,
                            activeParameter,
                            argumentCount));
                    }
                }

                return Task.FromResult<SignatureHelp?>(null);
            }

            // Bare function call (no dot) — try N# function lookup first
            if (callInfo.Value.TypeName == null)
            {
                var nsharpSignatures = BuildNSharpFunctionSignatures(doc, callInfo.Value.MethodName);
                if (nsharpSignatures.Count > 0)
                {
                    _logger.LogDebug("Found N# function: {Name} with {Count} signature(s)",
                        callInfo.Value.MethodName, nsharpSignatures.Count);

                    return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                        nsharpSignatures,
                        activeParameter,
                        argumentCount));
                }

                return Task.FromResult<SignatureHelp?>(null);
            }

            // Dot-qualified call — resolve the receiver as a value first, then as a type.
            var typeName = callInfo.Value.TypeName;
            var methodName = callInfo.Value.MethodName;

            _logger.LogDebug("Method call: {Type}.{Method}", typeName, methodName);

            var signatures = ResolveMemberSignatures(
                doc,
                typeName,
                methodName,
                request.Position.Line,
                request.Position.Character);
            if (signatures.Count == 0)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            return Task.FromResult<SignatureHelp?>(CreateSignatureHelp(
                signatures,
                activeParameter,
                argumentCount));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error providing signature help");
            return Task.FromResult<SignatureHelp?>(null);
        }
    }

    protected override SignatureHelpRegistrationOptions CreateRegistrationOptions(
        SignatureHelpCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SignatureHelpRegistrationOptions
        {
            TriggerCharacters = new Container<string>("(", ",")
        };
    }

    /// <summary>
    /// Build signatures for a user-defined N# function.
    /// Checks the AST for top-level functions, then falls back to SymbolsInfo
    /// (which includes local functions extracted by DocumentManager).
    /// </summary>
    private List<SignatureInformation> BuildNSharpFunctionSignatures(DocumentState doc, string functionName)
    {
        var signatures = new List<SignatureInformation>();

        // First, check top-level function declarations in the AST
        if (doc.CompilationUnit != null)
        {
            Models.SymbolInfo? symbolInfo = null;
            doc.SymbolsInfo?.TryGetValue(functionName, out symbolInfo);
            foreach (var funcDecl in FindTopLevelFunctions(doc.CompilationUnit, functionName))
            {
                signatures.Add(BuildSignatureFromDeclaration(funcDecl, symbolInfo?.Documentation));
            }
        }

        // Fall back to SymbolsInfo which also includes local functions
        if (signatures.Count == 0 && doc.SymbolsInfo != null)
        {
            if (doc.SymbolsInfo.TryGetValue(functionName, out var symbolInfo) &&
                symbolInfo.Kind == Models.SymbolKind.Function)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(symbolInfo));
            }
        }

        return signatures;
    }

    /// <summary>
    /// Build signatures for constructors of a user-defined N# type.
    /// </summary>
    private List<SignatureInformation> BuildNSharpConstructorSignatures(DocumentState doc, string typeName)
    {
        var signatures = new List<SignatureInformation>();

        if (doc.SymbolsInfo == null)
        {
            return signatures;
        }

        if (!doc.SymbolsInfo.TryGetValue(typeName, out var typeSymbol))
        {
            return signatures;
        }

        if (typeSymbol.Kind is not (Models.SymbolKind.Class or Models.SymbolKind.Struct
            or Models.SymbolKind.Record))
        {
            return signatures;
        }

        foreach (var member in typeSymbol.Members)
        {
            if (member.Kind == Models.SymbolKind.Constructor)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(member));
            }
        }

        return signatures;
    }

    /// <summary>
    /// Build signatures for .NET type constructors via reflection.
    /// </summary>
    private List<SignatureInformation>? BuildReflectionConstructorSignatures(Type type)
    {
        var constructors = type.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
        if (constructors.Length == 0) return null;

        var signatures = new List<SignatureInformation>();
        foreach (var ctor in constructors)
        {
            var parameters = ctor.GetParameters();
            var paramInfos = new List<ParameterInformation>();
            var documentation = _xmlDocReader.GetConstructorDocumentationInfo(ctor);

            foreach (var param in parameters)
            {
                var paramType = FormatTypeName(param.ParameterType);
                paramInfos.Add(new ParameterInformation
                {
                    Label = $"{param.Name}: {paramType}",
                    Documentation = CreateDocumentationMarkup(
                        documentation?.GetParameterDocumentation(param.Name))
                });
            }

            var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
            var label = $"new {type.Name}({paramList})";

            signatures.Add(new SignatureInformation
            {
                Label = label,
                Documentation = CreateDocumentationMarkup(documentation?.Summary),
                Parameters = new Container<ParameterInformation>(paramInfos)
            });
        }

        return signatures;
    }

    /// <summary>
    /// Build signatures for a method on a user-defined N# type.
    /// </summary>
    private List<SignatureInformation> BuildNSharpMemberSignatures(DocumentState doc, string typeName, string methodName)
    {
        var signatures = new List<SignatureInformation>();

        if (doc.SymbolsInfo == null)
        {
            return signatures;
        }

        if (!doc.SymbolsInfo.TryGetValue(typeName, out var typeSymbol))
        {
            return signatures;
        }

        // Only look at type symbols that have members
        if (typeSymbol.Kind is not (Models.SymbolKind.Class or Models.SymbolKind.Struct
            or Models.SymbolKind.Record or Models.SymbolKind.Interface))
        {
            return signatures;
        }

        foreach (var member in typeSymbol.Members)
        {
            if (member.Name == methodName &&
                member.Kind is Models.SymbolKind.Method or Models.SymbolKind.Function or Models.SymbolKind.Constructor)
            {
                signatures.Add(BuildSignatureFromSymbolInfo(member));
            }
        }

        return signatures;
    }

    /// <summary>
    /// Resolve signature help for a dot-qualified call. Simple identifiers are
    /// checked as in-scope values before type names so `message.Contains(` uses
    /// string instance overloads while `String.Format(` uses static overloads.
    /// </summary>
    private List<SignatureInformation> ResolveMemberSignatures(
        DocumentState doc,
        string receiverName,
        string methodName,
        int lspLine,
        int lspCharacter)
    {
        if (TryLookupReceiverTypeInfo(doc, receiverName, lspLine, lspCharacter, out var receiverTypeInfo))
        {
            var nsharpTypeName = GetNSharpTypeName(doc, receiverTypeInfo);
            if (nsharpTypeName != null)
            {
                var nsharpInstanceSignatures = BuildNSharpMemberSignatures(doc, nsharpTypeName, methodName);
                if (nsharpInstanceSignatures.Count > 0)
                {
                    _logger.LogDebug("Resolved receiver '{Receiver}' as N# type '{Type}'",
                        receiverName, nsharpTypeName);
                    return nsharpInstanceSignatures;
                }
            }

            var clrReceiverType = ResolveClrType(receiverTypeInfo);
            if (clrReceiverType != null)
            {
                var instanceSignatures = BuildReflectionSignatures(
                    clrReceiverType,
                    methodName,
                    MemberAccessMode.InstanceOnly,
                    TryGetSelectedReflectionMethod(doc, methodName, lspLine, lspCharacter));
                if (instanceSignatures.Count > 0)
                {
                    _logger.LogDebug("Resolved receiver '{Receiver}' as CLR instance type '{Type}'",
                        receiverName, clrReceiverType.FullName);
                    return instanceSignatures;
                }
            }
        }

        // Direct N# type access, e.g. Person.Create(
        var nsharpMemberSignatures = BuildNSharpMemberSignatures(doc, receiverName, methodName);
        if (nsharpMemberSignatures.Count > 0)
        {
            return nsharpMemberSignatures;
        }

        // Static .NET type access, e.g. Console.WriteLine( or System.String.Format(
        var staticType = _typeResolver.ResolveType(receiverName);
        if (staticType == null)
        {
            _logger.LogDebug("Could not resolve receiver: {Receiver}", receiverName);
            return new List<SignatureInformation>();
        }

        return BuildReflectionSignatures(
            staticType,
            methodName,
            MemberAccessMode.StaticOnly,
            TryGetSelectedReflectionMethod(doc, methodName, lspLine, lspCharacter));
    }

    private bool TryLookupReceiverTypeInfo(
        DocumentState doc,
        string receiverName,
        int lspLine,
        int lspCharacter,
        out CompilerTypeInfo receiverTypeInfo)
    {
        receiverTypeInfo = null!;

        if (doc.SemanticModel == null || !IsValidIdentifier(receiverName))
        {
            return false;
        }

        // SemanticModel stores source positions as 1-based coordinates.
        var typeInfo = doc.SemanticModel.LookupIdentifierAtPosition(receiverName, lspLine + 1, lspCharacter + 1)
                       ?? doc.SemanticModel.LookupIdentifier(receiverName);

        if (typeInfo == null)
        {
            return false;
        }

        receiverTypeInfo = typeInfo;
        return true;
    }

    private Type? ResolveClrType(CompilerTypeInfo typeInfo)
    {
        return typeInfo switch
        {
            ReflectionTypeInfo reflectionType => reflectionType.Type,
            _ => _typeResolver.ResolveType(typeInfo.ToString())
        };
    }

    private static MethodInfo? TryGetSelectedReflectionMethod(
        DocumentState doc,
        string methodName,
        int lspLine,
        int lspCharacter)
    {
        if (doc.CompilationUnit == null || doc.SemanticModel == null)
        {
            return null;
        }

        CallExpression? bestCall = null;

        void ConsiderCall(CallExpression call)
        {
            if (call.Callee is not MemberAccessExpression memberAccess
                || memberAccess.MemberName != methodName
                || !IsBeforeOrAt(call.Line, call.Column, lspLine, lspCharacter))
            {
                return;
            }

            if (bestCall == null || IsAfter(call.Line, call.Column, bestCall.Line, bestCall.Column))
            {
                bestCall = call;
            }
        }

        void VisitDeclaration(Declaration declaration)
        {
            switch (declaration)
            {
                case FunctionDeclaration function:
                    if (function.Body != null) VisitStatement(function.Body);
                    if (function.ExpressionBody != null) VisitExpression(function.ExpressionBody);
                    break;
                case ClassDeclaration cls:
                    foreach (var member in cls.Members) VisitDeclaration(member);
                    break;
                case StructDeclaration str:
                    foreach (var member in str.Members) VisitDeclaration(member);
                    break;
                case RecordDeclaration record:
                    foreach (var member in record.Members) VisitDeclaration(member);
                    break;
            }
        }

        void VisitStatement(Statement statement)
        {
            switch (statement)
            {
                case BlockStatement block:
                    foreach (var child in block.Statements) VisitStatement(child);
                    break;
                case ExpressionStatement expressionStatement:
                    VisitExpression(expressionStatement.Expression);
                    break;
                case VariableDeclarationStatement variableDeclaration:
                    if (variableDeclaration.Initializer != null) VisitExpression(variableDeclaration.Initializer);
                    break;
                case ReturnStatement returnStatement:
                    if (returnStatement.Value != null) VisitExpression(returnStatement.Value);
                    break;
                case IfStatement ifStatement:
                    VisitExpression(ifStatement.Condition);
                    VisitStatement(ifStatement.ThenStatement);
                    if (ifStatement.ElseStatement != null) VisitStatement(ifStatement.ElseStatement);
                    break;
                case ForeachStatement foreachStatement:
                    VisitExpression(foreachStatement.Collection);
                    VisitStatement(foreachStatement.Body);
                    break;
            }
        }

        void VisitExpression(Expression expression)
        {
            switch (expression)
            {
                case CallExpression call:
                    ConsiderCall(call);
                    VisitExpression(call.Callee);
                    foreach (var argument in call.Arguments) VisitExpression(argument.Value);
                    break;
                case MemberAccessExpression memberAccess:
                    VisitExpression(memberAccess.Object);
                    break;
                case BinaryExpression binary:
                    VisitExpression(binary.Left);
                    VisitExpression(binary.Right);
                    break;
                case UnaryExpression unary:
                    VisitExpression(unary.Operand);
                    break;
                case AssignmentExpression assignment:
                    VisitExpression(assignment.Target);
                    VisitExpression(assignment.Value);
                    break;
                case LambdaExpression lambda:
                    if (lambda.ExpressionBody != null) VisitExpression(lambda.ExpressionBody);
                    if (lambda.BlockBody != null) VisitStatement(lambda.BlockBody);
                    break;
                case ArrayLiteralExpression array:
                    foreach (var element in array.Elements) VisitExpression(element);
                    break;
                case ParenthesizedExpression parenthesized:
                    VisitExpression(parenthesized.Inner);
                    break;
            }
        }

        foreach (var declaration in doc.CompilationUnit.Declarations)
        {
            VisitDeclaration(declaration);
        }

        return bestCall != null
            ? doc.SemanticModel.LookupReflectionCallTarget(bestCall.Line, bestCall.Column)
            : null;

        static bool IsBeforeOrAt(int line, int column, int targetLine, int targetColumn)
        {
            var zeroBasedLine = Math.Max(0, line - 1);
            var zeroBasedColumn = Math.Max(0, column - 1);
            return zeroBasedLine < targetLine
                || (zeroBasedLine == targetLine && zeroBasedColumn <= targetColumn);
        }

        static bool IsAfter(int line, int column, int otherLine, int otherColumn)
        {
            return line > otherLine || (line == otherLine && column > otherColumn);
        }
    }

    private static string? GetNSharpTypeName(DocumentState doc, CompilerTypeInfo typeInfo)
    {
        var typeName = typeInfo switch
        {
            ClassTypeInfo classType => classType.Declaration.Name,
            StructTypeInfo structType => structType.Declaration.Name,
            RecordTypeInfo recordType => recordType.Declaration.Name,
            InterfaceTypeInfo interfaceType => interfaceType.Declaration.Name,
            _ => typeInfo.ToString()
        };

        if (doc.SymbolsInfo?.TryGetValue(typeName, out var symbolInfo) == true &&
            symbolInfo.Kind is Models.SymbolKind.Class or Models.SymbolKind.Struct
                or Models.SymbolKind.Record or Models.SymbolKind.Interface)
        {
            return typeName;
        }

        return null;
    }

    /// <summary>
    /// Build signatures for .NET types via reflection.
    /// </summary>
    private List<SignatureInformation> BuildReflectionSignatures(
        Type type,
        string methodName,
        MemberAccessMode mode,
        MethodInfo? selectedMethod = null)
    {
        var bindingFlags = BindingFlags.Public;
        bindingFlags |= mode switch
        {
            MemberAccessMode.StaticOnly => BindingFlags.Static,
            MemberAccessMode.InstanceOnly => BindingFlags.Instance,
            _ => BindingFlags.Static | BindingFlags.Instance
        };

        var methods = type.GetMethods(bindingFlags)
            .Where(m => m.Name == methodName && !m.IsSpecialName)
            .OrderByDescending(m => selectedMethod != null && ReflectionMethodIdentity.MethodsMatch(m, selectedMethod))
            .ThenBy(m => m.GetParameters().Length)
            .ThenBy(m => string.Join(",", m.GetParameters().Select(p => p.ParameterType.FullName)))
            .ToList();

        if (!methods.Any())
        {
            _logger.LogDebug("No methods found with name: {Method}", methodName);
            return new List<SignatureInformation>();
        }

        var signatures = new List<SignatureInformation>();
        foreach (var method in methods)
        {
            var parameters = method.GetParameters();
            var paramInfos = new List<ParameterInformation>();
            var documentation = _xmlDocReader.GetMethodDocumentationInfo(method);

            foreach (var param in parameters)
            {
                var paramType = FormatTypeName(param.ParameterType);
                var paramLabel = $"{param.Name}: {paramType}";

                paramInfos.Add(new ParameterInformation
                {
                    Label = paramLabel,
                    Documentation = CreateDocumentationMarkup(
                        documentation?.GetParameterDocumentation(param.Name))
                });
            }

            var returnType = FormatTypeName(method.ReturnType);
            var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
            var label = $"{method.Name}({paramList}): {returnType}";

            signatures.Add(new SignatureInformation
            {
                Label = label,
                Documentation = CreateDocumentationMarkup(documentation?.Summary),
                Parameters = new Container<ParameterInformation>(paramInfos)
            });
        }

        return signatures;
    }

    private SignatureHelp CreateSignatureHelp(
        List<SignatureInformation> signatures,
        int activeParameter,
        int argumentCount)
    {
        return new SignatureHelp
        {
            Signatures = new Container<SignatureInformation>(signatures),
            ActiveSignature = SelectActiveSignature(signatures, argumentCount),
            ActiveParameter = activeParameter
        };
    }

    private static int SelectActiveSignature(List<SignatureInformation> signatures, int argumentCount)
    {
        if (signatures.Count == 0)
        {
            return 0;
        }

        var exactArity = signatures.FindIndex(signature => GetParameterCount(signature) == argumentCount);
        if (exactArity >= 0)
        {
            return exactArity;
        }

        var canStillAcceptArguments = signatures.FindIndex(signature => GetParameterCount(signature) > argumentCount);
        return canStillAcceptArguments >= 0 ? canStillAcceptArguments : 0;
    }

    private static int GetParameterCount(SignatureInformation signature)
    {
        return signature.Parameters?.Count() ?? 0;
    }

    /// <summary>
    /// Build a SignatureInformation from an N# FunctionDeclaration AST node.
    /// </summary>
    private SignatureInformation BuildSignatureFromDeclaration(FunctionDeclaration funcDecl, string? documentation = null)
    {
        var paramInfos = new List<ParameterInformation>();

        foreach (var param in funcDecl.Parameters)
        {
            var paramType = FormatTypeReference(param.Type);
            var paramLabel = FormatParameterLabel(param.Name, paramType, param.Modifier, param.DefaultValue != null);

            paramInfos.Add(new ParameterInformation
            {
                Label = paramLabel
            });
        }

        var returnType = funcDecl.ReturnType != null
            ? FormatTypeReference(funcDecl.ReturnType)
            : "void";
        var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
        var label = $"{funcDecl.Name}({paramList}): {returnType}";

        return new SignatureInformation
        {
            Label = label,
            Documentation = CreateDocumentationMarkup(documentation),
            Parameters = new Container<ParameterInformation>(paramInfos)
        };
    }

    /// <summary>
    /// Build a SignatureInformation from a SymbolInfo (for N# type members).
    /// </summary>
    private SignatureInformation BuildSignatureFromSymbolInfo(Models.SymbolInfo symbolInfo)
    {
        var paramInfos = new List<ParameterInformation>();

        foreach (var param in symbolInfo.Parameters)
        {
            var paramLabel = $"{param.Name}: {param.TypeName}";
            paramInfos.Add(new ParameterInformation
            {
                Label = paramLabel
            });
        }

        var returnType = symbolInfo.TypeName ?? "void";
        var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
        var label = $"{symbolInfo.Name}({paramList}): {returnType}";

        return new SignatureInformation
        {
            Label = label,
            Documentation = CreateDocumentationMarkup(symbolInfo.Documentation),
            Parameters = new Container<ParameterInformation>(paramInfos)
        };
    }

    private static MarkupContent? CreateDocumentationMarkup(string? documentation)
    {
        return string.IsNullOrWhiteSpace(documentation)
            ? null
            : new MarkupContent
            {
                Kind = MarkupKind.Markdown,
                Value = documentation
            };
    }

    /// <summary>
    /// Find top-level FunctionDeclaration nodes matching a given name in the compilation unit.
    /// Does not search class/struct members (those are resolved via BuildNSharpMemberSignatures).
    /// </summary>
    private static IEnumerable<FunctionDeclaration> FindTopLevelFunctions(CompilationUnit unit, string name)
    {
        foreach (var decl in unit.Declarations)
        {
            if (decl is FunctionDeclaration func && func.Name == name)
            {
                yield return func;
            }
        }
    }

    /// <summary>
    /// Extract method call information from text before cursor.
    /// Returns (null, functionName) for bare function calls, or (typeName, methodName) for dot-qualified calls.
    /// </summary>
    private (string? TypeName, string MethodName, bool IsConstructor)? ExtractMethodCall(string text)
    {
        // Find the opening parenthesis
        var openParenIndex = text.LastIndexOf('(');
        if (openParenIndex < 0)
        {
            return null;
        }

        var beforeParen = text.Substring(0, openParenIndex).TrimEnd();

        // Extract identifier (method name)
        var parts = beforeParen.Split(new[] { ' ', '\t', '(', ')', '[', ']', '{', '}', ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            return null;
        }

        var lastPart = parts[parts.Length - 1];

        // Check if it's a constructor call: "new TypeName("
        if (parts.Length >= 2 && parts[parts.Length - 2] == "new" && IsValidIdentifier(lastPart))
        {
            return (null, lastPart, IsConstructor: true);
        }

        // Check if it's a member call (Type.Method)
        if (lastPart.Contains('.'))
        {
            var dotIndex = lastPart.LastIndexOf('.');
            var typeName = lastPart.Substring(0, dotIndex);
            var methodName = lastPart.Substring(dotIndex + 1);
            return (typeName, methodName, IsConstructor: false);
        }

        // Bare function call — return with null TypeName
        if (IsValidIdentifier(lastPart))
        {
            return (null, lastPart, IsConstructor: false);
        }

        return null;
    }

    /// <summary>
    /// Check if a string is a valid N# identifier.
    /// </summary>
    private static bool IsValidIdentifier(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return false;
        }

        if (!char.IsLetter(text[0]) && text[0] != '_')
        {
            return false;
        }

        for (var i = 1; i < text.Length; i++)
        {
            if (!char.IsLetterOrDigit(text[i]) && text[i] != '_')
            {
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// Count commas in parameter list to determine active parameter.
    /// </summary>
    private int CountCommas(string text)
    {
        var count = 0;
        var depth = 0;
        var inString = false;
        var inChar = false;
        var escaped = false;

        foreach (var ch in text)
        {
            if (inString)
            {
                if (escaped)
                {
                    escaped = false;
                }
                else if (ch == '\\')
                {
                    escaped = true;
                }
                else if (ch == '"')
                {
                    inString = false;
                }

                continue;
            }

            if (inChar)
            {
                if (escaped)
                {
                    escaped = false;
                }
                else if (ch == '\\')
                {
                    escaped = true;
                }
                else if (ch == '\'')
                {
                    inChar = false;
                }

                continue;
            }

            switch (ch)
            {
                case '"':
                    inString = true;
                    break;
                case '\'':
                    inChar = true;
                    break;
                case '(':
                case '[':
                case '<':
                    depth++;
                    break;
                case ')':
                case ']':
                case '>':
                    if (depth > 0) depth--;
                    break;
                case ',':
                    if (depth == 0)
                    {
                        count++;
                    }
                    break;
            }
        }

        return count;
    }

    private int GetArgumentCount(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return 0;
        }

        return CountCommas(text) + 1;
    }

    /// <summary>
    /// Format a parameter label with modifier prefix if applicable.
    /// </summary>
    private static string FormatParameterLabel(string name, string typeName, Compiler.Ast.ParameterModifier modifier, bool hasDefault)
    {
        var prefix = modifier switch
        {
            Compiler.Ast.ParameterModifier.Ref => "ref ",
            Compiler.Ast.ParameterModifier.Out => "out ",
            Compiler.Ast.ParameterModifier.Params => "params ",
            _ => ""
        };

        return $"{prefix}{name}: {typeName}";
    }

    /// <summary>
    /// Format an N# TypeReference for display using CodeIntelligenceService.
    /// </summary>
    private static string FormatTypeReference(TypeReference? typeRef)
    {
        return CodeIntelligenceService.FormatTypeReferencePublic(typeRef);
    }

    /// <summary>
    /// Format a .NET System.Type for display.
    /// </summary>
    private string FormatTypeName(Type type)
    {
        if (type.IsGenericType)
        {
            var genericType = type.GetGenericTypeDefinition();
            var genericArgs = type.GetGenericArguments();
            var typeName = genericType.Name;

            // Remove `1, `2, etc. from generic type names
            var backtickIndex = typeName.IndexOf('`');
            if (backtickIndex > 0)
            {
                typeName = typeName.Substring(0, backtickIndex);
            }

            var argNames = string.Join(", ", genericArgs.Select(FormatTypeName));
            return $"{typeName}<{argNames}>";
        }

        // Use simple names for common types
        return type.Name switch
        {
            "SByte" => "sbyte",
            "Byte" => "byte",
            "Int16" => "short",
            "UInt16" => "ushort",
            "Int32" => "int",
            "UInt32" => "uint",
            "Int64" => "long",
            "UInt64" => "ulong",
            "Single" => "float",
            "Double" => "double",
            "Decimal" => "decimal",
            "Boolean" => "bool",
            "Char" => "char",
            "String" => "string",
            "Void" => "void",
            "Object" => "object",
            _ => type.Name
        };
    }
}
