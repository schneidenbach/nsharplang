using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler.SourceGenerators;

public sealed class GeneratedSymbolIndex
{
    public static GeneratedSymbolIndex Empty { get; } = new(Array.Empty<GeneratedTypeSymbols>());

    private readonly Dictionary<string, GeneratedTypeSymbols> _typesByFullName;

    public GeneratedSymbolIndex(IEnumerable<GeneratedTypeSymbols> types)
    {
        _typesByFullName = types
            .GroupBy(type => type.FullName, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.First(),
                StringComparer.Ordinal);
    }

    public bool IsEmpty => _typesByFullName.Count == 0;

    public bool TryGetType(string fullName, out GeneratedTypeSymbols type)
        => _typesByFullName.TryGetValue(fullName, out type!);

    public IReadOnlyList<string> GetMemberNames(string fullName, bool includeStaticMembers)
    {
        return _typesByFullName.TryGetValue(fullName, out var type)
            ? type.Members
                .Where(member => includeStaticMembers || !member.IsStatic)
                .Select(member => member.Name)
                .Distinct(StringComparer.Ordinal)
                .ToArray()
            : Array.Empty<string>();
    }

    public bool TryResolveMember(
        string fullName,
        string memberName,
        bool includeStaticMembers,
        out GeneratedMemberSymbol member)
    {
        member = null!;
        if (!_typesByFullName.TryGetValue(fullName, out var type))
        {
            return false;
        }

        member = type.Members.FirstOrDefault(candidate =>
            string.Equals(candidate.Name, memberName, StringComparison.Ordinal)
            && (includeStaticMembers || !candidate.IsStatic))!;
        return member != null;
    }
}

public sealed record GeneratedTypeSymbols(
    string FullName,
    string Name,
    IReadOnlyList<GeneratedMemberSymbol> Members);

public sealed record GeneratedMemberSymbol(
    string Name,
    GeneratedMemberKind Kind,
    TypeInfo Type,
    bool IsStatic,
    string? DeclaringTypeFullName = null);

public enum GeneratedMemberKind
{
    Property,
    Field,
    Method,
    NestedType
}
