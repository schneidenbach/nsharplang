namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

class LinterConfig {
    RuleSeverities: Dictionary<string, object>
    DisabledRules: List<string>

    constructor() {
        RuleSeverities = new Dictionary<string, object>()
        DisabledRules = new List<string>()
    }

    static func Default(): LinterConfig {
        config := new LinterConfig()
        descriptors := DiagnosticCatalog.LinterDescriptors

        for descriptorValue in descriptors {
            descriptor := descriptorValue as DiagnosticDescriptor
            if descriptor != null {
                config.RuleSeverities[descriptor.Code] = SeverityObject(descriptor.DefaultSeverity)
            }
        }

        return config
    }

    static func FromEditorConfig(directoryPath: string): LinterConfig {
        config := Default()

        current: string? = directoryPath
        while current != null {
            currentValue := current ?? ""
            editorConfigPath := Path.Combine(currentValue, ".editorconfig")

            if File.Exists(editorConfigPath) {
                ParseEditorConfig(editorConfigPath, config)

                if IsEditorConfigRoot(editorConfigPath) {
                    break
                }
            }

            parent := Path.GetDirectoryName(currentValue)
            if parent == null || parent == "" || parent == currentValue {
                current = null
            } else {
                current = parent
            }
        }

        return config
    }

    static func ParseEditorConfig(path: string, config: LinterConfig) {
        lines := File.ReadAllLines(path)
        inNSharpSection := false

        for line in lines {
            trimmed := line.Trim()

            if trimmed.StartsWith("[") && trimmed.EndsWith("]") {
                pattern := trimmed.Substring(1, trimmed.Length - 2)
                inNSharpSection = pattern.IndexOf("*.nl", StringComparison.Ordinal) >= 0 || pattern.IndexOf(".nl", StringComparison.Ordinal) >= 0
                continue
            }

            if inNSharpSection {
                equalsIndex := trimmed.IndexOf("=", StringComparison.Ordinal)
                if equalsIndex >= 0 {
                    key := trimmed.Substring(0, equalsIndex).Trim()
                    value := trimmed.Substring(equalsIndex + 1).Trim()

                    ParseRuleSeverity(key, value, config)
                }
            }
        }
    }

    static func ParseRuleSeverity(key: string, value: string, config: LinterConfig) {
        prefix := "dotnet_diagnostic."
        suffix := ".severity"

        if !key.StartsWith(prefix) || !key.EndsWith(suffix) {
            return
        }

        ruleCodeLength := key.Length - prefix.Length - suffix.Length
        if ruleCodeLength <= 0 {
            return
        }

        ruleCode := NormalizeRuleCode(key.Substring(prefix.Length, ruleCodeLength))
        severity := DiagnosticSeverity.Warning

        if TryParseSeverity(value, out severity) {
            config.RemoveDisabledRule(ruleCode)
            config.RuleSeverities[ruleCode] = SeverityObject(severity)
            return
        }

        if IsDisabledSeverity(value) {
            config.AddDisabledRule(ruleCode)
            removedSeverity: object = SeverityObject(DiagnosticSeverity.Warning)
            config.RuleSeverities.Remove(ruleCode, out removedSeverity)
        }
    }

    // THE FOLD IS INVARIANT, NOT THE MACHINE'S. `error`/`warning`/`info`/`suggestion` is a fixed
    // ASCII vocabulary, so a config file must parse the same on every machine: under a Turkish
    // culture `.ToLower()` sends `I` to the DOTLESS lowercase i, and `INFO` stopped being a severity.
    static func TryParseSeverity(value: string, out severity: DiagnosticSeverity): bool {
        severity = DiagnosticSeverity.Warning
        normalized := value.ToLowerInvariant()

        if normalized == "error" {
            severity = DiagnosticSeverity.Error
            return true
        }

        if normalized == "warning" {
            severity = DiagnosticSeverity.Warning
            return true
        }

        if normalized == "info" || normalized == "suggestion" {
            severity = DiagnosticSeverity.Info
            return true
        }

        return false
    }

    // Invariant for the same reason, and the miss is worse here: an unrecognised `SILENT` leaves the
    // rule ENABLED, so a culture-sensitive fold turns a disabled rule back on.
    static func IsDisabledSeverity(value: string): bool {
        normalized := value.ToLowerInvariant()
        return normalized == "none" || normalized == "silent"
    }

    // A rule code is an IDENTIFIER and is the dictionary KEY every severity lookup uses, so its
    // fold is invariant: a Turkish `.ToUpper()` would key `ni001` under a DOTTED capital I.
    static func NormalizeRuleCode(ruleCode: string): string {
        return ruleCode.ToUpperInvariant()
    }

    static func SeverityObject(severity: DiagnosticSeverity): object {
        return Enum.ToObject(typeof(DiagnosticSeverity), Convert.ToInt32(severity))
    }

    static func IsEditorConfigRoot(path: string): bool {
        lines := File.ReadAllLines(path)

        for line in lines {
            trimmed := line.Trim()
            if String.Compare(trimmed, "root=true", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(trimmed, "root = true", StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }
        }

        return false
    }

    func GetSeverity(ruleCode: string): DiagnosticSeverity {
        severity: object = SeverityObject(DiagnosticSeverity.Warning)
        normalizedRuleCode := NormalizeRuleCode(ruleCode)
        if RuleSeverities.TryGetValue(normalizedRuleCode, out severity) {
            return (DiagnosticSeverity)Convert.ToInt32(severity)
        }

        return DiagnosticCatalog.GetDefaultSeverity(normalizedRuleCode)
    }

    func IsRuleEnabled(ruleCode: string): bool {
        return !HasDisabledRule(ruleCode)
    }

    func AddDisabledRule(ruleCode: string) {
        if !HasDisabledRule(ruleCode) {
            DisabledRules.Add(NormalizeRuleCode(ruleCode))
        }
    }

    func RemoveDisabledRule(ruleCode: string) {
        normalizedRuleCode := NormalizeRuleCode(ruleCode)
        i := 0
        while i < DisabledRules.Count {
            if String.Compare(DisabledRules[i], normalizedRuleCode, StringComparison.OrdinalIgnoreCase) == 0 {
                DisabledRules.RemoveAt(i)
                return
            }

            i = i + 1
        }
    }

    func HasDisabledRule(ruleCode: string): bool {
        normalizedRuleCode := NormalizeRuleCode(ruleCode)
        i := 0
        while i < DisabledRules.Count {
            if String.Compare(DisabledRules[i], normalizedRuleCode, StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }
}
