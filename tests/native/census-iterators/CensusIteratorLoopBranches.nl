namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// `break` AND `continue` INSIDE A GENERATOR BODY.
//
// Neither was lowered at all. A `func*` whose loop broke or continued declined the whole program
// with "an iterator body statement (node kind 21/22) is not yet lowered in '<function>'" — so the
// most ordinary sequence function there is, a loop that skips some elements and stops at a
// sentinel, could not be written as a generator. The shape that found it is a directory walk that
// skips a directory it cannot read.
//
// Every subject below is executed, and each one pins a decision the lowering has to make:
//
//   * `continue` in a COUNTED loop must run the step. A branch to the condition instead of to the
//     increment is an infinite loop, not a skipped element.
//   * `break` out of a `for..in` over a SEQUENCE must still release the enumerator, which is what
//     branching to the loop's own exit label (where the dispose stands) does.
//   * a branch that crosses a `try` the loop was opened OUTSIDE of must be `leave`, not `br`.
//   * `break` in an INNER loop leaves the inner loop only.
//   * a `yield` after the branch still resumes at its own state — the branch is an ordinary edge in
//     the state machine, not an exit from it.
class LoopBranches {

    // A counted loop that skips the odd values and stops at a sentinel. `continue` must reach the
    // `i++`: to the condition instead, and `Evens(10, 7)` never returns.
    static func* Evens(limit: int, stopAt: int): IEnumerable<int> {
        for i := 0; i < limit; i++ {
            if i == stopAt {
                break
            }

            if i % 2 == 1 {
                continue
            }

            yield i
        }
    }

    // A `while` whose `continue` targets the condition, because a `while` has no step to run.
    static func* WhileSkipping(values: int[]): IEnumerable<int> {
        index := 0
        while index < values.Length {
            current := values[index]
            index = index + 1
            if current < 0 {
                continue
            }

            if current == 0 {
                break
            }

            yield current
        }
    }

    // `for..in` over an ARRAY field — the index-loop lowering, which is a different emitter from the
    // enumerator one below.
    static func* ArraySkipping(values: int[], stopAt: int): IEnumerable<int> {
        for value in values {
            if value == 0 {
                continue
            }

            if value == stopAt {
                break
            }

            yield value
        }
    }

    // `for..in` over a SEQUENCE — the hoisted-enumerator lowering. The trace records the enumerator's
    // Dispose, so an early `break` that skipped the release would show up as a missing "disposed".
    static func* SequenceSkipping(source: IEnumerable<int>, stopAt: int): IEnumerable<int> {
        for value in source {
            if value < 0 {
                continue
            }

            if value == stopAt {
                break
            }

            yield value
        }
    }

    // A BRANCH OUT OF A PROTECTED REGION. The `try` is opened INSIDE the loop, so both branches cross
    // its boundary and have to be `leave`; the `finally` runs on the way out of each one.
    static func* GuardedSkipping(values: int[], stopAt: int, trace: CensusTrace): IEnumerable<int> {
        for value in values {
            try {
                trace.Add("try")
                if value < 0 {
                    continue
                }

                if value == stopAt {
                    break
                }
            } finally {
                trace.Add("finally")
            }

            yield value
        }

        trace.Add("after")
    }

    // NESTED LOOPS. The inner `break` leaves the inner loop; the outer one keeps running.
    static func* Pairs(rows: int, columns: int, skipColumn: int): IEnumerable<int> {
        for row := 0; row < rows; row++ {
            for column := 0; column < columns; column++ {
                if column == skipColumn {
                    break
                }

                yield row * 10 + column
            }

            yield row * 100
        }
    }

    // A generator whose ONLY exit from the loop is the `break`: the body never falls through, so the
    // step and the back edge exist only because the `continue` needs them.
    static func* UntilSentinel(values: int[], sentinel: int): IEnumerable<int> {
        for i := 0; i < values.Length; i++ {
            if values[i] == sentinel {
                break
            }

            if values[i] < 0 {
                continue
            }

            yield values[i]
        }
    }
}

// A SEQUENCE THAT RECORDS ITS OWN DISPOSAL, so an early `break` can be proved to have RELEASED the
// enumerator rather than merely to have stopped reading it: a generator's `finally` runs when its
// enumerator is disposed, which is exactly the moment the consuming loop's `break` has to produce.
func* TracedSource(values: int[], trace: CensusTrace): IEnumerable<int> {
    try {
        for value in values {
            yield value
        }
    } finally {
        trace.Add("disposed")
    }
}

// STRING EQUALITY INSIDE A GENERATOR. `ceq` over two string references is the wrong answer and the
// plan path had no `String.op_Equality` arm, so this shape declined the whole program with
// `emit.iterator.unsupported-shape: an iterator body expression (node kind 12) could not be
// lowered` — while `name + "!"` in the same body planned fine.
func* NamedSkipping(values: string[], stopAt: string): IEnumerable<string> {
    for value in values {
        if value == "" {
            continue
        }

        if value == stopAt {
            break
        }

        yield value
    }
}
