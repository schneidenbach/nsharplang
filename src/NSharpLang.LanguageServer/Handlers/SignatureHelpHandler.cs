using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles signature help (parameter info when typing method calls).
/// Supports both .NET types (via reflection) and user-defined N# functions (via AST).
/// </summary>
public class SignatureHelpHandler : SignatureHelpHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<SignatureHelpHandler> _logger;

    public SignatureHelpHandler(DocumentManager documentManager, TypeResolver typeResolver, ILogger<SignatureHelpHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
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

            var activeParameter = CountCommas(beforeCursor.Substring(beforeCursor.LastIndexOf('(') + 1));

            // Constructor call (new TypeName(...)) — look up constructors for the type
            if (callInfo.Value.IsConstructor)
            {
                var ctorSignatures = BuildNSharpConstructorSignatures(doc, callInfo.Value.MethodName);
                if (ctorSignatures.Count > 0)
                {
                    _logger.LogDebug("Found N# constructor for {Type} with {Count} signature(s)",
                        callInfo.Value.MethodName, ctorSignatures.Count);

                    return Task.FromResult<SignatureHelp?>(new SignatureHelp
                    {
                        Signatures = new Container<SignatureInformation>(ctorSignatures),
                        ActiveSignature = 0,
                        ActiveParameter = activeParameter
                    });
                }

                // Fall back to reflection for .NET types
                var ctorType = _typeResolver.ResolveType(callInfo.Value.MethodName);
                if (ctorType != null)
                {
                    var reflectionCtors = BuildReflectionConstructorSignatures(ctorType);
                    if (reflectionCtors != null && reflectionCtors.Count > 0)
                    {
                        return Task.FromResult<SignatureHelp?>(new SignatureHelp
                        {
                            Signatures = new Container<SignatureInformation>(reflectionCtors),
                            ActiveSignature = 0,
                            ActiveParameter = activeParameter
                        });
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

                    return Task.FromResult<SignatureHelp?>(new SignatureHelp
                    {
                        Signatures = new Container<SignatureInformation>(nsharpSignatures),
                        ActiveSignature = 0,
                        ActiveParameter = activeParameter
                    });
                }

                return Task.FromResult<SignatureHelp?>(null);
            }

            // Dot-qualified call — try N# type members first, then fall back to .NET reflection
            var typeName = callInfo.Value.TypeName;
            var methodName = callInfo.Value.MethodName;

            _logger.LogDebug("Method call: {Type}.{Method}", typeName, methodName);

            var nsharpMemberSignatures = BuildNSharpMemberSignatures(doc, typeName, methodName);
            if (nsharpMemberSignatures.Count > 0)
            {
                return Task.FromResult<SignatureHelp?>(new SignatureHelp
                {
                    Signatures = new Container<SignatureInformation>(nsharpMemberSignatures),
                    ActiveSignature = 0,
                    ActiveParameter = activeParameter
                });
            }

            // Fall back to .NET type resolution via reflection
            var signatures = BuildReflectionSignatures(typeName, methodName);
            if (signatures == null || signatures.Count == 0)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            return Task.FromResult<SignatureHelp?>(new SignatureHelp
            {
                Signatures = new Container<SignatureInformation>(signatures),
                ActiveSignature = 0, // TODO: Choose best overload
                ActiveParameter = activeParameter
            });
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
            foreach (var funcDecl in FindTopLevelFunctions(doc.CompilationUnit, functionName))
            {
                signatures.Add(BuildSignatureFromDeclaration(funcDecl));
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

            foreach (var param in parameters)
            {
                var paramType = FormatTypeName(param.ParameterType);
                paramInfos.Add(new ParameterInformation
                {
                    Label = $"{param.Name}: {paramType}"
                });
            }

            var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
            var label = $"new {type.Name}({paramList})";

            signatures.Add(new SignatureInformation
            {
                Label = label,
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
    /// Build signatures for .NET types via reflection (existing behavior).
    /// </summary>
    private List<SignatureInformation>? BuildReflectionSignatures(string typeName, string methodName)
    {
        var type = _typeResolver.ResolveType(typeName);
        if (type == null)
        {
            _logger.LogDebug("Could not resolve type: {Type}", typeName);
            return null;
        }

        var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)
            .Where(m => m.Name == methodName && !m.IsSpecialName)
            .ToList();

        if (!methods.Any())
        {
            _logger.LogDebug("No methods found with name: {Method}", methodName);
            return null;
        }

        var signatures = new List<SignatureInformation>();
        foreach (var method in methods)
        {
            var parameters = method.GetParameters();
            var paramInfos = new List<ParameterInformation>();

            foreach (var param in parameters)
            {
                var paramType = FormatTypeName(param.ParameterType);
                var paramLabel = $"{param.Name}: {paramType}";

                paramInfos.Add(new ParameterInformation
                {
                    Label = paramLabel,
                    Documentation = null
                });
            }

            var returnType = FormatTypeName(method.ReturnType);
            var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
            var label = $"{method.Name}({paramList}): {returnType}";

            signatures.Add(new SignatureInformation
            {
                Label = label,
                Documentation = null,
                Parameters = new Container<ParameterInformation>(paramInfos)
            });
        }

        return signatures;
    }

    /// <summary>
    /// Build a SignatureInformation from an N# FunctionDeclaration AST node.
    /// </summary>
    private SignatureInformation BuildSignatureFromDeclaration(FunctionDeclaration funcDecl)
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
            Parameters = new Container<ParameterInformation>(paramInfos)
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

        foreach (var ch in text)
        {
            switch (ch)
            {
                case '(':
                case '[':
                case '<':
                    depth++;
                    break;
                case ')':
                case ']':
                case '>':
                    depth--;
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
            "Int32" => "int",
            "Int64" => "long",
            "Single" => "float",
            "Double" => "double",
            "Boolean" => "bool",
            "String" => "string",
            "Void" => "void",
            "Object" => "object",
            _ => type.Name
        };
    }
}
