namespace NSharpLang.Cli

public class PositionalArgumentKernels {
    public static func GetArgs(args: string[], optionsWithValues: string[]): string[] {
        count := CountArgs(args, optionsWithValues)
        result := new string[](count)

        resultIndex := 0
        i := 0
        while i < args.Length {
            arg := args[i]
            if IsOptionWithValue(arg, optionsWithValues) {
                i = i + 2
                continue
            }

            if IsValueLessFlag(arg) {
                i = i + 1
                continue
            }

            if IsPositional(arg) {
                result[resultIndex] = arg
                resultIndex = resultIndex + 1
            }

            i = i + 1
        }

        return result
    }

    static func CountArgs(args: string[], optionsWithValues: string[]): int {
        count := 0
        i := 0
        while i < args.Length {
            arg := args[i]
            if IsOptionWithValue(arg, optionsWithValues) {
                i = i + 2
                continue
            }

            if IsValueLessFlag(arg) {
                i = i + 1
                continue
            }

            if IsPositional(arg) {
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    static func IsOptionWithValue(arg: string, optionsWithValues: string[]): bool {
        i := 0
        while i < optionsWithValues.Length {
            if arg == optionsWithValues[i] {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func IsPositional(arg: string): bool {
        if arg.Length == 0 {
            return true
        }

        return arg[0] != '-'
    }

    static func IsValueLessFlag(arg: string): bool {
        if arg == "--check" {
            return true
        }

        if arg == "--verify-no-changes" {
            return true
        }

        if arg == "--diff" {
            return true
        }

        if arg == "--stdin" {
            return true
        }

        if arg == "--verbose" {
            return true
        }

        return false
    }
}
