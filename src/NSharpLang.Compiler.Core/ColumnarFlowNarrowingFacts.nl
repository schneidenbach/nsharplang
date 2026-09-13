namespace NSharpLang.Compiler.Columnar

import System
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
// IT IS NARROWER THAN THE ANALYZER'S, DELIBERATELY, AND IN ONE DIRECTION. The analyzer records a
// null STATE for member paths (`doc.Text`) and a narrowed TYPE for `is` patterns; neither can be
// acted on at emit, because the only thing an emitted unwrap can address is a storage location the
// body owns — a local, a parameter, a lifted local. So only the facts about a SIMPLE NAME are
// collected, and every other fact the analyzer holds is silently not repeated here.
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
        if kind == 7 && nodes.ChildCount(condition) == 1 {
            Collect(nodes, source, nodes.Child(condition, 0), thenNames, elseNames)
            return
        }

        // 11 Unary — only `!`, and it is the two lists the other way round.
        if kind == 11 && nodes.ChildCount(condition) == 1 {
            if ColumnarNodeTextFacts.Text(nodes, source, condition) == "!" {
                Collect(nodes, source, nodes.Child(condition, 0), elseNames, thenNames)
            }

            return
        }

        // 8 MemberAccess — `x.HasValue` proves `x` present in the true branch and nothing in the
        // false one (the analyzer's `TryExtractHasValueNarrowing`, which likewise files no else fact).
        if kind == 8 {
            if ColumnarNodeTextFacts.Text(nodes, source, condition) == "HasValue" && nodes.ChildCount(condition) == 1 {
                receiverName := SimpleName(nodes, source, nodes.Child(condition, 0))
                if receiverName != null {
                    thenNames.Add(receiverName)
                }
            }

            return
        }

        if kind != 12 || nodes.ChildCount(condition) != 2 {
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
    static func CollectNullComparison(nodes: ColumnarNodeTable, source: string, value: int, other: int, notEqual: bool, thenNames: List<string>, elseNames: List<string>) {
        if other < 0 || other >= nodes.Kinds.Length || nodes.Kind(other) != 5 {
            return
        }

        name := SimpleName(nodes, source, value)
        if name == null {
            return
        }

        if notEqual {
            thenNames.Add(name)
            return
        }

        elseNames.Add(name)
    }

    // A BARE NAME, THROUGH THE PARENTHESES THAT ARE TRANSPARENTLY IT. Only an identifier (6) with no
    // children can name a storage location an unwrap may address.
    static func SimpleName(nodes: ColumnarNodeTable, source: string, node: int): string? {
        if node < 0 || node >= nodes.Kinds.Length {
            return null
        }

        if nodes.Kind(node) == 7 && nodes.ChildCount(node) == 1 {
            return SimpleName(nodes, source, nodes.Child(node, 0))
        }

        if nodes.Kind(node) != 6 || nodes.ChildCount(node) != 0 {
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

    // EVERY NAME A STATEMENT SUBTREE WRITES. A narrowing is a statement about the value a name holds
    // NOW, so any write inside a region whose flow this reader cannot follow — a loop body, which runs
    // an unknown number of times and jumps backwards — ends it. Collecting the writes is what lets a
    // narrowing survive a loop that does not touch the name, which is the common case.
    //
    // THE WRITE SHAPES ARE THE ONES THE EMITTER ITSELF LOWERS: an assignment expression (14) and a
    // postfix/prefix step (44/11) whose target is a bare name, plus the two declaration statements
    // (24, 40) and a `for x in xs` loop variable (29/76/73), each of which BINDS the name anew.
    static func CollectAssignedNames(nodes: ColumnarNodeTable, source: string, node: int, into: HashSet<string>) {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length || into == null {
            return
        }

        kind := nodes.Kind(node)
        if kind == 14 || kind == 44 {
            if nodes.ChildCount(node) >= 1 {
                target := SimpleName(nodes, source, nodes.Child(node, 0))
                if target != null {
                    into.Add(target)
                }
            }
        } else if kind == 11 && nodes.ChildCount(node) == 1 {
            op := ColumnarNodeTextFacts.Text(nodes, source, node)
            if op == "++" || op == "--" {
                target := SimpleName(nodes, source, nodes.Child(node, 0))
                if target != null {
                    into.Add(target)
                }
            }
        } else if kind == 24 || kind == 29 || kind == 73 {
            // The BOUND NAME rides in the value slot for a `:=` declaration and for both `for x in`
            // spellings that carry no written type.
            declared := ColumnarNodeTextFacts.Text(nodes, source, node)
            if declared.Length > 0 {
                into.Add(declared)
            }
        } else if kind == 40 || kind == 76 {
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
