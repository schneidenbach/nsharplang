# Visual IDE re-verification, 2026-09-02 (evening), systems-language 529ad23bf

Follow-up to `../2026-09/README.md`. That record filed four IDE defects (D1 to D4) against
d26460045; this one verifies their fixes plus the formatter's new wrapping rule and the two new
hover behaviours, all on one build of the extension, in the real editor, with computer-use.

| Field | Value |
|---|---|
| Commit verified | `529ad23bf` (pushed `systems-language` tip at the time; `verify/ide-2026-09-02b` branched from it) |
| Extension | `nsharp-0.6.0.vsix` built by `scripts/reload-vscode-extension.sh` from this worktree |
| VSIX sha256 | `2499bb3b4273ff406074e8d9695b5885ade7c0248c72996219e3bdf758bd5bea` |
| Language server | `server/LanguageServer.dll` inside the VSIX, built 2026-09-02 20:39, installed to `~/.vscode/extensions/nsharp.nsharp-0.6.0`; the server process that served the verified window started 20:50:39 under a VS Code process started 20:50:37 (see "Harness finding") |
| VS Code | 1.136.0 on macOS (Darwin 24.6.0); it self-updated from 1.134 during the session |
| Sample project | `examples/12-multi-file-projects/WeatherDemo` with a workspace `.vscode/settings.json` (`editor.formatOnSave: true`, `files.autoSave: off`) and two scratch files, `FormatProbe.nl` and `RawProbe.nl`; none of these are committed, the probe sources are copied under `format-probe/` |

The editor was driven exactly as in the first record: click-tier computer-use, edits written to
disk, cursor placement with `code -g`, commands through the menu bar and the Command Palette,
quick fixes through the lightbulb, `screencapture -R` for the on-disk PNGs.

## Results

| Flow | Result | Screenshots | Observed |
|---|---|---|---|
| 1. D3: member completion after a trailing `.` via Trigger Suggest | PASS | `d3-completion-record-fresh.png` (fresh 529ad23bf server); the service-class and `string` receivers were observed on the 385b7e8d1 server, which already carried the D3 fix, see `stale-385b7e8d1/d3-completion-*.png` | `tc := forecast.` (record from `Models/WeatherForecast.nl`, a cross-file receiver) lists exactly `Date`, `TemperatureC`, `Summary`, `TemperatureF` as properties. `svc := service.` (class from `Services/WeatherService.nl`) lists `summaries` (field, `string[]`) and the four methods. `upper := summary.` (`string`) lists `String` members with method and property icons, ending with `Chars` and `Length`. No scope identifiers, no keywords, no `get_`/`set_`/`add_`/`remove_` accessors anywhere in the lists. See observations O1 and O2. |
| 2. Format-on-save | PASS | `format-full-after-save.png`, `format-rawprobe-fresh-after-save.png`; sources in `format-probe/` | On File > Save of `FormatProbe.nl` the hand-wrapped `String.Join(", ",` / `names)` became one argument per line, block-indented, closer alone on its own line, no trailing comma; the long single-line `String.Join(" | ", ...)` stayed on one line; `Task.Run(() => {` ... `})` stayed hugged; the multi-line `[trusted(reason: ..., owner: ..., review: ...)]` attribute and the `"""` raw string are byte-identical (`diff` shows only the wrapped call changed). Saving `RawProbe.nl`, which holds a plain `"""` and an interpolated `$"""` raw string, left the file byte-for-byte unchanged with no formatter warning in the log. |
| 3. D1: hover inside an interpolated-string hole | PASS | `d1-hover-interpolation.png` | `{forecast.TemperatureC}` inside `$"..."` hovers as `field TemperatureC: int`, `Defined in: Models/WeatherForecast.nl`. |
| 3. D2: hover on BCL members | PASS | `d2-hover-adddays.png`, `d2-hover-now.png`, `d2-hover-length.png`, `d2-hover-toarray.png`, `d2-hover-toupper.png` | `AddDays`: `method AddDays: DateTime AddDays(double value)`, "Returns a new DateTime that adds the specified number of days to the value of this instance.", `Declaring Type: System.DateTime`. `Now`: `property Now: DateTime { get; }`, "Gets a DateTime object that is set to the current date and time on this computer, expressed as the local time.", `System.DateTime`. `summaries.Length`: `property Length: int { get; }`, "Gets the total number of elements in all the dimensions of the Array.", `System.Array`. `result.ToArray()`: `method ToArray: WeatherForecast[] ToArray()`, "Copies the elements of the List to a new array.", `System.Collections.Generic.List<T>`. `summary.ToUpper()`: `method ToUpper: string ToUpper()`, "Returns a copy of this string converted to uppercase.", `System.String` (narrowed to the zero-argument overload at the call site, so no `(+1 overload)` suffix). |
| 3. Controls | PASS, unchanged | `control-hover-record-member.png`, `control-hover-local.png` | `forecast.Summary` on a plain line: `field Summary: string?`, defined in `Models/WeatherForecast.nl`. Local `summary`: `local summary: string`, its comment as doc, defined in `Program.nl`. |
| 4. D4: NL002 anchoring and the auto-import quick fix | PASS | `d4-quickfix-first-col.png`, `d4-lightbulb-middle-col.png`, `d4-lightbulb-last-col.png`, `d4-menu-on-new.png`, `d4-quickfix-applied.png` | With `scratch: StringBuilder` (field) and `sb := new StringBuilder()` (local) and no `import System.Text`, Problems shows `NL002 ... [Ln 5, Col 14]` and `[Ln 9, Col 19]`, both squiggles exactly under `StringBuilder`. With the cursor at the first (col 19), a middle (col 25) and the last (col 31) column of the type name the blue preferred-fix lightbulb appears and its menu offers `Add import System.Text`; with the cursor on `new` (col 16) only the AI Fix/Explain entries appear. Applying the fix inserted `import System.Text` as line 3 after the last import and both diagnostics cleared. |
| 5. Hover doc summaries and first-hover timing | PASS | `d2-hover-adddays.png` | The summary sentence renders under the signature for every BCL member above. The very first metadata hover in the fresh window (`AddDays`) was visible in the screenshot taken 1.2 s after the mouse arrived; every later hover was visible at the 2.5 s checkpoints and looked immediate. |
| 6. Call-site overload narrowing | PASS | `d2-hover-next-minmax.png`, `d2-hover-next-max.png` | `Random.Shared.Next(-20, 55)` hovers as `method Next: int Next(int minValue, int maxValue)`, "Returns a random integer that is within a specified range."; `Random.Shared.Next(summaries.Length)` as `method Next: int Next(int maxValue)`, "Returns a non-negative random integer that is less than the specified maximum."; both `Declaring Type: System.Random`, neither with an overload-count suffix. |

All six flows pass on 529ad23bf. D1, D2, D3 and D4 from the first record are fixed in the editor.

## Observations (not failures)

- O1. Overloads appear as repeated identical rows in the completion list (`CompareTo` twice,
  `EndsWith` four times, `Split` nine times, `IndexOf` six times, ...) rather than one row with
  an overload count, and members come in declaration order with the properties (`Chars`,
  `Length`) after every method rather than grouped or alphabetical. The first record's headless
  report from May had a `duplicateLabels` check; this list would fail it.
- O2. `service.` offers the camelCase field `summaries` on a receiver in another file. Under the
  project's naming rule (camelCase is file-private) that member is not accessible from
  `Program.nl`, so the list offers something the analyzer will reject.
- O3. `[trusted(...)]` without `review:` or without `[memory(safe)]` on the wrapper yields two
  NSYS100 diagnostics in a non-systems project; the probe was adjusted to carry both. Expected
  behaviour as far as this record can tell, noted because the peer's example attribute omitted
  them.

## Harness finding: three rebuilds did not restart the editor

`scripts/reload-vscode-extension.sh` was run four times during this re-verification (16:52 for
385b7e8d1, 18:21 for 7af97ac86, 19:00 for ef0a5bf65, 20:39 for 529ad23bf). Each run reported
success and installed the new VSIX, but only the first actually restarted VS Code: the window's
main process (pid 40309) and its language server (pid 40335) kept their 16:52 start times through
the next three runs, so the extension host kept running the 385b7e8d1 build while the files on
disk said 529ad23bf. The script's kill step is `killall "Visual Studio Code" 2>/dev/null ||
killall "Code" 2>/dev/null || true`, which cannot fail visibly. A pending VS Code self-update
(1.134 to 1.135 to 1.136 happened during the session) is the likely reason the kill did not take.

The consequence was real: flows run before the restart was noticed produced the wrong verdicts,
and they are kept under `stale-385b7e8d1/` purely as evidence of what that older build did:
the multi-line `[trusted(...)]` attribute was joined onto one line with `reason:` rewritten as
`reason =`, which re-triggered NSYS100 (`stale-385b7e8d1/FormatProbe.v2.after-save.nl`), and any
file containing a `"""` raw string was left unformatted because the formatter's output failed
the safety reparse ("Unexpected token '==' in expression"). Both are consistent with that build
predating the formatter batch and are not verdicts against 529ad23bf. BCL hovers were also
empty on that stale server. After `killall Code` by hand and a relaunch, every flow above was
re-run on a server whose start time (20:50:39) postdates the 529ad23bf install.

Suggested follow-up for the script (not done here, no product code was touched): after the kill,
wait until `pgrep -x Code` is empty, and print the new server process start time after the
window opens, so a verification record can prove which build it looked at.

## Files

- `d3-*.png`, `format-*.png`, `d1-*.png`, `d2-*.png`, `control-*.png`, `d4-*.png`: screenshots
  from the fresh 529ad23bf server (1372 px wide, 256 colours).
- `stale-385b7e8d1/`: screenshots and one formatted file taken before the editor restart was
  noticed; evidence for the harness finding only.
- `format-probe/FormatProbe.before.nl.txt`, `format-probe/FormatProbe.after-save.nl`,
  `format-probe/RawProbe.nl`: the format-on-save probe sources and the saved result.
- `language-server.log`: the language server log from the 20:50 relaunch onward.
