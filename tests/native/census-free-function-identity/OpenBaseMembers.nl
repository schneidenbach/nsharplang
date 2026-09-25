namespace Census.FreeFunctionIdentity.OpenBase

import System.Collections.Generic


// A BARE NAME INSIDE A TYPE WITH AN EXTERNAL BASE IS THAT BASE'S MEMBER, AND ITS TYPE ARGUMENTS COME
// FROM THE `:` CLAUSE — whether the clause closes them (`List<string>`) or passes the type's own
// parameter through (`List<U>`).
//
// Both shapes were wrong in the analyzer. Over the open `U`, `List<U>` had no CLR form, so every
// member of it answered `unknown`: `this.ToArray()` was NL303, the bare `ToArray()` NL412 and the bare
// `Count` NL301. Over the closed `string`, the bare call had no receiver to read `T` from, so
// `ToArray()[0]` typed as `T` while `this.ToArray()[0]` typed as `string`. Every member below is
// written in both spellings, and each pair must agree at runtime.
class Names: List<string> {
    func Put(value: string) {
        Add(value)
    }

    func FirstThis(): string => this.ToArray()[0]

    func FirstBare(): string => ToArray()[0]

    func SizeBare(): int => Count
}

class Mid<U>: List<U> {
    func PutThis(value: U) {
        this.Add(value)
    }

    func PutBare(value: U) {
        Add(value)
    }

    func FirstThis(): U => this.ToArray()[0]

    func FirstBare(): U => ToArray()[0]

    func LastThis(): U => this[this.Count - 1]

    func SizeThis(): int => this.Count

    func SizeBare(): int => Count
}

// The same instantiation reached through a FUNCTION's type parameter rather than a class's.
func FirstOf<U>(xs: List<U>): U => xs.ToArray()[0]

func CountOf<U>(xs: List<U>): int => xs.Count
