using System;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterTextKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetNoSymbolsText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return "No symbols found.";

        try
        {
            var text = bindings.QueryNoSymbolsText();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return "No symbols found.";
    }

    internal static string GetSymbolLineText(SymbolResult symbol, int indent)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetSymbolLineTextWithCSharp(symbol, indent);

        try
        {
            var modifiers = symbol.Modifiers ?? Array.Empty<string>();
            var text = bindings.QuerySymbolLineText(
                indent,
                symbol.Kind.ToString(),
                symbol.Name,
                symbol.TypeName ?? string.Empty,
                symbol.TypeName != null ? 1 : 0,
                symbol.File,
                symbol.Line,
                modifiers,
                modifiers.Length);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetSymbolLineTextWithCSharp(symbol, indent);
    }

    internal static string GetSymbolParametersLineText(ParameterResult[] parameters, int indent)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetSymbolParametersLineTextWithCSharp(parameters, indent);

        try
        {
            var count = parameters.Length;
            var names = new string[count];
            var types = new string[count];
            var hasDefaults = new int[count];
            var defaultValues = new string[count];

            for (var i = 0; i < count; i++)
            {
                var parameter = parameters[i];
                names[i] = parameter.Name;
                types[i] = parameter.Type;
                hasDefaults[i] = parameter.HasDefault ? 1 : 0;
                defaultValues[i] = parameter.DefaultValue ?? string.Empty;
            }

            var text = bindings.QuerySymbolParametersLineText(
                indent,
                names,
                types,
                hasDefaults,
                defaultValues,
                count);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetSymbolParametersLineTextWithCSharp(parameters, indent);
    }

    internal static string GetOutlineFileLineText(string file)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetOutlineFileLineTextWithCSharp(file);

        try
        {
            var text = bindings.QueryOutlineFileLineText(file);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetOutlineFileLineTextWithCSharp(file);
    }

    internal static string GetOutlineImportsLineText(string[] imports)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetOutlineImportsLineTextWithCSharp(imports);

        try
        {
            var text = bindings.QueryOutlineImportsLineText(imports, imports.Length);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetOutlineImportsLineTextWithCSharp(imports);
    }

    internal static string GetOutlineEntryLineText(OutlineEntry entry, int indent)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetOutlineEntryLineTextWithCSharp(entry, indent);

        try
        {
            var text = bindings.QueryOutlineEntryLineText(
                indent,
                entry.Kind.ToString(),
                entry.Name,
                entry.ReturnType ?? string.Empty,
                entry.ReturnType != null ? 1 : 0,
                entry.Line,
                entry.EndLine);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetOutlineEntryLineTextWithCSharp(entry, indent);
    }

    internal static string GetTypeLocationHeaderText(string file, int line, int column)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetTypeLocationHeaderTextWithCSharp(file, line, column);

        try
        {
            var text = bindings.QueryTypeLocationHeaderText(file, line, column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetTypeLocationHeaderTextWithCSharp(file, line, column);
    }

    internal static string GetTypeResultLineText(TypeResult result)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetTypeResultLineTextWithCSharp(result);

        try
        {
            var text = bindings.QueryTypeResultLineText(result.Name, result.ResolvedType, result.Kind);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetTypeResultLineTextWithCSharp(result);
    }

    internal static string GetTypeNullabilityLineText(string nullability)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetTypeNullabilityLineTextWithCSharp(nullability);

        try
        {
            var text = bindings.QueryTypeNullabilityLineText(nullability);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetTypeNullabilityLineTextWithCSharp(nullability);
    }

    internal static string GetTypeDefinedAtLineText(LocationResult definition)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetTypeDefinedAtLineTextWithCSharp(definition);

        try
        {
            var text = bindings.QueryTypeDefinedAtLineText(definition.File, definition.Line, definition.Column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetTypeDefinedAtLineTextWithCSharp(definition);
    }

    internal static string GetCompletionsHeaderText(string file, int line, int column, string contextText)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCompletionsHeaderTextWithCSharp(file, line, column, contextText);

        try
        {
            var text = bindings.QueryCompletionsHeaderText(file, line, column, contextText);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCompletionsHeaderTextWithCSharp(file, line, column, contextText);
    }

    internal static string GetCompletionReceiverLineText(string receiver, string? receiverType)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCompletionReceiverLineTextWithCSharp(receiver, receiverType);

        try
        {
            var text = bindings.QueryCompletionReceiverLineText(
                receiver,
                receiverType ?? string.Empty,
                receiverType != null ? 1 : 0);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCompletionReceiverLineTextWithCSharp(receiver, receiverType);
    }

    internal static string GetCompletionCategoryLineText(string category, int count)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCompletionCategoryLineTextWithCSharp(category, count);

        try
        {
            var text = bindings.QueryCompletionCategoryLineText(category, count);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCompletionCategoryLineTextWithCSharp(category, count);
    }

    internal static string GetCompletionItemLineText(CompletionItem item)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCompletionItemLineTextWithCSharp(item);

        try
        {
            var text = bindings.QueryCompletionItemLineText(
                item.Name,
                item.Parameters ?? string.Empty,
                item.Parameters != null ? 1 : 0,
                item.Type ?? string.Empty,
                item.Type != null ? 1 : 0);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCompletionItemLineTextWithCSharp(item);
    }

    internal static string GetCompletionOverflowLineText(int remaining)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetCompletionOverflowLineTextWithCSharp(remaining);

        try
        {
            var text = bindings.QueryCompletionOverflowLineText(remaining);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetCompletionOverflowLineTextWithCSharp(remaining);
    }

    internal static string GetInspectHeaderText(string file, int line, int column)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectHeaderTextWithCSharp(file, line, column);

        try
        {
            var text = bindings.QueryInspectHeaderText(file, line, column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectHeaderTextWithCSharp(file, line, column);
    }

    internal static string GetInspectSymbolLineText(InspectSymbolResult symbol)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectSymbolLineTextWithCSharp(symbol);

        try
        {
            var text = bindings.QueryInspectSymbolLineText(symbol.Name, symbol.Kind);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectSymbolLineTextWithCSharp(symbol);
    }

    internal static string GetInspectNoSymbolText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectNoSymbolTextWithCSharp();

        try
        {
            var text = bindings.QueryInspectNoSymbolText();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectNoSymbolTextWithCSharp();
    }

    internal static string GetInspectTypeLineText(TypeResult type)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectTypeLineTextWithCSharp(type);

        try
        {
            var text = bindings.QueryInspectTypeLineText(type.ResolvedType, type.Kind);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectTypeLineTextWithCSharp(type);
    }

    internal static string GetInspectUnknownTypeText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectUnknownTypeTextWithCSharp();

        try
        {
            var text = bindings.QueryInspectUnknownTypeText();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectUnknownTypeTextWithCSharp();
    }

    internal static string GetInspectDefinitionLineText(DefinitionResult definition)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectDefinitionLineTextWithCSharp(definition);

        try
        {
            var text = bindings.QueryInspectDefinitionLineText(
                definition.Kind,
                definition.Name,
                definition.File,
                definition.Line,
                definition.Column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectDefinitionLineTextWithCSharp(definition);
    }

    internal static string GetInspectNoDefinitionText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectNoDefinitionTextWithCSharp();

        try
        {
            var text = bindings.QueryInspectNoDefinitionText();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectNoDefinitionTextWithCSharp();
    }

    internal static string GetInspectReferencesHeaderText(int count, int definitionCount)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectReferencesHeaderTextWithCSharp(count, definitionCount);

        try
        {
            var text = bindings.QueryInspectReferencesHeaderText(count, definitionCount);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectReferencesHeaderTextWithCSharp(count, definitionCount);
    }

    internal static string GetInspectReferencesOverflowLineText(int remaining)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetInspectReferencesOverflowLineTextWithCSharp(remaining);

        try
        {
            var text = bindings.QueryInspectReferencesOverflowLineText(remaining);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetInspectReferencesOverflowLineTextWithCSharp(remaining);
    }

    internal static string GetHoverHeaderText(string file, int line, int column)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverHeaderTextWithCSharp(file, line, column);

        try
        {
            var text = bindings.QueryHoverHeaderText(file, line, column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverHeaderTextWithCSharp(file, line, column);
    }

    internal static string GetHoverSignatureLineText(string signature)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverSignatureLineTextWithCSharp(signature);

        try
        {
            var text = bindings.QueryHoverSignatureLineText(signature);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverSignatureLineTextWithCSharp(signature);
    }

    internal static string GetHoverKindLineText(string kind)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverKindLineTextWithCSharp(kind);

        try
        {
            var text = bindings.QueryHoverKindLineText(kind);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverKindLineTextWithCSharp(kind);
    }

    internal static string GetHoverDefinedInLineText(string definedIn)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverDefinedInLineTextWithCSharp(definedIn);

        try
        {
            var text = bindings.QueryHoverDefinedInLineText(definedIn);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverDefinedInLineTextWithCSharp(definedIn);
    }

    internal static string GetHoverDocumentationHeaderText()
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverDocumentationHeaderTextWithCSharp();

        try
        {
            var text = bindings.QueryHoverDocumentationHeaderText();
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverDocumentationHeaderTextWithCSharp();
    }

    internal static string GetHoverDocumentationLineText(string docLine)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetHoverDocumentationLineTextWithCSharp(docLine);

        try
        {
            var text = bindings.QueryHoverDocumentationLineText(docLine);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetHoverDocumentationLineTextWithCSharp(docLine);
    }

    internal static string GetNoReferencesText(string symbolName)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetNoReferencesTextWithCSharp(symbolName);

        try
        {
            var text = bindings.QueryNoReferencesText(symbolName);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetNoReferencesTextWithCSharp(symbolName);
    }

    internal static string GetReferencesHeaderText(string symbolName, int count)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetReferencesHeaderTextWithCSharp(symbolName, count);

        try
        {
            var text = bindings.QueryReferencesHeaderText(symbolName, count);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetReferencesHeaderTextWithCSharp(symbolName, count);
    }

    internal static string GetReferenceLineText(ReferenceResult reference)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetReferenceLineTextWithCSharp(reference);

        try
        {
            var text = bindings.QueryReferenceLineText(
                reference.File,
                reference.Line,
                reference.Column,
                reference.IsDefinition ? 1 : 0,
                reference.Context ?? string.Empty,
                reference.Context != null ? 1 : 0);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetReferenceLineTextWithCSharp(reference);
    }

    internal static string GetDefinitionLineText(DefinitionResult definition)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetDefinitionLineTextWithCSharp(definition);

        try
        {
            var text = bindings.QueryDefinitionLineText(
                definition.Kind,
                definition.Name,
                definition.File,
                definition.Line,
                definition.Column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetDefinitionLineTextWithCSharp(definition);
    }

    internal static string GetNoDefinitionsText(string name)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetNoDefinitionsTextWithCSharp(name);

        try
        {
            var text = bindings.QueryNoDefinitionsText(name);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetNoDefinitionsTextWithCSharp(name);
    }

    internal static string GetDefinitionsHeaderText(string name)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetDefinitionsHeaderTextWithCSharp(name);

        try
        {
            var text = bindings.QueryDefinitionsHeaderText(name);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetDefinitionsHeaderTextWithCSharp(name);
    }

    internal static string GetDefinitionSearchResultLineText(DefinitionResult definition)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return GetDefinitionSearchResultLineTextWithCSharp(definition);

        try
        {
            var text = bindings.QueryDefinitionSearchResultLineText(
                definition.Kind,
                definition.Name,
                definition.File,
                definition.Line,
                definition.Column);
            if (!string.IsNullOrEmpty(text))
                return text;
        }
        catch
        {
        }

        return GetDefinitionSearchResultLineTextWithCSharp(definition);
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<QueryNoSymbolsText>(
                programType,
                "QueryNoSymbolsText"),
            DogfoodKernelLoader.CreateDelegate<QuerySymbolLineText>(
                programType,
                "QuerySymbolLineText"),
            DogfoodKernelLoader.CreateDelegate<QuerySymbolParametersLineText>(
                programType,
                "QuerySymbolParametersLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineFileLineText>(
                programType,
                "QueryOutlineFileLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineImportsLineText>(
                programType,
                "QueryOutlineImportsLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineEntryLineText>(
                programType,
                "QueryOutlineEntryLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeLocationHeaderText>(
                programType,
                "QueryTypeLocationHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeResultLineText>(
                programType,
                "QueryTypeResultLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeNullabilityLineText>(
                programType,
                "QueryTypeNullabilityLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeDefinedAtLineText>(
                programType,
                "QueryTypeDefinedAtLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionsHeaderText>(
                programType,
                "QueryCompletionsHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionReceiverLineText>(
                programType,
                "QueryCompletionReceiverLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionCategoryLineText>(
                programType,
                "QueryCompletionCategoryLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionItemLineText>(
                programType,
                "QueryCompletionItemLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionOverflowLineText>(
                programType,
                "QueryCompletionOverflowLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectHeaderText>(
                programType,
                "QueryInspectHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectSymbolLineText>(
                programType,
                "QueryInspectSymbolLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectNoSymbolText>(
                programType,
                "QueryInspectNoSymbolText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectTypeLineText>(
                programType,
                "QueryInspectTypeLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectUnknownTypeText>(
                programType,
                "QueryInspectUnknownTypeText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectDefinitionLineText>(
                programType,
                "QueryInspectDefinitionLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectNoDefinitionText>(
                programType,
                "QueryInspectNoDefinitionText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectReferencesHeaderText>(
                programType,
                "QueryInspectReferencesHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectReferencesOverflowLineText>(
                programType,
                "QueryInspectReferencesOverflowLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverHeaderText>(
                programType,
                "QueryHoverHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverSignatureLineText>(
                programType,
                "QueryHoverSignatureLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverKindLineText>(
                programType,
                "QueryHoverKindLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDefinedInLineText>(
                programType,
                "QueryHoverDefinedInLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDocumentationHeaderText>(
                programType,
                "QueryHoverDocumentationHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDocumentationLineText>(
                programType,
                "QueryHoverDocumentationLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryNoReferencesText>(
                programType,
                "QueryNoReferencesText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferencesHeaderText>(
                programType,
                "QueryReferencesHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferenceLineText>(
                programType,
                "QueryReferenceLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionLineText>(
                programType,
                "QueryDefinitionLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryNoDefinitionsText>(
                programType,
                "QueryNoDefinitionsText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionsHeaderText>(
                programType,
                "QueryDefinitionsHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionSearchResultLineText>(
                programType,
                "QueryDefinitionSearchResultLineText")));

    private delegate string QueryNoSymbolsText();

    private delegate string QuerySymbolLineText(
        int indent,
        string kindText,
        string name,
        string typeName,
        int hasType,
        string fileName,
        int line,
        string[] modifiers,
        int modifierCount);

    private delegate string QuerySymbolParametersLineText(
        int indent,
        string[] names,
        string[] types,
        int[] hasDefaults,
        string[] defaultValues,
        int requestedCount);

    private delegate string QueryOutlineFileLineText(string fileName);

    private delegate string QueryOutlineImportsLineText(string[] imports, int requestedCount);

    private delegate string QueryOutlineEntryLineText(
        int indent,
        string kindText,
        string name,
        string returnType,
        int hasReturnType,
        int line,
        int endLine);

    private delegate string QueryTypeLocationHeaderText(string fileName, int line, int column);

    private delegate string QueryTypeResultLineText(string name, string resolvedType, string kindText);

    private delegate string QueryTypeNullabilityLineText(string nullability);

    private delegate string QueryTypeDefinedAtLineText(string fileName, int line, int column);

    private delegate string QueryCompletionsHeaderText(string fileName, int line, int column, string contextText);

    private delegate string QueryCompletionReceiverLineText(string receiver, string receiverType, int hasReceiverType);

    private delegate string QueryCompletionCategoryLineText(string category, int count);

    private delegate string QueryCompletionItemLineText(
        string name,
        string parameters,
        int hasParameters,
        string typeName,
        int hasType);

    private delegate string QueryCompletionOverflowLineText(int remaining);

    private delegate string QueryInspectHeaderText(string fileName, int line, int column);

    private delegate string QueryInspectSymbolLineText(string name, string kindText);

    private delegate string QueryInspectNoSymbolText();

    private delegate string QueryInspectTypeLineText(string resolvedType, string kindText);

    private delegate string QueryInspectUnknownTypeText();

    private delegate string QueryInspectDefinitionLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private delegate string QueryInspectNoDefinitionText();

    private delegate string QueryInspectReferencesHeaderText(int count, int definitionCount);

    private delegate string QueryInspectReferencesOverflowLineText(int remaining);

    private delegate string QueryHoverHeaderText(string fileName, int line, int column);

    private delegate string QueryHoverSignatureLineText(string signature);

    private delegate string QueryHoverKindLineText(string kindText);

    private delegate string QueryHoverDefinedInLineText(string definedIn);

    private delegate string QueryHoverDocumentationHeaderText();

    private delegate string QueryHoverDocumentationLineText(string docLine);

    private delegate string QueryNoReferencesText(string symbolName);

    private delegate string QueryReferencesHeaderText(string symbolName, int count);

    private delegate string QueryReferenceLineText(
        string fileName,
        int line,
        int column,
        int isDefinition,
        string context,
        int hasContext);

    private delegate string QueryDefinitionLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private delegate string QueryNoDefinitionsText(string name);

    private delegate string QueryDefinitionsHeaderText(string name);

    private delegate string QueryDefinitionSearchResultLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private sealed record Bindings(
        QueryNoSymbolsText QueryNoSymbolsText,
        QuerySymbolLineText QuerySymbolLineText,
        QuerySymbolParametersLineText QuerySymbolParametersLineText,
        QueryOutlineFileLineText QueryOutlineFileLineText,
        QueryOutlineImportsLineText QueryOutlineImportsLineText,
        QueryOutlineEntryLineText QueryOutlineEntryLineText,
        QueryTypeLocationHeaderText QueryTypeLocationHeaderText,
        QueryTypeResultLineText QueryTypeResultLineText,
        QueryTypeNullabilityLineText QueryTypeNullabilityLineText,
        QueryTypeDefinedAtLineText QueryTypeDefinedAtLineText,
        QueryCompletionsHeaderText QueryCompletionsHeaderText,
        QueryCompletionReceiverLineText QueryCompletionReceiverLineText,
        QueryCompletionCategoryLineText QueryCompletionCategoryLineText,
        QueryCompletionItemLineText QueryCompletionItemLineText,
        QueryCompletionOverflowLineText QueryCompletionOverflowLineText,
        QueryInspectHeaderText QueryInspectHeaderText,
        QueryInspectSymbolLineText QueryInspectSymbolLineText,
        QueryInspectNoSymbolText QueryInspectNoSymbolText,
        QueryInspectTypeLineText QueryInspectTypeLineText,
        QueryInspectUnknownTypeText QueryInspectUnknownTypeText,
        QueryInspectDefinitionLineText QueryInspectDefinitionLineText,
        QueryInspectNoDefinitionText QueryInspectNoDefinitionText,
        QueryInspectReferencesHeaderText QueryInspectReferencesHeaderText,
        QueryInspectReferencesOverflowLineText QueryInspectReferencesOverflowLineText,
        QueryHoverHeaderText QueryHoverHeaderText,
        QueryHoverSignatureLineText QueryHoverSignatureLineText,
        QueryHoverKindLineText QueryHoverKindLineText,
        QueryHoverDefinedInLineText QueryHoverDefinedInLineText,
        QueryHoverDocumentationHeaderText QueryHoverDocumentationHeaderText,
        QueryHoverDocumentationLineText QueryHoverDocumentationLineText,
        QueryNoReferencesText QueryNoReferencesText,
        QueryReferencesHeaderText QueryReferencesHeaderText,
        QueryReferenceLineText QueryReferenceLineText,
        QueryDefinitionLineText QueryDefinitionLineText,
        QueryNoDefinitionsText QueryNoDefinitionsText,
        QueryDefinitionsHeaderText QueryDefinitionsHeaderText,
        QueryDefinitionSearchResultLineText QueryDefinitionSearchResultLineText);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product query text routes through OutputFormatterText.nl.
    private static string GetSymbolLineTextWithCSharp(SymbolResult symbol, int indent)
    {
        var prefix = new string(' ', indent * 2);
        var typeText = symbol.TypeName != null ? $": {symbol.TypeName}" : string.Empty;
        var modifierText = symbol.Modifiers is { Length: > 0 } ? $"[{string.Join(", ", symbol.Modifiers)}] " : string.Empty;
        return $"{prefix}{modifierText}{symbol.Kind} {symbol.Name}{typeText}  ({symbol.File}:{symbol.Line})";
    }

    private static string GetSymbolParametersLineTextWithCSharp(ParameterResult[] parameters, int indent)
    {
        var builder = new StringBuilder();
        builder.Append(new string(' ', indent * 2));
        builder.Append("  (");

        for (var i = 0; i < parameters.Length; i++)
        {
            if (i > 0)
                builder.Append(", ");

            var parameter = parameters[i];
            builder.Append(parameter.Name);
            builder.Append(": ");
            builder.Append(parameter.Type);
            if (parameter.HasDefault)
            {
                builder.Append(" = ");
                builder.Append(parameter.DefaultValue);
            }
        }

        builder.Append(')');
        return builder.ToString();
    }

    private static string GetOutlineFileLineTextWithCSharp(string file)
        => $"File: {file}";

    private static string GetOutlineImportsLineTextWithCSharp(string[] imports)
        => $"Imports: {string.Join(", ", imports)}";

    private static string GetOutlineEntryLineTextWithCSharp(OutlineEntry entry, int indent)
    {
        var prefix = new string(' ', indent * 2);
        var typeText = entry.ReturnType != null ? $" -> {entry.ReturnType}" : string.Empty;
        var rangeText = entry.EndLine > entry.Line ? $" (lines {entry.Line}-{entry.EndLine})" : $" (line {entry.Line})";
        return $"{prefix}{entry.Kind} {entry.Name}{typeText}{rangeText}";
    }

    private static string GetTypeLocationHeaderTextWithCSharp(string file, int line, int column)
        => $"At {file}:{line}:{column}:";

    private static string GetTypeResultLineTextWithCSharp(TypeResult result)
        => $"  {result.Name}: {result.ResolvedType} ({result.Kind})";

    private static string GetTypeNullabilityLineTextWithCSharp(string nullability)
        => $"  Nullability: {nullability}";

    private static string GetTypeDefinedAtLineTextWithCSharp(LocationResult definition)
        => $"  Defined at: {definition.File}:{definition.Line}:{definition.Column}";

    private static string GetCompletionsHeaderTextWithCSharp(string file, int line, int column, string contextText)
        => $"Completions at {file}:{line}:{column} (context: {contextText})";

    private static string GetCompletionReceiverLineTextWithCSharp(string receiver, string? receiverType)
        => $"Receiver: {receiver}" + (receiverType != null ? $" ({receiverType})" : "");

    private static string GetCompletionCategoryLineTextWithCSharp(string category, int count)
        => $"  {category} ({count}):";

    private static string GetCompletionItemLineTextWithCSharp(CompletionItem item)
    {
        var typeText = item.Type != null ? $": {item.Type}" : string.Empty;
        var parameterText = item.Parameters != null ? $" {item.Parameters}" : string.Empty;
        return $"    {item.Name}{parameterText}{typeText}";
    }

    private static string GetCompletionOverflowLineTextWithCSharp(int remaining)
        => $"    ... and {remaining} more";

    private static string GetInspectHeaderTextWithCSharp(string file, int line, int column)
        => $"Inspect {file}:{line}:{column}";

    private static string GetInspectSymbolLineTextWithCSharp(InspectSymbolResult symbol)
        => $"Symbol: {symbol.Name} ({symbol.Kind})";

    private static string GetInspectNoSymbolTextWithCSharp()
        => "Symbol: none";

    private static string GetInspectTypeLineTextWithCSharp(TypeResult type)
        => $"Type: {type.ResolvedType} ({type.Kind})";

    private static string GetInspectUnknownTypeTextWithCSharp()
        => "Type: unknown";

    private static string GetInspectDefinitionLineTextWithCSharp(DefinitionResult definition)
        => $"Definition: {definition.Kind} {definition.Name} at {definition.File}:{definition.Line}:{definition.Column}";

    private static string GetInspectNoDefinitionTextWithCSharp()
        => "Definition: none";

    private static string GetInspectReferencesHeaderTextWithCSharp(int count, int definitionCount)
        => $"References: {count} total ({definitionCount} definitions)";

    private static string GetInspectReferencesOverflowLineTextWithCSharp(int remaining)
        => $"  ... and {remaining} more";

    private static string GetHoverHeaderTextWithCSharp(string file, int line, int column)
        => $"Hover {file}:{line}:{column}";

    private static string GetHoverSignatureLineTextWithCSharp(string signature)
        => $"Signature:  {signature}";

    private static string GetHoverKindLineTextWithCSharp(string kind)
        => $"Kind:       {kind}";

    private static string GetHoverDefinedInLineTextWithCSharp(string definedIn)
        => $"Defined in: {definedIn}";

    private static string GetHoverDocumentationHeaderTextWithCSharp()
        => "Documentation:";

    private static string GetHoverDocumentationLineTextWithCSharp(string docLine)
        => $"  {docLine}";

    private static string GetNoReferencesTextWithCSharp(string symbolName)
        => $"No references found for '{symbolName}'.";

    private static string GetReferencesHeaderTextWithCSharp(string symbolName, int count)
        => $"References to '{symbolName}' ({count} found):";

    private static string GetReferenceLineTextWithCSharp(ReferenceResult reference)
    {
        var definitionMarker = reference.IsDefinition ? " [definition]" : string.Empty;
        var contextText = reference.Context != null ? $"  {reference.Context.Trim()}" : string.Empty;
        return $"  {reference.File}:{reference.Line}:{reference.Column}{definitionMarker}{contextText}";
    }

    private static string GetDefinitionLineTextWithCSharp(DefinitionResult definition)
        => $"{definition.Kind} {definition.Name} at {definition.File}:{definition.Line}:{definition.Column}";

    private static string GetNoDefinitionsTextWithCSharp(string name)
        => $"No definitions found for '{name}'.";

    private static string GetDefinitionsHeaderTextWithCSharp(string name)
        => $"Definitions of '{name}':";

    private static string GetDefinitionSearchResultLineTextWithCSharp(DefinitionResult definition)
        => $"  {GetDefinitionLineTextWithCSharp(definition)}";
}
