// THE GLOBAL NAMESPACE'S FREE FUNCTIONS, the shape `Compiler.Syntax`'s parser kernels take: a file
// with no namespace puts its functions on the global `Program` holder, and a program that references
// this assembly reaches them by their bare names from any namespace, because the global namespace is
// the outermost member of every file's lexical chain.

// A table the functions below fill, the way a parser kernel fills its caller's output table.
class GlobalTally {
    Count: int
}

func GlobalScale(value: int): int => value * 3

func GlobalFill(tally: GlobalTally, count: int): int {
    tally.Count = tally.Count + count
    return tally.Count * 2
}
