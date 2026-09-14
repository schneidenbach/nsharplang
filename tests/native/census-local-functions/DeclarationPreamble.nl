namespace NSharpLang.CensusLocalFunctions.Tests

import System
import System.Threading.Tasks


// WHAT A DECLARATION'S MODIFIERS ARE, WHEN THE DECLARATION BEFORE IT HAS NO BRACES.
//
// A top-level declaration's modifiers are the run of keywords immediately before its `func` (or
// `class`, `enum`, …). The scan that collects them walks the whole token stream and skips bodies by
// BRACE DEPTH — which works for every block body and for nothing else. An EXPRESSION-BODIED function
// has no braces, so its body's tokens were read as if they sat between declarations, and an `async`
// lambda in that position left `async` pending for the NEXT function to wear.
//
// That produced no diagnostic. The following function silently became `async`: its signature grew a
// `ValueTask<T>` wrap and its body was emitted inside the async fault guard, so a `throw` it raised
// became a faulted task nobody awaited and the call simply RETURNED. The local function that raised
// it looked correct in source, in `check`, and in `build`.
//
// So every function below is a real program: the shapes are the (sync | async) x (arrow | block)
// lambda body crossed with a local function declared before it and after it, capturing and not, and
// the contracts beside them assert what the emitted IL DOES — the throw arriving, the value returned,
// and the signature reflection reports.

// ---------------------------------------------------------------------------
// ARROW-BODIED FACTORIES. Each is followed by a function whose local function throws: if the `async`
// leaks, the throw is swallowed and the call returns instead.
// ---------------------------------------------------------------------------

// The original reproduction: an expression-bodied function whose body is an `async` lambda.
func AsyncArrowFactory(): Func<Task<int>> => async () => 1

func RequiredAfterAsyncArrow(name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return v
    }

    return require(name)
}

// The same shape with a SYNCHRONOUS lambda body — the control that says the leak is the `async`
// keyword and not expression bodies in general.
func SyncArrowFactory(): Func<int> => () => 2

func RequiredAfterSyncArrow(name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return v
    }

    return require(name)
}

// An `async` lambda with a BLOCK body behind the arrow: the lambda's braces open AFTER the keyword,
// so the keyword itself is still read at depth zero.
func AsyncArrowBlockFactory(): Func<Task<int>> => async () => {
    v := await Task.FromResult(3)
    return v
}

func RequiredAfterAsyncArrowBlock(name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return v
    }

    return require(name)
}

// A CAPTURING local function after the leak site: the capture is lifted into a display class, which
// is a second thing the async fault guard would have wrapped.
func CapturingRequiredAfterAsyncArrow(prefix: string, name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return prefix + v
    }

    return require(name)
}

// A local function declared BEFORE any arrow-bodied factory in the file is unaffected, and says so.
func RequiredBeforeArrowFactories(name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return v
    }

    return require(name)
}

// A BLOCK-BODIED factory returning the same `async` lambda: brace depth already hid this one, and it
// is here so a regression that "fixes" the arrow case by breaking the block case is a failing test.
func AsyncBlockFactory(): Func<Task<int>> {
    return async () => 4
}

func RequiredAfterAsyncBlock(name: string?): string {
    func require(v: string?): string {
        if v == null {
            throw new ArgumentNullException("v")
        }

        return v
    }

    return require(name)
}

// ---------------------------------------------------------------------------
// THE MODIFIERS A DECLARATION AFTER AN ARROW BODY REALLY DOES DECLARE. Suppressing the leak must not
// suppress the real thing: each of these sits directly after an expression-bodied function.
// ---------------------------------------------------------------------------

func ArrowBeforeAsyncFunction(): int => 5

async func DeclaredAsyncAfterArrow(): int {
    return await Task.FromResult(6)
}

func ArrowBeforeAttributedFunction(): int => 7

[Obsolete("pinned by the preamble contract")]
func AttributedAfterArrow(): int => 8

// A CONSTRAINT CLAUSE ends at the body, and an expression body opens with `=>`, not `{`. While the
// scan only ended it at a brace, this declaration swallowed every declaration after it in the file
// and the whole source declined at `parse.declaration-scan`.
func ConstrainedArrow<T>(value: T): T where T: class => value

func AfterConstrainedArrow(): int => 9

// AN INDEXER AT THE END OF AN ARROW BODY is not an attribute group. The preamble walk that finds
// where the next declaration's modifiers begin reads backwards from its `func`, and a `]` there
// looked like an attribute's close — so `=> items[0]` made the next declaration's preamble start
// inside the body, and the file declined at `parse.declaration-scan`. The body's end is measured
// forward to the next `func` instead, over that declaration's real modifiers and attributes.
func IndexerArrow(items: int[]): int => items[0]

func AfterIndexerArrow(): int => 10

func IndexerArrowBeforeAttributed(items: int[]): int => items[1]

[Obsolete("pinned by the indexer preamble contract")]
func AttributedAfterIndexerArrow(): int => 11
