namespace NSharpLang.Compiler.Columnar

import System

func InheritanceDepthOrderText(order: int[]): string {
    text := ""
    index := 0
    while index < order.Length {
        if index > 0 {
            text = text + ","
        }
        text = text + Convert.ToString(order[index])
        index = index + 1
    }
    return text
}

func InheritanceDepthOrderOf(depths: int[]): string {
    return InheritanceDepthOrderText(ColumnarInheritanceDepthOrder.Sort(depths))
}

func InheritanceDepths(values: int[]): int[] {
    return values
}

test "types at the same depth keep source order" {
    // Nothing derives from anything: the pass must not shuffle the emitted metadata for a program
    // that has no inheritance in it at all.
    flat := new int[](4)
    flat[0] = 0
    flat[1] = 0
    flat[2] = 0
    flat[3] = 0
    assert InheritanceDepthOrderOf(flat) == "0,1,2,3"
}

test "a base declared after its subclass is still visited first" {
    // Source order: Circle (depth 2), Square (depth 1), Shape (depth 0), Rounded (depth 1). Shape
    // must come first, then Square and Rounded IN SOURCE ORDER, then Circle.
    depths := new int[](4)
    depths[0] = 2
    depths[1] = 1
    depths[2] = 0
    depths[3] = 1
    assert InheritanceDepthOrderOf(depths) == "2,1,3,0"
}

test "every depth level is emptied before the next begins" {
    depths := new int[](6)
    depths[0] = 3
    depths[1] = 1
    depths[2] = 0
    depths[3] = 2
    depths[4] = 1
    depths[5] = 0
    assert InheritanceDepthOrderOf(depths) == "2,5,1,4,3,0"
}

test "a gap in the depth numbers does not lose a type" {
    // Depths need not be contiguous — a chain whose middle links are in another file can leave a hole
    // — and the walk must still place every index exactly once.
    depths := new int[](3)
    depths[0] = 5
    depths[1] = 0
    depths[2] = 5
    assert InheritanceDepthOrderOf(depths) == "1,0,2"
}

test "a negative depth is read as the root rather than reordering the program" {
    // A chain walk cannot produce one. Treating it as depth 0 keeps SOURCE order visible, which is
    // far easier to see in emitted metadata than an order invented from nonsense.
    depths := new int[](3)
    depths[0] = 1
    depths[1] = -4
    depths[2] = 0
    assert InheritanceDepthOrderOf(depths) == "1,2,0"
}

test "an empty or absent depth column yields an empty order" {
    assert InheritanceDepthOrderOf(new int[](0)) == ""
    assert ColumnarInheritanceDepthOrder.Sort(null).Length == 0
}

test "the order is a permutation of the input indices" {
    depths := new int[](5)
    depths[0] = 2
    depths[1] = 0
    depths[2] = 1
    depths[3] = 0
    depths[4] = 2
    order := ColumnarInheritanceDepthOrder.Sort(depths)
    assert order.Length == 5

    seen := new bool[](5)
    index := 0
    while index < order.Length {
        slot := order[index]
        assert slot >= 0 && slot < 5
        assert !seen[slot]
        seen[slot] = true
        index = index + 1
    }
}
