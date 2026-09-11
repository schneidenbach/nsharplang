# Complete compiler reference resolver ownership

Accepted production revision: `a20dc98af8d444881730e0a192585ba91bd6f6b5`.

`a641613ed` deletes the complete 497-line C# CompilationReferenceResolver. All thirteen production
callers bind directly to the N# class in BootstrapServices. It owns recursive project builds,
package/framework discovery, dependency/cache mutation, runtime asset resolution and copying,
diagnostic formatting, HTTP download and cleanup. The class has two public static entries,
twenty-two private helpers, private construction and one private readonly two-minute HTTP client.
There is no C# resolver facade, decision callback or fallback.

Review preserved project/NuGet cache insertion and cycle behavior, first-match ordering, lazy
traversal, exact generic diagnostic enumeration, disposal and failure propagation. The only new
compiler prerequisite was the exact HttpClient.Timeout setter, verified in the earlier seed.
`3f880c86a` adds seven direct N# owner canonicals and four real command cases, including project and
NuGet runtime assets, framework resolution, child AOT failure, query no-build behavior and diagnostic
enumeration. Source and fixture receipts are in
`/private/tmp/nsharp-compilation-reference-resolver-owner-20260908`.

## Verification

The fresh isolated backend gate at the accepted revision passed in 560 seconds: 408 remaining C#
tests, 7,999 compiler canonicals, all native projects (including 82 migrated diagnostic methods),
twelve throughput cells, examples/templates and 68 IL assemblies. The first gate failed only its
stale corpus census; `a20dc98af` records the measured77-project correction and pins both added projects.
The failed first run is not acceptance evidence.

Official `setup-local.sh --skip-vscode --no-path-update` installed that exact revision. Ordinary
clean/restore/self-host passed 7,999/7,999 without SDK or package-path overrides. Installed native
families passed47/196/76/4/82. The four reference tests initially stopped at repository discovery
when hosted from the installation directory; rerunning via a byte-verified copy of the installed
CLI inside the isolated repository passed. All78 copied CLI/LSP payload files remain byte-identical.

Unfiltered installed IL verification passed BootstrapServices1235types/10927methods and
Compiler5types/58methods. Installed metadata confirms the resolver exists solely in BootstrapServices,
its API/client contract, and no NSharpTests classes in production BSS/Compiler/CLI. Both feeds match
all four archives; ten Release payloads and twelve restored SDK cache files match the package.

SDK SHA-256: `7869e52c846e887feffc6bd23837c1a0372c686219347baf6e4ece41e447a8cb`.
Final installed receipt: `full-owner-installed-verification/final-receipt.json` under the evidence
directory above; SHA-256 `870220c3fa8d5ed7e41cb2242581f2c1438eda2a643f678ef91b87d59f848e77`.
Fresh gate log: `root-full-owner-integration-gate-r2.log`; SHA-256
`017abc3509a66aec7ad9f7be3e3398846e87c9339d2633323d3ff036ac0e4cee`.

## Remaining objective

Compiler-wide completion is still open. The complete SDK EmitIlAssembly task retains compiler
reference-assembly scanning/rewrite decisions in C# and is actively moving to N# with actual-source
proven MSBuild/Cecil prerequisites and complete behavior tests. The existing Cecil writer remains;
no new metadata writer is required. Additional reviewed workspace/import and command compiler
canonicals are queued for the next integration. CLI/editor policy, runtime rewrite, NativeAOT and
broader branch initiatives remain separately recorded.
