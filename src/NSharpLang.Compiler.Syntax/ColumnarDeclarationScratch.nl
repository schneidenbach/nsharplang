import NSharpLang.Compiler


// THE SCRATCH ONE DECLARATION'S PARSE NEEDS IS BOUNDED BY THAT DECLARATION, NOT BY ITS FILE.
//
// Every per-declaration kernel -- a function's signature and body, a member's signature end, a
// struct's member scan, a test's body -- writes its rows into scratch columns before the caller
// trims them. Those columns used to be sized `count + 1`, the WHOLE FILE's token count, because a
// parse can produce no more rows than the tokens it reads plus one. That bound is true, and it was
// paid once per DECLARATION: a file of `m` methods and `n` tokens allocated about sixty `n`-sized
// arrays per method, so the parse was O(m * n) in memory traffic. `ColumnarIlEmitter.nl` -- one
// 30,800-line class, 585 functions, 191,000 tokens -- allocated 57 GB to parse, almost all of it
// large-object-heap arrays that forced a gen-2 collection every dozen methods, and every emit of
// Compiler.Emit paid it (1.1 GB with the windowed capacity; Compiler.Core 29.5 GB -> 4.8 GB).
//
// The same bound, applied to the tokens the declaration CAN read, is the declaration's own extent:
// its parse starts at `start` and never produces a row from a token past the declaration's end. A
// parse can produce MORE rows than tokens -- synthesized nodes, a block per branch; the densest
// function in the compiler's own source writes 1.6 nodes per token -- which the whole-file bound only
// ever satisfied through slack. So the capacity is four rows per token of the extent plus a constant,
// and never exceeds the old whole-file capacity, which stays the answer whenever the extent cannot
// be measured.

// Where the declaration that begins at `start` ends: the index one past its last token, or `count`
// when that cannot be decided. The three bracket pairs are balanced from `start` on.
//   * A block body -- the first depth-0 `{` not preceded by a depth-0 `=>` -- ends at its matching
//     `}`. A signature's own parentheses, brackets, defaults and constraints sit at depth > 0 or
//     before the `{`.
//   * An expression body or a bodiless member ends where the next depth-0 `func` begins, or at the
//     `}` that closes the body enclosing it. No expression contains a depth-0 `func` (a local
//     function is a statement, inside a block), so the answer is never short; it may run over
//     fields and properties that follow, which only makes the window larger. A `func` still in the
//     declaration's HEAD -- before its first bracket or `=>`, as when `start` is the `private` of
//     `private func F()` -- is the declaration's own.
//   * An unbalanced closer before any of that is the enclosing body's end.
func ColumnarDeclarationTokenEnd(tokenKinds: int[], count: int, start: int): int {
    if start < 0 || start >= count {
        return count
    }

    depth := 0
    blockBody := false
    sawArrow := false
    inHead := true
    i := start
    while i < count {
        kind := tokenKinds[i]
        if ColumnarTokenKindFacts.IsOpeningBracketKind(kind) {
            if depth == 0 && kind == ColumnarTokenKindFacts.LeftBraceKind && !sawArrow {
                blockBody = true
            }
            depth = depth + 1
            inHead = false
        } else if ColumnarTokenKindFacts.IsClosingBracketKind(kind) {
            depth = depth - 1
            if depth < 0 {
                return i
            }
            if depth == 0 && blockBody {
                return i + 1
            }
        } else if depth == 0 {
            if kind == ColumnarTokenKindFacts.FuncKind && !inHead {
                return i
            }
            if kind == ColumnarTokenKindFacts.ArrowKind {
                sawArrow = true
                inHead = false
            }
        }
        i = i + 1
    }

    return count
}

// The scratch-column capacity for a kernel that parses the declaration beginning at `start`.
func ColumnarDeclarationScratchCapacity(tokenKinds: int[], count: int, start: int): int {
    wholeFile := count + 1
    if start < 0 || start >= count {
        return wholeFile
    }

    extent := ColumnarDeclarationTokenEnd(tokenKinds, count, start) - start
    windowed := 4 * (extent + 1) + 64
    if windowed < wholeFile {
        return windowed
    }

    return wholeFile
}

// Scratch SHARED by consecutive parses of several declarations -- one struct's methods, parsed one
// after another into the same columns -- needs the largest one's capacity.
func ColumnarLargestDeclarationScratchCapacity(tokenKinds: int[], count: int, starts: int[], declarationCount: int): int {
    largest := 1
    i := 0
    while i < declarationCount {
        capacity := ColumnarDeclarationScratchCapacity(tokenKinds, count, starts[i])
        if capacity > largest {
            largest = capacity
        }
        i = i + 1
    }

    return largest
}

// Rows ACCUMULATED across several declarations -- every method's parameter types, end to end --
// need the sum of their capacities, and never more than the whole-file bound `limit` they had.
func ColumnarAccumulatedDeclarationScratchCapacity(tokenKinds: int[], count: int, starts: int[], declarationCount: int, limit: int): int {
    total := 1
    i := 0
    while i < declarationCount && total < limit {
        total = total + ColumnarDeclarationScratchCapacity(tokenKinds, count, starts[i])
        i = i + 1
    }

    if total < limit {
        return total
    }

    return limit
}
