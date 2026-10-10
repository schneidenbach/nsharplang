namespace NSharpLang.GateScriptContracts.Tests

import System
import System.Collections.Generic
import System.IO
import System.Security.Cryptography
import System.Text

// ─── THE PRODUCT GATE'S SHARED NUGET STORE ────────────────────────────────────────────────────
//
// Any number of product gates, at any mix of commits, run on one machine at once. Each restores
// into a packages folder of its own; what they share is `tests/scripts/test-all.sh`'s NuGet store:
// immutable `<id>/<version>/<sha512>/` entries, published by one atomic rename and never modified.
// Before it, one packages folder per dependency key was shared and rewritten in place: a gate at one
// commit deleted `nsharplang.runtime/0.1.0` while another was copying it (MSB3030), and every launch
// re-copied the user's global-cache seed over the one the tree under test had committed.
//
// These rows run the SHIPPED store program -- the `nuget_store` heredoc lifted out of the script --
// against synthetic packages, including several copies of it racing one another as processes.
func StoreScript(workRoot: string): string {
    python := ExtractPythonHeredoc(ReadGateScript("test-all.sh"), "python3 - \"$@\" <<'PY'", "tests/scripts/test-all.sh")
    path := Path.Combine(workRoot, "nuget-store.py")
    File.WriteAllText(path, python)
    return path
}

func NuGetOrgSource(): string {
    return "https://api.nuget.org/v3/index.json"
}

// A package laid out the way NuGet extracts one: the `.nupkg`, its base64 `.sha512`, an optional
// `.nupkg.metadata` naming its source, and `fileCount` content files so a copy takes long enough to
// overlap its rivals. Returns the lowercase hex SHA-512 the store keys the entry by.
func WriteFakePackage(packages: string, packageId: string, version: string, source: string, seed: int, fileCount: int): string {
    directory := Path.Combine(Path.Combine(packages, packageId), version)
    Directory.CreateDirectory(Path.Combine(directory, "lib"))

    payload := new byte[4 * 1024 * 1024]
    index := 0
    while index < payload.Length {
        payload[index] = (byte)((index * 31 + seed * 17) % 251)
        index = index + 1
    }

    stem := Path.Combine(directory, packageId + "." + version + ".nupkg")
    File.WriteAllBytes(stem, payload)
    digest := SHA512.HashData(payload)
    File.WriteAllText(stem + ".sha512", Convert.ToBase64String(digest))
    if source != "" {
        File.WriteAllText(Path.Combine(directory, ".nupkg.metadata"), "{\"version\": 2, \"contentHash\": \"x\", \"source\": \"" + source + "\"}")
    }

    file := 0
    while file < fileCount {
        File.WriteAllText(Path.Combine(Path.Combine(directory, "lib"), "part" + file.ToString() + ".txt"), packageId + " " + file.ToString())
        file = file + 1
    }

    return Convert.ToHexString(digest).ToLowerInvariant()
}

func StoreRun(script: string, command: string, store: string, index: string, packages: string): ProcessRun {
    launch := new ProcessLaunch("python3", RepositoryRoot(), 180000)
    launch.Arguments.Add(script)
    launch.Arguments.Add(command)
    launch.Arguments.Add(store)
    launch.Arguments.Add(index)
    launch.Arguments.Add(packages)
    return Run(launch)
}

func ShellQuote(value: string): string {
    return "'" + value.Replace("'", "'\"'\"'") + "'"
}

// Every shell command started in the background by ONE shell before it waits on any, so they
// genuinely overlap; each exit code lands in `<workRoot>/rc-<n>`. Returns those exit codes, as
// written, in order.
func StoreRunConcurrently(workRoot: string, commands: List<string>): List<string> {
    builder := new StringBuilder()
    index := 0
    while index < commands.Count {
        builder.Append("( ( " + commands[index] + " ) > " + ShellQuote(Path.Combine(workRoot, "out-" + index.ToString())) + " 2>&1; echo $? > " + ShellQuote(Path.Combine(workRoot, "rc-" + index.ToString())) + " ) &\n")
        index = index + 1
    }

    builder.Append("wait\n")
    run := Run(BashLaunch(builder.ToString(), 300000))
    if run.ExitCode != 0 {
        throw new InvalidOperationException("The concurrent store runs did not finish: " + run.Report())
    }

    codes := new List<string>()
    read := 0
    while read < commands.Count {
        codes.Add(File.ReadAllText(Path.Combine(workRoot, "rc-" + read.ToString())).Trim())
        read = read + 1
    }

    return codes
}

func StoreCommand(script: string, command: string, store: string, index: string, packages: string): string {
    return "python3 " + ShellQuote(script) + " " + command + " " + ShellQuote(store) + " " + ShellQuote(index) + " " + ShellQuote(packages)
}

// A reader that keeps starting fresh runs -- each materializing into a new packages folder -- until
// one of them finds `packageId`, so the reads straddle the whole publication rather than landing
// before or after it. Bounded: 400 attempts.
func StoreReaderUntilPublished(script: string, store: string, index: string, readerBase: string, packageId: string): string {
    folder := ShellQuote(readerBase) + "-$attempt"
    return "for attempt in $(seq 1 400); do " + "python3 " + ShellQuote(script) + " materialize " + ShellQuote(store) + " " + ShellQuote(index) + " " + folder + " || exit 1; if [ -d " + folder + "/" + packageId + " ]; then exit 0; fi; done; exit 2"
}

func PackageFileCount(directory: string): int {
    return Directory.GetFiles(directory, "*", SearchOption.AllDirectories).Length
}

// The entry's `.nupkg` hashes to the name it is published under, and every content file is there.
func EntryIsIntact(directory: string, packageId: string, version: string, digest: string, expectedFiles: int): bool {
    nupkg := Path.Combine(directory, packageId + "." + version + ".nupkg")
    if !File.Exists(nupkg) {
        return false
    }

    actual := Convert.ToHexString(SHA512.HashData(File.ReadAllBytes(nupkg))).ToLowerInvariant()
    return actual == digest && PackageFileCount(directory) == expectedFiles
}

func StagingLeftovers(store: string): int {
    staging := Path.Combine(store, ".staging")
    if !Directory.Exists(staging) {
        return 0
    }

    return Directory.GetFileSystemEntries(staging).Length
}

test "a gate restores into its own run's packages folder and takes its seed only from its own tree's bootstrap" {
    script := ReadGateScript("test-all.sh")
    assert script.Contains("RUN_PACKAGES=\"$RUN_ROOT/nuget/packages\""), "The packages folder a run restores into must live under that run's private root."
    assert script.Contains("export NUGET_PACKAGES=\"$RUN_PACKAGES\""), "The core gate must restore into the run's private packages folder."
    assert !script.Contains(".nuget/packages"), "The gate must never read a seed out of the user's global NuGet cache."
    assert !script.Contains("NUGET_PACKAGES:-"), "The gate must never read a seed out of the caller's NUGET_PACKAGES."

    // The bytes checked against SHA256SUMS are the COPIED tree's -- the ones its restore consumes.
    copyIndex := script.IndexOf("\ncopy_source_tree\n")
    verifyIndex := script.IndexOf("python3 \"$RUN_REPO/scripts/verify-bootstrap.py\"")
    coreIndex := script.IndexOf("export NUGET_PACKAGES=")
    assert copyIndex >= 0 && verifyIndex > copyIndex && coreIndex > verifyIndex, "verify-bootstrap.py must check the copied tree after the copy and before the core gate restores."
    nugetConfig := File.ReadAllText(Path.Combine(RepositoryRoot(), "NuGet.config"))
    assert nugetConfig.Contains("<clear />") && nugetConfig.Contains("value=\"bootstrap\""), "The tree's NuGet.config is what makes its bootstrap/ the seed's only source."

    workRoot := NewTempDirectory("nsharp-nuget-store-seed")
    try {
        store := StoreScript(workRoot)
        storeRoot := Path.Combine(workRoot, "store")
        index := Path.Combine(workRoot, "deps/index.txt")
        first := Path.Combine(workRoot, "run-1")
        WriteFakePackage(first, "nsharplang.sdk", "0.1.0", "/some/other/tree/bootstrap", 1, 3)
        WriteFakePackage(first, "nsharplang.runtime", "0.1.0", NuGetOrgSource(), 2, 3)
        WriteFakePackage(first, "fixture.localfeed", "1.0.0", "/tmp/private-feed", 3, 3)
        shared := WriteFakePackage(first, "shared.dependency", "2.0.0", NuGetOrgSource(), 4, 3)
        fromResolver := WriteFakePackage(first, "resolver.download", "3.0.0", "", 5, 3)

        promoted := StoreRun(store, "promote", storeRoot, index, first)
        assert promoted.ExitCode == 0, promoted.Report()

        second := Path.Combine(workRoot, "run-2")
        materialized := StoreRun(store, "materialize", storeRoot, index, second)
        assert materialized.ExitCode == 0, materialized.Report()

        assert !Directory.Exists(Path.Combine(storeRoot, "nsharplang.sdk")), "A seed must never enter the shared store."
        assert !Directory.Exists(Path.Combine(storeRoot, "nsharplang.runtime")), "No NSharpLang identity may enter the shared store, whatever its source."
        assert !Directory.Exists(Path.Combine(storeRoot, "fixture.localfeed")), "A package from a local feed must never enter the shared store."
        assert !Directory.Exists(Path.Combine(second, "nsharplang.sdk")), "A run must start with no seed, so its first restore extracts its own tree's."
        assert !Directory.Exists(Path.Combine(second, "nsharplang.runtime"))
        assert !Directory.Exists(Path.Combine(second, "fixture.localfeed"))
        assert EntryIsIntact(Path.Combine(second, "shared.dependency/2.0.0"), "shared.dependency", "2.0.0", shared, 6)
        assert EntryIsIntact(Path.Combine(second, "resolver.download/3.0.0"), "resolver.download", "3.0.0", fromResolver, 5)
    } finally {
        DeleteTempDirectory(workRoot)
    }
}

test "concurrent promotions of the same package publish exactly one intact entry and leave no staging behind" {
    workRoot := NewTempDirectory("nsharp-nuget-store-race")
    try {
        store := StoreScript(workRoot)
        storeRoot := Path.Combine(workRoot, "store")
        commands := new List<string>()
        digest := ""
        run := 0
        while run < 8 {
            packages := Path.Combine(workRoot, "run-" + run.ToString())
            digest = WriteFakePackage(packages, "raced.package", "1.2.3", NuGetOrgSource(), 7, 400)
            commands.Add(StoreCommand(store, "promote", storeRoot, Path.Combine(workRoot, "index-" + run.ToString() + ".txt"), packages))
            run = run + 1
        }

        codes := StoreRunConcurrently(workRoot, commands)
        code := 0
        while code < codes.Count {
            assert codes[code] == "0", "Promoter " + code.ToString() + " failed: " + File.ReadAllText(Path.Combine(workRoot, "out-" + code.ToString()))
            code = code + 1
        }

        versionDirectory := Path.Combine(storeRoot, "raced.package/1.2.3")
        entries := Directory.GetDirectories(versionDirectory)
        assert entries.Length == 1, "Racing promotions must leave exactly one entry, found " + entries.Length.ToString()
        assert Path.GetFileName(entries[0]) == digest, "The entry must be keyed by the SHA-512 of its .nupkg."
        assert EntryIsIntact(entries[0], "raced.package", "1.2.3", digest, 403)
        assert StagingLeftovers(storeRoot) == 0, "Every loser must discard its staged copy."

        // Every racer, winner or loser, records the one published entry for its dependency key.
        indexRun := 0
        while indexRun < 8 {
            recorded := File.ReadAllText(Path.Combine(workRoot, "index-" + indexRun.ToString() + ".txt"))
            assert recorded.Trim() == "raced.package 1.2.3 " + digest
            indexRun = indexRun + 1
        }
    } finally {
        DeleteTempDirectory(workRoot)
    }
}

test "a published entry is never modified by a later promotion of the same package" {
    workRoot := NewTempDirectory("nsharp-nuget-store-immutable")
    try {
        store := StoreScript(workRoot)
        storeRoot := Path.Combine(workRoot, "store")
        index := Path.Combine(workRoot, "index.txt")
        first := Path.Combine(workRoot, "run-1")
        digest := WriteFakePackage(first, "stable.package", "4.0.0", NuGetOrgSource(), 9, 3)
        assert StoreRun(store, "promote", storeRoot, index, first).ExitCode == 0

        entry := Path.Combine(Path.Combine(storeRoot, "stable.package/4.0.0"), digest)
        nupkg := Path.Combine(entry, "stable.package.4.0.0.nupkg")
        pinned := new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc)
        File.SetLastWriteTimeUtc(nupkg, pinned)
        Directory.SetLastWriteTimeUtc(entry, pinned)

        second := Path.Combine(workRoot, "run-2")
        WriteFakePackage(second, "stable.package", "4.0.0", NuGetOrgSource(), 9, 3)
        File.WriteAllText(Path.Combine(Path.Combine(second, "stable.package/4.0.0"), "lib/written-by-run-2.txt"), "a run's own mutation")
        assert StoreRun(store, "promote", storeRoot, index, second).ExitCode == 0

        assert File.GetLastWriteTimeUtc(nupkg) == pinned, "A published .nupkg must never be rewritten."
        assert Directory.GetLastWriteTimeUtc(entry) == pinned, "Nothing may be added to or removed from a published entry."
        assert !File.Exists(Path.Combine(entry, "lib/written-by-run-2.txt"))
        assert EntryIsIntact(entry, "stable.package", "4.0.0", digest, 6)
    } finally {
        DeleteTempDirectory(workRoot)
    }
}

test "a run never reads a partially written entry" {
    workRoot := NewTempDirectory("nsharp-nuget-store-torn")
    try {
        store := StoreScript(workRoot)
        storeRoot := Path.Combine(workRoot, "store")
        index := Path.Combine(workRoot, "index.txt")

        // A promoter killed mid-copy leaves its half-staged entry under `.staging`, never at the
        // published path, so nothing a run reads can name it.
        staged := Path.Combine(workRoot, "staged")
        stagedDigest := WriteFakePackage(staged, "crashed.package", "1.0.0", NuGetOrgSource(), 11, 3)
        Directory.CreateDirectory(Path.Combine(storeRoot, ".staging/0123abcd"))
        Directory.Move(Path.Combine(staged, "crashed.package/1.0.0"), Path.Combine(storeRoot, ".staging/0123abcd/entry"))

        // An entry torn at the published path (a truncated .nupkg) fails verification and is skipped.
        torn := Path.Combine(workRoot, "torn")
        tornDigest := WriteFakePackage(torn, "torn.package", "1.0.0", NuGetOrgSource(), 12, 3)
        tornEntry := Path.Combine(Path.Combine(storeRoot, "torn.package/1.0.0"), tornDigest)
        Directory.CreateDirectory(Path.GetDirectoryName(tornEntry) ?? "")
        Directory.Move(Path.Combine(torn, "torn.package/1.0.0"), tornEntry)
        File.WriteAllBytes(Path.Combine(tornEntry, "torn.package.1.0.0.nupkg"), new byte[16])

        File.WriteAllText(index, "crashed.package 1.0.0 " + stagedDigest + "\ntorn.package 1.0.0 " + tornDigest + "\n")
        reader := Path.Combine(workRoot, "reader")
        assert StoreRun(store, "materialize", storeRoot, index, reader).ExitCode == 0
        assert !Directory.Exists(Path.Combine(reader, "crashed.package")), "A staged entry must never be read."
        assert !Directory.Exists(Path.Combine(reader, "torn.package")), "An entry whose .nupkg does not hash to its name must never be read."

        // Readers racing a publication see the entry whole or not at all.
        racedIndex := Path.Combine(workRoot, "raced-index.txt")
        publisher := Path.Combine(workRoot, "publisher")
        digest := WriteFakePackage(publisher, "published.package", "2.0.0", NuGetOrgSource(), 13, 2000)
        File.WriteAllText(racedIndex, "published.package 2.0.0 " + digest + "\n")
        readerRoot := Path.Combine(workRoot, "raced-readers")
        Directory.CreateDirectory(readerRoot)
        commands := new List<string>()
        readers := 0
        while readers < 6 {
            commands.Add(StoreReaderUntilPublished(store, storeRoot, racedIndex, Path.Combine(readerRoot, "reader-" + readers.ToString()), "published.package"))
            readers = readers + 1
        }

        commands.Add(StoreCommand(store, "promote", storeRoot, Path.Combine(workRoot, "publisher-index.txt"), publisher))
        codes := StoreRunConcurrently(workRoot, commands)
        code := 0
        while code < codes.Count {
            assert codes[code] == "0", "Store run " + code.ToString() + " failed: " + File.ReadAllText(Path.Combine(workRoot, "out-" + code.ToString()))
            code = code + 1
        }

        // Every reader stopped only once it found the package, so each one read it at least once.
        readFolders := Directory.GetDirectories(readerRoot)
        found := 0
        folderIndex := 0
        while folderIndex < readFolders.Length {
            read := Path.Combine(readFolders[folderIndex], "published.package/2.0.0")
            if Directory.Exists(read) {
                assert EntryIsIntact(read, "published.package", "2.0.0", digest, 2003), "A reader cloned a partial entry into " + readFolders[folderIndex]
                found = found + 1
            }

            folderIndex = folderIndex + 1
        }

        assert found == 6, "Every reader must have found the published package, found " + found.ToString()
    } finally {
        DeleteTempDirectory(workRoot)
    }
}
