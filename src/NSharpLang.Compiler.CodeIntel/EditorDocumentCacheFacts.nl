namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

// ONE TRACKED DOCUMENT'S CACHE ROW: which buffer it is and when the editor last touched it. The
// ticks are `DateTime.UtcNow.Ticks` at the caller, because only the caller knows when "now" is;
// everything decided from them is decided here.
class EditorDocumentCacheRow {
    uriValue: string
    lastAccessTicksValue: long

    Uri: string => uriValue
    LastAccessTicks: long => lastAccessTicksValue

    constructor(Uri: string, LastAccessTicks: long) {
        uriValue = Uri
        lastAccessTicksValue = LastAccessTicks
    }
}

// HOW MANY BUFFERS THE EDITOR KEEPS, WHICH ONE GOES WHEN IT IS FULL, AND WHEN A CACHED PROJECT
// SNAPSHOT MAY BE REUSED.
//
// These are three decisions the language server's `DocumentManager` used to make inline, where no
// test could reach them: a magic `100`, a `_documents.Count >= MaxDocuments && !ContainsKey(uri)`
// guard whose second half is the whole reason reopening a tracked file never evicts anything, an
// `OrderBy(kvp => kvp.Value).FirstOrDefault()` whose tie-breaking nobody had written down, and a
// stamp equality that decides whether a keystroke re-analyses a whole project.
//
// NONE OF IT IS ABOUT THE PROTOCOL. What stays on the editor's side is the dictionaries themselves
// and the mutation; what comes here is every question asked of them.
class EditorDocumentCacheFacts {

    // THE CEILING. A hundred buffers is what this server has always kept, and the number is a
    // product decision rather than an implementation detail, so it is stated once and read.
    static func MaxDocuments(): int {
        return 100
    }

    // WHETHER UPDATING `uri` HAS TO EVICT SOMETHING FIRST.
    //
    // The second half of the guard is load-bearing and easy to lose: a document ALREADY tracked is
    // being replaced, not added, so a full cache does not have to give anything up for it. Without
    // that, editing the hundredth open file would evict a buffer on every keystroke.
    static func ShouldEvictBefore(trackedCount: int, isAlreadyTracked: bool): bool {
        if isAlreadyTracked {
            return false
        }

        return trackedCount >= MaxDocuments()
    }

    // WHICH BUFFER IS THE LEAST RECENTLY ACCESSED ONE, as an INDEX into the caller's rows, or -1
    // when there is nothing to evict.
    //
    // THE TIE RULE IS THE SHIPPED ONE AND IS PINNED DELIBERATELY. `OrderBy` is a stable sort and
    // the C# took `FirstOrDefault()` of it, so when two buffers carry the same tick the one the
    // dictionary yielded FIRST is the one that went. Strictly-less-than keeps that: a later row
    // equal to the best does not displace it.
    static func EvictionIndex(rows: List<EditorDocumentCacheRow>): int {
        best := -1
        bestTicks: long = 0

        index := 0
        while index < rows.Count {
            ticks := rows[index].LastAccessTicks
            if best < 0 || ticks < bestTicks {
                best = index
                bestTicks = ticks
            }

            index = index + 1
        }

        return best
    }

    // THE URI THAT GOES, or null when the cache is empty. A convenience over `EvictionIndex` for
    // the caller that only wants the key, spelled here so the two cannot disagree about the tie.
    static func EvictionUri(rows: List<EditorDocumentCacheRow>): string? {
        index := EvictionIndex(rows)
        if index < 0 {
            return null
        }

        return rows[index].Uri
    }

    // WHETHER A CACHED PROJECT SNAPSHOT STILL ANSWERS FOR THIS STAMP.
    //
    // A missing cache entry is spelled as a null stamp by the caller, so "nothing cached" and
    // "cached but stale" are one question with one answer, and the caller has one branch.
    // `EditorWorkspaceFacts.ProjectSnapshotStamp` is what produces both sides.
    static func SnapshotCacheHit(cachedStamp: string?, currentStamp: string?): bool {
        if cachedStamp == null || currentStamp == null {
            return false
        }

        return cachedStamp == currentStamp
    }
}
