namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

public class CompilationBackendSelectionKernels {
    public static func Validate(backendOption: string?, config: ProjectConfig?) {
        selectedValue := GetSelectedBackendValue(backendOption, config)
        projectBackend := ""
        if config != null {
            projectBackend = config.Backend
        }

        statusCode := EffectiveBackendKind(backendOption ?? "", projectBackend)
        if statusCode == 1 {
            return
        }

        if statusCode == 0 {
            throw new InvalidOperationException("Invalid backend: '" + (selectedValue ?? "") + "'. Must be 'il'.")
        }

        throw new InvalidOperationException("N# compilation backend selection kernel rejected the backend configuration.")
    }

    static func GetSelectedBackendValue(backendOption: string?, config: ProjectConfig?): string? {
        if !string.IsNullOrWhiteSpace(backendOption ?? "") {
            return backendOption
        }

        if config != null {
            return config.Backend
        }

        return null
    }

    static func EffectiveBackendKind(backendOption: string, projectBackend: string): int {
        selected := backendOption
        if selected.Trim().Length == 0 {
            selected = projectBackend
        }

        normalized := selected.Trim()
        if normalized.Length == 0 {
            return 1
        }

        if String.Compare(normalized, "il", StringComparison.OrdinalIgnoreCase) == 0 {
            return 1
        }

        return 0
    }
}
