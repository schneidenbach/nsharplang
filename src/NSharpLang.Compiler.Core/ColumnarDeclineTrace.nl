namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// Thread-local trace for columnar backend declines. Records append from the deepest failing site
// outward as false returns unwind; the first record is normally the most specific cause, and the
// last record can carry enclosing-member context.
class ColumnarDeclineTrace {
    [System.ThreadStatic]
    private static Records: List<ColumnarDeclineReason>?

    [System.ThreadStatic]
    private static SourceFileId: int?

    static func Reset() {
        ColumnarDeclineTrace.Records = null
        ColumnarDeclineTrace.SourceFileId = null
    }

    static func SetSourceFileId(sourceFileId: int) {
        ColumnarDeclineTrace.SourceFileId = sourceFileId
    }

    static func ClearSourceFileId() {
        ColumnarDeclineTrace.SourceFileId = null
    }

    static func Record(siteId: string, message: string, spanStart: int, spanLength: int, memberName: string) {
        records := ColumnarDeclineTrace.Records
        if records == null {
            records = new List<ColumnarDeclineReason>()
            ColumnarDeclineTrace.Records = records
        }

        sourceFileId := ColumnarDeclineTrace.SourceFileId
        if sourceFileId.HasValue {
            records.Add(new ColumnarDeclineReason(siteId, message, spanStart, spanLength, memberName, sourceFileId.Value, true))
        } else {
            records.Add(new ColumnarDeclineReason(siteId, message, spanStart, spanLength, memberName))
        }
    }

    static func Snapshot(): IReadOnlyList<ColumnarDeclineReason> {
        records := ColumnarDeclineTrace.Records
        if records == null {
            return System.Array.Empty<ColumnarDeclineReason>()
        }
        return records.ToArray()
    }
}
