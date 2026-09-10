namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// THE ONE OWNER OF "WHAT TYPE DOES A `Name<Args>.` RECEIVER NAME".
//
// The parser kernel commits a kind-70 node for `Vector<int>.Count`, `EqualityComparer<int>.Default`
// and `Box<int>.Create(42)`: the full dotted head name in the value span, the TYPE-kernel
// type-argument roots as children. Turning that into a live `System.Type` is the same two-stage walk
// `typeof` already uses — the subtree becomes a canonical string, and the SCOPED catalog turns the
// string into a type — so the canonical builder is `ColumnarTypeOfPlanner.TryBuildTypeCanonical` and
// the resolver is `ColumnarBindingScopeFacts.TryResolveExactExplicitTypeInContext`, which already
// closes a constructed generic through `MakeGenericType` for `typeof(List<int>)` and for an explicit
// call type argument. NOTHING here is specific to any BCL type: there is no name table, no arity
// table and no per-API modelling — the head resolves through ordinary scoped type resolution or the
// receiver declines.
//
// THE SOURCE-CLAIMED ANSWER IS REPORTED SEPARATELY, NOT SWALLOWED. A receiver over a USER-declared
// generic (`Box<int>.Create`) resolves to a `TypeBuilder` INSTANTIATION, whose reflection surface is
// not the runtime one: `GetField`/`GetProperty`/`GetMethod` throw on it, and every member handle must
// be rebound through `TypeBuilder.GetField`/`GetMethod`. The two are therefore separate answers, not
// one: `TryResolveReceiverType` reports only the RUNTIME shape (and says `claimedBySource` when it
// declined because the head was a source type), while `TryResolveSourceReceiverType` reports the
// constructed SOURCE shape for the source member owners to resolve against.
class ColumnarGenericTypeReceiverFacts {
    static func IsReceiver(nodes: ColumnarNodeTable, node: int): bool {
        return nodes != null && node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.GenericTypeReceiverExpression()
    }

    // `Vector<int>` / `Dictionary<string,List<int>>` — the canonical spelling the scoped catalog
    // parses. It is assembled from the head name plus each argument's own canonical, which is exactly
    // what the type kernel's kind-1 arm does for an annotation, so a receiver and an annotation over
    // the same written text produce the same string.
    static func TryBuildCanonical(nodes: ColumnarNodeTable, source: string, node: int, out canonical: string): bool {
        canonical = ""
        if !IsReceiver(nodes, node) || source == null || nodes.ChildCount(node) <= 0 {
            return false
        }

        head := nodes.Text(source, node)
        if head == null || head.Length == 0 {
            return false
        }

        builder := head + "<"
        index := 0
        while index < nodes.ChildCount(node) {
            argument := ""
            if !ColumnarTypeOfPlanner.TryBuildTypeCanonical(nodes, source, nodes.Child(node, index), 0, out argument) {
                return false
            }

            if index > 0 {
                builder = builder + ","
            }

            builder = builder + argument
            index = index + 1
        }

        canonical = builder + ">"
        return true
    }

    // The head's ROOT segment — `System` of `System.Numerics.Vector`, `Vector` of `Vector` — which is
    // the name the shadowing fences are asked about, exactly as the non-generic static-member and
    // direct-call owners ask about theirs.
    static func RootName(nodes: ColumnarNodeTable, source: string, node: int): string {
        if !IsReceiver(nodes, node) || source == null {
            return ""
        }

        head := nodes.Text(source, node)
        if head == null {
            return ""
        }

        separator := head.IndexOf(".", StringComparison.Ordinal)
        if separator < 0 {
            return head
        }

        return head.Substring(0, separator)
    }

    static func TryResolveReceiverType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resolved: Type, out claimedBySource: bool): bool {
        resolved = typeof(object)
        claimedBySource = false
        if !IsReceiver(nodes, node) || bindings == null {
            return false
        }

        rootName := RootName(nodes, source, node)
        if rootName.Length == 0 || bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || nodes.HasAdditionalRootBinding(rootName) {
            return false
        }

        canonical := ""
        if !TryBuildCanonical(nodes, source, node, out canonical) {
            return false
        }

        scope := nodes.BindingScope
        if scope == null {
            return false
        }

        candidate := typeof(object)
        claimed := false
        if !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out candidate, out claimed) {
            claimedBySource = claimed
            return false
        }

        // A source-claimed head is a USER-declared generic type. Its constructed form is a
        // `TypeBuilder` instantiation, which does not answer the runtime member queries this
        // resolver's callers make, so it is reported as claimed-but-not-runtime and belongs to
        // `TryResolveSourceReceiverType` instead.
        if claimed {
            claimedBySource = true
            return false
        }

        resolved = candidate
        return true
    }

    // THE CONSTRUCTED SOURCE TYPE A `Name<Args>.` RECEIVER NAMES — `Box<int>`, `Result<int, string>`.
    // Same canonical spelling and same scoped resolution as the runtime answer above; the only
    // difference is which of the two shapes is being asked for, so an EXTERNAL head declines here
    // exactly as a source head declines there. The result is a closed instantiation over the open
    // `TypeBuilder`, which is what `ColumnarSourceDirectCallResolver` and the source member owners
    // already classify as a closed source receiver.
    static func TryResolveSourceReceiverType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resolved: Type): bool {
        resolved = typeof(object)
        if !IsReceiver(nodes, node) || bindings == null {
            return false
        }

        rootName := RootName(nodes, source, node)
        if rootName.Length == 0 || bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || nodes.HasAdditionalRootBinding(rootName) {
            return false
        }

        canonical := ""
        if !TryBuildCanonical(nodes, source, node, out canonical) {
            return false
        }

        scope := nodes.BindingScope
        if scope == null {
            return false
        }

        candidate := typeof(object)
        claimed := false
        if !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out candidate, out claimed) || !claimed {
            return false
        }

        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(candidate) {
            return false
        }

        resolved = candidate
        return true
    }

    // The source definition a constructed source receiver's head declares, or null. Identity is the
    // open `TypeBuilder`, never a name, so an alias or a same-spelled BCL type cannot answer here.
    static func FindSourceDefinition(receiverType: Type, definitions: IEnumerable<ColumnarStructDef>): ColumnarStructDef? {
        if receiverType == null || definitions == null || !ColumnarTypeOfPlanner.IsClosedSourceGeneric(receiverType) {
            return null
        }
        return ColumnarSourceDefinitionResolver.FindByBuilderIdentity(definitions, receiverType.GetGenericTypeDefinition())
    }

    // THE GENERAL STATIC READ. `GetField` / `GetProperty` with `Public | Static | DeclaredOnly`-free
    // flags over the CLOSED constructed type, which is ordinary CLR member resolution and reflects
    // the substituted member types for free — `Vector<int>.Zero` comes back as `Vector<int>` and
    // `EqualityComparer<int>.Default` as `EqualityComparer<int>` because that is what the closed
    // type's metadata says. An INSTANCE member reached through the type name answers nothing here,
    // so it declines rather than emitting a load with no receiver.
    static func TryResolveStaticField(receiverType: Type, memberName: string): FieldInfo? {
        if receiverType == null || memberName == null || memberName.Length == 0 {
            return null
        }

        field := receiverType.GetField(memberName, BindingFlags.Public | BindingFlags.Static)
        if field == null || !field.get_IsStatic() {
            return null
        }

        return field
    }

    static func TryResolveStaticGetter(receiverType: Type, memberName: string): MethodInfo? {
        if receiverType == null || memberName == null || memberName.Length == 0 {
            return null
        }

        property := receiverType.GetProperty(memberName, BindingFlags.Public | BindingFlags.Static)
        if property == null {
            return null
        }

        getter := property.GetGetMethod()
        if getter == null || !getter.get_IsStatic() || getter.GetParameters().Length != 0 {
            return null
        }

        return getter
    }
}
