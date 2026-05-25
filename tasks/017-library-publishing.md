# Task 017: Library Publishing Workflow

Priority: P2.

Make the N# library publishing workflow credible from template creation through NuGet packing and C# consumption.

## User Outcome

A developer can create an N# library, add package metadata, run tests if the template includes them, pack it, publish it, and consume the actual packed package from a C# project.

## Scope

- Audit library template, `project.yml` metadata, `nlc pack`, generated assemblies, docs, and C# consumption.
- Decide whether the library template should include a small `.tests.nl` example.
- Write a dedicated library publishing guide.
- Add an end-to-end test using an actual packed N# NuGet package, not only a project reference.

## Likely Files

- `templates`
- `src/NSharpLang.Cli/Commands/PackCommand.cs`
- `src/NSharpLang.Sdk`
- `docs`
- `website/docs`
- `tests`

## Acceptance

- Library template includes a small `.tests.nl` example or documents why not.
- Publishing guide covers metadata, `nlc pack`, NuGet push, and C# consumption.
- End-to-end test verifies a C# project can consume a packed N# package.
- Public docs avoid unsupported package claims.

## Verification

- Run focused pack/template/SDK tests while developing.
- Run the packed-NuGet C# consumption test.
- Run `./scripts/test-all.sh` before committing.
