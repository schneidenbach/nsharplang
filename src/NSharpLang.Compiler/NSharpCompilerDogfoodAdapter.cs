using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class NSharpCompilerDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<SemanticModel, SemanticScopeCache> s_semanticScopeCaches = new();
    [ThreadStatic]
    private static ParserTokenCompactionScratch? t_parserTokenCompactionScratch;
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

    internal static bool IsAvailable => s_bindings.Value != null;

    internal static bool TryGetVisibleVariablesAtPosition(
        SemanticModel semanticModel,
        int line,
        int column,
        out Dictionary<string, TypeInfo> visibleVariables)
    {
        visibleVariables = new Dictionary<string, TypeInfo>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_semanticScopeCaches.GetValue(semanticModel, static model => new SemanticScopeCache(model));
            return cache.TryGetVisibleVariablesAtPosition(bindings, line, column, out visibleVariables);
        }
        catch
        {
            visibleVariables = new Dictionary<string, TypeInfo>();
            return false;
        }
    }

    internal static bool TryLookupIdentifierAtPosition(
        SemanticModel semanticModel,
        string name,
        int line,
        int column,
        out TypeInfo? typeInfo)
    {
        typeInfo = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_semanticScopeCaches.GetValue(semanticModel, static model => new SemanticScopeCache(model));
            return cache.TryLookupIdentifierAtPosition(bindings, name, line, column, out typeInfo);
        }
        catch
        {
            typeInfo = null;
            return false;
        }
    }

    internal static bool TryCompactParserTokens(IReadOnlyList<Token> tokens, out List<Token> compactedTokens)
    {
        compactedTokens = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var tokenCount = tokens.Count;
        if (tokenCount == 0)
            return true;

        var scratch = t_parserTokenCompactionScratch ??= new ParserTokenCompactionScratch();
        scratch.EnsureCapacity(tokenCount);

        try
        {
            for (var i = 0; i < tokenCount; i++)
            {
                scratch.TokenKinds[i] = (int)tokens[i].Type;
            }

            var compactedCount = bindings.ParserTokenCompaction(
                scratch.TokenKinds,
                scratch.ResultIndices);

            if (compactedCount < 0 || compactedCount > tokenCount)
            {
                compactedTokens = [];
                return false;
            }

            var result = new List<Token>(compactedCount);
            for (var i = 0; i < compactedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= tokenCount)
                {
                    compactedTokens = [];
                    return false;
                }

                result.Add(tokens[sourceIndex]);
            }

            compactedTokens = result;
            return true;
        }
        catch
        {
            compactedTokens = [];
            return false;
        }
    }

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
                CreateDelegate<ParserTokenCompactionIndicesInto>(
                    programType,
                    "ParserTokenCompactionIndicesInto"),
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
                CreateDelegate<SemanticScopeBuildSortedIndexInto>(
                    programType,
                    "SemanticScopeBuildSortedIndexInto"),
                CreateDelegate<SemanticScopeBuildDepthsInto>(
                    programType,
                    "SemanticScopeBuildDepthsInto"),
                CreateDelegate<SemanticScopeVisibleSymbolIndicesInto>(
                    programType,
                    "SemanticScopeVisibleSymbolIndicesInto"),
                CreateDelegate<SemanticScopeLookupSymbolIndicesInto>(
                    programType,
                    "SemanticScopeLookupSymbolIndicesInto"));
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

    private delegate int ParserTokenCompactionIndicesInto(int[] tokenKinds, int[] resultIndices);
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
    private delegate int AnalyzerMissingMemberIndicesInto(int[] coveredFlags, int count, int[] resultIndices);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);
    private delegate int SemanticScopeVisibleSymbolIndicesInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultSymbolIndices,
        int[] slotNameIds,
        int[] touchedSlots);
    private delegate int SemanticScopeBuildSortedIndexInto(
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] tempScopeIds,
        int[] stackLefts,
        int[] stackRights,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines);
    private delegate int SemanticScopeBuildDepthsInto(
        int[] scopeParentIds,
        int[] scopeDepths);
    private delegate int SemanticScopeLookupSymbolIndicesInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryNameIds,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultSymbolIndices);

    private sealed record Bindings(
        ParserTokenCompactionIndicesInto ParserTokenCompaction,
        FormatterImportOrderIndicesInto FormatterImportOrderIndices,
        FirstDistinctRankIndicesInto FirstDistinctRankIndices,
        DeclaredTypeUniqueSuffixValueRank DeclaredTypeUniqueSuffixValueRank,
        DeclaredTypeNameCandidateIndex DeclaredTypeNameCandidateIndex,
        TypeCreationOrderIndicesInto TypeCreationOrderIndices,
        ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks,
        AnonymousUnionDeclaresPublicShim AnonymousUnionDeclaresPublicShim,
        AnalyzerMissingMemberIndicesInto AnalyzerMissingMemberIndices,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices,
        SemanticScopeBuildSortedIndexInto SemanticScopeBuildSortedIndex,
        SemanticScopeBuildDepthsInto SemanticScopeBuildDepths,
        SemanticScopeVisibleSymbolIndicesInto SemanticScopeVisibleSymbolIndices,
        SemanticScopeLookupSymbolIndicesInto SemanticScopeLookupSymbolIndices);

    private sealed class SemanticScopeCache
    {
        private readonly object _gate = new();
        private readonly SemanticModel _model;
        private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);
        private readonly int[] _lookupResultSymbolIndices = new int[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly int[] _queryNameIds = new int[1];
        private readonly int[] _resultCounts = new int[1];
        private readonly int[] _resultScopeIds = new int[1];
        private readonly int[] _resultStarts = new int[1];

        private int[] _scopeDepths = Array.Empty<int>();
        private int[] _scopeEndColumns = Array.Empty<int>();
        private int[] _scopeEndLines = Array.Empty<int>();
        private int[] _scopeParentIds = Array.Empty<int>();
        private int[] _scopeStartColumns = Array.Empty<int>();
        private int[] _scopeStartLines = Array.Empty<int>();
        private int[] _scopeSymbolCounts = Array.Empty<int>();
        private int[] _scopeSymbolStarts = Array.Empty<int>();
        private int[] _resultSymbolIndices = Array.Empty<int>();
        private int[] _slotNameIds = Array.Empty<int>();
        private int[] _sortStackLefts = Array.Empty<int>();
        private int[] _sortStackRights = Array.Empty<int>();
        private int[] _sortTempScopeIds = Array.Empty<int>();
        private int[] _sortedScopeIds = Array.Empty<int>();
        private int[] _sortedScopeMaxEndLines = Array.Empty<int>();
        private int[] _sortedScopeStartColumns = Array.Empty<int>();
        private int[] _sortedScopeStartLines = Array.Empty<int>();
        private int[] _symbolNameIds = Array.Empty<int>();
        private string[] _symbolNames = Array.Empty<string>();
        private TypeInfo[] _symbolTypes = Array.Empty<TypeInfo>();
        private int[] _touchedSlots = Array.Empty<int>();
        private int _version = -1;

        public SemanticScopeCache(SemanticModel model)
        {
            _model = model;
        }

        public bool TryGetVisibleVariablesAtPosition(
            Bindings bindings,
            int line,
            int column,
            out Dictionary<string, TypeInfo> visibleVariables)
        {
            visibleVariables = new Dictionary<string, TypeInfo>();

            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_scopeParentIds.Length == 0)
                {
                    visibleVariables = new Dictionary<string, TypeInfo>(_model.Variables);
                    return true;
                }

                EnsureQueryCapacity();
                _queryLines[0] = line;
                _queryColumns[0] = column;
                _resultScopeIds[0] = -1;
                _resultStarts[0] = 0;
                _resultCounts[0] = 0;

                var total = bindings.SemanticScopeVisibleSymbolIndices(
                    _scopeParentIds,
                    _scopeStartLines,
                    _scopeStartColumns,
                    _scopeEndLines,
                    _scopeEndColumns,
                    _scopeDepths,
                    _scopeSymbolStarts,
                    _scopeSymbolCounts,
                    _symbolNameIds,
                    _sortedScopeIds,
                    _sortedScopeStartLines,
                    _sortedScopeStartColumns,
                    _sortedScopeMaxEndLines,
                    _queryLines,
                    _queryColumns,
                    _resultScopeIds,
                    _resultStarts,
                    _resultCounts,
                    _resultSymbolIndices,
                    _slotNameIds,
                    _touchedSlots);

                if (total < 0)
                    return false;

                if (_resultScopeIds[0] < 0)
                {
                    visibleVariables = new Dictionary<string, TypeInfo>(_model.Variables);
                    return true;
                }

                var start = _resultStarts[0];
                var count = _resultCounts[0];
                var result = new Dictionary<string, TypeInfo>(count);
                for (var i = 0; i < count; i++)
                {
                    var resultIndex = start + i;
                    if (resultIndex < 0 || resultIndex >= total || resultIndex >= _resultSymbolIndices.Length)
                        return false;

                    var symbolIndex = _resultSymbolIndices[resultIndex];
                    if (symbolIndex < 0 || symbolIndex >= _symbolNames.Length || symbolIndex >= _symbolTypes.Length)
                        return false;

                    result.TryAdd(_symbolNames[symbolIndex], _symbolTypes[symbolIndex]);
                }

                visibleVariables = result;
                return true;
            }
        }

        public bool TryLookupIdentifierAtPosition(
            Bindings bindings,
            string name,
            int line,
            int column,
            out TypeInfo? typeInfo)
        {
            typeInfo = null;

            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_scopeParentIds.Length == 0)
                {
                    typeInfo = _model.LookupIdentifier(name);
                    return true;
                }

                var nameId = GetExistingNameId(name);
                if (nameId < 0)
                {
                    typeInfo = LookupScopedFallback(name);
                    return true;
                }

                _queryNameIds[0] = nameId;
                _queryLines[0] = line;
                _queryColumns[0] = column;
                _resultScopeIds[0] = -1;
                _lookupResultSymbolIndices[0] = -1;

                var found = bindings.SemanticScopeLookupSymbolIndices(
                    _scopeParentIds,
                    _scopeStartLines,
                    _scopeStartColumns,
                    _scopeEndLines,
                    _scopeEndColumns,
                    _scopeDepths,
                    _scopeSymbolStarts,
                    _scopeSymbolCounts,
                    _symbolNameIds,
                    _sortedScopeIds,
                    _sortedScopeStartLines,
                    _sortedScopeStartColumns,
                    _sortedScopeMaxEndLines,
                    _queryNameIds,
                    _queryLines,
                    _queryColumns,
                    _resultScopeIds,
                    _lookupResultSymbolIndices);

                if (found < 0)
                    return false;

                var symbolIndex = _lookupResultSymbolIndices[0];
                if (symbolIndex >= 0 && symbolIndex < _symbolTypes.Length)
                {
                    typeInfo = _symbolTypes[symbolIndex];
                    return true;
                }

                typeInfo = LookupScopedFallback(name);
                return true;
            }
        }

        private void EnsureBuilt(Bindings bindings)
        {
            if (_version == _model.ScopeVersion)
                return;

            _nameIds.Clear();

            var scopes = _model.Scopes;
            var scopeCount = scopes.Count;
            _scopeParentIds = new int[scopeCount];
            _scopeStartLines = new int[scopeCount];
            _scopeStartColumns = new int[scopeCount];
            _scopeEndLines = new int[scopeCount];
            _scopeEndColumns = new int[scopeCount];
            _scopeDepths = new int[scopeCount];
            _scopeSymbolStarts = new int[scopeCount];
            _scopeSymbolCounts = new int[scopeCount];

            var symbolCount = 0;
            for (var i = 0; i < scopeCount; i++)
            {
                symbolCount += scopes[i].Variables.Count;
                symbolCount += scopes[i].Functions.Count;
            }

            _symbolNames = new string[symbolCount];
            _symbolTypes = new TypeInfo[symbolCount];
            _symbolNameIds = new int[symbolCount];

            var symbolIndex = 0;
            for (var i = 0; i < scopeCount; i++)
            {
                var scope = scopes[i];
                _scopeParentIds[i] = scope.ParentId;
                _scopeStartLines[i] = scope.StartLine;
                _scopeStartColumns[i] = scope.StartColumn;
                _scopeEndLines[i] = scope.EndLine;
                _scopeEndColumns[i] = scope.EndColumn;
                _scopeSymbolStarts[i] = symbolIndex;

                foreach (var (name, type) in scope.Variables)
                {
                    AddSymbol(name, type, ref symbolIndex);
                }

                foreach (var (name, type) in scope.Functions)
                {
                    AddSymbol(name, type, ref symbolIndex);
                }

                _scopeSymbolCounts[i] = symbolIndex - _scopeSymbolStarts[i];
            }

            BuildScopeDepths(bindings, scopeCount);
            BuildSortedScopeIndex(bindings, scopeCount);
            _version = _model.ScopeVersion;
        }

        private void BuildScopeDepths(Bindings bindings, int scopeCount)
        {
            if (scopeCount == 0)
                return;

            var dogfoodCount = bindings.SemanticScopeBuildDepths(_scopeParentIds, _scopeDepths);
            if (dogfoodCount == scopeCount)
                return;

            for (var i = 0; i < scopeCount; i++)
            {
                _scopeDepths[i] = ComputeScopeDepth(i);
            }
        }

        private void BuildSortedScopeIndex(Bindings bindings, int scopeCount)
        {
            _sortedScopeIds = new int[scopeCount];
            _sortedScopeStartLines = new int[scopeCount];
            _sortedScopeStartColumns = new int[scopeCount];
            _sortedScopeMaxEndLines = new int[scopeCount];
            _sortTempScopeIds = new int[scopeCount];
            _sortStackLefts = new int[scopeCount];
            _sortStackRights = new int[scopeCount];

            if (scopeCount == 0)
                return;

            var dogfoodCount = bindings.SemanticScopeBuildSortedIndex(
                _scopeStartLines,
                _scopeStartColumns,
                _scopeEndLines,
                _sortTempScopeIds,
                _sortStackLefts,
                _sortStackRights,
                _sortedScopeIds,
                _sortedScopeStartLines,
                _sortedScopeStartColumns,
                _sortedScopeMaxEndLines);

            if (dogfoodCount == scopeCount)
                return;

            var order = new int[scopeCount];
            for (var i = 0; i < scopeCount; i++)
            {
                order[i] = i;
            }

            Array.Sort(order, CompareScopeStartOrder);

            var maxEndLine = 0;
            for (var sortedIndex = 0; sortedIndex < scopeCount; sortedIndex++)
            {
                var scopeIndex = order[sortedIndex];
                _sortedScopeIds[sortedIndex] = scopeIndex;
                _sortedScopeStartLines[sortedIndex] = _scopeStartLines[scopeIndex];
                _sortedScopeStartColumns[sortedIndex] = _scopeStartColumns[scopeIndex];

                if (_scopeEndLines[scopeIndex] > maxEndLine)
                    maxEndLine = _scopeEndLines[scopeIndex];

                _sortedScopeMaxEndLines[sortedIndex] = maxEndLine;
            }
        }

        private int CompareScopeStartOrder(int left, int right)
        {
            var diff = _scopeStartLines[left].CompareTo(_scopeStartLines[right]);
            if (diff != 0)
                return diff;

            diff = _scopeStartColumns[left].CompareTo(_scopeStartColumns[right]);
            if (diff != 0)
                return diff;

            return left.CompareTo(right);
        }

        private void AddSymbol(string name, TypeInfo type, ref int symbolIndex)
        {
            _symbolNames[symbolIndex] = name;
            _symbolTypes[symbolIndex] = type;
            _symbolNameIds[symbolIndex] = GetOrAddNameId(name);
            symbolIndex++;
        }

        private int ComputeScopeDepth(int scopeIndex)
        {
            var depth = 0;
            var current = scopeIndex;
            while (current >= 0 && current < _scopeParentIds.Length)
            {
                var parent = _scopeParentIds[current];
                if (parent < 0 || parent == current)
                    break;

                depth++;
                current = parent;
            }

            return depth;
        }

        private int GetOrAddNameId(string name)
        {
            if (_nameIds.TryGetValue(name, out var id))
                return id;

            id = _nameIds.Count + 1;
            _nameIds.Add(name, id);
            return id;
        }

        private int GetExistingNameId(string name) => _nameIds.TryGetValue(name, out var id) ? id : -1;

        private TypeInfo? LookupScopedFallback(string name)
        {
            if (_model.Properties.TryGetValue(name, out var propType))
                return propType;
            if (_model.Fields.TryGetValue(name, out var fieldType))
                return fieldType;
            if (_model.Types.TryGetValue(name, out var type))
                return type;

            return null;
        }

        private void EnsureQueryCapacity()
        {
            var symbolCapacity = Math.Max(1, _symbolNameIds.Length);
            if (_resultSymbolIndices.Length < symbolCapacity)
            {
                _resultSymbolIndices = new int[symbolCapacity];
            }

            var slotCapacity = Math.Max(1, _symbolNameIds.Length * 2 + 1);
            if (_slotNameIds.Length < slotCapacity)
            {
                _slotNameIds = new int[slotCapacity];
            }

            if (_touchedSlots.Length < symbolCapacity)
            {
                _touchedSlots = new int[symbolCapacity];
            }
        }
    }

    private sealed class ParserTokenCompactionScratch
    {
        public int[] ResultIndices = Array.Empty<int>();
        public int[] TokenKinds = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (TokenKinds.Length != count)
            {
                TokenKinds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class FormatterImportOrderingScratch
    {
        // Distinct namespace strings keyed ordinally (so distinct strings stay distinct
        // entries), each mapped to a rank that reflects Comparer<string>.Default ordering.
        // Namespaces that compare EQUAL under that comparer share a rank, exactly mirroring
        // LINQ ThenBy(i => i.Namespace), whose ties are broken by original input order.
        private readonly Dictionary<string, int> _namespaceRanks = new(StringComparer.Ordinal);

        public int[] BucketCounts = Array.Empty<int>();
        public int[] BucketOffsets = Array.Empty<int>();
        public int[] NameRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SystemFlags = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public string[] UniqueNamespaces = Array.Empty<string>();
        public int UniqueNamespaceCount;

        public void EnsureCapacity(int count)
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

        public void AddNamespace(string ns)
        {
            if (_namespaceRanks.ContainsKey(ns))
                return;

            _namespaceRanks.Add(ns, 0);
            UniqueNamespaces[UniqueNamespaceCount] = ns;
            UniqueNamespaceCount++;
        }

        public void BuildRanks()
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

        public int GetRank(string ns) => _namespaceRanks[ns];

        public void ResetRanks()
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
        public int[] ParameterFlags = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (ParameterFlags.Length < count)
            {
                ParameterFlags = new int[count];
            }
        }
    }

    private sealed class MissingEnumMemberScratch
    {
        private readonly HashSet<string> _seenNames = new(StringComparer.Ordinal);

        public int[] CoveredFlags = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();

        public bool AddName(string name) => _seenNames.Add(name);

        public void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }

        public void ResetNames()
        {
            _seenNames.Clear();
        }
    }

    private sealed class MissingUnionCaseScratch
    {
        public int[] MissingIndices = Array.Empty<int>();
        public int[] NeverCoveredIndices = Array.Empty<int>();
        public int[] PartialMissingIndices = Array.Empty<int>();
        public int[] ResultCounts = new int[3];

        public void EnsureCapacity(int count)
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

        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int[] TypeRanks = Array.Empty<int>();
        public int UniqueKeyCount;

        public void EnsureCapacity(int count)
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

        public int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        public void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class FirstDistinctStringScratch(IEqualityComparer<string> comparer)
    {
        private readonly Dictionary<string, int> _keyRanks = new(comparer);

        public int[] Ranks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int UniqueKeyCount;

        public void EnsureCapacity(int count)
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

        public int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        public void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class DistinctOrderedStringScratch
    {
        private readonly Dictionary<string, int> _valueRanks = new(StringComparer.Ordinal);

        public int[] CountsByRank = Array.Empty<int>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueValues = Array.Empty<string>();
        public int[] ValueRanks = Array.Empty<int>();
        public string[] Values = Array.Empty<string>();
        public int UniqueValueCount;

        public void EnsureCapacity(int count)
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

        public void AddValue(string value)
        {
            if (_valueRanks.ContainsKey(value))
                return;

            _valueRanks.Add(value, 0);
            UniqueValues[UniqueValueCount] = value;
            UniqueValueCount++;
        }

        public void BuildRanks()
        {
            Array.Sort(UniqueValues, 0, UniqueValueCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueValueCount; i++)
            {
                _valueRanks[UniqueValues[i]] = i + 1;
            }
        }

        public int GetRank(string value) => _valueRanks[value];

        public void ClearValues(int count) => Array.Clear(Values, 0, count);

        public void ResetValues()
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

        public int Count;
        public string[] Keys = Array.Empty<string>();
        public int[] TailHashes = Array.Empty<int>();
        public int[] ValueRanks = Array.Empty<int>();
        public Type[] Values = Array.Empty<Type>();

        public bool Load<TType>(IReadOnlyDictionary<string, TType> types)
            where TType : Type
        {
            var count = types.Count;
            if (ReferenceEquals(_source, types) && _sourceCount == count)
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

        public void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = GetTailHash(Keys[i], width);
            }

            _tailHashWidth = width;
        }

        public static int GetTailHashWidth(string text) => Math.Min(4, text.Length);

        public static int GetTailHash(string text, int width)
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

        public int Count;
        public int[] ImportedNamespaceFlags = Array.Empty<int>();
        public string[] Names = Array.Empty<string>();
        public int[] TailHashes = Array.Empty<int>();

        public void Load(CompilationUnit compilationUnit)
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

        public void RefreshTailHashes(int width)
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
        public int Count;
        public int[] DepthCounts = Array.Empty<int>();
        public int[] DepthOffsets = Array.Empty<int>();
        public int[] DotCounts = Array.Empty<int>();
        public string[] Keys = Array.Empty<string>();
        public int[] ResultIndices = Array.Empty<int>();
        public Type[] Values = Array.Empty<Type>();

        public bool Load<TType>(IEnumerable<TType> types, Func<TType, string> getTypeKey)
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

        public void ClearValues()
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
