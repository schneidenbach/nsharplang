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
            DogfoodKernelLoader.CreateDelegate<QueryNoReferencesText>(
                programType,
                "QueryNoReferencesText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferencesHeaderText>(
                programType,
                "QueryReferencesHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferenceLineText>(
                programType,
                "QueryReferenceLineText")));

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

    private delegate string QueryNoReferencesText(string symbolName);

    private delegate string QueryReferencesHeaderText(string symbolName, int count);

    private delegate string QueryReferenceLineText(
        string fileName,
        int line,
        int column,
        int isDefinition,
        string context,
        int hasContext);

    private sealed record Bindings(
        QueryNoSymbolsText QueryNoSymbolsText,
        QuerySymbolLineText QuerySymbolLineText,
        QuerySymbolParametersLineText QuerySymbolParametersLineText,
        QueryOutlineFileLineText QueryOutlineFileLineText,
        QueryOutlineImportsLineText QueryOutlineImportsLineText,
        QueryOutlineEntryLineText QueryOutlineEntryLineText,
        QueryNoReferencesText QueryNoReferencesText,
        QueryReferencesHeaderText QueryReferencesHeaderText,
        QueryReferenceLineText QueryReferenceLineText);

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
}
