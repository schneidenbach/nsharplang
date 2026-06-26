using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Versioned effect summary catalog for external hot-callable APIs. Source
/// inference is handled by <see cref="SystemsAnalyzer"/>; this model represents
/// compiler/BCL seed facts and explicit sidecar facts.
/// </summary>
public sealed class HotSummaryCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly List<HotSummaryEntry> _entries;

    private HotSummaryCatalog(IEnumerable<HotSummaryEntry> entries)
    {
        _entries = entries.ToList();
    }

    public static HotSummaryCatalog Load(string projectRoot, ProjectConfig config)
    {
        var entries = new List<HotSummaryEntry>();
        entries.AddRange(BclHotSummaryPack.Create(config.TargetFramework));

        foreach (var sidecar in config.Language.Systems.HotSummaryFiles)
        {
            var path = Path.IsPathRooted(sidecar)
                ? sidecar
                : Path.Combine(projectRoot, sidecar);
            if (!File.Exists(path))
                continue;

            var document = JsonSerializer.Deserialize<HotSummaryDocument>(File.ReadAllText(path), JsonOptions);
            if (document?.Entries == null)
                continue;

            foreach (var entry in document.Entries)
            {
                if (entry.SchemaVersion == 0)
                    entry.SchemaVersion = document.SchemaVersion == 0 ? 1 : document.SchemaVersion;
                if (string.IsNullOrWhiteSpace(entry.Source))
                    entry.Source = HotSummarySource.Sidecar;
                if (string.IsNullOrWhiteSpace(entry.TargetFramework))
                    entry.TargetFramework = config.TargetFramework;
                entries.Add(entry);
            }
        }

        return new HotSummaryCatalog(entries);
    }

    public bool TryResolve(string target, string targetFramework, out HotSummaryEntry entry)
    {
        foreach (var candidate in _entries)
        {
            if (!TargetFrameworkMatches(candidate.TargetFramework, targetFramework))
                continue;
            if (MethodMatches(candidate.Method, target))
            {
                entry = candidate;
                return true;
            }
        }

        entry = HotSummaryEntry.None;
        return false;
    }

    public bool HasReceiverSummary(string receiver, string targetFramework)
        => _entries.Any(entry =>
            TargetFrameworkMatches(entry.TargetFramework, targetFramework)
            && (entry.Method.StartsWith(receiver + ".", StringComparison.Ordinal)
                || entry.Method.StartsWith("System." + receiver + ".", StringComparison.Ordinal)
                || entry.Method.StartsWith(receiver + "*", StringComparison.Ordinal)));

    private static bool TargetFrameworkMatches(string? summaryTfm, string targetFramework)
        => string.IsNullOrWhiteSpace(summaryTfm)
           || string.Equals(summaryTfm, targetFramework, StringComparison.OrdinalIgnoreCase)
           || string.Equals(summaryTfm, "*", StringComparison.Ordinal);

    private static bool MethodMatches(string pattern, string target)
    {
        if (string.IsNullOrWhiteSpace(pattern))
            return false;

        if (pattern.IndexOf('*') >= 0 && !pattern.EndsWith(".*", StringComparison.Ordinal))
            return GlobMatches(pattern, target) || GlobMatches(pattern, "System." + target);

        if (pattern.EndsWith(".*", StringComparison.Ordinal))
        {
            var prefix = pattern[..^1];
            return target.StartsWith(prefix, StringComparison.Ordinal)
                   || target.EndsWith("." + prefix, StringComparison.Ordinal);
        }

        return string.Equals(pattern, target, StringComparison.Ordinal)
               || target.EndsWith("." + pattern, StringComparison.Ordinal);
    }

    private static bool GlobMatches(string pattern, string target)
    {
        var parts = pattern.Split('*');
        var position = 0;
        foreach (var part in parts)
        {
            if (part.Length == 0)
                continue;

            var found = target.IndexOf(part, position, StringComparison.Ordinal);
            if (found < 0)
                return false;

            if (position == 0 && !pattern.StartsWith('*') && found != 0)
                return false;

            position = found + part.Length;
        }

        return pattern.EndsWith('*') || position == target.Length;
    }
}
