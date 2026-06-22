using System;
using System.Collections.Generic;
using System.Globalization;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

internal readonly record struct DocOptionSummary(
    string? ProjectOption,
    string? OutputOption,
    bool Json,
    bool Open,
    bool ShowHelp);

internal enum DocOutputModeKind
{
    Json = 1,
    Text = 2
}

internal static class DocCommandKernels
{
    [ThreadStatic]
    private static SymbolOrderScratch? t_symbolOrderScratch;
    [ThreadStatic]
    private static int[]? t_optionSummaryIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOptionSummary(string[] args, out DocOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionSummaryIndices ??= new int[5];
        try
        {
            var code = bindings.OptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var outputOption))
            {
                summary = default;
                return false;
            }

            summary = new DocOptionSummary(
                projectOption,
                outputOption,
                resultIndices[2] != 0,
                resultIndices[3] != 0,
                resultIndices[4] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    internal static bool TryGetOutputMode(bool json, out DocOutputModeKind outputMode)
    {
        outputMode = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var code = bindings.OutputMode(json ? 1 : 0);
            if (code is < 1 or > 2)
                return false;

            outputMode = (DocOutputModeKind)code;
            return true;
        }
        catch
        {
            outputMode = default;
            return false;
        }
    }

    internal static bool TryOrderSymbolsForGeneration(
        IReadOnlyList<SymbolResult> symbols,
        out List<SymbolResult> orderedSymbols)
        => TryOrderEntriesForGeneration(symbols, includeAllKinds: false, out orderedSymbols);

    internal static bool TryOrderMembersForGeneration(
        IReadOnlyList<SymbolResult> members,
        out List<SymbolResult> orderedMembers)
        => TryOrderEntriesForGeneration(members, includeAllKinds: true, out orderedMembers);

    internal static bool TryCreateSlugs(string[] rawSlugs, out string[] slugs)
    {
        slugs = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var resultSlugs = new string[rawSlugs.Length];
            var count = bindings.DocSlugs(rawSlugs, resultSlugs);
            if (count != rawSlugs.Length)
                return false;

            slugs = resultSlugs;
            return true;
        }
        catch
        {
            slugs = Array.Empty<string>();
            return false;
        }
    }

    internal static string GetHelpText()
        => TryGetMessage(bindings => bindings.HelpText(), out var message)
            ? message
            : FallbackHelpText();

    internal static string GetProjectDirectoryNotFoundMessage(string projectRoot)
        => TryGetMessage(bindings => bindings.ProjectDirectoryNotFoundMessage(projectRoot), out var message)
            ? message
            : FallbackProjectDirectoryNotFoundMessage(projectRoot);

    internal static string GetGeneratedSummaryMessage(int pageCount)
    {
        var pageCountText = pageCount.ToString(CultureInfo.InvariantCulture);
        return TryGetMessage(bindings => bindings.GeneratedSummaryMessage(pageCountText), out var message)
            ? message
            : FallbackGeneratedSummaryMessage(pageCountText);
    }

    internal static string GetOutputPathMessage(string outputDir)
        => TryGetMessage(bindings => bindings.OutputPathMessage(outputDir), out var message)
            ? message
            : FallbackOutputPathMessage(outputDir);

    internal static string GetIndexPathMessage(string indexPath)
        => TryGetMessage(bindings => bindings.IndexPathMessage(indexPath), out var message)
            ? message
            : FallbackIndexPathMessage(indexPath);

    internal static string GetOpenedMessage()
        => TryGetMessage(bindings => bindings.OpenedMessage(), out var message)
            ? message
            : FallbackOpenedMessage();

    internal static string GetGenerationFailedMessage(string exceptionMessage)
        => TryGetMessage(bindings => bindings.GenerationFailedMessage(exceptionMessage), out var message)
            ? message
            : FallbackGenerationFailedMessage(exceptionMessage);

    internal static string GetOpenFailedMessage(string indexPath)
        => TryGetMessage(bindings => bindings.OpenFailedMessage(indexPath), out var message)
            ? message
            : FallbackOpenFailedMessage(indexPath);

    internal static string GetOpenFailedWithDetailMessage(string indexPath, string exceptionMessage)
        => TryGetMessage(bindings => bindings.OpenFailedWithDetailMessage(indexPath, exceptionMessage), out var message)
            ? message
            : FallbackOpenFailedWithDetailMessage(indexPath, exceptionMessage);

    internal static string GetLocationText(string relativePath, int line, int column)
        => GetLocationText(
            relativePath,
            line.ToString(CultureInfo.InvariantCulture),
            column.ToString(CultureInfo.InvariantCulture));

    internal static string GetLocationText(string relativePath, string lineText, string columnText)
        => TryGetMessage(bindings => bindings.LocationText(relativePath, lineText, columnText), out var message)
            ? message
            : FallbackLocationText(relativePath, lineText, columnText);

    internal static string GetParameterText(string name, string typeName, bool hasDefault, string defaultValue)
        => TryGetMessage(bindings => bindings.ParameterText(name, typeName, hasDefault ? 1 : 0, defaultValue), out var message)
            ? message
            : FallbackParameterText(name, typeName, hasDefault, defaultValue);

    internal static string GetSignatureText(
        SymbolKind kind,
        string name,
        bool hasParameterList,
        string parametersText,
        string typeName)
        => TryGetMessage(
            bindings => bindings.SignatureText((int)kind, name, hasParameterList ? 1 : 0, parametersText, typeName),
            out var message)
            ? message
            : FallbackSignatureText(kind, name, hasParameterList, parametersText, typeName);

    private static bool TryOrderEntriesForGeneration(
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

        var scratch = t_symbolOrderScratch ??= new SymbolOrderScratch();
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
                scratch.KindRanks[i] = GetSymbolKindRank(symbol.Kind);
                scratch.NameRanks[i] = scratch.GetNameRank(symbol.Name);
                scratch.IncludeFlags[i] = (includeAllKinds || IsDocumentedSymbolKind(symbol.Kind)) ? 1 : 0;
            }

            var orderedCount = bindings.SymbolOrderCountingIndices(
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
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliDocSymbolOrderCountingIndicesInto>(
                programType,
                "CliDocSymbolOrderCountingIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliDocSlugsInto>(
                programType,
                "CliDocSlugsInto"),
            DogfoodKernelLoader.CreateDelegate<CliDocOptionSummaryInto>(
                programType,
                "CliDocOptionSummaryInto"),
            DogfoodKernelLoader.CreateDelegate<CliDocOutputMode>(
                programType,
                "CliDocOutputMode"),
            DogfoodKernelLoader.CreateDelegate<CliDocHelpText>(
                programType,
                "CliDocHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliDocProjectDirectoryNotFoundMessage>(
                programType,
                "CliDocProjectDirectoryNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocGeneratedSummaryMessage>(
                programType,
                "CliDocGeneratedSummaryMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocOutputPathMessage>(
                programType,
                "CliDocOutputPathMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocIndexPathMessage>(
                programType,
                "CliDocIndexPathMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocOpenedMessage>(
                programType,
                "CliDocOpenedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocGenerationFailedMessage>(
                programType,
                "CliDocGenerationFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocOpenFailedMessage>(
                programType,
                "CliDocOpenFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocOpenFailedWithDetailMessage>(
                programType,
                "CliDocOpenFailedWithDetailMessage"),
            DogfoodKernelLoader.CreateDelegate<CliDocLocationText>(
                programType,
                "CliDocLocationText"),
            DogfoodKernelLoader.CreateDelegate<CliDocParameterText>(
                programType,
                "CliDocParameterText"),
            DogfoodKernelLoader.CreateDelegate<CliDocSignatureText>(
                programType,
                "CliDocSignatureText")));

    private static bool IsDocumentedSymbolKind(SymbolKind kind) =>
        kind is not SymbolKind.Variable and not SymbolKind.Parameter;

    private static int GetSymbolKindRank(SymbolKind kind) =>
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

    private delegate int CliDocSlugsInto(string[] rawSlugs, string[] resultSlugs);

    private delegate int CliDocOptionSummaryInto(
        string[] args,
        int[] resultIndices);

    private delegate int CliDocOutputMode(int json);

    private delegate string CliDocHelpText();

    private delegate string CliDocProjectDirectoryNotFoundMessage(string projectRoot);

    private delegate string CliDocGeneratedSummaryMessage(string pageCountText);

    private delegate string CliDocOutputPathMessage(string outputDir);

    private delegate string CliDocIndexPathMessage(string indexPath);

    private delegate string CliDocOpenedMessage();

    private delegate string CliDocGenerationFailedMessage(string message);

    private delegate string CliDocOpenFailedMessage(string indexPath);

    private delegate string CliDocOpenFailedWithDetailMessage(string indexPath, string message);

    private delegate string CliDocLocationText(string relativePath, string lineText, string columnText);

    private delegate string CliDocParameterText(string name, string typeName, int hasDefault, string defaultValue);

    private delegate string CliDocSignatureText(
        int kind,
        string name,
        int hasParameterList,
        string parametersText,
        string typeName);

    private sealed record Bindings(
        CliDocSymbolOrderCountingIndicesInto SymbolOrderCountingIndices,
        CliDocSlugsInto DocSlugs,
        CliDocOptionSummaryInto OptionSummary,
        CliDocOutputMode OutputMode,
        CliDocHelpText HelpText,
        CliDocProjectDirectoryNotFoundMessage ProjectDirectoryNotFoundMessage,
        CliDocGeneratedSummaryMessage GeneratedSummaryMessage,
        CliDocOutputPathMessage OutputPathMessage,
        CliDocIndexPathMessage IndexPathMessage,
        CliDocOpenedMessage OpenedMessage,
        CliDocGenerationFailedMessage GenerationFailedMessage,
        CliDocOpenFailedMessage OpenFailedMessage,
        CliDocOpenFailedWithDetailMessage OpenFailedWithDetailMessage,
        CliDocLocationText LocationText,
        CliDocParameterText ParameterText,
        CliDocSignatureText SignatureText);

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return message.Length > 0;
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product doc messages route through CliDoc* kernels.
    private static string FallbackLocationText(string relativePath, string lineText, string columnText)
        => $"{relativePath}:{lineText}:{columnText}";

    private static string FallbackParameterText(string name, string typeName, bool hasDefault, string defaultValue)
        => hasDefault
            ? $"{name}: {typeName} = {defaultValue}"
            : $"{name}: {typeName}";

    private static string FallbackSignatureText(
        SymbolKind kind,
        string name,
        bool hasParameterList,
        string parametersText,
        string typeName)
    {
        var parameters = hasParameterList ? $"({parametersText})" : string.Empty;
        var suffix = string.IsNullOrEmpty(typeName) ? string.Empty : $": {typeName}";
        return $"{FallbackSignaturePrefix(kind)}{name}{parameters}{suffix}";
    }

    private static string FallbackSignaturePrefix(SymbolKind kind)
        => kind switch
        {
            SymbolKind.Function => "func ",
            SymbolKind.Method => "func ",
            SymbolKind.Constructor => "ctor ",
            SymbolKind.Class => "class ",
            SymbolKind.Struct => "struct ",
            SymbolKind.Record => "record ",
            SymbolKind.Interface => "interface ",
            SymbolKind.Enum => "enum ",
            SymbolKind.Union => "union ",
            SymbolKind.Property => "prop ",
            SymbolKind.Field => "field ",
            SymbolKind.TypeAlias => "type ",
            SymbolKind.Test => "test ",
            _ => string.Empty
        };

    private static string FallbackHelpText()
        => @"N# API Documentation

Usage: nlc doc [options]

Generate HTML API documentation for the current project. Similar to `cargo doc`.

Options:
  --project <dir>   Project root directory (default: current directory)
  --output <dir>    Output directory (default: ./nsharp/docs)
  --json            Emit a structured JSON result envelope
  --open            Open the generated index in the default browser
  --help, -h        Show this help text

Examples:
  nlc doc
  nlc doc --open
  nlc doc --json
  nlc doc --project examples/16-task-cli --output /tmp/nsharp-docs

Exit codes:
  0  Documentation generated successfully
  1  Documentation generation failed";

    private static string FallbackProjectDirectoryNotFoundMessage(string projectRoot)
        => $"Project directory not found: {projectRoot}";

    private static string FallbackGeneratedSummaryMessage(string pageCountText)
        => $"Generated API docs for {pageCountText} symbols.";

    private static string FallbackOutputPathMessage(string outputDir)
        => $"Output: {outputDir}";

    private static string FallbackIndexPathMessage(string indexPath)
        => $"Index: {indexPath}";

    private static string FallbackOpenedMessage()
        => "Opened generated documentation in the default browser.";

    private static string FallbackGenerationFailedMessage(string message)
        => $"Doc generation failed: {message}";

    private static string FallbackOpenFailedMessage(string indexPath)
        => $"Generated docs, but failed to open {indexPath}.";

    private static string FallbackOpenFailedWithDetailMessage(string indexPath, string message)
        => $"Generated docs, but failed to open {indexPath}: {message}";

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    private sealed class SymbolOrderScratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.Ordinal);

        internal int[] IncludeFlags = Array.Empty<int>();
        internal int[] KindCounts = Array.Empty<int>();
        internal int[] KindOffsets = Array.Empty<int>();
        internal int[] KindRanks = Array.Empty<int>();
        internal int[] NameCounts = Array.Empty<int>();
        internal int[] NameOffsets = Array.Empty<int>();
        internal int[] NameRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] TempIndices = Array.Empty<int>();
        internal string[] UniqueNames = Array.Empty<string>();
        internal int UniqueNameCount;

        internal void EnsureCapacity(int symbolCount)
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

        internal void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            _nameRanks.Add(name, 0);
            UniqueNames[UniqueNameCount] = name;
            UniqueNameCount++;
        }

        internal void BuildSortedNameRanks()
        {
            Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueNameCount; i++)
            {
                _nameRanks[UniqueNames[i]] = i + 1;
            }
        }

        internal int GetNameRank(string name) => _nameRanks[name];

        internal void ResetNames()
        {
            _nameRanks.Clear();
            if (UniqueNameCount > 0)
            {
                Array.Clear(UniqueNames, 0, UniqueNameCount);
                UniqueNameCount = 0;
            }
        }
    }
}
