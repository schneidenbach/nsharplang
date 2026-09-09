# Pinned compiler seed

N# is self-hosted. A clean build needs an already compiled SDK before it can compile
Compiler Core or the SDK's own build tasks. These two NuGet packages are that
stage-0 input, not a fallback compiler implementation.

The seed is the locally built SDK/runtime 0.1.0 captured at `6e1377dbc` on
September 9, 2026, after the accepted compiler ownership and Core rename gates. `SHA256SUMS` pins its exact bytes.
`python3 scripts/verify-bootstrap.py` checks the hashes and package identities against
the compiler's SDK pin before CI executes the seed. The root `NuGet.config` makes the
seed available on clean machines, including public fork builds, without credentials.
The packages contain portable managed .NET 10 assemblies.

To repin, build and verify the new SDK using the current seed, copy the resulting
SDK/runtime packages here, update the compiler's SDK/runtime pins if their versions
change, regenerate `SHA256SUMS`, and run a clean build plus the fresh product gate.
Commit the packages and checksums together. Never depend on a disposable PR release
as the compiler seed; closing that PR must not break future builds.
