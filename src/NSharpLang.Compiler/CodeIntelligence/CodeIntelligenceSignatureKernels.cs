using System;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceSignatureKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetFunctionSignatureText(
        string name,
        string[] parameterNames,
        string[] parameterTypes,
        int[] hasDefaults,
        int parameterCount,
        string returnType,
        bool hasReturnType)
    {
        var bindings = s_bindings.Value;
        if (bindings != null)
        {
            try
            {
                var text = bindings.FunctionSignatureText(
                    name,
                    parameterNames,
                    parameterTypes,
                    hasDefaults,
                    parameterCount,
                    returnType,
                    hasReturnType ? 1 : 0);
                if (!string.IsNullOrEmpty(text))
                    return text;
            }
            catch
            {
            }
        }

        return GetFunctionSignatureTextWithCSharp(
            name,
            parameterNames,
            parameterTypes,
            hasDefaults,
            parameterCount,
            returnType,
            hasReturnType);
    }

    internal static string GetFallbackSignatureText(string kind, string name, string? typeName)
    {
        var bindings = s_bindings.Value;
        if (bindings != null)
        {
            try
            {
                var text = bindings.FallbackSignatureText(
                    kind,
                    name,
                    typeName ?? string.Empty,
                    typeName != null ? 1 : 0);
                if (!string.IsNullOrEmpty(text))
                    return text;
            }
            catch
            {
            }
        }

        return GetFallbackSignatureTextWithCSharp(kind, name, typeName);
    }

    private static string GetFunctionSignatureTextWithCSharp(
        string name,
        string[] parameterNames,
        string[] parameterTypes,
        int[] hasDefaults,
        int parameterCount,
        string returnType,
        bool hasReturnType)
    {
        var count = Math.Min(parameterCount, parameterNames.Length);
        count = Math.Min(count, parameterTypes.Length);
        count = Math.Min(count, hasDefaults.Length);

        var builder = new StringBuilder();
        builder.Append("func ");
        builder.Append(name);
        builder.Append('(');

        for (var i = 0; i < count; i++)
        {
            if (i > 0)
                builder.Append(", ");

            builder.Append(parameterNames[i]);
            builder.Append(": ");
            builder.Append(parameterTypes[i]);

            if (hasDefaults[i] != 0)
                builder.Append(" = ...");
        }

        builder.Append(')');

        if (hasReturnType)
        {
            builder.Append(": ");
            builder.Append(returnType);
        }

        return builder.ToString();
    }

    private static string GetFallbackSignatureTextWithCSharp(string kind, string name, string? typeName)
        => typeName != null ? $"{kind} {name}: {typeName}" : $"{kind} {name}";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CodeIntelligenceFunctionSignatureText>(
                programType,
                "CodeIntelligenceFunctionSignatureText"),
            DogfoodKernelLoader.CreateDelegate<CodeIntelligenceFallbackSignatureText>(
                programType,
                "CodeIntelligenceFallbackSignatureText")));

    private delegate string CodeIntelligenceFunctionSignatureText(
        string name,
        string[] parameterNames,
        string[] parameterTypes,
        int[] hasDefaults,
        int requestedCount,
        string returnType,
        int hasReturnType);

    private delegate string CodeIntelligenceFallbackSignatureText(
        string kind,
        string name,
        string typeName,
        int hasType);

    private sealed record Bindings(
        CodeIntelligenceFunctionSignatureText FunctionSignatureText,
        CodeIntelligenceFallbackSignatureText FallbackSignatureText);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product hover signature text routes through CodeIntelligenceSignatures.nl.
}
