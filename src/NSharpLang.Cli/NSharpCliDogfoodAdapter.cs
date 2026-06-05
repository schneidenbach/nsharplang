using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static BatchDuplicateIdScratch? t_batchDuplicateIdScratch;
    [ThreadStatic]
    private static BuildOperandScratch? t_buildOperandScratch;
    [ThreadStatic]
    private static DocSymbolOrderScratch? t_docSymbolOrderScratch;
    [ThreadStatic]
    private static TreeDependencyDeduplicateScratch? t_treeDependencyDeduplicateScratch;
    [ThreadStatic]
    private static CompilerErrorSeverityFilterScratch? t_compilerErrorSeverityFilterScratch;
    [ThreadStatic]
    private static FixSafetyFilterScratch? t_fixSafetyFilterScratch;
    [ThreadStatic]
    private static CleanArtifactDirectoryScratch? t_cleanArtifactDirectoryScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

    internal static bool IsAvailable => s_bindings.Value != null;

    internal static bool TryGetBuildOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            firstOperandIndex = bindings.CliBuildFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            count = firstOperandIndex >= 0 ? 1 : 0;
            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    internal static bool TryGetFirstPositionalArg(
        string[] args,
        string[] optionsWithValues,
        out string? positional)
    {
        positional = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.CliFirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            positional = args[index];
            return true;
        }
        catch
        {
            positional = null;
            return false;
        }
    }

    internal static bool TryGetExportCSharpInputOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var index = bindings.CliExportCSharpFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static bool TryFindDuplicateBatchRequestIds(
        IReadOnlyList<BatchQueryRequest> requests,
        out string[] duplicateIds)
    {
        duplicateIds = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var requestCount = requests.Count;
        if (requestCount == 0)
            return true;

        var scratch = t_batchDuplicateIdScratch ??= new BatchDuplicateIdScratch();
        scratch.EnsureCapacity(requestCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                if (!string.IsNullOrWhiteSpace(id))
                {
                    scratch.AddId(id);
                }
            }

            if (scratch.UniqueIdCount == 0)
                return true;

            scratch.BuildSortedRanks();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                scratch.IdRanks[i] = string.IsNullOrWhiteSpace(id)
                    ? 0
                    : scratch.GetIdRank(id);
            }

            var duplicateCount = bindings.CliBatchDuplicateIdRanks(
                scratch.IdRanks,
                scratch.UniqueIdCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (duplicateCount < 0 ||
                duplicateCount > scratch.UniqueIdCount ||
                duplicateCount > scratch.ResultRanks.Length)
            {
                return false;
            }

            if (duplicateCount == 0)
                return true;

            duplicateIds = new string[duplicateCount];
            for (var i = 0; i < duplicateCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueIdCount)
                {
                    duplicateIds = Array.Empty<string>();
                    return false;
                }

                duplicateIds[i] = scratch.UniqueIds[rank - 1];
            }

            return true;
        }
        catch
        {
            duplicateIds = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static bool TryOrderDocSymbolsForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        out List<SymbolResult> orderedSymbols)
        => TryOrderDocEntriesForGeneration(symbols, includeAllKinds: false, out orderedSymbols);

    internal static bool TryOrderDocMembersForGeneration(
        IReadOnlyList<SymbolResult> members,
        out List<SymbolResult> orderedMembers)
        => TryOrderDocEntriesForGeneration(members, includeAllKinds: true, out orderedMembers);

    internal static bool TryDeduplicateTreeDependencyIndices(
        int[] kindRanks,
        int[] nameRanks,
        int uniqueKindCount,
        int uniqueNameCount,
        out int[] orderedSourceIndices)
    {
        orderedSourceIndices = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (kindRanks.Length != nameRanks.Length)
            return false;

        var dependencyCount = kindRanks.Length;
        if (dependencyCount == 0)
            return true;

        var scratch = t_treeDependencyDeduplicateScratch ??= new TreeDependencyDeduplicateScratch();
        scratch.EnsureCapacity(dependencyCount, uniqueKindCount, uniqueNameCount);

        try
        {
            var orderedCount = bindings.CliTreeDependencyDeduplicateIndices(
                kindRanks,
                nameRanks,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.SortedIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > dependencyCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedSourceIndices = new int[orderedCount];
            Array.Copy(scratch.ResultIndices, orderedSourceIndices, orderedCount);
            return true;
        }
        catch
        {
            orderedSourceIndices = Array.Empty<int>();
            return false;
        }
    }

    internal static bool TryFilterCompilerErrorsBySeverity(
        IReadOnlyList<CompilerError> errors,
        ErrorSeverity severity,
        out List<CompilerError> filteredErrors)
    {
        filteredErrors = new List<CompilerError>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var targetRank = GetCompilerErrorSeverityRank(severity);
        if (targetRank == 0)
            return false;

        var errorCount = errors.Count;
        if (errorCount == 0)
            return true;

        var scratch = t_compilerErrorSeverityFilterScratch ??= new CompilerErrorSeverityFilterScratch();
        scratch.EnsureCapacity(errorCount);

        try
        {
            for (var i = 0; i < errorCount; i++)
            {
                scratch.SeverityRanks[i] = GetCompilerErrorSeverityRank(errors[i].Severity);
            }

            var filteredCount = bindings.DiagnosticSeverityFilter(
                scratch.SeverityRanks,
                targetRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > errorCount || filteredCount > scratch.ResultIndices.Length)
            {
                filteredErrors = new List<CompilerError>();
                return false;
            }

            filteredErrors = new List<CompilerError>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= errorCount)
                {
                    filteredErrors = new List<CompilerError>();
                    return false;
                }

                filteredErrors.Add(errors[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredErrors = new List<CompilerError>();
            return false;
        }
    }

    internal static bool TryOrderCleanArtifactDirectories(
        IReadOnlyList<string> directories,
        out string[] orderedDirectories)
    {
        orderedDirectories = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var directoryCount = directories.Count;
        if (directoryCount == 0)
            return true;

        var scratch = t_cleanArtifactDirectoryScratch ??= new CleanArtifactDirectoryScratch();
        scratch.EnsureInputCapacity(directoryCount);

        try
        {
            scratch.ResetPathRanks();
            var maxPathLength = 0;
            for (var i = 0; i < directoryCount; i++)
            {
                var directory = directories[i];
                scratch.KindRanks[i] = CleanCommand.IsArtifactDirectoryName(Path.GetFileName(directory)) ? 1 : 0;
                scratch.NodeModuleFlags[i] = CleanCommand.IsUnderNodeModulesDirectory(directory) ? 1 : 0;
                scratch.PathLengths[i] = directory.Length;
                scratch.AddPath(directory);

                if (directory.Length > maxPathLength)
                    maxPathLength = directory.Length;
            }

            scratch.EnsureScratchCapacity(scratch.UniquePathCount, maxPathLength);
            for (var i = 0; i < directoryCount; i++)
            {
                scratch.PathRanks[i] = scratch.GetPathRank(directories[i]);
            }

            var orderedCount = bindings.CliCleanArtifactDirectoryIndices(
                scratch.KindRanks,
                scratch.NodeModuleFlags,
                scratch.PathRanks,
                scratch.PathLengths,
                scratch.SeenPathRanks,
                scratch.LengthCounts,
                scratch.LengthOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > directoryCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedDirectories = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= directoryCount)
                {
                    orderedDirectories = Array.Empty<string>();
                    return false;
                }

                orderedDirectories[i] = directories[sourceIndex];
            }

            return true;
        }
        catch
        {
            orderedDirectories = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetPathRanks();
        }
    }

    internal static bool TryFilterFixesBySafety(
        IReadOnlyList<CodeAction> fixes,
        bool includeReviewNeeded,
        out List<CodeAction> safeActions)
    {
        safeActions = new List<CodeAction>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fixCount = fixes.Count;
        if (fixCount == 0)
            return true;

        var scratch = t_fixSafetyFilterScratch ??= new FixSafetyFilterScratch();
        scratch.EnsureCapacity(fixCount);

        try
        {
            for (var i = 0; i < fixCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixSafetyRank(fixes[i].Safety);
            }

            var safeCount = bindings.CliFixSafetyFilter(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (safeCount < 0 || safeCount > fixCount || safeCount > scratch.ResultIndices.Length)
            {
                safeActions = new List<CodeAction>();
                return false;
            }

            safeActions = new List<CodeAction>(safeCount);
            for (var i = 0; i < safeCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fixCount)
                {
                    safeActions = new List<CodeAction>();
                    return false;
                }

                safeActions.Add(fixes[sourceIndex]);
            }

            return true;
        }
        catch
        {
            safeActions = new List<CodeAction>();
            return false;
        }
    }

    internal static bool TrySelectSkippedFixEntries(
        IReadOnlyList<FixEntry> results,
        bool includeReviewNeeded,
        out List<FixEntry> skipped)
    {
        skipped = new List<FixEntry>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultCount = results.Count;
        if (resultCount == 0)
            return true;

        var scratch = t_fixSafetyFilterScratch ??= new FixSafetyFilterScratch();
        scratch.EnsureCapacity(resultCount);

        try
        {
            for (var i = 0; i < resultCount; i++)
            {
                scratch.SafetyRanks[i] = GetFixEntrySafetyRank(results[i].Safety);
            }

            var skippedCount = bindings.CliFixSkippedIndices(
                scratch.SafetyRanks,
                includeReviewNeeded ? 1 : 0,
                scratch.ResultIndices);

            if (skippedCount < 0 || skippedCount > resultCount || skippedCount > scratch.ResultIndices.Length)
            {
                skipped = new List<FixEntry>();
                return false;
            }

            skipped = new List<FixEntry>(skippedCount);
            for (var i = 0; i < skippedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= resultCount)
                {
                    skipped = new List<FixEntry>();
                    return false;
                }

                skipped.Add(results[sourceIndex]);
            }

            return true;
        }
        catch
        {
            skipped = new List<FixEntry>();
            return false;
        }
    }

    private static bool TryOrderDocEntriesForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        bool includeAllKinds,
        out List<SymbolResult> orderedSymbols)
    {
        orderedSymbols = new List<SymbolResult>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var symbolCount = symbols.Count;
        if (symbolCount == 0)
            return true;

        var scratch = t_docSymbolOrderScratch ??= new DocSymbolOrderScratch();
        scratch.EnsureCapacity(symbolCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < symbolCount; i++)
            {
                scratch.AddName(symbols[i].Name);
            }

            scratch.BuildSortedNameRanks();
            for (var i = 0; i < symbolCount; i++)
            {
                var symbol = symbols[i];
                scratch.KindRanks[i] = GetDocSymbolKindRank(symbol.Kind);
                scratch.NameRanks[i] = scratch.GetNameRank(symbol.Name);
                scratch.IncludeFlags[i] = (includeAllKinds || IsDocumentedSymbolKind(symbol.Kind)) ? 1 : 0;
            }

            var orderedCount = bindings.CliDocSymbolOrderCountingIndices(
                scratch.KindRanks,
                scratch.NameRanks,
                scratch.IncludeFlags,
                scratch.NameCounts,
                scratch.NameOffsets,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > symbolCount || orderedCount > scratch.ResultIndices.Length)
                return false;

            orderedSymbols = new List<SymbolResult>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= symbolCount)
                {
                    orderedSymbols = new List<SymbolResult>();
                    return false;
                }

                orderedSymbols.Add(symbols[sourceIndex]);
            }

            return true;
        }
        catch
        {
            orderedSymbols = new List<SymbolResult>();
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
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
                CreateDelegate<CliBuildFirstOperandIndexInto>(programType, "CliBuildFirstOperandIndexInto"),
                CreateDelegate<CliExportCSharpFirstOperandIndexInto>(programType, "CliExportCSharpFirstOperandIndexInto"),
                CreateDelegate<CliFirstPositionalArgIndex>(programType, "CliFirstPositionalArgIndex"),
                CreateDelegate<CliBatchDuplicateIdRanksInto>(programType, "CliBatchDuplicateIdRanksInto"),
                CreateDelegate<CliDocSymbolOrderCountingIndicesInto>(programType, "CliDocSymbolOrderCountingIndicesInto"),
                CreateDelegate<CliTreeDependencyDeduplicateIndicesInto>(programType, "CliTreeDependencyDeduplicateIndicesInto"),
                CreateDelegate<DiagnosticSeverityFilterIndicesInto>(programType, "DiagnosticSeverityFilterIndicesInto"),
                CreateDelegate<CliFixSafetyFilterIndicesInto>(programType, "CliFixSafetyFilterIndicesInto"),
                CreateDelegate<CliFixSkippedIndicesInto>(programType, "CliFixSkippedIndicesInto"),
                CreateDelegate<CliCleanArtifactDirectoryIndicesInto>(programType, "CliCleanArtifactDirectoryIndicesInto"));
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

    private delegate int CliBuildFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliExportCSharpFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliBatchDuplicateIdRanksInto(
        int[] idRanks,
        int uniqueIdCount,
        int[] countsByRank,
        int[] resultRanks);

    private delegate int CliDocSymbolOrderCountingIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] includeFlags,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private delegate int CliTreeDependencyDeduplicateIndicesInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] sortedIndices,
        int[] resultIndices);

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private delegate int CliFixSafetyFilterIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliFixSkippedIndicesInto(
        int[] safetyRanks,
        int includeReviewNeeded,
        int[] resultIndices);

    private delegate int CliCleanArtifactDirectoryIndicesInto(
        int[] kindRanks,
        int[] nodeModuleFlags,
        int[] pathRanks,
        int[] pathLengths,
        int[] seenPathRanks,
        int[] lengthCounts,
        int[] lengthOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private sealed record Bindings(
        CliBuildFirstOperandIndexInto CliBuildFirstOperandIndex,
        CliExportCSharpFirstOperandIndexInto CliExportCSharpFirstOperandIndex,
        CliFirstPositionalArgIndex CliFirstPositionalArgIndex,
        CliBatchDuplicateIdRanksInto CliBatchDuplicateIdRanks,
        CliDocSymbolOrderCountingIndicesInto CliDocSymbolOrderCountingIndices,
        CliTreeDependencyDeduplicateIndicesInto CliTreeDependencyDeduplicateIndices,
        DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter,
        CliFixSafetyFilterIndicesInto CliFixSafetyFilter,
        CliFixSkippedIndicesInto CliFixSkippedIndices,
        CliCleanArtifactDirectoryIndicesInto CliCleanArtifactDirectoryIndices);

    private static bool IsDocumentedSymbolKind(SymbolKind kind) =>
        kind is not SymbolKind.Variable and not SymbolKind.Parameter;

    private static int GetDocSymbolKindRank(SymbolKind kind) =>
        kind switch
        {
            SymbolKind.Class => 1,
            SymbolKind.Constructor => 2,
            SymbolKind.Enum => 3,
            SymbolKind.EnumMember => 4,
            SymbolKind.Field => 5,
            SymbolKind.Function => 6,
            SymbolKind.Interface => 7,
            SymbolKind.Method => 8,
            SymbolKind.Parameter => 9,
            SymbolKind.Property => 10,
            SymbolKind.Record => 11,
            SymbolKind.Struct => 12,
            SymbolKind.Test => 13,
            SymbolKind.TypeAlias => 14,
            SymbolKind.Union => 15,
            SymbolKind.Variable => 16,
            _ => 100
        };

    private static int GetCompilerErrorSeverityRank(ErrorSeverity severity) =>
        severity switch
        {
            ErrorSeverity.Error => 1,
            ErrorSeverity.Warning => 2,
            _ => 0
        };

    private static int GetFixSafetyRank(FixSafety safety) =>
        safety switch
        {
            FixSafety.Safe => 1,
            FixSafety.ReviewNeeded => 2,
            FixSafety.SuggestionOnly => 3,
            _ => 0
        };

    private static int GetFixEntrySafetyRank(string safety) =>
        safety switch
        {
            "safe" => 1,
            "reviewNeeded" => 2,
            "suggestionOnly" => 3,
            _ => 0
        };

    private sealed class BuildOperandScratch
    {
        public int[] KindIds = Array.Empty<int>();
        public int[] NextIndices = Array.Empty<int>();
        public int[] NextOptionIndices = Array.Empty<int>();
        public int[] PreviousIndices = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                NextIndices = new int[count];
                NextOptionIndices = new int[count];
                PreviousIndices = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class BatchDuplicateIdScratch
    {
        private readonly Dictionary<string, int> _idRanks = new(StringComparer.Ordinal);

        public int[] CountsByRank = Array.Empty<int>();
        public int[] IdRanks = Array.Empty<int>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueIds = Array.Empty<string>();
        public int UniqueIdCount;

        public void EnsureCapacity(int requestCount)
        {
            if (IdRanks.Length != requestCount)
            {
                IdRanks = new int[requestCount];
                ResultRanks = new int[requestCount];
                UniqueIds = new string[requestCount];
            }

            var rankCapacity = requestCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        public void AddId(string id)
        {
            if (_idRanks.ContainsKey(id))
                return;

            _idRanks.Add(id, 0);
            UniqueIds[UniqueIdCount] = id;
            UniqueIdCount++;
        }

        public void BuildSortedRanks()
        {
            Array.Sort(UniqueIds, 0, UniqueIdCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueIdCount; i++)
            {
                _idRanks[UniqueIds[i]] = i + 1;
            }
        }

        public int GetIdRank(string id) => _idRanks[id];

        public void ResetIds()
        {
            _idRanks.Clear();
            if (UniqueIdCount > 0)
            {
                Array.Clear(UniqueIds, 0, UniqueIdCount);
                UniqueIdCount = 0;
            }
        }
    }

    private sealed class DocSymbolOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.Ordinal);

        public int[] IncludeFlags = Array.Empty<int>();
        public int[] KindCounts = Array.Empty<int>();
        public int[] KindOffsets = Array.Empty<int>();
        public int[] KindRanks = Array.Empty<int>();
        public int[] NameCounts = Array.Empty<int>();
        public int[] NameOffsets = Array.Empty<int>();
        public int[] NameRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public string[] UniqueNames = Array.Empty<string>();
        public int UniqueNameCount;

        public void EnsureCapacity(int symbolCount)
        {
            if (KindRanks.Length != symbolCount)
            {
                KindRanks = new int[symbolCount];
                NameRanks = new int[symbolCount];
                IncludeFlags = new int[symbolCount];
                TempIndices = new int[symbolCount];
                ResultIndices = new int[symbolCount];
                UniqueNames = new string[symbolCount];
            }

            var nameRankCapacity = symbolCount + 1;
            if (NameCounts.Length != nameRankCapacity)
            {
                NameCounts = new int[nameRankCapacity];
                NameOffsets = new int[nameRankCapacity];
            }

            if (KindCounts.Length != 32)
            {
                KindCounts = new int[32];
                KindOffsets = new int[32];
            }
        }

        public void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            _nameRanks.Add(name, 0);
            UniqueNames[UniqueNameCount] = name;
            UniqueNameCount++;
        }

        public void BuildSortedNameRanks()
        {
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueNameCount; i++)
            {
                _nameRanks[UniqueNames[i]] = i + 1;
            }
        }

        public int GetNameRank(string name) => _nameRanks[name];

        public void ResetNames()
        {
            _nameRanks.Clear();
            if (UniqueNameCount > 0)
            {
                Array.Clear(UniqueNames, 0, UniqueNameCount);
                UniqueNameCount = 0;
            }
        }
    }

    private sealed class TreeDependencyDeduplicateScratch
    {
        public int[] KindCounts = Array.Empty<int>();
        public int[] KindOffsets = Array.Empty<int>();
        public int[] NameCounts = Array.Empty<int>();
        public int[] NameOffsets = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SortedIndices = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();

        public void EnsureCapacity(int dependencyCount, int uniqueKindCount, int uniqueNameCount)
        {
            if (TempIndices.Length != dependencyCount)
            {
                TempIndices = new int[dependencyCount];
                SortedIndices = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }

            var kindBucketCapacity = uniqueKindCount + 1;
            if (KindCounts.Length != kindBucketCapacity)
            {
                KindCounts = new int[kindBucketCapacity];
                KindOffsets = new int[kindBucketCapacity];
            }

            var nameBucketCapacity = uniqueNameCount + 1;
            if (NameCounts.Length != nameBucketCapacity)
            {
                NameCounts = new int[nameBucketCapacity];
                NameOffsets = new int[nameBucketCapacity];
            }
        }
    }

    private sealed class CompilerErrorSeverityFilterScratch
    {
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeverityRanks = Array.Empty<int>();

        public void EnsureCapacity(int errorCount)
        {
            if (SeverityRanks.Length != errorCount)
            {
                SeverityRanks = new int[errorCount];
                ResultIndices = new int[errorCount];
            }
        }
    }

    private sealed class FixSafetyFilterScratch
    {
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SafetyRanks = Array.Empty<int>();

        public void EnsureCapacity(int fixCount)
        {
            if (SafetyRanks.Length != fixCount)
            {
                SafetyRanks = new int[fixCount];
                ResultIndices = new int[fixCount];
            }
        }
    }

    private sealed class CleanArtifactDirectoryScratch
    {
        private readonly Dictionary<string, int> _pathRanks = new(StringComparer.Ordinal);

        public int[] KindRanks = Array.Empty<int>();
        public int[] LengthCounts = Array.Empty<int>();
        public int[] LengthOffsets = Array.Empty<int>();
        public int[] NodeModuleFlags = Array.Empty<int>();
        public int[] PathLengths = Array.Empty<int>();
        public int[] PathRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenPathRanks = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public int UniquePathCount;

        public void EnsureInputCapacity(int directoryCount)
        {
            if (KindRanks.Length != directoryCount)
            {
                KindRanks = new int[directoryCount];
                NodeModuleFlags = new int[directoryCount];
                PathRanks = new int[directoryCount];
                PathLengths = new int[directoryCount];
                TempIndices = new int[directoryCount];
                ResultIndices = new int[directoryCount];
            }
        }

        public void EnsureScratchCapacity(int uniquePathCount, int maxPathLength)
        {
            var pathRankCapacity = uniquePathCount + 1;
            if (SeenPathRanks.Length != pathRankCapacity)
            {
                SeenPathRanks = new int[pathRankCapacity];
            }

            var lengthCapacity = maxPathLength + 1;
            if (LengthCounts.Length != lengthCapacity)
            {
                LengthCounts = new int[lengthCapacity];
                LengthOffsets = new int[lengthCapacity];
            }
        }

        public void AddPath(string path)
        {
            if (_pathRanks.ContainsKey(path))
                return;

            UniquePathCount++;
            _pathRanks.Add(path, UniquePathCount);
        }

        public int GetPathRank(string path) => _pathRanks[path];

        public void ResetPathRanks()
        {
            _pathRanks.Clear();
            UniquePathCount = 0;
        }
    }
}
