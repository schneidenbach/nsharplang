namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic


// The two name lists a condition yields at EMIT: the names it proves NON-NULL when it is true, and
// the names it proves non-null when it is false. They travel together because a caller almost always
// needs both — the then-branch takes one, the else-branch takes the other, and a guard clause whose
// taken branch leaves hands the OPPOSITE one to the flow that survives it.
class ColumnarFlowNarrowingSplit {
    thenValue: List<string>
    elseValue: List<string>

    Then: List<string> => thenValue
    Else: List<string> => elseValue

    constructor(thenNames: List<string>, elseNames: List<string>) {
        thenValue = thenNames
        elseValue = elseNames
    }
}

// WHAT A CONDITION PROVES ABOUT A NAME, READ OFF THE NODE TABLE — the emit-side mirror of the
// diagnostics pass's `AnalyzerFlowNarrowing.ExtractFlowNarrowings`, and the reason the emitter can
// unwrap a `Nullable<T>` the analyzer already narrowed.
//
// THE ANALYZER'S ANSWER IS THE CONTRACT AND THIS IS THE SAME RULE OVER THE OTHER REPRESENTATION.
// `AnalyzerStatementTermination` and `ColumnarMethodBodyPlanner.AlwaysReturns` are already kept
// verbatim-identical for exactly this reason; the narrowing rule is the second pair, and the two are
// written against each other arm for arm. A shape the analyzer narrows and this does not is a
// DECLINE — never a wrong value — because the emitter then sees the declared `Nullable<T>` and
// refuses the operator, the return or the member read, which is what it did for every shape before
// this owner existed.
//
// THE FACTS ARE ABOUT STABLE PATHS, EXACTLY AS THE ANALYZER'S ARE. A path is what
// `AnalyzerDiagnosticSpanFacts.TryGetStableNullPath` answers — a bare name, `this`, and dotted member
// reads over those — spelled the same dotted way, so `h.Slot != null` proves `"h.Slot"` here for the
// same reason it files a null fact for `"h.Slot"` there. The unwrap the emitter writes does not need
// to ADDRESS the path's storage: it parks the value the ordinary read produced and calls `Value` on
// that, so a member path is as unwrappable as a local.
//
// IT IS NARROWER THAN THE ANALYZER'S, DELIBERATELY, AND IN ONE DIRECTION. The analyzer also records
// a narrowed TYPE for `is` patterns and the postconditions a call's signature states; those are not
// repeated here, and the price is a decline where the analyzer would have accepted. The OTHER
// direction is never allowed: a path this reader proves and the analyzer does not would have the
// emitter unwrap a value the program may legitimately read as null, and `Value` would throw. That is
// why every write shape below matches the analyzer's kill set, `ref`/`out` arguments included.
//
// THE NEGATION RULES ARE THE ANALYZER'S, STATED ONCE. A parenthesis is transparent; `!c` is `c` with
// the two lists swapped; `a && b` proves both sides in the TRUE branch and nothing in the false one
// (the negation of a conjunction is a disjunction), unless one operand is the constant `true`, which
// collapses it onto the other side; `a || b` is the mirror. `x != null` proves `x` in the true
// branch, `x == null` in the false one, and `x.HasValue` in the true one.
//
// NOTHING HERE IS EVALUATED. A condition whose value this reader cannot see on the syntax proves
// nothing in either direction, which is the safe answer: the worst an unproved name can cause is the
// decline that already existed.
class ColumnarFlowNarrowingFacts {
    static func Extract(nodes: ColumnarNodeTable, source: string, condition: int): ColumnarFlowNarrowingSplit {
        thenNames := new List<string>()
        elseNames := new List<string>()
        Collect(nodes, source, condition, thenNames, elseNames)
        return new ColumnarFlowNarrowingSplit(thenNames, elseNames)
    }

    static func Collect(nodes: ColumnarNodeTable, source: string, condition: int, thenNames: List<string>, elseNames: List<string>) {
        if nodes == null || source == null || condition < 0 || condition >= nodes.Kinds.Length {
            return
        }

        kind := nodes.Kind(condition)
        // 7 Parenthesized — transparent, exactly as the analyzer reads it.
        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression && nodes.ChildCount(condition) == 1 {
            Collect(nodes, source, nodes.Child(condition, 0), thenNames, elseNames)
            return
        }

        // 11 Unary — only `!`, and it is the two lists the other way round.
        if kind == ColumnarExpressionNodeKind.UnaryExpression && nodes.ChildCount(condition) == 1 {
            if ColumnarNodeTextFacts.Text(nodes, source, condition) == "!" {
                Collect(nodes, source, nodes.Child(condition, 0), elseNames, thenNames)
            }

            return
        }

        // 8 MemberAccess — `x.HasValue` proves `x` present in the true branch, exactly as `x != null`
        // does (the analyzer's `TryExtractHasValueNarrowing`), and `h.Slot.HasValue` proves the path
        // `h.Slot` by the same rule. What its false branch proves is that the path is ABSENT, which is
        // not a fact this reader collects, so nothing is filed there.
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression {
            if ColumnarNodeTextFacts.Text(nodes, source, condition) == "HasValue" && nodes.ChildCount(condition) == 1 {
                receiverPath := StablePath(nodes, source, nodes.Child(condition, 0))
                if receiverPath != null {
                    thenNames.Add(receiverPath)
                }
            }

            return
        }

        if kind != ColumnarExpressionNodeKind.BinaryExpression || nodes.ChildCount(condition) != 2 {
            return
        }

        left := nodes.Child(condition, 0)
        right := nodes.Child(condition, 1)
        op := ColumnarNodeTextFacts.Text(nodes, source, condition)
        if op == "==" || op == "!=" {
            notEqual := op == "!="
            CollectNullComparison(nodes, source, left, right, notEqual, thenNames, elseNames)
            CollectNullComparison(nodes, source, right, left, notEqual, thenNames, elseNames)
            return
        }

        if op == "&&" {
            leftSplit := Extract(nodes, source, left)
            rightSplit := Extract(nodes, source, right)
            thenNames.AddRange(leftSplit.Then)
            thenNames.AddRange(rightSplit.Then)
            if IsConstantTrue(nodes, source, left) {
                elseNames.AddRange(rightSplit.Else)
            } else if IsConstantTrue(nodes, source, right) {
                elseNames.AddRange(leftSplit.Else)
            }

            return
        }

        if op == "||" {
            leftSplit := Extract(nodes, source, left)
            rightSplit := Extract(nodes, source, right)
            elseNames.AddRange(leftSplit.Else)
            elseNames.AddRange(rightSplit.Else)
            if IsConstantFalse(nodes, source, left) {
                thenNames.AddRange(rightSplit.Then)
            } else if IsConstantFalse(nodes, source, right) {
                thenNames.AddRange(leftSplit.Then)
            }
        }
    }

    // One side of an equality against `null`. The OTHER side must be the literal (5), which is what
    // makes this callable twice with the operands swapped rather than needing to know which side the
    // reader wrote the literal on.
    //
    // A `?.` CHAIN TESTED ITS OWN RECEIVERS, and the comparison reports what those tests found — the
    // analyzer's `TryExtractNullNarrowing`, arm for arm. `h?.Slot == null` is true when `h` is null OR
    // `h.Slot` is, a disjunction, so only the side that rules both out proves anything, and it proves
    // every tested prefix as well as the path itself.
    static func CollectNullComparison(nodes: ColumnarNodeTable, source: string, value: int, other: int, notEqual: bool, thenNames: List<string>, elseNames: List<string>) {
        if other < 0 || other >= nodes.Kinds.Length || nodes.Kind(other) != ColumnarExpressionNodeKind.NullLiteralExpression {
            return
        }

        testedPrefixes := new List<string>()
        path := ChainPath(nodes, source, value, testedPrefixes)
        if path == null {
            return
        }

        proved := elseNames
        if notEqual {
            proved = thenNames
        }

        proved.AddRange(testedPrefixes)
        proved.Add(path)
    }

    // THE STABLE PATH A NODE DENOTES, or null — the node-table twin of the analyzer's
    // `TryGetStableNullPath`. A bare name, `this`, and a plain member read over a stable receiver, with
    // parentheses and `must` transparent because each denotes the storage its operand denotes. A `?.`
    // hop, a call and an index are not stable: re-reading them could run something or denote
    // something else, so no fact about them survives to the next read.
    static func StablePath(nodes: ColumnarNodeTable, source: string, node: int): string? {
        if node < 0 || node >= nodes.Kinds.Length {
            return null
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression && nodes.ChildCount(node) == 1 {
            receiverPath := StablePath(nodes, source, nodes.Child(node, 0))
            member := ColumnarNodeTextFacts.Text(nodes, source, node)
            if receiverPath == null || member.Length == 0 {
                return null
            }

            return receiverPath + "." + member
        }

        if kind == ColumnarExpressionNodeKind.ThisExpression && nodes.ChildCount(node) == 0 {
            return "this"
        }

        if (kind == ColumnarExpressionNodeKind.ParenthesizedExpression || kind == ColumnarExpressionNodeKind.MustExpression) && nodes.ChildCount(node) == 1 {
            return StablePath(nodes, source, nodes.Child(node, 0))
        }

        return SimpleName(nodes, source, node)
    }

    // THE PATH A `?.` CHAIN DENOTES, AND THE RECEIVERS IT TESTED ON THE WAY — the twin of the
    // analyzer's `TryGetNullConditionalChainPath`. `a?.B` denotes the storage `a.B` does; the null
    // guard (75) over its receiver is the TEST of `a`, recorded as a tested prefix. A chain with no
    // conditional hop yields exactly `StablePath` and no prefixes.
    static func ChainPath(nodes: ColumnarNodeTable, source: string, node: int, testedPrefixes: List<string>): string? {
        if node < 0 || node >= nodes.Kinds.Length {
            return null
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression && nodes.ChildCount(node) == 1 {
            return ChainPath(nodes, source, nodes.Child(node, 0), testedPrefixes)
        }

        if kind == ColumnarExpressionNodeKind.MustExpression && nodes.ChildCount(node) == 1 {
            return ChainPath(nodes, source, nodes.Child(node, 0), testedPrefixes)
        }

        if kind != ColumnarExpressionNodeKind.MemberAccessExpression || nodes.ChildCount(node) != 1 {
            return StablePath(nodes, source, node)
        }

        receiver := nodes.Child(node, 0)
        conditional := receiver >= 0 && receiver < nodes.Kinds.Length && nodes.Kind(receiver) == ColumnarExpressionNodeKind.NullGuardExpression && nodes.ChildCount(receiver) == 1
        if conditional {
            receiver = nodes.Child(receiver, 0)
        }

        receiverPath := ChainPath(nodes, source, receiver, testedPrefixes)
        member := ColumnarNodeTextFacts.Text(nodes, source, node)
        if receiverPath == null || member.Length == 0 {
            return null
        }

        if conditional {
            testedPrefixes.Add(receiverPath)
        }

        return receiverPath + "." + member
    }

    // WHETHER A NARROWED PATH IS `written` OR LIES UNDER IT. Writing `h` rewrites everything reached
    // through `h`, so `h.Slot` stops being known — the analyzer's `InvalidateNullFactsForAssignment`
    // prefix rule, stated over the same dotted spelling.
    static func IsInvalidatedBy(path: string, written: string): bool {
        return path == written || (path.Length > written.Length && path.StartsWith(written, System.StringComparison.Ordinal) && path[written.Length] == '.')
    }

    // A BARE NAME, THROUGH THE PARENTHESES THAT ARE TRANSPARENTLY IT. Only an identifier (6) with no
    // children names one binding; a declaration binds exactly such a name.
    static func SimpleName(nodes: ColumnarNodeTable, source: string, node: int): string? {
        if node < 0 || node >= nodes.Kinds.Length {
            return null
        }

        if nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression && nodes.ChildCount(node) == 1 {
            return SimpleName(nodes, source, nodes.Child(node, 0))
        }

        if nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression || nodes.ChildCount(node) != 0 {
            return null
        }

        name := ColumnarNodeTextFacts.Text(nodes, source, node)
        if name.Length == 0 {
            return null
        }

        return name
    }

    static func IsConstantTrue(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return ColumnarMethodBodyPlanner.IsConstantTrueConditionNode(nodes, source, node)
    }

    static func IsConstantFalse(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return ColumnarMethodBodyPlanner.IsConstantFalseConditionNode(nodes, source, node)
    }

    // EVERY PATH A STATEMENT SUBTREE WRITES. A narrowing is a statement about the value a path holds
    // NOW, so any write inside a region whose flow this reader cannot follow — a loop body, which runs
    // an unknown number of times and jumps backwards — ends it. Collecting the writes is what lets a
    // narrowing survive a loop that does not touch the path, which is the common case. A caller ends
    // every narrowing `IsInvalidatedBy` a collected write, so a write to `h` ends `h.Slot` too.
    //
    // THE WRITE SHAPES TRACK THE ANALYZER'S KILL SET (`AnalyzerLoopCarriedNullFacts`): an assignment
    // expression (14), a postfix/prefix step (44/11), and a `ref`/`out` argument (54), each named by
    // the STABLE PATH it targets. An `in` argument only reads its target. The emitter also tracks the
    // two declaration statements (24, 40), a deconstruction's names (30), and a `for x in xs` loop
    // variable (29/76/73), each of which binds a name anew. A method call on a receiver is NOT a write.
    static func CollectAssignedNames(nodes: ColumnarNodeTable, source: string, node: int, into: HashSet<string>) {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length || into == null {
            return
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.RefOutArgument && nodes.ChildCount(node) == 1 {
            modifier := ColumnarNodeTextFacts.Text(nodes, source, node)
            if modifier == "ref" || modifier == "out" {
                target := StablePath(nodes, source, nodes.Child(node, 0))
                if target != null {
                    into.Add(target)
                }
            }
        } else if kind == ColumnarStatementNodeKind.TupleDeconstructionStatement {
            nameIndex := 0
            while nameIndex < nodes.ChildCount(node) - 1 {
                name := ColumnarNodeTextFacts.Text(nodes, source, nodes.Child(node, nameIndex))
                if name.Length > 0 && name != "_" {
                    into.Add(name)
                }
                nameIndex = nameIndex + 1
            }
        } else if kind == ColumnarExpressionNodeKind.AssignmentExpression || kind == ColumnarExpressionNodeKind.PostfixUnary {
            if nodes.ChildCount(node) >= 1 {
                target := StablePath(nodes, source, nodes.Child(node, 0))
                if target != null {
                    into.Add(target)
                }
            }
        } else if kind == ColumnarExpressionNodeKind.UnaryExpression && nodes.ChildCount(node) == 1 {
            op := ColumnarNodeTextFacts.Text(nodes, source, node)
            if op == "++" || op == "--" {
                target := StablePath(nodes, source, nodes.Child(node, 0))
                if target != null {
                    into.Add(target)
                }
            }
        } else if kind == ColumnarStatementNodeKind.VariableDeclarationStatement || kind == ColumnarStatementNodeKind.ForeachStatement || kind == ColumnarStatementNodeKind.AwaitForeachStatement {
            // The BOUND NAME rides in the value slot for a `:=` declaration and for both `for x in`
            // spellings that carry no written type.
            declared := ColumnarNodeTextFacts.Text(nodes, source, node)
            if declared.Length > 0 {
                into.Add(declared)
            }
        } else if kind == ColumnarStatementNodeKind.TypedLocalDeclaration || kind == ColumnarStatementNodeKind.TypedForeachStatement {
            // An ANNOTATED declaration and an annotated loop variable put the written TYPE in the
            // value slot, so the name is the leading identifier child instead.
            if nodes.ChildCount(node) >= 1 {
                declared := SimpleName(nodes, source, nodes.Child(node, 0))
                if declared != null {
                    into.Add(declared)
                }
            }
        }

        childIndex := 0
        while childIndex < nodes.ChildCount(node) {
            CollectAssignedNames(nodes, source, nodes.Child(node, childIndex), into)
            childIndex = childIndex + 1
        }
    }
}
