using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterDiagnosticClusterKernels
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DiagnosticClusterGroupingScratch? t_diagnosticClusterGroupingScratch;

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
                scratch.RiskIds[i] = GetRiskId(category);
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

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<DiagnosticClusterTraitsInto>(
                    programType,
                    "DiagnosticClusterTraitsInto"),
                CreateDelegate<DiagnosticClusterCompactGroupsInto>(
                    programType,
                    "DiagnosticClusterCompactGroupsInto"),
                CreateDelegate<DiagnosticClusterCompactGroupMembersInto>(
                    programType,
                    "DiagnosticClusterCompactGroupMembersInto"));
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

    private static int GetRiskId(int category) => category switch
    {
        0 or 1 or 2 => 1,
        3 or 4 or 5 or 6 => 2,
        _ => 3
    };

    private delegate int DiagnosticClusterTraitsInto(
        string[] codes,
        string[] messages,
        string[] snippets,
        int[] resultCategories,
        int[] resultSourceConstructs);

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

    private sealed record Bindings(
        DiagnosticClusterTraitsInto DiagnosticClusterTraits,
        DiagnosticClusterCompactGroupsInto DiagnosticClusterCompactGroups,
        DiagnosticClusterCompactGroupMembersInto DiagnosticClusterCompactGroupMembers);

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
}
