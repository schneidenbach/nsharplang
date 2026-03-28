// Comprehensive example demonstrating iterator functions (func*)
// Iterators use yield to return values one at a time
import System
import System.Collections.Generic
import System.Linq


// Basic iterator - generates a sequence of numbers
func* GetNumbers(count: int): IEnumerable<int> {
    i: int = 0
    while i < count {
        yield i
        i = i + 1
    }
}

// Iterator with yield break - early termination
func* GetNumbersUntilNegative(numbers: int[]): IEnumerable<int> {
    for num in numbers {
        if num < 0 {
            yield break
        }

        // Stop iteration

        yield num
    }
}

// Fibonacci sequence generator
func* Fibonacci(count: int): IEnumerable<int> {
    if count <= 0 {
        yield break
    }

    a: int = 0
    b: int = 1

    yield a
    if count == 1 {
        yield break
    }

    yield b

    i: int = 2
    while i < count {
        next := a + b
        yield next
        a = b
        b = next
        i = i + 1
    }
}

// Infinite sequence - only use with Take() or similar
func* InfiniteSequence(start: int, step: int): IEnumerable<int> {
    value := start
    while true {
        yield value
        value = value + step
    }
}

// Iterator that filters and transforms
func* GetEvenSquares(numbers: int[]): IEnumerable<int> {
    for num in numbers {
        if num % 2 == 0 {
            yield num * num
        }
    }
}

// Generic iterator
func* Repeat<T>(value: T, count: int): IEnumerable<T> {
    i: int = 0
    while i < count {
        yield value
        i = i + 1
    }
}

// Iterator that yields from another iterator
func* ChainSequences(first: IEnumerable<int>, second: IEnumerable<int>): IEnumerable<int> {
    for item in first {
        yield item
    }

    for item in second {
        yield item
    }
}

// Custom range iterator with step
func* Range(start: int, end: int, step: int): IEnumerable<int> {
    if step == 0 {
        throw new ArgumentException("Step cannot be zero")
    }

    if step > 0 {
        value := start
        while value < end {
            yield value
            value = value + step
        }
    } else {
        value := start
        while value > end {
            yield value
            value = value + step
        }
    }
}

class TreeNode {
    Value: int
    Children: List<TreeNode>

    constructor(value: int) {
        Value = value
        Children = new List<TreeNode>()
    }

    func AddChild(value: int): TreeNode {
        child := new TreeNode(value)
        Children.Add(child)
        return child
    }

    // Iterator for depth-first traversal
    func* DepthFirstTraversal(): IEnumerable<int> {
        yield Value

        for child in Children {

            // Yield all values from child's traversal
            for childValue in child.DepthFirstTraversal() {
                yield childValue
            }
        }
    }
}

func Main() {
    print "=== Iterator Functions (func*) Examples ==="
    print ""

    // Example 1: Basic iterator
    print "1. Basic iterator - GetNumbers(5):"
    for num in GetNumbers(5) {
        print $"  {num}"
    }

    print ""

    // Example 2: Iterator with early termination
    print "2. Iterator with yield break:"
    numbers: int[] = [1, 2, 3, -1, 4, 5]
    separator := ", "
    print $"  Input: [{String.Join(separator, numbers)}]"
    print "  Output (stops at -1):"
    for num in GetNumbersUntilNegative(numbers) {
        print $"  {num}"
    }

    print ""

    // Example 3: Fibonacci sequence
    print "3. Fibonacci sequence (first 10):"
    fib := String.Join(separator, Fibonacci(10))
    print $"  {fib}"
    print ""

    // Example 4: Infinite sequence with LINQ
    print "4. Infinite sequence (take first 5, starting at 10, step 3):"
    infinite := String.Join(separator, InfiniteSequence(10, 3).Take(5))
    print $"  {infinite}"
    print ""

    // Example 5: Filtering and transforming
    print "5. Even squares from [1, 2, 3, 4, 5, 6]:"
    input: int[] = [1, 2, 3, 4, 5, 6]
    evenSquares := String.Join(separator, GetEvenSquares(input))
    print $"  {evenSquares}"
    print ""

    // Example 6: Generic iterator
    print "6. Repeat<string>(\"Hello\", 3):"
    for item in Repeat("Hello", 3) {
        print $"  {item}"
    }

    print ""

    // Example 7: Chaining sequences
    print "7. Chain two sequences:"
    seq1: int[] = [1, 2, 3]
    seq2: int[] = [4, 5, 6]
    seq1Str := String.Join(separator, seq1)
    seq2Str := String.Join(separator, seq2)
    chained := String.Join(separator, ChainSequences(seq1, seq2))
    print $"  First: [{seq1Str}]"
    print $"  Second: [{seq2Str}]"
    print $"  Chained: [{chained}]"
    print ""

    // Example 8: Custom range with step
    print "8. Range with custom step:"
    range1 := String.Join(separator, Range(0, 10, 2))
    range2 := String.Join(separator, Range(10, 0, -2))
    print $"  Range(0, 10, 2): [{range1}]"
    print $"  Range(10, 0, -2): [{range2}]"
    print ""

    // Example 9: Tree traversal with iterator
    print "9. Tree depth-first traversal:"
    root := new TreeNode(1)
    child2 := root.AddChild(2)
    child3 := root.AddChild(3)
    child2.AddChild(4)
    child2.AddChild(5)
    child3.AddChild(6)

    print "  Tree structure:"
    print "       1"
    print "      / \\"
    print "     2   3"
    print "    / \\   \\"
    print "   4   5   6"
    traversal := String.Join(separator, root.DepthFirstTraversal())
    print $"  Traversal: [{traversal}]"
    print ""

    // Example 10: Combining iterators with LINQ
    print "10. Combining iterators with LINQ:"
    result := GetNumbers(10).Where(x => x % 2 == 0).Select(x => x * x).ToList()

    resultStr := String.Join(separator, result)
    print $"  Even squares from 0-9: [{resultStr}]"
    print ""

    print "=== Iterator Benefits ==="
    print "  - Lazy evaluation (values computed on demand)"
    print "  - Memory efficient (no intermediate collections)"
    print "  - Can represent infinite sequences"
    print "  - Composable with LINQ"
    print "  - Natural expression of sequential algorithms"
}
