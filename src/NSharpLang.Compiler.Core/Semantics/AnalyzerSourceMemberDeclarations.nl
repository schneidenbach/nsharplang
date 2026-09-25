namespace NSharpLang.Compiler


// WHERE A SOURCE MEMBER IS DECLARED: the one answer both member-naming forms record their binding
// from, so go-to-definition, references, hover and rename read the SAME declaration whether the
// member was written `this.Label()` or bare `Label()`.
//
// The owner's own members are searched first and then every source base's, nearest first, through
// closed generic base substitutions — `AnalyzerDeclarationContext.TryFindMember`'s walk, which is the
// walk member resolution itself takes. A member only a REFLECTED type declares has no source position
// and answers `false`: its hover belongs to the reflected-member route, and it has nothing to define.
//
// Extension methods are deliberately NOT here. Only a written receiver can select one, so the member
// access arm adds that fallback on top of this answer and a bare name never reaches it.
class AnalyzerSourceMemberDeclarations {
    declarationContextValue: AnalyzerDeclarationContext
    projectSourcesValue: AnalyzerProjectSourceProvider

    constructor(declarationContext: AnalyzerDeclarationContext, projectSources: AnalyzerProjectSourceProvider) {
        declarationContextValue = declarationContext
        projectSourcesValue = projectSources
    }

    func TryFind(owner: TypeInfo, memberName: string, out declaration: SymbolDeclaration?): bool {
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(owner)
        selection := new AnalyzerMemberSelection()
        if !declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            declaration = null
            return false
        }

        member := selection.Member
        if member != null {
            declaration = Create(member, selection.FilePath, selection.KindName)
        } else {
            declaration = new SymbolDeclaration(memberName, selection.FilePath, selection.Line, selection.Column, selection.KindName)
        }

        return true
    }

    // The declaration's own column is re-derived from the declaring file's TEXT rather than trusted
    // from the parsed node, so go-to-definition lands on the NAME and not on the modifier that
    // precedes it.
    // The KIND WORD comes from the selection rather than off the member, because the word depends on
    // the OWNER the member was found on: an interface's instance value member is a property, and only
    // the lookup that walked the owner knows that.
    func Create(member: DeclaredMemberInfo, filePath: string?, kindName: string): SymbolDeclaration {
        sourceText := projectSourcesValue.TryGetProjectSourceText(filePath)
        return new SymbolDeclaration(member.Name, filePath, member.Line, AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, member.Name, member.Line, member.Column), kindName)
    }
}
