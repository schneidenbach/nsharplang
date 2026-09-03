# Visual IDE verification, fourth round, systems-language a2d75f537

Follow-up to `../2026-09-02b/README.md`. That round recorded three observations (duplicate
overload rows in completion, a file-private member offered from another file, two NSYS100
diagnostics for one incomplete `[trusted]`) and a harness finding (the reload script installed
the VSIX without restarting VS Code). This round verifies the chips that answered them, plus two
spot checks that nothing regressed.

| Field | Value |
|---|---|
| Commit verified | `a2d75f537` (pushed `systems-language` tip at the time; `verify/ide-2026-09-02c` branched from it) |
| Extension | `nsharp-0.6.0.vsix` built by `scripts/reload-vscode-extension.sh` from this worktree |
| VSIX sha256 | `00063460ee94be29467a3dbc2f3b520624500d9565361e734d6adcdd18adb24d` |
| Language server | `server/LanguageServer.dll` inside the VSIX, built 2026-09-02 22:48; the server that served the verified window is pid 12382, started 22:48:13, child of the "Code Helper (Plugin)" process of the VS Code main process pid 12359 started 22:48:11 |
| VS Code | 1.136.0 on macOS (Darwin 24.6.0) |
| Sample project | `examples/12-multi-file-projects/WeatherDemo`, probes written to disk and reverted, none committed; the systems probe is a copy of `docs/design/systems-samples/proofs/31-hot-metrics` with one extra function, sources under `systems-probe/` |

Driven as in the earlier records: click-tier computer-use, on-disk edits, `code -g` for the
cursor, Command Palette > Trigger Suggest for completion, lightbulb clicks for quick fixes,
`screencapture -R` for the PNGs.

## The reload script's proof line

The script now waits for VS Code to exit and prints the language server it started. What it
printed this run (`reload-script-proof-lines.txt`):

```
   VS Code exited after 1s.
5. Language server under test:
   LanguageServer.dll pid 10584 started Wed Aug 5 21:29:33 2026
```

The wait works and the relaunch is real: a new VS Code main process (pid 12359, 22:48:11) and a
new server (pid 12382, 22:48:13) exist, and every flow below ran on that server. But the printed
line names the wrong process. It comes from `pgrep -f 'LanguageServer.dll' | head -n 1`, which
returns the lowest pid, and this machine carries thirteen orphaned `LanguageServer.dll`
processes from windows closed between July 7 and September 2 (parent pid 1), the lowest being
10584 from August 5. So the proof line is FAIL as a proof: it would have printed the same
August pid whether or not a new server started. `pgrep -n -f 'LanguageServer.dll'` (newest
matching process) prints pid 12382 here; picking the child of the newest "Code Helper (Plugin)"
process would be stricter still. Not changed here (no product or script code in this record).

## Results

| Flow | Result | Screenshots | Observed |
|---|---|---|---|
| 1. Completion on `summary.` (a `string` receiver) | PASS | `r4-completion-string-top.png`, `r4-completion-string-tail.png`, `r4-completion-split-overloads.png` | One row per member name: `Clone`, `CompareTo`, `Contains`, `CopyTo`, `EndsWith`, `EnumerateRunes`, `Equals`, `GetEnumerator`, `GetHashCode`, `GetPinnableReference`, `GetType`, `GetTypeCode`, ... `ToUpperInvariant`, `Trim`, `TrimEnd`, `TrimStart`, `TryCopyTo`, then the properties `Chars`, `Length`: methods first, then properties, each group alphabetical. No duplicate labels (`Trim` once where the previous round showed four, `Split` once). The overload count renders in the item detail: with the prefix `Spl` the single `Split` row's detail reads `String[] (+10 overloads)`; `Clone` reads `object` with no suffix. |
| 2. Completion on `service.` across namespaces | PASS | `r4-completion-service-outside.png`, `r4-completion-service-inside.png` | From `Program.nl` (no `namespace` line, so outside `WeatherDemo.Services`) `service.` lists only `GetForecast`, `GetForecasts`, `GetHotDaysSummary`, `GetMinMaxTemp`; the camelCase field `summaries` is not offered, and the class has no camelCase method to check. Control: `other := new WeatherService()` then `other.` inside `Services/WeatherService.nl` (in `namespace WeatherDemo.Services`) lists the same four methods and `summaries`. |
| 3. One NSYS100 for an incomplete `[trusted]` | PASS | `r4-nsys100-single.png`; source in `systems-probe/Program.nl` | `[trusted(reason: "probe: nothing unsafe happens here", owner: "ide-verification")]` with no `review:` and no `[memory(safe)]` on `func Audit` yields exactly one NSYS100, at `[Ln 19, Col 1]` (the `func` keyword of the wrapper): `NSYS100: [trusted] is missing the review metadata and [memory(safe)]`, body "Systems policy 'systems:strict' rejected the 'memorySafety' effect.", "effect path: Audit", "help: Write [trusted(reason: "...", owner: "...", review: "...")] and [memory(safe)] on the wrapper, after documenting the unsafe proof.", docs link. The file's only other problem is the pre-existing NSYS050 on `print Export(metrics)`. |
| 4a. Spot check: hover `.AddDays(` | PASS | `r4-hover-adddays.png` | `method AddDays: DateTime AddDays(double value)`, "Returns a new DateTime that adds the specified number of days to the value of this instance.", `Declaring Type: System.DateTime`. |
| 4b. Spot check: D4 quick fix | PASS | `r4-quickfix-applied.png` | `sb := new StringBuilder()` without `import System.Text`: NL002 at `[Ln 8, Col 19]` on the type name, the preferred lightbulb offers `Add import System.Text`, applying it inserts `import System.Text` after the last import and the diagnostic clears. |

All four flows pass on a2d75f537. The three observations from the previous round are closed in
the editor; the reload script's kill wait works but its proof line does not prove anything on a
machine with orphaned servers.

## Notes

- The systems probe was opened as a loose file from `/tmp/nsharp-ide-verify-sys` into the
  WeatherDemo window; the language server resolved that folder's `project.yml` (profile systems,
  mode strict) for it, which is why NSYS diagnostics appear without switching workspaces.
- NSYS100's span is the wrapper's `func` keyword (line 19), one line below the attribute it
  describes (line 18). Consistent with the previous rounds; noted, not judged.
- Thirteen orphaned `LanguageServer.dll` processes (parent pid 1, started July 7 to September 2)
  survive their windows on this machine. They cost memory and, as above, confuse any pid-based
  proof; the server does not seem to exit when its extension host goes away.

## Files

- `r4-*.png`: screenshots (1372 px wide, 256 colours).
- `reload-script-proof-lines.txt`: the script's kill-wait and proof lines from this run.
- `systems-probe/Program.nl`, `systems-probe/project.yml`: the systems probe.
- `language-server.log`: the language server log from the 22:48 relaunch onward.
