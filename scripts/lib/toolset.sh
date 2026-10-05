#!/usr/bin/env bash

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

NSHARP_DEFAULT_INSTALL_DIR="${NSHARP_INSTALL_DIR:-$HOME/.nsharp}"

nsharp_install_dir() {
    printf '%s\n' "${1:-$NSHARP_DEFAULT_INSTALL_DIR}"
}

nsharp_packages_dir() {
    local install_dir
    install_dir="$(nsharp_install_dir "${1:-}")"
    printf '%s/packages\n' "$install_dir"
}

nsharp_require_safe_install_dir() {
    local install_dir="$1"
    if [[ -z "$install_dir" || "$install_dir" == "/" || "$install_dir" == "$HOME" ]]; then
        echo "Error: refusing unsafe N# install directory: ${install_dir:-<empty>}" >&2
        exit 1
    fi
}

nsharp_write_unix_launcher() {
    local output="$1"
    local display_name="$2"
    local app_relative_path="$3"

    mkdir -p "$(dirname "$output")"
    cat > "$output" <<EOF
#!/usr/bin/env bash
set -euo pipefail

resolve_link() {
    local target="\$1"
    local dir link
    while [[ -L "\$target" ]]; do
        dir="\$(cd -P "\$(dirname "\$target")" && pwd)"
        link="\$(readlink "\$target")"
        if [[ "\$link" == /* ]]; then
            target="\$link"
        else
            target="\$dir/\$link"
        fi
    done
    dir="\$(cd -P "\$(dirname "\$target")" && pwd)"
    printf '%s/%s\n' "\$dir" "\$(basename "\$target")"
}

is_dotnet_root() {
    local candidate="\${1:-}"
    [[ -n "\$candidate" && -x "\$candidate/dotnet" && -d "\$candidate/shared/Microsoft.NETCore.App" ]] || return 1
    compgen -G "\$candidate/shared/Microsoft.NETCore.App/10.*" >/dev/null
}

try_dotnet_root() {
    local candidate="\${1:-}"
    if is_dotnet_root "\$candidate"; then
        printf '%s\n' "\$candidate"
        return 0
    fi
    return 1
}

resolve_dotnet_root_from_executable() {
    local dotnet_path="\$1"
    local resolved bin_dir parent
    resolved="\$(resolve_link "\$dotnet_path")"
    bin_dir="\$(cd -P "\$(dirname "\$resolved")" && pwd)"
    parent="\$(dirname "\$bin_dir")"

    try_dotnet_root "\$bin_dir" && return 0
    try_dotnet_root "\$parent/libexec" && return 0
    try_dotnet_root "\$parent" && return 0
    return 1
}

resolve_dotnet_root() {
    local arch_root=""
    case "\$(uname -m)" in
        arm64|aarch64) arch_root="\${DOTNET_ROOT_ARM64:-}" ;;
        x86_64|amd64) arch_root="\${DOTNET_ROOT_X64:-}" ;;
        i386|i686) arch_root="\${DOTNET_ROOT_X86:-}" ;;
    esac

    try_dotnet_root "\$arch_root" && return 0
    try_dotnet_root "\${DOTNET_ROOT:-}" && return 0

    if command -v dotnet >/dev/null 2>&1; then
        resolve_dotnet_root_from_executable "\$(command -v dotnet)" && return 0
    fi

    try_dotnet_root "\$HOME/.dotnet" && return 0
    try_dotnet_root "/opt/homebrew/opt/dotnet/libexec" && return 0
    try_dotnet_root "/usr/local/opt/dotnet/libexec" && return 0
    try_dotnet_root "/usr/local/share/dotnet" && return 0
    try_dotnet_root "/usr/share/dotnet" && return 0
    return 1
}

SOURCE="\${BASH_SOURCE[0]}"
SELF="\$(resolve_link "\$SOURCE")"
ROOT="\$(cd -P "\$(dirname "\$SELF")/.." && pwd)"
APP_DLL="\$ROOT/$app_relative_path"

if [[ ! -f "\$APP_DLL" ]]; then
    echo "Error: N# installation is incomplete; missing $display_name payload: \$APP_DLL" >&2
    exit 127
fi

if ! DOTNET_ROOT_RESOLVED="\$(resolve_dotnet_root)"; then
    cat >&2 <<'DOTNETERR'
Error: N# requires .NET 10, but no usable dotnet runtime was found.

Install .NET first, then retry:
  macOS:   brew install dotnet
  Linux:   use your distro package manager or https://dotnet.microsoft.com/download
  Windows: winget install Microsoft.DotNet.SDK.10
DOTNETERR
    exit 127
fi

export DOTNET_ROOT="\$DOTNET_ROOT_RESOLVED"
case "\$(uname -m)" in
    arm64|aarch64) export DOTNET_ROOT_ARM64="\${DOTNET_ROOT_ARM64:-\$DOTNET_ROOT}" ;;
    x86_64|amd64) export DOTNET_ROOT_X64="\${DOTNET_ROOT_X64:-\$DOTNET_ROOT}" ;;
    i386|i686) export DOTNET_ROOT_X86="\${DOTNET_ROOT_X86:-\$DOTNET_ROOT}" ;;
esac

exec "\$DOTNET_ROOT/dotnet" "\$APP_DLL" "\$@"
EOF
    chmod +x "$output"
}

nsharp_write_powershell_launcher() {
    local output="$1"
    local display_name="$2"
    local app_relative_path="$3"

    mkdir -p "$(dirname "$output")"
    cat > "$output" <<EOF
\$ErrorActionPreference = "Stop"

function Test-DotnetRoot([string]\$Candidate) {
    if ([string]::IsNullOrWhiteSpace(\$Candidate)) { return \$false }
    \$dotnet = Join-Path \$Candidate "dotnet.exe"
    if (-not (Test-Path \$dotnet)) { return \$false }
    \$runtimeRoot = Join-Path \$Candidate "shared/Microsoft.NETCore.App"
    if (-not (Test-Path \$runtimeRoot)) { return \$false }
    return \$null -ne (Get-ChildItem \$runtimeRoot -Directory -Filter "10.*" -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Resolve-DotnetRootFromCommand() {
    \$command = Get-Command dotnet -ErrorAction SilentlyContinue
    if (\$null -eq \$command) { return \$null }
    \$dotnet = [System.IO.Path]::GetFullPath(\$command.Source)
    \$bin = Split-Path -Parent \$dotnet
    \$parent = Split-Path -Parent \$bin
    foreach (\$candidate in @(\$bin, \$parent)) {
        if (Test-DotnetRoot \$candidate) { return \$candidate }
    }
    return \$null
}

function Join-OptionalPath([string]\$Root, [string]\$Child) {
    if ([string]::IsNullOrWhiteSpace(\$Root)) { return \$null }
    return Join-Path \$Root \$Child
}

function Resolve-DotnetRoot() {
    \$archRoot = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
        "Arm64" { \$env:DOTNET_ROOT_ARM64 }
        "X64" { \$env:DOTNET_ROOT_X64 }
        "X86" { \$env:DOTNET_ROOT_X86 }
        default { \$null }
    }

    foreach (\$candidate in @(
        \$archRoot,
        \$env:DOTNET_ROOT,
        (Resolve-DotnetRootFromCommand),
        (Join-OptionalPath \$HOME ".dotnet"),
        (Join-OptionalPath \$env:ProgramFiles "dotnet"),
        (Join-OptionalPath \${env:ProgramFiles(x86)} "dotnet")
    )) {
        if (Test-DotnetRoot \$candidate) { return \$candidate }
    }

    return \$null
}

\$root = Split-Path -Parent \$PSScriptRoot
\$app = Join-Path \$root "$app_relative_path"
if (-not (Test-Path \$app)) {
    Write-Error "N# installation is incomplete; missing $display_name payload: \$app"
    exit 127
}

\$dotnetRoot = Resolve-DotnetRoot
if ([string]::IsNullOrWhiteSpace(\$dotnetRoot)) {
    Write-Error "N# requires .NET 10, but no usable dotnet runtime was found. Install .NET with winget install Microsoft.DotNet.SDK.10 and retry."
    exit 127
}

\$env:DOTNET_ROOT = \$dotnetRoot
switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
    "Arm64" { if ([string]::IsNullOrWhiteSpace(\$env:DOTNET_ROOT_ARM64)) { \$env:DOTNET_ROOT_ARM64 = \$dotnetRoot } }
    "X64" { if ([string]::IsNullOrWhiteSpace(\$env:DOTNET_ROOT_X64)) { \$env:DOTNET_ROOT_X64 = \$dotnetRoot } }
    "X86" { if ([string]::IsNullOrWhiteSpace(\$env:DOTNET_ROOT_X86)) { \$env:DOTNET_ROOT_X86 = \$dotnetRoot } }
}

& (Join-Path \$dotnetRoot "dotnet.exe") \$app @args
exit \$LASTEXITCODE
EOF
}

nsharp_write_cmd_launcher() {
    local output="$1"
    local command_name="$2"

    mkdir -p "$(dirname "$output")"
    cat > "$output" <<EOF
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$command_name.ps1" %*
exit /b %ERRORLEVEL%
EOF
}

nsharp_write_launchers() {
    local bin_dir="$1"
    nsharp_write_unix_launcher "$bin_dir/nlc" "nlc" "lib/nlc/Cli.dll"
    nsharp_write_unix_launcher "$bin_dir/nsharp-lsp" "nsharp-lsp" "lib/nsharp-lsp/LanguageServer.dll"
    nsharp_write_powershell_launcher "$bin_dir/nlc.ps1" "nlc" "lib/nlc/Cli.dll"
    nsharp_write_powershell_launcher "$bin_dir/nsharp-lsp.ps1" "nsharp-lsp" "lib/nsharp-lsp/LanguageServer.dll"
    nsharp_write_cmd_launcher "$bin_dir/nlc.cmd" "nlc"
    nsharp_write_cmd_launcher "$bin_dir/nsharp-lsp.cmd" "nsharp-lsp"
}

# The RID this machine's .NET SDK builds for (`osx-arm64`, `linux-x64`, ...).
nsharp_host_rid() {
    dotnet --info 2>/dev/null | awk -F': *' '/^ *RID:/ { gsub(/ /, "", $2); print $2; exit }'
}

# NativeAOT compiles for the OS and architecture it runs on; this toolchain assumes no cross
# linker, so only a host-RID toolset gets the native front door.
nsharp_can_build_native_front_door() {
    [[ "$1" == "$(nsharp_host_rid)" ]]
}

# A source-built .NET SDK (Homebrew, distro packages) bundles its own NativeAOT packs, whose
# native runtime links the distro's OpenSSL (`ld: library 'ssl' not found` on macOS) and so
# cannot produce a relocatable executable. Resolving the packs from NuGet instead gives the
# official ones, which link only system libraries. An official SDK ships no ILCompiler pack and
# needs nothing.
nsharp_native_front_door_pack_args() {
    local rid="$1"
    local dotnet_root=""
    if command -v dotnet >/dev/null 2>&1; then
        dotnet_root="$(nsharp_resolve_dotnet_root "$(command -v dotnet)")"
    fi
    if [[ -n "$dotnet_root" && -d "$dotnet_root/packs/runtime.$rid.Microsoft.DotNet.ILCompiler" ]]; then
        local temp_root="${TMPDIR:-/tmp}"
        local empty_pack_root="${temp_root%/}/nsharp-official-pack-root"
        mkdir -p "$empty_pack_root"
        printf '%s\n' "-p:NetCoreTargetingPackRoot=$empty_pack_root" "-p:AllowMissingPrunePackageData=true"
    fi
}

# `bin/nlc` becomes the NativeAOT front door (src/NSharpLang.Compiler.Driver/FrontDoor.nl): it
# answers --version/help itself and execs `dotnet lib/nlc/Cli.dll` for everything else, so the
# toolset needs no launcher script for nlc. Any trim/AOT warning fails the publish: the front
# door is warning-free by construction and must stay that way.
nsharp_publish_native_front_door() {
    local rid="$1"
    local bin_dir="$2"
    local stage log executable target
    local pack_args=()
    local pack_arg
    while IFS= read -r pack_arg; do
        [[ -n "$pack_arg" ]] && pack_args+=("$pack_arg")
    done < <(nsharp_native_front_door_pack_args "$rid")

    local temp_root="${TMPDIR:-/tmp}"
    stage="$(mktemp -d "${temp_root%/}/nsharp-front-door.XXXXXX")"
    log="$stage.log"
    if ! nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet publish src/NSharpLang.Cli/Cli.csproj -c Release -r "$rid" -o "$stage" -p:PublishAot=true ${pack_args[@]+"${pack_args[@]}"} -v q >"$log" 2>&1; then
        cat "$log" >&2
        echo "Error: NativeAOT publish of the nlc front door failed for $rid." >&2
        rm -rf "$stage" "$log"
        return 1
    fi
    if grep -E 'warning IL[0-9]+' "$log" >&2; then
        echo "Error: the nlc front door must publish without trim/AOT warnings." >&2
        rm -rf "$stage" "$log"
        return 1
    fi

    executable="Cli"
    target="nlc"
    if [[ "$rid" == win-* ]]; then
        executable="Cli.exe"
        target="nlc.exe"
    fi
    rm -f "$bin_dir/nlc"
    cp "$stage/$executable" "$bin_dir/$target"
    chmod +x "$bin_dir/$target"
    rm -rf "$stage" "$log"
}

# Without a RID: the portable, framework-dependent IL toolset that runs on every platform (the
# release archive and the Docker integration rows use it). With a RID: the compiler host and the
# language server are ReadyToRun-compiled for that RID, and on a host of that RID `nlc` is the
# NativeAOT front door; elsewhere it keeps the launcher script.
nsharp_publish_toolset() {
    local output_dir="$1"
    local package_source_dir="$2"
    local rid="${3:-}"
    local rid_args=()
    local front_door="script"

    if [[ -n "$rid" ]]; then
        rid_args=(-r "$rid" -p:PublishReadyToRun=true)
    fi

    rm -rf "$output_dir"
    mkdir -p "$output_dir/lib/nlc" "$output_dir/lib/nsharp-lsp" "$output_dir/bin" "$output_dir/packages"

    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet publish src/NSharpLang.Cli/Cli.csproj -c Release -o "$output_dir/lib/nlc" --self-contained false -p:UseAppHost=false ${rid_args[@]+"${rid_args[@]}"} -v q
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet publish src/NSharpLang.LanguageServer/LanguageServer.csproj -c Release -o "$output_dir/lib/nsharp-lsp" --self-contained false -p:UseAppHost=false ${rid_args[@]+"${rid_args[@]}"} -v q

    if compgen -G "$package_source_dir/NSharpLang.*.nupkg" >/dev/null; then
        cp -f "$package_source_dir"/NSharpLang.*.nupkg "$output_dir/packages/"
    fi

    nsharp_write_launchers "$output_dir/bin"
    if [[ -n "$rid" ]]; then
        if nsharp_can_build_native_front_door "$rid"; then
            nsharp_log "Publishing the NativeAOT nlc front door for $rid"
            nsharp_publish_native_front_door "$rid" "$output_dir/bin"
            front_door="native"
        else
            nsharp_log "The NativeAOT nlc front door needs a $rid build host; this toolset keeps the launcher script"
        fi
    fi

    {
        echo "nsharp-toolset"
        echo "repo=$NSHARP_REPO_ROOT"
        echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "rid=${rid:-portable}"
        echo "nlc=$front_door"
    } > "$output_dir/VERSION"
}

nsharp_install_toolset() {
    local source_dir="$1"
    local install_dir="$2"
    nsharp_require_safe_install_dir "$install_dir"

    if [[ ! -d "$source_dir/bin" || ! -d "$source_dir/lib" ]]; then
        echo "Error: $source_dir is not an N# toolset directory." >&2
        exit 1
    fi

    mkdir -p "$install_dir"
    rm -rf "$install_dir/bin" "$install_dir/lib" "$install_dir/packages"
    cp -R "$source_dir/bin" "$install_dir/bin"
    cp -R "$source_dir/lib" "$install_dir/lib"
    if [[ -d "$source_dir/packages" ]]; then
        cp -R "$source_dir/packages" "$install_dir/packages"
    else
        mkdir -p "$install_dir/packages"
    fi
    if [[ -f "$source_dir/VERSION" ]]; then
        cp -f "$source_dir/VERSION" "$install_dir/VERSION"
    fi
}

nsharp_find_template_package() {
    local packages_dir="$1"
    find "$packages_dir" -maxdepth 1 -name 'NSharpLang.Templates.*.nupkg' -type f 2>/dev/null | sort | tail -n 1
}

nsharp_install_templates_from_packages() {
    local packages_dir="$1"
    local template_package
    template_package="$(nsharp_find_template_package "$packages_dir")"
    if [[ -z "$template_package" ]]; then
        echo "Error: no NSharpLang.Templates package found in $packages_dir" >&2
        exit 1
    fi

    dotnet new uninstall NSharpLang.Templates >/dev/null 2>&1 || true
    nsharp_run dotnet new install "$template_package" --force
}

nsharp_write_shared_nuget_config() {
    local packages_dir="$1"
    local config_file="$2"

    mkdir -p "$(dirname "$config_file")"
    cat > "$config_file" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="nsharp-local" value="$packages_dir" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    <packageSource key="nsharp-local">
      <package pattern="NSharpLang.*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
EOF
}

nsharp_write_env_file() {
    local install_dir="$1"
    local env_file="$2"
    local dotnet_root=""

    if command -v dotnet >/dev/null 2>&1; then
        dotnet_root="$(nsharp_resolve_dotnet_root "$(command -v dotnet)")"
    fi

    mkdir -p "$(dirname "$env_file")"
    cat > "$env_file" <<EOF
# Added by N# setup.
export NSHARP_INSTALL_DIR="$install_dir"
export PATH="\$NSHARP_INSTALL_DIR/bin:\$PATH"
EOF
    if [[ -n "$dotnet_root" ]]; then
        {
            echo "export DOTNET_ROOT=\"${dotnet_root}\""
            case "$(uname -m)" in
                arm64|aarch64) echo "export DOTNET_ROOT_ARM64=\"\${DOTNET_ROOT_ARM64:-\$DOTNET_ROOT}\"" ;;
                x86_64|amd64) echo "export DOTNET_ROOT_X64=\"\${DOTNET_ROOT_X64:-\$DOTNET_ROOT}\"" ;;
                i386|i686) echo "export DOTNET_ROOT_X86=\"\${DOTNET_ROOT_X86:-\$DOTNET_ROOT}\"" ;;
            esac
        } >> "$env_file"
    fi
}
