namespace NSharpLang.Compiler.Columnar

public class ColumnarDeclineReason {
    siteIdValue: string
    messageValue: string
    spanStartValue: int
    spanLengthValue: int
    memberNameValue: string

    SiteId: string => siteIdValue
    Message: string => messageValue
    SpanStart: int => spanStartValue
    SpanLength: int => spanLengthValue
    MemberName: string => memberNameValue

    constructor(siteId: string, message: string, spanStart: int, spanLength: int, memberName: string) {
        siteIdValue = siteId
        messageValue = message
        spanStartValue = spanStart
        spanLengthValue = spanLength
        memberNameValue = memberName
    }
}

public class ColumnarDeclineReasonFacts {
    public static func MapMergedOffsetFileIndex(fileLengths: int[], separatorLength: int, offset: int): int {
        if offset < 0 {
            return -1
        }

        start := 0
        index := 0
        while index < fileLengths.Length {
            length := fileLengths[index]
            end := start + length
            if offset >= start && offset < end {
                return index
            }

            start = end + separatorLength
            index = index + 1
        }

        return -1
    }

    public static func MapMergedOffsetLocalOffset(fileLengths: int[], separatorLength: int, offset: int): int {
        fileIndex := MapMergedOffsetFileIndex(fileLengths, separatorLength, offset)
        if fileIndex < 0 {
            return -1
        }

        start := 0
        index := 0
        while index < fileIndex {
            start = start + fileLengths[index] + separatorLength
            index = index + 1
        }

        return offset - start
    }

    public static func LineFromOffset(source: string, offset: int): int {
        if offset < 0 || offset > source.Length {
            return 0
        }

        line := 1
        position := 0
        while position < offset {
            ch := source[position]
            if ch == '\r' {
                line = line + 1
                if position + 1 < offset && position + 1 < source.Length && source[position + 1] == '\n' {
                    position = position + 2
                    continue
                }
            } else {
                if ch == '\n' {
                    line = line + 1
                }
            }

            position = position + 1
        }

        return line
    }

    public static func ColumnFromOffset(source: string, offset: int): int {
        if offset < 0 || offset > source.Length {
            return 0
        }

        lineStart := 0
        position := 0
        while position < offset {
            ch := source[position]
            if ch == '\r' {
                if position + 1 < offset && position + 1 < source.Length && source[position + 1] == '\n' {
                    position = position + 2
                } else {
                    position = position + 1
                }

                lineStart = position
                continue
            }

            if ch == '\n' {
                position = position + 1
                lineStart = position
                continue
            }

            position = position + 1
        }

        return offset - lineStart + 1
    }

    public static func FormatDetail(reason: ColumnarDeclineReason, fileName: string? = null, line: int = 0, column: int = 0): string {
        detail := "Declined at " + reason.SiteId + ": " + reason.Message
        if reason.MemberName.Length > 0 {
            detail = detail + " in '" + reason.MemberName + "'"
        }

        if fileName != null && fileName.Length > 0 && line > 0 && column > 0 {
            detail = detail + " (" + fileName + ":" + line.ToString() + ":" + column.ToString() + ")"
        }

        return detail + "."
    }

    public static func FormatTraceLine(reason: ColumnarDeclineReason, fileName: string? = null, line: int = 0, column: int = 0): string {
        lineText := "decline site=" + reason.SiteId
            + " message=\"" + reason.Message + "\""
            + " span=" + reason.SpanStart.ToString() + ":" + reason.SpanLength.ToString()

        if reason.MemberName.Length > 0 {
            lineText = lineText + " member=\"" + reason.MemberName + "\""
        }

        if fileName != null && fileName.Length > 0 && line > 0 && column > 0 {
            lineText = lineText + " location=" + fileName + ":" + line.ToString() + ":" + column.ToString()
        }

        return lineText
    }
}
