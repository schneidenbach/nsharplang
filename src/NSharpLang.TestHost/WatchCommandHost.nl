namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Threading
import NSharpLang.Cli

// `nlc watch <check|build|test|lint|format>`.
//
// It runs the watched command once, then re-runs it whenever a file the kernels care about changes,
// debounced, until Ctrl-C or `--max-runs`. Every rule — which targets exist, which changed paths
// count, what the debounce default is, when to stop — is `WatchCommandKernels` in Compiler.Core.
// This owner is the `FileSystemWatcher`, the wake signal and the loop.
//
// It lives beside `CliPipeline` because it RE-ENTERS it: a watched run is the same dispatch an
// ordinary invocation takes, with the working directory moved to the project root and the version
// carried through so a watched `nlc help` still reports `Cli.dll`'s own version.
static class WatchCommandHost {
    static func Execute(args: string[], version: string): int {
        options := WatchCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            Console.WriteLine(WatchCommandKernels.GetHelpText())
            return 0
        }

        targetSummary := WatchCommandKernels.GetTargetSummary(args)
        targetNameForError := WatchCommandKernels.GetUnsupportedTargetName(args)
        if targetSummary.TargetKind == 0 {
            return Error(WatchCommandKernels.GetUnsupportedTargetMessage(targetNameForError))
        }

        watchedCommand := WatchCommandKernels.GetTargetCommandName(targetSummary.TargetKind)

        forwardedArgs := WatchCommandKernels.GetForwardedArgs(args)
        projectRoot := WatchCommandKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory())

        if !Directory.Exists(projectRoot) {
            return Error(WatchCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot))
        }

        debounceMs := ParsePositiveInt(options.DebounceMsOption, WatchCommandKernels.GetDefaultDebounceMilliseconds(), "--debounce-ms")
        if debounceMs == null {
            return 1
        }

        debounceValue: int = debounceMs

        maxRuns := ParsePositiveInt(options.MaxRunsOption, null, "--max-runs")
        if options.MaxRunsOption != null && maxRuns == null {
            return 1
        }

        hasMaxRuns := maxRuns != null
        maxRunsValue := 0
        if maxRuns != null {
            maxRunsValue = maxRuns
        }

        state := new WatchLoopState()
        wakeSignal := new AutoResetEvent(false)
        lastExitCode := RunWatchedCommand(projectRoot, watchedCommand, forwardedArgs, version)
        runCount := 1

        if WatchCommandKernels.ShouldStopAfterRun(runCount, hasMaxRuns, maxRunsValue) {
            return lastExitCode
        }

        using watcher := new FileSystemWatcher(projectRoot)
        watcher.IncludeSubdirectories = true
        watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.CreationTime

        changedSubscription := on watcher.Changed (sender, eventArgs) => WatchCommandHost.HandleChange(state, wakeSignal, eventArgs.FullPath)
        createdSubscription := on watcher.Created (sender, eventArgs) => WatchCommandHost.HandleChange(state, wakeSignal, eventArgs.FullPath)
        deletedSubscription := on watcher.Deleted (sender, eventArgs) => WatchCommandHost.HandleChange(state, wakeSignal, eventArgs.FullPath)
        renamedSubscription := on watcher.Renamed (sender, eventArgs) => WatchCommandHost.HandleChange(state, wakeSignal, eventArgs.FullPath)
        watcher.EnableRaisingEvents = true

        Console.WriteLine(WatchCommandKernels.GetStartedMessage(projectRoot))

        cancelSubscription := on Console.CancelKeyPress (sender, eventArgs) => WatchCommandHost.Cancel(state, wakeSignal, eventArgs)

        try {
            while !state.Cancelled {
                wakeSignal.WaitOne(100)

                shouldRun := state.TakePendingChange(debounceValue)
                if !shouldRun {
                    continue
                }

                Console.WriteLine()
                changeTime := DateTime.Now.ToString(WatchCommandKernels.GetChangeTimeFormat())
                Console.WriteLine(WatchCommandKernels.GetChangeDetectedMessage(changeTime, watchedCommand))
                lastExitCode = RunWatchedCommand(projectRoot, watchedCommand, forwardedArgs, version)
                runCount = runCount + 1

                if WatchCommandKernels.ShouldStopAfterRun(runCount, hasMaxRuns, maxRunsValue) {
                    return lastExitCode
                }
            }

            return lastExitCode
        } finally {
            off cancelSubscription
            off changedSubscription
            off createdSubscription
            off deletedSubscription
            off renamedSubscription
        }
    }

    static func HandleChange(state: WatchLoopState, wakeSignal: AutoResetEvent, path: string) {
        if !WatchCommandKernels.ShouldTriggerForChangedPath(path) {
            return
        }

        state.RecordChange()
        wakeSignal.Set()
    }

    // Ctrl-C asks the loop to leave rather than killing the process, so the watched command's last
    // exit code is still the one `nlc watch` answers with.
    static func Cancel(state: WatchLoopState, wakeSignal: AutoResetEvent, eventArgs: ConsoleCancelEventArgs) {
        eventArgs.Cancel = true
        state.Cancel()
        wakeSignal.Set()
    }

    static func RunWatchedCommand(projectRoot: string, watchedCommand: string, forwardedArgs: IReadOnlyList<string>, version: string): int {
        originalDirectory := Directory.GetCurrentDirectory()
        try {
            Directory.SetCurrentDirectory(projectRoot)
            commandArgs := new string[](forwardedArgs.Count + 1)
            commandArgs[0] = watchedCommand
            index := 0
            while index < forwardedArgs.Count {
                commandArgs[index + 1] = forwardedArgs[index]
                index = index + 1
            }

            return CliPipeline.Execute(commandArgs, version)
        } finally {
            Directory.SetCurrentDirectory(originalDirectory)
        }
    }

    static func ParsePositiveInt(value: string?, defaultValue: int?, flag: string): int? {
        hasDefault := defaultValue != null
        defaultNumber := 0
        if defaultValue != null {
            defaultNumber = defaultValue
        }

        parsed := WatchCommandKernels.ParsePositiveIntOption(value, hasDefault, defaultNumber)
        if parsed.IsValid {
            return WatchCommandKernels.GetParsedOptionalIntValue(parsed)
        }

        Error(WatchCommandKernels.GetPositiveIntExpectedMessage(flag))
        return null
    }

    // `nlc watch`'s own refusals name their remedy and answer 1; they are not routed through
    // `CliError.Report`, which prefixes `Error: `, because these sentences carry their own wording.
    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }
}

// The watcher's threads and the loop share three mutable facts. They were three captured locals and
// a `lock` object in the C# owner; they are one object with a lock inside it here, so no caller can
// read one of them outside the lock.
class WatchLoopState {
    sync: object
    cancelledValue: bool
    pendingChangeValue: bool
    lastChangeUtcValue: DateTime

    Cancelled: bool => cancelledValue

    constructor() {
        sync = new object()
        cancelledValue = false
        pendingChangeValue = false
        lastChangeUtcValue = DateTime.MinValue
    }

    func RecordChange() {
        lock sync {
            pendingChangeValue = true
            lastChangeUtcValue = DateTime.UtcNow
        }
    }

    func Cancel() {
        cancelledValue = true
    }

    // The debounce: a change only runs the command once it has been quiet for the window, and
    // claiming it clears the flag so one change cannot run the command twice.
    func TakePendingChange(debounceMs: int): bool {
        lock sync {
            quietFor := DateTime.UtcNow - lastChangeUtcValue
            debounceWindow := TimeSpan.FromMilliseconds((double)debounceMs)
            settled := quietFor >= debounceWindow
            shouldRun := pendingChangeValue && settled
            if shouldRun {
                pendingChangeValue = false
            }

            return shouldRun
        }
    }
}
