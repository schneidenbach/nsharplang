# Complete SDK compiler task ownership

Accepted production revision: `b13cc762299e8a046d2cd0747010a21a2c65082d`.

`e7e8dc035` replaces the complete 303-line C# EmitIlAssembly task with N#. SDK UsingTask routing
loads the class directly from BootstrapServices. Source/reference enumeration, compiler invocation,
diagnostic ordering, reference owner scanning, nested-type/forwarder traversal, assembly identity
reuse, metadata scope rewriting, writing and cleanup have one N# production owner. No C# adapter,
decision callback or fallback remains. MSBuild and Cecil objects are external ecosystem interfaces;
the existing Cecil writer remains sufficient for this compiler-ownership area.

The demonstrated prerequisites in `d0dc69536` cover exact MSBuild/Cecil runtime member shapes,
Required-property metadata and the required exception/collection behavior. N# canonical tests
exercise successful execution, ordered mutation, identity rejection and meaningful failures.
Public API review preserves ten properties, three Required attributes, ten private fields,
sixteen private helpers, public construction and Execute override.

Actual generation-two self-hosting found a same-identity assembly loaded in two distinct contexts.
`645cdfed0` prefers executable handles from the compiler's own load context for exact identity
collisions. Semantic metadata/reference ordering and the original first-loaded snapshot remain
unchanged. The actual second and third generations now build and pass unfiltered IL verification;
`518744372` adds deterministic N# collision and wrong-identity controls.

## Verification

The fresh isolated backend gate passes in562s:399 C# integration tests,8017 N# compiler tests,
56 native-project pass entries,12 throughput cells, templates/examples and68 IL assemblies.
The first gate failed a generated Web API template build; it is not acceptance evidence. The second
gate preserves its workspace and passes that build with diagnostics visible.

Official setup installed the accepted revision. An ordinary clean/restore/self-host with no SDK or
package-path overrides passes8017/8017. Installed native suites pass47 reflection,197 columnar,
78 query,4 reference,88 diagnostic and12 SDK-owner cases. All112 copied installed host payloads
are byte-verified. Unfiltered installed IL verifies BSS1236types/10977methods, Compiler5/58 and
Build.Tasks3/33. Production contains no NSharpTests classes. The task exists solely in BSS with
the exact reviewed public/private/Required metadata. Both feeds match all four package archives;
ten Release payloads and twelve restored SDK cache files match the installed package.

SDK SHA256: `dc68e0d8d13bdb4b445e81ab9bcf6d1d8b50148d535008e6cd1ae632a8812630`.
Evidence: `/private/tmp/nsharp-sdk-owner-root-integration-20260909`.
Final installed receipt: `installed-verification/final-receipt.json`, SHA256
`4237f923ec20914bdfdac7d5b0e7479620e5e64d914e0c48b1b46d784bf026e9`.
Fresh gate log SHA256: `ccd1c08c2087d9a4b31275fa1c638667e1848c51ffa111ca49fb4517f69aa2f7`.

## Remaining compiler objective

Compiler-wide assertion and surviving-boundary review remains open. The exact define-flag fixture
now executes in N# (`b00e24c75`); its four replaced C# compiler assertion markers are removed.
Final audit found that the earlier receiver-generic successor used a reduced library fixture and
did not preserve the original executable wrapper, total diagnostic cardinality or contiguous
message assertion. Its complete exact-fixture correction is active separately. CLI/editor policy,
runtime reimplementation, NativeAOT and broader branch initiatives remain in the separate backlog.
