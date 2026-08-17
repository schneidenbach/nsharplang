namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Xml.Linq


// WHAT `nlc query doc` ANSWERS WITH, AND WHERE IT READS THE ANSWER FROM.
//
// One name comes in — `Console`, `Console.WriteLine`, `System.Console`, `List` — and a documented
// description of a type or a member goes out. Two halves make that up and they are strictly
// ordered: `DocQueryTypeIndex` decides WHICH CLR type or member a name means, and this file decides
// WHAT the .NET XML documentation says about it. The second half is the whole of this file, and it
// is why the file is a Linq-to-XML client: the shipped documentation is XML, keyed by ECMA-334
// doc-comment ids, and nothing else in the compiler reads it.
//
// THE DOC LOOKUP IS TWO INDEXES TRIED IN ONE DIRECTION, AND THE ORDER IS THE POLICY.
//   1. the PER-ASSEMBLY index, built lazily from the assembly's own sibling `.xml` file — the
//      authoritative answer, because it is the documentation shipped WITH that exact assembly;
//   2. the GLOBAL index, built once by sweeping every `.xml` in every reference-pack directory —
//      a fallback, because a runtime assembly frequently has no sibling doc file while the
//      reference pack for the same API does.
// A miss in (1) falls to (2); a hit in (1) never consults (2). Reversing them would answer a
// framework's documentation for a member the running assembly actually declares.
//
// AN EMPTY PER-ASSEMBLY INDEX IS A CACHED NEGATIVE, NOT A MISSING ONE. `LoadXmlDoc` inserts the
// (possibly empty) dictionary BEFORE it looks for the file, so an assembly with no `.xml` beside it
// is asked once and never again — which matters, because the miss path is the common one and it is
// what the global sweep exists to catch.
//
// TEXT IS FLATTENED HERE AND SPELLED IN `DocQueryKernels`. A `<summary>` is not a string: it is a
// tree of text and inline elements (`<c>`, `<see cref>`, `<paramref name>`, `<see langword>`), and
// `FormatDocNode` walks it recursively while the kernel decides how each element reads. That split
// is why this file names no punctuation.
class DocQuery {
    loadedDocs: Dictionary<string, XDocument>
    docIndexes: Dictionary<string, Dictionary<string, XElement>>
    globalDocIndex: Dictionary<string, XElement>
    globalDocOwners: Dictionary<string, string>
    typeIndex: DocQueryTypeIndex
    globalDocIndexLoaded: bool

    // THE COMPARERS ARE NOT INTERCHANGEABLE AND BOTH ARE DELIBERATE. The per-assembly maps are keyed
    // by ASSEMBLY NAME and are case-INSENSITIVE, because a file name's case is a filesystem detail.
    // The global maps are keyed by DOC ID and are case-SENSITIVE (`Ordinal`), because a doc id is
    // ECMA-334 identifier text where `M:T.Item` and `M:T.item` are different members.
    constructor() {
        loadedDocs = new Dictionary<string, XDocument>(StringComparer.OrdinalIgnoreCase)
        docIndexes = new Dictionary<string, Dictionary<string, XElement>>(StringComparer.OrdinalIgnoreCase)
        globalDocIndex = new Dictionary<string, XElement>(StringComparer.Ordinal)
        globalDocOwners = new Dictionary<string, string>(StringComparer.Ordinal)
        typeIndex = new DocQueryTypeIndex()
        globalDocIndexLoaded = false
    }

    // ── loading ──────────────────────────────────────────────────────────────────────────────

    // THE THREE SOURCES OF TYPES, IN ORDER: the seed assemblies this tool guarantees are indexed,
    // whatever else the host process already has loaded, and the assemblies a reference pack names
    // but this runtime may not carry. Only the third can fail, and a failure there is DATA — the
    // N# owner records the name so a failed lookup can say the API exists but is not loadable here.
    func LoadSystemAssemblies() {
        for seedAssembly in SeedAssemblies() {
            typeIndex.AddAssembly(seedAssembly)
        }

        for loadedAssembly in ExternalAssemblyScan.Loaded() {
            typeIndex.AddAssembly(loadedAssembly)
        }

        for assemblyName in typeIndex.DiscoverReferencePackAssemblyNames() {
            LoadReferencePackAssembly(assemblyName)
        }
    }

    // THE ONE FALLIBLE STEP, ON ITS OWN. A reference pack names APIs by assembly, and a pack can
    // name one this runtime does not carry — that is normal, not an error, and the three exception
    // types are exactly the three ways `Assembly.Load` says "not here". Anything else is a real
    // fault and is rethrown.
    //
    // ONE CATCH WITH A TEST, NOT THREE CATCHES, AND THAT IS A CLOSER TRANSLITERATION THAN IT LOOKS:
    // the C# this replaced was a SINGLE `catch (Exception ex) when (ex is FileNotFoundException or
    // FileLoadException or BadImageFormatException)`, so the filter always was one predicate over
    // one caught exception. (It is also the only form the toolset takes — a second typed `catch`
    // clause declines the whole `try`. Measured by execution; recorded as finding 99.2.)
    func LoadReferencePackAssembly(assemblyName: string) {
        try {
            loaded := Assembly.Load(assemblyName)
            typeIndex.AddAssembly(loaded)
        } catch ex: Exception {
            if !IsAssemblyUnloadable(ex) {
                throw ex
            }

            typeIndex.NoteUnloadableAssembly(assemblyName)
        }
    }

    // The three ways the runtime says "that assembly is not here".
    static func IsAssemblyUnloadable(ex: Exception): bool {
        return ex is FileNotFoundException || ex is FileLoadException || ex is BadImageFormatException
    }

    // THE SEED SET, NAMED BY TYPE IDENTITY RATHER THAN BY ASSEMBLY NAME, AND THAT IS THE POINT.
    // The C# this replaced wrote `typeof(Console).Assembly`: it seeds the assembly that DECLARES a
    // known type, which is not the same as loading an assembly by a name someone wrote down —
    // `System.IO.File`, `System.Threading.Tasks.Task` and `System.Collections.Generic.List<T>` all
    // live in `System.Private.CoreLib` on this runtime and in facades on others. Naming the TYPE
    // keeps that indirection, and `Type.GetType` on an assembly-qualified name resolves the SAME
    // `Type` object — hence the same `Assembly` object — that `typeof` binds, by reference identity.
    // The nine names collapse to six distinct assemblies, exactly as the C# did.
    static func SeedTypeIdentities(): string[] {
        return ["System.Object, System.Private.CoreLib", "System.Console, System.Console", "System.Linq.Enumerable, System.Linq", "System.Collections.Generic.List`1, System.Private.CoreLib", "System.IO.File, System.Private.CoreLib", "System.Threading.Tasks.Task, System.Private.CoreLib", "System.Text.RegularExpressions.Regex, System.Text.RegularExpressions", "System.Net.Http.HttpClient, System.Net.Http", "System.Text.Json.JsonSerializer, System.Text.Json"]
    }

    static func SeedAssemblies(): Assembly[] {
        identities := SeedTypeIdentities()
        seeds := new Assembly[](identities.Length)
        index := 0
        while index < identities.Length {
            seeds[index] = RequiredSeedType(identities[index]).get_Assembly()
            index = index + 1
        }

        return seeds
    }

    // A SEED THAT DOES NOT RESOLVE IS A BROKEN INSTALL, NOT A MISSING FEATURE. `typeof` could not
    // fail; this can, so it throws rather than silently seeding a shorter index and answering
    // "no documentation" for half the framework.
    static func RequiredSeedType(assemblyQualifiedName: string): Type {
        seedType := Type.GetType(assemblyQualifiedName)
        if seedType == null {
            throw new InvalidOperationException("Required documentation seed type '" + assemblyQualifiedName + "' was not found.")
        }

        return seedType
    }

    // ── the public answer ────────────────────────────────────────────────────────────────────

    // A NAME IS TRIED WHOLE BEFORE IT IS TRIED SPLIT. `System.Console` is a type, and splitting it
    // first would ask for a `Console` member of a `System` type. Only when the whole name resolves
    // to nothing does the kernel propose the type/member splits, in its own order.
    func Lookup(query: string): DocResult? {
        if string.IsNullOrWhiteSpace(query) {
            return null
        }

        exactType := typeIndex.ResolveType(query)
        if exactType != null {
            return DescribeType(exactType)
        }

        splitPlans := DocQueryKernels.GetLookupSplitPlans(query)
        if splitPlans.Length == 0 {
            return null
        }

        for splitPlan in splitPlans {
            planType := typeIndex.ResolveType(splitPlan.TypeCandidate)
            if planType != null {
                nestedType := DocQueryTypeIndex.ResolveNestedTypeChain(planType, splitPlan.RemainderParts)
                if nestedType != null {
                    return DescribeType(nestedType)
                }

                if splitPlan.HasContainingType {
                    containingType := DocQueryTypeIndex.ResolveNestedTypeChain(planType, splitPlan.ContainingTypeParts)
                    if containingType != null {
                        return LookupMember(containingType, splitPlan.LastRemainder)
                    }
                }

                // THE FIRST RESOLVABLE TYPE IS TERMINAL. A plan whose type resolved but whose member
                // did not does NOT fall through to the next plan: the caller asked about that type.
                return LookupMember(planType, splitPlan.FirstRemainder)
            }
        }

        return null
    }

    // WHY A LOOKUP FOUND NOTHING, WHEN THERE IS SOMETHING USEFUL TO SAY. The reference packs
    // document names this runtime cannot load, so a miss on such a name is not "no such API" — it
    // is "that API is not loadable here". The owners are read in the index's own order, which is
    // reference-pack directory order, so the kernel's choice of which owner to name is stable.
    func DescribeLookupMiss(query: string): string? {
        EnsureGlobalDocIndex()
        docIds := new string[](globalDocOwners.Count)
        owners := new string[](globalDocOwners.Count)
        index := 0
        for ownerEntry in globalDocOwners {
            docIds[index] = ownerEntry.Key
            owners[index] = ownerEntry.Value
            index = index + 1
        }

        return DocQueryKernels.DescribeDocLookupMiss(query, docIds, owners, typeIndex.GetUnloadableAssemblyNames())
    }

    // ── describing a type ────────────────────────────────────────────────────────────────────

    func DescribeType(reflectionType: Type): DocResult {
        summary := GetTypeSummary(reflectionType)
        members := GetTypeMembers(reflectionType)
        baseTypes := DocQueryReflectionFacts.GetBaseTypes(reflectionType)

        return DocQueryKernels.CreateTypeDocResult(DocQueryKernels.StripGenericArity(reflectionType.get_Name()), DocQueryReflectionFacts.FormatQualifiedType(reflectionType), DocQueryReflectionFacts.GetTypeKind(reflectionType), summary, reflectionType.get_Namespace(), members, baseTypes)
    }

    // THE MEMBER KINDS IN THE ORDER A READER MEANS THEM. A nested TYPE wins over everything, then
    // constructors, then methods (all overloads together), then a property, a field and an event.
    // The order is not alphabetical and not arbitrary: it goes from the most specific thing the
    // spelling can name to the least, so `List.Enumerator` is a type and `List.Count` is a property.
    func LookupMember(reflectionType: Type, memberName: string): DocResult? {
        nestedType := FindNestedType(reflectionType, memberName)
        if nestedType != null {
            return DescribeType(nestedType)
        }

        constructors := FindConstructors(reflectionType, memberName)
        if constructors.Length > 0 {
            return DescribeConstructors(reflectionType, constructors)
        }

        methods := FindMethods(reflectionType, memberName)
        if methods.Length > 0 {
            return DescribeMethods(reflectionType, memberName, methods)
        }

        instanceFlags := BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase
        property := reflectionType.GetProperty(memberName, instanceFlags)
        if property != null {
            return DocQueryKernels.CreateValueDocResult(property.get_Name(), DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(reflectionType), property.get_Name()), "property", GetPropertySummary(property), reflectionType.get_Namespace(), DocQueryReflectionFacts.FormatType(property.get_PropertyType()))
        }

        field := reflectionType.GetField(memberName, instanceFlags)
        if field != null {
            return DocQueryKernels.CreateValueDocResult(field.get_Name(), DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(reflectionType), field.get_Name()), "field", GetFieldSummary(field), reflectionType.get_Namespace(), DocQueryReflectionFacts.FormatType(field.get_FieldType()))
        }

        eventMember := reflectionType.GetEvent(memberName, instanceFlags)
        if eventMember != null {
            return DocQueryKernels.CreateValueDocResult(eventMember.get_Name(), DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(reflectionType), eventMember.get_Name()), "event", GetEventSummary(eventMember), reflectionType.get_Namespace(), EventHandlerTypeName(eventMember))
        }

        return null
    }

    // An event with no handler type has no type to print. The C# spelled this as a conditional in
    // the argument list; naming it keeps the two event sites reading the same way.
    static func EventHandlerTypeName(eventMember: EventInfo): string? {
        handlerType := eventMember.get_EventHandlerType()
        if handlerType != null {
            return DocQueryReflectionFacts.FormatType(handlerType)
        }

        return null
    }

    static func FindNestedType(reflectionType: Type, memberName: string): Type? {
        for candidate in reflectionType.GetNestedTypes(BindingFlags.Public) {
            if DocQueryKernels.IsDocMemberNameMatch(candidate.get_Name(), memberName) {
                return candidate
            }
        }

        return null
    }

    // THE CONSTRUCTOR TEST DOES NOT LOOK AT THE CANDIDATE, AND THAT IS THE SHIPPED BEHAVIOUR. The
    // question `IsConstructorMemberMatch` answers is whether the REQUESTED NAME names this type's
    // constructor at all, which is a property of the two names and not of any one overload — so the
    // set is all of them or none of them. Reproduced exactly, quirk included.
    static func FindConstructors(reflectionType: Type, memberName: string): ConstructorInfo[] {
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static
        candidates := reflectionType.GetConstructors(flags)
        if !DocQueryKernels.IsConstructorMemberMatch(memberName, reflectionType.get_Name()) {
            return new ConstructorInfo[](0)
        }

        return candidates
    }

    static func FindMethods(reflectionType: Type, memberName: string): MethodInfo[] {
        flags := BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance
        matches := new List<MethodInfo>()
        for candidate in reflectionType.GetMethods(flags) {
            if DocQueryKernels.IsMethodMemberMatch(candidate.get_Name(), memberName, candidate.get_IsSpecialName()) {
                matches.Add(candidate)
            }
        }

        results := new MethodInfo[](matches.Count)
        index := 0
        while index < matches.Count {
            results[index] = matches[index]
            index = index + 1
        }

        return results
    }

    // EVERY OVERLOAD IS SHOWN, AND THE FIRST ONE SUPPLIES THE HEADLINE. A doc answer for
    // `Console.WriteLine` that showed one of nineteen overloads would be worse than useless.
    func DescribeConstructors(reflectionType: Type, constructors: ConstructorInfo[]): DocResult {
        overloads := new DocMemberResult[](constructors.Length)
        index := 0
        while index < constructors.Length {
            constructor := constructors[index]
            overloads[index] = DocQueryKernels.CreateDocMemberResult(DocQueryReflectionFacts.FormatMethodSignature(constructor), "constructor", null, GetMethodSummary(constructor), DocQueryReflectionFacts.FormatParameters(constructor))
            index = index + 1
        }

        first := constructors[0]
        return DocQueryKernels.CreateCallableDocResult(DocQueryKernels.StripGenericArity(reflectionType.get_Name()), DocQueryReflectionFacts.FormatQualifiedType(reflectionType), DocQueryKernels.GetOverloadKindText("constructor", constructors.Length), GetMethodSummary(first), reflectionType.get_Namespace(), overloads, DescribeParameters(first), null, null)
    }

    func DescribeMethods(reflectionType: Type, memberName: string, methods: MethodInfo[]): DocResult {
        overloads := new DocMemberResult[](methods.Length)
        index := 0
        while index < methods.Length {
            method := methods[index]
            overloads[index] = DocQueryKernels.CreateDocMemberResult(DocQueryReflectionFacts.FormatMethodSignature(method), "method", DocQueryReflectionFacts.FormatType(method.get_ReturnType()), GetMethodSummary(method), DocQueryReflectionFacts.FormatParameters(method))
            index = index + 1
        }

        first := methods[0]
        return DocQueryKernels.CreateCallableDocResult(memberName, DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(reflectionType), memberName), DocQueryKernels.GetOverloadKindText("method", methods.Length), GetMethodSummary(first), reflectionType.get_Namespace(), overloads, DescribeParameters(first), DocQueryReflectionFacts.FormatType(first.get_ReturnType()), GetReturnsSummary(first))
    }

    // THE HEADLINE OVERLOAD'S PARAMETERS, each with its own `<param>` text. Shared by the
    // constructor and the method arms because the row is identical in both.
    func DescribeParameters(method: MethodBase): DocParameterResult[] {
        parameters := method.GetParameters()
        results := new DocParameterResult[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            results[index] = DocQueryKernels.CreateDocParameterResult(parameter.get_Name(), DocQueryReflectionFacts.FormatType(parameter.get_ParameterType()), GetParameterSummary(method, parameter.get_Name()))
            index = index + 1
        }

        return results
    }

    // EVERY DECLARED MEMBER OF A TYPE, IN THE ORDER THE KERNEL SORTS THEM. `DeclaredOnly` is on all
    // five member sweeps and off the nested-type sweep, which is the shipped shape: an inherited
    // `ToString` is noise on `List<T>`, but a nested type is always the type's own.
    func GetTypeMembers(reflectionType: Type): DocMemberResult[] {
        results := new List<DocMemberResult>()
        declaredFlags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly

        for nestedType in reflectionType.GetNestedTypes(BindingFlags.Public) {
            results.Add(DocQueryKernels.CreateDocMemberResult(DocQueryKernels.StripGenericArity(nestedType.get_Name()), "nested type", DocQueryReflectionFacts.FormatQualifiedType(nestedType), GetTypeSummary(nestedType), null))
        }

        for constructor in reflectionType.GetConstructors(declaredFlags) {
            results.Add(DocQueryKernels.CreateDocMemberResult(DocQueryReflectionFacts.FormatMethodSignature(constructor), "constructor", null, GetMethodSummary(constructor), DocQueryReflectionFacts.FormatParameters(constructor)))
        }

        for property in reflectionType.GetProperties(declaredFlags) {
            results.Add(DocQueryKernels.CreateDocMemberResult(property.get_Name(), "property", DocQueryReflectionFacts.FormatType(property.get_PropertyType()), GetPropertySummary(property), null))
        }

        // `get_`/`set_`/`add_`/`remove_` accessors are members of the metadata and not of the API.
        for method in reflectionType.GetMethods(declaredFlags) {
            if !method.get_IsSpecialName() {
                results.Add(DocQueryKernels.CreateDocMemberResult(method.get_Name(), "method", DocQueryReflectionFacts.FormatType(method.get_ReturnType()), GetMethodSummary(method), DocQueryReflectionFacts.FormatParameters(method)))
            }
        }

        for field in reflectionType.GetFields(declaredFlags) {
            results.Add(DocQueryKernels.CreateDocMemberResult(field.get_Name(), "field", DocQueryReflectionFacts.FormatType(field.get_FieldType()), GetFieldSummary(field), null))
        }

        for eventMember in reflectionType.GetEvents(declaredFlags) {
            results.Add(DocQueryKernels.CreateDocMemberResult(eventMember.get_Name(), "event", EventHandlerTypeName(eventMember), GetEventSummary(eventMember), null))
        }

        return DocQueryKernels.OrderDocMembers(results)
    }

    // ── the doc-id summaries ─────────────────────────────────────────────────────────────────

    // FIVE MEMBER KINDS, FIVE DOC-ID PREFIXES, ONE LOOKUP. The prefix IS the member kind in the
    // ECMA-334 id grammar, and a member is looked up in the documentation of the assembly that
    // DECLARES it — not the one the caller asked through, which for an inherited member differs.
    func GetTypeSummary(reflectionType: Type): string? {
        return GetDocSummary(reflectionType.get_Assembly(), DocQueryKernels.GetReflectionTypeDocId(reflectionType))
    }

    func GetMethodSummary(method: MethodBase): string? {
        return GetDocSummary(DeclaringAssembly(method.get_DeclaringType()), DocQueryReflectionFacts.GetMethodDocId(method))
    }

    func GetPropertySummary(property: PropertyInfo): string? {
        declaringType := property.get_DeclaringType()
        return GetDocSummary(DeclaringAssembly(declaringType), DocQueryKernels.GetDocMemberDocId("P:", DeclaringFullName(declaringType), property.get_Name()))
    }

    func GetFieldSummary(field: FieldInfo): string? {
        declaringType := field.get_DeclaringType()
        return GetDocSummary(DeclaringAssembly(declaringType), DocQueryKernels.GetDocMemberDocId("F:", DeclaringFullName(declaringType), field.get_Name()))
    }

    func GetEventSummary(eventMember: EventInfo): string? {
        declaringType := eventMember.get_DeclaringType()
        return GetDocSummary(DeclaringAssembly(declaringType), DocQueryKernels.GetDocMemberDocId("E:", DeclaringFullName(declaringType), eventMember.get_Name()))
    }

    static func DeclaringAssembly(declaringType: Type?): Assembly? {
        if declaringType != null {
            return declaringType.get_Assembly()
        }

        return null
    }

    static func DeclaringFullName(declaringType: Type?): string? {
        if declaringType != null {
            return declaringType.get_FullName()
        }

        return null
    }

    // A `<param>` IS SELECTED BY ITS `name` ATTRIBUTE, NOT BY ITS POSITION. The documentation order
    // need not match the signature order, and for several BCL members it does not.
    func GetParameterSummary(method: MethodBase, parameterName: string?): string? {
        if parameterName != null {
            element := GetDocElement(DeclaringAssembly(method.get_DeclaringType()), DocQueryReflectionFacts.GetMethodDocId(method))
            if element != null {
                for parameterElement in element.Elements(XName.Get("param")) {
                    nameAttribute := parameterElement.Attribute(XName.Get("name"))
                    if nameAttribute != null {
                        attributeText := AttributeValue(nameAttribute)
                        if attributeText == parameterName {
                            return FormatDocText(parameterElement)
                        }
                    }
                }
            }
        }

        return null
    }

    func GetReturnsSummary(method: MethodInfo): string? {
        element := GetDocElement(DeclaringAssembly(method.get_DeclaringType()), DocQueryReflectionFacts.GetMethodDocId(method))
        if element != null {
            return FormatDocText(element.Element(XName.Get("returns")))
        }

        return null
    }

    func GetDocSummary(assembly: Assembly?, docId: string): string? {
        element := GetDocElement(assembly, docId)
        if element != null {
            return FormatDocText(element.Element(XName.Get("summary")))
        }

        return null
    }

    // ── the two indexes ──────────────────────────────────────────────────────────────────────

    // THE PER-ASSEMBLY INDEX FIRST, THE GLOBAL SWEEP SECOND. See the file note: an assembly's own
    // documentation outranks a reference pack's for the same id.
    func GetDocElement(assembly: Assembly?, docId: string): XElement? {
        if assembly != null {
            assemblyName := assembly.GetName().get_Name()
            if assemblyName != null {
                if !docIndexes.ContainsKey(assemblyName) {
                    LoadXmlDoc(assembly)
                }

                // `ContainsKey` + indexer rather than `TryGetValue`: an `out` of a reference type
                // needs a throwaway initial value, and constructing an `XElement` to discard it is
                // both wasteful and a constructor this catalog deliberately does not admit — the
                // doc walk only ever READS XML.
                if docIndexes.ContainsKey(assemblyName) {
                    index := docIndexes[assemblyName]
                    if index.ContainsKey(docId) {
                        return index[docId]
                    }
                }

                EnsureGlobalDocIndex()
                if globalDocIndex.ContainsKey(docId) {
                    return globalDocIndex[docId]
                }
            }
        }

        return null
    }

    // THE EMPTY INDEX IS INSERTED BEFORE THE FILE IS SOUGHT. That is what turns "this assembly has
    // no documentation" into a question asked once instead of on every member of every answer.
    func LoadXmlDoc(assembly: Assembly) {
        assemblyName := assembly.GetName().get_Name()
        if assemblyName != null {
            if !docIndexes.ContainsKey(assemblyName) {
                index := new Dictionary<string, XElement>()
                docIndexes[assemblyName] = index

                xmlPath := typeIndex.GetXmlDocPath(assembly)
                if File.Exists(xmlPath) {
                    document := XDocument.Load(xmlPath)
                    loadedDocs[assemblyName] = document
                    for member in DocumentMembers(document) {
                        nameAttribute := member.Attribute(XName.Get("name"))
                        if nameAttribute != null {
                            index[AttributeValue(nameAttribute)] = member
                        }
                    }
                }
            }
        }
    }

    // `<doc><members><member name="…">` — the shipped layout. A file that does not have it
    // contributes nothing rather than throwing, which is what the C#'s `?.` chain also did.
    static func DocumentMembers(document: XDocument): IEnumerable<XElement> {
        root := document.Root
        if root != null {
            members := root.Element(XName.Get("members"))
            if members != null {
                return members.Elements(XName.Get("member"))
            }
        }

        return new List<XElement>()
    }

    // SWEPT ONCE, FIRST WRITER WINS, AND BOTH FACTS MATTER. Reference packs overlap heavily, so the
    // same doc id appears in several files; keeping the FIRST makes the answer depend on directory
    // order rather than on filesystem enumeration order, and the owner recorded beside it is what
    // `DescribeLookupMiss` names.
    func EnsureGlobalDocIndex() {
        if !globalDocIndexLoaded {
            globalDocIndexLoaded = true

            for referenceDirectory in typeIndex.GetReferencePackDirectories() {
                for xmlFile in Directory.EnumerateFiles(referenceDirectory, "*.xml") {
                    // `GetFileNameWithoutExtension` is modelled as `string?`; the paths here come
                    // from `EnumerateFiles`, so the null arm is unreachable and coalescing to the
                    // empty string is what the C# `string` return already meant.
                    owner := Path.GetFileNameWithoutExtension(xmlFile) ?? ""
                    document := XDocument.Load(xmlFile)
                    for member in DocumentMembers(document) {
                        nameAttribute := member.Attribute(XName.Get("name"))
                        if nameAttribute != null {
                            docId := AttributeValue(nameAttribute)
                            if !string.IsNullOrWhiteSpace(docId) {
                                if !globalDocIndex.ContainsKey(docId) {
                                    globalDocIndex[docId] = member
                                    globalDocOwners[docId] = owner
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the doc text ─────────────────────────────────────────────────────────────────────────

    // A `<summary>` IS A TREE, NOT A STRING. Its children are text runs and inline elements, and
    // the raw concatenation is handed to the kernel to be collapsed and trimmed.
    static func FormatDocText(element: XElement?): string? {
        if element != null {
            raw := ""
            for node in element.Nodes() {
                raw = raw + FormatDocNode(node)
            }

            return DocQueryKernels.FormatDocTextRaw(raw)
        }

        return null
    }

    // THE RECURSION IS THE POINT: `<summary>Uses <see cref="T:X"/> for <c>y</c></summary>` nests,
    // and each element's own children are flattened before the kernel decides how the element
    // reads. A node that is neither text nor an element (a comment, a processing instruction)
    // contributes nothing.
    static func FormatDocNode(node: XNode): string {
        textNode := node as XText
        if textNode != null {
            return textNode.Value
        }

        elementNode := node as XElement
        if elementNode != null {
            childText := ""
            for child in elementNode.Nodes() {
                childText = childText + FormatDocNode(child)
            }

            elementName := elementNode.Name
            return DocQueryKernels.FormatDocElementNodeText(elementName.LocalName, elementNode.Value, childText, AttributeText(elementNode, "name"), AttributeText(elementNode, "langword"), AttributeText(elementNode, "href"), AttributeText(elementNode, "cref"))
        }

        return ""
    }

    static func AttributeText(element: XElement, attributeName: string): string? {
        attribute := element.Attribute(XName.Get(attributeName))
        if attribute != null {
            return AttributeValue(attribute)
        }

        return null
    }

    // `.Value` IS READ THROUGH A NON-NULLABLE PARAMETER, AND THAT IS NOT A STYLE CHOICE. On a
    // NULLABLE-ANNOTATED receiver the analyser reads `.Value` as the language's nullable UNWRAP
    // rather than as `XAttribute`'s own property, and types the result `XAttribute` — and narrowing
    // a local with `!= null` does not change its declared annotation, so the collision survives the
    // guard. A non-nullable parameter has no annotation to unwrap, so the property binds. The
    // EMITTER binds the property either way; this is an analyser-side name collision, recorded as
    // finding 99.3, and routing every attribute read through here is what keeps `nlc check` clean.
    static func AttributeValue(attribute: XAttribute): string {
        return attribute.Value
    }
}
