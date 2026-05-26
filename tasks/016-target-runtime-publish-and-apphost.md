# Task 016: Target Runtime Publish And Apphost

Priority: P2.

Make `nlc publish --runtime` and `nlc publish --self-contained` produce real .NET deployment artifacts, including apphost/self-contained bundles, rather than only supporting portable framework-dependent output and current-host launchers.

## User Outcome

A developer can publish an N# executable for a target runtime and know whether the artifact is portable framework-dependent, runtime-specific framework-dependent, or genuinely self-contained.

## Scope

- Design the publish pipeline for runtime-specific framework-dependent apphost output.
- Design true self-contained publish support, including runtime pack resolution and apphost generation.
- Define which cross-runtime scenarios are supported on each host OS and which require publishing on the target OS.
- Preserve the project.yml-first workflow without requiring users to hand-author build settings in `.csproj`.
- Decide whether the implementation should invoke MSBuild/.NET SDK apphost targets, synthesize equivalent artifacts, or use a small generated compatibility project internally.
- Add stable text output and JSON output if publish automation becomes schemaVersioned.
- Update docs, website docs, and help text once the workflows are real.

## Likely Files

- `src/NSharpLang.Cli/Program.cs`
- `src/NSharpLang.Cli/Program.Backends.cs`
- `src/NSharpLang.Sdk`
- `src/NSharpLang.Compiler`
- `tests/CompilationBackendTests.cs`
- `tests/CliCommandTests.cs`
- `docs/guide/cli-reference.md`
- `website/docs/cli-reference.md`
- `memory/components/cli-toolchain.md`

## Acceptance

- `nlc publish --runtime <current-rid>` produces a real runtime-specific framework-dependent apphost where .NET supports it.
- `nlc publish --self-contained --runtime <rid>` produces an artifact that runs without a globally installed `dotnet`.
- Unsupported cross-runtime scenarios fail before producing partial artifacts and explain the supported alternatives.
- Publish output clearly states artifact type, runtime identifier, output path, and whether a global .NET runtime is required.
- Scenario tests cover portable, current-runtime, self-contained, and unsupported cross-runtime paths.

## Verification

- Run focused publish tests on the current host runtime.
- Where available, validate at least one self-contained artifact without relying on global `dotnet`.
- Run `./scripts/test-all.sh` before committing.
