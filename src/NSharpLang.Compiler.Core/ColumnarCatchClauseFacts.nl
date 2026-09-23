namespace NSharpLang.Compiler.Columnar


// WHICH CHILD OF A kind-50 CATCH CLAUSE IS WHICH.
//
// A catch clause has one required child and two optional ones, and before exception filters existed
// every reader could settle the question by COUNTING: `ChildCount == 2` meant "there is a bound
// variable", `ChildCount - 1` meant "the handler block". The count is no longer enough. `catch e: T
// when running { }` has three children and `catch T when running { }` has two — the same two a bound
// variable used to mean — so a counting reader silently takes the FILTER for the BINDING.
//
// So the layout is stated once, here, and asked rather than counted:
//
//     children [ binding (kind 6)? , filter (kind 84)? , block (kind 25) ]
//
// The block is ALWAYS last, which is why `ChildCount - 1` remains correct everywhere it is already
// written; the two leading slots are distinguishable BY KIND, which is the same discipline kind 49
// already uses to tell its trailing kind-25 `finally` from its kind-50 catches. Nothing here walks
// or allocates: each function is one bounded look at the clause's own children, so the hot member
// binding and shadowing walks that call it pay what a field read costs.
class ColumnarCatchClauseFacts {
    static func CatchClauseKind(): int {
        return 50
    }

    static func FilterClauseKind(): int {
        return 84
    }

    static func IdentifierKind(): int {
        return 6
    }

    // The clause's bound exception variable, or -1 for `catch T { }` and `catch { }`. It is child 0
    // when it is present at all, because the grammar writes the binding before the `when`.
    static func BindingNode(nodes: ColumnarNodeTable, clause: int): int {
        if nodes == null || clause < 0 {
            return 0 - 1
        }

        if nodes.ChildCount(clause) < 2 {
            return 0 - 1
        }

        first := nodes.Child(clause, 0)
        if nodes.Kind(first) == IdentifierKind() && nodes.ValueStart(first) >= 0 {
            return first
        }

        return 0 - 1
    }

    // The kind-84 wrapper, or -1 when the clause has no `when`.
    static func FilterNode(nodes: ColumnarNodeTable, clause: int): int {
        if nodes == null || clause < 0 {
            return 0 - 1
        }

        count := nodes.ChildCount(clause)
        ordinal := 0
        while ordinal < count - 1 {
            child := nodes.Child(clause, ordinal)
            if nodes.Kind(child) == FilterClauseKind() {
                return child
            }
            ordinal = ordinal + 1
        }

        return 0 - 1
    }

    // The guard EXPRESSION inside the wrapper — what the analyzer types as `bool` and what the
    // emitter runs inside the CLR filter block — or -1 when there is no filter.
    static func FilterGuard(nodes: ColumnarNodeTable, clause: int): int {
        filter := FilterNode(nodes, clause)
        if filter < 0 || nodes.ChildCount(filter) < 1 {
            return 0 - 1
        }

        return nodes.Child(filter, 0)
    }

    static func HasFilter(nodes: ColumnarNodeTable, clause: int): bool {
        return FilterNode(nodes, clause) >= 0
    }

    // The handler block. Always the last child, which is the invariant that keeps every
    // `ChildCount - 1` already written in the planners correct.
    static func BodyNode(nodes: ColumnarNodeTable, clause: int): int {
        if nodes == null || clause < 0 || nodes.ChildCount(clause) < 1 {
            return 0 - 1
        }

        return nodes.Child(clause, nodes.ChildCount(clause) - 1)
    }
}
