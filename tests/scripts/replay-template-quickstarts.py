#!/usr/bin/env python3
"""Replay the templates/README.md quickstart command blocks from scratch.

The docs own the commands. This script extracts fenced bash blocks marked with
`<!-- quickstart:<name> -->`, rewrites project output paths into a temporary
workspace, installs the current repo-local template/CLI packages, and executes
the documented create/build/run/test path for each template.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


QUICKSTART_RE = re.compile(
    r"<!--\s*quickstart:(?P<name>[a-z0-9-]+)\s*-->\s*```bash\s*(?P<commands>.*?)\s*```",
    re.DOTALL,
)


def run(command: str, cwd: Path, env: dict[str, str]) -> None:
    print(f"$ {command}", flush=True)
    subprocess.run(command, cwd=cwd, env=env, shell=True, check=True)


def quickstarts(markdown: str) -> list[tuple[str, list[str]]]:
    result: list[tuple[str, list[str]]] = []
    for match in QUICKSTART_RE.finditer(markdown):
        commands = [
            line.strip()
            for line in match.group("commands").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        result.append((match.group("name"), commands))
    return result


def rewrite_commands(commands: list[str], project_dir: Path) -> list[str]:
    project_name = project_dir.name
    rewritten: list[str] = []
    for command in commands:
        command = re.sub(r"\s-o\s+\S+", f" -o {project_dir}", command)
        command = re.sub(r"^cd\s+\S+$", f"cd {project_dir}", command)
        for placeholder in ("MyApp", "MyLib", "MyTests", "MyApi"):
            command = command.replace(f" {placeholder}", f" {project_name}")
        rewritten.append(command)
    return rewritten


def replay_command(command: str) -> str:
    if not command.startswith("ASPNETCORE_URLS=") or not command.endswith(" nlc run"):
        return command

    escaped = command.replace("'", "'\\''")
    return (
        "bash -lc 'set -e; "
        f"{escaped} > /tmp/nsharp-webapi-quickstart.log 2>&1 & pid=$!; "
        "for i in $(seq 1 40); do "
        "if curl -fsS http://127.0.0.1:5050/api/weather >/tmp/nsharp-webapi-quickstart-response.txt 2>/dev/null; then "
        "kill $pid; wait $pid 2>/dev/null || true; cat /tmp/nsharp-webapi-quickstart-response.txt; exit 0; "
        "fi; "
        "if ! kill -0 $pid 2>/dev/null; then cat /tmp/nsharp-webapi-quickstart.log; exit 1; fi; "
        "sleep 0.5; "
        "done; "
        "cat /tmp/nsharp-webapi-quickstart.log; kill $pid 2>/dev/null || true; exit 1'"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--keep-temp", action="store_true")
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    docs_path = repo_root / "templates" / "README.md"
    blocks = quickstarts(docs_path.read_text())
    names = sorted(name for name, _ in blocks)
    expected = ["console", "library", "test", "webapi"]
    if names != expected:
        raise SystemExit(f"Expected quickstarts {expected}, found {names}")

    temp_root = Path(tempfile.mkdtemp(prefix="nsharp-template-quickstarts-"))
    packages_dir = temp_root / "packages"
    install_dir = temp_root / ".nsharp"
    toolset_dir = temp_root / "toolset"
    dotnet_home = temp_root / "dotnet-home"
    packages_dir.mkdir()
    dotnet_home.mkdir()

    env = os.environ.copy()
    env["HOME"] = str(temp_root)
    env["DOTNET_CLI_HOME"] = str(dotnet_home)
    env["PATH"] = f"{install_dir / 'bin'}{os.pathsep}{env['PATH']}"
    if "DOTNET_ROOT" not in env:
        dotnet_root = subprocess.check_output(
            ["dotnet", "--list-runtimes"], text=True
        ).split("[")[-1].split("]", 1)[0]
        env["DOTNET_ROOT"] = str(Path(dotnet_root).parents[1])
        env.setdefault("DOTNET_ROOT_ARM64", env["DOTNET_ROOT"])

    try:
        run(
            f"dotnet build {repo_root / 'src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj'} "
            "-c Release --disable-build-servers -v q",
            repo_root,
            env,
        )
        for project in (
            "src/NSharpLang.Compiler/Compiler.csproj",
            "src/NSharpLang.Sdk/NSharpLang.Sdk.csproj",
            "templates/NSharpLang.Templates.csproj",
        ):
            run(f"dotnet pack {repo_root / project} -c Release -o {packages_dir} --disable-build-servers -v q", repo_root, env)

        run(
            f"{repo_root / 'scripts/publish-toolset.sh'} --output {toolset_dir} "
            f"--packages {packages_dir} --skip-packages --skip-archive",
            repo_root,
            env,
        )
        run(
            f"{repo_root / 'scripts/install.sh'} --source {toolset_dir} "
            f"--install-dir {install_dir} --skip-vscode --no-path-update",
            repo_root,
            env,
        )

        # Isolate generated-project restores from any globally cached NSharpLang packages,
        # but only after repo-local pack has used the developer's normal restore cache.
        env["NUGET_PACKAGES"] = str(temp_root / "nuget-packages")

        nuget_config = temp_root / "NuGet.config"
        nuget_config.write_text(
            "<configuration>\n"
            "  <packageSources>\n"
            f"    <add key=\"local-nsharp\" value=\"{packages_dir}\" />\n"
            "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n"
            "  </packageSources>\n"
            "</configuration>\n"
        )

        for name, commands in blocks:
            project_dir = temp_root / f"docs-{name}"
            cwd = temp_root
            rewritten = rewrite_commands(commands, project_dir)
            if not 1 <= len(rewritten) <= 4:
                raise SystemExit(f"quickstart:{name} has {len(rewritten)} commands; expected 1-4")
            print(f"\n== Replaying quickstart:{name} ==", flush=True)
            for command in rewritten:
                run(replay_command(command), cwd, env)
                if command.startswith("cd "):
                    destination = Path(command[3:].strip())
                    cwd = destination if destination.is_absolute() else cwd / destination

        print(f"\nReplayed {len(blocks)} template quickstarts successfully.", flush=True)
        return 0
    finally:
        if args.keep_temp:
            print(f"Kept temp workspace: {temp_root}", flush=True)
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
