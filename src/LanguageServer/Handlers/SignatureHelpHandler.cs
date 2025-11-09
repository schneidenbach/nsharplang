using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace LanguageServer.Handlers;

/// <summary>
/// Handles signature help (parameter info when typing method calls)
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

            // Find the method call
            var methodInfo = ExtractMethodCall(beforeCursor);
            if (methodInfo == null)
            {
                return Task.FromResult<SignatureHelp?>(null);
            }

            _logger.LogDebug("Method call: {Type}.{Method}", methodInfo.Value.TypeName, methodInfo.Value.MethodName);

            // Try to resolve the type
            var type = _typeResolver.ResolveType(methodInfo.Value.TypeName);
            if (type == null)
            {
                _logger.LogDebug("Could not resolve type: {Type}", methodInfo.Value.TypeName);
                return Task.FromResult<SignatureHelp?>(null);
            }

            // Get method overloads
            var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)
                .Where(m => m.Name == methodInfo.Value.MethodName && !m.IsSpecialName)
                .ToList();

            if (!methods.Any())
            {
                _logger.LogDebug("No methods found with name: {Method}", methodInfo.Value.MethodName);
                return Task.FromResult<SignatureHelp?>(null);
            }

            // Convert to signature information
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
                        Documentation = null // Will be populated from XML docs later
                    });
                }

                var returnType = FormatTypeName(method.ReturnType);
                var paramList = string.Join(", ", paramInfos.Select(p => p.Label));
                var label = $"{method.Name}({paramList}): {returnType}";

                signatures.Add(new SignatureInformation
                {
                    Label = label,
                    Documentation = null, // Will be populated from XML docs later
                    Parameters = new Container<ParameterInformation>(paramInfos)
                });
            }

            // Determine active parameter based on comma count
            var activeParameter = CountCommas(beforeCursor.Substring(beforeCursor.LastIndexOf('(') + 1));

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
    /// Extract method call information from text before cursor
    /// </summary>
    private (string TypeName, string MethodName)? ExtractMethodCall(string text)
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

        // Check if it's a member call (Type.Method)
        if (lastPart.Contains('.'))
        {
            var dotIndex = lastPart.LastIndexOf('.');
            var typeName = lastPart.Substring(0, dotIndex);
            var methodName = lastPart.Substring(dotIndex + 1);
            return (typeName, methodName);
        }

        // Otherwise, it's just a method call (we'd need more context to know the type)
        return null;
    }

    /// <summary>
    /// Count commas in parameter list to determine active parameter
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
    /// Format a type name for display
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
