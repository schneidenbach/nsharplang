namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.IO
import System.Linq


// A METHOD GROUP DECLARED BY A REFERENCED ASSEMBLY.
//
// `roots.Where(Directory.Exists).SelectMany(root => ...).Where(path => ...)` is the census's own
// line, and it reported THREE errors: NL402 for `Where`, then NL203 for `root` and for `path`,
// because a method group in the first link left the chain's element type unknown and every later
// lambda in the chain had nothing to take its parameter type from. A method group was only ever a
// name the PROJECT declared; a group read out of a referenced assembly converted to no delegate
// anywhere, and `local: Func<string, bool> = Directory.Exists` reported NL202 for the same reason.
//
// A group's declaring assembly is no part of the conversion: it compares two signatures. The
// receiver here is a TYPE rather than a value, so the delegate closes over a null target.
class Sorting {
    static func ByLength(left: string, right: string): int {
        return left.Length - right.Length
    }
}

class Doubling {
    static func Twice(value: int): int {
        return value * 2
    }

    static func Twice(value: string): int {
        return value.Length * 2
    }
}

func EmptyPredicate(): Func<string, bool> {
    return String.IsNullOrEmpty
}

func ParsePicked(): Func<string, int> {
    return Int32.Parse
}

func NonEmpty(values: string[]): string[] {
    return values.Where(HasText).ToArray()
}

func HasText(value: string): bool {
    return !String.IsNullOrEmpty(value)
}

func EmptyOnes(values: string[]): string[] {
    return values.Where(String.IsNullOrEmpty).ToArray()
}

func ParsedAll(values: string[]): int[] {
    return values.Select(Int32.Parse).ToArray()
}

// THE CENSUS'S OWN CHAIN, verbatim in shape: a method group in the FIRST link, then two lambdas that
// can only take their parameter type from what that link produced.
func FilesUnder(roots: string[], extras: string[]): string[] {
    return roots.Where(Directory.Exists).SelectMany(root => Directory.EnumerateFiles(root, "*", SearchOption.TopDirectoryOnly)).Where(path => !path.EndsWith(".skip", StringComparison.Ordinal)).Concat(extras.Where(File.Exists)).ToArray()
}

// A SOURCE type's static group, named through its type from OUTSIDE that type.
func DoubledAll(values: int[]): int[] {
    return values.Select(Doubling.Twice).ToArray()
}

func SortedByLength(values: string[]): string[] {
    copy := new string[](values.Length)
    Array.Copy(values, copy, values.Length)
    byLength: Comparison<string> = Sorting.ByLength
    Array.Sort(copy, byLength)
    return copy
}
