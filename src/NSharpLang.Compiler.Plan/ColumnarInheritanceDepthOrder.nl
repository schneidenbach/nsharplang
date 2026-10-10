namespace NSharpLang.Compiler.Columnar

import System


// THE ORDER A DECLARATION PASS MUST VISIT TYPES IN WHEN ONE TYPE'S MEMBERS ANSWER FOR ANOTHER'S.
//
// A derived class's `override func Name(...)` is resolved against the BASE class's own declaration
// table — the `MethodBuilder` handles the base filled in when it was declared. Source order says
// nothing about which of two classes is the base, so a program that writes the derived class first
// would ask a base that has not declared anything yet and be told, wrongly, that no overridable
// member exists.
//
// INHERITANCE DEPTH IS THE ORDER, AND IT IS ALREADY COMPUTED. The emitter measures every type's
// chain length to reject inheritance cycles; the same numbers, read as a sort key, put every base
// ahead of everything that derives from it. Ties keep SOURCE ORDER, so two unrelated types are
// still declared in the order they were written and the emitted metadata does not shuffle.
class ColumnarInheritanceDepthOrder {

    // The type indices, ordered by chain depth ascending and by source index within a depth. A
    // negative depth cannot arise from a chain walk; it is treated as depth 0 rather than silently
    // reordering, because an order this pass produced from nonsense would be far harder to see than
    // one that simply kept the source order.
    static func Sort(depths: int[]): int[] {
        if depths == null {
            return new int[](0)
        }

        count := depths.Length
        order := new int[](count)
        cursor := 0
        maxDepth := 0
        index := 0
        while index < count {
            depth := DepthAt(depths, index)
            if depth > maxDepth {
                maxDepth = depth
            }
            index = index + 1
        }

        level := 0
        while level <= maxDepth && cursor < count {
            index = 0
            while index < count {
                if DepthAt(depths, index) == level {
                    order[cursor] = index
                    cursor = cursor + 1
                }
                index = index + 1
            }
            level = level + 1
        }

        if cursor != count {
            throw new InvalidOperationException("Inheritance-depth ordering must place every type exactly once.")
        }

        return order
    }

    static func DepthAt(depths: int[], index: int): int {
        depth := depths[index]
        if depth < 0 {
            return 0
        }
        return depth
    }
}
