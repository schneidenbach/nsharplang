namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE IMPLEMENTORS — which concrete types claim a named interface, and the answer
// `query implementors` prints.
//
// The whole territory is here: the per-unit walk that tests every top-level declaration against the
// interface name, and the `ImplementorsResult` the walk accumulates. Nothing escapes this owner and
// nothing inside the service enters it — the C# `GetImplementors` survives only as the driver that
// turns a `ProjectSnapshot` into the two parallel lists below.
//
// THREE ARMS AND NOT FIFTEEN. Only a class, a struct and a record can implement an interface here;
// an interface declaration that EXTENDS the named interface is NOT an implementor and never was.
//
// A CLASS IS ASKED TWICE AND THE OTHER TWO ARE ASKED ONCE. `BaseClass` holds the first
// colon-separated type, which the parser cannot distinguish from an interface, so a class matches on
// EITHER its base type or any listed interface. A struct and a record have no base type to confuse,
// so only their `Interfaces` list is read.
//
// THE WALK IS TOP-LEVEL ONLY: a nested type that implements the interface is not reported, because
// the walk never descends into `Members`. That is the shipped answer, asserted so it cannot change
// silently.
class CodeIntelligenceImplementors {
    static func Build(units: List<CompilationUnit>, relativeFiles: List<string>, interfaceName: string): ImplementorsResult {
        results := new List<ImplementorResult>()

        unitIndex := 0
        while unitIndex < units.Count {
            Collect(units[unitIndex], interfaceName, relativeFiles[unitIndex], results)
            unitIndex = unitIndex + 1
        }

        return new ImplementorsResult(interfaceName, results)
    }

    static func Collect(unit: CompilationUnit, interfaceName: string, relativeFile: string, results: List<ImplementorResult>) {
        declarationIndex := 0
        while declarationIndex < unit.Declarations.Count {
            declaration := unit.Declarations[declarationIndex]

            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                if (classDeclaration.BaseClass != null && CodeIntelligenceDisplayText.InterfaceNameMatches(classDeclaration.BaseClass, interfaceName)) || MatchesAny(classDeclaration.Interfaces, interfaceName) {
                    results.Add(new ImplementorResult(classDeclaration.Name, "class", relativeFile, classDeclaration.Line, classDeclaration.Column))
                }
                declarationIndex = declarationIndex + 1
                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                if MatchesAny(structDeclaration.Interfaces, interfaceName) {
                    results.Add(new ImplementorResult(structDeclaration.Name, "struct", relativeFile, structDeclaration.Line, structDeclaration.Column))
                }
                declarationIndex = declarationIndex + 1
                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null {
                if MatchesAny(recordDeclaration.Interfaces, interfaceName) {
                    results.Add(new ImplementorResult(recordDeclaration.Name, "record", relativeFile, recordDeclaration.Line, recordDeclaration.Column))
                }
            }

            declarationIndex = declarationIndex + 1
        }
    }

    // A record STRUCT reports "record", not "struct": the arm is chosen by the declaration form and
    // never by `IsStruct`.
    static func MatchesAny(interfaces: List<TypeReference>?, interfaceName: string): bool {
        if interfaces == null {
            return false
        }

        index := 0
        while index < interfaces.Count {
            if CodeIntelligenceDisplayText.InterfaceNameMatches(interfaces[index], interfaceName) {
                return true
            }
            index = index + 1
        }

        return false
    }
}
