using System;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles hover information (shows type info when hovering over identifiers)
/// </summary>
public class HoverHandler : HoverHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<HoverHandler> _logger;

    public HoverHandler(DocumentManager documentManager, TypeResolver typeResolver, ILogger<HoverHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
        _logger = logger;
    }

    public override Task<Hover?> Handle(HoverParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Hover?>(null);
        }

        var line = request.Position.Line;
        var character = request.Position.Character;

        _logger.LogDebug("Hover request at {Line}:{Character}", line, character);

        // Get the word at the cursor position for fallback lookup
        var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);

        // Try AST-based resolution first (most precise)
        if (doc.CompilationUnit != null && doc.SemanticModel != null)
        {
            var expression = AstNodeFinder.FindExpressionAtPosition(doc.CompilationUnit, line, character);
            if (expression != null)
            {
                var hover = TryResolveExpression(expression, word, doc);
                if (hover != null)
                {
                    // Ensure Range is set for consistent behavior
                    if (hover.Range == null && !string.IsNullOrWhiteSpace(word))
                    {
                        hover = new Hover
                        {
                            Contents = hover.Contents,
                            Range = GetWordRange(doc.Text, line, character, word)
                        };
                    }
                    return Task.FromResult<Hover?>(hover);
                }
            }
        }

        // Fallback: check semantic model for simple identifiers
        if (!string.IsNullOrWhiteSpace(word) && doc.SemanticModel != null)
        {
            var typeInfo = doc.SemanticModel.LookupIdentifier(word);
            if (typeInfo != null)
            {
                var typeName = typeInfo.ToString();
                _logger.LogDebug("Found '{Word}' in semantic model with type: {TypeName}", word, typeName);

                var systemType = _typeResolver.ResolveType(typeName);
                var markdown = systemType != null
                    ? FormatVariableWithSystemType(word, typeName, systemType)
                    : FormatVariable(word, typeName);

                return Task.FromResult<Hover?>(new Hover
                {
                    Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                    {
                        Kind = MarkupKind.Markdown,
                        Value = markdown
                    }),
                    Range = GetWordRange(doc.Text, line, character, word)
                });
            }
        }

        // Check symbols (type declarations)
        if (!string.IsNullOrWhiteSpace(word) && doc.Symbols != null && doc.Symbols.TryGetValue(word, out var symbolTypeInfo))
        {
            var markdown = FormatTypeInfo(word, symbolTypeInfo);
            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                }),
                Range = GetWordRange(doc.Text, line, character, word)
            });
        }

        // Check for keywords
        if (!string.IsNullOrWhiteSpace(word))
        {
            var keywords = new[]
            {
                "func", "class", "struct", "record", "interface", "enum", "union",
                "match", "async", "await", "yield", "lock", "using", "import", "let"
            };

            if (keywords.Contains(word))
            {
                return Task.FromResult<Hover?>(new Hover
                {
                    Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                    {
                        Kind = MarkupKind.Markdown,
                        Value = $"**{word}** *(keyword)*"
                    }),
                    Range = GetWordRange(doc.Text, line, character, word)
                });
            }

            // Check for primitive types
            var primitiveTypes = new[]
            {
                "int", "long", "float", "double", "bool", "string", "void", "object"
            };

            if (primitiveTypes.Contains(word))
            {
                return Task.FromResult<Hover?>(new Hover
                {
                    Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                    {
                        Kind = MarkupKind.Markdown,
                        Value = $"**{word}** *(primitive type)*"
                    }),
                    Range = GetWordRange(doc.Text, line, character, word)
                });
            }
        }

        return Task.FromResult<Hover?>(null);
    }

    private Hover? TryResolveExpression(Expression expression, string word, DocumentState doc)
    {
        if (doc?.SemanticModel == null) return null;

        var resolver = new ExpressionTypeResolver(doc.SemanticModel);

        switch (expression)
        {
            case IdentifierExpression id:
                return ResolveIdentifier(id.Name, doc);

            case MemberAccessExpression memberAccess:
                return ResolveMemberAccess(memberAccess, resolver);

            case CallExpression call when call.Callee is MemberAccessExpression callMemberAccess:
                return ResolveMethodCall(call, callMemberAccess, resolver, doc);

            default:
                // Try to resolve the expression type generically
                var exprType = resolver.ResolveExpressionType(expression);
                if (exprType != null)
                {
                    return new Hover
                    {
                        Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                        {
                            Kind = MarkupKind.Markdown,
                            Value = FormatType(exprType)
                        })
                    };
                }
                break;
        }

        return null;
    }

    private Hover? ResolveIdentifier(string name, DocumentState doc)
    {
        if (doc?.SemanticModel == null) return null;

        var typeInfo = doc.SemanticModel.LookupIdentifier(name);
        if (typeInfo != null)
        {
            var typeName = typeInfo.ToString();
            var systemType = _typeResolver.ResolveType(typeName);
            var markdown = systemType != null
                ? FormatVariableWithSystemType(name, typeName, systemType)
                : FormatVariable(name, typeName);

            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                })
            };
        }

        return null;
    }

    private Hover? ResolveMemberAccess(MemberAccessExpression memberAccess, ExpressionTypeResolver resolver)
    {
        var memberInfo = TryResolveMemberInfo(memberAccess, resolver);
        if (memberInfo == null) return null;

        string? markdown = memberInfo switch
        {
            MethodInfo method => FormatMethod(method),
            PropertyInfo property => FormatProperty(property),
            FieldInfo field => FormatField(field),
            _ => null
        };

        if (markdown != null)
        {
            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                })
            };
        }

        return null;
    }

    private Hover? ResolveMethodCall(
        CallExpression call,
        MemberAccessExpression memberAccess,
        ExpressionTypeResolver resolver,
        DocumentState doc)
    {
        var memberInfo = doc.SemanticModel?.LookupReflectionCallTarget(call.Line, call.Column)
            ?? TryResolveMemberInfo(memberAccess, resolver);
        if (memberInfo is MethodInfo method)
        {
            var overloads = TryGetMethodOverloads(memberAccess, resolver);
            var markdown = overloads.Length > 1
                ? FormatMethodWithOverloads(method, overloads)
                : FormatMethod(method);

            return new Hover
            {
                Contents = new MarkedStringsOrMarkupContent(new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = markdown
                })
            };
        }

        return null;
    }

    private MemberInfo? TryResolveMemberInfo(MemberAccessExpression memberAccess, ExpressionTypeResolver resolver)
    {
        var resolved = resolver.ResolveMemberInfo(memberAccess);
        if (resolved != null)
        {
            return resolved;
        }

        // Fallback: allow static member resolution on known .NET types like `Console.WriteLine`
        // where `Console` is a type name (not a variable in the semantic model).
        if (memberAccess.Object is IdentifierExpression id)
        {
            var type = _typeResolver.ResolveType(id.Name);
            if (type == null) return null;

            var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;

            var methods = type.GetMethods(bindingFlags)
                .Where(m => m.Name == memberAccess.MemberName)
                .ToArray();
            if (methods.Length > 0) return methods[0];

            var property = type.GetProperty(memberAccess.MemberName, bindingFlags);
            if (property != null) return property;

            var field = type.GetField(memberAccess.MemberName, bindingFlags);
            if (field != null) return field;
        }

        return null;
    }

    private MethodInfo[] TryGetMethodOverloads(MemberAccessExpression memberAccess, ExpressionTypeResolver resolver)
    {
        var overloads = resolver.GetMethodOverloads(memberAccess);
        if (overloads.Length > 0)
        {
            return overloads;
        }

        if (memberAccess.Object is IdentifierExpression id)
        {
            var type = _typeResolver.ResolveType(id.Name);
            if (type == null) return Array.Empty<MethodInfo>();

            return type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                .Where(m => m.Name == memberAccess.MemberName)
                .ToArray();
        }

        return Array.Empty<MethodInfo>();
    }

    protected override HoverRegistrationOptions CreateRegistrationOptions(
        HoverCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new HoverRegistrationOptions
        {
            // DocumentSelector will be set automatically
        };
    }

    private LspRange GetWordRange(string text, int line, int character, string word)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return new LspRange(line, character, line, character);

        var lineText = lines[line];
        var startSearch = Math.Max(0, Math.Min(lineText.Length, character) - word.Length);
        var startChar = lineText.IndexOf(word, startSearch, StringComparison.Ordinal);
        if (startChar < 0) startChar = character;

        return new LspRange(line, startChar, line, startChar + word.Length);
    }

    private string FormatTypeInfo(string name, Compiler.TypeInfo typeInfo)
    {
        var kind = typeInfo switch
        {
            ClassTypeInfo => "class",
            StructTypeInfo => "struct",
            RecordTypeInfo => "record",
            InterfaceTypeInfo => "interface",
            EnumTypeInfo => "enum",
            UnionTypeInfo => "union",
            _ => "type"
        };

        return $"**{name}** *({kind})*\n\n```nsharp\n{kind} {name}\n```";
    }

    private string FormatVariable(string name, string typeName)
    {
        return $"**(variable)** `{name}`\n\n```nsharp\n{name}: {typeName}\n```";
    }

    private string FormatVariableWithSystemType(string name, string typeName, Type systemType)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(variable)** `{name}: {typeName}`");
        sb.AppendLine();
        sb.AppendLine("```nsharp");
        sb.AppendLine($"{name}: {typeName}");
        sb.AppendLine("```");

        // Add namespace info if available
        if (!string.IsNullOrEmpty(systemType.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Namespace:* `{systemType.Namespace}`");
        }

        // Add assembly info
        sb.AppendLine();
        sb.AppendLine($"*Assembly:* `{systemType.Assembly.GetName().Name}`");

        return sb.ToString();
    }

    private string FormatMethod(MethodInfo method)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(method)** `{method.Name}`");
        sb.AppendLine();
        sb.AppendLine("```csharp");
        sb.Append(FormatMethodSignature(method));
        sb.AppendLine("```");

        if (!string.IsNullOrEmpty(method.DeclaringType?.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Declaring Type:* `{method.DeclaringType.FullName}`");
        }

        return sb.ToString();
    }

    private string FormatMethodWithOverloads(MethodInfo primary, MethodInfo[] overloads)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(method)** `{primary.Name}` *({overloads.Length} overloads)*");
        sb.AppendLine();
        sb.AppendLine("```csharp");

        var orderedOverloads = overloads
            .OrderByDescending(overload => ReflectionMethodIdentity.MethodsMatch(overload, primary))
            .ThenBy(overload => overload.GetParameters().Length)
            .ThenBy(overload => string.Join(",", overload.GetParameters().Select(p => p.ParameterType.FullName)))
            .Take(5);

        foreach (var overload in orderedOverloads)
        {
            sb.AppendLine(FormatMethodSignature(overload));
        }

        if (overloads.Length > 5)
        {
            sb.AppendLine($"... and {overloads.Length - 5} more overloads");
        }

        sb.AppendLine("```");

        if (!string.IsNullOrEmpty(primary.DeclaringType?.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Declaring Type:* `{primary.DeclaringType.FullName}`");
        }

        return sb.ToString();
    }

    private string FormatMethodSignature(MethodInfo method)
    {
        var parameters = method.GetParameters();
        var paramList = string.Join(", ", parameters.Select(p =>
            $"{FormatTypeName(p.ParameterType)} {p.Name}"));

        var returnType = FormatTypeName(method.ReturnType);
        return $"{returnType} {method.Name}({paramList})";
    }

    private string FormatProperty(PropertyInfo property)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(property)** `{property.Name}`");
        sb.AppendLine();
        sb.AppendLine("```csharp");

        var accessors = "";
        if (property.CanRead && property.CanWrite)
            accessors = " { get; set; }";
        else if (property.CanRead)
            accessors = " { get; }";
        else if (property.CanWrite)
            accessors = " { set; }";

        sb.AppendLine($"{FormatTypeName(property.PropertyType)} {property.Name}{accessors}");
        sb.AppendLine("```");

        if (!string.IsNullOrEmpty(property.DeclaringType?.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Declaring Type:* `{property.DeclaringType.FullName}`");
        }

        return sb.ToString();
    }

    private string FormatField(FieldInfo field)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(field)** `{field.Name}`");
        sb.AppendLine();
        sb.AppendLine("```csharp");

        var modifiers = "";
        if (field.IsStatic) modifiers = "static ";
        if (field.IsInitOnly) modifiers += "readonly ";

        sb.AppendLine($"{modifiers}{FormatTypeName(field.FieldType)} {field.Name}");
        sb.AppendLine("```");

        if (!string.IsNullOrEmpty(field.DeclaringType?.Namespace))
        {
            sb.AppendLine();
            sb.AppendLine($"*Declaring Type:* `{field.DeclaringType.FullName}`");
        }

        return sb.ToString();
    }

    private string FormatType(Type type)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"**(type)** `{FormatTypeName(type)}`");
        sb.AppendLine();

        if (!string.IsNullOrEmpty(type.Namespace))
        {
            sb.AppendLine($"*Namespace:* `{type.Namespace}`");
        }

        if (type.Assembly != null)
        {
            sb.AppendLine($"*Assembly:* `{type.Assembly.GetName().Name}`");
        }

        return sb.ToString();
    }

    private string FormatTypeName(Type type)
    {
        if (type.IsGenericType)
        {
            var genericArgs = type.GetGenericArguments();
            var typeName = type.Name.Substring(0, type.Name.IndexOf('`'));
            var args = string.Join(", ", genericArgs.Select(FormatTypeName));
            return $"{typeName}<{args}>";
        }

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
