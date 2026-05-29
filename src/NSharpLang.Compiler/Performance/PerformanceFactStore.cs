using System.Collections.Generic;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Stores <see cref="PerformanceFacts"/> keyed by source position.
/// Mirrors the position-keyed dictionary pattern used by <see cref="SemanticModel"/>
/// and <see cref="BindingMap"/>, but keyed by <c>(File, Line, Column)</c> so facts
/// from multiple files can be aggregated.
///
/// This is a pure data store: it records, looks up, and merges facts. It is not
/// yet wired into the analyzer or IL emitter and changes no existing behavior.
/// See docs/design/performance-compiler-refactor.md "Performance Facts".
/// </summary>
public class PerformanceFactStore
{
    private readonly Dictionary<(string? File, int Line, int Column), PerformanceFacts> _facts = new();

    /// <summary>
    /// The number of positions with recorded facts.
    /// </summary>
    public int Count => _facts.Count;

    /// <summary>
    /// Record (last-write-wins) the performance facts for the construct at a source position.
    /// </summary>
    public void Record(string? file, int line, int column, PerformanceFacts facts)
    {
        _facts[(file, line, column)] = facts;
    }

    /// <summary>
    /// Try to find the performance facts recorded at a source position.
    /// Returns null if no facts were recorded there.
    /// </summary>
    public PerformanceFacts? Lookup(string? file, int line, int column)
    {
        return _facts.TryGetValue((file, line, column), out var facts) ? facts : null;
    }

    /// <summary>
    /// Get all recorded facts keyed by their source position.
    /// </summary>
    public IReadOnlyDictionary<(string? File, int Line, int Column), PerformanceFacts> All => _facts;

    /// <summary>
    /// Merge another store's facts into this one (for multi-file aggregation).
    /// On a position collision, the other store's facts win, matching the
    /// last-write-wins semantics of <see cref="Record"/> and
    /// <see cref="BindingMap.Merge"/>.
    /// </summary>
    public void Merge(PerformanceFactStore other)
    {
        foreach (var (key, facts) in other._facts)
        {
            _facts[key] = facts;
        }
    }
}
