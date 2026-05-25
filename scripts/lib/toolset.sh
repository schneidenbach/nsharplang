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

nsharp_publish_toolset() {
    local output_dir="$1"
    local package_source_dir="$2"

    rm -rf "$output_dir"
    mkdir -p "$output_dir/lib/nlc" "$output_dir/lib/nsharp-lsp" "$output_dir/bin" "$output_dir/packages"

    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet publish src/NSharpLang.Cli/Cli.csproj -c Release -o "$output_dir/lib/nlc" --self-contained false -p:UseAppHost=false -v q
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet publish src/NSharpLang.LanguageServer/LanguageServer.csproj -c Release -o "$output_dir/lib/nsharp-lsp" --self-contained false -p:UseAppHost=false -v q

    if compgen -G "$package_source_dir/NSharpLang.*.nupkg" >/dev/null; then
        cp -f "$package_source_dir"/NSharpLang.*.nupkg "$output_dir/packages/"
    fi

    nsharp_write_launchers "$output_dir/bin"
    {
        echo "nsharp-toolset"
        echo "repo=$NSHARP_REPO_ROOT"
        echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
export PATH="$install_dir/bin:\$PATH"
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
