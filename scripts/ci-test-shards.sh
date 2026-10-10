#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

exec python3 - "$@" <<'PY'
"""Discover, duration-balance, and execute CI compiler/native test shards."""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path.cwd()
DURATION_FILE = ROOT / "scripts" / "ci-test-durations.json"
PERFORMANCE_PROJECT = "tests/native/compile-time-bench"
SHARD_COUNT = 10
DEFAULT_SECONDS = 10.0
RELEASE_CLI_DLL = "src/NSharpLang.Cli/bin/Release/net10.0/Cli.dll"
DEBUG_CLI_DLL = "src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
PERFORMANCE_SLICES = (
    "core",
    "small-check", "small-build", "small-test",
    "medium-check", "medium-build", "medium-test",
    "medium-lsp", "large-lsp",
)


def has_tests(directory):
    return any(
        file.is_file()
        for file in directory.rglob("*.tests.nl")
        if "bin" not in file.parts and "obj" not in file.parts
    )


def discover(root=ROOT):
    projects = []
    estate_patterns = ("src/NSharpLang/*.csproj", "src/NSharpLang.*/*.csproj")
    estate_files = set()
    for pattern in estate_patterns:
        estate_files.update(root.glob(pattern))
    for project in sorted(estate_files, key=lambda path: path.as_posix()):
        if has_tests(project.parent):
            projects.append("estate:" + project.relative_to(root).as_posix())

    native_root = root / "tests" / "native"
    native_configs = sorted(native_root.glob("*/project.yml"), key=lambda path: path.as_posix())
    for config in native_configs:
        directory = config.parent
        if not has_tests(directory):
            raise ValueError("Native project has no *.tests.nl files: " + directory.relative_to(root).as_posix())
        projects.append(directory.relative_to(root).as_posix())

    if not projects:
        raise ValueError("No compiler-service estate or native test projects were discovered.")
    if PERFORMANCE_PROJECT not in projects:
        raise ValueError("The dedicated compiler performance project was not discovered: " + PERFORMANCE_PROJECT)
    return sorted(projects)


def load_durations(path=DURATION_FILE):
    with path.open(encoding="utf-8") as stream:
        baseline = json.load(stream)
    if baseline.get("schemaVersion") != 1 or not isinstance(baseline.get("seconds"), dict):
        raise ValueError("Unsupported CI test duration baseline: " + str(path))
    return baseline


def project_seconds(project, durations):
    value = durations["seconds"].get(project, durations.get("unseenProjectSeconds", DEFAULT_SECONDS))
    if not isinstance(value, (int, float)) or value <= 0:
        raise ValueError("Invalid duration estimate for " + project)
    return float(value)


def assign(projects, durations, shard_count=SHARD_COUNT):
    if shard_count < 1:
        raise ValueError("Shard count must be positive.")
    shards = [{"id": "{:02d}".format(index + 1), "projects": [], "seconds": 0.0} for index in range(shard_count)]
    for project in sorted(projects, key=lambda item: (-project_seconds(item, durations), item)):
        shard = min(shards, key=lambda item: (item["seconds"], item["id"]))
        shard["projects"].append(project)
        shard["seconds"] += project_seconds(project, durations)
    for shard in shards:
        shard["projects"].sort()
        shard["seconds"] = round(shard["seconds"], 3)
    return shards


def plan(root=ROOT, duration_path=DURATION_FILE, shard_count=SHARD_COUNT):
    projects = discover(root)
    durations = load_durations(duration_path)
    shards = assign(projects, durations, shard_count)
    return {
        "schemaVersion": 1,
        "shardCount": shard_count,
        "durationSource": durations.get("source", "checked-in baseline"),
        "shards": shards,
        "projectCount": len(projects),
    }


def verify_contract(root=ROOT, duration_path=DURATION_FILE):
    projects = discover(root)
    durations = load_durations(duration_path)
    first = assign(projects, durations)
    second = assign(projects, durations)
    if first != second:
        raise AssertionError("Shard assignment changed between identical discovery runs.")
    flattened = [project for shard in first for project in shard["projects"]]
    if len(flattened) != len(set(flattened)):
        raise AssertionError("A discovered test project is assigned more than once.")
    if set(flattened) != set(projects):
        missing = sorted(set(projects) - set(flattened))
        unexpected = sorted(set(flattened) - set(projects))
        raise AssertionError("Shard union differs from discovery; missing={} unexpected={}".format(missing, unexpected))

    # A newly discovered project with no baseline entry must still be assigned. This makes the
    # discovery contract explicit and exercises the documented fallback estimate.
    synthetic = "tests/native/__contract_new_project__"
    extended = assign(projects + [synthetic], durations)
    extended_union = [project for shard in extended for project in shard["projects"]]
    if extended_union.count(synthetic) != 1 or set(extended_union) != set(projects + [synthetic]):
        raise AssertionError("A newly discovered project was not assigned exactly once.")
    return len(projects), first


def write_plan_output(plan_value, output_path=None, github_output=None):
    encoded = json.dumps(plan_value, indent=2, sort_keys=True) + "\n"
    if output_path:
        path = Path(output_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded, encoding="utf-8")
    if github_output:
        matrix = {"include": [{"shard": shard["id"]} for shard in plan_value["shards"]]}
        with open(github_output, "a", encoding="utf-8") as stream:
            stream.write("matrix=" + json.dumps(matrix, separators=(",", ":")) + "\n")


def refresh_durations(directory, source):
    directory = Path(directory)
    measured = {}
    for path in sorted(directory.rglob("*.json")):
        with path.open(encoding="utf-8") as stream:
            payload = json.load(stream)
        if not isinstance(payload, dict) or payload.get("schemaVersion") != 1 or not isinstance(payload.get("projects"), list):
            raise ValueError("Not a CI project-duration artifact: " + str(path))
        for record in payload["projects"]:
            project = record.get("project") if isinstance(record, dict) else None
            seconds = record.get("seconds") if isinstance(record, dict) else None
            if not isinstance(project, str) or not isinstance(seconds, (int, float)) or seconds <= 0:
                raise ValueError("Invalid project duration in " + str(path))
            if project in measured:
                raise ValueError("Project duration was reported more than once: " + project)
            measured[project] = round(float(seconds), 3)

    discovered = set(discover())
    if set(measured) != discovered:
        missing = sorted(discovered - set(measured))
        unexpected = sorted(set(measured) - discovered)
        raise ValueError("Duration artifacts do not cover the discovered project set; missing={} unexpected={}".format(missing, unexpected))
    baseline = load_durations()
    baseline["source"] = "GitHub Actions run {}; refreshed from per-project duration artifacts".format(source)
    baseline["seconds"] = dict(sorted(measured.items()))
    DURATION_FILE.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("Refreshed {} project durations from {}.".format(len(measured), source))


def print_plan(plan_value):
    print("CI test shard plan: {} discovered projects; {} duration-balanced shards; source {}".format(
        plan_value["projectCount"], plan_value["shardCount"], plan_value["durationSource"]
    ))
    for shard in plan_value["shards"]:
        print("shard {}: {:7.2f}s ({:5.2f} min), {} projects".format(
            shard["id"], shard["seconds"], shard["seconds"] / 60.0, len(shard["projects"])
        ))


def workflow_error(message):
    safe = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print("::error::" + safe)


def compact_text(value):
    return re.sub(r"\s+", " ", str(value)).strip()


def parse_native_result(path, exit_code, project):
    try:
        with open(path, encoding="utf-8") as stream:
            payload = json.load(stream)
    except Exception as error:
        raise RuntimeError("Native test build/run failed before a valid result for {}: {}".format(project, error))

    summary = payload.get("summary") if isinstance(payload, dict) else None
    results = payload.get("results") if isinstance(payload, dict) else None
    if (not isinstance(payload, dict) or payload.get("schemaVersion") != 1 or
            payload.get("command") != "test" or not isinstance(summary, dict) or not isinstance(results, list)):
        raise RuntimeError("Native test build/run failed before a valid result for {}.".format(project))

    total, passed, failed, skipped = (summary.get(key) for key in ("total", "passed", "failed", "skipped"))
    outcomes = {"passed": 0, "failed": 0, "skipped": 0}
    for result in results:
        if not isinstance(result, dict) or result.get("outcome") not in outcomes:
            raise RuntimeError("Native test output contains an invalid result for {}.".format(project))
        outcomes[result["outcome"]] += 1
    values = (total, passed, failed, skipped)
    if (any(type(value) is not int for value in values) or total <= 0 or len(results) != total or
            sum(outcomes.values()) != total or
            (passed, failed, skipped) != tuple(outcomes[key] for key in ("passed", "failed", "skipped"))):
        raise RuntimeError("Native test build/run did not produce a complete nonempty result for {}.".format(project))

    names = []
    if payload.get("ok") is False and exit_code != 0 and failed > 0:
        for result in results:
            if result["outcome"] == "failed":
                name = compact_text(result.get("displayName") or result.get("name") or "unnamed test")
                detail = compact_text(result.get("errorMessage") or "")
                names.append((name, detail))
    elif not (payload.get("ok") is True and exit_code == 0 and passed > 0 and failed == 0):
        raise RuntimeError("Native test build/run failed for {} (exit {}); incomplete test-failure result.".format(project, exit_code))
    return {"total": total, "passed": passed, "failed": failed, "skipped": skipped}, names


ESTATE_FAILURE_RE = re.compile(r"^\s*Failed\s+(.+?)(?:\s+\[[^\]]+\])?\s*$", re.MULTILINE)
ESTATE_SUMMARY_RE = re.compile(
    r"(?:Passed|Failed)!\s+-\s+Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)"
)


def estate_result(output, exit_code, project):
    match = ESTATE_SUMMARY_RE.search(output)
    names = [(compact_text(name), "") for name in ESTATE_FAILURE_RE.findall(output)]
    if not match:
        if exit_code != 0:
            raise RuntimeError("Compiler-service estate failed before a complete test result for {}.".format(project))
        raise RuntimeError("Compiler-service estate produced no complete test summary for {}.".format(project))
    failed, passed, skipped, total = (int(value) for value in match.groups())
    if total <= 0 or failed + passed + skipped != total:
        raise RuntimeError("Compiler-service estate produced an invalid test summary for {}.".format(project))
    if exit_code == 0 and failed == 0 and passed > 0:
        return {"total": total, "passed": passed, "failed": failed, "skipped": skipped}, []
    if exit_code != 0 and failed > 0:
        if not names:
            names = [("(see project log)", "")]
        return {"total": total, "passed": passed, "failed": failed, "skipped": skipped}, names
    raise RuntimeError("Compiler-service estate failed for {} (exit {}) without a complete test-failure result.".format(project, exit_code))


def project_command(project, repository_root, performance_slice=None):
    if project.startswith("estate:"):
        relative = project[len("estate:"):]
        return ["dotnet", "test", relative, "-c", "Release", "-p:NSharpExcludeTests=false", "--no-build"], "estate"
    cli_dll = DEBUG_CLI_DLL if project == PERFORMANCE_PROJECT else RELEASE_CLI_DLL
    cli = repository_root / cli_dll
    command = ["dotnet", str(cli), "test", "--project", project, "--no-cache", "--json"]
    if performance_slice:
        test_filter = "CompileTimeGate" if performance_slice == "core" else "AgentLoopGate"
        command.extend(["--filter", test_filter])
    return command, "native"


def append_summary(path, title, records, hard_failure=None):
    if not path:
        return
    lines = ["## " + title, "", "| Project | Result | Duration |", "| --- | --- | ---: |"]
    for record in records:
        tests = record.get("tests", {})
        outcome = record.get("outcome", "not run")
        cell = "{} ({} passed, {} failed, {} skipped)".format(
            outcome, tests.get("passed", 0), tests.get("failed", 0), tests.get("skipped", 0)
        )
        lines.append("| `{}` | {} | {:.2f}s |".format(record["project"], cell, record.get("seconds", 0.0)))
        for failure in record.get("failedTests", []):
            name = failure.get("name", "unnamed test")
            detail = failure.get("detail", "")
            name = compact_text(name).replace("|", "\\|")
            detail = compact_text(detail).replace("|", "\\|")
            lines.append("|  | **FAILED:** {}{} | |".format(name, (" — " + detail) if detail else ""))
    if hard_failure:
        lines.extend(["", "**Shard stopped:** " + hard_failure])
    lines.append("")
    with open(path, "a", encoding="utf-8") as stream:
        stream.write("\n".join(lines))


def run_projects(projects, title, repository_root, artifact_directory, duration_output, summary_path, performance_slice=None):
    artifact_directory = Path(artifact_directory)
    artifact_directory.mkdir(parents=True, exist_ok=True)
    records = []
    test_failures = []
    hard_failure = None
    cli_paths = set()
    for project in projects:
        if not project.startswith("estate:"):
            cli_dll = DEBUG_CLI_DLL if project == PERFORMANCE_PROJECT else RELEASE_CLI_DLL
            cli_paths.add(repository_root / cli_dll)
    missing_cli = sorted(str(path) for path in cli_paths if not path.is_file())
    if missing_cli:
        raise RuntimeError("Downloaded native prerequisite artifact is missing CLI output(s): " + ", ".join(missing_cli))

    for project in projects:
        command, kind = project_command(project, repository_root, performance_slice)
        display = project[len("estate:"):] if kind == "estate" else project
        print("Testing {}: {}".format("compiler-service estate" if kind == "estate" else "native project", display), flush=True)
        started = time.monotonic()
        restore_output = ""
        if kind == "estate":
            restore = subprocess.run(
                ["dotnet", "restore", project[len("estate:"):], "-p:NSharpExcludeTests=false"],
                cwd=str(repository_root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                universal_newlines=True,
            )
            restore_output = restore.stdout
            if restore.returncode != 0:
                elapsed = round(time.monotonic() - started, 3)
                message = "Compiler-service estate restore failed for {} (exit {}).".format(display, restore.returncode)
                record = {"project": project, "seconds": elapsed, "exitCode": restore.returncode,
                          "outcome": "infrastructure failure", "error": message}
                records.append(record)
                hard_failure = message
                workflow_error(message)
                print(restore_output, end="" if restore_output.endswith("\n") else "\n")
                break
        environment = os.environ.copy()
        if project == PERFORMANCE_PROJECT:
            environment["NSHARP_COMPILER_PERF_MODE"] = "timing" if performance_slice else "structural"
            if performance_slice and performance_slice != "core":
                size, scenario_group = performance_slice.split("-", 1)
                environment["NSHARP_COMPILER_PERF_SIZE"] = size
                environment["NSHARP_COMPILER_PERF_SCENARIO_GROUP"] = scenario_group
        process = subprocess.run(command, cwd=str(repository_root), env=environment, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, universal_newlines=True)
        elapsed = round(time.monotonic() - started, 3)
        log_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", project) + ".log"
        log_path = artifact_directory / log_name
        combined_output = restore_output + process.stdout
        log_path.write_text(combined_output, encoding="utf-8")
        record = {"project": project, "seconds": elapsed, "exitCode": process.returncode, "outcome": "infrastructure failure"}
        try:
            if kind == "native":
                result_path = artifact_directory / (log_name + ".json")
                result_path.write_text(process.stdout, encoding="utf-8")
                tests, failed_names = parse_native_result(result_path, process.returncode, project)
            else:
                tests, failed_names = estate_result(combined_output, process.returncode, project)
            record["tests"] = tests
            record["failedTests"] = [{"name": name, "detail": detail} for name, detail in failed_names]
            if failed_names:
                record["outcome"] = "failed"
                test_failures.append(record)
                print("{}: {} — {} test(s), {} passed, {} failed, {} skipped".format(
                    "Native result" if kind == "native" else "Estate result", display,
                    tests["total"], tests["passed"], tests["failed"], tests["skipped"]
                ))
                for name, detail in failed_names:
                    print("  FAILED {}{}".format(name, (": " + detail) if detail else ""))
            else:
                record["outcome"] = "passed"
                print("{}: {} — {} tests (passed {}, failed 0, skipped {})".format(
                    "Native result" if kind == "native" else "Estate result", display,
                    tests["total"], tests["passed"], tests["skipped"]
                ))
        except RuntimeError as error:
            hard_failure = str(error)
            record["error"] = hard_failure
            records.append(record)
            workflow_error(hard_failure)
            print(process.stdout, end="" if process.stdout.endswith("\n") else "\n")
            break
        records.append(record)

    if duration_output:
        output = {
            "schemaVersion": 1,
            "shard": title,
            "projects": records,
        }
        destination = Path(duration_output)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    append_summary(summary_path, title, records, hard_failure)
    if hard_failure:
        return 2
    if test_failures:
        print("::error::Test failures in {}:".format(title))
        for record in test_failures:
            print("  {}: {}".format(record["project"], ", ".join(item["name"] for item in record["failedTests"])))
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan_parser = subparsers.add_parser("plan", help="discover projects and write the matrix and plan")
    plan_parser.add_argument("--output")
    plan_parser.add_argument("--github-output")
    plan_parser.add_argument("--print", action="store_true", dest="show")
    plan_parser.add_argument("--shards", type=int, default=SHARD_COUNT)

    check_parser = subparsers.add_parser("verify-contract", help="check exact, deterministic discovery coverage")

    build_parser = subparsers.add_parser("build-estate", help="compile every discovered compiler-service estate project")

    refresh_parser = subparsers.add_parser("refresh-durations", help="refresh the checked-in balance baseline from downloaded artifacts")
    refresh_parser.add_argument("--from-dir", required=True)
    refresh_parser.add_argument("--source", required=True, help="workflow run id or other audit label")

    run_parser = subparsers.add_parser("run", help="run one assigned shard or one isolated compiler performance slice")
    group = run_parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--shard")
    group.add_argument("--performance-slice", choices=PERFORMANCE_SLICES, dest="performance_slice")
    run_parser.add_argument("--artifacts", default="artifacts/ci-test-shards")
    run_parser.add_argument("--durations")
    run_parser.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"))

    args = parser.parse_args()
    try:
        if args.command == "plan":
            value = plan(shard_count=args.shards)
            write_plan_output(value, args.output, args.github_output)
            if args.show:
                print_plan(value)
            return 0
        if args.command == "verify-contract":
            count, _ = verify_contract()
            print("CI test shard contract passed: {} discovered projects are assigned exactly once across 10 test shards.".format(count))
            return 0
        if args.command == "build-estate":
            projects = [project[len("estate:"):] for project in discover() if project.startswith("estate:")]
            if not projects:
                raise ValueError("No compiler-service estate projects were discovered.")
            for project in projects:
                print("Building compiler-service estate: " + project, flush=True)
                result = subprocess.run(
                    ["dotnet", "build", project, "-c", "Release", "-p:NSharpExcludeTests=false"],
                    cwd=str(ROOT),
                )
                if result.returncode != 0:
                    workflow_error("Compiler-service estate build failed: " + project)
                    return result.returncode
            return 0
        if args.command == "refresh-durations":
            refresh_durations(args.from_dir, args.source)
            return 0
        value = plan()
        if args.performance_slice:
            projects = [PERFORMANCE_PROJECT]
            title = "compiler-performance-" + args.performance_slice
        else:
            matching = [shard for shard in value["shards"] if shard["id"] == args.shard]
            if not matching:
                raise ValueError("Unknown shard id: " + args.shard)
            projects = matching[0]["projects"]
            title = "shard-" + args.shard
        if not projects:
            raise ValueError(title + " has no projects; zero-test shards are invalid.")
        return run_projects(projects, title, ROOT, args.artifacts, args.durations, args.summary,
                            args.performance_slice)
    except (AssertionError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        workflow_error(str(error))
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
PY
