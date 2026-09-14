namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// NAMED ARGUMENTS, from the name a call wrote to the slot the signature keeps it in.
//
// A named argument names a PARAMETER: `Retry(attempts: 3)` says nothing about where `attempts` sits
// in the signature, only that this value is its. The parser records the name as a kind-60 wrapper
// around the argument it names (ColumnarParserKernels' NamedArgumentExpression), and everything
// below this owner -- overload scoring, conversions, IL -- is positional. So exactly one thing has
// to happen between them: each written argument has to be moved into the slot its parameter
// occupies, and the columns that describe it (its type, its literal facts, the node to emit) have to
// move with it, because they are all indexed by the same slot.
//
// THE PLACEMENT RULE IS THE ANALYZER'S, and it is deliberately the same one AnalyzerSyntheticCallBinder
// applies at the front door: a NAMED argument binds to the parameter it names, wherever it is written;
// a POSITIONAL argument fills the next parameter nothing has claimed yet. A name that no parameter
// carries, a parameter claimed twice, and a parameter left with nothing are all reported there, with
// the sentence and the fix-it. Here they only mean the placement could not be made, and the call is
// declined rather than mis-bound -- the backend never invents a placement the front door rejected.
//
// EVALUATION ORDER IS THE WRITTEN ORDER. `Send(body: Build(), to: Lookup())` runs `Build()` first
// because it is written first, even though `to` is the earlier parameter. The binder therefore
// answers two things, not one: the slot each argument belongs in, and the order the arguments were
// written in. A caller that finds RequiresReorder true evaluates along the written order into
// temporaries and hands the values over in slot order; when the two orders agree -- which is every
// call whose names were written where the signature keeps them -- there is nothing to spill.
class ColumnarNamedArgumentBinder {

    // THE KIND THE PARSER WRAPS A NAMED ARGUMENT IN: `name: value`, the parameter name in the value
    // span and the argument it names as its one child.
    static func NamedArgumentKind(): int {
        return 60
    }

    static func IsNamedArgument(nodes: ColumnarNodeTable, node: int): bool {
        return nodes != null && node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == NamedArgumentKind() && nodes.ChildCount(node) == 1
    }

    // The argument a call child really carries: the child itself, or -- when it was written with a
    // name -- the argument underneath the name.
    static func ArgumentValueNode(nodes: ColumnarNodeTable, node: int): int {
        if IsNamedArgument(nodes, node) {
            return nodes.Child(node, 0)
        }

        return node
    }

    // The parameter name written in front of an argument, or null when it was written positionally.
    static func ArgumentName(nodes: ColumnarNodeTable, source: string, node: int): string? {
        if !IsNamedArgument(nodes, node) || source == null {
            return null
        }

        return nodes.Text(source, node)
    }

    // Whether any of a call's `argumentCount` arguments -- the children from `firstArgumentOrdinal`
    // on -- was written with a name.
    static func HasNamedArgument(nodes: ColumnarNodeTable, callNode: int, firstArgumentOrdinal: int, argumentCount: int): bool {
        if nodes == null || callNode < 0 || callNode >= nodes.Kinds.Length {
            return false
        }

        index := 0
        while index < argumentCount {
            if IsNamedArgument(nodes, nodes.Child(callNode, firstArgumentOrdinal + index)) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ContainsNamedArgument(nodes: ColumnarNodeTable, callNode: int, firstArgumentOrdinal: int): bool {
        if nodes == null || callNode < 0 || callNode >= nodes.Kinds.Length {
            return false
        }

        return HasNamedArgument(nodes, callNode, firstArgumentOrdinal, nodes.ChildCount(callNode) - firstArgumentOrdinal)
    }

    // The index of `name` in `parameterNames`, or -1 when no parameter carries it. Parameter names
    // are ordinal-compared: they are CLR identifiers, and a call that writes `Value` for `value` has
    // named a parameter that does not exist.
    static func ParameterIndexOf(parameterNames: string[], name: string): int {
        if parameterNames == null || name == null {
            return -1
        }

        index := 0
        while index < parameterNames.Length {
            if String.Equals(parameterNames[index], name, StringComparison.Ordinal) {
                return index
            }

            index = index + 1
        }

        return -1
    }

    // Place `argumentCount` written arguments onto `parameterCount` slots by the rule above.
    // `slotForWrittenArgument[w]` is the slot written argument `w` claimed; every slot is claimed
    // exactly once, or the placement fails and the call is left to decline. A signature that carries
    // no names at all admits only positional arguments.
    static func TryPlace(nodes: ColumnarNodeTable, source: string, callNode: int, firstArgumentOrdinal: int, argumentCount: int, parameterNames: string[], parameterCount: int, out slotForWrittenArgument: int[]): bool {
        slotForWrittenArgument = new int[](0)
        if nodes == null || source == null || parameterNames == null || argumentCount != parameterCount || callNode < 0 || callNode >= nodes.Kinds.Length {
            return false
        }

        placements := new int[](argumentCount)
        claimedBy := new int[](parameterCount)
        slot := 0
        while slot < parameterCount {
            claimedBy[slot] = -1
            slot = slot + 1
        }

        nextPositionalSlot := 0
        written := 0
        while written < argumentCount {
            name := ArgumentName(nodes, source, nodes.Child(callNode, firstArgumentOrdinal + written))
            if name != null {
                named := ParameterIndexOf(parameterNames, name)
                if named < 0 || named >= parameterCount || claimedBy[named] >= 0 {
                    return false
                }

                claimedBy[named] = written
                placements[written] = named
                written = written + 1
                continue
            }

            while nextPositionalSlot < parameterCount && claimedBy[nextPositionalSlot] >= 0 {
                nextPositionalSlot = nextPositionalSlot + 1
            }

            if nextPositionalSlot >= parameterCount {
                return false
            }

            claimedBy[nextPositionalSlot] = written
            placements[written] = nextPositionalSlot
            nextPositionalSlot = nextPositionalSlot + 1
            written = written + 1
        }

        unclaimed := 0
        while unclaimed < parameterCount {
            if claimedBy[unclaimed] < 0 {
                return false
            }

            unclaimed = unclaimed + 1
        }

        slotForWrittenArgument = placements
        return true
    }

    // Move the already-computed argument rows into the slots `slotForWrittenArgument` assigned, in
    // place. Every column moves together, so a planner that reads `argumentTypes[slot]` and
    // `facts.ArgumentNodes[slot]` afterwards sees the SIGNATURE's order with no further arithmetic.
    // The written order is kept in `facts.WrittenOrderSlots` for the evaluation-order rule.
    static func ApplyPlacement(argumentTypes: Type[], facts: ColumnarDirectCallArgumentFacts, slotForWrittenArgument: int[]): bool {
        if argumentTypes == null || facts == null || slotForWrittenArgument == null || slotForWrittenArgument.Length != argumentTypes.Length || facts.ArgumentNodes.Length != argumentTypes.Length {
            return false
        }

        count := argumentTypes.Length
        movedTypes := new Type[](count)
        movedNodes := new int[](count)
        movedUnsuffixed := new bool[](count)
        movedNegative := new bool[](count)
        movedValues := new long[](count)
        movedNull := new bool[](count)
        movedByRef := new bool[](count)
        movedArrayLiteral := new bool[](count)
        movedArrayMinimums := new long[](count)
        movedArrayMaximums := new long[](count)

        reorders := false
        written := 0
        while written < count {
            slot := slotForWrittenArgument[written]
            if slot < 0 || slot >= count {
                return false
            }

            if slot != written {
                reorders = true
            }

            movedTypes[slot] = argumentTypes[written]
            movedNodes[slot] = facts.ArgumentNodes[written]
            movedUnsuffixed[slot] = facts.IsUnsuffixedIntegerLiteral[written]
            movedNegative[slot] = facts.IsNegativeIntegerLiteral[written]
            movedValues[slot] = facts.IntegerLiteralValues[written]
            movedNull[slot] = facts.IsNullLiteral[written]
            movedByRef[slot] = facts.IsByRefArgument[written]
            movedArrayLiteral[slot] = facts.IsIntegerConstantArrayLiteral[written]
            movedArrayMinimums[slot] = facts.ArrayLiteralMinimumValues[written]
            movedArrayMaximums[slot] = facts.ArrayLiteralMaximumValues[written]
            written = written + 1
        }

        copy := 0
        while copy < count {
            argumentTypes[copy] = movedTypes[copy]
            facts.ArgumentNodes[copy] = movedNodes[copy]
            facts.IsUnsuffixedIntegerLiteral[copy] = movedUnsuffixed[copy]
            facts.IsNegativeIntegerLiteral[copy] = movedNegative[copy]
            facts.IntegerLiteralValues[copy] = movedValues[copy]
            facts.IsNullLiteral[copy] = movedNull[copy]
            facts.IsByRefArgument[copy] = movedByRef[copy]
            facts.IsIntegerConstantArrayLiteral[copy] = movedArrayLiteral[copy]
            facts.ArrayLiteralMinimumValues[copy] = movedArrayMinimums[copy]
            facts.ArrayLiteralMaximumValues[copy] = movedArrayMaximums[copy]
            facts.WrittenOrderSlots[copy] = slotForWrittenArgument[copy]
            copy = copy + 1
        }

        facts.RequiresReorder = reorders
        return true
    }

    // Bind a call's named arguments against one candidate signature and move the rows into its
    // order. Answers false -- leaving every column exactly as it was -- when the names do not place.
    static func TryBind(nodes: ColumnarNodeTable, source: string, callNode: int, firstArgumentOrdinal: int, parameterNames: string[], parameterCount: int, argumentTypes: Type[], facts: ColumnarDirectCallArgumentFacts): bool {
        placement := new int[](0)
        if !TryPlace(nodes, source, callNode, firstArgumentOrdinal, argumentTypes.Length, parameterNames, parameterCount, out placement) {
            return false
        }

        return ApplyPlacement(argumentTypes, facts, placement)
    }

    // The parameter names of a reflected method or constructor, in declaration order. A parameter
    // whose metadata carries no name cannot be named at a call, and answers the empty spelling.
    static func ReflectedParameterNames(method: MethodBase?): string[] {
        if method == null {
            return new string[](0)
        }

        parameters := method.GetParameters()
        names := new string[](parameters.Length)
        index := 0
        while index < parameters.Length {
            names[index] = parameters[index].get_Name() ?? ""
            index = index + 1
        }

        return names
    }

    // The parameter names of a reflected method with its FIRST parameter dropped -- the shape an
    // extension method is called in, where the receiver is written before the dot and the names a
    // call may write start one parameter in.
    static func ReflectedExtensionParameterNames(method: MethodBase?): string[] {
        declared := ReflectedParameterNames(method)
        if declared.Length == 0 {
            return declared
        }

        names := new string[](declared.Length - 1)
        index := 1
        while index < declared.Length {
            names[index - 1] = declared[index]
            index = index + 1
        }

        return names
    }

    // EVERY SIGNATURE THE CALL COULD REACH, by name and arity alone. A name PRUNES the overload set
    // long before types are scored -- `Encoding.GetString(bytes: b)` can only mean an overload that
    // has a `bytes` -- so the placement is asked of each candidate and the answer is accepted only
    // when every candidate that admits the names places them the same way. Two same-arity overloads
    // that spell their parameters differently and BOTH admit the written names would place the call
    // two ways; that call is ambiguous and is declined rather than guessed at.
    static func AddCandidate(candidates: List<string[]>, parameterNames: string[]?, arity: int) {
        if parameterNames == null || parameterNames.Length != arity || arity == 0 {
            return
        }

        for existing in candidates {
            same := true
            index := 0
            while index < arity {
                if !String.Equals(existing[index], parameterNames[index], StringComparison.Ordinal) {
                    same = false
                    break
                }

                index = index + 1
            }

            if same {
                return
            }
        }

        candidates.Add(parameterNames)
    }

    // The source instance methods named `memberName` at `arity`, walking the declaration's own base
    // chain exactly as instance selection does.
    static func CollectSourceInstanceParameterNames(definition: ColumnarStructDef?, memberName: string, arity: int, candidates: List<string[]>) {
        current := definition
        while current != null {
            single: ColumnarInstanceMethodDef? = null
            if current.Methods.TryGetValue(memberName, out single) {
                AddCandidate(candidates, single.ParamNames, arity)
            }

            overloads: List<ColumnarInstanceMethodDef>? = null
            if current.MethodOverloads.TryGetValue(memberName, out overloads) {
                for overload in overloads {
                    AddCandidate(candidates, overload.ParamNames, arity)
                }
            }

            current = current.BaseDef
        }
    }

    // The source static methods named `memberName` at `arity`, over the same chain.
    static func CollectSourceStaticParameterNames(definition: ColumnarStructDef?, memberName: string, arity: int, candidates: List<string[]>) {
        current := definition
        while current != null {
            statics: List<ColumnarStaticMethodDef>? = null
            if current.StaticMethods.TryGetValue(memberName, out statics) {
                for candidate in statics {
                    AddCandidate(candidates, candidate.ParamNames, arity)
                }
            }

            current = current.BaseDef
        }
    }

    // The source constructors of `definition` that could take `arity` written arguments. A
    // constructor with defaults is included at every arity it can be called at, because the names a
    // call may write are the same list either way.
    static func CollectSourceConstructorParameterNames(definition: ColumnarStructDef?, arity: int, candidates: List<string[]>) {
        if definition == null {
            return
        }

        for constructor in definition.Constructors {
            AddCandidate(candidates, constructor.ParamNames, arity)
        }
    }

    // THE SOURCE DECLARATION A RECEIVER TYPE BELONGS TO, by builder identity -- the plain emitted type
    // and the closed generic alike. A receiver that is not a source type at all answers null, and its
    // names come from metadata instead.
    static func FindReceiverDefinition(receiverType: Type?, definitions: IEnumerable<ColumnarStructDef>): ColumnarStructDef? {
        if receiverType == null || definitions == null {
            return null
        }

        if receiverType is System.Reflection.Emit.TypeBuilder {
            return ColumnarSourceDefinitionResolver.FindByBuilderIdentity(definitions, receiverType)
        }

        return ColumnarGenericTypeReceiverFacts.FindSourceDefinition(receiverType, definitions)
    }

    // A TYPE STILL BEING EMITTED ANSWERS NO REFLECTION QUESTION -- `TypeBuilder.GetMethods()` throws
    // "the invoked member is not supported before the type is created". A source type's parameter
    // names are carried on its own definitions instead, which is what the collectors above read, so
    // the reflected collectors simply have nothing to say about one.
    static func IsReflectable(candidate: Type?): bool {
        return candidate != null && !(candidate is System.Reflection.Emit.TypeBuilder) && !candidate.get_IsGenericParameter()
    }

    // The reflected members of `ownerType` named `memberName` at `arity`, including those it
    // inherits. `Type.GetMethods()` already walks the base chain for public members, which is the
    // only visibility an external call can reach.
    static func CollectReflectedParameterNames(ownerType: Type?, memberName: string, arity: int, requireStatic: bool, candidates: List<string[]>) {
        if !IsReflectable(ownerType) || memberName == null || arity == 0 {
            return
        }

        for method in ownerType.GetMethods() {
            if method.get_Name() != memberName || method.get_IsStatic() != requireStatic || method.GetParameters().Length != arity {
                continue
            }

            AddCandidate(candidates, ReflectedParameterNames(method), arity)
        }
    }

    // The reflected constructors of `ownerType` that take `arity` arguments.
    static func CollectReflectedConstructorParameterNames(ownerType: Type?, arity: int, candidates: List<string[]>) {
        if !IsReflectable(ownerType) || arity == 0 {
            return
        }

        for constructor in ownerType.GetConstructors() {
            if constructor.GetParameters().Length != arity {
                continue
            }

            AddCandidate(candidates, ReflectedParameterNames(constructor), arity)
        }
    }

    // Place the call's arguments against the gathered candidates and move the argument rows into the
    // agreed order. False means the call keeps the order it was written in and its named arguments
    // are still un-bound, which is what the planner declines on.
    static func TryBindAgreedPlacement(nodes: ColumnarNodeTable, source: string, callNode: int, firstArgumentOrdinal: int, candidates: List<string[]>, argumentTypes: Type[], facts: ColumnarDirectCallArgumentFacts): bool {
        if candidates == null || candidates.Count == 0 {
            return false
        }

        agreed := new int[](0)
        found := false
        for candidate in candidates {
            placement := new int[](0)
            if !TryPlace(nodes, source, callNode, firstArgumentOrdinal, argumentTypes.Length, candidate, candidate.Length, out placement) {
                continue
            }

            if !found {
                agreed = placement
                found = true
                continue
            }

            index := 0
            while index < placement.Length {
                if placement[index] != agreed[index] {
                    return false
                }

                index = index + 1
            }
        }

        if !found || !ApplyPlacement(argumentTypes, facts, agreed) {
            return false
        }

        FlattenPlacedArguments(nodes, callNode, firstArgumentOrdinal, argumentTypes.Length, facts)
        return true
    }

    // A VERIFIED IN-POSITION PLACEMENT IS FLATTENED INTO THE NODE TABLE. Once the names have been
    // checked against a real signature and found to name the parameters they were already written
    // at, the wrappers carry no information at all -- so they are removed, and a call the planner
    // ends up declining for some unrelated reason (a lambda argument, say) reaches the residual
    // emitter as the ordinary positional call it is. A placement that MOVES an argument is left
    // alone: only the planner can emit that, because only it spills the written order.
    static func FlattenPlacedArguments(nodes: ColumnarNodeTable, callNode: int, firstArgumentOrdinal: int, argumentCount: int, facts: ColumnarDirectCallArgumentFacts) {
        if facts.RequiresReorder {
            return
        }

        index := 0
        while index < argumentCount {
            nodes.SetChild(callNode, firstArgumentOrdinal + index, facts.ArgumentNodes[index])
            index = index + 1
        }
    }
}
