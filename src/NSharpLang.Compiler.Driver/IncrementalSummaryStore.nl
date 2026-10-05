namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Security.Cryptography
import System.Text

// THE ONE ON-DISK ENVELOPE every incremental cache file uses: a payload followed by its own SHA-256.
// A truncated, partially written or hand-edited file fails the checksum and reads as nothing. Writes
// go to a unique temp file that is renamed over the target, so a reader sees the old file or the new
// one. Neither door throws: a cache that cannot be read or written is a cache miss.
static class IncrementalCacheFile {
    static func ReadPayload(path: string): byte[]? {
        try {
            if !File.Exists(path) {
                return null
            }

            bytes := File.ReadAllBytes(path)
            if bytes.Length <= 32 {
                return null
            }

            payloadLength := bytes.Length - 32
            algorithm := SHA256.Create()
            computed: byte[] = null
            try {
                computed = algorithm.ComputeHash(bytes, 0, payloadLength)
            } finally {
                algorithm.Dispose()
            }

            index := 0
            while index < 32 {
                if computed[index] != bytes[payloadLength + index] {
                    return null
                }
                index = index + 1
            }

            payload := new byte[payloadLength]
            Array.Copy(bytes, payload, payloadLength)
            return payload
        } catch {
            return null
        }
    }

    static func WritePayload(path: string, payload: byte[]): bool {
        tempPath := path + "." + Guid.NewGuid().ToString("N") + ".tmp"
        try {
            directory := Path.GetDirectoryName(path)
            if directory != null {
                Directory.CreateDirectory(directory)
            }

            algorithm := SHA256.Create()
            checksum: byte[] = null
            try {
                checksum = algorithm.ComputeHash(payload)
            } finally {
                algorithm.Dispose()
            }

            file := new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None)
            try {
                file.Write(payload, 0, payload.Length)
                file.Write(checksum, 0, checksum.Length)
            } finally {
                file.Dispose()
            }

            File.Move(tempPath, path, true)
            return true
        } catch {
            IncrementalCacheFile.TryDeleteTemporary(tempPath)
            return false
        }
    }

    // A temp file left by a failed write is litter, not a cache: no reader ever opens a `.tmp`.
    private static func TryDeleteTemporary(tempPath: string): bool {
        try {
            if File.Exists(tempPath) {
                File.Delete(tempPath)
            }
            return true
        } catch {
            return false
        }
    }
}

// THE PERSISTED PER-FILE SUMMARIES (`IncrementalFileSummary`), so a process that opens a session cold
// does not re-derive the dependency summary of every file it has seen before. One file per project
// output name under `obj/nlc/`, keyed by the compiler's identity and the summary format: a summary
// computed by any other compiler is not loaded. Each entry is keyed by path AND text hash, so a
// loaded summary is only ever used for the exact bytes it was computed from.
static class IncrementalSummaryStore {
    static func Magic(): string => "NSHARP-INCREMENTAL-SUMMARIES"

    static FormatVersion: int => 1

    static func PathFor(projectRoot: string, assemblyName: string): string {
        return Path.Combine(Path.GetFullPath(projectRoot), "obj", "nlc", assemblyName + ".summaries")
    }

    private static func Identity(): string {
        return IncrementalCompilerIdentity.Current() + "/" + IncrementalFileSummary.FormatVersion.ToString()
    }

    static func LoadInto(path: string, cache: Dictionary<string, IncrementalFileSummary>): int {
        payload := IncrementalCacheFile.ReadPayload(path)
        if payload == null {
            return 0
        }

        loaded := new List<IncrementalFileSummary>()
        try {
            reader := new BinaryReader(new MemoryStream(payload), Encoding.UTF8)
            try {
                if reader.ReadString() != IncrementalSummaryStore.Magic() {
                    return 0
                }
                if reader.ReadInt32() != IncrementalSummaryStore.FormatVersion {
                    return 0
                }
                if reader.ReadString() != IncrementalSummaryStore.Identity() {
                    return 0
                }

                count := reader.ReadInt32()
                index := 0
                while index < count {
                    summaryPath := reader.ReadString()
                    textHash := reader.ReadString()
                    surfaceHash := reader.ReadString()
                    opaque := reader.ReadBoolean()
                    summary := new IncrementalFileSummary(summaryPath, textHash, surfaceHash, opaque)
                    if reader.ReadBoolean() {
                        summary.Namespace = reader.ReadString()
                    }
                    ReadSet(reader, summary.DeclaredNames)
                    ReadSet(reader, summary.BaseNames)
                    ReadSet(reader, summary.ReferencedNames)
                    ReadSet(reader, summary.Mentions)
                    loaded.Add(summary)
                    index = index + 1
                }
            } finally {
                reader.Dispose()
            }
        } catch {
            return 0
        }

        for summary in loaded {
            cache[summary.Path + "|" + summary.TextHash] = summary
        }
        return loaded.Count
    }

    static func Write(path: string, summaries: List<IncrementalFileSummary>): bool {
        stream := new MemoryStream()
        writer := new BinaryWriter(stream, Encoding.UTF8)
        writer.Write(IncrementalSummaryStore.Magic())
        writer.Write(IncrementalSummaryStore.FormatVersion)
        writer.Write(IncrementalSummaryStore.Identity())
        writer.Write(summaries.Count)
        for summary in summaries {
            writer.Write(summary.Path)
            writer.Write(summary.TextHash)
            writer.Write(summary.SurfaceHash)
            writer.Write(summary.Opaque)
            namespaceName := summary.Namespace
            if namespaceName == null {
                writer.Write(false)
            } else {
                writer.Write(true)
                writer.Write(namespaceName)
            }
            WriteSet(writer, summary.DeclaredNames)
            WriteSet(writer, summary.BaseNames)
            WriteSet(writer, summary.ReferencedNames)
            WriteSet(writer, summary.Mentions)
        }
        writer.Flush()
        payload := stream.ToArray()
        writer.Dispose()
        return IncrementalCacheFile.WritePayload(path, payload)
    }

    private static func WriteSet(writer: BinaryWriter, values: HashSet<string>) {
        ordered := new List<string>(values)
        ordered.Sort(StringComparer.Ordinal)
        writer.Write(ordered.Count)
        for value in ordered {
            writer.Write(value)
        }
    }

    private static func ReadSet(reader: BinaryReader, values: HashSet<string>) {
        count := reader.ReadInt32()
        index := 0
        while index < count {
            values.Add(reader.ReadString())
            index = index + 1
        }
    }
}
