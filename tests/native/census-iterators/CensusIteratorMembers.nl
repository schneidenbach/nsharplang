namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// AN INSTANCE GENERATOR'S BODY IS A MEMBER BODY. It reaches every field its type declares — a
// camelCase one and a `private` one as readily as a public one — because its state machine is nested
// in that type. And it follows the member body's shadowing rule exactly: a parameter or local of the
// same spelling hides a field while it is in scope, and `this.name` reaches the field whatever hides it.
class CensusLedger {
    Title: string = "title"
    note: string = "note"
    private secret: string = "secret"
    count: int = 0
    private tally: int = 0

    // A read of all three visibilities, bare and through `this`.
    func* Visibilities(): IEnumerable<string> {
        yield Title
        yield note
        yield secret
        yield this.note
        yield this.secret
    }

    // A parameter is in scope for the whole body.
    func* ParameterHides(secret: string): IEnumerable<string> {
        yield secret
        yield this.secret
    }

    // A local is in scope from the statement after its declaration to the end of its block: its own
    // initializer, and every read outside that block, still names the field.
    func* LocalHides(flag: bool): IEnumerable<string> {
        yield note
        note := note + "-local"
        yield note
        yield this.note
        if flag {
            secret := "inner"
            yield secret
        }
        yield secret
    }

    // A `for..in` variable is in scope for its loop body alone, and a counted `for`'s own local for
    // that statement alone.
    func* LoopVariablesHide(): IEnumerable<string> {
        for note in ["a", "b"] {
            yield note
        }
        yield note
        for secret := 0; secret < 1; secret++ {
            yield secret.ToString()
        }
        yield secret
    }

    // A catch clause's variable is in scope for its handler alone.
    func* CatchVariableHides(): IEnumerable<string> {
        caught := ""
        try {
            throw new InvalidOperationException("caught")
        } catch note: InvalidOperationException {
            caught = note.Message
        }
        yield caught
        yield note
    }

    // A lambda sees a field exactly where it was written sees it, less its own parameters' names.
    func* LambdasSee(): IEnumerable<string> {
        rename: Func<string, string> = secret => secret + "!"
        yield rename("argument")
        both: Func<string> = () => note + secret
        yield both()
        note := "local"
        shadowed: Func<string> = () => note + "/" + this.note
        yield shadowed()
    }

    // A lambda created per iteration captures the loop local through its own display, which still
    // reaches the `private` field and still sees the field behind a hiding local through `this`.
    func* PerIterationLambdas(): IEnumerable<string> {
        made := new List<Func<string>>()
        for i in [1, 2] {
            note := "n" + i.ToString()
            captured: Func<string> = () => note + ":" + secret + ":" + this.note
            made.Add(captured)
        }
        for make in made {
            yield make()
        }
    }

    // Writes follow the same rule as reads: a bare name stores to whatever it means where it is
    // written, and `this.name` stores to the field.
    func* Writes(): IEnumerable<int> {
        count++
        tally = tally + 10
        yield count
        yield tally
        count := 100
        count++
        this.count++
        this.tally = this.tally + count
        yield count
        yield this.count
        yield tally
    }

    func Note(): string {
        return note
    }

    func Tally(): int {
        return tally
    }
}

class CensusLedgerBase {
    Shared: string = "shared"
    inherited: string = "inherited"
}

// A source base's public and camelCase fields are the derived member body's to read and write.
class CensusDerivedLedger: CensusLedgerBase {
    own: string = "own"

    func* Inherited(): IEnumerable<string> {
        yield Shared
        yield inherited
        yield own
        inherited = "rewritten"
        yield this.inherited
    }
}
