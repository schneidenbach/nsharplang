# Builds and unofficial releases

`Build` runs for PRs targeting main and pushes to main. Both jobs verify the checked-in
compiler seed before restoring; a clean runner does not need a developer's NuGet cache.
The build job compiles and tests Release, checks canonical formatting, runs native compiler and Docker installation tests, and packs the canonical SDK,
runtime, templates, compiler API, CLI/LSP toolset, and VS Code extension. The separate
IL verification job remains required before publication.

Successful same-repository PR builds publish GitHub prereleases named
`unofficial-pr-<number>-<run-id>-<attempt>`. Main publishes
`unofficial-main-<run-id>-<attempt>`. The unique tag identifies the exact source commit;
these releases never become GitHub's latest stable release. Package versions remain
the project's versions; these are downloadable development snapshots, not NuGet feed
publications. Fork PRs run the same build and upload the same downloadable Actions
artifact without receiving release write permission. Artifacts expire after 14 days.

Closing or merging a PR deletes every release and tag in that PR's exact namespace.
Main builds and official `v*` releases remain. Cleanup uses `pull_request_target` with
no checkout or execution of PR code; it shares a concurrency group with publication,
which rechecks the PR state and head SHA before creating a release. The cleanup
workflow can also be dispatched with a closed PR number to retry a failed deletion.
GitHub must have the cleanup workflow on the default branch before it can handle
closures; merge this workflow change before relying on automatic cleanup.

Official `v*` pushes retain the separate GitHub Packages publishing workflow.

The compiler migration's E0 ownership manifest is unchanged. The explicitly requested
delivery repair is recorded separately in
`tests/native/ownership-audit/DeliveryOwnership.nl`: twelve exact paths and fingerprints,
including both bootstrap binaries. This is not a directory or language exemption.
The live audit requires each file to exist and rejects changed contents, new adjacent
files, and removed E0 owners. Future delivery changes require reviewing this record.
The isolated product gate includes the seed packages instead of filtering them out.
