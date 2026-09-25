namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

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

    // THE LOCAL FUNCTIONS THIS BODY DECLARES, by name. A call to one of them reads whatever its body
    // reads, and the caller is where that question is answered — see `AnalyzerLocalFunctionCaptures`.
    LocalFunctions: Dictionary<string, LocalFunctionStatement>

    // THE CYCLE GUARD for that walk: the local functions whose bodies are currently being read. A
    // mutually recursive pair would otherwise re-enter each other forever.
    Active: HashSet<string>

    // COLLECT INSTEAD OF REPORT. Non-null only while a local function's body is being read on behalf
    // of a CALL to it: a read of an unassigned candidate lands here and the call site decides what to
    // say about it. Null for every ordinary walk, which is what makes the report the default.
    Collected: HashSet<string>?

    constructor() {
        Candidates = new HashSet<string>(StringComparer.Ordinal)
        Assigned = new HashSet<string>(StringComparer.Ordinal)
        Reported = new HashSet<ValueTuple<string, int, int>>()
        RequiredAtExit = new HashSet<string>(StringComparer.Ordinal)
        LocalFunctions = new Dictionary<string, LocalFunctionStatement>(StringComparer.Ordinal)
        Active = new HashSet<string>(StringComparer.Ordinal)
        Collected = null
    }
}
