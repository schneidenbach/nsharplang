namespace NSharpInteropLib

import System

// Tests ref/out parameter interop from C#
class StringUtils {
    static func TryParseInt(input: string, out result: int): bool {
        return Int32.TryParse(input, out result)
    }

    static func Swap(ref a: string, ref b: string) {
        temp := a
        a = b
        b = temp
    }

    static func Reverse(input: string): string {
        chars := input.ToCharArray()
        Array.Reverse(chars)
        return new string(chars)
    }

    static func Truncate(input: string, maxLength: int): string {
        if input.Length <= maxLength {
            return input
        }
        return input.Substring(0, maxLength) + "..."
    }
}
