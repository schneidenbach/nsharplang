INVARIANT DIAGNOSTICS (c) — THE NL924 PROCESS BOUNDARY

Parent: 54d524580 on stream/invariant-diagnostics, rebased from c604e1d90 onto systems-language
6ea697316. The fourteen invariant sentences from (a) and the source reachability census from (b)
remain unchanged. This slice catches unexpected exceptions ESCAPING command dispatch, once, in N#.

THE FULL EXECUTE MOVE WAS MEASURED BEFORE THE FALLBACK

Program.Execute dispatches to private Program methods and residual C# command owners. BootstrapServices
is already a project dependency of Cli, so placing those direct calls there would require a reverse
reference and a dependency cycle. Neither SDK supports co-compiling the existing C# and an N# owner:

1. External dispatch probe, native project referencing the built Cli.dll:
   import NSharpLang.Cli
   import NSharpLang.Cli.Commands
   func main(): int { return Program.Execute(new string[0]) }
   `nlc check --json` and `nlc build` report NL704 for NSharpLang.Cli and NL301 for Program;
   Program is internal and Execute is internal, with private command methods below it.
2. A Microsoft.NET.Sdk scratch project with `return Boundary.Execute();` in Program.cs and
   `class Boundary { static func Execute(): int { return 0 } }` in Boundary.nl:
   dotnet build reports CS0103: The name 'Boundary' does not exist in the current context.
   The ordinary C# SDK does not compile the N# file.
3. The same scratch project changed to `<Project Sdk="NSharpLang.Sdk" />`, project.yml supplied,
   with `public class Host { public static int Invoke() => 0; }` in Program.cs and
   `func main(): int { return Host.Invoke() }` in Boundary.nl:
   the packaged SDK prints `Skipping CoreCompile for N# project; emitting direct IL assembly.`
   then NL301: Variable 'Host' not found. Its CoreCompile replacement omits the C# input.
4. A native N# probe with `Execute(action: Func<int>)`, `try { return action() } catch
   (error: Exception) { ... }` compiled and ran: synthetic invariant, stderr-only, exit 2.
   The renderer reads the concrete exception type through an object-typed receiver's GetType().

RULING APPLIED

The coordinator selected the handoff's no-growth fallback: Main's existing expression changes from
`=> Execute(args);` to `=> InternalErrorBoundary.Execute(() => Execute(args));`.
Program.cs remains 786 lines. The N# owner contains catch, message, docs lookup, and exit status.
Execute itself HAS NOT migrated. No mixed-language target, dispatch callback service, new C# owner,
or second command dispatcher was added. The C# file receives a fingerprint-only ratchet repin.

OUTPUT CONTRACT

error NL924: Internal compiler error.
This is a bug in N#, not in your code.
AnalyzerScopeStack requires a non-empty scope stack before Peek.
Exception: System.InvalidOperationException
Report this failure: https://schneidenbach.github.io/nsharplang/docs/errors/NL924

The process status is 2, stdout is untouched, and no stack trace or source span is invented. Render
can prefix a known file; Main has no known source file and supplies none. This same stderr diagnostic
applies to JSON requests; no new JSON envelope or schema is claimed, and earlier stdout can be partial.
The status census found no literal return 2 in command owners; kernel return-2 arms classify options
or modes. HOWEVER nlc run forwards DotnetRunner.RunPassthrough's process status at Program.Backends.cs
146/183, so any integer can also come from a user program. The documentation explicitly retains that
behavior: exit 2 plus NL924 distinguishes this boundary's failure. A native child-return-2 contract
proves stderr stays empty in that case.

CONTRACTS AND MEASURED SPELLINGS

- Three estate blocks: exact render with/without a filename; return-code passthrough 0/1/17;
  catalog row error severity, build-blocking, non-configurable, title and URL.
- Five native blocks in existing cli-command-contracts: synthetic exception exact stderr and status;
  the same output bytes extracted directly from the NL924 page; real private Main invoked by reflection
  with null arguments (an input the OS cannot supply) produces exact NullReferenceException NL924;
  existing stdout remains unchanged; ordinary status 17 remains unchanged; nlc run child status 2.
  No synthetic failure hook enters production.
- The cross-assembly static call with an INLINE lambda declines at emission. Binding a named
  `action: Func<int> = () => ...` first compiles and runs. The same-assembly estate and C# entry point
  accept their own direct lambda forms. `new object?[1]` in the reflection probe declines at
  parse.function; the established spelling `new object?[](1)` passes. A try/finally-only return in
  the native helper reports NL305; assigning a result inside try and returning after finally passes.
- Contract A's missing-page/unenforced-language-rule list remains ZERO. One separate SOURCE-repro
  exemption row names NL924 and the exact existing synthetic-output native test. The code must still
  be in the catalog and have a page. The referenced file, test identity, page link, and output fence
  are verified. This exemption never exempts a page or parks an unenforced language rule.
- Catalog partition: 69 compiler + 10 linter = 79 (was 68 + 10 = 78); pages 98 (was 97).

FOCUSED EVIDENCE

- ./scripts/dev.sh Cli: 124/124, zero failed; fresh CLI build green.
- Exact generated-name selection for 10 catalog + 3 boundary estate blocks: 13/13. Both restore
  and test explicitly use -p:NSharpExcludeTests=false. An initial filename-based filter selected
  only ONE test, because the generated class is NSharpTests; that one-test result is not the proof.
- tests/native/cli-command-contracts: 103/103 (was 98), including the pre-existing unknown-command
  exit-1 and JSON envelope contracts; all five new blocks passed.
- tests/native/error-docs-contract: 13/13 (was 12), including all source-page repros and exact NL924
  source-repro exemption checks.
- Root format check passed. Live BootstrapServices check: 424 checked files, 261 error
  rows overall; ZERO rows name the changed InternalErrorBoundary, DiagnosticCatalog, or ErrorCode
  owners. This is a changed-owner check, not a claim that the entire estate is semantically clean.
- Ownership first reported the changed Program.cs fingerprint plus OWN003 for both this decode and
  the inherited census when they carried `.nl.txt`. Renaming those documentation files to `.md`
  removed both unclassified-file failures. The observed Program.cs fingerprint is
  text-v1:31f140d5a06107ad; its unchanged ceilings yield observed head-v1:62f0367150863580.

REMAINING SCOPE (NOT DISCHARGED HERE)

Command-local catch(Exception) blocks can still convert internal failures to their ordinary exit-1
messages before this outer boundary sees them. They were not changed by this bounded slice. Their
future classification must separate expected command failures from invariant failures under each
command's documented JSON/text contract. Moving the whole Execute closure into N# remains ownership
work; the mixed-language SDK and assembly-direction obstacles above must be resolved, not replaced
with a permanent callback dispatcher.
