using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class FormatterImportOrderer
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<ImportDirective> OrderBySystemThenNamespace(IReadOnlyList<ImportDirective> imports)
    {
        var bindings = RequiredBindings;

        var count = imports.Count;
        var namespaces = new string[count];
        var resultIndices = new int[count];
        for (var i = 0; i < count; i++)
        {
            namespaces[i] = imports[i].Namespace;
        }

        var orderedCount = bindings.FormatterImportOrderIndicesFromNamespaces(namespaces, resultIndices);

        var result = new List<ImportDirective>(orderedCount);
        for (var i = 0; i < orderedCount; i++)
        {
            var sourceIndex = resultIndices[i];
            result.Add(imports[sourceIndex]);
        }

        return result;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<FormatterImportOrderIndicesFromNamespacesInto>(
                programType,
                "FormatterImportOrderIndicesFromNamespacesInto")));

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# formatter import-order kernel is unavailable.");

    private delegate int FormatterImportOrderIndicesFromNamespacesInto(
        string[] namespaces,
        int[] resultIndices);

    private sealed record Bindings(FormatterImportOrderIndicesFromNamespacesInto FormatterImportOrderIndicesFromNamespaces);
}
