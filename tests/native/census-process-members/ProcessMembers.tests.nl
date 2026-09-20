namespace NSharpLang.CensusProcessMembers.Tests

import System
import System.IO

test "Process.Id on the current process is the id the environment reports" {
    assert ProcessMembers.CurrentId() == Environment.ProcessId
}

test "Process.ProcessName on the current process is a non-empty name" {
    assert ProcessMembers.CurrentProcessName().Length > 0
}

test "Process.HasExited on the running process is false" {
    assert !ProcessMembers.CurrentHasExited()
}

test "Process.StartTime on the current process is a DateTime already in the past" {
    started := ProcessMembers.CurrentStartTime()
    assert started.Year >= 2020
    assert started <= DateTime.Now
}

test "Process.MainModule and its FileName read through to the executing binary" {
    fileName := ProcessMembers.CurrentMainModuleFileName()
    assert fileName.Length > 0
    assert fileName == Environment.ProcessPath
}

test "WaitForExitAsync fills its defaulted CancellationToken and completes before the exit code is read" {
    assert ProcessMembers.RunAndWaitForExit(0).Result == 0
    assert ProcessMembers.RunAndWaitForExit(3).Result == 3
}

test "StandardOutput still reads a redirected child's output" {
    assert ProcessMembers.RunAndReadOutput("census").Result == "census"
}

test "a static call fills the same defaulted CancellationToken" {
    path := Path.Combine(Path.GetTempPath(), "census-process-members-" + Environment.ProcessId.ToString() + ".txt")
    try {
        assert ProcessMembers.WriteThenReadBack(path, "round-trip").Result == "round-trip"
    } finally {
        File.Delete(path)
    }
}
