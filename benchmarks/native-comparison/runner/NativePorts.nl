namespace NSharpLang.NativeComparisonRunner

import System
import System.Collections.Generic
import System.IO


// THE RUST AND C PORTS, COMPILED FROM SOURCE ON EVERY RUN.
//
// The flags are the ones this directory's README has always documented, and they are not tuned here:
//
//     rustc -C opt-level=3 -o <tmp>/<workload>_rs <repo>/benchmarks/native-comparison/<workload>/main.rs
//     clang -O3            -o <tmp>/<workload>_c  <repo>/benchmarks/native-comparison/<workload>/main.c
//
// Compiling rather than caching binaries is what makes a comparison honest: the native numbers in a
// report were produced by the toolchain whose `--version` that same report records, on the machine
// it names, in the same session as the N# numbers beside them.
//
// ALL TWELVE ARE BUILT BEFORE ANY OF THEM RUNS. A missing `clang` discovered after four workloads
// have already been measured wastes the measurements taken so far and, worse, tempts a partial
// table; discovering it in the first two seconds costs nothing.
//
// `rustc` IS RESOLVED BY PATH, NOT ASSUMED ON `PATH`. A rustup install puts it at
// `$HOME/.cargo/bin/rustc`, which a non-login shell — and therefore a child of the product gate —
// does not necessarily have on `PATH`; the README's old shell loop had to `source "$HOME/.cargo/env"`
// first for exactly this reason. The absolute path is preferred and bare `rustc` is the fallback, so
// a system-packaged toolchain still works.
class NativePort {
    Workload: string
    RustBinary: string
    CBinary: string

    constructor(workload: string, rustBinary: string, cBinary: string) {
        Workload = workload
        RustBinary = rustBinary
        CBinary = cBinary
    }
}

// The twelve binaries, or the first failure that stopped the set. `Error` is empty on success.
class NativePortSet {
    Ports: List<NativePort>
    RustCompiler: string
    Error: string

    constructor(ports: List<NativePort>, rustCompiler: string, error: string) {
        Ports = ports
        RustCompiler = rustCompiler
        Error = error
    }
}

func RustOptimizationFlags(): string {
    return "-C opt-level=3"
}

func ClangOptimizationFlags(): string {
    return "-O3"
}

func ClangCompiler(): string {
    return "clang"
}

func ResolveRustCompiler(): string {
    home := Environment.GetEnvironmentVariable("HOME") ?? ""
    if home != "" {
        cargoBin := Path.Combine(Path.Combine(home, ".cargo"), "bin")
        cargoRustc := Path.Combine(cargoBin, "rustc")
        if File.Exists(cargoRustc) {
            return cargoRustc
        }
    }
    return "rustc"
}

func WorkloadSourceFile(repoRoot: string, workload: string, fileName: string): string {
    comparison := Path.Combine(Path.Combine(repoRoot, "benchmarks"), "native-comparison")
    return Path.Combine(Path.Combine(comparison, workload), fileName)
}

func RustBinaryPath(temporaryDirectory: string, workload: string): string {
    return Path.Combine(temporaryDirectory, workload + "_rs")
}

func CBinaryPath(temporaryDirectory: string, workload: string): string {
    return Path.Combine(temporaryDirectory, workload + "_c")
}

func RustCompileArguments(repoRoot: string, temporaryDirectory: string, workload: string): string {
    binary := QuoteArgument(RustBinaryPath(temporaryDirectory, workload))
    source := QuoteArgument(WorkloadSourceFile(repoRoot, workload, "main.rs"))
    return RustOptimizationFlags() + " -o " + binary + " " + source
}

func ClangCompileArguments(repoRoot: string, temporaryDirectory: string, workload: string): string {
    binary := QuoteArgument(CBinaryPath(temporaryDirectory, workload))
    source := QuoteArgument(WorkloadSourceFile(repoRoot, workload, "main.c"))
    return ClangOptimizationFlags() + " -o " + binary + " " + source
}

// Build every port. The first failure stops the set and is returned as an `Error`; the caller prints
// it and aborts, because a native column measured from a stale binary is worse than no column.
func CompileNativePorts(repoRoot: string, temporaryDirectory: string): NativePortSet {
    rustCompiler := ResolveRustCompiler()
    ports := new List<NativePort>()
    workloads := WorkloadKeys()

    for i := 0; i < workloads.Length; i++ {
        workload := workloads[i]

        missingSource := MissingPortSource(repoRoot, workload)
        if missingSource != "" {
            return new NativePortSet(ports, rustCompiler, missingSource)
        }

        rustArguments := RustCompileArguments(repoRoot, temporaryDirectory, workload)
        rustBuild := RunProcess(rustCompiler, rustArguments, temporaryDirectory)
        if !rustBuild.Succeeded() {
            failure := CompilerFailureMessage(rustCompiler, rustArguments, rustBuild)
            return new NativePortSet(ports, rustCompiler, failure)
        }

        clangArguments := ClangCompileArguments(repoRoot, temporaryDirectory, workload)
        clangBuild := RunProcess(ClangCompiler(), clangArguments, temporaryDirectory)
        if !clangBuild.Succeeded() {
            failure := CompilerFailureMessage(ClangCompiler(), clangArguments, clangBuild)
            return new NativePortSet(ports, rustCompiler, failure)
        }

        rustBinary := RustBinaryPath(temporaryDirectory, workload)
        cBinary := CBinaryPath(temporaryDirectory, workload)
        ports.Add(new NativePort(workload, rustBinary, cBinary))
    }

    return new NativePortSet(ports, rustCompiler, "")
}

func MissingPortSource(repoRoot: string, workload: string): string {
    rustSource := WorkloadSourceFile(repoRoot, workload, "main.rs")
    if !File.Exists(rustSource) {
        return "Rust port not found: " + rustSource
    }
    cSource := WorkloadSourceFile(repoRoot, workload, "main.c")
    if !File.Exists(cSource) {
        return "C port not found: " + cSource
    }
    return ""
}

func CompilerFailureMessage(compiler: string, arguments: string, run: ProcessRun): string {
    message := compiler + " " + arguments
    message = message + " failed: " + run.FailureReason()
    if run.Stderr.Trim() != "" {
        message = message + "\n" + run.Stderr.TrimEnd()
    }
    return message
}

func IndexOfNativePort(ports: List<NativePort>, workload: string): int {
    for i := 0; i < ports.Count; i++ {
        port := ports[i]
        if port.Workload == workload {
            return i
        }
    }
    return -1
}
