namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Metadata
import System.Reflection.PortableExecutable
import System.Runtime.CompilerServices
import System.Threading


// A metadata reader must never retain a view over a reference file that another process can rewrite.
// The image is copied through a read-only, shared-read handle once per path and the owned byte array
// is what MetadataLoadContext receives. Later file changes therefore select either the complete
// image we already captured or a clean load failure; they cannot invalidate metadata handles.
class ReferenceImageSnapshotStore {
    private class AssemblyOrigin {
        Path: string

        constructor(path: string) {
            Path = path
        }
    }

    private static readonly origins: ConditionalWeakTable<Assembly, ReferenceImageSnapshotStore.AssemblyOrigin> = new ConditionalWeakTable<Assembly, ReferenceImageSnapshotStore.AssemblyOrigin>()
    private static readonly originsGate: object = new object()

    Gate: object
    private readonly imagesByPath: Dictionary<string, byte[]>
    private readonly assemblyNamesByPath: Dictionary<string, AssemblyName>

    constructor(): this(new object()) {
    }

    constructor(loadGate: object) {
        Gate = loadGate
        imagesByPath = new Dictionary<string, byte[]>(StringComparer.Ordinal)
        assemblyNamesByPath = new Dictionary<string, AssemblyName>(StringComparer.Ordinal)
    }

    private static func RetryDelayMilliseconds(attempt: int): int {
        delay := 100 * (attempt + 1)
        return delay > 750 ? 750 : delay
    }

    // The immutable image for a path, copied before it is given to a metadata reader. A file that is
    // temporarily absent or being replaced gets a bounded backoff window for its build to publish
    // the completed DLL; after that the caller receives an IOException and reports a reference-load
    // diagnostic rather than letting a reader continue over changing bytes.
    func Capture(path: string): byte[] {
        fullPath := Path.GetFullPath(path)
        lock Gate {
            image: byte[]? = null
            if imagesByPath.TryGetValue(fullPath, out image) && image != null {
                return image
            }

            lastFailure: IOException? = null
            attempt := 0
            while attempt < 16 {
                try {
                    stream := File.Open(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read)
                    try {
                        expectedLength := stream.Length
                        if expectedLength <= 0 || expectedLength > int.MaxValue {
                            throw new IOException("Reference image has an unsupported or incomplete size: " + fullPath)
                        }

                        writeTicks := File.GetLastWriteTimeUtc(fullPath).Ticks
                        copied := new byte[(int)expectedLength]
                        offset := 0
                        while offset < copied.Length {
                            count := stream.Read(copied, offset, copied.Length - offset)
                            if count == 0 {
                                throw new IOException("Reference image changed while it was being copied: " + fullPath)
                            }
                            offset = offset + count
                        }

                        current := new FileInfo(fullPath)
                        if stream.Length != expectedLength || !current.Exists || current.Length != expectedLength || current.LastWriteTimeUtc.Ticks != writeTicks {
                            throw new IOException("Reference image changed while it was being copied: " + fullPath)
                        }

                        imagesByPath[fullPath] = copied
                        return copied
                    } finally {
                        stream.Dispose()
                    }
                } catch readFailure: IOException {
                    lastFailure = readFailure
                    Thread.Sleep(ReferenceImageSnapshotStore.RetryDelayMilliseconds(attempt))
                }

                attempt = attempt + 1
            }

            throw new IOException("Could not take a stable snapshot of reference image '" + fullPath + "'. Retry after the build that writes it finishes.", lastFailure)
        }
    }

    // Load one captured image into a metadata universe. Its original path is kept separately because
    // in-memory metadata assemblies intentionally have an empty Assembly.Location.
    func LoadFromPath(context: MetadataLoadContext, path: string): Assembly {
        AssemblyNameForPath(path)
        return LoadFromImage(context, path, Capture(path))
    }

    // Kept as a separate operation so a test can place a deterministic file rewrite between capture
    // and load, the vulnerable interval this store closes in production.
    func LoadFromImage(context: MetadataLoadContext, path: string, image: byte[]): Assembly {
        fullPath := Path.GetFullPath(path)
        assembly := context.LoadFromByteArray(image)
        lock Gate {
            imagesByPath[fullPath] = image
            lock ReferenceImageSnapshotStore.originsGate {
                ReferenceImageSnapshotStore.origins.Remove(assembly)
                ReferenceImageSnapshotStore.origins.Add(assembly, new ReferenceImageSnapshotStore.AssemblyOrigin(fullPath))
            }
        }

        return assembly
    }

    // Read identity from the same immutable bytes that will enter MetadataLoadContext. Asking
    // AssemblyName.GetAssemblyName on the original path here would reopen the file and reintroduce
    // the exact race this store closes.
    static func AssemblyNameFromImage(image: byte[]): AssemblyName {
        stream := new MemoryStream(image, false)
        pe := new PEReader(stream, PEStreamOptions.PrefetchMetadata)
        try {
            if !pe.HasMetadata {
                throw new BadImageFormatException("Reference image does not contain CLR metadata.")
            }

            reader := pe.GetMetadataReader()
            if !reader.IsAssembly {
                throw new BadImageFormatException("Reference image does not define an assembly.")
            }

            definition := reader.GetAssemblyDefinition()
            name := new AssemblyName(reader.GetString(definition.Name))
            name.Version = definition.Version
            definitionFlags := (int)definition.Flags
            name.Flags = (AssemblyNameFlags)definitionFlags
            if !definition.Culture.IsNil {
                name.CultureName = reader.GetString(definition.Culture)
            } else {
                name.CultureName = "neutral"
            }
            if (definitionFlags & 1) != 0 {
                name.SetPublicKey(reader.GetBlobBytes(definition.PublicKey))
            } else {
                name.SetPublicKeyToken(new byte[](0))
            }
            return name
        } finally {
            pe.Dispose()
        }
    }

    // Cache identity alongside the captured bytes, so both resolver selection and the scan consume
    // the same file version without reopening the original path.
    func AssemblyNameForPath(path: string): AssemblyName {
        fullPath := Path.GetFullPath(path)
        lock Gate {
            identity: AssemblyName? = null
            if assemblyNamesByPath.TryGetValue(fullPath, out identity) && identity != null {
                return identity
            }

            lastInvalidImage: BadImageFormatException? = null
            attempt := 0
            while attempt < 16 {
                try {
                    identity = ReferenceImageSnapshotStore.AssemblyNameFromImage(Capture(fullPath))
                    assemblyNamesByPath[fullPath] = identity
                    return identity
                } catch invalidImage: BadImageFormatException {
                    lastInvalidImage = invalidImage
                    imagesByPath.Remove(fullPath)
                    assemblyNamesByPath.Remove(fullPath)
                    Thread.Sleep(ReferenceImageSnapshotStore.RetryDelayMilliseconds(attempt))
                }

                attempt = attempt + 1
            }

            throw new BadImageFormatException("Reference image remained incomplete or invalid while it was being read: " + fullPath, lastInvalidImage)
        }
    }

    // A failed parse can have happened while a build was replacing the file. Drop the image so a
    // later resolution attempt can take a fresh snapshot.
    func Forget(path: string) {
        fullPath := Path.GetFullPath(path)
        lock Gate {
            imagesByPath.Remove(fullPath)
            assemblyNamesByPath.Remove(fullPath)
        }
    }

    // The backing path for metadata loaded through this owner, or the assembly's ordinary location
    // for runtime and other file-backed assemblies.
    static func OriginalPathOf(assembly: Assembly?): string? {
        if assembly == null {
            return null
        }

        origin: ReferenceImageSnapshotStore.AssemblyOrigin? = null
        lock ReferenceImageSnapshotStore.originsGate {
            if ReferenceImageSnapshotStore.origins.TryGetValue(assembly, out origin) && origin != null {
                return origin.Path
            }
        }

        try {
            return assembly.Location
        } catch {
            return null
        }
    }
}

// The standalone external scan gets the same copy-on-read guarantee as its path resolver. It keeps
// the original filename lookup, public-key-token preference, and highest-version choice while
// loading every selected image from owned bytes.
class ReferenceImagePathResolver: MetadataAssemblyResolver {
    private readonly pathsByFileName: Dictionary<string, List<string>>
    private readonly images: ReferenceImageSnapshotStore
    private readonly gate: object

    constructor(searchPaths: string[], snapshots: ReferenceImageSnapshotStore, loadGate: object) {
        pathsByFileName = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase)
        images = snapshots
        gate = loadGate

        for path in searchPaths {
            simpleName := Path.GetFileNameWithoutExtension(path)
            if simpleName == null || simpleName.Length == 0 {
                continue
            }

            candidates: List<string>? = null
            if !pathsByFileName.TryGetValue(simpleName, out candidates) || candidates == null {
                candidates = new List<string>()
                pathsByFileName[simpleName] = candidates
            }

            candidates.Add(path)
        }
    }

    override func Resolve(context: MetadataLoadContext, assemblyName: AssemblyName): Assembly? {
        simpleName := assemblyName.Name
        if simpleName == null {
            return null
        }

        lock gate {
            candidates: List<string>? = null
            if pathsByFileName.TryGetValue(simpleName, out candidates) && candidates != null {
                samePacketPath := ""
                ignoredPacketPath := ""
                samePacketVersion: Version? = null
                ignoredPacketVersion: Version? = null
                requestedPacket := assemblyName.GetPublicKeyToken() ?? new byte[](0)
                for path in candidates {
                    if !File.Exists(path) {
                        continue
                    }

                    try {
                        identity := images.AssemblyNameForPath(path)
                        if !AnalyzerMetadataLoadPolicy.IsSameSimpleName(identity.Name, simpleName) {
                            continue
                        }

                        imagePacket := identity.GetPublicKeyToken() ?? new byte[](0)
                        samePacket := ReferenceImagePathResolver.BytesEqual(requestedPacket, imagePacket)
                        version := identity.Version
                        if samePacket {
                            if samePacketPath.Length == 0 || ReferenceImagePathResolver.CompareVersion(version, samePacketVersion) > 0 {
                                samePacketPath = path
                                samePacketVersion = version
                            }
                        } else {
                            retargetable := ((int)assemblyName.Flags & (int)AssemblyNameFlags.Retargetable) != 0
                            if (samePacketPath.Length == 0 && requestedPacket.Length == 0) || retargetable {
                                if ignoredPacketPath.Length == 0 || ReferenceImagePathResolver.CompareVersion(version, ignoredPacketVersion) > 0 {
                                    ignoredPacketPath = path
                                    ignoredPacketVersion = version
                                }
                            }
                        }
                    } catch {
                        images.Forget(path)
                    }
                }

                selectedPath := samePacketPath.Length > 0 ? samePacketPath : ignoredPacketPath
                if selectedPath.Length > 0 {
                    fullSelectedPath := Path.GetFullPath(selectedPath)
                    for loaded in context.GetAssemblies() {
                        loadedPath := ReferenceImageSnapshotStore.OriginalPathOf(loaded)
                        if loadedPath != null && string.Equals(Path.GetFullPath(loadedPath), fullSelectedPath, StringComparison.Ordinal) {
                            return loaded
                        }
                    }

                    try {
                        return images.LoadFromPath(context, selectedPath)
                    } catch {
                        images.Forget(selectedPath)
                    }
                }
            }
        }

        return null
    }

    private static func BytesEqual(left: byte[], right: byte[]): bool {
        if left.Length != right.Length {
            return false
        }

        index := 0
        while index < left.Length {
            if left[index] != right[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    private static func CompareVersion(left: Version?, right: Version?): int {
        if left == null {
            return right == null ? 0 : -1
        }
        if right == null {
            return 1
        }

        return left.CompareTo(right)
    }
}

// Keep MetadataLoadContext construction beside its compiler owned resolver implementation. The
// Model project consumes this factory so the backend only sees one ordinary Core method call; the
// resolver's runtime API boundary remains implemented and checked here.
class ReferenceImageMetadataContext {
    static func Create(paths: string[], images: ReferenceImageSnapshotStore, gate: object): MetadataLoadContext {
        resolver: MetadataAssemblyResolver = new ReferenceImagePathResolver(paths, images, gate)
        context := new MetadataLoadContext(resolver, "System.Runtime")
        return context
    }
}
