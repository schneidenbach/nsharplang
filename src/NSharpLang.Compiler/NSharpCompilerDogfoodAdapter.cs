using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class NSharpCompilerDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static FirstDistinctTypeKeyScratch? t_firstDistinctTypeKeyScratch;
    [ThreadStatic]
    private static FirstDistinctStringScratch? t_firstDistinctStringScratch;
    [ThreadStatic]
    private static DistinctOrderedStringScratch? t_distinctOrderedStringScratch;
    [ThreadStatic]
    private static DeclaredTypeSuffixLookupScratch? t_declaredTypeSuffixLookupScratch;
    [ThreadStatic]
    private static DeclaredTypeNameCandidateScratch? t_declaredTypeNameCandidateScratch;
    [ThreadStatic]
    private static TypeCreationOrderScratch? t_typeCreationOrderScratch;
    [ThreadStatic]
    private static AnonymousUnionShimScratch? t_anonymousUnionShimScratch;
    [ThreadStatic]
    private static MissingEnumMemberScratch? t_missingEnumMemberScratch;
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;
    [ThreadStatic]
    private static FormatterImportOrderingScratch? t_formatterImportOrderingScratch;
    [ThreadStatic]
    private static OverloadCandidateScratch? t_overloadCandidateScratch;

    internal static bool TryOrderImportsBySystemThenNamespace(
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

        var scratch = t_formatterImportOrderingScratch ??= new FormatterImportOrderingScratch();
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

    internal static bool TryDeduplicateFirstTypeKeys(
        IReadOnlyList<Type> types,
        Func<Type, string> getTypeKey,
        out List<Type> deduplicatedTypes)
    {
        deduplicatedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var typeCount = types.Count;
        if (typeCount == 0)
            return true;

        var scratch = t_firstDistinctTypeKeyScratch ??= new FirstDistinctTypeKeyScratch();
        scratch.EnsureCapacity(typeCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < typeCount; i++)
            {
                scratch.TypeRanks[i] = scratch.AddKey(getTypeKey(types[i]));
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.TypeRanks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > typeCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedTypes = [];
                return false;
            }

            var result = new List<Type>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= typeCount)
                {
                    deduplicatedTypes = [];
                    return false;
                }

                result.Add(types[sourceIndex]);
            }

            deduplicatedTypes = result;
            return true;
        }
        catch
        {
            deduplicatedTypes = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDeduplicateFirstStringsOrdinalIgnoreCase(
        IReadOnlyList<string> values,
        out List<string> deduplicatedValues)
    {
        deduplicatedValues = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_firstDistinctStringScratch ??= new FirstDistinctStringScratch(StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    deduplicatedValues = [];
                    return false;
                }

                scratch.Ranks[i] = scratch.AddKey(value);
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > valueCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = [];
                return false;
            }

            var result = new List<string>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = [];
                    return false;
                }

                result.Add(values[sourceIndex]);
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDistinctOrderStringsOrdinal(
        IReadOnlyList<string> values,
        out string[] orderedValues)
    {
        orderedValues = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_distinctOrderedStringScratch ??= new DistinctOrderedStringScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetValues();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                scratch.Values[i] = value;
                scratch.AddValue(value);
            }

            scratch.BuildRanks();
            for (var i = 0; i < valueCount; i++)
            {
                scratch.ValueRanks[i] = scratch.GetRank(scratch.Values[i]);
            }

            var orderedCount = bindings.ReferenceFileSummaryRanks(
                scratch.ValueRanks,
                scratch.UniqueValueCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (orderedCount < 0 || orderedCount > scratch.UniqueValueCount || orderedCount > scratch.ResultRanks.Length)
            {
                orderedValues = Array.Empty<string>();
                return false;
            }

            var result = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueValueCount)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                result[i] = scratch.UniqueValues[rank - 1];
            }

            orderedValues = result;
            return true;
        }
        catch
        {
            orderedValues = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearValues(valueCount);
            scratch.ResetValues();
        }
    }

    internal static bool TryLookupUniqueDeclaredTypeBySuffix<TType>(
        IReadOnlyDictionary<string, TType> types,
        string typeName,
        out TType type,
        out bool found)
        where TType : Type
    {
        type = null!;
        found = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_declaredTypeSuffixLookupScratch ??= new DeclaredTypeSuffixLookupScratch();

        try
        {
            if (!scratch.Load(types))
                return false;

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var rank = bindings.DeclaredTypeUniqueSuffixValueRank(
                scratch.Keys,
                scratch.ValueRanks,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (rank == -2)
                return false;

            if (rank <= 0)
                return true;

            if (rank >= scratch.Values.Length || scratch.Values[rank] is not TType result)
                return false;

            type = result;
            found = true;
            return true;
        }
        catch
        {
            type = null!;
            found = false;
            return false;
        }
    }

    internal static bool TrySelectDeclaredTypeNameCandidate(
        CompilationUnit compilationUnit,
        string typeName,
        out string? candidate)
    {
        candidate = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (string.IsNullOrWhiteSpace(typeName))
            return true;

        var scratch = t_declaredTypeNameCandidateScratch ??= new DeclaredTypeNameCandidateScratch();

        try
        {
            scratch.Load(compilationUnit);

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var index = bindings.DeclaredTypeNameCandidateIndex(
                scratch.Names,
                scratch.ImportedNamespaceFlags,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (index == -2)
                return false;

            if (index <= 0)
                return true;

            var candidateIndex = index - 1;
            if (candidateIndex >= scratch.Count)
                return false;

            candidate = scratch.Names[candidateIndex];
            return true;
        }
        catch
        {
            candidate = null;
            return false;
        }
    }

    internal static bool TryOrderTypesByDescendingKeyDotCount<TType>(
        IEnumerable<TType> types,
        Func<TType, string> getTypeKey,
        out List<TType> orderedTypes)
        where TType : Type
    {
        orderedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_typeCreationOrderScratch ??= new TypeCreationOrderScratch();

        try
        {
            if (!scratch.Load(types, getTypeKey))
                return false;

            if (scratch.Count == 0)
                return true;

            var orderedCount = bindings.TypeCreationOrderIndices(
                scratch.Keys,
                scratch.Count,
                scratch.DotCounts,
                scratch.DepthCounts,
                scratch.DepthOffsets,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > scratch.Count || orderedCount > scratch.ResultIndices.Length)
            {
                orderedTypes = [];
                return false;
            }

            var result = new List<TType>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= scratch.Count || scratch.Values[sourceIndex] is not TType type)
                {
                    orderedTypes = [];
                    return false;
                }

                result.Add(type);
            }

            orderedTypes = result;
            return true;
        }
        catch
        {
            orderedTypes = [];
            return false;
        }
        finally
        {
            scratch.ClearValues();
        }
    }

    internal static bool TryDeclaresAnonymousUnionShims(
        IReadOnlyList<Parameter> parameters,
        Func<TypeReference, bool> isTwoArmAnonymousUnion,
        out bool declaresShims)
    {
        declaresShims = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var parameterCount = parameters.Count;
        if (parameterCount == 0)
            return true;

        var scratch = t_anonymousUnionShimScratch ??= new AnonymousUnionShimScratch();
        scratch.EnsureCapacity(parameterCount);

        try
        {
            var unionParameterCount = 0;
            for (var i = 0; i < parameterCount; i++)
            {
                var parameter = parameters[i];
                if (!isTwoArmAnonymousUnion(parameter.Type))
                {
                    continue;
                }

                var hasDisallowedModifier =
                    parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out or Ast.ParameterModifier.Params;
                scratch.ParameterFlags[unionParameterCount] = hasDisallowedModifier ? 2 : 1;
                unionParameterCount++;
            }

            var result = bindings.AnonymousUnionDeclaresPublicShim(
                scratch.ParameterFlags,
                unionParameterCount);
            if (result is not 0 and not 1)
                return false;

            declaresShims = result != 0;
            return true;
        }
        catch
        {
            declaresShims = false;
            return false;
        }
    }

    /// <summary>
    /// Selects the winning declared-method overload index from a compact candidate table using the
    /// N# ranking kernel. The caller fills the rank columns for each surviving candidate through
    /// <paramref name="fillColumns"/> (writing one entry per candidate into the supplied buffers and
    /// returning the candidate count), and this routine runs the exact four-level tie-break
    /// (score &gt; non-generic &gt; non-params &gt; fewer-defaults, first-wins-on-tie) over those
    /// columns. <paramref name="selectedIndex"/> is the zero-based index of the winning candidate in
    /// fill order, or -1 when no candidate is valid.
    /// </summary>
    internal static bool TrySelectOverloadCandidate(
        int candidateCapacity,
        OverloadColumnFiller fillColumns,
        out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (candidateCapacity < 0)
            return false;

        var scratch = t_overloadCandidateScratch ??= new OverloadCandidateScratch();
        scratch.EnsureCapacity(candidateCapacity);

        try
        {
            var count = fillColumns(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed);

            if (count < 0 || count > candidateCapacity)
                return false;

            var index = bindings.OverloadSelectBestCandidate(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed,
                count);

            if (index < -1 || index >= count)
                return false;

            selectedIndex = index;
            return true;
        }
        catch
        {
            selectedIndex = -1;
            return false;
        }
    }

    /// <summary>
    /// Fills the compact overload-candidate rank columns for surviving candidates and returns the
    /// candidate count.
    /// </summary>
    internal delegate int OverloadColumnFiller(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed);

    internal static bool TrySelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers,
        out List<string> missingMembers)
    {
        missingMembers = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var memberCount = members.Count;
        if (memberCount == 0)
            return true;

        var scratch = t_missingEnumMemberScratch ??= new MissingEnumMemberScratch();
        scratch.EnsureCapacity(memberCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < memberCount; i++)
            {
                var memberName = members[i].Name;
                if (!scratch.AddName(memberName))
                    return false;

                scratch.CoveredFlags[i] = coveredMembers.Contains(memberName) ? 1 : 0;
            }

            var missingCount = bindings.AnalyzerMissingMemberIndices(
                scratch.CoveredFlags,
                memberCount,
                scratch.ResultIndices);

            if (missingCount < 0 || missingCount > memberCount || missingCount > scratch.ResultIndices.Length)
            {
                missingMembers = [];
                return false;
            }

            var result = new List<string>(missingCount);
            for (var i = 0; i < missingCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= memberCount)
                {
                    missingMembers = [];
                    return false;
                }

                result.Add(members[sourceIndex].Name);
            }

            missingMembers = result;
            return true;
        }
        catch
        {
            missingMembers = [];
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static bool TrySelectMissingUnionCasesFromFlags(
        IReadOnlyList<UnionCase> cases,
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        out List<string> missingCases,
        out List<string> partialMissingCases,
        out List<string> neverCoveredCases)
    {
        missingCases = [];
        partialMissingCases = [];
        neverCoveredCases = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (count < 0 || count > cases.Count || count > coveredFlags.Length || count > partialFlags.Length)
            return false;

        if (count == 0)
            return true;

        var scratch = t_missingUnionCaseScratch ??= new MissingUnionCaseScratch();
        scratch.EnsureCapacity(count);

        try
        {
            var missingCount = bindings.AnalyzerUnionMissingCaseIndices(
                coveredFlags,
                partialFlags,
                count,
                scratch.MissingIndices,
                scratch.PartialMissingIndices,
                scratch.NeverCoveredIndices,
                scratch.ResultCounts);

            var partialMissingCount = scratch.ResultCounts[1];
            var neverCoveredCount = scratch.ResultCounts[2];
            if (missingCount < 0 ||
                missingCount > count ||
                partialMissingCount < 0 ||
                partialMissingCount > missingCount ||
                neverCoveredCount < 0 ||
                neverCoveredCount > missingCount ||
                partialMissingCount + neverCoveredCount != missingCount)
            {
                missingCases = [];
                partialMissingCases = [];
                neverCoveredCases = [];
                return false;
            }

            missingCases = MaterializeCaseNames(cases, scratch.MissingIndices, missingCount);
            partialMissingCases = MaterializeCaseNames(cases, scratch.PartialMissingIndices, partialMissingCount);
            neverCoveredCases = MaterializeCaseNames(cases, scratch.NeverCoveredIndices, neverCoveredCount);
            return true;
        }
        catch
        {
            missingCases = [];
            partialMissingCases = [];
            neverCoveredCases = [];
            return false;
        }
    }

    private static List<string> MaterializeCaseNames(
        IReadOnlyList<UnionCase> cases,
        int[] indices,
        int count)
    {
        var result = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            if (sourceIndex < 0 || sourceIndex >= cases.Count)
                throw new InvalidOperationException("Dogfood union missing-case selection returned an invalid source index.");

            result.Add(cases[sourceIndex].Name);
        }

        return result;
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<FormatterImportOrderIndicesInto>(
                    programType,
                    "FormatterImportOrderIndicesInto"),
                CreateDelegate<FirstDistinctRankIndicesInto>(
                    programType,
                    "FirstDistinctRankIndicesInto"),
                CreateDelegate<DeclaredTypeUniqueSuffixValueRank>(
                    programType,
                    "DeclaredTypeUniqueSuffixValueRank"),
                CreateDelegate<DeclaredTypeNameCandidateIndex>(
                    programType,
                    "DeclaredTypeNameCandidateIndex"),
                CreateDelegate<TypeCreationOrderIndicesInto>(
                    programType,
                    "TypeCreationOrderIndicesInto"),
                CreateDelegate<ReferenceFileSummaryRanksInto>(
                    programType,
                    "ReferenceFileSummaryRanksInto"),
                CreateDelegate<AnonymousUnionDeclaresPublicShim>(
                    programType,
                    "AnonymousUnionDeclaresPublicShim"),
                CreateDelegate<AnalyzerMissingMemberIndicesInto>(
                    programType,
                    "AnalyzerMissingMemberIndicesInto"),
                CreateDelegate<AnalyzerUnionMissingCaseIndicesInto>(
                    programType,
                    "AnalyzerUnionMissingCaseIndicesInto"),
                CreateDelegate<OverloadSelectBestCandidate>(
                    programType,
                    "OverloadSelectBestCandidate"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int FormatterImportOrderIndicesInto(
        int[] systemFlags,
        int[] nameRanks,
        int nameRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);
    private delegate int FirstDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);
    private delegate int DeclaredTypeUniqueSuffixValueRank(
        string[] keys,
        int[] valueRanks,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int DeclaredTypeNameCandidateIndex(
        string[] names,
        int[] importedNamespaceFlags,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int TypeCreationOrderIndicesInto(
        string[] keys,
        int count,
        int[] dotCounts,
        int[] depthCounts,
        int[] depthOffsets,
        int[] resultIndices);
    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);
    private delegate int AnonymousUnionDeclaresPublicShim(int[] parameterFlags, int count);
    private delegate int OverloadSelectBestCandidate(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed,
        int count);
    private delegate int AnalyzerMissingMemberIndicesInto(int[] coveredFlags, int count, int[] resultIndices);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);
    private sealed record Bindings(
        FormatterImportOrderIndicesInto FormatterImportOrderIndices,
        FirstDistinctRankIndicesInto FirstDistinctRankIndices,
        DeclaredTypeUniqueSuffixValueRank DeclaredTypeUniqueSuffixValueRank,
        DeclaredTypeNameCandidateIndex DeclaredTypeNameCandidateIndex,
        TypeCreationOrderIndicesInto TypeCreationOrderIndices,
        ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks,
        AnonymousUnionDeclaresPublicShim AnonymousUnionDeclaresPublicShim,
        AnalyzerMissingMemberIndicesInto AnalyzerMissingMemberIndices,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices,
        OverloadSelectBestCandidate OverloadSelectBestCandidate);

    private sealed class FormatterImportOrderingScratch
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

    private sealed class AnonymousUnionShimScratch
    {
        internal int[] ParameterFlags = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ParameterFlags.Length < count)
            {
                ParameterFlags = new int[count];
            }
        }
    }

    private sealed class OverloadCandidateScratch
    {
        internal int[] ValidFlags = Array.Empty<int>();
        internal int[] Scores = Array.Empty<int>();
        internal int[] GenericFlags = Array.Empty<int>();
        internal int[] ParamsFlags = Array.Empty<int>();
        internal int[] DefaultsUsed = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ValidFlags.Length < count)
            {
                ValidFlags = new int[count];
                Scores = new int[count];
                GenericFlags = new int[count];
                ParamsFlags = new int[count];
                DefaultsUsed = new int[count];
            }
        }
    }

    private sealed class MissingEnumMemberScratch
    {
        private readonly HashSet<string> _seenNames = new(StringComparer.Ordinal);

        internal int[] CoveredFlags = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal bool AddName(string name) => _seenNames.Add(name);

        internal void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }

        internal void ResetNames()
        {
            _seenNames.Clear();
        }
    }

    private sealed class MissingUnionCaseScratch
    {
        internal int[] MissingIndices = Array.Empty<int>();
        internal int[] NeverCoveredIndices = Array.Empty<int>();
        internal int[] PartialMissingIndices = Array.Empty<int>();
        internal int[] ResultCounts = new int[3];

        internal void EnsureCapacity(int count)
        {
            if (MissingIndices.Length < count)
            {
                MissingIndices = new int[count];
                NeverCoveredIndices = new int[count];
                PartialMissingIndices = new int[count];
            }

            if (ResultCounts.Length != 3)
            {
                ResultCounts = new int[3];
            }
        }
    }

    private sealed class FirstDistinctTypeKeyScratch
    {
        private readonly Dictionary<string, int> _keyRanks = new(StringComparer.Ordinal);

        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int[] TypeRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
        {
            if (TypeRanks.Length != count)
            {
                TypeRanks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class FirstDistinctStringScratch(IEqualityComparer<string> comparer)
    {
        private readonly Dictionary<string, int> _keyRanks = new(comparer);

        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class DistinctOrderedStringScratch
    {
        private readonly Dictionary<string, int> _valueRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal string[] UniqueValues = Array.Empty<string>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal string[] Values = Array.Empty<string>();
        internal int UniqueValueCount;

        internal void EnsureCapacity(int count)
        {
            if (ValueRanks.Length != count)
            {
                ValueRanks = new int[count];
                Values = new string[count];
                ResultRanks = new int[count];
                UniqueValues = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        internal void AddValue(string value)
        {
            if (_valueRanks.ContainsKey(value))
                return;

            _valueRanks.Add(value, 0);
            UniqueValues[UniqueValueCount] = value;
            UniqueValueCount++;
        }

        internal void BuildRanks()
        {
            Array.Sort(UniqueValues, 0, UniqueValueCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueValueCount; i++)
            {
                _valueRanks[UniqueValues[i]] = i + 1;
            }
        }

        internal int GetRank(string value) => _valueRanks[value];

        internal void ClearValues(int count) => Array.Clear(Values, 0, count);

        internal void ResetValues()
        {
            _valueRanks.Clear();
            if (UniqueValueCount > 0)
            {
                Array.Clear(UniqueValues, 0, UniqueValueCount);
                UniqueValueCount = 0;
            }
        }
    }

    private sealed class DeclaredTypeSuffixLookupScratch
    {
        private readonly Dictionary<Type, int> _valueRanks = new();
        private object? _source;
        private int _sourceCount;
        private int _tailHashWidth = -1;

        internal int Count;
        internal string[] Keys = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IReadOnlyDictionary<string, TType> types)
            where TType : Type
        {
            var count = types.Count;
            if (ReferenceEquals(_source, types) && _sourceCount == count && !CachedValuesContainUnbakedBuilder())
                return true;

            EnsureCapacity(count);
            _valueRanks.Clear();

            var index = 0;
            var uniqueValueCount = 0;
            foreach (var entry in types)
            {
                var value = entry.Value;
                if (value == null)
                    return false;

                if (!_valueRanks.TryGetValue(value, out var rank))
                {
                    rank = ++uniqueValueCount;
                    _valueRanks.Add(value, rank);
                    Values[rank] = value;
                }

                Keys[index] = entry.Key;
                ValueRanks[index] = rank;
                index++;
            }

            Count = count;
            _source = types;
            _sourceCount = count;
            _tailHashWidth = -1;
            return true;
        }

        // A cache hit keyed on (same dictionary instance, same count) is unsafe when the
        // dictionary's VALUES were replaced in place since we cached — e.g. ILCompiler's
        // FinalizeTopLevelEnumTypes swaps each EnumBuilder value for its baked Type while keeping
        // the same keys and count. If any cached value is still an unbaked reflection-emit builder,
        // force a reload so we don't hand back a stale EnumBuilder/TypeBuilder (M9).
        private bool CachedValuesContainUnbakedBuilder()
        {
            foreach (var value in _valueRanks.Keys)
            {
                if (value is System.Reflection.Emit.TypeBuilder or System.Reflection.Emit.EnumBuilder)
                {
                    return true;
                }
            }

            return false;
        }

        internal void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = GetTailHash(Keys[i], width);
            }

            _tailHashWidth = width;
        }

        internal static int GetTailHashWidth(string text) => Math.Min(4, text.Length);

        internal static int GetTailHash(string text, int width)
        {
            var hash = 0;
            for (var offset = 0; offset < width && offset < text.Length; offset++)
            {
                hash = hash * 31 + text[text.Length - 1 - offset];
            }

            return hash;
        }

        private void EnsureCapacity(int count)
        {
            if (Keys.Length < count)
            {
                Keys = new string[count];
                ValueRanks = new int[count];
                TailHashes = new int[count];
            }

            var valueCapacity = count + 1;
            if (Values.Length < valueCapacity)
            {
                Values = new Type[valueCapacity];
            }
        }
    }

    private sealed class DeclaredTypeNameCandidateScratch
    {
        private readonly HashSet<string> _importedNamespaces = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _nameIndices = new(StringComparer.Ordinal);
        private CompilationUnit? _source;
        private int _sourceDeclarationCount;
        private int _sourceImportCount;
        private int _tailHashWidth = -1;

        internal int Count;
        internal int[] ImportedNamespaceFlags = Array.Empty<int>();
        internal string[] Names = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();

        internal void Load(CompilationUnit compilationUnit)
        {
            var declarationCount = compilationUnit.Declarations.Count;
            var importCount = compilationUnit.Imports.Count;
            if (ReferenceEquals(_source, compilationUnit)
                && _sourceDeclarationCount == declarationCount
                && _sourceImportCount == importCount)
            {
                return;
            }

            Count = 0;
            _tailHashWidth = -1;
            _nameIndices.Clear();
            _importedNamespaces.Clear();

            for (var i = 0; i < importCount; i++)
            {
                var import = compilationUnit.Imports[i];
                if (import.Alias == null)
                {
                    _importedNamespaces.Add(import.Namespace);
                }
            }

            for (var i = 0; i < declarationCount; i++)
            {
                AddDeclaration(compilationUnit.Declarations[i], containingTypeName: null);
            }

            for (var i = 0; i < Count; i++)
            {
                var namespaceName = GetNamespaceFromTypeName(Names[i]);
                ImportedNamespaceFlags[i] = string.IsNullOrEmpty(namespaceName) || _importedNamespaces.Contains(namespaceName)
                    ? 1
                    : 0;
            }

            _source = compilationUnit;
            _sourceDeclarationCount = declarationCount;
            _sourceImportCount = importCount;
        }

        internal void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = DeclaredTypeSuffixLookupScratch.GetTailHash(Names[i], width);
            }

            _tailHashWidth = width;
        }

        private void AddDeclaration(Declaration declaration, string? containingTypeName)
        {
            var name = GetDeclaredTypeName(declaration);
            if (string.IsNullOrWhiteSpace(name))
                return;

            var typeName = containingTypeName == null ? name : $"{containingTypeName}.{name}";
            if (!_nameIndices.ContainsKey(typeName))
            {
                EnsureCapacity(Count + 1);
                _nameIndices.Add(typeName, Count);
                Names[Count] = typeName;
                Count++;
            }

            AddNestedTypeDeclarations(declaration, typeName);
        }

        private void AddNestedTypeDeclarations(Declaration declaration, string containingTypeName)
        {
            switch (declaration)
            {
                case ClassDeclaration classDeclaration:
                    AddNestedTypeDeclarations(classDeclaration.Members, containingTypeName);
                    break;
                case StructDeclaration structDeclaration:
                    AddNestedTypeDeclarations(structDeclaration.Members, containingTypeName);
                    break;
                case RecordDeclaration recordDeclaration:
                    AddNestedTypeDeclarations(recordDeclaration.Members, containingTypeName);
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    AddNestedTypeDeclarations(interfaceDeclaration.Members, containingTypeName);
                    break;
            }
        }

        private void AddNestedTypeDeclarations(List<Declaration> members, string containingTypeName)
        {
            for (var i = 0; i < members.Count; i++)
            {
                var member = members[i];
                if (IsTypeDeclaration(member))
                {
                    AddDeclaration(member, containingTypeName);
                }
            }
        }

        private static string? GetDeclaredTypeName(Declaration declaration)
        {
            return declaration switch
            {
                ClassDeclaration classDeclaration => classDeclaration.Name,
                StructDeclaration structDeclaration => structDeclaration.Name,
                RecordDeclaration recordDeclaration => recordDeclaration.Name,
                SoaRecordDeclaration soaRecordDeclaration => soaRecordDeclaration.Name,
                InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Name,
                EnumDeclaration enumDeclaration => enumDeclaration.Name,
                UnionDeclaration unionDeclaration => unionDeclaration.Name,
                NewtypeDeclaration newtypeDeclaration => newtypeDeclaration.Name,
                _ => null
            };
        }

        private static bool IsTypeDeclaration(Declaration declaration)
        {
            return declaration is ClassDeclaration
                or StructDeclaration
                or RecordDeclaration
                or SoaRecordDeclaration
                or InterfaceDeclaration
                or EnumDeclaration
                or UnionDeclaration
                or NewtypeDeclaration;
        }

        private static string GetNamespaceFromTypeName(string typeName)
        {
            var separatorIndex = typeName.LastIndexOf('.');
            return separatorIndex >= 0 ? typeName[..separatorIndex] : string.Empty;
        }

        private void EnsureCapacity(int count)
        {
            if (Names.Length >= count)
                return;

            var newCapacity = Names.Length == 0 ? 8 : Names.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Names, newCapacity);
            Array.Resize(ref ImportedNamespaceFlags, newCapacity);
            Array.Resize(ref TailHashes, newCapacity);
        }
    }

    private sealed class TypeCreationOrderScratch
    {
        internal int Count;
        internal int[] DepthCounts = Array.Empty<int>();
        internal int[] DepthOffsets = Array.Empty<int>();
        internal int[] DotCounts = Array.Empty<int>();
        internal string[] Keys = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IEnumerable<TType> types, Func<TType, string> getTypeKey)
            where TType : Type
        {
            Count = 0;
            var maxKeyLength = 0;
            foreach (var type in types)
            {
                if (type == null)
                    return false;

                var key = getTypeKey(type);
                if (key == null)
                    return false;

                EnsureTypeCapacity(Count + 1);
                Values[Count] = type;
                Keys[Count] = key;
                if (key.Length > maxKeyLength)
                {
                    maxKeyLength = key.Length;
                }

                Count++;
            }

            EnsureDepthCapacity(maxKeyLength + 1);
            return true;
        }

        internal void ClearValues()
        {
            for (var i = 0; i < Count; i++)
            {
                Values[i] = null!;
                Keys[i] = null!;
            }

            Count = 0;
        }

        private void EnsureTypeCapacity(int count)
        {
            if (Values.Length >= count)
                return;

            var newCapacity = Values.Length == 0 ? 8 : Values.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Values, newCapacity);
            Array.Resize(ref Keys, newCapacity);
            Array.Resize(ref DotCounts, newCapacity);
            Array.Resize(ref ResultIndices, newCapacity);
        }

        private void EnsureDepthCapacity(int count)
        {
            if (DepthCounts.Length >= count)
                return;

            var newCapacity = DepthCounts.Length == 0 ? 8 : DepthCounts.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref DepthCounts, newCapacity);
            Array.Resize(ref DepthOffsets, newCapacity);
        }
    }
}
