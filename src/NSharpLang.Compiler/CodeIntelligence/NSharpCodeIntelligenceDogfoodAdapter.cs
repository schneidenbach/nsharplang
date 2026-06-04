using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class NSharpCodeIntelligenceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<ProjectSnapshot, SnapshotCache> s_snapshotCaches = new();
    private static readonly ConditionalWeakTable<string, SourceLineCache> s_sourceLineCaches = new();
    [ThreadStatic]
    private static CompletionReceiverScratch? t_completionReceiverScratch;
    [ThreadStatic]
    private static DiagnosticSummaryScratch? t_diagnosticSummaryScratch;
    [ThreadStatic]
    private static DiagnosticClusterGroupingScratch? t_diagnosticClusterGroupingScratch;
    [ThreadStatic]
    private static DiagnosticDeduplicationScratch? t_diagnosticDeduplicationScratch;
    [ThreadStatic]
    private static ReferenceDeduplicationScratch? t_referenceDeduplicationScratch;

    internal static bool IsAvailable => s_bindings.Value != null;

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

            grouping = new DiagnosticClusterGrouping(
                groupCount,
                scratch.RootIndices,
                scratch.Counts,
                scratch.CodeIds,
                scratch.SeverityIds,
                scratch.CategoryIds,
                scratch.SourceConstructIds,
                scratch.RecipeIds,
                scratch.RiskIds,
                scratch.MessagePatternIds);
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

    private static FileCache GetFileCache(ProjectSnapshot snapshot, string filePath, string source)
    {
        var snapshotCache = s_snapshotCaches.GetValue(snapshot, static _ => new SnapshotCache());
        return snapshotCache.GetFileCache(Path.GetFullPath(filePath), source);
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
                CreateDelegate<BuildCodeIntelligenceLineRangesInto>(programType, "BuildCodeIntelligenceLineRangesInto"),
                CreateDelegate<BuildCodeIntelligenceMemberReceiverCacheInto>(programType, "BuildCodeIntelligenceMemberReceiverCacheInto"),
                CreateDelegate<BuildCodeIntelligenceVariableDeclarationNameCacheInto>(programType, "BuildCodeIntelligenceVariableDeclarationNameCacheInto"),
                CreateDelegate<CodeIntelligenceDeclarationNameMatchesFromLinesInto>(programType, "CodeIntelligenceDeclarationNameMatchesFromLinesInto"),
                CreateDelegate<CodeIntelligenceIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceEditorIdentifierSpansFromLinesInto>(programType, "CodeIntelligenceEditorIdentifierSpansFromLinesInto"),
                CreateDelegate<CodeIntelligenceCompletionPrefixesFromLinesInto>(programType, "CodeIntelligenceCompletionPrefixesFromLinesInto"),
                CreateDelegate<CodeIntelligenceDocCommentLinesFromLinesInto>(programType, "CodeIntelligenceDocCommentLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceMemberReceiversFromCacheInto>(programType, "CodeIntelligenceMemberReceiversFromCacheInto"),
                CreateDelegate<CodeIntelligenceSourceContextsFromLinesInto>(programType, "CodeIntelligenceSourceContextsFromLinesInto"),
                CreateDelegate<CodeIntelligenceSourceLinesFromLinesInto>(programType, "CodeIntelligenceSourceLinesFromLinesInto"),
                CreateDelegate<CodeIntelligenceVariableDeclarationNamesFromCacheInto>(programType, "CodeIntelligenceVariableDeclarationNamesFromCacheInto"),
                CreateDelegate<CodeIntelligenceCompletionReceiversInto>(programType, "CodeIntelligenceCompletionReceiversInto"),
                CreateDelegate<DiagnosticSeveritySummaryInto>(programType, "DiagnosticSeveritySummaryInto"),
                CreateDelegate<DiagnosticClusterTraitsInto>(programType, "DiagnosticClusterTraitsInto"),
                CreateDelegate<DiagnosticClusterCompactGroupsInto>(programType, "DiagnosticClusterCompactGroupsInto"),
                CreateDelegate<DiagnosticDeduplicateCompactInto>(programType, "DiagnosticDeduplicateCompactInto"),
                CreateDelegate<ReferenceDeduplicateCompactInto>(programType, "ReferenceDeduplicateCompactInto"));
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

    private sealed record Bindings(
        BuildCodeIntelligenceLineRangesInto BuildLineRanges,
        BuildCodeIntelligenceMemberReceiverCacheInto BuildMemberReceiverCache,
        BuildCodeIntelligenceVariableDeclarationNameCacheInto BuildVariableDeclarationNameCache,
        CodeIntelligenceDeclarationNameMatchesFromLinesInto DeclarationNameMatchesFromLines,
        CodeIntelligenceIdentifierSpansFromLinesInto IdentifierSpansFromLines,
        CodeIntelligenceEditorIdentifierSpansFromLinesInto EditorIdentifierSpansFromLines,
        CodeIntelligenceCompletionPrefixesFromLinesInto CompletionPrefixesFromLines,
        CodeIntelligenceDocCommentLinesFromLinesInto DocCommentLinesFromLines,
        CodeIntelligenceMemberReceiversFromCacheInto MemberReceiversFromCache,
        CodeIntelligenceSourceContextsFromLinesInto SourceContextsFromLines,
        CodeIntelligenceSourceLinesFromLinesInto SourceLinesFromLines,
        CodeIntelligenceVariableDeclarationNamesFromCacheInto VariableDeclarationNamesFromCache,
        CodeIntelligenceCompletionReceiversInto CompletionReceivers,
        DiagnosticSeveritySummaryInto DiagnosticSeveritySummary,
        DiagnosticClusterTraitsInto DiagnosticClusterTraits,
        DiagnosticClusterCompactGroupsInto DiagnosticClusterCompactGroups,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateCompact,
        ReferenceDeduplicateCompactInto ReferenceDeduplicateCompact);

    internal sealed class DiagnosticClusterGrouping
    {
        public DiagnosticClusterGrouping(
            int groupCount,
            int[] rootIndices,
            int[] counts,
            int[] codeIds,
            int[] severityIds,
            int[] categoryIds,
            int[] sourceConstructIds,
            int[] recipeIds,
            int[] riskIds,
            int[] messagePatternIds)
        {
            GroupCount = groupCount;
            RootIndices = rootIndices;
            Counts = counts;
            CodeIds = codeIds;
            SeverityIds = severityIds;
            CategoryIds = categoryIds;
            SourceConstructIds = sourceConstructIds;
            RecipeIds = recipeIds;
            RiskIds = riskIds;
            MessagePatternIds = messagePatternIds;
        }

        public int GroupCount { get; }
        public int[] RootIndices { get; }
        public int[] Counts { get; }
        public int[] CodeIds { get; }
        public int[] SeverityIds { get; }
        public int[] CategoryIds { get; }
        public int[] SourceConstructIds { get; }
        public int[] RecipeIds { get; }
        public int[] RiskIds { get; }
        public int[] MessagePatternIds { get; }

        public bool KeyMatches(int left, int right) =>
            SeverityIds[left] == SeverityIds[right]
            && CodeIds[left] == CodeIds[right]
            && CategoryIds[left] == CategoryIds[right]
            && SourceConstructIds[left] == SourceConstructIds[right]
            && RecipeIds[left] == RecipeIds[right]
            && RiskIds[left] == RiskIds[right]
            && MessagePatternIds[left] == MessagePatternIds[right];
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
        public int[] GroupKeyIndices = Array.Empty<int>();
        public int[] Lines = Array.Empty<int>();
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
