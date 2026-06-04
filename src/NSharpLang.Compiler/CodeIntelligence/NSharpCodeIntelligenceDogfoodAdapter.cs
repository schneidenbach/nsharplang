using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class NSharpCodeIntelligenceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<BindingMap, BindingLookupCache> s_bindingLookupCaches = new();
    private static readonly ConditionalWeakTable<SemanticModel, SemanticScopeCache> s_semanticScopeCaches = new();
    private static readonly ConditionalWeakTable<ProjectSnapshot, SnapshotCache> s_snapshotCaches = new();
    private static readonly ConditionalWeakTable<string, SourceLineCache> s_sourceLineCaches = new();
    [ThreadStatic]
    private static BindingCandidateColumnScratch? t_bindingCandidateColumnScratch;
    [ThreadStatic]
    private static CompletionItemGroupingScratch? t_completionItemGroupingScratch;
    [ThreadStatic]
    private static CompletionMethodGroupingScratch? t_completionMethodGroupingScratch;
    [ThreadStatic]
    private static CompletionReceiverScratch? t_completionReceiverScratch;
    [ThreadStatic]
    private static DiagnosticSummaryScratch? t_diagnosticSummaryScratch;
    [ThreadStatic]
    private static DiagnosticClusterGroupingScratch? t_diagnosticClusterGroupingScratch;
    [ThreadStatic]
    private static ReferenceFileSummaryScratch? t_diagnosticClusterFileSummaryScratch;
    [ThreadStatic]
    private static DiagnosticDeduplicationScratch? t_diagnosticDeduplicationScratch;
    [ThreadStatic]
    private static ReferenceFileSummaryScratch? t_referenceFileSummaryScratch;
    [ThreadStatic]
    private static ReferenceDeduplicationScratch? t_referenceDeduplicationScratch;
    [ThreadStatic]
    private static TextEditOrderingScratch? t_textEditOrderingScratch;

    internal static bool IsAvailable => s_bindings.Value != null;

    internal static bool TryGetBindingCandidateColumns(
        int column,
        (int StartColumn, int EndColumn)? span,
        out int[] candidateColumns)
    {
        candidateColumns = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var maxCandidateCount = 3;
        if (span is { } spanValue && spanValue.StartColumn > 0 && spanValue.EndColumn >= spanValue.StartColumn)
        {
            var spanLength = spanValue.EndColumn - spanValue.StartColumn + 1;
            if (spanLength < 0)
                return false;

            maxCandidateCount += spanLength;
        }

        var scratch = t_bindingCandidateColumnScratch ??= new BindingCandidateColumnScratch();
        scratch.EnsureCapacity(maxCandidateCount);
        scratch.QueryColumns[0] = column;
        scratch.SpanStartColumns[0] = span?.StartColumn ?? -1;
        scratch.SpanEndColumns[0] = span?.EndColumn ?? -1;

        try
        {
            var total = bindings.BindingLookupCandidateColumns(
                scratch.QueryColumns,
                scratch.SpanStartColumns,
                scratch.SpanEndColumns,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultColumns);
            var count = scratch.ResultCounts[0];
            if (total < 0 || total > scratch.ResultColumns.Length || count < 0 || count > total)
                return false;

            candidateColumns = new int[count];
            Array.Copy(scratch.ResultColumns, scratch.ResultStarts[0], candidateColumns, 0, count);
            return true;
        }
        catch
        {
            candidateColumns = Array.Empty<int>();
            return false;
        }
    }

    internal static bool TryOrderTextEdits(
        IReadOnlyCollection<TextEdit> edits,
        out List<TextEdit> sortedEdits)
    {
        sortedEdits = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = edits.Count;
        if (count == 0)
            return true;

        var editArray = edits as TextEdit[] ?? edits.ToArray();
        var scratch = t_textEditOrderingScratch ??= new TextEditOrderingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            var startPositionRankCount = scratch.BuildRanks(
                editArray,
                count,
                TextEditOrderingPosition.Start,
                scratch.StartPositionRanks);
            var endPositionRankCount = scratch.BuildRanks(
                editArray,
                count,
                TextEditOrderingPosition.End,
                scratch.EndPositionRanks);

            var orderedCount = bindings.TextEditOrderIndices(
                scratch.StartPositionRanks,
                scratch.EndPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                scratch.BucketCounts,
                scratch.BucketOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount != count)
                return false;

            sortedEdits = new List<TextEdit>(count);
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    sortedEdits = [];
                    return false;
                }

                sortedEdits.Add(editArray[sourceIndex]);
            }

            return true;
        }
        catch
        {
            sortedEdits = [];
            return false;
        }
        finally
        {
            scratch.Reset();
        }
    }

    internal static bool TryExtractIdentifierSpan(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out (int StartColumn, int EndColumn)? span)
    {
        span = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractIdentifierSpan(bindings, line, column, out span);
        }
        catch
        {
            span = null;
            return false;
        }
    }

    internal static bool TryExtractDocComment(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int definitionLine,
        out string? documentation)
    {
        documentation = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractDocComment(bindings, definitionLine, out documentation);
        }
        catch
        {
            documentation = null;
            return false;
        }
    }

    internal static bool TrySelectedSpanMatchesDeclarationName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int declarationColumn,
        string declarationName,
        int selectedStartColumn,
        int selectedEndColumn,
        out bool matches)
    {
        matches = false;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TrySelectedSpanMatchesDeclarationName(
                bindings,
                line,
                declarationColumn,
                declarationName,
                selectedStartColumn,
                selectedEndColumn,
                out matches);
        }
        catch
        {
            matches = false;
            return false;
        }
    }

    internal static bool TryFindIdentifierNameColumn(
        string? source,
        string name,
        int line,
        int fallbackColumn,
        out int column)
    {
        column = fallbackColumn;
        if (source == null || string.IsNullOrWhiteSpace(name))
            return false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryFindIdentifierNameColumn(bindings, name, line, fallbackColumn, out column);
        }
        catch
        {
            column = fallbackColumn;
            return false;
        }
    }

    internal static bool TryExtractCompletionPrefix(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out string? prefix)
    {
        prefix = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractCompletionPrefix(bindings, line, column, out prefix);
        }
        catch
        {
            prefix = null;
            return false;
        }
    }

    internal static bool TryExtractIdentifierName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int column,
        out string? name)
    {
        name = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractIdentifierName(bindings, line, column, out name);
        }
        catch
        {
            name = null;
            return false;
        }
    }

    internal static bool TryExtractMemberReceiverName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        int memberStartColumn,
        out string? receiverName)
    {
        receiverName = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractMemberReceiverName(bindings, line, memberStartColumn, out receiverName);
        }
        catch
        {
            receiverName = null;
            return false;
        }
    }

    internal static bool TryExtractSourceContext(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? context)
    {
        context = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractSourceContext(bindings, line, out context);
        }
        catch
        {
            context = null;
            return false;
        }
    }

    internal static bool TryExtractSourceLine(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? text)
    {
        text = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractSourceLine(bindings, line, out text);
        }
        catch
        {
            text = null;
            return false;
        }
    }

    internal static bool TryExtractSourceLine(string source, int line, out string? text)
    {
        text = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryExtractSourceLine(bindings, line, out text);
        }
        catch
        {
            text = null;
            return false;
        }
    }

    internal static bool TryExtractEditorIdentifierSpan(
        string source,
        int line,
        int column,
        out (int StartColumn, int EndColumn, string Name)? span)
    {
        span = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_sourceLineCaches.GetValue(source, static key => new SourceLineCache(key));
            return cache.TryExtractEditorIdentifierSpan(bindings, line, column, out span);
        }
        catch
        {
            span = null;
            return false;
        }
    }

    internal static bool TryExtractVariableDeclarationName(
        ProjectSnapshot snapshot,
        string filePath,
        string source,
        int line,
        out string? name)
    {
        name = null;
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = GetFileCache(snapshot, filePath, source);
            return cache.TryExtractVariableDeclarationName(bindings, line, out name);
        }
        catch
        {
            name = null;
            return false;
        }
    }

    internal static bool TryClassifyDiagnosticClusterTraits(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out int[] categories,
        out int[] sourceConstructs)
    {
        categories = Array.Empty<int>();
        sourceConstructs = Array.Empty<int>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var count = diagnostics.Count;
            var codes = new string[count];
            var messages = new string[count];
            var snippets = new string[count];
            categories = new int[count];
            sourceConstructs = new int[count];

            for (var i = 0; i < count; i++)
            {
                var diagnostic = diagnostics[i];
                codes[i] = diagnostic.Code ?? string.Empty;
                messages[i] = diagnostic.Message ?? string.Empty;
                snippets[i] = diagnostic.SourceSnippet ?? string.Empty;
            }

            var classified = bindings.DiagnosticClusterTraits(
                codes,
                messages,
                snippets,
                categories,
                sourceConstructs);

            if (classified == count)
                return true;

            categories = Array.Empty<int>();
            sourceConstructs = Array.Empty<int>();
            return false;
        }
        catch
        {
            categories = Array.Empty<int>();
            sourceConstructs = Array.Empty<int>();
            return false;
        }
    }

    internal static bool TrySummarizeDiagnosticSeverities(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out DiagnosticSummary summary)
    {
        summary = new DiagnosticSummary(0, 0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = diagnostics.Count;
        var scratch = t_diagnosticSummaryScratch ??= new DiagnosticSummaryScratch();
        scratch.EnsureCapacity(count);

        try
        {
            for (var i = 0; i < count; i++)
            {
                scratch.Severities[i] = diagnostics[i].Severity ?? string.Empty;
            }

            var summarized = bindings.DiagnosticSeveritySummary(scratch.Severities, count, scratch.Counts);
            if (summarized != count)
                return false;

            summary = new DiagnosticSummary(
                scratch.Counts[0],
                scratch.Counts[1],
                scratch.Counts[2]);
            return true;
        }
        catch
        {
            summary = new DiagnosticSummary(0, 0, 0);
            return false;
        }
        finally
        {
            Array.Clear(scratch.Severities, 0, count);
            scratch.Counts[0] = 0;
            scratch.Counts[1] = 0;
            scratch.Counts[2] = 0;
        }
    }

    internal static bool TryGroupDiagnosticClusters(
        IReadOnlyList<DiagnosticResult> diagnostics,
        int[] categoryIds,
        int[] sourceConstructIds,
        string[] messagePatterns,
        out DiagnosticClusterGrouping? grouping)
    {
        grouping = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = diagnostics.Count;
        if (categoryIds.Length < count || sourceConstructIds.Length < count || messagePatterns.Length < count)
            return false;

        var scratch = t_diagnosticClusterGroupingScratch ??= new DiagnosticClusterGroupingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < count; i++)
            {
                var diagnostic = diagnostics[i];
                var category = categoryIds[i];

                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code ?? string.Empty);
                scratch.SeverityIds[i] = scratch.GetSeverityId(diagnostic.Severity ?? string.Empty);
                scratch.CategoryIds[i] = category;
                scratch.SourceConstructIds[i] = sourceConstructIds[i];
                scratch.RecipeIds[i] = category;
                scratch.RiskIds[i] = DiagnosticClusterRiskId(category);
                scratch.MessagePatternIds[i] = scratch.GetMessagePatternId(messagePatterns[i] ?? string.Empty);
                scratch.Files[i] = diagnostic.File ?? string.Empty;
                scratch.Lines[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
            }

            var groupCount = bindings.DiagnosticClusterCompactGroups(
                scratch.CodeIds,
                scratch.SeverityIds,
                scratch.CategoryIds,
                scratch.SourceConstructIds,
                scratch.RecipeIds,
                scratch.RiskIds,
                scratch.MessagePatternIds,
                scratch.Files,
                scratch.Lines,
                scratch.Columns,
                scratch.SlotGroups,
                scratch.GroupKeyIndices,
                scratch.RootIndices,
                scratch.Counts);

            if (groupCount < 0 || groupCount > count)
                return false;

            var memberTotal = bindings.DiagnosticClusterCompactGroupMembers(
                scratch.CodeIds,
                scratch.SeverityIds,
                scratch.CategoryIds,
                scratch.SourceConstructIds,
                scratch.RecipeIds,
                scratch.RiskIds,
                scratch.MessagePatternIds,
                scratch.Files,
                scratch.Lines,
                scratch.Columns,
                scratch.RootIndices,
                scratch.Counts,
                groupCount,
                scratch.SlotGroups,
                scratch.GroupFirstMemberIndices,
                scratch.MemberNextIndices,
                scratch.MemberStarts,
                scratch.MemberIndices);

            if (memberTotal != count)
                return false;

            grouping = new DiagnosticClusterGrouping(
                groupCount,
                scratch.RootIndices,
                scratch.Counts,
                scratch.MemberStarts,
                scratch.MemberIndices);
            return true;
        }
        catch
        {
            grouping = null;
            return false;
        }
        finally
        {
            scratch.ClearFiles(count);
            scratch.ResetIds();
        }
    }

    internal static bool TryDeduplicateDiagnostics(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out int[] resultIndices,
        out int count)
    {
        resultIndices = Array.Empty<int>();
        count = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return true;

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
                scratch.Files[i] = diagnostic.File;
                scratch.AddFile(diagnostic.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            count = bindings.DiagnosticDeduplicateCompact(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            if (count < 0 || count > diagnosticCount)
            {
                count = 0;
                return false;
            }

            resultIndices = scratch.ResultIndices;
            return true;
        }
        catch
        {
            resultIndices = Array.Empty<int>();
            count = 0;
            return false;
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.ResetIds();
        }
    }

    internal static bool TryDeduplicateDiagnosticsPreservingOrder(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out int[] resultIndices,
        out int count)
    {
        resultIndices = Array.Empty<int>();
        count = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return true;

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.FileRanks[i] = scratch.GetFileId(diagnostic.File);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
            }

            count = bindings.DiagnosticDeduplicateStable(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            if (count < 0 || count > diagnosticCount)
            {
                count = 0;
                return false;
            }

            resultIndices = scratch.ResultIndices;
            return true;
        }
        catch
        {
            resultIndices = Array.Empty<int>();
            count = 0;
            return false;
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static bool TryDeduplicateReferences(
        IReadOnlyList<ReferenceResult> references,
        out int[] resultIndices,
        out int count)
    {
        resultIndices = Array.Empty<int>();
        count = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = references.Count;
        if (referenceCount == 0)
            return true;

        var scratch = t_referenceDeduplicationScratch ??= new ReferenceDeduplicationScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < referenceCount; i++)
            {
                var reference = references[i];
                scratch.LineNumbers[i] = reference.Line;
                scratch.Columns[i] = reference.Column;
                scratch.Files[i] = reference.File;
                scratch.AddFile(reference.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < referenceCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            count = bindings.ReferenceDeduplicateCompact(
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.SlotIndices,
                scratch.ResultIndices);

            if (count < 0 || count > referenceCount)
            {
                count = 0;
                return false;
            }

            resultIndices = scratch.ResultIndices;
            return true;
        }
        catch
        {
            resultIndices = Array.Empty<int>();
            count = 0;
            return false;
        }
        finally
        {
            scratch.ClearFiles(referenceCount);
            scratch.ResetFiles();
        }
    }

    internal static bool TryBuildInspectSummaryReferenceFiles(
        IReadOnlyList<ReferenceResult> references,
        out string[] referenceFiles)
    {
        referenceFiles = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = references.Count;
        if (referenceCount == 0)
            return true;

        var scratch = t_referenceFileSummaryScratch ??= new ReferenceFileSummaryScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < referenceCount; i++)
            {
                var file = NormalizeDogfoodPath(references[i].File);
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < referenceCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var resultCount = bindings.ReferenceFileSummaryRanks(
                scratch.FileRanks,
                scratch.UniqueFileCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (resultCount < 0 || resultCount > scratch.UniqueFileCount || resultCount > scratch.ResultRanks.Length)
                return false;

            referenceFiles = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueFileCount)
                {
                    referenceFiles = Array.Empty<string>();
                    return false;
                }

                referenceFiles[i] = scratch.UniqueFiles[rank - 1];
            }

            return true;
        }
        catch
        {
            referenceFiles = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearFiles(referenceCount);
            scratch.ResetFiles();
        }
    }

    internal static bool TryBuildDiagnosticClusterFiles(
        IReadOnlyList<DiagnosticResult> diagnostics,
        out string[] files)
    {
        files = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return true;

        var scratch = t_diagnosticClusterFileSummaryScratch ??=
            new ReferenceFileSummaryScratch(StringComparer.OrdinalIgnoreCase, StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var file = diagnostics[i].File;
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var resultCount = bindings.ReferenceFileSummaryRanks(
                scratch.FileRanks,
                scratch.UniqueFileCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (resultCount < 0 || resultCount > scratch.UniqueFileCount || resultCount > scratch.ResultRanks.Length)
                return false;

            files = new string[resultCount];
            for (var i = 0; i < resultCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueFileCount)
                {
                    files = Array.Empty<string>();
                    return false;
                }

                files[i] = scratch.UniqueFiles[rank - 1];
            }

            return true;
        }
        catch
        {
            files = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.ResetFiles();
        }
    }

    internal static bool TryResolveBindingDeclaration(
        BindingMap bindingMap,
        string filePath,
        int line,
        int[] candidateColumns,
        out SymbolDeclaration? declaration)
    {
        declaration = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (candidateColumns.Length == 0)
            return true;

        try
        {
            var cache = s_bindingLookupCaches.GetValue(bindingMap, static map => new BindingLookupCache(map));
            return cache.TryResolve(bindings, filePath, line, candidateColumns, out declaration);
        }
        catch
        {
            declaration = null;
            return false;
        }
    }

    internal static bool TryFindNearestBindingDeclarationByName(
        BindingMap bindingMap,
        string filePath,
        string name,
        int line,
        out SymbolDeclaration? declaration)
    {
        declaration = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (string.IsNullOrEmpty(name))
            return true;

        try
        {
            var cache = s_bindingLookupCaches.GetValue(bindingMap, static map => new BindingLookupCache(map));
            return cache.TryFindNearestDeclaration(bindings, filePath, name, line, out declaration);
        }
        catch
        {
            declaration = null;
            return false;
        }
    }

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

    internal static bool TryClassifyCompletionReceiver(
        string beforeCursor,
        out bool isMemberAccess,
        out string? receiver)
    {
        isMemberAccess = false;
        receiver = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var scratch = t_completionReceiverScratch ??= new CompletionReceiverScratch();
            scratch.Prefixes[0] = beforeCursor;
            scratch.Contexts[0] = 0;
            scratch.Receivers[0] = string.Empty;

            var classified = bindings.CompletionReceivers(
                scratch.Prefixes,
                scratch.Contexts,
                scratch.Receivers);

            if (classified != 1)
            {
                scratch.Prefixes[0] = string.Empty;
                scratch.Receivers[0] = string.Empty;
                return false;
            }

            isMemberAccess = scratch.Contexts[0] != 0;
            receiver = scratch.Receivers[0].Length > 0 ? scratch.Receivers[0] : null;
            scratch.Prefixes[0] = string.Empty;
            scratch.Receivers[0] = string.Empty;
            return true;
        }
        catch
        {
            if (t_completionReceiverScratch is { } scratch)
            {
                scratch.Prefixes[0] = string.Empty;
                scratch.Contexts[0] = 0;
                scratch.Receivers[0] = string.Empty;
            }

            isMemberAccess = false;
            receiver = null;
            return false;
        }
    }

    internal static bool TryAddGroupedCompletionItemsByKind(
        IReadOnlyList<CompletionItem> items,
        Dictionary<string, List<CompletionItem>> completions)
    {
        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = items.Count;
        if (count == 0)
            return true;

        var scratch = t_completionItemGroupingScratch ??= new CompletionItemGroupingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetKindIds();
            for (var i = 0; i < count; i++)
            {
                scratch.KindIds[i] = scratch.GetKindId(items[i].Kind);
            }

            var groupCount = bindings.CompletionItemKindGroups(
                scratch.KindIds,
                scratch.KindCounts,
                scratch.KindOffsets,
                scratch.ResultKindIds,
                scratch.ResultStarts,
                scratch.ResultCounts,
                scratch.ResultIndices);

            if (groupCount < 0 || groupCount > count)
                return false;

            var total = 0;
            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var start = scratch.ResultStarts[groupIndex];
                var itemCount = scratch.ResultCounts[groupIndex];
                if (start < 0 || itemCount < 0 || start + itemCount > count)
                    return false;

                total += itemCount;
            }

            if (total != count)
                return false;

            for (var resultIndex = 0; resultIndex < count; resultIndex++)
            {
                var sourceIndex = scratch.ResultIndices[resultIndex];
                if (sourceIndex < 0 || sourceIndex >= count)
                    return false;
            }

            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var kindId = scratch.ResultKindIds[groupIndex];
                var kind = scratch.GetKindName(kindId);
                var start = scratch.ResultStarts[groupIndex];
                var itemCount = scratch.ResultCounts[groupIndex];
                var groupItems = new List<CompletionItem>(itemCount);

                for (var itemIndex = 0; itemIndex < itemCount; itemIndex++)
                {
                    var sourceIndex = scratch.ResultIndices[start + itemIndex];
                    groupItems.Add(items[sourceIndex]);
                }

                completions[CompletionEngine.PluralizeCompletionKind(kind)] = groupItems;
            }

            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            scratch.ResetKindIds();
        }
    }

    internal static bool TryGroupReflectionMethodsByName(
        MethodInfo[] methods,
        out CompletionMethodGrouping? grouping)
    {
        grouping = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = methods.Length;
        if (count == 0)
        {
            grouping = new CompletionMethodGrouping(0, Array.Empty<int>(), Array.Empty<int>(), Array.Empty<int>());
            return true;
        }

        var scratch = t_completionMethodGroupingScratch ??= new CompletionMethodGroupingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetNameIds();
            var includedCount = 0;
            for (var i = 0; i < count; i++)
            {
                var method = methods[i];
                if (IsIncludedCompletionMethod(method))
                {
                    scratch.IncludeFlags[i] = 1;
                    scratch.NameIds[i] = scratch.GetNameId(method.Name);
                    includedCount++;
                }
                else
                {
                    scratch.IncludeFlags[i] = 0;
                    scratch.NameIds[i] = 0;
                }
            }

            var groupCount = bindings.CompletionMethodOverloadGroups(
                scratch.NameIds,
                scratch.IncludeFlags,
                scratch.NameCounts,
                scratch.ResultNameIds,
                scratch.ResultFirstIndices,
                scratch.ResultCounts);

            if (groupCount < 0 || groupCount > count)
                return false;

            var total = 0;
            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var firstIndex = scratch.ResultFirstIndices[groupIndex];
                var methodCount = scratch.ResultCounts[groupIndex];
                var nameId = scratch.ResultNameIds[groupIndex];

                if (firstIndex < 0 || firstIndex >= count
                    || methodCount <= 0
                    || nameId <= 0
                    || nameId >= scratch.NameCounts.Length
                    || scratch.IncludeFlags[firstIndex] == 0)
                {
                    return false;
                }

                total += methodCount;
            }

            if (total != includedCount)
                return false;

            grouping = new CompletionMethodGrouping(
                groupCount,
                scratch.ResultNameIds,
                scratch.ResultFirstIndices,
                scratch.ResultCounts);
            return true;
        }
        catch
        {
            grouping = null;
            return false;
        }
        finally
        {
            scratch.ResetNameIds();
        }
    }

    private static bool IsIncludedCompletionMethod(MethodInfo method) =>
        !method.IsSpecialName && method.DeclaringType?.FullName != "System.Object";

    private static FileCache GetFileCache(ProjectSnapshot snapshot, string filePath, string source)
    {
        var snapshotCache = s_snapshotCaches.GetValue(snapshot, static _ => new SnapshotCache());
        return snapshotCache.GetFileCache(Path.GetFullPath(filePath), source);
    }

    private static string NormalizeDogfoodPath(string path) => path.Replace('\\', '/');

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<BuildCodeIntelligenceLineRangesInto>(programType, "BuildCodeIntelligenceLineRangesInto"),
                CreateDelegate<BuildCodeIntelligenceMemberReceiverCacheInto>(programType, "BuildCodeIntelligenceMemberReceiverCacheInto"),
                CreateDelegate<BuildCodeIntelligenceVariableDeclarationNameCacheInto>(programType, "BuildCodeIntelligenceVariableDeclarationNameCacheInto"),
                CreateDelegate<CodeIntelligenceDeclarationNameMatchesFromLinesInto>(programType, "CodeIntelligenceDeclarationNameMatchesFromLinesInto"),
                CreateDelegate<CodeIntelligenceIdentifierNameColumnsFromLinesInto>(programType, "CodeIntelligenceIdentifierNameColumnsFromLinesInto"),
                CreateDelegate<CodeIntelligenceIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceEditorIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceEditorIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceCompletionPrefixesFromLinesInto>(programType, "CodeIntelligenceCompletionPrefixesFromLinesInto"),
                CreateDelegate<CodeIntelligenceDocCommentLinesFromLinesInto>(programType, "CodeIntelligenceDocCommentLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceMemberReceiversFromCacheInto>(programType, "CodeIntelligenceMemberReceiversFromCacheInto"),
                CreateDelegate<CodeIntelligenceSourceContextsFromLinesInto>(programType, "CodeIntelligenceSourceContextsFromLinesInto"),
                CreateDelegate<CodeIntelligenceSourceLinesFromLinesInto>(programType, "CodeIntelligenceSourceLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceVariableDeclarationNamesFromCacheInto>(programType, "CodeIntelligenceVariableDeclarationNamesFromCacheInto"),
                CreateDelegate<CodeIntelligenceCompletionReceiversInto>(programType, "CodeIntelligenceCompletionReceiversInto"),
                CreateDelegate<CompletionItemKindGroupsInto>(programType, "CompletionItemKindGroupsInto"),
                CreateDelegate<CompletionMethodOverloadGroupsInto>(programType, "CompletionMethodOverloadGroupsInto"),
                CreateDelegate<DiagnosticSeveritySummaryInto>(programType, "DiagnosticSeveritySummaryInto"),
                CreateDelegate<DiagnosticClusterTraitsInto>(programType, "DiagnosticClusterTraitsInto"),
                CreateDelegate<DiagnosticClusterCompactGroupsInto>(programType, "DiagnosticClusterCompactGroupsInto"),
                CreateDelegate<DiagnosticClusterCompactGroupMembersInto>(programType, "DiagnosticClusterCompactGroupMembersInto"),
                CreateDelegate<DiagnosticDeduplicateCompactInto>(programType, "DiagnosticDeduplicateCompactInto"),
                CreateDelegate<DiagnosticDeduplicateCompactInto>(programType, "DiagnosticDeduplicateStableInto"),
                CreateDelegate<TextEditOrderIndicesInto>(programType, "TextEditOrderIndicesInto"),
                CreateDelegate<ReferenceDeduplicateCompactInto>(programType, "ReferenceDeduplicateCompactInto"),
                CreateDelegate<ReferenceFileSummaryRanksInto>(programType, "ReferenceFileSummaryRanksInto"),
                CreateDelegate<BindingLookupCandidateColumnsInto>(programType, "BindingLookupCandidateColumnsInto"),
                CreateDelegate<BindingLookupBuildSlotsInto>(programType, "BindingLookupBuildSlotsInto"),
                CreateDelegate<BindingLookupQueryDeclarationIndicesInto>(programType, "BindingLookupQueryDeclarationIndicesInto"),
                CreateDelegate<BindingLookupFindNearestDeclarationIndicesInto>(programType, "BindingLookupFindNearestDeclarationIndicesInto"),
                CreateDelegate<SemanticScopeBuildSortedIndexInto>(programType, "SemanticScopeBuildSortedIndexInto"),
                CreateDelegate<SemanticScopeBuildDepthsInto>(programType, "SemanticScopeBuildDepthsInto"),
                CreateDelegate<SemanticScopeVisibleSymbolIndicesInto>(programType, "SemanticScopeVisibleSymbolIndicesInto"),
                CreateDelegate<SemanticScopeLookupSymbolIndicesInto>(programType, "SemanticScopeLookupSymbolIndicesInto"));
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

    private delegate int BuildCodeIntelligenceLineRangesInto(string source, int[] starts, int[] lengths);

    private delegate int BuildCodeIntelligenceMemberReceiverCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] receiverStartsBySeparator,
        int[] receiverLengthsBySeparator);

    private delegate int BuildCodeIntelligenceVariableDeclarationNameCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] nameStartsByLine,
        int[] nameLengthsByLine);

    private delegate int CodeIntelligenceIdentifierSpansFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceEditorIdentifierSpansFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceDeclarationNameMatchesFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] declarationColumns,
        string[] declarationNames,
        int[] selectedStartColumns,
        int[] selectedEndColumns,
        int[] resultMatches);

    private delegate int CodeIntelligenceIdentifierNameColumnsFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        string[] declarationNames,
        int[] fallbackColumns,
        int[] resultColumns);

    private delegate int CodeIntelligenceCompletionPrefixesFromLinesInto(
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] queryColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceDocCommentLinesFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int definitionLine,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceMemberReceiversFromCacheInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] receiverStartsBySeparator,
        int[] receiverLengthsBySeparator,
        int[] queryLines,
        int[] memberStartColumns,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceSourceContextsFromLinesInto(
        string source,
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceSourceLinesFromLinesInto(
        int[] lineStarts,
        int[] lineLengths,
        int lineCount,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceVariableDeclarationNamesFromCacheInto(
        int lineCount,
        int[] nameStartsByLine,
        int[] nameLengthsByLine,
        int[] queryLines,
        int[] resultStarts,
        int[] resultLengths);

    private delegate int CodeIntelligenceCompletionReceiversInto(
        string[] prefixes,
        int[] resultContexts,
        string[] resultReceivers);

    private delegate int CompletionItemKindGroupsInto(
        int[] kindIds,
        int[] kindCounts,
        int[] kindOffsets,
        int[] resultKindIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices);

    private delegate int CompletionMethodOverloadGroupsInto(
        int[] nameIds,
        int[] includeFlags,
        int[] nameCounts,
        int[] resultNameIds,
        int[] resultFirstIndices,
        int[] resultCounts);

    private delegate int DiagnosticClusterTraitsInto(
        string[] codes,
        string[] messages,
        string[] snippets,
        int[] resultCategories,
        int[] resultSourceConstructs);

    private delegate int DiagnosticSeveritySummaryInto(
        string[] severities,
        int count,
        int[] resultCounts);

    private delegate int DiagnosticClusterCompactGroupsInto(
        int[] codeIds,
        int[] severityIds,
        int[] categoryIds,
        int[] sourceConstructIds,
        int[] recipeIds,
        int[] riskIds,
        int[] messagePatternIds,
        string[] files,
        int[] lines,
        int[] columns,
        int[] slotGroups,
        int[] groupKeyIndices,
        int[] resultRootIndices,
        int[] resultCounts);

    private delegate int DiagnosticClusterCompactGroupMembersInto(
        int[] codeIds,
        int[] severityIds,
        int[] categoryIds,
        int[] sourceConstructIds,
        int[] recipeIds,
        int[] riskIds,
        int[] messagePatternIds,
        string[] files,
        int[] lines,
        int[] columns,
        int[] groupRootIndices,
        int[] groupCounts,
        int groupCount,
        int[] slotGroups,
        int[] groupFirstMemberIndices,
        int[] memberNextIndices,
        int[] resultStarts,
        int[] resultMemberIndices);

    private delegate int DiagnosticDeduplicateCompactInto(
        int[] codeIds,
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] messageIds,
        int[] slotIndices,
        int[] resultIndices);

    private delegate int ReferenceDeduplicateCompactInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices,
        int[] resultIndices);

    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);

    private delegate int TextEditOrderIndicesInto(
        int[] startPositionRanks,
        int[] endPositionRanks,
        int startPositionRankCount,
        int endPositionRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);

    private delegate int BindingLookupCandidateColumnsInto(
        int[] queryColumns,
        int[] spanStartColumns,
        int[] spanEndColumns,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultColumns);

    private delegate int BindingLookupBuildSlotsInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices);

    private delegate int BindingLookupQueryDeclarationIndicesInto(
        int[] declarationFileRanks,
        int[] declarationLineNumbers,
        int[] declarationColumns,
        int[] declarationSlotIndices,
        int[] bindingFileRanks,
        int[] bindingLineNumbers,
        int[] bindingColumns,
        int[] bindingDeclarationIndices,
        int[] bindingSlotIndices,
        int[] queryFileRanks,
        int[] queryLineNumbers,
        int[] queryColumns,
        int[] resultDeclarationIndices);

    private delegate int BindingLookupFindNearestDeclarationIndicesInto(
        int[] sortedNameIds,
        int[] sortedFileRanks,
        int[] sortedLineNumbers,
        int[] sortedColumns,
        int[] sortedDeclarationIndices,
        int[] queryNameIds,
        int[] queryFileRanks,
        int[] queryLineNumbers,
        int[] resultDeclarationIndices);

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
        BuildCodeIntelligenceLineRangesInto BuildLineRanges,
        BuildCodeIntelligenceMemberReceiverCacheInto BuildMemberReceiverCache,
        BuildCodeIntelligenceVariableDeclarationNameCacheInto BuildVariableDeclarationNameCache,
        CodeIntelligenceDeclarationNameMatchesFromLinesInto DeclarationNameMatchesFromLines,
        CodeIntelligenceIdentifierNameColumnsFromLinesInto IdentifierNameColumnsFromLines,
        CodeIntelligenceIdentifierSpansFromLinesInto IdentifierSpansFromLines,
        CodeIntelligenceEditorIdentifierSpansFromLinesInto EditorIdentifierSpansFromLines,
        CodeIntelligenceCompletionPrefixesFromLinesInto CompletionPrefixesFromLines,
        CodeIntelligenceDocCommentLinesFromLinesInto DocCommentLinesFromLines,
        CodeIntelligenceMemberReceiversFromCacheInto MemberReceiversFromCache,
        CodeIntelligenceSourceContextsFromLinesInto SourceContextsFromLines,
        CodeIntelligenceSourceLinesFromLinesInto SourceLinesFromLines,
        CodeIntelligenceVariableDeclarationNamesFromCacheInto VariableDeclarationNamesFromCache,
        CodeIntelligenceCompletionReceiversInto CompletionReceivers,
        CompletionItemKindGroupsInto CompletionItemKindGroups,
        CompletionMethodOverloadGroupsInto CompletionMethodOverloadGroups,
        DiagnosticSeveritySummaryInto DiagnosticSeveritySummary,
        DiagnosticClusterTraitsInto DiagnosticClusterTraits,
        DiagnosticClusterCompactGroupsInto DiagnosticClusterCompactGroups,
        DiagnosticClusterCompactGroupMembersInto DiagnosticClusterCompactGroupMembers,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateCompact,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateStable,
        TextEditOrderIndicesInto TextEditOrderIndices,
        ReferenceDeduplicateCompactInto ReferenceDeduplicateCompact,
        ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks,
        BindingLookupCandidateColumnsInto BindingLookupCandidateColumns,
        BindingLookupBuildSlotsInto BindingLookupBuildSlots,
        BindingLookupQueryDeclarationIndicesInto BindingLookupQueryDeclarationIndices,
        BindingLookupFindNearestDeclarationIndicesInto BindingLookupFindNearestDeclarationIndices,
        SemanticScopeBuildSortedIndexInto SemanticScopeBuildSortedIndex,
        SemanticScopeBuildDepthsInto SemanticScopeBuildDepths,
        SemanticScopeVisibleSymbolIndicesInto SemanticScopeVisibleSymbolIndices,
        SemanticScopeLookupSymbolIndicesInto SemanticScopeLookupSymbolIndices);

    internal sealed class CompletionMethodGrouping
    {
        public CompletionMethodGrouping(
            int groupCount,
            int[] nameIds,
            int[] firstIndices,
            int[] counts)
        {
            GroupCount = groupCount;
            NameIds = nameIds;
            FirstIndices = firstIndices;
            Counts = counts;
        }

        public int GroupCount { get; }
        public int[] NameIds { get; }
        public int[] FirstIndices { get; }
        public int[] Counts { get; }
    }

    internal sealed class DiagnosticClusterGrouping
    {
        public DiagnosticClusterGrouping(
            int groupCount,
            int[] rootIndices,
            int[] counts,
            int[] memberStarts,
            int[] memberIndices)
        {
            GroupCount = groupCount;
            RootIndices = rootIndices;
            Counts = counts;
            MemberStarts = memberStarts;
            MemberIndices = memberIndices;
        }

        public int GroupCount { get; }
        public int[] RootIndices { get; }
        public int[] Counts { get; }
        public int[] MemberStarts { get; }
        public int[] MemberIndices { get; }
    }

    private sealed class BindingCandidateColumnScratch
    {
        public int[] QueryColumns = new int[1];
        public int[] ResultColumns = Array.Empty<int>();
        public int[] ResultCounts = new int[1];
        public int[] ResultStarts = new int[1];
        public int[] SpanEndColumns = new int[1];
        public int[] SpanStartColumns = new int[1];

        public void EnsureCapacity(int resultCapacity)
        {
            if (ResultColumns.Length < resultCapacity)
            {
                ResultColumns = new int[resultCapacity];
            }
        }
    }

    private sealed class CompletionReceiverScratch
    {
        public readonly int[] Contexts = new int[1];
        public readonly string[] Prefixes = new string[1];
        public readonly string[] Receivers = new string[1];

        public CompletionReceiverScratch()
        {
            Prefixes[0] = string.Empty;
            Receivers[0] = string.Empty;
        }
    }

    private sealed class CompletionItemGroupingScratch
    {
        private readonly Dictionary<string, int> _kindIds = new(StringComparer.Ordinal);

        public int[] KindCounts = Array.Empty<int>();
        public int[] KindIds = Array.Empty<int>();
        public string[] KindNames = Array.Empty<string>();
        public int[] KindOffsets = Array.Empty<int>();
        public int[] ResultCounts = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] ResultKindIds = Array.Empty<int>();
        public int[] ResultStarts = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                ResultKindIds = new int[count];
                ResultStarts = new int[count];
                ResultCounts = new int[count];
                ResultIndices = new int[count];
            }

            var bucketCapacity = count + 1;
            if (KindCounts.Length < bucketCapacity)
            {
                KindCounts = new int[bucketCapacity];
                KindOffsets = new int[bucketCapacity];
                KindNames = new string[bucketCapacity];
            }
        }

        public int GetKindId(string kind)
        {
            if (_kindIds.TryGetValue(kind, out var id))
                return id;

            id = _kindIds.Count + 1;
            _kindIds.Add(kind, id);
            KindNames[id] = kind;
            return id;
        }

        public string GetKindName(int id) =>
            id > 0 && id < KindNames.Length
                ? KindNames[id] ?? string.Empty
                : string.Empty;

        public void ResetKindIds()
        {
            if (_kindIds.Count > 0)
            {
                Array.Clear(KindNames, 1, _kindIds.Count);
                _kindIds.Clear();
            }
        }
    }

    private sealed class CompletionMethodGroupingScratch
    {
        private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);

        public int[] IncludeFlags = Array.Empty<int>();
        public int[] NameCounts = Array.Empty<int>();
        public int[] NameIds = Array.Empty<int>();
        public int[] ResultCounts = Array.Empty<int>();
        public int[] ResultFirstIndices = Array.Empty<int>();
        public int[] ResultNameIds = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (NameIds.Length != count)
            {
                NameIds = new int[count];
                IncludeFlags = new int[count];
                ResultNameIds = new int[count];
                ResultFirstIndices = new int[count];
                ResultCounts = new int[count];
            }

            var bucketCapacity = count + 1;
            if (NameCounts.Length < bucketCapacity)
            {
                NameCounts = new int[bucketCapacity];
            }
        }

        public int GetNameId(string name)
        {
            if (_nameIds.TryGetValue(name, out var id))
                return id;

            id = _nameIds.Count + 1;
            _nameIds.Add(name, id);
            return id;
        }

        public void ResetNameIds()
        {
            if (_nameIds.Count > 0)
            {
                _nameIds.Clear();
            }
        }
    }

    private sealed class DiagnosticSummaryScratch
    {
        public readonly int[] Counts = new int[3];
        public string[] Severities = Array.Empty<string>();

        public void EnsureCapacity(int count)
        {
            if (Severities.Length < count)
            {
                Severities = new string[count];
            }
        }
    }

    private sealed class DiagnosticClusterGroupingScratch
    {
        private readonly Dictionary<string, int> _codeIds = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _messagePatternIds = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _severityIds = new(StringComparer.Ordinal);

        public int[] CategoryIds = Array.Empty<int>();
        public int[] CodeIds = Array.Empty<int>();
        public int[] Columns = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] Counts = Array.Empty<int>();
        public int[] GroupFirstMemberIndices = Array.Empty<int>();
        public int[] GroupKeyIndices = Array.Empty<int>();
        public int[] Lines = Array.Empty<int>();
        public int[] MemberIndices = Array.Empty<int>();
        public int[] MemberNextIndices = Array.Empty<int>();
        public int[] MemberStarts = Array.Empty<int>();
        public int[] MessagePatternIds = Array.Empty<int>();
        public int[] RecipeIds = Array.Empty<int>();
        public int[] RiskIds = Array.Empty<int>();
        public int[] RootIndices = Array.Empty<int>();
        public int[] SeverityIds = Array.Empty<int>();
        public int[] SlotGroups = Array.Empty<int>();
        public int[] SourceConstructIds = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (CodeIds.Length != count)
            {
                CodeIds = new int[count];
                SeverityIds = new int[count];
                CategoryIds = new int[count];
                SourceConstructIds = new int[count];
                RecipeIds = new int[count];
                RiskIds = new int[count];
                MessagePatternIds = new int[count];
                Files = new string[count];
                Lines = new int[count];
                Columns = new int[count];
                GroupKeyIndices = new int[count];
                GroupFirstMemberIndices = new int[count];
                MemberIndices = new int[count];
                MemberNextIndices = new int[count];
                MemberStarts = new int[count];
                RootIndices = new int[count];
                Counts = new int[count];
            }

            var slotCapacity = count * 2 + 1;
            if (SlotGroups.Length != slotCapacity)
            {
                SlotGroups = new int[slotCapacity];
            }
        }

        public int GetCodeId(string text) => GetId(_codeIds, text);

        public int GetSeverityId(string text) => GetId(_severityIds, text);

        public int GetMessagePatternId(string text) => GetId(_messagePatternIds, text);

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetIds()
        {
            _codeIds.Clear();
            _severityIds.Clear();
            _messagePatternIds.Clear();
        }

        private static int GetId(Dictionary<string, int> ids, string text)
        {
            if (ids.TryGetValue(text, out var id))
                return id;

            id = ids.Count + 1;
            ids.Add(text, id);
            return id;
        }
    }

    private sealed class DiagnosticDeduplicationScratch
    {
        private readonly Dictionary<string, int> _codeIds = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _messageIds = new(StringComparer.Ordinal);

        public int[] CodeIds = Array.Empty<int>();
        public int[] Columns = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] LineNumbers = Array.Empty<int>();
        public int[] MessageIds = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SlotIndices = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (CodeIds.Length != count)
            {
                CodeIds = new int[count];
                FileRanks = new int[count];
                LineNumbers = new int[count];
                Columns = new int[count];
                MessageIds = new int[count];
                Files = new string[count];
                ResultIndices = new int[count];
                UniqueFiles = new string[count];
            }

            var slotCapacity = count * 2 + 1;
            if (SlotIndices.Length != slotCapacity)
            {
                SlotIndices = new int[slotCapacity];
            }
        }

        public int GetCodeId(string text) => GetId(_codeIds, text);

        public int GetFileId(string text) => GetId(_fileRanks, text);

        public int GetMessageId(string text) => GetId(_messageIds, text);

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, Comparer<string>.Default);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks[text];

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetIds()
        {
            _codeIds.Clear();
            _fileRanks.Clear();
            _messageIds.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }

        private static int GetId(Dictionary<string, int> ids, string text)
        {
            if (ids.TryGetValue(text, out var id))
                return id;

            id = ids.Count + 1;
            ids.Add(text, id);
            return id;
        }
    }

    private sealed class ReferenceDeduplicationScratch
    {
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);

        public int[] Columns = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] LineNumbers = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SlotIndices = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (FileRanks.Length != count)
            {
                FileRanks = new int[count];
                LineNumbers = new int[count];
                Columns = new int[count];
                Files = new string[count];
                ResultIndices = new int[count];
                UniqueFiles = new string[count];
            }

            var slotCapacity = count * 2 + 1;
            if (SlotIndices.Length != slotCapacity)
            {
                SlotIndices = new int[slotCapacity];
            }
        }

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, Comparer<string>.Default);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks[text];

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetFiles()
        {
            _fileRanks.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }
    }

    private sealed class ReferenceFileSummaryScratch
    {
        private readonly Dictionary<string, int> _fileRanks;
        private readonly IComparer<string> _sortComparer;

        public ReferenceFileSummaryScratch()
            : this(StringComparer.Ordinal, StringComparer.Ordinal)
        {
        }

        public ReferenceFileSummaryScratch(IEqualityComparer<string> equalityComparer, IComparer<string> sortComparer)
        {
            _fileRanks = new Dictionary<string, int>(equalityComparer);
            _sortComparer = sortComparer;
        }

        public int[] CountsByRank = Array.Empty<int>();
        public int[] FileRanks = Array.Empty<int>();
        public string[] Files = Array.Empty<string>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueFiles = Array.Empty<string>();
        public int UniqueFileCount;

        public void EnsureCapacity(int count)
        {
            if (FileRanks.Length != count)
            {
                FileRanks = new int[count];
                Files = new string[count];
                ResultRanks = new int[count];
                UniqueFiles = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        public void AddFile(string text)
        {
            if (_fileRanks.ContainsKey(text))
                return;

            _fileRanks.Add(text, 0);
            UniqueFiles[UniqueFileCount] = text;
            UniqueFileCount++;
        }

        public void BuildFileRanks()
        {
            Array.Sort(UniqueFiles, 0, UniqueFileCount, _sortComparer);
            for (var i = 0; i < UniqueFileCount; i++)
            {
                _fileRanks[UniqueFiles[i]] = i + 1;
            }
        }

        public int GetFileRank(string text) => _fileRanks[text];

        public void ClearFiles(int count) => Array.Clear(Files, 0, count);

        public void ResetFiles()
        {
            _fileRanks.Clear();
            if (UniqueFileCount > 0)
            {
                Array.Clear(UniqueFiles, 0, UniqueFileCount);
                UniqueFileCount = 0;
            }
        }
    }

    private enum TextEditOrderingPosition
    {
        Start,
        End
    }

    private sealed class TextEditOrderingScratch
    {
        private readonly Dictionary<(int Line, int Column), int> _rankMap = new();

        public int[] BucketCounts = Array.Empty<int>();
        public int[] BucketOffsets = Array.Empty<int>();
        public int[] EndPositionRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] StartPositionRanks = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public (int Line, int Column)[] UniquePositions = Array.Empty<(int Line, int Column)>();

        public void EnsureCapacity(int count)
        {
            if (StartPositionRanks.Length != count)
            {
                StartPositionRanks = new int[count];
                EndPositionRanks = new int[count];
                TempIndices = new int[count];
                ResultIndices = new int[count];
                UniquePositions = new (int Line, int Column)[count];
            }

            var bucketCapacity = count + 1;
            if (BucketCounts.Length != bucketCapacity)
            {
                BucketCounts = new int[bucketCapacity];
                BucketOffsets = new int[bucketCapacity];
            }
        }

        public int BuildRanks(
            TextEdit[] edits,
            int count,
            TextEditOrderingPosition position,
            int[] ranks)
        {
            _rankMap.Clear();
            var uniqueCount = 0;
            for (var i = 0; i < count; i++)
            {
                var value = GetPosition(edits[i], position);
                if (_rankMap.ContainsKey(value))
                    continue;

                _rankMap.Add(value, 0);
                UniquePositions[uniqueCount] = value;
                uniqueCount++;
            }

            Array.Sort(UniquePositions, 0, uniqueCount);
            for (var i = 0; i < uniqueCount; i++)
            {
                _rankMap[UniquePositions[i]] = i + 1;
            }

            for (var i = 0; i < count; i++)
            {
                ranks[i] = _rankMap[GetPosition(edits[i], position)];
            }

            return uniqueCount;
        }

        public void Reset() => _rankMap.Clear();

        private static (int Line, int Column) GetPosition(TextEdit edit, TextEditOrderingPosition position) =>
            position switch
            {
                TextEditOrderingPosition.Start => (edit.StartLine, edit.StartColumn),
                TextEditOrderingPosition.End => (edit.EndLine, edit.EndColumn),
                _ => (0, 0)
            };
    }

    private sealed class BindingLookupCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<(string? File, int Line, int Column), int> _declarationIndices = new();
        private readonly Dictionary<string, int> _fileRanks = new(StringComparer.Ordinal);
        private readonly BindingMap _map;
        private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);

        private int[] _bindingColumns = Array.Empty<int>();
        private int[] _bindingDeclarationIndices = Array.Empty<int>();
        private int[] _bindingFileRanks = Array.Empty<int>();
        private int[] _bindingLineNumbers = Array.Empty<int>();
        private int[] _bindingSlotIndices = Array.Empty<int>();
        private int[] _declarationColumns = Array.Empty<int>();
        private int[] _declarationFileRanks = Array.Empty<int>();
        private int[] _declarationLineNumbers = Array.Empty<int>();
        private int[] _declarationNameIds = Array.Empty<int>();
        private int[] _declarationSlotIndices = Array.Empty<int>();
        private SymbolDeclaration[] _declarations = Array.Empty<SymbolDeclaration>();
        private int[] _queryColumns = Array.Empty<int>();
        private int[] _queryFileRanks = Array.Empty<int>();
        private int[] _queryLineNumbers = Array.Empty<int>();
        private int[] _queryNameIds = Array.Empty<int>();
        private int[] _resultDeclarationIndices = Array.Empty<int>();
        private int[] _sortedDeclarationColumns = Array.Empty<int>();
        private int[] _sortedDeclarationFileRanks = Array.Empty<int>();
        private int[] _sortedDeclarationIndices = Array.Empty<int>();
        private int[] _sortedDeclarationLineNumbers = Array.Empty<int>();
        private int[] _sortedDeclarationNameIds = Array.Empty<int>();
        private int _version = -1;

        public BindingLookupCache(BindingMap map)
        {
            _map = map;
        }

        public bool TryResolve(
            Bindings bindings,
            string filePath,
            int line,
            int[] candidateColumns,
            out SymbolDeclaration? declaration)
        {
            declaration = null;
            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_declarations.Length == 0 || candidateColumns.Length == 0)
                    return true;

                var fileRank = GetExistingFileRank(filePath);
                if (fileRank < 0)
                    return true;

                EnsureQueryCapacity(candidateColumns.Length);
                for (var i = 0; i < candidateColumns.Length; i++)
                {
                    _queryFileRanks[i] = fileRank;
                    _queryLineNumbers[i] = line;
                    _queryColumns[i] = candidateColumns[i];
                    _resultDeclarationIndices[i] = -1;
                }

                bindings.BindingLookupQueryDeclarationIndices(
                    _declarationFileRanks,
                    _declarationLineNumbers,
                    _declarationColumns,
                    _declarationSlotIndices,
                    _bindingFileRanks,
                    _bindingLineNumbers,
                    _bindingColumns,
                    _bindingDeclarationIndices,
                    _bindingSlotIndices,
                    _queryFileRanks,
                    _queryLineNumbers,
                    _queryColumns,
                    _resultDeclarationIndices);

                for (var i = 0; i < candidateColumns.Length; i++)
                {
                    var declarationIndex = _resultDeclarationIndices[i];
                    if (declarationIndex >= 0 && declarationIndex < _declarations.Length)
                    {
                        declaration = _declarations[declarationIndex];
                        return true;
                    }
                }

                return true;
            }
        }

        public bool TryFindNearestDeclaration(
            Bindings bindings,
            string filePath,
            string name,
            int line,
            out SymbolDeclaration? declaration)
        {
            declaration = null;
            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_declarations.Length == 0)
                    return true;

                var fileRank = GetExistingFileRank(filePath);
                if (fileRank < 0)
                    return true;

                var nameId = GetExistingNameId(name);
                if (nameId < 0)
                    return true;

                EnsureQueryCapacity(1);
                _queryNameIds[0] = nameId;
                _queryFileRanks[0] = fileRank;
                _queryLineNumbers[0] = line;
                _resultDeclarationIndices[0] = -1;

                bindings.BindingLookupFindNearestDeclarationIndices(
                    _sortedDeclarationNameIds,
                    _sortedDeclarationFileRanks,
                    _sortedDeclarationLineNumbers,
                    _sortedDeclarationColumns,
                    _sortedDeclarationIndices,
                    _queryNameIds,
                    _queryFileRanks,
                    _queryLineNumbers,
                    _resultDeclarationIndices);

                var declarationIndex = _resultDeclarationIndices[0];
                if (declarationIndex >= 0 && declarationIndex < _declarations.Length)
                {
                    declaration = _declarations[declarationIndex];
                }

                return true;
            }
        }

        private void EnsureBuilt(Bindings bindings)
        {
            if (_version == _map.Version)
                return;

            _declarationIndices.Clear();
            _fileRanks.Clear();
            _nameIds.Clear();

            var declarationCount = _map.DeclarationEntries.Count;
            _declarations = new SymbolDeclaration[declarationCount];
            _declarationFileRanks = new int[declarationCount];
            _declarationLineNumbers = new int[declarationCount];
            _declarationColumns = new int[declarationCount];
            _declarationNameIds = new int[declarationCount];
            _declarationSlotIndices = declarationCount > 0
                ? new int[declarationCount * 2 + 1]
                : Array.Empty<int>();

            var declarationIndex = 0;
            foreach (var declaration in _map.DeclarationEntries.Values)
            {
                _declarations[declarationIndex] = declaration;
                _declarationFileRanks[declarationIndex] = GetOrAddFileRank(declaration.File);
                _declarationLineNumbers[declarationIndex] = declaration.Line;
                _declarationColumns[declarationIndex] = declaration.Column;
                _declarationNameIds[declarationIndex] = GetOrAddNameId(declaration.Name);
                _declarationIndices[(declaration.File, declaration.Line, declaration.Column)] = declarationIndex;
                declarationIndex++;
            }

            BuildNearestDeclarationIndex();

            var bindingCount = _map.BindingEntries.Count;
            _bindingFileRanks = new int[bindingCount];
            _bindingLineNumbers = new int[bindingCount];
            _bindingColumns = new int[bindingCount];
            _bindingDeclarationIndices = new int[bindingCount];
            _bindingSlotIndices = bindingCount > 0
                ? new int[bindingCount * 2 + 1]
                : Array.Empty<int>();

            var bindingIndex = 0;
            foreach (var (usage, declaration) in _map.BindingEntries)
            {
                _bindingFileRanks[bindingIndex] = GetOrAddFileRank(usage.File);
                _bindingLineNumbers[bindingIndex] = usage.Line;
                _bindingColumns[bindingIndex] = usage.Col;
                _bindingDeclarationIndices[bindingIndex] = _declarationIndices.TryGetValue(
                    (declaration.File, declaration.Line, declaration.Column),
                    out var mappedDeclarationIndex)
                    ? mappedDeclarationIndex
                    : -1;
                bindingIndex++;
            }

            bindings.BindingLookupBuildSlots(
                _declarationFileRanks,
                _declarationLineNumbers,
                _declarationColumns,
                _declarationSlotIndices);
            bindings.BindingLookupBuildSlots(
                _bindingFileRanks,
                _bindingLineNumbers,
                _bindingColumns,
                _bindingSlotIndices);

            _version = _map.Version;
        }

        private void BuildNearestDeclarationIndex()
        {
            var declarationCount = _declarations.Length;
            _sortedDeclarationNameIds = new int[declarationCount];
            _sortedDeclarationFileRanks = new int[declarationCount];
            _sortedDeclarationLineNumbers = new int[declarationCount];
            _sortedDeclarationColumns = new int[declarationCount];
            _sortedDeclarationIndices = new int[declarationCount];

            if (declarationCount == 0)
                return;

            var order = new int[declarationCount];
            for (var i = 0; i < declarationCount; i++)
            {
                order[i] = i;
            }

            Array.Sort(order, CompareDeclarationOrder);

            for (var sortedIndex = 0; sortedIndex < declarationCount; sortedIndex++)
            {
                var declarationIndex = order[sortedIndex];
                _sortedDeclarationNameIds[sortedIndex] = _declarationNameIds[declarationIndex];
                _sortedDeclarationFileRanks[sortedIndex] = _declarationFileRanks[declarationIndex];
                _sortedDeclarationLineNumbers[sortedIndex] = _declarationLineNumbers[declarationIndex];
                _sortedDeclarationColumns[sortedIndex] = _declarationColumns[declarationIndex];
                _sortedDeclarationIndices[sortedIndex] = declarationIndex;
            }
        }

        private int CompareDeclarationOrder(int left, int right)
        {
            var diff = _declarationNameIds[left].CompareTo(_declarationNameIds[right]);
            if (diff != 0)
                return diff;

            diff = _declarationFileRanks[left].CompareTo(_declarationFileRanks[right]);
            if (diff != 0)
                return diff;

            diff = _declarationLineNumbers[left].CompareTo(_declarationLineNumbers[right]);
            if (diff != 0)
                return diff;

            return _declarationColumns[left].CompareTo(_declarationColumns[right]);
        }

        private int GetOrAddFileRank(string? file)
        {
            if (file == null)
                return 0;

            if (_fileRanks.TryGetValue(file, out var rank))
                return rank;

            rank = _fileRanks.Count + 1;
            _fileRanks.Add(file, rank);
            return rank;
        }

        private int GetOrAddNameId(string name)
        {
            if (_nameIds.TryGetValue(name, out var id))
                return id;

            id = _nameIds.Count + 1;
            _nameIds.Add(name, id);
            return id;
        }

        private int GetExistingFileRank(string? file)
        {
            if (file == null)
                return 0;

            return _fileRanks.TryGetValue(file, out var rank) ? rank : -1;
        }

        private int GetExistingNameId(string name) => _nameIds.TryGetValue(name, out var id) ? id : -1;

        private void EnsureQueryCapacity(int count)
        {
            if (_queryFileRanks.Length >= count)
                return;

            _queryNameIds = new int[count];
            _queryFileRanks = new int[count];
            _queryLineNumbers = new int[count];
            _queryColumns = new int[count];
            _resultDeclarationIndices = new int[count];
        }
    }

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

    private static int DiagnosticClusterRiskId(int category) => category switch
    {
        0 or 1 or 2 => 1,
        3 or 4 or 5 or 6 => 2,
        _ => 3
    };

    private sealed class SourceLineCache
    {
        private readonly object _gate = new();
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
        private readonly string[] _queryNames = new string[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly int[] _resultLengths = new int[1];
        private readonly int[] _resultStarts = new int[1];
        private readonly string _source;
        private bool _lineRangesBuilt;
        private int _lineCount;

        public SourceLineCache(string source)
        {
            _source = source;
            var capacity = source.Length + 1;
            _lineStarts = new int[capacity];
            _lineLengths = new int[capacity];
            _queryNames[0] = string.Empty;
        }

        public bool TryExtractSourceLine(Bindings bindings, int line, out string? text)
        {
            text = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceLinesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                text = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryFindIdentifierNameColumn(
            Bindings bindings,
            string name,
            int line,
            int fallbackColumn,
            out int column)
        {
            column = fallbackColumn;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryNames[0] = name;
                _queryColumns[0] = fallbackColumn;
                _resultStarts[0] = fallbackColumn;

                try
                {
                    bindings.IdentifierNameColumnsFromLines(
                        _source,
                        _lineStarts,
                        _lineLengths,
                        _lineCount,
                        _queryLines,
                        _queryNames,
                        _queryColumns,
                        _resultStarts);

                    column = _resultStarts[0];
                    return true;
                }
                finally
                {
                    _queryNames[0] = string.Empty;
                }
            }
        }

        public bool TryExtractEditorIdentifierSpan(
            Bindings bindings,
            int line,
            int column,
            out (int StartColumn, int EndColumn, string Name)? span)
        {
            span = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryColumns[0] = column;
                bindings.EditorIdentifierSpansFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _queryColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                var length = _resultLengths[0];
                if (start < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                span = (start, start + length - 1, _source.Substring(absoluteStart, length));
                return true;
            }
        }

        private void EnsureLineRanges(Bindings bindings)
        {
            if (_lineRangesBuilt)
                return;

            _lineCount = bindings.BuildLineRanges(_source, _lineStarts, _lineLengths);
            _lineRangesBuilt = true;
        }
    }

    private sealed class SnapshotCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<string, FileCache> _files = new(StringComparer.OrdinalIgnoreCase);

        public FileCache GetFileCache(string filePath, string source)
        {
            lock (_gate)
            {
                if (_files.TryGetValue(filePath, out var cache) && cache.Matches(source))
                    return cache;

                cache = new FileCache(source);
                _files[filePath] = cache;
                return cache;
            }
        }
    }

    private sealed class FileCache
    {
        private readonly object _gate = new();
        private readonly int[] _docCommentLengths;
        private readonly int[] _docCommentStarts;
        private readonly int[] _lineLengths;
        private readonly int[] _lineStarts;
        private readonly int[] _declarationColumns = new int[1];
        private readonly int[] _memberStartColumns = new int[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly string[] _queryNames = new string[1];
        private readonly int[] _receiverLengthsBySeparator;
        private readonly int[] _receiverStartsBySeparator;
        private readonly int[] _resultLengths = new int[1];
        private readonly int[] _resultMatches = new int[1];
        private readonly int[] _resultStarts = new int[1];
        private readonly int[] _selectedEndColumns = new int[1];
        private readonly int[] _selectedStartColumns = new int[1];
        private readonly string _source;
        private readonly int[] _variableDeclarationNameLengthsByLine;
        private readonly int[] _variableDeclarationNameStartsByLine;
        private bool _lineRangesBuilt;
        private int _lineCount;
        private bool _receiverCacheBuilt;
        private bool _variableDeclarationNameCacheBuilt;

        public FileCache(string source)
        {
            _source = source;
            var capacity = source.Length + 1;
            _docCommentStarts = new int[capacity];
            _docCommentLengths = new int[capacity];
            _lineStarts = new int[capacity];
            _lineLengths = new int[capacity];
            _receiverStartsBySeparator = new int[capacity];
            _receiverLengthsBySeparator = new int[capacity];
            _variableDeclarationNameStartsByLine = new int[capacity];
            _variableDeclarationNameLengthsByLine = new int[capacity];
        }

        public bool Matches(string source) =>
            ReferenceEquals(_source, source) || string.Equals(_source, source, StringComparison.Ordinal);

        public bool TryExtractIdentifierSpan(
            Bindings bindings,
            int line,
            int column,
            out (int StartColumn, int EndColumn)? span)
        {
            span = null;
            lock (_gate)
            {
                var found = TryExtractIdentifierSpanCore(bindings, line, column, out var start, out var length);
                if (!found)
                    return true;

                span = (start, start + length - 1);
                return true;
            }
        }

        public bool TryExtractDocComment(Bindings bindings, int definitionLine, out string? documentation)
        {
            documentation = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                var lineCount = bindings.DocCommentLinesFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    definitionLine,
                    _docCommentStarts,
                    _docCommentLengths);

                if (lineCount <= 0)
                    return true;

                var builder = new StringBuilder();
                for (var i = 0; i < lineCount; i++)
                {
                    if (i > 0)
                    {
                        builder.Append('\n');
                    }

                    builder.Append(_source, _docCommentStarts[i], _docCommentLengths[i]);
                }

                documentation = builder.ToString();
                return true;
            }
        }

        public bool TrySelectedSpanMatchesDeclarationName(
            Bindings bindings,
            int line,
            int declarationColumn,
            string declarationName,
            int selectedStartColumn,
            int selectedEndColumn,
            out bool matches)
        {
            matches = false;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _declarationColumns[0] = declarationColumn;
                _queryNames[0] = declarationName;
                _selectedStartColumns[0] = selectedStartColumn;
                _selectedEndColumns[0] = selectedEndColumn;

                bindings.DeclarationNameMatchesFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _declarationColumns,
                    _queryNames,
                    _selectedStartColumns,
                    _selectedEndColumns,
                    _resultMatches);

                matches = _resultMatches[0] != 0;
                _queryNames[0] = string.Empty;
                return true;
            }
        }

        public bool TryExtractCompletionPrefix(Bindings bindings, int line, int column, out string? prefix)
        {
            prefix = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                _queryColumns[0] = column;
                bindings.CompletionPrefixesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _queryColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                prefix = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractIdentifierName(
            Bindings bindings,
            int line,
            int column,
            out string? name)
        {
            name = null;
            lock (_gate)
            {
                var found = TryExtractIdentifierSpanCore(bindings, line, column, out var start, out var length);
                if (!found)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                name = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        public bool TryExtractMemberReceiverName(
            Bindings bindings,
            int line,
            int memberStartColumn,
            out string? receiverName)
        {
            receiverName = null;
            lock (_gate)
            {
                EnsureReceiverCache(bindings);

                _queryLines[0] = line;
                _memberStartColumns[0] = memberStartColumn;
                bindings.MemberReceiversFromCache(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _receiverStartsBySeparator,
                    _receiverLengthsBySeparator,
                    _queryLines,
                    _memberStartColumns,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                var length = _resultLengths[0];
                if (start < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + start - 1;
                receiverName = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        public bool TryExtractSourceContext(Bindings bindings, int line, out string? context)
        {
            context = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceContextsFromLines(
                    _source,
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                context = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractSourceLine(Bindings bindings, int line, out string? text)
        {
            text = null;
            lock (_gate)
            {
                EnsureLineRanges(bindings);

                _queryLines[0] = line;
                bindings.SourceLinesFromLines(
                    _lineStarts,
                    _lineLengths,
                    _lineCount,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var start = _resultStarts[0];
                if (start < 0)
                    return true;

                text = _source.Substring(start, _resultLengths[0]);
                return true;
            }
        }

        public bool TryExtractVariableDeclarationName(Bindings bindings, int line, out string? name)
        {
            name = null;
            lock (_gate)
            {
                EnsureVariableDeclarationNameCache(bindings);

                _queryLines[0] = line;
                bindings.VariableDeclarationNamesFromCache(
                    _lineCount,
                    _variableDeclarationNameStartsByLine,
                    _variableDeclarationNameLengthsByLine,
                    _queryLines,
                    _resultStarts,
                    _resultLengths);

                var startColumn = _resultStarts[0];
                var length = _resultLengths[0];
                if (startColumn < 0 || length <= 0)
                    return true;

                var absoluteStart = _lineStarts[line - 1] + startColumn - 1;
                name = _source.Substring(absoluteStart, length);
                return true;
            }
        }

        private bool TryExtractIdentifierSpanCore(
            Bindings bindings,
            int line,
            int column,
            out int start,
            out int length)
        {
            EnsureLineRanges(bindings);

            _queryLines[0] = line;
            _queryColumns[0] = column;
            bindings.IdentifierSpansFromLines(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _queryLines,
                _queryColumns,
                _resultStarts,
                _resultLengths);

            start = _resultStarts[0];
            length = _resultLengths[0];
            return start >= 0 && length > 0;
        }

        private void EnsureLineRanges(Bindings bindings)
        {
            if (_lineRangesBuilt)
                return;

            _lineCount = bindings.BuildLineRanges(_source, _lineStarts, _lineLengths);
            _lineRangesBuilt = true;
        }

        private void EnsureReceiverCache(Bindings bindings)
        {
            if (_receiverCacheBuilt)
                return;

            EnsureLineRanges(bindings);
            bindings.BuildMemberReceiverCache(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _receiverStartsBySeparator,
                _receiverLengthsBySeparator);
            _receiverCacheBuilt = true;
        }

        private void EnsureVariableDeclarationNameCache(Bindings bindings)
        {
            if (_variableDeclarationNameCacheBuilt)
                return;

            EnsureLineRanges(bindings);
            bindings.BuildVariableDeclarationNameCache(
                _source,
                _lineStarts,
                _lineLengths,
                _lineCount,
                _variableDeclarationNameStartsByLine,
                _variableDeclarationNameLengthsByLine);
            _variableDeclarationNameCacheBuilt = true;
        }
    }
}
