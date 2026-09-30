namespace Census.Imports.Clr


// A SOURCE TYPE SPELLED LIKE A CLR ONE. `System.Range` exists in every reference set, so a file that
// imports `System` and this namespace has two candidates for `Range` — the collision the census
// found in real converted code, here as an executable contract.
class Range {
    func Side(): string {
        return "source"
    }
}
