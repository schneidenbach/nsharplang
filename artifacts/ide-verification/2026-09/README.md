# Visual IDE verification, 2026-09-02

Visual verification of the N# VS Code extension in the real editor, driven with computer-use and
recorded with screenshots. This is the terminal condition that task 021's audit and the closeout
ledger (STATUS.md §3.8 / §2.4) recorded as undischarged: the VS Code-enabled gate and the headless
suite pass, but nobody had looked at the editor since the parser, analyzer and error-reporting
owners moved to N#.

| Field | Value |
|---|---|
| Commit verified | `d26460045` (local `systems-language` tip; `verify/ide-2026-09` branched from it) |
| Extension | `nsharp-0.6.0.vsix` built by `scripts/reload-vscode-extension.sh` from this worktree |
| VSIX sha256 | `853abbfc0cd74892b49dd2768e360ba7a7e84e0972c604cd7a40b38d59138568` |
| Language server | `server/LanguageServer.dll` inside the VSIX, built 2026-09-02 10:58, installed to `~/.vscode/extensions/nsharp.nsharp-0.6.0` |
| VS Code | 1.134.0 on macOS (Darwin 24.6.0) |
| Sample project | `examples/12-multi-file-projects/WeatherDemo` plus a scratch `Highlighting.nl` (not committed) |
| Systems project | copy of `docs/design/systems-samples/proofs/31-hot-metrics` with one allocation added in a `[hot]` function; sources in `h-systems-probe/` |
| CLI used for cross-checks | `src/NSharpLang.Cli` built Release from the same commit (`nlc check --systems-report`, `nlc query hover`, `nlc query completions`) |

## How the editor was driven

Computer-use granted VS Code at the "click" tier: left-click, mouse hover, scroll and screenshots
only, no keystrokes, no paste, and no keystroke injection by other means. Everything below was
therefore driven this way:

- **Text changes** were written to the file on disk. `files.autoSave` is `afterDelay` on this
  machine, the open buffer re-synced from disk, and the language server received `didChange`
  (visible in `language-server.log` as "File watcher event" followed by "Document updated").
  This is the closest available substitute for typing; the diagnostic latency and the
  re-analysis path are the same as for a typed edit, only the incremental-delta shape differs.
- **Cursor placement** used `code -g <file>:<line>:<col>`.
- **Commands** came from the menu bar (Go > Go to Definition, Go > Go to References, View >
  Problems) and from the Command Palette opened through the View menu and scrolled with the
  mouse (Trigger Suggest, Rename Symbol). Quick fixes were opened by clicking the lightbulb.
- **Screenshots** were taken with `screencapture -R` cropped to the VS Code window and reduced to
  1x, 256 colours (about 85 KB each). Every PNG in this folder is one of those captures.

Consequence: the rename input box cannot be filled or confirmed, so item g) stops at the widget.

## Results

| Item | Result | Screenshot(s) | Observed |
|---|---|---|---|
| a) Syntax highlighting: union, match, record, interpolated string | PASS | `a-syntax-highlighting.png` | Keywords, type names, union cases, record fields, the comment and the interpolated string with its `{...}` holes are all distinctly coloured; the file compiles clean (0 problems). |
| b) Live NL diagnostic with Elm-style text, squiggle on the right span, disappears when fixed | PASS | `b-diagnostic-hover.png`, `b-diagnostic-problems.png`, `b-diagnostic-cleared.png` | `limit: int = "seven"` produced NL202 within about a second: red squiggle exactly under `"seven"`, hover and Problems panel show `NL202: Variable 'limit' is typed as 'int', but the value is 'string'` followed by the full Elm body (source excerpt with carets, actual/expected, the int.Parse hint, docs link). Reverting the edit cleared it (status bar 0/0, "No problems have been detected"). This also confirms the rich-route NL202 message change: the headline is the full sentence, not "Type mismatch". |
| b2) Parser cast-lookahead fix | PASS | `b2-cast-lookahead-hover.png` | `print(forecasts.Length)` followed by `sum := 0` on the next line: no NL101/NL301/NL001, `sum` gets an `int` inlay hint and its own hover (`local sum: int`, defined in Program.nl). |
| c) Hover: user function | PASS | `c-hover-user-function.png` | `service.GetForecasts(7)` shows `function GetForecasts: (int) -> WeatherForecast[]`, the leading comment as doc, and `Defined in: Services/WeatherService.nl`. See observation O1 (no parameter names/defaults). |
| c) Hover: record member | FAIL inside interpolation, PASS elsewhere | `c-hover-record-member-in-interpolation.png`, `c-hover-date-in-interpolation.png`, `c-hover-record-member-plain.png` | `forecast.TemperatureC` on a plain line shows `field TemperatureC: int`; the same member inside `$"...{forecast.TemperatureC}..."` shows `field TemperatureC: string`, and `{forecast.Date...}` shows `field Date: string` (declared `DateTime`). Defect D1. |
| c) Hover: BCL member | FAIL | `c-hover-bcl-member-toupper.png` | `summary.ToUpper()` shows only `method ToUpper: ToUpper(...)` with no return type, declaring type or doc. `DateTime.Now`, `.AddDays(i)`, `Random.Shared.Next(...)`, `result.ToArray()`, `summaries.Length` and the `DateTime` type name show no hover at all after 3 to 4 seconds (hover on a user local in the same file worked immediately). Defect D2. |
| d) Completion after `.` on a user type and on a BCL type; ordering; no get_/set_ | FAIL | `d-completion-user-record.png`, `d-completion-bcl-assignment.png`, `d-completion-bcl-bare-statement.png` | With the cursor right after `tc := forecast.` or `upper := summary.`, Trigger Suggest lists the enclosing scope's identifiers followed by keywords (`day`, `dayForecast`, `forecast`, `forecasts`, `hotDays`, `Program`, `service`, `summary`, `tempRange`, `abstract`, `and`, `as`, ...) instead of the record's fields or `String`'s members. Ordering and accessor filtering could not be assessed. Defect D3. |
| e) Go to Definition and Find References across two files | PASS | `e-goto-definition.png`, `e-find-references.png` | Definition on `WeatherService` in Program.nl jumped to `class WeatherService {` in Services/WeatherService.nl with the name selected. References on the `GetForecasts` declaration peeked 4 hits: `service.GetForecasts(7)` in Program.nl, the declaration and two `GetForecasts(days)` calls in WeatherService.nl. |
| f) Code action offered and applied | PASS, span defect | `f-quickfix-cursor-on-List.png`, `f-quickfix-menu.png`, `f-quickfix-applied.png` | `xs := new List<int>()` without the import gave NL002 "I can't find 'List' — it looks like a missing import". The lightbulb offered the preferred fix `Add import System.Collections.Generic`; applying it inserted `import System.Collections.Generic` after the existing imports and the diagnostic cleared. But the diagnostic is anchored at `new` (Ln 8, Col 15), so with the cursor on `List` the lightbulb only offered the AI Fix/Explain entries. Defect D4. |
| g) Rename across files | BLOCKED (harness tier) | `g-rename-widget.png` | Rename Symbol on `service.GetHotDaysSummary(7)` opened the rename widget pre-filled and selected with `GetHotDaysSummary` (so `prepareRename` resolved the symbol and range). Typing a new name and confirming needs keystrokes the click-tier grant forbids, so the edit was not applied and cross-file rename remains unverified in the editor. |
| h) Systems profile: NSYS diagnostic renders and matches `nlc check --systems-report` | PASS | `h-systems-hover-problems.png`, `h-systems-report.json` | With `scratch := new byte[16]` inside `[hot] func RecordError`, the editor shows exactly what the CLI reports: NL001 at 15:5, NSYS010 `allocation not allowed in [hot] function` at 15:16, NSYS050 `unknown external call 'Console.WriteLine' has no systems summary` at 33:5; status bar 2 errors / 1 warning equals the CLI summary `{"errors": 2, "warnings": 1}`. Hover and Problems show the policy body ("Systems policy '[hot]' rejected the 'allocation' effect", effect path `RecordError`, the help line, docs link). See observation O2 on the one-character span. |

Summary: 6 of 8 items pass (a, b, e, f, h fully; c for user symbols on plain lines), 2 fail
(c for BCL members and interpolation holes, d entirely), 1 is blocked by the harness (g). Both
IDE-visible changes named for this tip (the full-sentence NL202 headline and the parser
cast-lookahead fix) are confirmed in the editor.

## Defects found

None of these were fixed here. Each has a repro that does not need VS Code where one exists.
`language-server.log` is the server's own log for the session (`~/.nsharp/lsp-20260902.log`);
it contains no errors or exceptions. Hover and completion handlers log only at Debug level, so
D1 to D3 leave no trace in it; the code-action requests for D4 are near its end.

### D1. Hover inside an interpolated-string hole reports `string` for every member

- Repro (editor): open `examples/12-multi-file-projects/WeatherDemo/Program.nl`, hover
  `TemperatureC` inside `{forecast.TemperatureC}` on the `print $"..."` line of the for loop
  (line 21, 1-based column 61). Shows `field TemperatureC: string`. Hover `Date` in
  `{forecast.Date:yyyy-MM-dd}` (column 24): `field Date: string`. The record declares
  `TemperatureC: int` and `Date: DateTime`.
- Repro (CLI, same result): `nlc query hover --no-daemon --project <WeatherDemo> --file Program.nl --pos 21:61 --text`
  prints `Signature: field TemperatureC: string`. So the owner is the shared code-intelligence
  hover, not the LSP handler.
- Control: `forecast.TemperatureC` on a plain line hovers as `field TemperatureC: int`
  (`c-hover-record-member-plain.png`); `nlc query hover ... --pos 20:33` on `forecast.Summary`
  gives `string?` as declared.
- Expected: the member's declared type regardless of the enclosing interpolated string.

### D2. Hover on BCL members shows nothing, or only a bare name

- Repro (editor): in `Services/WeatherService.nl` hover `AddDays` in `DateTime.Now.AddDays(i)`
  (line 21, col 36), `Now` (21:32), `Next` in `Random.Shared.Next(-20, 55)` (22:45), `ToArray` in
  `result.ToArray()` (27:23), `Length` in `summaries.Length` (23:65), and the `DateTime` type
  name (21:19): no hover appears. In `Program.nl` add `upper := summary.ToUpper()` and hover
  `ToUpper`: `method ToUpper: ToUpper(...)` only.
- Repro (CLI, same result): `nlc query hover ... --file Services/WeatherService.nl --pos 21:38 --text`
  prints `No symbol found`; on `ToUpper` it prints `Signature: method ToUpper: ToUpper(...)`.
- Reference: `.context/vscode-headless-report.json` (2026-05-25) recorded the hover on `ToUpper`
  as `**(method)** ToUpper` with the C# signature `string ToUpper()` and `Declaring Type:
  System.String`, so this is a regression of the BCL hover content.
- Expected: signature with parameter and return types, declaring type, and the API doc summary
  for BCL members, including members reached through static and chained receivers.

### D3. Member completion after a trailing `.` lists scope identifiers and keywords

- Repro (editor): in `Program.nl`, inside the for loop, add the line `tc := forecast.` (nothing
  after the dot), put the cursor after the dot, run Trigger Suggest. The list is the enclosing
  scope's identifiers followed by keywords, not `Date`, `TemperatureC`, `Summary`,
  `TemperatureF`. Same with `upper := summary.` (a `string` local) and with a bare `summary.`
  statement. The inlay hint shows `tc: unknown`.
- The completion request was issued with Trigger Suggest (trigger kind Invoked). By code
  inspection `CompletionHandler` treats a typed `.` and an invoked request the same way: it sets
  `isMemberAccess` from either the trigger character or the text before the cursor, then calls
  `GetMemberCompletionItems`, which only has the AST path `GetMemberCompletionViaAst`. That path
  needs a `MemberAccessExpression` at the cursor and resolves members only for N# user types via
  `GetNSharpTypeMembers`; there is no BCL member source. When it returns nothing the handler
  falls through to the generic document/semantic/keyword list, which is what the screenshots show.
- Repro (CLI, different result): `nlc query completions --no-daemon --project <WeatherDemo> --file Program.nl --pos <line>:<col>`
  at the same positions returns `"context": "memberaccess"` with the receiver resolved
  (`forecast: WeatherForecast` giving `Date`, `TemperatureC`, `Summary`, `TemperatureF`;
  `summary: System.String` giving `CompareTo`, `EndsWith`, ...). The LSP handler is therefore the
  broken owner; routing it through the same completions owner as `nlc query completions` is the
  obvious direction.
- Note: the headless suite's `completion` check passed with 39 `String` members on its own
  fixture, so that fixture does not exercise the trailing-dot shape; this exact repro belongs in
  the suite.
- Expected: the receiver's members (members before extension methods, no `get_`/`set_`
  accessors), for both user and BCL receivers.

### D4. NL002 is anchored on `new`, so the import fix is only offered with the cursor on `new`

- Repro (editor): in `Program.nl` add `xs := new List<int>()` in `Main` without
  `import System.Collections.Generic`. Problems shows `NL002 ... [Ln 8, Col 15]` and the squiggle
  sits under `new`, not under `List`. With the cursor on `List` the lightbulb offers only the AI
  Fix/Explain entries; with the cursor on `new` it offers the preferred
  `Add import System.Collections.Generic`, which applies correctly.
- Server log (`language-server.log`, near the end): `Code action requested ... at "[start: (7, 15), end: (7, 15)]"`,
  `Found 1 diagnostics at location`, `Returning 1 code actions` for the cursor on `new`.
- Expected: the diagnostic span on the unresolved type name `List` (and the fix offered there).

## Observations (not defects, worth a look)

- O1. The user-function hover shows the arrow form `(int) -> WeatherForecast[]` with no
  parameter name or default (`days: int = 5`); the signature-help and definition views have them.
- O2. NSYS010's span is one character (`length: 1` at the `n` of `new`, identical in the CLI
  report), so the squiggle is a single underlined letter rather than the allocation expression.
  Analyzer span choice, consistent between editor and CLI.
- O3. Opening `WeatherService.nl` logged "Document updated successfully with 12 diagnostics"
  followed immediately by "Published 0 diagnostics" for every file, that is, a single-file
  analysis before the project context is applied. Nothing flashed in the editor, but it is
  wasted work on every open.

## Files

- `a-` to `h-` PNGs: the screenshots listed in the table (1372 px wide, 256 colours).
- `h-systems-report.json`: `nlc check --project <probe> --systems-report` output (stderr was empty).
- `h-systems-probe/Program.nl`, `h-systems-probe/project.yml`: the systems probe project.
- `language-server.log`: the language server log for the session.
