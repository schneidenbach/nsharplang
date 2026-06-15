using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler.Performance;

internal static class NSharpPerformanceDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static AotRequirementScratch? t_aotRequirementScratch;

    [ThreadStatic]
    private static StructCopyScratch? t_structCopyScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

    internal static bool TryAllInstanceFieldsAreInitOnly(
        IReadOnlyList<StructCopyAnalysis.StructFieldDescriptor> fields,
        out bool allInitOnly)
    {
        allInitOnly = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fieldCount = fields.Count;
        var scratch = t_structCopyScratch ??= new StructCopyScratch();
        scratch.EnsureFieldCapacity(fieldCount);

        try
        {
            for (var i = 0; i < fieldCount; i++)
            {
                var field = fields[i];
                scratch.FieldReadonlyFlags[i] = field.IsStatic || field.IsInitOnly ? 1 : 0;
            }

            var result = bindings.StructCopyAllInstanceFieldsInitOnly(
                scratch.FieldReadonlyFlags,
                fieldCount);
            if (result is not 0 and not 1)
                return false;

            allInitOnly = result != 0;
            return true;
        }
        catch
        {
            allInitOnly = false;
            return false;
        }
    }

    internal static bool TryBuildAotRequirements(
        IReadOnlyList<AotBlocker> blockers,
        out AotRequirements requirements)
    {
        requirements = AotRequirements.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var blockerCount = blockers.Count;
        if (blockerCount == 0)
            return true;

        var scratch = t_aotRequirementScratch ??= new AotRequirementScratch();
        scratch.EnsureBlockerCapacity(blockerCount);

        try
        {
            scratch.Reset();
            for (var i = 0; i < blockerCount; i++)
            {
                var blocker = blockers[i];
                if (!blocker.IsOnPublicSurface || string.IsNullOrEmpty(blocker.EnclosingDeclaration))
                {
                    scratch.DeclarationRanks[i] = 0;
                    scratch.KindIds[i] = 0;
                    scratch.ConstructRanks[i] = 0;
                    continue;
                }

                scratch.DeclarationRanks[i] = scratch.AddDeclaration(blocker.EnclosingDeclaration);
                scratch.KindIds[i] = GetAotSafetyKindId(blocker.Kind);
                scratch.AddConstruct(blocker.Construct);
            }

            if (scratch.UniqueDeclarationCount == 0)
                return true;

            scratch.BuildConstructRanks();
            for (var i = 0; i < blockerCount; i++)
            {
                scratch.ConstructRanks[i] = scratch.DeclarationRanks[i] == 0
                    ? 0
                    : scratch.GetConstructRank(blockers[i].Construct);
            }

            scratch.EnsureGroupCapacity(scratch.UniqueDeclarationCount, scratch.UniqueConstructCount);
            var groupCount = bindings.AotRequirementGroups(
                scratch.DeclarationRanks,
                scratch.KindIds,
                scratch.ConstructRanks,
                scratch.UniqueDeclarationCount,
                scratch.UniqueConstructCount,
                scratch.DeclarationCounts,
                scratch.RequiresUnreferencedByRank,
                scratch.RequiresDynamicByRank,
                scratch.ConstructSeenByDeclaration,
                scratch.ResultDeclarationRanks,
                scratch.ResultRequiresUnreferenced,
                scratch.ResultRequiresDynamic,
                scratch.ResultConstructStarts,
                scratch.ResultConstructCounts,
                scratch.ResultConstructRanks);

            if (groupCount < 0 || groupCount > scratch.UniqueDeclarationCount)
                return false;

            var map = new Dictionary<string, AotRequirements.Annotation>(
                groupCount,
                StringComparer.Ordinal);
            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var declarationRank = scratch.ResultDeclarationRanks[groupIndex];
                if (declarationRank <= 0 || declarationRank > scratch.UniqueDeclarationCount)
                    return false;

                var constructStart = scratch.ResultConstructStarts[groupIndex];
                var constructCount = scratch.ResultConstructCounts[groupIndex];
                if (constructStart < 0
                    || constructCount < 0
                    || constructStart > scratch.ResultConstructRanks.Length - constructCount)
                {
                    return false;
                }

                var constructs = new string[constructCount];
                for (var offset = 0; offset < constructCount; offset++)
                {
                    var constructRank = scratch.ResultConstructRanks[constructStart + offset];
                    if (constructRank <= 0 || constructRank > scratch.UniqueConstructCount)
                        return false;

                    constructs[offset] = scratch.UniqueConstructs[constructRank - 1];
                }

                var declaration = scratch.UniqueDeclarations[declarationRank - 1];
                map[declaration] = new AotRequirements.Annotation(
                    scratch.ResultRequiresUnreferenced[groupIndex] != 0,
                    scratch.ResultRequiresDynamic[groupIndex] != 0,
                    AotRequirements.CreateAnnotationMessage(constructs));
            }

            requirements = AotRequirements.FromMap(map);
            return true;
        }
        catch
        {
            requirements = AotRequirements.Empty;
            return false;
        }
        finally
        {
            scratch.Reset();
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
                CreateDelegate<AotRequirementGroupsInto>(programType, "AotRequirementGroupsInto"),
                CreateDelegate<StructCopyAllInstanceFieldsInitOnly>(
                    programType,
                    "StructCopyAllInstanceFieldsInitOnly"));
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

    private static int GetAotSafetyKindId(AotSafetyKind kind) =>
        kind switch
        {
            AotSafetyKind.MetadataRequired => 1,
            AotSafetyKind.DynamicCodeRequired => 2,
            AotSafetyKind.ExpressionTreeRequired => 3,
            _ => 0
        };

    private delegate int AotRequirementGroupsInto(
        int[] declarationRanks,
        int[] kindIds,
        int[] constructRanks,
        int uniqueDeclarationCount,
        int uniqueConstructCount,
        int[] declarationCounts,
        int[] requiresUnreferencedByRank,
        int[] requiresDynamicByRank,
        int[] constructSeenByDeclaration,
        int[] resultDeclarationRanks,
        int[] resultRequiresUnreferenced,
        int[] resultRequiresDynamic,
        int[] resultConstructStarts,
        int[] resultConstructCounts,
        int[] resultConstructRanks);

    private delegate int StructCopyAllInstanceFieldsInitOnly(int[] fieldFlags, int count);

    private sealed record Bindings(
        AotRequirementGroupsInto AotRequirementGroups,
        StructCopyAllInstanceFieldsInitOnly StructCopyAllInstanceFieldsInitOnly);

    private sealed class StructCopyScratch
    {
        internal int[] FieldReadonlyFlags = Array.Empty<int>();

        internal void EnsureFieldCapacity(int fieldCount)
        {
            if (FieldReadonlyFlags.Length < fieldCount)
            {
                FieldReadonlyFlags = new int[fieldCount];
            }
        }
    }

    private sealed class AotRequirementScratch
    {
        private readonly Dictionary<string, int> _constructRanks = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _declarationRanks = new(StringComparer.Ordinal);

        internal int[] ConstructRanks = Array.Empty<int>();
        internal int[] ConstructSeenByDeclaration = Array.Empty<int>();
        internal int[] DeclarationCounts = Array.Empty<int>();
        internal int[] DeclarationRanks = Array.Empty<int>();
        internal int[] KindIds = Array.Empty<int>();
        internal int[] RequiresDynamicByRank = Array.Empty<int>();
        internal int[] RequiresUnreferencedByRank = Array.Empty<int>();
        internal int[] ResultConstructCounts = Array.Empty<int>();
        internal int[] ResultConstructRanks = Array.Empty<int>();
        internal int[] ResultConstructStarts = Array.Empty<int>();
        internal int[] ResultDeclarationRanks = Array.Empty<int>();
        internal int[] ResultRequiresDynamic = Array.Empty<int>();
        internal int[] ResultRequiresUnreferenced = Array.Empty<int>();
        internal string[] UniqueConstructs = Array.Empty<string>();
        internal string[] UniqueDeclarations = Array.Empty<string>();
        internal int UniqueConstructCount;
        internal int UniqueDeclarationCount;

        internal void EnsureBlockerCapacity(int blockerCount)
        {
            if (DeclarationRanks.Length != blockerCount)
            {
                DeclarationRanks = new int[blockerCount];
                KindIds = new int[blockerCount];
                ConstructRanks = new int[blockerCount];
                UniqueDeclarations = new string[blockerCount];
                UniqueConstructs = new string[blockerCount];
            }
        }

        internal void EnsureGroupCapacity(int declarationCount, int constructCount)
        {
            var rankCapacity = declarationCount + 1;
            if (DeclarationCounts.Length != rankCapacity)
            {
                DeclarationCounts = new int[rankCapacity];
                RequiresUnreferencedByRank = new int[rankCapacity];
                RequiresDynamicByRank = new int[rankCapacity];
            }

            var seenCapacity = (declarationCount + 1) * (constructCount + 1);
            if (ConstructSeenByDeclaration.Length != seenCapacity)
            {
                ConstructSeenByDeclaration = new int[seenCapacity];
            }

            if (ResultDeclarationRanks.Length != declarationCount)
            {
                ResultDeclarationRanks = new int[declarationCount];
                ResultRequiresUnreferenced = new int[declarationCount];
                ResultRequiresDynamic = new int[declarationCount];
                ResultConstructStarts = new int[declarationCount];
                ResultConstructCounts = new int[declarationCount];
            }

            var constructResultCapacity = declarationCount * 3;
            if (ResultConstructRanks.Length != constructResultCapacity)
            {
                ResultConstructRanks = new int[constructResultCapacity];
            }
        }

        internal int AddDeclaration(string declaration)
        {
            if (_declarationRanks.TryGetValue(declaration, out var rank))
                return rank;

            rank = UniqueDeclarationCount + 1;
            _declarationRanks.Add(declaration, rank);
            UniqueDeclarations[UniqueDeclarationCount] = declaration;
            UniqueDeclarationCount++;
            return rank;
        }

        internal void AddConstruct(string construct)
        {
            if (_constructRanks.ContainsKey(construct))
                return;

            _constructRanks.Add(construct, 0);
            UniqueConstructs[UniqueConstructCount] = construct;
            UniqueConstructCount++;
        }

        internal void BuildConstructRanks()
        {
            Array.Sort(UniqueConstructs, 0, UniqueConstructCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueConstructCount; i++)
            {
                _constructRanks[UniqueConstructs[i]] = i + 1;
            }
        }

        internal int GetConstructRank(string construct) => _constructRanks[construct];

        internal void Reset()
        {
            Array.Clear(UniqueDeclarations, 0, UniqueDeclarationCount);
            Array.Clear(UniqueConstructs, 0, UniqueConstructCount);
            _declarationRanks.Clear();
            _constructRanks.Clear();
            UniqueDeclarationCount = 0;
            UniqueConstructCount = 0;
        }
    }
}
