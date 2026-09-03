namespace NSharpLang.Compiler

import System
import System.Collections.Generic

class DefiniteAssignmentState {
    Candidates: HashSet<string>
    Assigned: HashSet<string>
    Reported: HashSet<ValueTuple<string, int, int>>

    // THE NAMES THAT MUST BE ASSIGNED AT EVERY EXIT, which is a DIFFERENT question from the one
    // `Candidates` asks. A candidate is checked where it is READ; an `out` parameter is checked
    // where the function RETURNS, whether or not anything ever reads it — the caller is the reader,
    // and the caller is in another file. Empty for every walk that has no `out` parameter, which is
    // almost all of them.
    RequiredAtExit: HashSet<string>

    constructor() {
        Candidates = new HashSet<string>(StringComparer.Ordinal)
        Assigned = new HashSet<string>(StringComparer.Ordinal)
        Reported = new HashSet<ValueTuple<string, int, int>>()
        RequiredAtExit = new HashSet<string>(StringComparer.Ordinal)
    }
}
