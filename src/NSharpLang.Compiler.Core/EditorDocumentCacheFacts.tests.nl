namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class EditorDocumentCacheFixture {
    static func Rows(pairs: string[], ticks: long[]): List<EditorDocumentCacheRow> {
        rows := new List<EditorDocumentCacheRow>()
        index := 0
        while index < pairs.Length {
            rows.Add(new EditorDocumentCacheRow(pairs[index], ticks[index]))
            index = index + 1
        }

        return rows
    }
}

test "the buffer ceiling is the shipped hundred" {
    assert EditorDocumentCacheFacts.MaxDocuments() == 100
}

test "a cache below the ceiling never evicts" {
    assert !EditorDocumentCacheFacts.ShouldEvictBefore(0, false)
    assert !EditorDocumentCacheFacts.ShouldEvictBefore(99, false)
}

test "a full cache evicts for a buffer it is not already tracking" {
    assert EditorDocumentCacheFacts.ShouldEvictBefore(100, false)
    assert EditorDocumentCacheFacts.ShouldEvictBefore(101, false)
}

// THE HALF THAT IS EASY TO LOSE: replacing a tracked buffer is not adding one, so a full cache
// gives nothing up for it. Without this, every keystroke in the hundredth open file would evict.
test "a full cache evicts NOTHING for a buffer it already tracks" {
    assert !EditorDocumentCacheFacts.ShouldEvictBefore(100, true)
    assert !EditorDocumentCacheFacts.ShouldEvictBefore(1000, true)
}

test "the least recently accessed buffer is the one that goes" {
    uris: string[] = ["file:///a.nl", "file:///b.nl", "file:///c.nl"]
    ticks: long[] = [300, 100, 200]
    rows := EditorDocumentCacheFixture.Rows(uris, ticks)

    assert EditorDocumentCacheFacts.EvictionIndex(rows) == 1
    evicted := EditorDocumentCacheFacts.EvictionUri(rows)
    assert evicted == "file:///b.nl"
}

// THE SHIPPED TIE RULE. `OrderBy` is stable and the C# took `FirstOrDefault()`, so the FIRST row
// carrying the lowest tick is the one that went. A later equal row must not displace it.
test "a tie keeps the first row, which is what the stable sort shipped" {
    uris: string[] = ["file:///first.nl", "file:///second.nl"]
    ticks: long[] = [100, 100]
    rows := EditorDocumentCacheFixture.Rows(uris, ticks)

    assert EditorDocumentCacheFacts.EvictionIndex(rows) == 0
    evicted := EditorDocumentCacheFacts.EvictionUri(rows)
    assert evicted == "file:///first.nl"
}

test "an empty cache has nothing to evict" {
    rows := new List<EditorDocumentCacheRow>()

    assert EditorDocumentCacheFacts.EvictionIndex(rows) == -1
    assert EditorDocumentCacheFacts.EvictionUri(rows) == null
}

test "a single tracked buffer is its own eviction candidate" {
    uris: string[] = ["file:///only.nl"]
    ticks: long[] = [7]
    rows := EditorDocumentCacheFixture.Rows(uris, ticks)

    assert EditorDocumentCacheFacts.EvictionIndex(rows) == 0
}

test "a cached snapshot answers only for the stamp it was built at" {
    assert EditorDocumentCacheFacts.SnapshotCacheHit("stamp-1", "stamp-1")
    assert !EditorDocumentCacheFacts.SnapshotCacheHit("stamp-1", "stamp-2")
}

// NOTHING CACHED AND CACHED-BUT-STALE ARE ONE ANSWER, so the caller has one branch and cannot
// accidentally treat a missing entry as a hit.
test "a missing cache entry or an unstampable project is never a hit" {
    assert !EditorDocumentCacheFacts.SnapshotCacheHit(null, "stamp-1")
    assert !EditorDocumentCacheFacts.SnapshotCacheHit("stamp-1", null)
    assert !EditorDocumentCacheFacts.SnapshotCacheHit(null, null)
}
