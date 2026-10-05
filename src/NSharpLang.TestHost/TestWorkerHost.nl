namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Text
import System.Threading
import NSharpLang.Cli.Daemon
import NSharpLang.Compiler

// WHERE `nlc test` RUNS THE USER'S TESTS WHEN THE WORKSPACE SERVER RUNS THE COMMAND.
//
// Building the tests is compiler work and happens in the warm server. RUNNING them is the user's
// code, and the user's code may do anything to the process it runs in: overflow its stack, call
// `Environment.Exit`, fail fast, spin forever, set statics, start threads, change the current
// directory. In-process `nlc test` that is the user's own process to lose; in a server that other
// commands share it would be everyone's. So the server never runs a test: it hands the built assembly
// to a TEST WORKER — a separate process of this same CLI, started ahead of time and used for exactly
// one run — and relays what the worker prints.
//
// A worker that dies without a result ends the request with the worker's exit code and nothing more
// (`CliInvocationContext.Terminate`), which is what the same death does to an in-process `nlc test`.
// The server is untouched either way.
//
// The next worker is started as soon as one is taken, so the process start-up and runtime load are
// paid while the server is idle, not while a client waits.
class TestWorkerHost {
    private static gate: object = new object()
    private static standby: Process?

    static func GetWorkerCommand(): string {
        return "__test-worker"
    }

    static func IsWorkerInvocation(args: string[]): bool {
        return args.Length > 0 && args[0] == GetWorkerCommand()
    }

    // ── Server side ─────────────────────────────────────────────────────────────────────────────

    static func RunIsolated(testFramework: string?, outputPath: string, filter: string?, verbose: bool, outputMode: int, timeoutMs: int?): NativeTestRun {
        worker := Acquire()
        resultPath := Path.Combine(Path.GetTempPath(), "nlc-test-run-" + Guid.NewGuid().ToString("N") + ".bin")
        try {
            CliInvocationContext.RegisterCancellation(() => Kill(worker))
            stdoutRelay := StartRelay(worker.StandardOutput.BaseStream, false)
            stderrRelay := StartRelay(worker.StandardError.BaseStream, true)
            WriteRequest(worker.StandardInput.BaseStream, testFramework, outputPath, filter, verbose, outputMode, timeoutMs, resultPath)
            worker.StandardInput.Close()
            worker.WaitForExit()
            stdoutRelay.Join()
            stderrRelay.Join()
            exitCode := worker.ExitCode
            worker.Dispose()
            Replenish()

            if exitCode == 0 && File.Exists(resultPath) {
                run := ReadResults(resultPath)
                if run != null {
                    return run ?? EmptyRun()
                }
            }

            CliInvocationContext.Terminate(exitCode)
            return EmptyRun()
        } finally {
            try {
                if File.Exists(resultPath) {
                    File.Delete(resultPath)
                }
            } catch cleanupFailure: Exception {
                Debug.WriteLine(cleanupFailure.Message)
            }
        }
    }

    // A standby worker if one is alive, else a fresh one.
    static func Acquire(): Process {
        lock TestWorkerHost.gate {
            ready := TestWorkerHost.standby
            TestWorkerHost.standby = null
            if ready != null {
                candidate := ready ?? new Process()
                if !candidate.HasExited {
                    return candidate
                }

                candidate.Dispose()
            }
        }

        return Spawn()
    }

    // Starts the next worker in the background.
    static func Replenish() {
        body: ThreadStart = () => {
            try {
                worker := Spawn()
                lock TestWorkerHost.gate {
                    previous := TestWorkerHost.standby
                    TestWorkerHost.standby = worker
                    if previous != null {
                        Kill(previous ?? worker)
                    }
                }
            } catch spawnFailure: Exception {
                Debug.WriteLine(spawnFailure.Message)
            }
        }
        thread := new Thread(body)
        thread.IsBackground = true
        thread.Start()
    }

    static func Spawn(): Process {
        processPath := Environment.ProcessPath ?? "dotnet"
        entryAssembly := Assembly.GetEntryAssembly()
        entryPath: string? = null
        if entryAssembly != null {
            entryPath = entryAssembly.Location
        }

        prefix := DaemonExecKernels.GetSelfLaunchPrefix(processPath, entryPath)
        psi := new ProcessStartInfo()
        psi.FileName = prefix[0]
        index := 1
        while index < prefix.Length {
            psi.ArgumentList.Add(prefix[index])
            index = index + 1
        }

        psi.ArgumentList.Add(GetWorkerCommand())
        psi.UseShellExecute = false
        psi.RedirectStandardInput = true
        psi.RedirectStandardOutput = true
        psi.RedirectStandardError = true
        psi.CreateNoWindow = true
        process := Process.Start(psi)
        if process == null {
            throw new InvalidOperationException("Could not start an nlc test worker.")
        }

        return process ?? new Process()
    }

    static func Kill(worker: Process) {
        try {
            if !worker.HasExited {
                worker.Kill(true)
            }
        } catch killFailure: Exception {
            Debug.WriteLine(killFailure.Message)
        }
    }

    // Copies a worker stream to the request's console as it arrives. Bytes are decoded with one
    // stateful decoder per stream, so a character split across two reads is written whole.
    static func StartRelay(source: Stream, toStandardError: bool): Thread {
        body: ThreadStart = () => {
            decoder := new UTF8Encoding(false).GetDecoder()
            buffer := new byte[](8192)
            chars := new char[](8192)
            target := Console.Out
            if toStandardError {
                target = Console.Error
            }

            try {
                while true {
                    received := source.Read(buffer, 0, buffer.Length)
                    if received <= 0 {
                        break
                    }

                    decoded := decoder.GetChars(buffer, 0, received, chars, 0, false)
                    if decoded > 0 {
                        target.Write(chars, 0, decoded)
                    }
                }

                tail := decoder.GetChars(new byte[](0), 0, 0, chars, 0, true)
                if tail > 0 {
                    target.Write(chars, 0, tail)
                }

                target.Flush()
            } catch relayFailure: Exception {
                Debug.WriteLine(relayFailure.Message)
            }
        }
        thread := new Thread(body)
        thread.IsBackground = true
        thread.Start()
        return thread
    }

    // The run a worker is asked for, with this request's directory, environment and culture: the
    // worker was started before the request existed, so it adopts them before it runs anything.
    static func WriteRequest(target: Stream, testFramework: string?, outputPath: string, filter: string?, verbose: bool, outputMode: int, timeoutMs: int?, resultPath: string) {
        using writer := new BinaryWriter(target, new UTF8Encoding(false), true)
        writer.Write(1)
        writer.Write(testFramework ?? "")
        writer.Write(outputPath)
        writer.Write(filter != null)
        writer.Write(filter ?? "")
        writer.Write(verbose)
        writer.Write(outputMode)
        timeoutValue := -1
        if timeoutMs != null {
            timeoutValue = timeoutMs ?? -1
        }

        writer.Write(timeoutValue)
        writer.Write(resultPath)
        writer.Write(Directory.GetCurrentDirectory())
        writer.Write(CultureInfo.CurrentCulture.Name)
        writer.Write(CultureInfo.CurrentUICulture.Name)
        names := DaemonProcessEnvironment.GetNames()
        writer.Write(names.Length)
        for name in names {
            writer.Write(name)
            writer.Write(Environment.GetEnvironmentVariable(name) ?? "")
        }

        writer.Flush()
        target.Flush()
    }

    static func EmptyRun(): NativeTestRun {
        return new NativeTestRun(new List<NativeTestResult>(), new int[](0), 0)
    }

    // ── Worker side ─────────────────────────────────────────────────────────────────────────────

    // `nlc __test-worker`: wait for one request on stdin, run it exactly as in-process `nlc test`
    // would, write the results, exit. A worker whose server goes away (stdin closes before a request
    // arrives) simply exits.
    static func Run(): int {
        // A Ctrl-C in the terminal the server was started from reaches its whole process group; the
        // server decides when a worker stops, so the worker ignores it.
        interrupt := PosixSignalRegistration.Create(PosixSignal.SIGINT, context => {
            context.Cancel = true
        })
        try {
            input := Console.OpenStandardInput()
            using reader := new BinaryReader(input, new UTF8Encoding(false), true)
            version := 0
            try {
                version = reader.ReadInt32()
            } catch endOfInput: Exception {
                return 0
            }

            if version != 1 {
                return 2
            }

            testFramework := reader.ReadString()
            outputPath := reader.ReadString()
            hasFilter := reader.ReadBoolean()
            filterText := reader.ReadString()
            verbose := reader.ReadBoolean()
            outputMode := reader.ReadInt32()
            timeoutValue := reader.ReadInt32()
            resultPath := reader.ReadString()
            workingDirectory := reader.ReadString()
            culture := reader.ReadString()
            uiCulture := reader.ReadString()
            count := reader.ReadInt32()
            names := new string[](count)
            values := new string[](count)
            index := 0
            while index < count {
                names[index] = reader.ReadString()
                values[index] = reader.ReadString()
                index = index + 1
            }

            DaemonExecHost.ApplyEnvironment(names, values)
            Directory.SetCurrentDirectory(workingDirectory)
            DaemonExecHost.ApplyCulture(culture, uiCulture)

            filter: string? = null
            if hasFilter {
                filter = filterText
            }

            timeoutMs: int? = null
            if timeoutValue >= 0 {
                timeoutMs = timeoutValue
            }

            framework: string? = null
            if testFramework != "" {
                framework = testFramework
            }

            run := TestCommandHost.RunRunnerInProcess(framework, outputPath, filter, verbose, outputMode, timeoutMs)
            Console.Out.Flush()
            Console.Error.Flush()
            WriteResults(resultPath, run)
            return 0
        } finally {
            interrupt.Dispose()
        }
    }

    // Written to a temporary name and renamed into place, with a trailing marker: a worker killed
    // mid-write leaves no file the server could mistake for a complete result.
    static func WriteResults(resultPath: string, run: NativeTestRun) {
        temporaryPath := resultPath + ".partial"
        using stream := new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None)
        using writer := new BinaryWriter(stream, new UTF8Encoding(false), false)
        writer.Write(run.Results.Count)
        for result in run.Results {
            writer.Write(result.Name)
            writer.Write(result.DisplayName)
            writer.Write(result.Outcome)
            writer.Write(result.Duration)
            WriteOptional(writer, result.ErrorMessage)
            WriteOptional(writer, result.NsharpDescription)
        }

        writer.Write(run.OutcomeCount)
        rankIndex := 0
        while rankIndex < run.OutcomeCount {
            writer.Write(run.OutcomeRanks[rankIndex])
            rankIndex = rankIndex + 1
        }

        writer.Write(GetResultsMarker())
        writer.Flush()
        stream.Flush(true)
        writer.Dispose()
        stream.Dispose()
        File.Move(temporaryPath, resultPath, true)
    }

    static func ReadResults(resultPath: string): NativeTestRun? {
        try {
            using stream := new FileStream(resultPath, FileMode.Open, FileAccess.Read, FileShare.Read)
            using reader := new BinaryReader(stream, new UTF8Encoding(false), false)
            count := reader.ReadInt32()
            results := new List<NativeTestResult>()
            index := 0
            while index < count {
                name := reader.ReadString()
                displayName := reader.ReadString()
                outcome := reader.ReadString()
                duration := reader.ReadString()
                errorMessage := ReadOptional(reader)
                description := ReadOptional(reader)
                results.Add(new NativeTestResult(name, displayName, outcome, duration, errorMessage, description))
                index = index + 1
            }

            outcomeCount := reader.ReadInt32()
            ranks := new int[](Math.Max(outcomeCount, 0))
            rankIndex := 0
            while rankIndex < outcomeCount {
                ranks[rankIndex] = reader.ReadInt32()
                rankIndex = rankIndex + 1
            }

            if reader.ReadString() != GetResultsMarker() {
                return null
            }

            return new NativeTestRun(results, ranks, outcomeCount)
        } catch readFailure: Exception {
            return null
        }
    }

    static func GetResultsMarker(): string {
        return "nlc-test-results-end"
    }

    static func WriteOptional(writer: BinaryWriter, value: string?) {
        writer.Write(value != null)
        writer.Write(value ?? "")
    }

    static func ReadOptional(reader: BinaryReader): string? {
        present := reader.ReadBoolean()
        value := reader.ReadString()
        if present {
            return value
        }

        return null
    }
}
