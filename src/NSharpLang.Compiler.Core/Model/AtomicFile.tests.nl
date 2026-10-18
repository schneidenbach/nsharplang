namespace NSharpLang.Compiler

import System
import System.IO

// BUILD OUTPUTS ARE REPLACED, NEVER REWRITTEN IN PLACE (issue 253).
//
// A process that has an assembly open keeps the inode it opened. Holding a `FileStream` is the
// deterministic stand-in for a running server's mapping: if the writer truncates and rewrites the
// same inode, the held handle reads the new bytes, which is the corruption the issue reports. The
// holder shares Read | Delete, as the Windows loader does for a mapped assembly: the file may be
// renamed or replaced, but not rewritten underneath the holder.
func AtomicTempDirectory(): string {
    directory := Path.Combine(Path.GetTempPath(), "atomic-file-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func AtomicReadAll(held: FileStream): string {
    held.Position = 0
    reader := new StreamReader(held, System.Text.Encoding.UTF8, false, 1024, true)
    text := reader.ReadToEnd()
    reader.Dispose()
    return text
}

test "WriteAllBytes leaves the bytes a holder has open untouched and replaces the path" {
    directory := AtomicTempDirectory()
    try {
        path := Path.Combine(directory, "Out.dll")
        AtomicFile.WriteAllBytes(path, System.Text.Encoding.UTF8.GetBytes("old-contents"))
        held := new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete)
        try {
            AtomicFile.WriteAllBytes(path, System.Text.Encoding.UTF8.GetBytes("new, longer contents"))

            assert AtomicReadAll(held) == "old-contents"
            assert File.ReadAllText(path) == "new, longer contents"
        } finally {
            held.Dispose()
        }

        assert Directory.GetFiles(directory, "*.tmp").Length == 0
    } finally {
        Directory.Delete(directory, true)
    }
}

test "WriteAllBytes creates a file that is not there yet and leaves no temporary file" {
    directory := AtomicTempDirectory()
    try {
        path := Path.Combine(directory, "Fresh.dll")
        AtomicFile.WriteAllBytes(path, System.Text.Encoding.UTF8.GetBytes("fresh"))

        assert File.ReadAllText(path) == "fresh"
        assert Directory.GetFiles(directory).Length == 1
    } finally {
        Directory.Delete(directory, true)
    }
}

test "Copy replaces the destination without touching a holder and keeps the source's write time" {
    directory := AtomicTempDirectory()
    try {
        source := Path.Combine(directory, "source.dll")
        destination := Path.Combine(directory, "dest.dll")
        File.WriteAllText(source, "copied")
        File.SetLastWriteTimeUtc(source, new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc))
        File.WriteAllText(destination, "previous")
        held := new FileStream(destination, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete)
        try {
            AtomicFile.Copy(source, destination)

            assert AtomicReadAll(held) == "previous"
            assert File.ReadAllText(destination) == "copied"
            assert File.GetLastWriteTimeUtc(destination) == File.GetLastWriteTimeUtc(source)
        } finally {
            held.Dispose()
        }

        assert Directory.GetFiles(directory, "*.tmp").Length == 0
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a failed write leaves the existing file and no temporary file" {
    directory := AtomicTempDirectory()
    try {
        path := Path.Combine(directory, "Out.dll")
        File.WriteAllText(path, "keep")
        threw := false
        try {
            AtomicFile.Copy(Path.Combine(directory, "missing.dll"), path)
        } catch ex: Exception {
            threw = true
        }

        assert threw
        assert File.ReadAllText(path) == "keep"
        assert Directory.GetFiles(directory, "*.tmp").Length == 0
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a stale temporary from a killed build is swept and a fresh one is left alone" {
    directory := AtomicTempDirectory()
    try {
        path := Path.Combine(directory, "Out.dll")
        stale := path + ".0123456789abcdef.tmp"
        fresh := path + ".fedcba9876543210.tmp"
        other := Path.Combine(directory, "Other.dll.0123456789abcdef.tmp")
        File.WriteAllText(stale, "x")
        File.WriteAllText(fresh, "x")
        File.WriteAllText(other, "x")
        File.SetLastWriteTimeUtc(stale, DateTime.UtcNow - TimeSpan.FromDays(2))
        File.SetLastWriteTimeUtc(other, DateTime.UtcNow - TimeSpan.FromDays(2))

        AtomicFile.WriteAllBytes(path, System.Text.Encoding.UTF8.GetBytes("out"))

        assert !File.Exists(stale)
        assert File.Exists(fresh)
        assert File.Exists(other)
    } finally {
        Directory.Delete(directory, true)
    }
}
