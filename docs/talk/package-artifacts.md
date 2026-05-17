# N# Launch Package Artifacts

Generated on 2026-05-16 from `/Users/spencer/code/nsharplang`.

This is a local release-artifact evidence file. It proves that the current tree can produce package artifacts and that the turnkey installer works against the local NuGet feed. It does not claim that any package has been published to NuGet, the VS Code Marketplace, Open VSX, or a GitHub Release.

## Supported release claims from this run

- Local NuGet package generation works for the CLI, compiler, language server, SDK, and templates.
- Local VS Code VSIX generation works.
- The turnkey installer works against `artifacts/nuget` with `--skip-vscode` in an isolated HOME.
- `nlc doctor --skip-vscode`, `nlc new`, `nlc build`, and `nlc run` work after installing from the local feed.
- Uninstall works for the locally installed CLI tool, language-server tool, and templates in the isolated HOME.
- Public exact version pinning is intentionally unsupported right now because package versions are mixed.

## Unsupported / not proven release claims

- NuGet.org publication is not proven. These artifacts were packed locally only.
- VS Code Marketplace or Open VSX publication is not proven. The evidence here is a local `.vsix` file plus local `code --install-extension` smoke output.
- A public GitHub Release asset URL for the VSIX is not proven.
- Do not claim a public `nlc convert` experience from this artifact run.
- Do not claim a single public NSharpLang version pin. Current artifacts still use mixed versions: CLI/SDK `0.1.0`, compiler/language-server/templates `1.0.0`, VSIX `0.6.0`.

## Commands run

```bash
./scripts/pack-nuget.sh
```

Wrapper log:

```text
/Users/spencer/code/nsharplang/artifacts/package-task-logs/pack-nuget.log
```

Result: exit status `0`. Generated NuGet artifacts and VSIX.

```bash
LOG_DIR=/Users/spencer/code/nsharplang/artifacts/package-task-logs/smoke-turnkey-abs ./scripts/smoke-turnkey-install.sh
```

Wrapper log:

```text
/Users/spencer/code/nsharplang/artifacts/package-task-logs/smoke-turnkey-abs-wrapper.log
```

Inner smoke log:

```text
/Users/spencer/code/nsharplang/artifacts/package-task-logs/smoke-turnkey-abs/20260516-170731/smoke.log
```

Result: exit status `0`. The smoke repacked NuGet artifacts with `SKIP_VSCODE_PACKAGE=1`, installed from the local feed in an isolated HOME, verified the CLI/toolchain, generated a console app, built it, ran it, and locally installed the VSIX with the `code` CLI.

```bash
RUN_DIR=/Users/spencer/code/nsharplang/artifacts/package-task-logs/smoke-turnkey-abs/20260516-170731
HOME="$RUN_DIR/home" \
PATH="$RUN_DIR/home/.dotnet/tools:$PATH" \
DOTNET_CLI_HOME="$RUN_DIR/home" \
NUGET_PACKAGES="$RUN_DIR/nuget-packages" \
./scripts/install.sh --source artifacts/nuget --skip-vscode --uninstall
```

Uninstall log:

```text
/Users/spencer/code/nsharplang/artifacts/package-task-logs/uninstall.log
```

Result: exit status `0`. The isolated CLI tool, language-server tool, and templates were uninstalled.

## Artifact outputs and checksums

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `artifacts/nuget/NSharpLang.Cli.0.1.0.nupkg` | 6,418,938 bytes | `3d199008bcb7b541afe3f52f2010bf85189f69d6a2ac0d4df70f909e63061015` |
| `artifacts/nuget/NSharpLang.Compiler.1.0.0.nupkg` | 488,620 bytes | `131412da366804817dc3b12ddfc80046d7edb79d3a23bb2028fe132d3c1b62f8` |
| `artifacts/nuget/NSharpLang.LanguageServer.1.0.0.nupkg` | 3,305,510 bytes | `f553a121c746a363be24c296f7e358de3b196280d0107597d0220f9d118bd42d` |
| `artifacts/nuget/NSharpLang.Sdk.0.1.0.nupkg` | 612,873 bytes | `a88b1fb0852a7e05ca6a1a3163d0959ed657b5fa50bbab9a235f1d7a5cdbe37d` |
| `artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg` | 11,020 bytes | `691d0a000aa4b8be4dfcbf3d1955b7888a174b0ca43773d14214a9a0c881779d` |
| `artifacts/vscode/nsharp-0.6.0.vsix` | 3,715,241 bytes | `3093656e74091ba5bdfa5e3a428104c7157a42bcc0850af378229e9efb48ddf5` |

## Build/package output excerpts

`./scripts/pack-nuget.sh` reported:

```text
Artifacts created successfully:
-rw-r--r--  1 spencer  staff   6.1M May 16 17:07 artifacts/nuget/NSharpLang.Cli.0.1.0.nupkg
-rw-r--r--  1 spencer  staff   477K May 16 17:07 artifacts/nuget/NSharpLang.Compiler.1.0.0.nupkg
-rw-r--r--  1 spencer  staff   3.2M May 16 17:07 artifacts/nuget/NSharpLang.LanguageServer.1.0.0.nupkg
-rw-r--r--  1 spencer  staff   599K May 16 17:06 artifacts/nuget/NSharpLang.Sdk.0.1.0.nupkg
-rw-r--r--  1 spencer  staff    11K May 16 17:06 artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg
-rw-r--r--  1 spencer  staff   3.5M May 16 17:07 artifacts/vscode/nsharp-0.6.0.vsix
```

The VSIX package step reported:

```text
DONE  Packaged: /Users/spencer/code/nsharplang/editors/vscode/nsharp-0.6.0.vsix (280 files, 3.54 MB)
✅ Extension built: /Users/spencer/code/nsharplang/editors/vscode/nsharp-0.6.0.vsix
```

The package step emitted non-blocking warnings:

- Existing nullable warnings in compiler code during the first Release build.
- NuGet readme warnings for `NSharpLang.Sdk`, `NSharpLang.Cli`, and `NSharpLang.LanguageServer`.
- VSIX warnings for missing extension license file and unbundled JavaScript files.

## Install smoke output excerpts

The installer correctly rejected unsupported public version pins:

```text
ERROR: scripts/install.sh does not support --version yet.
NSharpLang packages currently ship with mixed package versions, so one public version cannot safely pin the full toolchain.
Use the default latest install, or publish a unified release version across CLI, SDK, templates, compiler, and language server first.
```

Local-feed install succeeded:

```text
+ dotnet new install NSharpLang.Templates --add-source /Users/spencer/code/nsharplang/artifacts/nuget
Success: NSharpLang.Templates::1.0.0 installed the following templates:
Template Name           Short Name      Language  Tags
----------------------  --------------  --------  -------------
N# Class Library        nsharp-library  N#        Library/N#
N# Console Application  nsharp-console  N#        Console/N#
N# Test Project         nsharp-test     N#        Test/xUnit/N#
N# Web API Application  nsharp-webapi   N#        Web/WebAPI/N#

+ dotnet tool install -g NSharpLang.Cli --add-source /Users/spencer/code/nsharplang/artifacts/nuget
Tool 'nsharplang.cli' (version '0.1.0') was successfully installed.
+ dotnet tool install -g NSharpLang.LanguageServer --add-source /Users/spencer/code/nsharplang/artifacts/nuget
Tool 'nsharplang.languageserver' (version '1.0.0') was successfully installed.
```

`nlc doctor --skip-vscode` succeeded:

```text
N# doctor
status: ok

✓ dotnet: 10.0.107
✓ nlc: 0.1.0+e8b2084cdf0fa3bb602b239fee1a4a23b89766cc
✓ nlc global tool: NSharpLang.Cli
✓ language server tool: NSharpLang.LanguageServer
✓ templates: nsharp-console template is installed
✓ language-server: /Users/spencer/code/nsharplang/artifacts/package-task-logs/smoke-turnkey-abs/20260516-170731/home/.dotnet/tools/nsharp-lsp
! vscode-extension: skipped by --skip-vscode
```

`nlc new`, `nlc build`, and `nlc run` succeeded:

```text
Creating new console project: MyApp
Created: MyApp/project.yml
Created: MyApp/global.json
Created: MyApp/NuGet.config
Created: MyApp/Program.nl

Build succeeded.
    0 Warning(s)
    0 Error(s)
Build successful! (debug) [0.9s]

Running...

Hello, N#!
```

The smoke also verified the generated app used only the local NSharp feed:

```text
Registered Sources:
  1.  nsharp-local [Enabled]
      /Users/spencer/code/nsharplang/artifacts/nuget
```

Local VSIX install via `code` succeeded during the smoke:

```text
Installing extensions...
Extension 'nsharp-0.6.0.vsix' was successfully installed.
nsharp.nsharp
```

## Uninstall output excerpt

```text
==> Removing N# toolchain
+ dotnet tool uninstall -g NSharpLang.Cli
Tool 'nsharplang.cli' (version '0.1.0') was successfully uninstalled.
+ dotnet tool uninstall -g NSharpLang.LanguageServer
Tool 'nsharplang.languageserver' (version '1.0.0') was successfully uninstalled.
+ dotnet new uninstall NSharpLang.Templates
Success: NSharpLang.Templates::1.0.0 was uninstalled.
N# uninstall complete. Shared config under ~/.nsharp is left in place for auditability; remove it manually if desired.
```

## Notes / current blockers

- There is no blocker for local artifact generation: NuGet artifacts and a VSIX exist under `artifacts/`.
- Public launch is still blocked on choosing and completing the external VSIX publication path: Marketplace/Open VSX, or a versioned GitHub Release asset plus `NSHARP_VSIX_URL` release guidance.
- Public launch is also blocked on actual NuGet publication if the launch requires public NuGet.org installation instead of local-feed validation.
- Package readme/license/bundling warnings should be reviewed before a polished public release, but they did not block local artifact generation.
