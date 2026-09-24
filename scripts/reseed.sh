#!/usr/bin/env bash
#
# Republish the pinned stage-0 compiler seed.
#
# N# is self-hosted: `src/NSharpLang.Compiler.Core` is N# source that only an already-built N# SDK can
# compile. `bootstrap/` holds that SDK as two committed NuGet packages, and replacing them is the one
# procedure in this repository that can brick a clean checkout. It is a RUNBOOK, not a build step: the
# order below is load-bearing and every step exists because skipping it produced a seed that could not
# rebuild itself.
#
#   1. pack the SDK and runtime with the CURRENT seed
#   2. install those packages into the seed directory and re-pin SHA256SUMS
#   3. evict the old same-version packages from the NuGet cache (a republished 0.1.0 is otherwise
#      served from the cache forever, and the whole run proves nothing)
#   4. verify the seed's bytes, identities and SDK payload
#   5. rebuild the compiler from scratch with the NEW seed
#   6. pack AGAIN -- these are the packages a compiler COMPILED BY ITSELF produces, and they are the
#      ones that get committed; a one-stage seed cannot carry a change to the MSBuild task surface,
#      because stage 1's tasks were built by the OLD SDK
#   7. install stage 2 and rebuild from scratch a second time
#   8. run the compiler-service estate against the seed that will be committed
#
# The seed directory and NuGet cache are overridable so the runbook can be exercised without touching
# the committed seed or the shared package cache:
#
#   NSHARP_RESEED_BOOTSTRAP_DIR=/tmp/seed-probe \
#   NSHARP_RESEED_PACKAGES_DIR=/tmp/seed-probe-packages \
#   NSHARP_RESEED_STOP_AFTER=verify \
#     ./scripts/reseed.sh
#
# NSHARP_RESEED_STOP_AFTER takes a step name (pack, install, evict, verify, rebuild, repack,
# reinstall, rebuild2, estate) and stops the run after it. DRY_RUN=1 prints every command and runs
# none of them.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
source "$NSHARP_SCRIPTS_DIR/lib/packages.sh"

BOOTSTRAP_DIR="${NSHARP_RESEED_BOOTSTRAP_DIR:-$NSHARP_REPO_ROOT/bootstrap}"
STAGE_ROOT="${NSHARP_RESEED_STAGE_ROOT:-$NSHARP_REPO_ROOT/artifacts/reseed}"
STOP_AFTER="${NSHARP_RESEED_STOP_AFTER:-}"
CORE_PROJECT="src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"
# Every project the Core build compiles with the seed: Core itself and each slice carved out of it,
# which Core's `project:` dependencies build first. Building CORE_PROJECT builds them all.
COMPILER_PROJECT_DIRS=("src/NSharpLang.Compiler.Model" "src/NSharpLang.Compiler.Syntax" "src/NSharpLang.Compiler.Core")
ESTATE_PROJECTS=("src/NSharpLang.Compiler.Syntax/NSharpLang.Compiler.Syntax.csproj" "$CORE_PROJECT")
SEED_PACKAGES=("NSharpLang.Sdk" "NSharpLang.Runtime")

reseed_absolute_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$NSHARP_REPO_ROOT" "$path"
    fi
}

# `dotnet restore` runs from the repository root while verification and eviction run from the
# caller's shell. Resolve an explicitly supplied relative cache root once so all three use the
# same directory.
if [[ -n "${NSHARP_RESEED_PACKAGES_DIR:-}" ]]; then
    export NUGET_PACKAGES="$(reseed_absolute_path "$NSHARP_RESEED_PACKAGES_DIR")"
elif [[ -n "${NUGET_PACKAGES:-}" ]]; then
    export NUGET_PACKAGES="$(reseed_absolute_path "$NUGET_PACKAGES")"
fi

nsharp_require_command dotnet
nsharp_require_command python3
nsharp_require_command shasum

nsharp_configure_stable_dotnet_build_flags

reseed_should_stop() {
    [[ "$STOP_AFTER" == "$1" ]]
}

reseed_seed_version() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["msbuild-sdks"]["NSharpLang.Sdk"])' \
        "$NSHARP_REPO_ROOT/src/NSharpLang.Compiler.Core/global.json"
}

reseed_packages_root() {
    printf '%s\n' "${NUGET_PACKAGES:-$HOME/.nuget/packages}"
}

reseed_sha256() {
    local output digest ignored
    if ! output="$(shasum -a 256 "$1")"; then
        echo "Error: could not calculate SHA256 for $1" >&2
        return 1
    fi
    read -r digest ignored <<< "$output"
    if [[ ! "$digest" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Error: SHA256 command returned an invalid digest for $1" >&2
        return 1
    fi
    printf '%s\n' "$digest"
}

# `reseed_verify` has already authenticated the bootstrap bytes when this runs. Restore must now
# put those SAME bytes in NuGet's exact lower-cased package paths before the compiler may build;
# otherwise a same-version cache hit can make the rebuild prove an older seed instead of this one.
reseed_verify_restored_packages() {
    local version packages_root package package_lower bootstrap_package cache_package bootstrap_digest cache_digest
    version="$(reseed_seed_version)"
    packages_root="$(reseed_packages_root)"

    nsharp_log "Verifying restored seed package bytes in $packages_root"
    for package in "${SEED_PACKAGES[@]}"; do
        package_lower="$(nsharp_lowercase "$package")"
        bootstrap_package="$BOOTSTRAP_DIR/$package.$version.nupkg"
        cache_package="$packages_root/$package_lower/$version/$package_lower.$version.nupkg"

        if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
            nsharp_print_command shasum -a 256 "$bootstrap_package"
            nsharp_print_command shasum -a 256 "$cache_package"
            continue
        fi

        if [[ ! -f "$bootstrap_package" ]]; then
            echo "Error: verified bootstrap package is missing: $bootstrap_package" >&2
            exit 1
        fi
        if [[ ! -f "$cache_package" ]]; then
            echo "Error: restored NuGet cache package is missing: $cache_package" >&2
            exit 1
        fi

        if ! bootstrap_digest="$(reseed_sha256 "$bootstrap_package")"; then
            return 1
        fi
        if ! cache_digest="$(reseed_sha256 "$cache_package")"; then
            return 1
        fi
        if [[ "$cache_digest" != "$bootstrap_digest" ]]; then
            echo "Error: restored NuGet cache package differs from verified bootstrap:" >&2
            echo "  cache: $cache_package" >&2
            echo "  seed:  $bootstrap_package" >&2
            exit 1
        fi
    done
}

# STEP 1 / 6 -- pack. The package set is `nsharp_pack_package_set`, the same one the release scripts
# use, so a seed can never be built by a second, drifting recipe.
reseed_pack() {
    local stage_dir="$1"
    nsharp_log "Packing the SDK and runtime into $stage_dir"
    nsharp_run rm -rf "$stage_dir"
    nsharp_run mkdir -p "$stage_dir"
    nsharp_pack_package_set "$stage_dir" q
}

# STEP 2 / 7 -- install. ONLY the two seed packages move: the compiler and template packages are
# release artifacts, not stage-0 input, and a seed directory holding them would make every consumer
# restore resolve the compiler from the seed rather than from the build.
reseed_install() {
    local stage_dir="$1"
    local version
    version="$(reseed_seed_version)"
    nsharp_log "Installing the seed into $BOOTSTRAP_DIR"
    nsharp_run mkdir -p "$BOOTSTRAP_DIR"
    local package
    for package in "${SEED_PACKAGES[@]}"; do
        local file="$package.$version.nupkg"
        if [[ "${DRY_RUN:-0}" -eq 0 && ! -f "$stage_dir/$file" ]]; then
            echo "Error: packed seed is missing $file" >&2
            exit 1
        fi
        nsharp_run cp "$stage_dir/$file" "$BOOTSTRAP_DIR/$file"
    done

    nsharp_log "Re-pinning $BOOTSTRAP_DIR/SHA256SUMS"
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        (
            cd "$BOOTSTRAP_DIR"
            # Sorted so the manifest's order is the file listing's order and a re-pin diffs as a
            # digest change rather than a reshuffle.
            shasum -a 256 $(printf '%s\n' "${SEED_PACKAGES[@]/%/.$version.nupkg}" | sort) > SHA256SUMS
        )
        cat "$BOOTSTRAP_DIR/SHA256SUMS"
    else
        nsharp_print_command shasum -a 256 "${SEED_PACKAGES[@]/%/.$version.nupkg}"
    fi
}

# STEP 3 -- evict. A republished seed keeps its VERSION, so NuGet serves the extracted copy of the
# OLD bytes from the global cache and the rebuild below silently proves nothing. The two directories
# are named in full: a glob that matches nothing aborts the whole `rm` under `set -u` in some shells,
# and a glob that matches too much would delete a consumer's unrelated NSharpLang packages.
reseed_evict() {
    local packages_root
    packages_root="$(reseed_packages_root)"
    nsharp_log "Evicting the previous seed from $packages_root"
    nsharp_run rm -rf "$packages_root/nsharplang.sdk"
    nsharp_run rm -rf "$packages_root/nsharplang.runtime"
}

# STEP 4 -- verify. The same gate CI runs before it executes the seed at all.
reseed_verify() {
    nsharp_log "Verifying the seed"
    NSHARP_BOOTSTRAP_DIR="$BOOTSTRAP_DIR" nsharp_run python3 "$NSHARP_SCRIPTS_DIR/verify-bootstrap.py"
}

# STEP 5 / 7 -- rebuild the compiler FROM SCRATCH with the seed just installed. `obj` carries the
# restored SDK's resolved path in `project.assets.json`, so a rebuild that keeps it can run the old
# seed's tasks against the new packages and report a success that no clean machine can reproduce.
# That holds for EVERY project the Core build compiles: one stale carved slice would be emitted by
# the old seed and handed to Core as a reference, and the rebuild would prove nothing about it.
reseed_rebuild() {
    local label="$1"
    local project_dir
    nsharp_log "Clean self-rebuild of the compiler ($label)"
    for project_dir in "${COMPILER_PROJECT_DIRS[@]}"; do
        nsharp_run rm -rf "$NSHARP_REPO_ROOT/$project_dir/obj" "$NSHARP_REPO_ROOT/$project_dir/bin"
    done
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet restore "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$CORE_PROJECT" --force-evaluate -v q
    reseed_verify_restored_packages
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet build "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$CORE_PROJECT" --no-restore -v q
}

# STEP 8 -- the estate. The seed is only republishable if the compiler it produces still passes the
# compiler-service tests, and those need their own restore: `NSharpExcludeTests` is evaluated at
# RESTORE time, so a `dotnet test` after any other build silently runs zero tests and exits 0.
# Every compiler project whose own directory holds estate rows runs them (Compiler.Syntax carries its
# own; the rest still sit in Core's slice directories).
reseed_estate() {
    local estate_project
    nsharp_log "Running the compiler-service estate against the new seed"
    for estate_project in "${ESTATE_PROJECTS[@]}"; do
        nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet restore "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$estate_project" -p:NSharpExcludeTests=false --force-evaluate -v q
        nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet test "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$estate_project" -p:NSharpExcludeTests=false --no-restore -v q --nologo
    done
}

nsharp_log "Reseeding $BOOTSTRAP_DIR from $NSHARP_REPO_ROOT"
echo "    NuGet packages: ${NUGET_PACKAGES:-$HOME/.nuget/packages}"
echo "    Stage output:   $STAGE_ROOT"

reseed_pack "$STAGE_ROOT/stage1"
if reseed_should_stop pack; then exit 0; fi
reseed_install "$STAGE_ROOT/stage1"
if reseed_should_stop install; then exit 0; fi
reseed_evict
if reseed_should_stop evict; then exit 0; fi
reseed_verify
if reseed_should_stop verify; then exit 0; fi
reseed_rebuild "stage 1"
if reseed_should_stop rebuild; then exit 0; fi

reseed_pack "$STAGE_ROOT/stage2"
if reseed_should_stop repack; then exit 0; fi
reseed_install "$STAGE_ROOT/stage2"
if reseed_should_stop reinstall; then exit 0; fi
reseed_evict
reseed_verify
reseed_rebuild "stage 2"
if reseed_should_stop rebuild2; then exit 0; fi

reseed_estate

nsharp_log "Reseed complete"
echo "Commit $BOOTSTRAP_DIR/*.nupkg and $BOOTSTRAP_DIR/SHA256SUMS together."
