using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Thread-local trace for columnar backend declines. Records append from the deepest failing site outward as
/// false returns unwind; the first record is normally the most specific cause, and the last record can carry
/// enclosing-member context.
/// </summary>
internal static class ColumnarDeclineTrace
{
    [ThreadStatic]
    private static List<ColumnarDeclineReason>? t_records;

    internal static void Reset() => t_records = null;

    internal static void Record(string siteId, string message, int spanStart, int spanLength, string memberName)
    {
        (t_records ??= new List<ColumnarDeclineReason>()).Add(
            new ColumnarDeclineReason(siteId, message, spanStart, spanLength, memberName));
    }

    internal static IReadOnlyList<ColumnarDeclineReason> Snapshot()
        => t_records?.ToArray() ?? Array.Empty<ColumnarDeclineReason>();
}
