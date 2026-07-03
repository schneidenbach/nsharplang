namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast
import System.Collections.Generic

public class AnalyzerExhaustivenessSelector {
    public static func SelectMissingEnumMembers(
        members: IEnumerable<EnumMemberInfo>,
        coveredMembers: IEnumerable<string>): List<string> {
        result := new List<string>()

        foreach member in members {
            name := member.Name
            if !AnalyzerExhaustivenessContainsName(coveredMembers, name) {
                result.Add(name)
            }
        }

        return result
    }

    static func AnalyzerExhaustivenessContainsName(names: IEnumerable<string>, target: string): bool {
        foreach name in names {
            if name == target {
                return true
            }
        }

        return false
    }

    public static func SelectMissingUnionCasesFromFlags(
        cases: IReadOnlyList<UnionCase>,
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
                name := cases[i].Name
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
}
