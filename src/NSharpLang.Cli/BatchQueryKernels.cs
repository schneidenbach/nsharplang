using System;
using System.Collections.Generic;

namespace NSharpLang.Cli;

internal static class BatchQueryKernels
{
    [ThreadStatic]
    private static DuplicateIdScratch? t_duplicateIdScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFindDuplicateRequestIds(
        IReadOnlyList<BatchQueryRequest> requests,
        out string[] duplicateIds)
    {
        duplicateIds = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var requestCount = requests.Count;
        if (requestCount == 0)
            return true;

        var scratch = t_duplicateIdScratch ??= new DuplicateIdScratch();
        scratch.EnsureCapacity(requestCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                if (!string.IsNullOrWhiteSpace(id))
                {
                    scratch.AddId(id);
                }
            }

            if (scratch.UniqueIdCount == 0)
                return true;

            scratch.BuildSortedRanks();
            for (var i = 0; i < requestCount; i++)
            {
                var id = requests[i].Id;
                scratch.IdRanks[i] = string.IsNullOrWhiteSpace(id)
                    ? 0
                    : scratch.GetIdRank(id);
            }

            var duplicateCount = bindings.DuplicateIdRanks(
                scratch.IdRanks,
                scratch.UniqueIdCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (duplicateCount < 0 ||
                duplicateCount > scratch.UniqueIdCount ||
                duplicateCount > scratch.ResultRanks.Length)
            {
                return false;
            }

            if (duplicateCount == 0)
                return true;

            duplicateIds = new string[duplicateCount];
            for (var i = 0; i < duplicateCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueIdCount)
                {
                    duplicateIds = Array.Empty<string>();
                    return false;
                }

                duplicateIds[i] = scratch.UniqueIds[rank - 1];
            }

            return true;
        }
        catch
        {
            duplicateIds = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static bool TryCountResultSuccesses(ulong[] okWords, int itemCount, out int successCount)
    {
        successCount = 0;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (itemCount < 0)
            return false;

        if (itemCount == 0)
            return true;

        if (okWords.Length == 0 || itemCount > (long)okWords.Length * 64)
            return false;

        try
        {
            var count = bindings.ResultPackedSuccessCount(okWords, itemCount);
            if (count < 0 || count > itemCount)
            {
                successCount = 0;
                return false;
            }

            successCount = count;
            return true;
        }
        catch
        {
            successCount = 0;
            return false;
        }
    }

    internal static string GetRequestsFileNotFoundMessage(string path)
        => RequiredBindings.RequestsFileNotFoundMessage(path);

    internal static string GetPayloadShapeMessage()
        => RequiredBindings.PayloadShapeMessage();

    internal static string GetRequestObjectRequiredMessage()
        => RequiredBindings.RequestObjectRequiredMessage();

    internal static string GetRequestDeserializeFailedMessage()
        => RequiredBindings.RequestDeserializeFailedMessage();

    internal static string GetDuplicateRequestIdsMessage(string duplicateIdsText)
        => RequiredBindings.DuplicateRequestIdsMessage(duplicateIdsText);

    internal static string GetUnsupportedCommandMessage(string command)
        => RequiredBindings.UnsupportedCommandMessage(command);

    internal static string GetOutlineFileRequiredMessage()
        => RequiredBindings.OutlineFileRequiredMessage();

    internal static string GetDocQueryRequiredMessage()
        => RequiredBindings.DocQueryRequiredMessage();

    internal static string GetFileAndPosRequiredMessage()
        => RequiredBindings.FileAndPosRequiredMessage();

    internal static string GetInvalidPositionMessage(string position)
        => RequiredBindings.InvalidPositionMessage(position);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliBatchDuplicateIdRanksInto>(
                programType,
                "CliBatchDuplicateIdRanksInto"),
            DogfoodKernelLoader.CreateDelegate<CliBatchResultPackedSuccessCount>(
                programType,
                "CliBatchResultPackedSuccessCount"),
            DogfoodKernelLoader.CreateDelegate<CliBatchRequestsFileNotFoundMessage>(
                programType,
                "CliBatchRequestsFileNotFoundMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchPayloadShapeMessage>(
                programType,
                "CliBatchPayloadShapeMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchRequestObjectRequiredMessage>(
                programType,
                "CliBatchRequestObjectRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchRequestDeserializeFailedMessage>(
                programType,
                "CliBatchRequestDeserializeFailedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchDuplicateRequestIdsMessage>(
                programType,
                "CliBatchDuplicateRequestIdsMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchUnsupportedCommandMessage>(
                programType,
                "CliBatchUnsupportedCommandMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchOutlineFileRequiredMessage>(
                programType,
                "CliBatchOutlineFileRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchDocQueryRequiredMessage>(
                programType,
                "CliBatchDocQueryRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchFileAndPosRequiredMessage>(
                programType,
                "CliBatchFileAndPosRequiredMessage"),
            DogfoodKernelLoader.CreateDelegate<CliBatchInvalidPositionMessage>(
                programType,
                "CliBatchInvalidPositionMessage")));

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# batch query kernels are unavailable.");

    private delegate int CliBatchDuplicateIdRanksInto(
        int[] idRanks,
        int uniqueIdCount,
        int[] countsByRank,
        int[] resultRanks);

    private delegate int CliBatchResultPackedSuccessCount(
        ulong[] okWords,
        int itemCount);

    private delegate string CliBatchRequestsFileNotFoundMessage(string path);
    private delegate string CliBatchPayloadShapeMessage();
    private delegate string CliBatchRequestObjectRequiredMessage();
    private delegate string CliBatchRequestDeserializeFailedMessage();
    private delegate string CliBatchDuplicateRequestIdsMessage(string duplicateIdsText);
    private delegate string CliBatchUnsupportedCommandMessage(string command);
    private delegate string CliBatchOutlineFileRequiredMessage();
    private delegate string CliBatchDocQueryRequiredMessage();
    private delegate string CliBatchFileAndPosRequiredMessage();
    private delegate string CliBatchInvalidPositionMessage(string position);

    private sealed record Bindings(
        CliBatchDuplicateIdRanksInto DuplicateIdRanks,
        CliBatchResultPackedSuccessCount ResultPackedSuccessCount,
        CliBatchRequestsFileNotFoundMessage RequestsFileNotFoundMessage,
        CliBatchPayloadShapeMessage PayloadShapeMessage,
        CliBatchRequestObjectRequiredMessage RequestObjectRequiredMessage,
        CliBatchRequestDeserializeFailedMessage RequestDeserializeFailedMessage,
        CliBatchDuplicateRequestIdsMessage DuplicateRequestIdsMessage,
        CliBatchUnsupportedCommandMessage UnsupportedCommandMessage,
        CliBatchOutlineFileRequiredMessage OutlineFileRequiredMessage,
        CliBatchDocQueryRequiredMessage DocQueryRequiredMessage,
        CliBatchFileAndPosRequiredMessage FileAndPosRequiredMessage,
        CliBatchInvalidPositionMessage InvalidPositionMessage);

    private sealed class DuplicateIdScratch
    {
        private readonly Dictionary<string, int> _idRanks = new(StringComparer.Ordinal);

        internal int[] CountsByRank = Array.Empty<int>();
        internal int[] IdRanks = Array.Empty<int>();
        internal int[] ResultRanks = Array.Empty<int>();
        internal string[] UniqueIds = Array.Empty<string>();
        internal int UniqueIdCount;

        internal void EnsureCapacity(int requestCount)
        {
            if (IdRanks.Length != requestCount)
            {
                IdRanks = new int[requestCount];
                ResultRanks = new int[requestCount];
                UniqueIds = new string[requestCount];
            }

            var rankCapacity = requestCount + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        internal void AddId(string id)
        {
            if (_idRanks.ContainsKey(id))
                return;

            _idRanks.Add(id, 0);
            UniqueIds[UniqueIdCount] = id;
            UniqueIdCount++;
        }

        internal void BuildSortedRanks()
        {
            Array.Sort(UniqueIds, 0, UniqueIdCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueIdCount; i++)
            {
                _idRanks[UniqueIds[i]] = i + 1;
            }
        }

        internal int GetIdRank(string id) => _idRanks[id];

        internal void ResetIds()
        {
            _idRanks.Clear();
            if (UniqueIdCount > 0)
            {
                Array.Clear(UniqueIds, 0, UniqueIdCount);
                UniqueIdCount = 0;
            }
        }
    }
}
