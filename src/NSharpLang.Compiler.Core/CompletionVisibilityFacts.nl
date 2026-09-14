namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHICH DECLARED MEMBERS A COMPLETION IS ALLOWED TO OFFER, SAID IN THE ANALYZER'S OWN WORDS.
//
// A completion list that offers a member the analyzer will refuse is worse than a short list: the
// developer accepts the item, the editor writes it, and the next diagnostic pass underlines it.
// That is exactly what `service.` did — it offered `summaries`, a camelCase field on a class in
// another package, and `nlc check` answered NL308 the moment it was written.
//
// THE RULE IS THE ONE `AnalyzerMemberAccess.ValidateDeclaredMemberVisibility` ENFORCES, AND IT IS
// PACKAGE-SCOPED, NOT FILE-SCOPED. N# spells visibility the way Go does: PascalCase (or a written
// `public`) exports, camelCase does not — and an unexported member is still readable from ANY file
// in the SAME namespace. `IsCrossPackageFile` compares the declaring file's namespace against the
// current file's namespace and reports only when they differ, so a filter that dropped every
// camelCase member would hide members that compile, run and are meant to be used. Measured, not
// assumed: `service.summaries` from a file with no `namespace` is NL308, and the SAME line in a
// file that opens `namespace WeatherDemo.Services` checks clean.
//
// SO THE PREDICATE IS TWO WORDS WIDE — exported, or same package — and everything else in this
// file exists to answer the second word: which namespace declared the receiver's type.
//
// THE ANSWER FAILS OPEN, DELIBERATELY. When the declaring namespace cannot be established — no
// project units were handed over, the type is not source-declared, or two files declare the same
// simple name in different namespaces and nothing distinguishes them — the filter offers
// everything. A completion that hides a legal member is a defect the developer cannot see past; a
// completion that offers an illegal one is a defect the very next diagnostic explains. Between two
// imperfect answers this picks the one the compiler will correct.
class CompletionVisibilityFacts {

    // The namespace a file's declarations live in. The GLOBAL namespace answers `""` rather than
    // null, so that a comparison never has to reason about the difference between "no namespace"
    // and "namespace not known" — null is reserved for the second, and only this file's search
    // produces it.
    static func UnitNamespaceName(unit: CompilationUnit?): string {
        if unit == null {
            return ""
        }

        namespaceDeclaration := unit.Namespace
        if namespaceDeclaration == null {
            return ""
        }

        return namespaceDeclaration.Name
    }

    // The last segment of a dotted name. A completion's receiver type text is sometimes qualified
    // and sometimes not, and a declaration is only ever written under its simple name.
    static func SimpleTypeName(typeName: string): string {
        separator := typeName.LastIndexOf(".", StringComparison.Ordinal)
        if separator < 0 {
            return typeName
        }

        return typeName.Substring(separator + 1)
    }

    // The written name of a MEMBER-OWNING type declaration, or null for anything else. The four
    // families are exactly the four `CompletionDeclarationFacts.DeclaredMembersOfType` answers
    // members for; a declaration this walk does not recognise cannot be the receiver's type, so it
    // contributes no namespace rather than a wrong one.
    static func TypeDeclarationName(declaration: Declaration?): string? {
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return classDeclaration.Name
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return structDeclaration.Name
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return recordDeclaration.Name
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return interfaceDeclaration.Name
        }

        return null
    }

    // The source position a `TypeInfo` was declared at, or `false` when the shape carries none.
    // POSITION IS THE TIE-BREAKER AND THAT IS ITS WHOLE PURPOSE: two files may declare `Widget`,
    // and the receiver resolved to exactly one of them. A name match alone cannot tell them apart;
    // a line and column can, because no two declarations share one.
    static func TryGetDeclaredTypePosition(typeInfo: TypeInfo, out line: int, out column: int): bool {
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            line = classType.Line
            column = classType.Column
            return true
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            line = structType.Line
            column = structType.Column
            return true
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            line = recordType.Line
            column = recordType.Column
            return true
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            line = interfaceType.Line
            column = interfaceType.Column
            return true
        }

        line = 0
        column = 0
        return false
    }

    // WHICH NAMESPACE DECLARED THIS TYPE, or null when the walk cannot say.
    //
    // An EXACT positional match wins outright and returns immediately. Failing that, a single
    // name match answers; two name matches that agree on a namespace answer too, because then the
    // ambiguity does not change the verdict. Two that DISAGREE answer null, which the caller reads
    // as "offer everything".
    static func DeclaringNamespaceOfType(typeName: string, line: int, column: int, compilationUnits: IEnumerable<CompilationUnit>): string? {
        simpleName := SimpleTypeName(typeName)
        found: string? = null
        ambiguous := false

        for unit in compilationUnits {
            if unit != null {
                declarations := unit.Declarations
                index := 0
                while index < declarations.Count {
                    declaredName := TypeDeclarationName(declarations[index])
                    if declaredName != null && declaredName == simpleName {
                        unitNamespace := UnitNamespaceName(unit)
                        if line > 0 && declarations[index].Line == line && declarations[index].Column == column {
                            return unitNamespace
                        }

                        if found == null {
                            found = unitNamespace
                        } else if (found ?? "") != unitNamespace {
                            ambiguous = true
                        }
                    }

                    index = index + 1
                }
            }
        }

        if ambiguous {
            return null
        }

        return found
    }

    // THE DECLARED-ACCESSIBILITY HALF, which is the OTHER rule NL308 reports. A member kept in by a
    // written `private` or `protected` is refused by the analyzer even inside its own package, so a
    // completion that offers it is the same defect as one that offers a camelCase member across
    // packages: the editor writes it and the next diagnostic pass underlines it.
    //
    // `canReachProtected` is the receiver rule the analyzer enforces, answered by the caller: the
    // caret sits inside a type that IS the receiver's type or derives from it. `isInsideDeclaringType`
    // is the narrower question `private` asks. Both false is the ordinary "completing on somebody
    // else's object" case, and it is also what a caret outside every type answers.
    static func IsOfferableByDeclaredAccessibility(declaredModifiers: int, canReachProtected: bool, isInsideDeclaringType: bool): bool {
        level := MemberAccessibility.LevelOfDeclaredModifiers(declaredModifiers)

        // The whole completion list is one project, so `internal` and the assembly half of
        // `protected internal` are satisfied for every source member the editor can see.
        return MemberAccessibility.IsAccessible(level, isInsideDeclaringType, canReachProtected, canReachProtected, true)
    }

    // THE TYPE A CARET IS WRITTEN INSIDE, or null when it is at namespace scope.
    //
    // A declaration carries its START line and no end, so the enclosing type is read the way a
    // reader would read it: the LAST declaration that begins at or above the caret. When that
    // declaration is a type, the caret is inside it; when it is a top-level `func`, the caret has
    // left the type above and is at namespace scope again.
    static func EnclosingTypeName(unit: CompilationUnit?, line: int): string? {
        if unit == null {
            return null
        }

        best: Declaration? = null
        declarations := unit.Declarations
        index := 0
        while index < declarations.Count {
            candidate := declarations[index]
            if candidate.Line <= line && (best == null || candidate.Line > best.Line) {
                best = candidate
            }

            index = index + 1
        }

        if best == null {
            return null
        }

        return TypeDeclarationName(best)
    }

    // Whether `candidateName` is `ancestorName` or names it somewhere up its declared base chain,
    // read off the parsed files. A base the project did not write ends the walk: an external base
    // contributes no SOURCE member whose declared modifiers this filter could read.
    static func IsTypeOrDerived(candidateName: string?, ancestorName: string?, compilationUnits: IEnumerable<CompilationUnit>): bool {
        if candidateName == null || ancestorName == null {
            return false
        }

        target := SimpleTypeName(ancestorName)
        current := SimpleTypeName(candidateName)
        depth := 0
        while depth < 64 {
            if current == target {
                return true
            }

            next := DeclaredBaseName(current, compilationUnits)
            if next == null {
                return false
            }

            current = next
            depth = depth + 1
        }

        return false
    }

    // The simple name of a source class's `:` clause, or null for anything else.
    static func DeclaredBaseName(typeName: string, compilationUnits: IEnumerable<CompilationUnit>): string? {
        for unit in compilationUnits {
            if unit != null {
                declarations := unit.Declarations
                index := 0
                while index < declarations.Count {
                    classDeclaration := declarations[index] as ClassDeclaration
                    if classDeclaration != null && classDeclaration.Name == typeName && classDeclaration.BaseClass != null {
                        baseName := TypeReferenceName(classDeclaration.BaseClass)
                        if baseName == null {
                            return null
                        }

                        return SimpleTypeName(baseName)
                    }

                    index = index + 1
                }
            }
        }

        return null
    }

    // The written name of a base-class reference. Only the two spellings a `:` clause can carry
    // answer; anything else is not a class the project declared and ends the walk.
    static func TypeReferenceName(reference: TypeReference): string? {
        generic := reference as GenericTypeReference
        if generic != null {
            return generic.Name
        }

        simple := reference as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        return null
    }

    // The whole rule, in one line of code and two words of English: exported, or same package.
    // `declaringNamespace` null is the fail-open case described in the header.
    static func IsOfferableAcrossPackages(isExported: bool, declaringNamespace: string?, requestingNamespace: string): bool {
        if isExported || declaringNamespace == null {
            return true
        }

        return (declaringNamespace ?? "") == requestingNamespace
    }

    // The receiver-type half, resolved and answered in one call so no caller has to hold the
    // position out-parameters. Null means "no filtering", which is what an empty unit collection,
    // a non-source type and an ambiguous name all reduce to.
    static func DeclaringNamespaceOfReceiverType(typeInfo: TypeInfo, typeName: string, compilationUnits: IEnumerable<CompilationUnit>): string? {
        line := 0
        column := 0
        TryGetDeclaredTypePosition(typeInfo, out line, out column)
        return DeclaringNamespaceOfType(typeName, line, column, compilationUnits)
    }
}
