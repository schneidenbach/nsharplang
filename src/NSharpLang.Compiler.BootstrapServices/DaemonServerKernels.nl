namespace NSharpLang.Cli.Daemon

import System
import System.IO
import NSharpLang.Cli.Commands

class DaemonServerKernels {
    static func ParsePosition(position: string, out line: int, out column: int): bool {
        line = 0
        column = 0

        colon := -1
        i := 0
        while i < position.Length {
            if position[i] == ':' {
                if colon >= 0 {
                    line = 0
                    column = 0
                    return false
                }

                colon = i
            }

            i = i + 1
        }

        if colon < 0 {
            return false
        }

        parsedAny := false
        parsedLine := 0
        if TryParseIntSegment(position, 0, colon, out parsedLine) {
            line = parsedLine
            parsedAny = true
        }

        parsedColumn := 0
        if TryParseIntSegment(position, colon + 1, position.Length, out parsedColumn) {
            column = parsedColumn
            parsedAny = true
        }

        return parsedAny
    }

    static func GetUnknownMethodMessage(method: string): string {
        return DaemonServerMessageKernels.GetUnknownMethodMessage(method)
    }

    static func GetFailedLoadProjectMessage(): string {
        return DaemonServerMessageKernels.GetFailedLoadProjectMessage()
    }

    static func GetEmptyBatchPayloadMessage(): string {
        return DaemonServerMessageKernels.GetEmptyBatchPayloadMessage()
    }

    static func GetFileParameterRequiredMessage(): string {
        return DaemonServerMessageKernels.GetFileParameterRequiredMessage()
    }

    static func GetFileAndPosParametersRequiredMessage(): string {
        return DaemonServerMessageKernels.GetFileAndPosParametersRequiredMessage()
    }

    static func GetDefinitionTargetRequiredMessage(): string {
        return DaemonServerMessageKernels.GetDefinitionTargetRequiredMessage()
    }

    static func GetFileAndPosRequiredMessage(): string {
        return DaemonServerMessageKernels.GetFileAndPosRequiredMessage()
    }

    static func GetNoSymbolAtPositionMessage(filePath: string, line: int, column: int): string {
        return "No symbol found at " + filePath + ":" + line.ToString() + ":" + column.ToString()
    }

    static func GetSemanticReferencesUnavailableMessage(): string {
        return DaemonServerMessageKernels.GetSemanticReferencesUnavailableMessage()
    }

    static func GetListeningMessage(socketPath: string, processId: int): string {
        return DaemonServerMessageKernels.GetListeningMessage(socketPath, processId.ToString())
    }

    static func GetProjectMessage(projectRoot: string): string {
        return DaemonServerMessageKernels.GetProjectMessage(projectRoot)
    }

    static func GetIdleTimeoutMessage(durationText: string): string {
        return DaemonServerMessageKernels.GetIdleTimeoutMessage(durationText)
    }

    static func GetIdleTimeoutShutdownMessage(durationText: string): string {
        return DaemonServerMessageKernels.GetIdleTimeoutShutdownMessage(durationText)
    }

    static func GetServerErrorMessage(messageText: string): string {
        return DaemonServerMessageKernels.GetServerErrorMessage(messageText)
    }

    static func GetClientErrorMessage(messageText: string): string {
        return DaemonServerMessageKernels.GetClientErrorMessage(messageText)
    }

    static func GetLoadingProjectMessage(): string {
        return DaemonServerMessageKernels.GetLoadingProjectMessage()
    }

    static func GetProjectLoadedMessage(elapsedMilliseconds: long, fileCount: int): string {
        return DaemonServerMessageKernels.GetProjectLoadedMessage(elapsedMilliseconds.ToString(), fileCount.ToString())
    }

    static func GetProjectLoadFailedTraceMessage(messageText: string): string {
        return DaemonServerMessageKernels.GetProjectLoadFailedTraceMessage(messageText)
    }

    static func GetFileWatcherStartedMessage(): string {
        return DaemonServerMessageKernels.GetFileWatcherStartedMessage()
    }

    static func GetFileWatcherFailedMessage(messageText: string): string {
        return DaemonServerMessageKernels.GetFileWatcherFailedMessage(messageText)
    }

    static func GetFileChangedMessage(fileName: string): string {
        return DaemonServerMessageKernels.GetFileChangedMessage(fileName)
    }

    static func GetChangedFileName(path: string): string {
        return Path.GetFileName(path) ?? ""
    }

    static func ShouldInvalidateForChangedPath(path: string): bool {
        if ContainsPathSegmentIgnoreCase(path, ".nlc") {
            return false
        }

        return WatchCommandKernels.ShouldTriggerForChangedPath(path)
    }

    static func GetShutdownCompleteMessage(): string {
        return DaemonServerMessageKernels.GetShutdownCompleteMessage()
    }

    static func GetMalformedRequestParamMessage(key: string, typeName: string, messageText: string): string {
        return DaemonServerMessageKernels.GetMalformedRequestParamMessage(key, typeName, messageText)
    }

    static func FormatDurationMilliseconds(totalMilliseconds: long): string {
        if totalMilliseconds >= 60000 {
            return FormatDurationUnit(totalMilliseconds, 60000, "m")
        }

        if totalMilliseconds >= 1000 {
            return FormatDurationUnit(totalMilliseconds, 1000, "s")
        }

        return totalMilliseconds.ToString() + "ms"
    }

    static func FormatDurationUnit(totalMilliseconds: long, unitMilliseconds: long, suffix: string): string {
        tenths := (totalMilliseconds * 10 + unitMilliseconds / 2) / unitMilliseconds
        whole := tenths / 10
        fraction := tenths - whole * 10
        if fraction == 0 {
            return whole.ToString() + suffix
        }

        return whole.ToString() + "." + fraction.ToString() + suffix
    }

    static func ContainsPathSegmentIgnoreCase(path: string, segment: string): bool {
        start := 0
        index := 0
        while index <= path.Length {
            if index == path.Length || path[index] == '/' || path[index] == '\\' {
                if PathSegmentEqualsIgnoreCase(path, start, index, segment) {
                    return true
                }

                start = index + 1
            }

            index = index + 1
        }

        return false
    }

    static func PathSegmentEqualsIgnoreCase(text: string, start: int, end: int, value: string): bool {
        if start < 0 || end < start || end > text.Length {
            return false
        }

        if end - start != value.Length {
            return false
        }

        return String.Compare(text, start, value, 0, value.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func TryParseIntSegment(text: string, start: int, end: int, out result: int): bool {
        result = 0

        while start < end && char.IsWhiteSpace(text[start]) {
            start = start + 1
        }

        while end > start && char.IsWhiteSpace(text[end - 1]) {
            end = end - 1
        }

        if start >= end {
            return false
        }

        negative := false
        if text[start] == '+' || text[start] == '-' {
            negative = text[start] == '-'
            start = start + 1
            if start >= end {
                return false
            }
        }

        parsedValue := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                return false
            }

            digit := ch - '0'
            if parsedValue > 214748364 {
                return false
            }

            if parsedValue == 214748364 {
                if negative {
                    if digit == 8 && index == end - 1 {
                        result = 0 - 2147483647 - 1
                        return true
                    }

                    return false
                }

                if digit > 7 {
                    return false
                }
            }

            parsedValue = parsedValue * 10 + digit
            index = index + 1
        }

        if negative {
            result = 0 - parsedValue
        } else {
            result = parsedValue
        }

        return true
    }
}
