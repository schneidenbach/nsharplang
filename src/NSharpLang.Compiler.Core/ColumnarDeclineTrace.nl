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

    // THE MEMBER WHOSE BODY IS BEING EMITTED RIGHT NOW, for the one record that cannot name a member
    // for itself. A decline is written at the site that refused and carries the member from there; an
    // emitter FAULT is written by the driver after the walk has already unwound, with nothing left of
    // where it happened. The member scope is opened at the same eleven places the source file is,
    // because they are the same scope: one member's body, on the emission thread.
    [System.ThreadStatic]
    private static MemberName: string?

    static func Reset() {
        ColumnarDeclineTrace.Records = null
        ColumnarDeclineTrace.SourceFileId = null
        ColumnarDeclineTrace.MemberName = null
    }

    static func SetSourceFileId(sourceFileId: int) {
        ColumnarDeclineTrace.SourceFileId = sourceFileId
        ColumnarDeclineTrace.MemberName = null
    }

    static func SetSourceFileId(sourceFileId: int, memberName: string) {
        ColumnarDeclineTrace.SourceFileId = sourceFileId
        if memberName.Length == 0 {
            ColumnarDeclineTrace.MemberName = null
        } else {
            ColumnarDeclineTrace.MemberName = memberName
        }
    }

    static func ClearSourceFileId() {
        ColumnarDeclineTrace.SourceFileId = null
        ColumnarDeclineTrace.MemberName = null
    }

    // THE MEMBER THE EMISSION THREAD WAS INSIDE, or the empty string when it was between members.
    static func CurrentMemberName(): string {
        memberName := ColumnarDeclineTrace.MemberName
        if memberName == null {
            return ""
        }
        return memberName
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
