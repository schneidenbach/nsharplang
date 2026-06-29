namespace NSharpLang.Compiler

import System
import System.Collections.Generic

public class DefiniteAssignmentState {
    Candidates: HashSet<string>
    Assigned: HashSet<string>
    Reported: HashSet<ValueTuple<string, int, int>>

    constructor() {
        Candidates = new HashSet<string>(StringComparer.Ordinal)
        Assigned = new HashSet<string>(StringComparer.Ordinal)
        Reported = new HashSet<ValueTuple<string, int, int>>()
    }
}
