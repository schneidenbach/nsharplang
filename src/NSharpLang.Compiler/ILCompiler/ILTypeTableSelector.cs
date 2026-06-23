using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

internal static class ILTypeTableSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static FirstDistinctTypeKeyScratch? t_firstDistinctTypeKeyScratch;
    [ThreadStatic]
    private static DeclaredTypeSuffixLookupScratch? t_declaredTypeSuffixLookupScratch;
    [ThreadStatic]
    private static DeclaredTypeNameCandidateScratch? t_declaredTypeNameCandidateScratch;
    [ThreadStatic]
    private static TypeCreationOrderScratch? t_typeCreationOrderScratch;

    internal static List<Type> DeduplicateFirstTypeKeys(
        IReadOnlyList<Type> types,
        Func<Type, string> getTypeKey)
    {
        var typeCount = types.Count;
        if (typeCount == 0)
            return [];

        var bindings = RequiredBindings;
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
                throw new InvalidOperationException("N# IL type table first-key deduplication kernel rejected the type table.");

            var result = new List<Type>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= typeCount)
                    throw new InvalidOperationException("N# IL type table first-key deduplication kernel rejected the type table.");

                result.Add(types[sourceIndex]);
            }

            return result;
        }
        finally
        {
            scratch.ResetKeys();
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
        finally
        {
            scratch.ClearValues();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<FirstDistinctRankIndicesInto>(
                programType,
                "FirstDistinctRankIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DeclaredTypeUniqueSuffixValueRank>(
                programType,
                "DeclaredTypeUniqueSuffixValueRank"),
            DogfoodKernelLoader.CreateDelegate<DeclaredTypeNameCandidateIndex>(
                programType,
                "DeclaredTypeNameCandidateIndex"),
            DogfoodKernelLoader.CreateDelegate<TypeCreationOrderIndicesInto>(
                programType,
                "TypeCreationOrderIndicesInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# IL type table selector kernels are unavailable.");

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
    private sealed record Bindings(
        FirstDistinctRankIndicesInto FirstDistinctRankIndices,
        DeclaredTypeUniqueSuffixValueRank DeclaredTypeUniqueSuffixValueRank,
        DeclaredTypeNameCandidateIndex DeclaredTypeNameCandidateIndex,
        TypeCreationOrderIndicesInto TypeCreationOrderIndices);

    private sealed class FirstDistinctTypeKeyScratch
    {
        private readonly Dictionary<string, int> _keyRanks = new(StringComparer.Ordinal);

        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();
        internal int[] TypeRanks = Array.Empty<int>();
        internal int UniqueKeyCount;

        internal void EnsureCapacity(int count)
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

        internal int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        internal void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class DeclaredTypeSuffixLookupScratch
    {
        private readonly Dictionary<Type, int> _valueRanks = new();
        private object? _source;
        private int _sourceCount;
        private int _tailHashWidth = -1;

        internal int Count;
        internal string[] Keys = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();
        internal int[] ValueRanks = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IReadOnlyDictionary<string, TType> types)
            where TType : Type
        {
            var count = types.Count;
            if (ReferenceEquals(_source, types) && _sourceCount == count && !CachedValuesContainUnbakedBuilder())
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

        // A cache hit keyed on (same dictionary instance, same count) is unsafe when the
        // dictionary's VALUES were replaced in place since we cached — e.g. ILCompiler's
        // FinalizeTopLevelEnumTypes swaps each EnumBuilder value for its baked Type while keeping
        // the same keys and count. If any cached value is still an unbaked reflection-emit builder,
        // force a reload so we don't hand back a stale EnumBuilder/TypeBuilder (M9).
        private bool CachedValuesContainUnbakedBuilder()
        {
            foreach (var value in _valueRanks.Keys)
            {
                if (value is System.Reflection.Emit.TypeBuilder or System.Reflection.Emit.EnumBuilder)
                {
                    return true;
                }
            }

            return false;
        }

        internal void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = GetTailHash(Keys[i], width);
            }

            _tailHashWidth = width;
        }

        internal static int GetTailHashWidth(string text) => Math.Min(4, text.Length);

        internal static int GetTailHash(string text, int width)
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

        internal int Count;
        internal int[] ImportedNamespaceFlags = Array.Empty<int>();
        internal string[] Names = Array.Empty<string>();
        internal int[] TailHashes = Array.Empty<int>();

        internal void Load(CompilationUnit compilationUnit)
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

        internal void RefreshTailHashes(int width)
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
                SoaRecordDeclaration soaRecordDeclaration => soaRecordDeclaration.Name,
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
                or SoaRecordDeclaration
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
        internal int Count;
        internal int[] DepthCounts = Array.Empty<int>();
        internal int[] DepthOffsets = Array.Empty<int>();
        internal int[] DotCounts = Array.Empty<int>();
        internal string[] Keys = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal Type[] Values = Array.Empty<Type>();

        internal bool Load<TType>(IEnumerable<TType> types, Func<TType, string> getTypeKey)
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

        internal void ClearValues()
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
