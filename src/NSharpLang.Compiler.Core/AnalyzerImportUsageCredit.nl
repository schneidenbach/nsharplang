namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHICH NAMESPACE SUPPLIED A NAME — the one measurement NL010 and NL002 are both answered from.
//
// THE RULE IS ARITHMETIC ON THE RESOLVED IDENTITY, NOT A LOOKUP. A written spelling `W` that resolved
// to a type whose full name is `F` was supplied by the namespace `N` exactly when `F` is `N.W`. So
// the answer is `F` with `"." + W` cut off its end, and nothing else:
//
//     List                 -> System.Collections.Generic.List`1   -> System.Collections.Generic
//     Collections.Generic.List (with `import System`)
//                          -> System.Collections.Generic.List`1   -> System
//     System.Type          -> System.Type                         -> nothing: fully qualified
//     Outer.Inner          -> Catalog.Outer+Inner                 -> Catalog
//
// The third line is the one a table can never get right and the one the census turned up twice: a
// FULLY QUALIFIED spelling leaves no prefix over, so it credits no import — which is exactly why
// `import System` beside `func F(t: System.Type)` really is dead. The second line is the other one:
// a partially qualified spelling credits the import that supplied its ROOT, which no per-name table
// can express at all.
//
// TWO METADATA SPELLINGS ARE NORMALISED BEFORE THE ARITHMETIC, because neither is how a developer
// writes the name: the generic arity suffix (`List``1`) and the nested-type separator (`Outer+Inner`).
// Nothing else is touched — a namespace segment that happens to contain a backtick is not a thing.
//
// A SOURCE TYPE HAS NO `FullName`, so its namespace comes from the file that declares it. That is the
// same fact for the same purpose: `import Catalog.Parts` is used by a file that writes `Widget` when
// `Widget` is declared in a file whose namespace is `Catalog.Parts`.
class AnalyzerImportUsageCredit {
    declarationContext: AnalyzerDeclarationContext
    usingAliases: Dictionary<string, string>
    facts: ImportUsageFacts?

    // EVERY RESOLVED NAME IN EVERY FILE COMES THROUGH HERE, so the two metadata reads this rule needs
    // are memoised against the `Type` rather than paid per resolution. `Type.get_Namespace` and
    // `Type.get_FullName` are COMPUTED by the MetadataLoadContext — they build a string each call —
    // and asking them on every type reference in a project measured 60% on top of `nlc check`. The
    // keys are the load context's own `Type` instances, which outlive any single analysis, so the
    // memo is never cleared: a namespace is a property of the metadata, not of the file asking.
    namespacesByType: Dictionary<Type, string>
    fullNamesByType: Dictionary<Type, string>

    constructor(context: AnalyzerDeclarationContext, aliases: Dictionary<string, string>) {
        declarationContext = context
        usingAliases = aliases
        facts = null
        namespacesByType = new Dictionary<Type, string>()
        fullNamesByType = new Dictionary<Type, string>()
    }

    // One call per `Analyze`, with the unit's own (fresh) facts. A null unit — an in-memory probe —
    // credits nothing, which costs nothing to ask.
    func BeginAnalysis(unit: CompilationUnit?) {
        if unit == null {
            facts = null
            return
        }

        facts = unit.ImportUsage
    }

    Facts: ImportUsageFacts? => facts

    // THE CREDIT DOOR every resolution channel calls. `writtenName` is the developer's spelling at
    // this position; `resolved` is what it bound to. A position of `line <= 0` is a positionless
    // probe — an attribute's alternate spelling, a well-known-type question — and still credits the
    // namespace, because an import that answered a probe answered for something the file wrote.
    func CreditResolvedType(writtenName: string, resolved: TypeInfo?, line: int, column: int) {
        ledger := facts
        if ledger == null || resolved == null || writtenName.Length == 0 {
            return
        }

        metadataType := MetadataTypeOf(resolved)
        if metadataType != null {
            supplier := MetadataSupplier(writtenName, metadataType)
            if supplier != null {
                RecordMetadataName(writtenName, supplier ?? "", line, column, writtenName.Length)
            }

            return
        }

        sourceFullName := SourceFullNameOf(resolved)
        if sourceFullName == null {
            return
        }

        supplier := SupplyingNamespace(writtenName, sourceFullName ?? "")
        if supplier == null {
            supplier = AliasedSupplyingNamespace(writtenName, sourceFullName ?? "")
        }

        ledger.CreditNamespace(supplier)
    }

    // THE COMMON CASE IS ONE PROPERTY READ, NOT THE ARITHMETIC. A spelling with no dot in it and a
    // type that is not nested can only have been supplied by that type's OWN namespace, so the
    // memoised `Namespace` answers directly. The arithmetic below is for the two spellings where the
    // namespace and the prefix differ: a DOTTED spelling (fully or partially qualified), and a NESTED
    // type, whose own namespace is its outer type's.
    //
    // The name is checked before the shortcut is taken: a channel that answered with a type of some
    // OTHER name did not resolve this spelling, and crediting its namespace would keep a dead import
    // alive.
    func MetadataSupplier(writtenName: string, metadataType: Type): string? {
        if writtenName.IndexOf('.') < 0 && metadataType.DeclaringType == null && SimpleNameMatches(metadataType, writtenName) {
            return NamespaceOf(metadataType)
        }

        fullName := FullNameOf(metadataType)
        supplier := SupplyingNamespace(writtenName, fullName)
        if supplier == null {
            return AliasedSupplyingNamespace(writtenName, fullName)
        }

        return supplier
    }

    // `List``1` is written `List`. Compared without allocating: the metadata name is the written one
    // plus, at most, a backtick and digits.
    static func SimpleNameMatches(metadataType: Type, writtenName: string): bool {
        name := metadataType.Name
        if name.Length < writtenName.Length {
            return false
        }

        index := 0
        while index < writtenName.Length {
            if name[index] != writtenName[index] {
                return false
            }

            index = index + 1
        }

        if name.Length == writtenName.Length {
            return true
        }

        return name[writtenName.Length] == '`'
    }

    func NamespaceOf(metadataType: Type): string {
        cached := ""
        if namespacesByType.TryGetValue(metadataType, out cached) {
            return cached
        }

        resolvedNamespace := metadataType.Namespace ?? ""
        namespacesByType[metadataType] = resolvedNamespace
        return resolvedNamespace
    }

    func FullNameOf(metadataType: Type): string {
        cached := ""
        if fullNamesByType.TryGetValue(metadataType, out cached) {
            return cached
        }

        resolvedName := NormalizeMetadataName(metadataType.FullName ?? "")
        fullNamesByType[metadataType] = resolvedName
        return resolvedName
    }

    // The CLR type behind a resolution, or null when the name resolved to source, to a tuple, to a
    // function type or to nothing at all. A constructed generic answers with its DEFINITION's type:
    // `List<int>` is supplied by whatever supplies `List`.
    static func MetadataTypeOf(resolved: TypeInfo): Type? {
        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            return reflection.Type
        }

        generic := resolved as GenericTypeInfo
        if generic != null {
            definition := generic.GenericDefinition
            if definition != null {
                return MetadataTypeOf(definition)
            }
        }

        return null
    }

    // AN ALIAS-QUALIFIED SPELLING CREDITS THE IMPORT IT IS AN ALIAS OF. `import System.Text as Txt`
    // beside `new Txt.StringBuilder()` resolves to `System.Text.StringBuilder`, and the arithmetic
    // above finds nothing to cut because the written root is `Txt`, not `System.Text`. Expanding the
    // root and asking again is the same measurement on the same identity.
    //
    // ONE NAMESPACE IS CREDITED, NOT TWO NAMES. An N# aliased import does both things at once — it
    // binds `Txt` AND brings `StringBuilder` into scope unqualified — so both spellings are uses of
    // the SAME import, and crediting the namespace answers for both.
    func AliasedSupplyingNamespace(writtenName: string, resolvedFullName: string): string? {
        separator := writtenName.IndexOf('.')
        if separator <= 0 {
            return null
        }

        root := writtenName.Substring(0, separator)
        aliasedNamespace := ""
        if !usingAliases.TryGetValue(root, out aliasedNamespace) {
            return null
        }

        expanded := aliasedNamespace + writtenName.Substring(separator)
        if SupplyingNamespace(expanded, resolvedFullName) == null && NormalizeMetadataName(resolvedFullName) != NormalizeMetadataName(expanded) {
            return null
        }

        return aliasedNamespace
    }

    // THE NAMESPACE IS ALWAYS CREDITED; THE NL002 FINDING IS NOT.
    //
    // A name the PROJECT ITSELF declares is not a missing import, whatever a referenced assembly
    // happens to call its own types. The two disagree more often than they look: a receiver position
    // resolves through the external probe before it consults a sibling file's declarations, so
    // `Guard.Fail(...)` beside a source `class Guard` answers with a metadata `Guard` — and NL002
    // would tell the author to import a namespace their program does not use. NL010 is unaffected,
    // because keeping an import alive on a name that might have come through it is the safe
    // direction and reporting one that did not is not.
    func RecordMetadataName(writtenName: string, supplier: string, line: int, column: int, length: int) {
        ledger := facts
        if ledger == null {
            return
        }

        if declarationContext.DeclaresTypeNamed(writtenName) {
            ledger.CreditNamespace(supplier)
            return
        }

        ledger.CreditReference(writtenName, supplier, line, column, length)
    }

    // AN ATTRIBUTE HAS TWO LEGAL SPELLINGS AND A FILE MAY WRITE EITHER. `[Obsolete]` and
    // `[ObsoleteAttribute]` name one type, and the arithmetic cannot see that: the written `Obsolete`
    // is not a suffix of `System.ObsoleteAttribute`. So the second spelling is tried when the first
    // finds nothing, which is the same rule the attribute resolver itself applies when it looks the
    // type up.
    //
    // The NL002 finding keeps the WRITTEN spelling, because that is what the developer typed and what
    // the squiggle covers; only the lookup uses the other one. A fully qualified `[System.Obsolete]`
    // credits nothing, as every fully qualified spelling does: there is no prefix left over for an
    // import to have supplied.
    func CreditAttributeType(writtenName: string, attributeType: Type, line: int, column: int, length: int) {
        ledger := facts
        if ledger == null || writtenName.Length == 0 {
            return
        }

        supplier := MetadataSupplier(writtenName, attributeType)
        if supplier == null {
            supplier = MetadataSupplier(writtenName + "Attribute", attributeType)
        }

        if supplier == null {
            return
        }

        RecordMetadataName(writtenName, supplier ?? "", line, column, length)
    }

    // A NAMESPACE THAT ANSWERED FOR A NAME, credited directly by the channel that swept it. The
    // project-type sweep is the case: a source type carries its own name and not the namespace that
    // supplied it, so the arithmetic above has nothing to work on and the sweep is the only owner
    // that knows. It is never an NL002 finding — a source type in another namespace of the same
    // project resolves with no import at all, so there is no import to demand.
    func CreditNamespaceSupplier(namespaceName: string?) {
        ledger := facts
        if ledger != null {
            ledger.CreditNamespace(namespaceName)
        }
    }

    // An extension method, an attribute constructor or any other member whose DECLARING TYPE is what
    // the import supplied: there is no written type name to do the arithmetic on, so the declaring
    // namespace is credited directly. It is never an NL002 finding — the file wrote a member name,
    // not a type name, and "add an import for `Select`" is not a sentence.
    func CreditDeclaringNamespace(declaringType: Type?) {
        ledger := facts
        if ledger == null || declaringType == null {
            return
        }

        ledger.CreditNamespace(declaringType.Namespace)
    }

    // THE ARITHMETIC. `null` means "this spelling credits no import": either it already spells the
    // whole identity (a fully qualified name), or the resolved identity does not end in the spelling
    // at all, which happens when a channel answered with a type that is not what was written.
    static func SupplyingNamespace(writtenName: string, resolvedFullName: string): string? {
        normalized := NormalizeMetadataName(resolvedFullName)
        spelling := NormalizeMetadataName(writtenName)
        if spelling.Length == 0 || normalized.Length <= spelling.Length {
            return null
        }

        suffix := "." + spelling
        if !normalized.EndsWith(suffix, StringComparison.Ordinal) {
            return null
        }

        return normalized.Substring(0, normalized.Length - suffix.Length)
    }

    // `System.Collections.Generic.List``1` -> `System.Collections.Generic.List`;
    // `Catalog.Outer+Inner` -> `Catalog.Outer.Inner`. Both are metadata spellings for names a
    // developer writes without them.
    static func NormalizeMetadataName(name: string): string {
        text := name.Replace('+', '.')
        tick := text.IndexOf('`')
        while tick >= 0 {
            end := tick + 1
            while end < text.Length && char.IsDigit(text[end]) {
                end = end + 1
            }

            text = text.Substring(0, tick) + text.Substring(end)
            tick = text.IndexOf('`')
        }

        return text
    }

    // A SOURCE type answers with the namespace of the file that declares it plus its own name. A type
    // the declaration context does not own — a tuple, a function type, an unresolved placeholder —
    // answers nothing.
    func SourceFullNameOf(resolved: TypeInfo): string? {
        declarationFile := declarationContext.GetDeclarationFile(resolved)
        if declarationFile == null {
            return null
        }

        declaringNamespace := declarationContext.GetNamespaceForFile(declarationFile)
        if declaringNamespace == null {
            return null
        }

        sourceName := SourceTypeName(resolved)
        if sourceName == null {
            return null
        }

        return (declaringNamespace ?? "") + "." + (sourceName ?? "")
    }

    // A SOURCE TYPE'S WRITTEN NAME. The four nominal forms carry it directly; an enum and a union
    // carry it on their declaration. Anything else — a tuple, a function type, an array — is not a
    // name an import can supply and answers nothing.
    static func SourceTypeName(resolved: TypeInfo): string? {
        classType := resolved as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        structType := resolved as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := resolved as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        interfaceType := resolved as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        enumType := resolved as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Name
        }

        unionType := resolved as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Name
        }

        return null
    }

}
