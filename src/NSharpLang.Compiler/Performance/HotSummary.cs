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

public sealed class HotSummaryDocument
{
    public int SchemaVersion { get; set; } = 1;
    public List<HotSummaryEntry> Entries { get; set; } = new();
}

public sealed class HotSummaryEntry
{
    public static HotSummaryEntry None { get; } = new();

    public int SchemaVersion { get; set; } = 1;
    public string AssemblyIdentity { get; set; } = "";
    public string? PublicKeyToken { get; set; }
    public string? PackageId { get; set; }
    public string? PackageVersion { get; set; }
    public string TargetFramework { get; set; } = "*";
    public string? RuntimeIdentifier { get; set; }
    public string Method { get; set; } = "";
    public int GenericArity { get; set; }
    public string? BodyIdentity { get; set; }
    public HotSummaryEffects Effects { get; set; } = new();
    public List<string> GenericConditions { get; set; } = new();
    public List<string> Preconditions { get; set; } = new();
    public List<string> HotReadinessRequirements { get; set; } = new();
    public string Source { get; set; } = HotSummarySource.Compiler;

    [JsonIgnore]
    public bool IsSidecar => string.Equals(Source, HotSummarySource.Sidecar, StringComparison.OrdinalIgnoreCase);

    public bool IsAotSafeFor(string target)
    {
        if (!Effects.AotSafe)
            return false;

        return Effects.AotSafeTargets.Count == 0
               || Effects.AotSafeTargets.Contains(target, StringComparer.OrdinalIgnoreCase);
    }
}

public sealed class HotSummaryEffects
{
    public bool Allocates { get; set; }
    public bool Boxes { get; set; }
    public bool ConstructsDelegate { get; set; }
    public bool CapturesClosure { get; set; }
    public bool UsesRuntimeDispatch { get; set; }
    public bool UsesReflection { get; set; }
    public bool UsesDynamicCode { get; set; }
    public bool Throws { get; set; }
    public bool HasImplicitTrapObligation { get; set; }
    public bool UsesUnknownExternalCall { get; set; }
    public bool UsesResource { get; set; }
    public bool UsesPool { get; set; }
    public bool UsesConcurrencyPrimitive { get; set; }
    public bool RequiresWarmup { get; set; }
    public bool AotSafe { get; set; } = true;
    public bool TrimSafe { get; set; } = true;
    public List<string> AotSafeTargets { get; set; } = new();
}

public static class HotSummarySource
{
    public const string Compiler = "compiler";
    public const string BclPack = "bclPack";
    public const string SourceInferred = "sourceInferred";
    public const string Sidecar = "sidecar";
    public const string TrustedMemoryOnly = "trustedMemoryOnly";
}

internal static class BclHotSummaryPack
{
    public static IReadOnlyList<HotSummaryEntry> Create(string targetFramework)
    {
        var entries = new List<HotSummaryEntry>();

        Add(entries, targetFramework, "BinaryPrimitives.*");
        Add(entries, targetFramework, "System.Buffers.Binary.BinaryPrimitives.*");
        Add(entries, targetFramework, "MemoryExtensions.*");
        Add(entries, targetFramework, "System.MemoryExtensions.*");
        Add(entries, targetFramework, "MemoryMarshal.*");
        Add(entries, targetFramework, "System.Runtime.InteropServices.MemoryMarshal.*");
        Add(entries, targetFramework, "Buffer.MemoryCopy");
        Add(entries, targetFramework, "System.Buffer.MemoryCopy");
        Add(entries, targetFramework, "BitOperations.*");
        Add(entries, targetFramework, "System.Numerics.BitOperations.*");
        Add(entries, targetFramework, "Vector.*");
        Add(entries, targetFramework, "System.Numerics.Vector.*");
        Add(entries, targetFramework, "Math.*");
        Add(entries, targetFramework, "System.Math.*");
        Add(entries, targetFramework, "MathF.*");
        Add(entries, targetFramework, "System.MathF.*");
        Add(entries, targetFramework, "Span.*");
        Add(entries, targetFramework, "ReadOnlySpan.*");
        Add(entries, targetFramework, "String.get_Length");
        Add(entries, targetFramework, "Array.get_Length");
        Add(entries, targetFramework, "Slice");
        Add(entries, targetFramework, "AsSpan");
        Add(entries, targetFramework, "CopyTo");
        Add(entries, targetFramework, "Clear");
        Add(entries, targetFramework, "Fill");
        Add(entries, targetFramework, "Length");
        Add(entries, targetFramework, "LibraryImport");
        Add(entries, targetFramework, "System.Runtime.InteropServices.LibraryImportAttribute");

        foreach (var method in new[]
                 {
                     "Volatile.Read",
                     "Volatile.Write",
                     "System.Threading.Volatile.Read",
                     "System.Threading.Volatile.Write",
                     "Interlocked.Exchange",
                     "Interlocked.CompareExchange",
                     "Interlocked.Increment",
                     "Interlocked.Decrement",
                     "Interlocked.Add",
                     "System.Threading.Interlocked.Exchange",
                     "System.Threading.Interlocked.CompareExchange",
                     "System.Threading.Interlocked.Increment",
                     "System.Threading.Interlocked.Decrement",
                     "System.Threading.Interlocked.Add",
                     "Thread.MemoryBarrier",
                     "System.Threading.Thread.MemoryBarrier"
                 })
        {
            Add(entries, targetFramework, method, new HotSummaryEffects { UsesConcurrencyPrimitive = true });
        }

        Add(entries, targetFramework, "ArrayPool.*.Rent", new HotSummaryEffects { UsesPool = true, RequiresWarmup = true });
        Add(entries, targetFramework, "ArrayPool.*.Return", new HotSummaryEffects { UsesPool = true });
        Add(entries, targetFramework, "MemoryPool.*.Rent", new HotSummaryEffects { UsesPool = true, RequiresWarmup = true });
        Add(entries, targetFramework, "IMemoryOwner.*.Dispose", new HotSummaryEffects { UsesPool = true, UsesResource = true });

        return entries;
    }

    private static void Add(
        List<HotSummaryEntry> entries,
        string targetFramework,
        string method,
        HotSummaryEffects? effects = null)
    {
        entries.Add(new HotSummaryEntry
        {
            SchemaVersion = 1,
            AssemblyIdentity = "System.Private.CoreLib",
            TargetFramework = targetFramework,
            Method = method,
            Source = HotSummarySource.BclPack,
            Effects = effects ?? new HotSummaryEffects(),
            BodyIdentity = "nsharp-bcl-pack-v1"
        });
    }
}
