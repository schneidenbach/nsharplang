#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/nativeaot-warnings.sh"
PROJECT="src/NSharpLang.Cli/Cli.csproj"
MANIFEST="$SCRIPT_DIR/nativeaot-check-projects.txt"
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Release/net10.0/Cli.dll"
RID="${NATIVEAOT_RID:-$(dotnet --info | awk '/^ RID:/ { print $2; exit }')}"

if [[ -z "$RID" ]]; then
  echo "Could not determine the .NET host RID; set NATIVEAOT_RID explicitly." >&2
  exit 2
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nsharp-nativeaot-smoke.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

if ! dotnet build "$REPO_ROOT/$PROJECT" -c Release -v:q >"$TEMP_ROOT/jit-build.log" 2>&1; then
  cat "$TEMP_ROOT/jit-build.log" >&2
  exit 1
fi

if ! dotnet publish "$REPO_ROOT/$PROJECT" -c Release -r "$RID" -o "$TEMP_ROOT/r2r" \
  -p:PublishReadyToRun=true -v:q >"$TEMP_ROOT/r2r-publish.log" 2>&1; then
  cat "$TEMP_ROOT/r2r-publish.log" >&2
  exit 1
fi

AOT_PROPERTIES=(
  -p:PublishAot=true
  -p:EnableTrimAnalyzer=true
  -p:EnableAotAnalyzer=true
  -p:ILLinkTreatWarningsAsErrors=false
  -p:TreatWarningsAsErrors=false
  -p:TrimmerSingleWarn=false
)
if [[ -n "${NATIVEAOT_TARGETING_PACK_ROOT:-}" ]]; then
  AOT_PROPERTIES+=("-p:NetCoreTargetingPackRoot=$NATIVEAOT_TARGETING_PACK_ROOT")
fi
if [[ "${NATIVEAOT_ALLOW_MISSING_PRUNE_PACKAGE_DATA:-false}" == "true" ]]; then
  AOT_PROPERTIES+=(-p:AllowMissingPrunePackageData=true)
fi

if ! dotnet publish "$REPO_ROOT/$PROJECT" -c Release -r "$RID" -o "$TEMP_ROOT/aot" \
  "${AOT_PROPERTIES[@]}" -v:q >"$TEMP_ROOT/aot-publish.log" 2>&1; then
  cat "$TEMP_ROOT/aot-publish.log" >&2
  exit 1
fi

nsharp_check_nativeaot_warning_scopes "$TEMP_ROOT/aot-publish.log"

run_cli() {
  local host="$1"
  shift
  case "$host" in
    jit) dotnet "$CLI_DLL" "$@" ;;
    r2r) dotnet "$TEMP_ROOT/r2r/Cli.dll" "$@" ;;
    aot) "$TEMP_ROOT/aot/Cli" "$@" ;;
    *) echo "Unknown compiler host: $host" >&2; return 2 ;;
  esac
}

prepare_examples() {
  rm -rf "$TEMP_ROOT/workspace"
  mkdir -p "$TEMP_ROOT/workspace"
  cp -a "$REPO_ROOT/examples" "$TEMP_ROOT/workspace/examples"
  find "$TEMP_ROOT/workspace/examples" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
}

project_count=0
while IFS= read -r project; do
  [[ -z "$project" || "$project" == \#* ]] && continue
  source_root="$REPO_ROOT/examples/$project"
  if [[ ! -f "$source_root/project.yml" ]]; then
    echo "NativeAOT smoke manifest entry has no project.yml: $project" >&2
    exit 2
  fi

  label="${project//\//_}"
  for host in jit r2r aot; do
    prepare_examples
    project_root="$TEMP_ROOT/workspace/examples/$project"
    output_path="$TEMP_ROOT/$host-$label.json"
    status_path="$TEMP_ROOT/$host-$label.exit"
    set +e
    NLC_NO_DAEMON=1 run_cli "$host" check --json --project "$project_root" >"$output_path" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" >"$status_path"
    if [[ "$status" != 0 ]]; then
      echo "${host^^} check failed: $project (exit $status)" >&2
      cat "$output_path" >&2
      exit 1
    fi
  done

  for host in r2r aot; do
    if ! cmp -s "$TEMP_ROOT/jit-$label.json" "$TEMP_ROOT/$host-$label.json"; then
      echo "${host^^} check JSON differs from JIT: $project" >&2
      diff -u "$TEMP_ROOT/jit-$label.json" "$TEMP_ROOT/$host-$label.json" >&2 || true
      exit 1
    fi
    if [[ "$(cat "$TEMP_ROOT/jit-$label.exit")" != "$(cat "$TEMP_ROOT/$host-$label.exit")" ]]; then
      echo "${host^^} check exit code differs from JIT: $project" >&2
      exit 1
    fi
  done

  echo "PASS JIT/R2R/NativeAOT check parity: $project"
  project_count=$((project_count + 1))
done < "$MANIFEST"

if [[ "$project_count" -eq 0 ]]; then
  echo "NativeAOT smoke manifest selected no projects." >&2
  exit 2
fi

echo "NativeAOT compiler smoke passed for $project_count example projects on $RID."
