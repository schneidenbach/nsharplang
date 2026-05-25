# Task 030: Polish NuGet Library Publishing

Priority: P2 ecosystem.

Work in the N# repository and make the NuGet library publishing story credible end to end. Library template and `nlc pack` exist, but publishing docs and consumption tests need polish.

## Scope

- Audit library template, `nlc pack`, package metadata, generated assemblies, docs, and C# consumption path.
- Decide whether the library template should include a small `.tests.nl` example.
- Write a dedicated library publishing guide.
- Add an end-to-end test proving a C# project can consume an actual packed N# NuGet package.

## Likely Files

- `templates`
- `src/NSharpLang.Cli/Commands/PackCommand.cs`
- `src/NSharpLang.Sdk`
- `docs`
- `website/docs`
- `tests`

## Acceptance

- Library template includes a small `.tests.nl` example or a deliberate documented reason not to.
- Dedicated library publishing guide explains package metadata, `nlc pack`, NuGet push, and C# consumption.
- End-to-end test verifies a C# project can consume an actual packed N# NuGet package, not only a project reference.
- Public docs avoid claiming unsupported package features.

## Verification

- Run focused pack/template/SDK tests while developing.
- Run the end-to-end packed NuGet consumption test.
- Run `./scripts/test-all.sh` before committing.
