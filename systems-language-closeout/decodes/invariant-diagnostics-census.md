INVARIANT-DIAGNOSTICS CENSUS — measured at 51fa6592b (worktree /private/tmp/nsharp-agent-wt/invariants)

FOURTEEN sites, not twelve. `grep "throw new" src/NSharpLang.Compiler.BootstrapServices/Analyzer*.nl`
(excluding .tests.nl) finds 14 InvalidOperationException throws. All 14 are InvalidOperationException;
no other exception type is thrown from an Analyzer* owner. (Repo-wide there are 1,172 IOE throws, but
the rest are the columnar backend, which has its own decline mechanism.)

FAMILY A — THE COMPILER'S OWN RUNTIME (process-local). 10 sites. The lookup names a type in the
ANALYZER PROCESS's core library, via Type.GetType(name) with no assembly qualifier or via
typeof(object).get_Assembly().GetType(name). Neither reads the user's reference set; both are
properties of the compiler's own .NET installation.
  1  AnalyzerFunctionBodies.nl:1231        SequenceDefinition          Type.GetType(fullName)
  2  AnalyzerDeclarationContext.nl:661     (Span<T>.ptr void type)     typeof(Action).GetMethod("Invoke")
  3  AnalyzerLoopSequence.nl:653           AsynchronousSequenceDefinition  Type.GetType(IAsyncEnumerable`1)
  4  AnalyzerLoopSequence.nl:662           NonGenericSequenceType      Type.GetType(IEnumerable)
  7  AnalyzerFunctionTypeFactory.nl:646    RequiredCoreType            typeof(object).Assembly.GetType
  8  AnalyzerResourceStatements.nl:965     DisposableRoot              Type.GetType(System.IDisposable)
  9  AnalyzerResourceStatements.nl:974     VoidRuntimeType             Type.GetType(System.Void)
 13  AnalyzerReflectionArgumentBinder.nl:1084 LiveVoidType             typeof(object).Assembly.GetType
 (10,11,12 are family C)

FAMILY B — THE METADATA LOAD CONTEXT. 3 sites. These read a context, but the context's SEARCH SET is
built in AnalyzerMetadataLoadSurface.Open() from RuntimeEnvironment.GetRuntimeDirectory(),
AppContext.BaseDirectory and the shared-framework version ladder — all properties of the compiler's
installation. The core is bound EAGERLY at construction (022/3b-3's finding), and the only
user-controllable AddSearchDirectory caller is LoadByPath, which runs AFTER the context exists and so
cannot displace the core.
  5  AnalyzerMetadataLoadSurface.nl:174    "MLC not opened"            Context == null
  6  AnalyzerMetadataLoadSurface.nl:179    "MLC core assembly not loaded"
 14  AnalyzerWellKnownTypes.nl:201         ResolveRequired             18 primitives from the context core

FAMILY C — INTERNAL WALK DISCIPLINE. 3 sites. An empty scope stack. Clear() empties it and the driver
pushes the global scope immediately; reaching these needs a walk that pops past global, which is a
compiler bug, not a source shape.
 10  AnalyzerScopeStack.nl:84   Peek()        "Stack empty."
 11  AnalyzerScopeStack.nl:93   GlobalScope() "Sequence contains no elements"
 12  AnalyzerScopeStack.nl:117  Pop()         "Stack empty."

NEGATIVE EVIDENCE MEASURED (no crash reproduced from user input):
  * 103-project `nlc check` sweep over the whole repository: 0 crashes, 0 unhandled exceptions,
    every exit code in {0,1}.
  * 5 adversarial malformed sources (unclosed class/func/if/while/for, surplus closing braces before
    and after declarations, a namespace with stray braces around an interface): all answered
    "ok": false with diagnostics, none crashed.
  * 3 project.yml attacks on the reference set (targetFramework net99.0, netstandard1.0, and omitted
    entirely): all answered ok: true. targetFramework does not reach the search set.

CATALOG FINDING: NL924 IS NOT IN THE TREE. ErrorCode.nl's 9xx block is 903, 905, 907, 923 only;
DiagnosticCatalog publishes no 924 and website/docs/errors has no NL924.md. STATUS §1 says so in its
own words ("NL924 is NOT in the tree") and records that a prior attempt — "the full record-and-drain
attempt, NL924 and the BeginAnalysis invariant" — is preserved at a coordinator scratchpad
`2bii-*-attempt.nl.txt` and "need only a door that admits them".

NO ESTATE PRECEDENT FOR A NON-THROW INVARIANT: a search for Fail/Unreachable/Invariant/Debug.Assert
helpers in the BootstrapServices product files finds none. The throw IS the estate's current idiom
(1,172 of them). So "replace the throw with the N# way of stating an invariant that the estate
already uses" has no existing answer to adopt — that is itself a finding for the coordinator.
