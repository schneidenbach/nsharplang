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
