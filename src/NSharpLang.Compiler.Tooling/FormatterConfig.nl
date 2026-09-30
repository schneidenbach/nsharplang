namespace NSharpLang.Compiler

import System
import System.IO

class FormatterConfig {
    indentSizeValue: int
    indentSizeAssignedValue: bool
    useSpacesValue: bool
    useSpacesAssignedValue: bool
    maxLineLengthValue: int
    maxLineLengthAssignedValue: bool

    IndentSize: int {
        get {
            if !indentSizeAssignedValue {
                return 4
            }

            return indentSizeValue
        }
        set {
            indentSizeValue = value
            indentSizeAssignedValue = true
        }
    }

    UseSpaces: bool {
        get {
            if !useSpacesAssignedValue {
                return true
            }

            return useSpacesValue
        }
        set {
            useSpacesValue = value
            useSpacesAssignedValue = true
        }
    }

    MaxLineLength: int {
        get {
            if !maxLineLengthAssignedValue {
                return 100
            }

            return maxLineLengthValue
        }
        set {
            maxLineLengthValue = value
            maxLineLengthAssignedValue = true
        }
    }

    static func FromEditorConfig(directory: string): FormatterConfig {
        config := new FormatterConfig()
        editorConfigPath := FindEditorConfig(directory)

        if editorConfigPath == null {
            return config
        }

        editorConfigPathValue := editorConfigPath ?? ""
        lines := File.ReadAllLines(editorConfigPathValue)
        inNSharpSection := false

        for line in lines {
            trimmed := line.Trim()

            if trimmed.StartsWith("[*.nl]") {
                inNSharpSection = true
                continue
            }

            if trimmed.StartsWith("[") {
                inNSharpSection = false
            }

            if !inNSharpSection {
                continue
            }

            if trimmed.StartsWith("indent_size") {
                value := trimmed.Split("=")[1].Trim()
                config.IndentSize = ParseRequiredInt(value)
            }

            if trimmed.StartsWith("indent_style") {
                value := trimmed.Split("=")[1].Trim()
                config.UseSpaces = value == "space"
            }

            if trimmed.StartsWith("max_line_length") {
                value := trimmed.Split("=")[1].Trim()
                maxLen := FormatterConfigKernels.ParseInt(value)
                if maxLen.HasValue {
                    config.MaxLineLength = maxLen.Value
                }
            }
        }

        return config
    }

    static func ParseRequiredInt(value: string): int {
        parsed := FormatterConfigKernels.ParseInt(value)
        if !parsed.HasValue {
            throw new FormatException()
        }

        return parsed.Value
    }

    static func FindEditorConfig(dir: string): string? {
        current: string? = dir
        while current != null {
            currentValue := current ?? ""
            path := Path.Combine(currentValue, ".editorconfig")
            if File.Exists(path) {
                return path
            }

            current = Path.GetDirectoryName(currentValue)
        }

        return null
    }

    func GetIndentString(): string {
        if UseSpaces {
            return new string(' ', IndentSize)
        }

        return ((char)9).ToString()
    }
}
