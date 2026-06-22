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
    {
        if (TryGetMessage(bindings => bindings.RequestsFileNotFoundMessage(path), out var message))
            return message;

        return GetRequestsFileNotFoundMessageWithCSharp(path);
    }

    internal static string GetPayloadShapeMessage()
    {
        if (TryGetMessage(bindings => bindings.PayloadShapeMessage(), out var message))
            return message;

        return GetPayloadShapeMessageWithCSharp();
    }

    internal static string GetRequestObjectRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.RequestObjectRequiredMessage(), out var message))
            return message;

        return GetRequestObjectRequiredMessageWithCSharp();
    }

    internal static string GetRequestDeserializeFailedMessage()
    {
        if (TryGetMessage(bindings => bindings.RequestDeserializeFailedMessage(), out var message))
            return message;

        return GetRequestDeserializeFailedMessageWithCSharp();
    }

    internal static string GetDuplicateRequestIdsMessage(string duplicateIdsText)
    {
        if (TryGetMessage(bindings => bindings.DuplicateRequestIdsMessage(duplicateIdsText), out var message))
            return message;

        return GetDuplicateRequestIdsMessageWithCSharp(duplicateIdsText);
    }

    internal static string GetUnsupportedCommandMessage(string command)
    {
        if (TryGetMessage(bindings => bindings.UnsupportedCommandMessage(command), out var message))
            return message;

        return GetUnsupportedCommandMessageWithCSharp(command);
    }

    internal static string GetOutlineFileRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.OutlineFileRequiredMessage(), out var message))
            return message;

        return GetOutlineFileRequiredMessageWithCSharp();
    }

    internal static string GetDocQueryRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.DocQueryRequiredMessage(), out var message))
            return message;

        return GetDocQueryRequiredMessageWithCSharp();
    }

    internal static string GetFileAndPosRequiredMessage()
    {
        if (TryGetMessage(bindings => bindings.FileAndPosRequiredMessage(), out var message))
            return message;

        return GetFileAndPosRequiredMessageWithCSharp();
    }

    internal static string GetInvalidPositionMessage(string position)
    {
        if (TryGetMessage(bindings => bindings.InvalidPositionMessage(position), out var message))
            return message;

        return GetInvalidPositionMessageWithCSharp(position);
    }

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

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product batch query messages route through BatchQueryKernels.
    private static string GetRequestsFileNotFoundMessageWithCSharp(string path)
        => $"Requests file not found: {path}";

    private static string GetPayloadShapeMessageWithCSharp()
        => "Batch requests must be a JSON array or an object with a 'requests' array.";

    private static string GetRequestObjectRequiredMessageWithCSharp()
        => "Each batch request must be a JSON object.";

    private static string GetRequestDeserializeFailedMessageWithCSharp()
        => "Failed to deserialize a batch request.";

    private static string GetDuplicateRequestIdsMessageWithCSharp(string duplicateIdsText)
        => $"Duplicate batch request ids are not allowed: {duplicateIdsText}";

    private static string GetUnsupportedCommandMessageWithCSharp(string command)
        => $"Unsupported batch query command '{command}'.";

    private static string GetOutlineFileRequiredMessageWithCSharp()
        => "file is required for outline requests.";

    private static string GetDocQueryRequiredMessageWithCSharp()
        => "query is required for doc requests.";

    private static string GetFileAndPosRequiredMessageWithCSharp()
        => "file and pos are required.";

    private static string GetInvalidPositionMessageWithCSharp(string position)
        => $"Invalid position format '{position}'. Expected <line>:<col>.";

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
