namespace NSharpLang.Compiler

import System.Collections.Generic

public class AnalyzerExhaustivenessSelector {
    public static func SelectMissingEnumMembers<T>(
        members: IReadOnlyList<T>,
        coveredMembers: IEnumerable<string>): List<string> {
        result := new List<string>()

        i := 0
        while i < members.Count {
            name := AnalyzerExhaustivenessName(members[i])
            if !AnalyzerExhaustivenessContainsName(coveredMembers, name) {
                result.Add(name)
            }

            i = i + 1
        }

        return result
    }

    static func AnalyzerExhaustivenessContainsName(names: IEnumerable<string>, target: string): bool {
        for name in names {
            if name == target {
                return true
            }
        }

        return false
    }

    public static func SelectMissingUnionCasesFromFlags<T>(
        cases: IReadOnlyList<T>,
        coveredFlags: int[],
        partialFlags: int[],
        count: int,
        out missingCases: List<string>,
        out partialMissingCases: List<string>,
        out neverCoveredCases: List<string>) {
        missingCases = new List<string>()
        partialMissingCases = new List<string>()
        neverCoveredCases = new List<string>()

        i := 0
        while i < count {
            if coveredFlags[i] == 0 {
                name := AnalyzerExhaustivenessName(cases[i])
                missingCases.Add(name)

                if partialFlags[i] != 0 {
                    partialMissingCases.Add(name)
                } else {
                    neverCoveredCases.Add(name)
                }
            }

            i = i + 1
        }
    }

    static func AnalyzerExhaustivenessName(value: object): string {
        property := value.GetType().GetProperty("Name")
        if property != null {
            rawName := property.GetValue(value)
            name := AnalyzerExhaustivenessNameValue(rawName)
            if name.Length > 0 {
                return name
            }
        }

        field := value.GetType().GetField("Name")
        if field == null {
            return ""
        }

        rawFieldName := field.GetValue(value)
        return AnalyzerExhaustivenessNameValue(rawFieldName)
    }

    static func AnalyzerExhaustivenessNameValue(rawName: object): string {
        if rawName == null {
            return ""
        }

        name := rawName as string
        if name == null {
            return ""
        }

        return name
    }
}
