namespace NSharpLang.Compiler

import System
import System.Collections.Generic

public class DefiniteAssignmentState {
    Candidates: HashSet<string> = new HashSet<string>(StringComparer.Ordinal)
    Assigned: HashSet<string> = new HashSet<string>(StringComparer.Ordinal)
    Reported: HashSet<ValueTuple<string, int, int>> = new HashSet<ValueTuple<string, int, int>>()
}
