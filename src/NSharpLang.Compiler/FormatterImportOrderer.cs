using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class FormatterImportOrderer
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static bool TryOrderBySystemThenNamespace(
        IReadOnlyList<ImportDirective> imports,
        out List<ImportDirective> orderedImports)
    {
        orderedImports = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = imports.Count;
        if (count == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetRanks();
            for (var i = 0; i < count; i++)
            {
                var ns = imports[i].Namespace;
                if (ns == null)
                {
                    orderedImports = [];
                    return false;
                }

                // Match the production LINQ shape exactly: OrderByDescending uses the
                // default (current-culture) StartsWith, ThenBy uses Comparer<string>.Default.
                scratch.SystemFlags[i] = ns.StartsWith("System") ? 1 : 0;
                scratch.AddNamespace(ns);
            }

            scratch.BuildRanks();
            for (var i = 0; i < count; i++)
            {
                scratch.NameRanks[i] = scratch.GetRank(imports[i].Namespace);
            }

            var orderedCount = bindings.FormatterImportOrderIndices(
                scratch.SystemFlags,
                scratch.NameRanks,
                scratch.UniqueNamespaceCount,
                scratch.BucketCounts,
                scratch.BucketOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount != count)
            {
                orderedImports = [];
                return false;
            }

            var result = new List<ImportDirective>(count);
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    orderedImports = [];
                    return false;
                }

                result.Add(imports[sourceIndex]);
            }

            orderedImports = result;
            return true;
        }
        catch
        {
            orderedImports = [];
            return false;
        }
        finally
        {
            scratch.ResetRanks();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<FormatterImportOrderIndicesInto>(
                programType,
                "FormatterImportOrderIndicesInto")));

    private delegate int FormatterImportOrderIndicesInto(
        int[] systemFlags,
        int[] nameRanks,
        int nameRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private sealed record Bindings(FormatterImportOrderIndicesInto FormatterImportOrderIndices);

    private sealed class Scratch
    {
        // Distinct namespace strings keyed ordinally (so distinct strings stay distinct
        // entries), each mapped to a rank that reflects Comparer<string>.Default ordering.
        // Namespaces that compare EQUAL under that comparer share a rank, exactly mirroring
        // LINQ ThenBy(i => i.Namespace), whose ties are broken by original input order.
        private readonly Dictionary<string, int> _namespaceRanks = new(StringComparer.Ordinal);

        internal int[] BucketCounts = Array.Empty<int>();
        internal int[] BucketOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SystemFlags = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueNamespaces = Array.Empty<string>();
        internal int UniqueNamespaceCount;

        internal void EnsureCapacity(int count)
        {
            // Size the per-item arrays exactly to the logical import count: the kernel
            // derives its working count from systemFlags.Length, so these arrays must not
            // retain extra (stale) tail slots from a larger prior call on this thread.
            if (SystemFlags.Length != count)
            {
                SystemFlags = new int[count];
                NameRanks = new int[count];
                TempIndices = new int[count];
                ResultIndices = new int[count];
                UniqueNamespaces = new string[count];
            }

            // The name-pass counting sort uses ranks 1..uniqueRankCount; capacity must
            // cover the worst case where every namespace is distinct (uniqueRankCount == count).
            var bucketCapacity = count + 1;
            if (BucketCounts.Length != bucketCapacity)
            {
                BucketCounts = new int[bucketCapacity];
                BucketOffsets = new int[bucketCapacity];
            }
        }

        internal void AddNamespace(string ns)
        {
            if (_namespaceRanks.ContainsKey(ns))
                return;

            _namespaceRanks.Add(ns, 0);
            UniqueNamespaces[UniqueNamespaceCount] = ns;
            UniqueNamespaceCount++;
        }

        internal void BuildRanks()
        {
            Array.Sort(UniqueNamespaces, 0, UniqueNamespaceCount, Comparer<string>.Default);

            // Assign 1-based ranks; consecutive entries that compare equal under the
            // sort comparer share a rank so the kernel treats them as a stable tie.
            var rank = 0;
            for (var i = 0; i < UniqueNamespaceCount; i++)
            {
                if (i == 0 || Comparer<string>.Default.Compare(UniqueNamespaces[i], UniqueNamespaces[i - 1]) != 0)
                {
                    rank++;
                }

                _namespaceRanks[UniqueNamespaces[i]] = rank;
            }
        }

        internal int GetRank(string ns) => _namespaceRanks[ns];

        internal void ResetRanks()
        {
            _namespaceRanks.Clear();
            if (UniqueNamespaceCount > 0)
            {
                Array.Clear(UniqueNamespaces, 0, UniqueNamespaceCount);
                UniqueNamespaceCount = 0;
            }
        }
    }
}
