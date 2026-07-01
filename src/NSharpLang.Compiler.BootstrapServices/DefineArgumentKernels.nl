namespace NSharpLang.Cli

import System
import System.Collections.Generic

public class DefineArgumentExtraction {
    Defines: string[]
    RemainingArgs: string[]

    constructor(defines: string[], remainingArgs: string[]) {
        Defines = defines
        RemainingArgs = remainingArgs
    }
}

public class DefineArgumentKernels {
    public static func Extract(args: string[]): DefineArgumentExtraction {
        defines := new List<string>()
        remainingArgs := new List<string>()

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--define" || arg == "-d" {
                if i + 1 < args.Length {
                    AddDefineSymbols(defines, args[i + 1], 0)
                    i = i + 2
                    continue
                }

                i = i + 1
                continue
            }

            prefixLength := DefineEqualsPrefixLength(arg)
            if prefixLength > 0 {
                AddDefineSymbols(defines, arg, prefixLength)
                i = i + 1
                continue
            }

            remainingArgs.Add(arg)
            i = i + 1
        }

        return new DefineArgumentExtraction(defines.ToArray(), remainingArgs.ToArray())
    }

    static func DefineEqualsPrefixLength(arg: string): int {
        if arg.Length >= 9
            && arg[0] == '-'
            && arg[1] == '-'
            && arg[2] == 'd'
            && arg[3] == 'e'
            && arg[4] == 'f'
            && arg[5] == 'i'
            && arg[6] == 'n'
            && arg[7] == 'e'
            && arg[8] == '=' {
            return 9
        }

        if arg.Length >= 3
            && arg[0] == '-'
            && arg[1] == 'd'
            && arg[2] == '=' {
            return 3
        }

        return 0
    }

    static func AddDefineSymbols(defines: List<string>, raw: string, start: int) {
        segmentStart := start
        i := start
        while i <= raw.Length {
            if i == raw.Length || raw[i] == ',' || raw[i] == ';' {
                trimStart := segmentStart
                trimEnd := i
                while trimStart < trimEnd && Char.IsWhiteSpace(raw[trimStart]) {
                    trimStart = trimStart + 1
                }

                while trimEnd > trimStart && Char.IsWhiteSpace(raw[trimEnd - 1]) {
                    trimEnd = trimEnd - 1
                }

                if trimStart < trimEnd {
                    symbol := raw.Substring(trimStart, trimEnd - trimStart)
                    if !ContainsSymbol(defines, symbol) {
                        defines.Add(symbol)
                    }
                }

                segmentStart = i + 1
            }

            i = i + 1
        }
    }

    static func ContainsSymbol(defines: List<string>, symbol: string): bool {
        i := 0
        while i < defines.Count {
            if defines[i] == symbol {
                return true
            }

            i = i + 1
        }

        return false
    }
}
