namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT KIND OF RECEIVER THIS IS, AND WHICH REFLECTED MEMBERS IT OFFERS.
//
// A receiver that no source declaration explains is answered from METADATA instead, and that is the
// whole of this file: read what was written before the dot, turn it into the CLR type a completion
// should reflect over, decide which members that type may show, and read them.
//
// ONE RULE RUNS THROUGH IT: THE FAMILY NEVER ANSWERS A TYPE IT CANNOT READ. Every arm that cannot
// produce a readable `Type` answers null, and the caller then shows no members at all — which is
// what it already does for every receiver this file declines. There are exactly three ways to fail
// that way and all three used to be crashes:
//   - a `ReflectionTypeInfo` carrying a null `Type` (the C# reported success and handed the walk a
//     null to call `GetMethods` on),
//   - a generic close the CLR REFUSES, which throws,
//   - and a generic close the CLR ACCEPTS BUT POISONS. That last one is the reachable one, and it
//     is the estate's own already-solved problem: a LIVE `typeof(List<>)` closed over a
//     `MetadataLoadContext` type argument does not throw — it answers a `TypeBuilderInstantiation`
//     whose every member lookup throws `NotSupportedException`. The analyzer met this exact shape
//     and named it, so the predicate is `AnalyzerClrTypeConversion.IsPoisonedMixedInstantiation`
//     and not a second opinion. Re-homing, which that owner can do, is not available here: this
//     file's definitions are ALWAYS live and it is the ARGUMENT that is foreign, so declining is
//     the only sound answer.
//
// THE MEMBER READ ITSELF IS `MetadataLoadContext`-SAFE and deliberately so: it never compares a
// `Type` by identity, only `DeclaringType.FullName` against `"System.Object"`, and the type text it
// shows is `CompletionTypeTextFacts.FormatClrTypeText`, which is keyed on `get_FullName()`.

// WHICH HALF OF A TYPE A RECEIVER IS ASKING FOR. `Person.` wants the statics, `person.` wants the
// instance members; `All` is the unfiltered read.
enum CompletionMemberFilter {
    All,
    StaticOnly,
    InstanceOnly
}

class CompletionReflectionFacts {

    // WHICH HALF A RECEIVER IS ASKING FOR. `Person.` is a TYPE NAME and wants the statics; `person.`
    // is a VALUE and wants the instance members. A receiver read this way is never `All`: the
    // unfiltered read exists for callers that are not looking at a receiver at all.
    static func GetMemberFilter(receiver: string, typeInfo: TypeInfo): CompletionMemberFilter {
        if IsStaticTypeReceiver(receiver, typeInfo) {
            return CompletionMemberFilter.StaticOnly
        }

        return CompletionMemberFilter.InstanceOnly
    }

    // A RECEIVER IS A TYPE NAME ONLY WHEN BOTH HALVES AGREE: the TEXT is spelled the way N# spells
    // an exported name, and what it RESOLVED to is one of the five shapes a type can be. Neither
    // half is sufficient alone — an exported local would pass the first, and a variable's own type
    // is one of these five shapes too — so the conjunction is the rule and not an optimisation.
    static func IsStaticTypeReceiver(receiver: string, typeInfo: TypeInfo): bool {
        if !VisibilityConventions.IsExportedIdentifier(receiver) {
            return false
        }

        return typeInfo is ReflectionTypeInfo || typeInfo is ClassTypeInfo || typeInfo is StructTypeInfo || typeInfo is EnumTypeInfo || typeInfo is InterfaceTypeInfo
    }

    // A LITERAL RECEIVER HAS A TYPE NOBODY DECLARED, so the text is the only evidence there is. A
    // string literal is the one literal the engine answers, and it answers the NAME rather than the
    // `Type` — `ResolveCompletionReflectionType` above is what turns a name into one, and routing
    // through it is what keeps a literal receiver on exactly the same path as a declared one.
    static func ResolveLiteralReceiverType(receiver: string): TypeInfo? {
        if IsStringLiteralReceiver(receiver) {
            return new SimpleTypeInfo("System.String")
        }

        return null
    }

    // A run of `$` — none, one, or an interpolation's worth — and then a quote. Nothing after the
    // quote is read, and in particular the literal is NOT required to close: a completion is asked
    // inside half-written code by definition, so demanding a closing quote would refuse the very
    // receiver the caller is standing on.
    static func IsStringLiteralReceiver(receiver: string): bool {
        index := 0
        while index < receiver.Length && receiver[index] == '$' {
            index = index + 1
        }

        return index < receiver.Length && receiver[index] == '"'
    }

    // THE BINDING FLAGS A COMPLETION READS WITH, AND THE THREE THINGS THEY DELIBERATELY OMIT.
    // `Public` is always set and `NonPublic` never is, so a completion offers only what a caller
    // could write. `DeclaredOnly` is NOT set, so INHERITED INSTANCE members are offered — a
    // `string` receiver shows `GetType` because `System.Object` declares it. `FlattenHierarchy` is
    // NOT set either, so INHERITED STATICS are NOT offered, and the two arms of the filter are
    // therefore not mirror images. That asymmetry is the platform's and it is preserved exactly.
    static func GetReflectionBindingFlags(filter: CompletionMemberFilter): BindingFlags {
        return GetReflectionBindingFlags(filter, false)
    }

    // `inheritedProtected` IS THE INHERITED-BASE CASE AND NOTHING ELSE. A source type that derives
    // from a type in a referenced assembly owns what that type declares `protected`, and the editor
    // offered none of it: a caret after `this.` inside a `class Bag: Collection<string>` listed
    // `Add` and `Count` but not `SetItem`, `ClearItems` or `Items` — the very members that type
    // exists to have overridden, and which the compiler accepts. `NonPublic` is added only for that
    // walk; `IsReachableInheritedMember` below then decides what of it is actually reachable, so a
    // `private` or `internal` member of the base is still never offered.
    static func GetReflectionBindingFlags(filter: CompletionMemberFilter, inheritedProtected: bool): BindingFlags {
        return GetReflectionBindingFlags(filter, inheritedProtected, false)
    }

    // `friendAdmits` IS THE OTHER REASON TO ASK FOR NON-PUBLIC MEMBERS, and it is a DIFFERENT
    // relation from the inherited-protected one. A referenced assembly that declares
    // `[assembly: InternalsVisibleTo("Tests")]` has made this compilation a friend, and the analyzer
    // has resolved its `internal` members for that project since friends landed — `nlc check` accepts
    // `WorkspaceSymbolHandler.MatchesQuery(...)`, an `internal static` method of a public type, from
    // the project that assembly names. The completion list offered only the public surface, so the
    // editor hid exactly the members the compiler was willing to bind. `InternalsVisibleToGrants` is
    // the one owner of the grant and `MemberAccessibility.IsAccessible` the one owner of the relation;
    // this arm asks both rather than inventing a third answer.
    static func GetReflectionBindingFlags(filter: CompletionMemberFilter, inheritedProtected: bool, friendAdmits: bool): BindingFlags {
        flags := BindingFlags.Public
        if inheritedProtected || friendAdmits {
            flags = flags | BindingFlags.NonPublic
        }

        if filter == CompletionMemberFilter.StaticOnly {
            return flags | BindingFlags.Static
        }

        if filter == CompletionMemberFilter.InstanceOnly {
            return flags | BindingFlags.Instance
        }

        return flags | BindingFlags.Static | BindingFlags.Instance
    }

    // WHICH LEVELS A DERIVED TYPE IN THIS ASSEMBLY MAY REACH ON A REFERENCED BASE. The same relation
    // the analyzer's member resolution and the emitter's candidate enumeration ask, with the same
    // answer: `public`, `protected` and `protected internal` — and the three whose reach depends on
    // being in the same assembly ONLY when that referenced assembly has named this compilation a
    // friend, which is the second arity below.
    static func IsReachableInheritedMember(level: int, inheritedProtected: bool): bool {
        return IsReachableInheritedMember(level, inheritedProtected, false)
    }

    // The same relation with the friend grant answered. `sameAssembly` is what an `internal` member
    // asks, and a friend grant is precisely the CLR's answer that this compilation counts as the
    // declaring assembly for that question — so it is passed there rather than widened into a fourth
    // arm of the relation.
    static func IsReachableInheritedMember(level: int, inheritedProtected: bool, friendAdmits: bool): bool {
        return MemberAccessibility.IsAccessible(level, false, inheritedProtected, inheritedProtected, friendAdmits)
    }

    // A property has no accessibility of its own: its accessors do, and the more visible of the two
    // is what a reader may reach it through.
    static func PropertyAccessibilityLevel(property: PropertyInfo): int {
        getterLevel := MemberAccessibility.LevelOfMethod(property.GetGetMethod(true))
        setterLevel := MemberAccessibility.LevelOfMethod(property.GetSetMethod(true))
        if setterLevel > getterLevel {
            return setterLevel
        }

        return getterLevel
    }

    // DOES THE ASSEMBLY THAT DECLARES THIS TYPE MAKE THIS COMPILATION A FRIEND? The same one-line
    // question `AnalyzerMemberResolution.FriendAdmits` asks, against the same owner: a completion
    // with no grants behind it (no project, or a snapshot built without a compilation) answers no,
    // which is the behaviour that existed before friends did.
    static func FriendAdmits(grants: InternalsVisibleToGrants?, owner: Type?): bool {
        if grants == null || owner == null {
            return false
        }

        return grants.SameAssemblyOrFriend(owner)
    }

    // The CLR type a receiver's `TypeInfo` should be reflected over, or null when there is none.
    // A type the analyzer already reflected answers itself; a simple or generic NAME is looked up
    // in the compiler-known tables below, because a completion must work before anything has been
    // loaded for it.
    static func ResolveCompletionReflectionType(typeInfo: TypeInfo): Type? {
        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type
        }

        simpleType := typeInfo as SimpleTypeInfo
        if simpleType != null {
            return KnownReceiverType(simpleType.Name)
        }

        genericType := typeInfo as GenericTypeInfo
        if genericType != null {
            return CloseKnownReceiverDefinition(genericType)
        }

        return null
    }

    // The arity gate and the close. A definition this file does not know, or one whose arity does
    // not match what the source wrote, is not an answer — and neither is a close that throws or one
    // the CLR poisons.
    static func CloseKnownReceiverDefinition(genericType: GenericTypeInfo): Type? {
        // THE NAME TABLE STILL ANSWERS FIRST, because the types it names are RUNTIME types and the
        // arguments below are runtime types too — closing a metadata-context definition over them
        // is what the CLR poisons. A receiver the table has never heard of — `Vector<int>`,
        // `EqualityComparer<string>` — falls through to the definition the analyzer already
        // resolved, RE-HOMED into this process's universe so the two halves match.
        genericDefinition := KnownReceiverGenericDefinition(genericType.Name)
        if genericDefinition == null {
            genericDefinition = ResolvedGenericDefinitionOrNull(genericType)
        }

        if genericDefinition == null {
            return null
        }

        count := genericType.TypeArguments.Count
        if genericDefinition.GetGenericArguments().Length != count {
            return null
        }

        arguments := new Type[](count)
        index := 0
        while index < count {
            arguments[index] = GetReflectionTypeArgumentOrObject(genericType.TypeArguments[index])
            index = index + 1
        }

        closed: Type? = null
        try {
            closed = genericDefinition.MakeGenericType(arguments)
        } catch {
            closed = null
        }

        if closed == null {
            return null
        }

        if AnalyzerClrTypeConversion.IsPoisonedMixedInstantiation(closed) {
            return null
        }

        return closed
    }

    // The open CLR definition a constructed `GenericTypeInfo` carries, RE-HOMED into this process's
    // reflection universe. The analyzer resolves it through a `MetadataLoadContext`, and a
    // definition from one universe cannot be closed over arguments from another — the CLR answers a
    // `TypeBuilderInstantiation` rather than throwing, which is what `IsPoisonedMixedInstantiation`
    // exists to catch. Re-homing by assembly-qualified name is what makes the two halves match; a
    // definition with no runtime counterpart answers null and the receiver simply offers nothing.
    static func ResolvedGenericDefinitionOrNull(genericType: GenericTypeInfo): Type? {
        definition := genericType.GenericDefinition as ReflectionTypeInfo
        if definition == null {
            return null
        }

        candidate := definition.Type
        if candidate == null || !candidate.get_IsGenericTypeDefinition() {
            return null
        }

        qualifiedName := candidate.get_AssemblyQualifiedName()
        if qualifiedName != null {
            rehomed: Type? = null
            try {
                rehomed = Type.GetType(qualifiedName, false)
            } catch {
                rehomed = null
            }

            if rehomed != null && rehomed.get_IsGenericTypeDefinition() {
                return rehomed
            }
        }

        fullName := candidate.get_FullName()
        if fullName != null {
            named: Type? = null
            try {
                named = Type.GetType(fullName, false)
            } catch {
                named = null
            }

            if named != null && named.get_IsGenericTypeDefinition() {
                return named
            }
        }

        return null
    }

    // A type ARGUMENT is never allowed to fail the close by being absent: an argument this file
    // cannot spell becomes `object`, which is the widest thing every definition accepts. This table
    // is deliberately WIDER than the receiver table above — a receiver must be one of eleven named
    // types to be reflected at all, but any of the sixteen built-ins may appear inside one.
    static func GetReflectionTypeArgumentOrObject(typeInfo: TypeInfo): Type {
        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type
        }

        simpleType := typeInfo as SimpleTypeInfo
        if simpleType != null {
            argument := KnownArgumentType(simpleType.Name)
            if argument != null {
                return argument
            }
        }

        return typeof(object)
    }

    // The receivers a completion knows how to reflect over by NAME, in both the N# spelling and the
    // CLR one. Anything else is not a reflection receiver.
    //
    // `Console` and `Math` are loaded by METADATA NAME rather than written as `typeof(Console)`,
    // because `typeof` OF A STATIC CLASS DOES NOT EMIT — measured, not assumed, and it is the type
    // being `abstract sealed` that decides, not which assembly it lives in. `System.Math` is in the
    // core library so its name resolves unqualified; `System.Console` is not, so its name carries
    // its assembly. Both answer the same `Type` object `typeof` would have, and the contracts pin
    // that identity against the live `typeof` from the C# side.
    static func KnownReceiverType(name: string): Type? {
        if name == "string" || name == "System.String" {
            return typeof(string)
        }
        if name == "int" || name == "System.Int32" {
            return typeof(int)
        }
        if name == "long" || name == "System.Int64" {
            return typeof(long)
        }
        if name == "bool" || name == "System.Boolean" {
            return typeof(bool)
        }
        if name == "double" || name == "System.Double" {
            return typeof(double)
        }
        if name == "float" || name == "System.Single" {
            return typeof(float)
        }
        if name == "char" || name == "System.Char" {
            return typeof(char)
        }
        if name == "object" || name == "System.Object" {
            return typeof(object)
        }
        if name == "Console" || name == "System.Console" {
            return Type.GetType("System.Console, System.Console")
        }
        if name == "Math" || name == "System.Math" {
            return Type.GetType("System.Math")
        }
        if name == "DateTime" || name == "System.DateTime" {
            return typeof(DateTime)
        }

        return null
    }

    // The sixteen built-ins a TYPE ARGUMENT may be written as.
    static func KnownArgumentType(name: string): Type? {
        if name == "string" || name == "System.String" {
            return typeof(string)
        }
        if name == "int" || name == "System.Int32" {
            return typeof(int)
        }
        if name == "long" || name == "System.Int64" {
            return typeof(long)
        }
        if name == "bool" || name == "System.Boolean" {
            return typeof(bool)
        }
        if name == "double" || name == "System.Double" {
            return typeof(double)
        }
        if name == "float" || name == "System.Single" {
            return typeof(float)
        }
        if name == "char" || name == "System.Char" {
            return typeof(char)
        }
        if name == "object" || name == "System.Object" {
            return typeof(object)
        }
        if name == "decimal" || name == "System.Decimal" {
            return typeof(decimal)
        }
        if name == "byte" || name == "System.Byte" {
            return typeof(byte)
        }
        if name == "short" || name == "System.Int16" {
            return typeof(short)
        }
        if name == "uint" || name == "System.UInt32" {
            return typeof(uint)
        }
        if name == "ulong" || name == "System.UInt64" {
            return typeof(ulong)
        }
        if name == "ushort" || name == "System.UInt16" {
            return typeof(ushort)
        }
        if name == "sbyte" || name == "System.SByte" {
            return typeof(sbyte)
        }

        return null
    }

    // The generic definitions a completion knows how to close, in both spellings. The four
    // collection interfaces and the two awaitables are here because a receiver is very often typed
    // as one of them rather than as the concrete type.
    //
    // EVERY DEFINITION IS LOADED BY METADATA NAME, and that is one uniform rule rather than fifteen
    // spellings picked one at a time. An OPEN `typeof(List<>)` DOES NOT PARSE and several of the
    // closed forms do not EMIT, so a `typeof`-based table would be a minefield of special cases
    // whose membership only a build can tell you. A metadata name is the same runtime `Type` object
    // in every case — the contracts pin all fifteen against the live `typeof` — and it says out
    // loud which assembly each definition really lives in: everything here is core-library or
    // forwarded to it EXCEPT `Stack`, which is in `System.Collections` and so carries its assembly.
    static func KnownReceiverGenericDefinition(name: string): Type? {
        if name == "List" || name == "System.Collections.Generic.List" {
            return Type.GetType("System.Collections.Generic.List`1")
        }
        if name == "IEnumerable" || name == "System.Collections.Generic.IEnumerable" {
            return Type.GetType("System.Collections.Generic.IEnumerable`1")
        }
        if name == "ICollection" || name == "System.Collections.Generic.ICollection" {
            return Type.GetType("System.Collections.Generic.ICollection`1")
        }
        if name == "IList" || name == "System.Collections.Generic.IList" {
            return Type.GetType("System.Collections.Generic.IList`1")
        }
        if name == "IReadOnlyCollection" || name == "System.Collections.Generic.IReadOnlyCollection" {
            return Type.GetType("System.Collections.Generic.IReadOnlyCollection`1")
        }
        if name == "IReadOnlyList" || name == "System.Collections.Generic.IReadOnlyList" {
            return Type.GetType("System.Collections.Generic.IReadOnlyList`1")
        }
        if name == "Dictionary" || name == "System.Collections.Generic.Dictionary" {
            return Type.GetType("System.Collections.Generic.Dictionary`2")
        }
        if name == "IDictionary" || name == "System.Collections.Generic.IDictionary" {
            return Type.GetType("System.Collections.Generic.IDictionary`2")
        }
        if name == "IReadOnlyDictionary" || name == "System.Collections.Generic.IReadOnlyDictionary" {
            return Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
        }
        if name == "HashSet" || name == "System.Collections.Generic.HashSet" {
            return Type.GetType("System.Collections.Generic.HashSet`1")
        }
        if name == "Queue" || name == "System.Collections.Generic.Queue" {
            return Type.GetType("System.Collections.Generic.Queue`1")
        }
        if name == "Stack" || name == "System.Collections.Generic.Stack" {
            return Type.GetType("System.Collections.Generic.Stack`1, System.Collections")
        }
        if name == "Nullable" || name == "System.Nullable" {
            return Type.GetType("System.Nullable`1")
        }
        if name == "Task" || name == "System.Threading.Tasks.Task" {
            return Type.GetType("System.Threading.Tasks.Task`1")
        }
        if name == "ValueTask" || name == "System.Threading.Tasks.ValueTask" {
            return Type.GetType("System.Threading.Tasks.ValueTask`1")
        }

        return null
    }

    // THE READ. Methods, then properties, then fields — that order is what the caller groups by
    // kind, so it is the order a completion list comes out in.
    //
    // The `System.Object` skip is ASYMMETRIC ON PURPOSE: a property or field that `System.Object`
    // declares is dropped, a METHOD is not. That is why `GetType` appears in a `string` receiver's
    // methods; dropping it would silently narrow what the completion offers.
    static func BuildReflectionMemberItems(clrType: Type, flags: BindingFlags): List<CompletionItem> {
        return BuildReflectionMemberItems(clrType, flags, false)
    }

    static func BuildReflectionMemberItems(clrType: Type, flags: BindingFlags, inheritedProtected: bool): List<CompletionItem> {
        return BuildReflectionMemberItems(clrType, flags, inheritedProtected, false)
    }

    static func BuildReflectionMemberItems(clrType: Type, flags: BindingFlags, inheritedProtected: bool, friendAdmits: bool): List<CompletionItem> {
        return BuildReflectionMemberItems(clrType, flags, inheritedProtected, friendAdmits, null)
    }

    // CLR reflection walks a class hierarchy for these three APIs but deliberately does not walk an
    // interface hierarchy. An `IReadOnlyList<string>` read therefore returned `Item` and omitted the
    // inherited `IReadOnlyCollection<string>.Count`. Read each direct interface edge explicitly,
    // preserving the closed CLR type at every hop and using the same accessibility relation for the
    // declaring interface that supplied the member.
    static func BuildReflectionMemberItems(clrType: Type, flags: BindingFlags, inheritedProtected: bool, friendAdmits: bool, friendGrants: InternalsVisibleToGrants?): List<CompletionItem> {
        items := new List<CompletionItem>()
        seen := new List<Type>()
        AppendReflectionInterfaceClosure(clrType, flags, inheritedProtected, friendAdmits, friendGrants, items, seen, 0)
        return items
    }

    static func AppendReflectionInterfaceClosure(clrType: Type, flags: BindingFlags, inheritedProtected: bool, friendAdmits: bool, friendGrants: InternalsVisibleToGrants?, items: List<CompletionItem>, seen: List<Type>, depth: int) {
        if depth >= 64 || ContainsExactReflectionType(seen, clrType) {
            return
        }

        seen.Add(clrType)
        AppendNewReflectionMemberItems(items, BuildDeclaredReflectionMemberItems(clrType, flags, inheritedProtected, friendAdmits))
        if !clrType.get_IsInterface() {
            return
        }

        interfaces := DirectReflectionInterfaces(clrType)
        filter := ReflectionFilterFromFlags(flags)
        index := 0
        while index < interfaces.Count {
            baseInterface := interfaces[index]
            baseFriendAdmits := friendAdmits
            if friendGrants != null {
                baseFriendAdmits = FriendAdmits(friendGrants, baseInterface)
            }

            baseFlags := GetReflectionBindingFlags(filter, inheritedProtected, baseFriendAdmits)
            AppendReflectionInterfaceClosure(baseInterface, baseFlags, inheritedProtected, baseFriendAdmits, friendGrants, items, seen, depth + 1)
            index = index + 1
        }
    }

    // The immediate parents of an interface are the closure returned by `GetInterfaces` minus every
    // interface another closure member already reaches. This preserves nearest-first hiding without
    // assigning meaning to reflection's transitive enumeration order.
    static func DirectReflectionInterfaces(clrType: Type): List<Type> {
        direct := new List<Type>()
        interfaces: Type[] = new Type[](0)
        try {
            interfaces = clrType.GetInterfaces()
        } catch {
            return direct
        }

        candidateIndex := 0
        while candidateIndex < interfaces.Length {
            candidate := interfaces[candidateIndex]
            indirect := false
            otherIndex := 0
            while otherIndex < interfaces.Length && !indirect {
                if otherIndex != candidateIndex {
                    inheritedByOther: Type[] = new Type[](0)
                    try {
                        inheritedByOther = interfaces[otherIndex].GetInterfaces()
                    } catch {
                        inheritedByOther = new Type[](0)
                    }

                    inheritedIndex := 0
                    while inheritedIndex < inheritedByOther.Length {
                        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(candidate, inheritedByOther[inheritedIndex]) {
                            indirect = true
                            inheritedIndex = inheritedByOther.Length
                        } else {
                            inheritedIndex = inheritedIndex + 1
                        }
                    }
                }

                otherIndex = otherIndex + 1
            }

            if !indirect {
                direct.Add(candidate)
            }

            candidateIndex = candidateIndex + 1
        }

        return direct
    }

    static func ContainsExactReflectionType(seen: List<Type>, candidate: Type): bool {
        index := 0
        while index < seen.Count {
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(seen[index], candidate) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ReflectionFilterFromFlags(flags: BindingFlags): CompletionMemberFilter {
        hasStatic := (flags & BindingFlags.Static) == BindingFlags.Static
        hasInstance := (flags & BindingFlags.Instance) == BindingFlags.Instance
        if hasStatic && hasInstance {
            return CompletionMemberFilter.All
        }

        if hasStatic {
            return CompletionMemberFilter.StaticOnly
        }

        return CompletionMemberFilter.InstanceOnly
    }

    // A derived interface's declaration wins over a member it inherits, and a shared diamond base
    // wins once. Do not de-duplicate candidates from the SAME declaring interface here: overload
    // accounting remains the direct reader's existing responsibility.
    static func AppendNewReflectionMemberItems(items: List<CompletionItem>, candidates: List<CompletionItem>) {
        seen := new HashSet<string>(StringComparer.Ordinal)
        existingIndex := 0
        while existingIndex < items.Count {
            seen.Add(items[existingIndex].Name)
            existingIndex = existingIndex + 1
        }

        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            if !seen.Contains(candidate.Name) {
                items.Add(candidate)
            }

            candidateIndex = candidateIndex + 1
        }
    }

    // THE DIRECT READ. Methods, then properties, then fields — that order is what the caller groups
    // by kind, so it is the order a completion list comes out in.
    //
    // The `System.Object` skip is ASYMMETRIC ON PURPOSE: a property or field that `System.Object`
    // declares is dropped, a METHOD is not. That is why `GetType` appears in a `string` receiver's
    // methods; dropping it would silently narrow what the completion offers.
    static func BuildDeclaredReflectionMemberItems(clrType: Type, flags: BindingFlags, inheritedProtected: bool, friendAdmits: bool): List<CompletionItem> {
        names := new List<string>()
        kinds := new List<string>()
        typeTexts := new List<string>()
        isStaticValues := new List<bool>()

        // EVERY REFLECTED MEMBER IS READ THROUGH THE LOOP'S OWN BINDING, never through an index.
        //
        // ONE ROW PER NAME, AND THIS IS THE ONLY PLACE THAT CAN COUNT THEM. `GetMethods` hands back
        // one `MethodInfo` per OVERLOAD — `string` answers eleven `Split`s and ten `IndexOf`s — and
        // a completion row carries no parameter list to tell them apart with, so nothing downstream
        // could ever reconstruct the number. It is counted here, where the `MethodInfo`s are, and
        // travels on the row as `Overloads`; the first overload's return type is the one shown,
        // which is the row the reader would have seen first anyway.
        overloads := new List<int>()
        indexByName := new Dictionary<string, int>(StringComparer.Ordinal)
        methods := clrType.GetMethods(flags)
        for method in methods {
            if IsOfferableMethod(method) && IsReachableInheritedMember(MemberAccessibility.LevelOfMethod(method), inheritedProtected, friendAdmits) {
                methodName := method.get_Name()
                existingIndex := 0
                if indexByName.TryGetValue(methodName, out existingIndex) {
                    overloads[existingIndex] = overloads[existingIndex] + 1
                } else {
                    indexByName.Add(methodName, names.Count)
                    names.Add(methodName)
                    kinds.Add("method")
                    typeTexts.Add(CompletionTypeTextFacts.FormatClrTypeText(method.get_ReturnType()))
                    isStaticValues.Add(method.get_IsStatic())
                    overloads.Add(1)
                }
            }
        }

        properties := clrType.GetProperties(flags)
        for property in properties {
            if !DeclaredBySystemObject(property.get_DeclaringType()) && IsReachableInheritedMember(PropertyAccessibilityLevel(property), inheritedProtected, friendAdmits) {
                names.Add(property.get_Name())
                kinds.Add("property")
                typeTexts.Add(CompletionTypeTextFacts.FormatClrTypeText(property.get_PropertyType()))
                isStaticValues.Add(PropertyIsStatic(property))
                overloads.Add(1)
            }
        }

        fields := clrType.GetFields(flags)
        for field in fields {
            if !DeclaredBySystemObject(field.get_DeclaringType()) && IsReachableInheritedMember(MemberAccessibility.LevelOfField(field), inheritedProtected, friendAdmits) {
                names.Add(field.get_Name())
                kinds.Add("field")
                typeTexts.Add(CompletionTypeTextFacts.FormatClrTypeText(field.get_FieldType()))
                isStaticValues.Add(field.get_IsStatic())
                overloads.Add(1)
            }
        }

        return CompletionEngineKernels.BuildMemberItemsFromRows(names.ToArray(), kinds.ToArray(), typeTexts.ToArray(), isStaticValues.ToArray(), overloads.ToArray())
    }

    // A METHOD A CALLER COULD ACTUALLY WRITE. The CLR compiles a property into a pair of ordinary
    // methods and an operator into another, and `GetMethods` hands all of them back — so a `string`
    // receiver reflected raw offers `get_Length` beside `Length` and `op_Equality` beside nothing a
    // reader would recognise. `IsSpecialName` is the platform's own flag for exactly that class of
    // member: the compiler sets it on every accessor, operator and event hook it synthesises, and on
    // nothing a person declared by that name. Reading the flag rather than matching a `get_`/`set_`
    // PREFIX is the whole point — a user is entitled to declare a method called `get_Total`, and a
    // prefix test would hide it.
    //
    // The property or field itself is unaffected: it is read from `GetProperties`/`GetFields` below
    // and keeps its own name, so this removes the duplicate spelling and never the member.
    static func IsOfferableMethod(method: MethodInfo): bool {
        return !method.get_IsSpecialName()
    }

    // A FULL-NAME compare and not a `Type` identity one, so it holds for a type read through a
    // `MetadataLoadContext` exactly as it does for its runtime twin.
    static func DeclaredBySystemObject(declaringType: Type?): bool {
        if declaringType == null {
            return false
        }

        return declaringType.get_FullName() == "System.Object"
    }

    // A property with no getter is not static — it is unreadable, and the original chose `false`
    // rather than consulting the setter. Preserved.
    static func PropertyIsStatic(property: PropertyInfo): bool {
        getter := property.get_GetMethod()
        if getter == null {
            return false
        }

        return getter.get_IsStatic()
    }
}
