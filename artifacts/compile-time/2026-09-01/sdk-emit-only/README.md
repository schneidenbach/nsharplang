# SDK emit-only measurement of `src/NSharpLang.Compiler.BootstrapServices`, 2026-09-01

The product builds the compiler's own sources through the MSBuild SDK with legacy analysis switched
off by project name (`src/NSharpLang.Sdk/Sdk/Sdk.targets`), so this is the only path that reaches IL
emit on this project (see `systems-language-closeout/MEASUREMENT-VERDICT-2026-09.md` §3). It runs the
PACKAGED compiler (`~/.nuget/local-feed/NSharpLang.Sdk.0.1.0.nupkg`, md5 `932ac6ca…`, packed from
`b57c661a0`), not the tip CLI.

Each `rebuild-<n>.log` is one run, taken on the idle machine right after the harness sweep, from the
worktree root:

```bash
/usr/bin/time -l dotnet build src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj \
  -c Debug -t:Rebuild -m:1 -nr:false --disable-build-servers -clp:PerformanceSummary -v:m
```

`noop.log` is the same command without `-t:Rebuild`, run sixth with nothing changed. The number to
read is the `EmitIlAssembly` row of MSBuild's `Task Performance Summary` (the compiler's own task,
excluding MSBuild), the `real` line of `/usr/bin/time` (the whole build), and its
`maximum resident set size` (bytes).

| run | EmitIlAssembly task | real | peak RSS |
|---|---:|---:|---:|
| rebuild-1 | 133,409 ms | 134.04 s | 656,818,176 B (626.4 MB) |
| rebuild-2 | 133,083 ms | 133.69 s | 640,729,088 B (611.0 MB) |
| rebuild-3 | 132,644 ms | 133.26 s | 619,560,960 B (590.9 MB) |
| rebuild-4 | 131,453 ms | 132.07 s | 661,569,536 B (630.9 MB) |
| rebuild-5 | 132,618 ms | 133.23 s | 620,871,680 B (592.1 MB) |
| **median of five** | **132,644 ms** | **133.23 s** | **640,729,088 B (611.0 MB)** |
| noop (no `-t:Rebuild`, nothing changed) | 132,263 ms | 132.84 s | 630,833,152 B |

The no-op run re-emitted in full: the SDK build of an N# project has no incremental skip.
403 non-test files / 172,653 lines → 1,302 lines/s on the median task time.
