namespace NSharpLang.Compiler

import System
import System.Security.Cryptography

// THE TWO FIELDS A PE IMAGE CARRIES THAT ARE NOT ABOUT THE PROGRAM.
//
// `ManagedPEBuilder` is handed no `deterministicIdProvider`, so `PEBuilder` falls back to the
// time-based one: the COFF header's `TimeDateStamp` becomes the second the build happened, and
// `PersistedAssemblyBuilder` stamps the module row's MVID with a fresh `Guid`. Two builds of one
// unchanged source therefore differ in twenty bytes and in nothing else — which is enough to make
// the seed irreproducible, to defeat `CopyRefAssembly`'s MVID comparison (the whole mechanism that
// makes `ProduceReferenceAssembly` worth having), and to force every IL-identity check in the tree
// to mask the module version id before it can compare anything.
//
// The repair is the one Roslyn's `/deterministic` makes: DERIVE both fields from the image's own
// content. The image is written once, the two fields are zeroed, the zeroed image is hashed, and
// the hash supplies the MVID and the timestamp. Identical input therefore produces identical
// output, byte for byte, and a changed program changes the MVID exactly when it changes a byte.
//
// This is a BYTE pass over a serialized image rather than a metadata rewrite, deliberately: the
// MVID lives in the `#GUID` heap, which `MetadataBuilder` links into the image on `Serialize` and
// will not let a caller re-open (`ColumnarModifiedMemberReferenceRepair` records that limit), and
// the timestamp is written by `PEBuilder` after every stream is already laid out. Both fields sit
// at fixed, computable offsets in the finished image, and nothing else in the file depends on them:
// the PE checksum is written as zero by both writers this tree uses, and neither writer emits a
// debug directory whose CodeView entry would carry a second copy of the id.
class ColumnarDeterministicPeIdentity {

    // The PE checksum is zero in everything this compiler and Cecil write; it is zeroed before the
    // hash anyway so that an image which DOES carry one still hashes to the same value.
    static func Apply(image: byte[]): bool {
        if image == null {
            return false
        }
        if image.Length < 64 {
            return false
        }

        peHeaderOffset := ReadInt32(image, 60)
        if peHeaderOffset <= 0 {
            return false
        }
        if peHeaderOffset + 24 > image.Length {
            return false
        }
        if ByteAt(image, peHeaderOffset) != 80 {
            return false
        }
        if ByteAt(image, peHeaderOffset + 1) != 69 {
            return false
        }
        if ByteAt(image, peHeaderOffset + 2) != 0 {
            return false
        }
        if ByteAt(image, peHeaderOffset + 3) != 0 {
            return false
        }

        coffOffset := peHeaderOffset + 4
        sectionCount := ReadUInt16(image, coffOffset + 2)
        timestampOffset := coffOffset + 4
        optionalHeaderSize := ReadUInt16(image, coffOffset + 16)
        optionalHeaderOffset := coffOffset + 20
        if optionalHeaderOffset + optionalHeaderSize > image.Length {
            return false
        }
        if optionalHeaderSize < 96 {
            return false
        }

        magic := ReadUInt16(image, optionalHeaderOffset)
        checksumOffset := optionalHeaderOffset + 64
        dataDirectoryOffset := optionalHeaderOffset + 96
        if magic == 523 {
            dataDirectoryOffset = optionalHeaderOffset + 112
        }

        // Data directory 14 is the CLI header; an image without one is not a managed assembly.
        cliDirectoryOffset := dataDirectoryOffset + 112
        if cliDirectoryOffset + 8 > image.Length {
            return false
        }
        cliRva := ReadInt32(image, cliDirectoryOffset)
        if cliRva <= 0 {
            return false
        }

        sectionTableOffset := optionalHeaderOffset + optionalHeaderSize
        cliOffset := ResolveRva(image, sectionTableOffset, sectionCount, cliRva)
        if cliOffset < 0 {
            return false
        }
        if cliOffset + 16 > image.Length {
            return false
        }

        metadataRva := ReadInt32(image, cliOffset + 8)
        if metadataRva <= 0 {
            return false
        }
        metadataOffset := ResolveRva(image, sectionTableOffset, sectionCount, metadataRva)
        if metadataOffset < 0 {
            return false
        }
        if metadataOffset + 20 > image.Length {
            return false
        }

        // "BSJB"
        if ByteAt(image, metadataOffset) != 66 {
            return false
        }
        if ByteAt(image, metadataOffset + 1) != 83 {
            return false
        }
        if ByteAt(image, metadataOffset + 2) != 74 {
            return false
        }
        if ByteAt(image, metadataOffset + 3) != 66 {
            return false
        }

        versionLength := ReadInt32(image, metadataOffset + 12)
        if versionLength < 0 {
            return false
        }
        if versionLength > image.Length {
            return false
        }
        streamCountOffset := metadataOffset + 16 + versionLength + 2
        if streamCountOffset + 2 > image.Length {
            return false
        }
        streamCount := ReadUInt16(image, streamCountOffset)
        cursor := streamCountOffset + 2

        guidHeapOffset := -1
        streamIndex := 0
        while streamIndex < streamCount {
            if cursor + 8 > image.Length {
                return false
            }
            streamOffset := ReadInt32(image, cursor)
            nameStart := cursor + 8
            nameEnd := nameStart
            while nameEnd < image.Length {
                if ByteAt(image, nameEnd) == 0 {
                    break
                }
                nameEnd = nameEnd + 1
            }
            if nameEnd >= image.Length {
                return false
            }
            if IsGuidHeapName(image, nameStart, nameEnd - nameStart) {
                guidHeapOffset = metadataOffset + streamOffset
            }
            nameSize := nameEnd - nameStart + 1
            cursor = nameStart + PadToFour(nameSize)
            streamIndex = streamIndex + 1
        }

        if guidHeapOffset < 0 {
            return false
        }
        if guidHeapOffset + 16 > image.Length {
            return false
        }

        // THE ZEROING IS PART OF THE DEFINITION, not a convenience: the hash must not depend on the
        // two fields it is about to write, or the pass would not be idempotent and a second run
        // over its own output would produce a third image.
        WriteInt32(image, timestampOffset, 0)
        WriteInt32(image, checksumOffset, 0)
        guidByte := 0
        while guidByte < 16 {
            image[guidHeapOffset + guidByte] = Convert.ToByte(0)
            guidByte = guidByte + 1
        }

        hash := ComputeSha256(image)
        if hash.Length < 20 {
            return false
        }

        copied := 0
        while copied < 16 {
            image[guidHeapOffset + copied] = hash[copied]
            copied = copied + 1
        }
        // RFC 4122 version 4 and the IETF variant, exactly as `BlobContentId.FromHash` sets them,
        // so an N# module version id is a well-formed GUID and not merely sixteen hash bytes.
        versionByte := ByteAt(image, guidHeapOffset + 7)
        image[guidHeapOffset + 7] = Convert.ToByte((versionByte % 16) + 64)
        variantByte := ByteAt(image, guidHeapOffset + 8)
        image[guidHeapOffset + 8] = Convert.ToByte((variantByte % 64) + 128)

        // The timestamp's high bit is set for the same reason Roslyn sets it: a deterministic stamp
        // is not a date, and a tool that reads one must be able to tell.
        image[timestampOffset] = hash[16]
        image[timestampOffset + 1] = hash[17]
        image[timestampOffset + 2] = hash[18]
        image[timestampOffset + 3] = Convert.ToByte((ByteValue(hash, 19) % 128) + 128)
        return true
    }

    private static func ComputeSha256(content: byte[]): byte[] {
        algorithm := SHA256.Create()
        try {
            return algorithm.ComputeHash(content)
        } finally {
            algorithm.Dispose()
        }
    }

    // "#GUID", compared without materializing a string: this runs once per emitted image and the
    // heap names are fixed five-byte ASCII.
    private static func IsGuidHeapName(image: byte[], start: int, length: int): bool {
        if length != 5 {
            return false
        }
        if ByteAt(image, start) != 35 {
            return false
        }
        if ByteAt(image, start + 1) != 71 {
            return false
        }
        if ByteAt(image, start + 2) != 85 {
            return false
        }
        if ByteAt(image, start + 3) != 73 {
            return false
        }
        return ByteAt(image, start + 4) == 68
    }

    private static func PadToFour(value: int): int {
        remainder := value % 4
        if remainder == 0 {
            return value
        }
        return value + (4 - remainder)
    }

    // A section header is 40 bytes: the virtual size is at +8, the virtual address at +12, the raw
    // size at +16 and the raw pointer at +20.
    private static func ResolveRva(image: byte[], sectionTableOffset: int, sectionCount: int, rva: int): int {
        index := 0
        while index < sectionCount {
            headerOffset := sectionTableOffset + (index * 40)
            if headerOffset + 40 > image.Length {
                return -1
            }
            virtualAddress := ReadInt32(image, headerOffset + 12)
            virtualSize := ReadInt32(image, headerOffset + 8)
            rawSize := ReadInt32(image, headerOffset + 16)
            rawPointer := ReadInt32(image, headerOffset + 20)
            span := virtualSize
            if rawSize > span {
                span = rawSize
            }
            if rva >= virtualAddress {
                if rva < virtualAddress + span {
                    return rawPointer + (rva - virtualAddress)
                }
            }
            index = index + 1
        }
        return -1
    }

    private static func ByteAt(image: byte[], index: int): int {
        return ByteValue(image, index)
    }

    private static func ByteValue(content: byte[], index: int): int {
        return Convert.ToInt32(content[index])
    }

    private static func ReadUInt16(image: byte[], offset: int): int {
        return ByteValue(image, offset) + (ByteValue(image, offset + 1) * 256)
    }

    private static func ReadInt32(image: byte[], offset: int): int {
        low := ReadUInt16(image, offset)
        high := ReadUInt16(image, offset + 2)
        if high >= 32768 {
            return -1
        }
        return low + (high * 65536)
    }

    private static func WriteInt32(image: byte[], offset: int, value: int) {
        remaining := value
        position := 0
        while position < 4 {
            image[offset + position] = Convert.ToByte(remaining % 256)
            remaining = remaining / 256
            position = position + 1
        }
    }
}
