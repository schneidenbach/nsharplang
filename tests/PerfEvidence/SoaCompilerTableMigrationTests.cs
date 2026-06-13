using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

[Collection("ProcessState")]
public class SoaCompilerTableMigrationTests
{
    private const string ExperimentalSoaEnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";
    private const string Source = """
        soa record OverloadCandidateTable {
            valid: int
            score: int
            isGeneric: int
            usesParams: int
            defaultsUsed: int
            paramTypeOffset: int
            paramTypeCount: int
        }

        func selectCandidateTable(candidates: OverloadCandidateTable, paramTypeIds: int[], argTypeIds: int[], argCount: int): int {
            if argCount < 0 || argCount > argTypeIds.Length {
                return -2
            }

            bestIndex := -1
            bestScore := -1
            bestIsGeneric := 1
            bestUsesParams := 1
            bestDefaultsUsed := 2147483647

            i := 0
            while i < candidates.length {
                candidateValid := candidates[i].valid != 0
                if candidateValid {
                    offset := candidates[i].paramTypeOffset
                    paramCount := candidates[i].paramTypeCount
                    if offset < 0 || paramCount < 0 || offset + paramCount > paramTypeIds.Length {
                        candidateValid = false
                    }
                }

                if candidateValid {
                    score := candidates[i].score
                    isGeneric := candidates[i].isGeneric
                    usesParams := candidates[i].usesParams
                    defaults := candidates[i].defaultsUsed

                    takeCandidate := false
                    if bestIndex < 0 {
                        takeCandidate = true
                    } else if score > bestScore {
                        takeCandidate = true
                    } else if score == bestScore && bestIsGeneric != 0 && isGeneric == 0 {
                        takeCandidate = true
                    } else if score == bestScore
                        && bestIsGeneric == isGeneric
                        && bestUsesParams != 0
                        && usesParams == 0 {
                        takeCandidate = true
                    } else if score == bestScore
                        && bestIsGeneric == isGeneric
                        && bestUsesParams == usesParams
                        && defaults < bestDefaultsUsed {
                        takeCandidate = true
                    }

                    if takeCandidate {
                        bestIndex = i
                        bestScore = score
                        bestIsGeneric = isGeneric
                        bestUsesParams = usesParams
                        bestDefaultsUsed = defaults
                    }
                }

                i = i + 1
            }

            return bestIndex
        }

        func selectCandidateTableFromColumns(
            valid: int[],
            scores: int[],
            isGeneric: int[],
            usesParams: int[],
            defaultsUsed: int[],
            paramTypeOffsets: int[],
            paramTypeCounts: int[],
            paramTypeIds: int[],
            argTypeIds: int[],
            argCount: int,
            count: int): int {
            if count < 0
                || count > valid.Length
                || count > scores.Length
                || count > isGeneric.Length
                || count > usesParams.Length
                || count > defaultsUsed.Length
                || count > paramTypeOffsets.Length
                || count > paramTypeCounts.Length {
                return -2
            }

            candidates := OverloadCandidateTable.wrap(
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                count)
            return selectCandidateTable(candidates, paramTypeIds, argTypeIds, argCount)
        }
        """;

    [Fact]
    public void OverloadCandidateTable_MatchesParallelColumnBaseline()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        ILShapeInspector.Compile(Source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "selectCandidateTableFromColumns");

            var valid = new[] { 0, 1, 1, 1, 1 };
            var scores = new[] { 0, 10, 10, 12, 12 };
            var isGeneric = new[] { 0, 1, 0, 1, 0 };
            var usesParams = new[] { 0, 1, 1, 0, 0 };
            var defaultsUsed = new[] { 0, 3, 4, 2, 1 };
            var paramTypeOffsets = new[] { 0, 0, 2, 4, 6 };
            var paramTypeCounts = new[] { 0, 2, 2, 2, 2 };
            var paramTypeIds = new[] { 11, 12, 21, 22, 31, 32, 41, 42 };
            var argTypeIds = new[] { 11, 12 };

            AssertSelectMatchesBaseline(
                method,
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                paramTypeIds,
                argTypeIds,
                argCount: 2,
                count: valid.Length);

            paramTypeOffsets[4] = paramTypeIds.Length;
            AssertSelectMatchesBaseline(
                method,
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                paramTypeIds,
                argTypeIds,
                argCount: 2,
                count: valid.Length);

            AssertSelectMatchesBaseline(
                method,
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                paramTypeIds,
                argTypeIds,
                argCount: -1,
                count: valid.Length);

            AssertSelectMatchesBaseline(
                method,
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                paramTypeIds,
                argTypeIds,
                argCount: 2,
                count: valid.Length + 1);

            return 0;
        });
    }

    [Fact]
    public void OverloadCandidateTable_RowProjectionStaysColumnar()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        ILShapeInspector.Compile(Source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "selectCandidateTable");

            ILShapeInspector.AssertNoBoxing(method);
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountDelegateConstructions(method));
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Call));
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Ldfld) >= 8,
                "The table loop should project SoA row fields through direct column-field loads.");
            Assert.True(
                CountArrayElementLoads(method) >= 7,
                "The table loop should read candidate data through direct array element loads.");
            Assert.Equal(0, CountArrayElementStores(method));

            return 0;
        });
    }

    private static void AssertSelectMatchesBaseline(
        MethodInfo method,
        int[] valid,
        int[] scores,
        int[] isGeneric,
        int[] usesParams,
        int[] defaultsUsed,
        int[] paramTypeOffsets,
        int[] paramTypeCounts,
        int[] paramTypeIds,
        int[] argTypeIds,
        int argCount,
        int count)
    {
        var expected = SelectParallelBaseline(
            valid,
            scores,
            isGeneric,
            usesParams,
            defaultsUsed,
            paramTypeOffsets,
            paramTypeCounts,
            paramTypeIds,
            argTypeIds,
            argCount,
            count);
        var actual = method.Invoke(
            null,
            new object[]
            {
                valid,
                scores,
                isGeneric,
                usesParams,
                defaultsUsed,
                paramTypeOffsets,
                paramTypeCounts,
                paramTypeIds,
                argTypeIds,
                argCount,
                count
            });

        Assert.Equal(expected, Assert.IsType<int>(actual));
    }

    private static int SelectParallelBaseline(
        int[] valid,
        int[] scores,
        int[] isGeneric,
        int[] usesParams,
        int[] defaultsUsed,
        int[] paramTypeOffsets,
        int[] paramTypeCounts,
        int[] paramTypeIds,
        int[] argTypeIds,
        int argCount,
        int count)
    {
        if (count < 0
            || count > valid.Length
            || count > scores.Length
            || count > isGeneric.Length
            || count > usesParams.Length
            || count > defaultsUsed.Length
            || count > paramTypeOffsets.Length
            || count > paramTypeCounts.Length
            || argCount < 0
            || argCount > argTypeIds.Length)
        {
            return -2;
        }

        var bestIndex = -1;
        var bestScore = -1;
        var bestIsGeneric = 1;
        var bestUsesParams = 1;
        var bestDefaultsUsed = int.MaxValue;

        for (var i = 0; i < count; i++)
        {
            var candidateValid = valid[i] != 0;
            if (candidateValid)
            {
                var offset = paramTypeOffsets[i];
                var paramCount = paramTypeCounts[i];
                if (offset < 0 || paramCount < 0 || offset + paramCount > paramTypeIds.Length)
                {
                    candidateValid = false;
                }
            }

            if (!candidateValid)
            {
                continue;
            }

            var score = scores[i];
            var candidateIsGeneric = isGeneric[i];
            var candidateUsesParams = usesParams[i];
            var defaults = defaultsUsed[i];

            var takeCandidate = false;
            if (bestIndex < 0)
            {
                takeCandidate = true;
            }
            else if (score > bestScore)
            {
                takeCandidate = true;
            }
            else if (score == bestScore && bestIsGeneric != 0 && candidateIsGeneric == 0)
            {
                takeCandidate = true;
            }
            else if (score == bestScore
                && bestIsGeneric == candidateIsGeneric
                && bestUsesParams != 0
                && candidateUsesParams == 0)
            {
                takeCandidate = true;
            }
            else if (score == bestScore
                && bestIsGeneric == candidateIsGeneric
                && bestUsesParams == candidateUsesParams
                && defaults < bestDefaultsUsed)
            {
                takeCandidate = true;
            }

            if (takeCandidate)
            {
                bestIndex = i;
                bestScore = score;
                bestIsGeneric = candidateIsGeneric;
                bestUsesParams = candidateUsesParams;
                bestDefaultsUsed = defaults;
            }
        }

        return bestIndex;
    }

    private static int CountArrayElementLoads(MethodBase method)
    {
        return CountOpcodes(
            method,
            OpCodes.Ldelem,
            OpCodes.Ldelem_I1,
            OpCodes.Ldelem_I2,
            OpCodes.Ldelem_I4,
            OpCodes.Ldelem_I8,
            OpCodes.Ldelem_R4,
            OpCodes.Ldelem_R8,
            OpCodes.Ldelem_Ref,
            OpCodes.Ldelem_U1,
            OpCodes.Ldelem_U2,
            OpCodes.Ldelem_U4,
            OpCodes.Ldelema);
    }

    private static int CountArrayElementStores(MethodBase method)
    {
        return CountOpcodes(
            method,
            OpCodes.Stelem,
            OpCodes.Stelem_I,
            OpCodes.Stelem_I1,
            OpCodes.Stelem_I2,
            OpCodes.Stelem_I4,
            OpCodes.Stelem_I8,
            OpCodes.Stelem_R4,
            OpCodes.Stelem_R8,
            OpCodes.Stelem_Ref);
    }

    private static int CountOpcodes(MethodBase method, params OpCode[] opCodes)
    {
        return ILShapeInspector.Decode(method).Count(instruction => opCodes.Contains(instruction.OpCode));
    }

    private static IDisposable SetEnvironmentVariable(string name, string? value)
    {
        var previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
        return new RestoreEnvironmentVariable(name, previousValue);
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }
}
