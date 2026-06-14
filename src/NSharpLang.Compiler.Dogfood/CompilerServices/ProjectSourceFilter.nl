// Project source-file filtering kernel.
//
// Mirrors ProjectConfig.GetSourceFiles' post-enumeration filtering: drop *.tests.nl when
// !includeTests, then drop files whose project-relative path matches any exclude glob.
//
// The C# baseline allocates 2-3 intermediate arrays (two .Where(...).ToArray() passes) and
// recompiles a regex per (file, pattern) pair. This kernel classifies every relative path in a
// single pass and writes kept indices into a caller-owned int[] (stable indexes, no string
// materialization across the boundary).

// Single pass: for each relative path, keep it unless it is a test file (when tests excluded) or it
// matches an exclude pattern. Kept original indices are written, in order, into resultIndices.
// Returns the count of kept files.
//
// excludePatterns are the raw exclude globs (project.yml order preserved). includeTests != 0 keeps
// *.tests.nl files. relativePaths are project-relative paths (already what Path.GetRelativePath
// yields); they may contain '\' or '/' separators - both are normalized to '/' during matching.

struct ProjectSourcePathTable {
    RelativePaths: string[]
}

struct ProjectSourceExcludePatternTable {
    Patterns: string[]
}

struct ProjectSourceFilterResultTable {
    Indices: int[]
}

func ProjectSourceFilterKeptIndicesInto(
    relativePaths: string[],
    excludePatterns: string[],
    includeTests: int,
    resultIndices: int[]): int {
    paths := new ProjectSourcePathTable { RelativePaths: relativePaths }
    patterns := new ProjectSourceExcludePatternTable { Patterns: excludePatterns }
    result := new ProjectSourceFilterResultTable { Indices: resultIndices }
    return ProjectSourceFilterKeptIndicesCore(ref paths, ref patterns, includeTests, ref result)
}

func ProjectSourceFilterKeptIndicesCore(
    paths: &ProjectSourcePathTable,
    patterns: &ProjectSourceExcludePatternTable,
    includeTests: int,
    result: &ProjectSourceFilterResultTable): int {
    resultCount := 0
    i := 0
    while i < paths.RelativePaths.Length {
        path := paths.RelativePaths[i]
        keep := true

        if includeTests == 0 && ProjectSourceFilterIsTestFile(path) {
            keep = false
        }

        if keep && ProjectSourceFilterIsExcludedCore(path, ref patterns) {
            keep = false
        }

        if keep {
            if resultCount < result.Indices.Length {
                result.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

// Matches the C# `f.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase)` guard.
func ProjectSourceFilterIsTestFile(path: string): bool {
    suffixLength := 9
    if path.Length < suffixLength {
        return false
    }

    start := path.Length - suffixLength
    return ProjectSourceFilterCharEqualsIgnoreCase(path[start], '.')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 1], 't')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 2], 'e')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 3], 's')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 4], 't')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 5], 's')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 6], '.')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 7], 'n')
        && ProjectSourceFilterCharEqualsIgnoreCase(path[start + 8], 'l')
}

func ProjectSourceFilterIsExcludedCore(path: string, patterns: &ProjectSourceExcludePatternTable): bool {
    j := 0
    while j < patterns.Patterns.Length {
        if ProjectSourceFilterMatchesPattern(path, patterns.Patterns[j]) {
            return true
        }

        j = j + 1
    }

    return false
}

// Anchored glob match equivalent to the C# regex built in MatchesPattern. Both path and pattern are
// slash-normalized. Supported metacharacters (in the C# replacement order):
//   "**/" => match any number of directories (lazy ".*?/")
//   "**"  => match anything (".*")
//   "*"   => match anything except '/' ("[^/]*")
//   "?"   => match a single character (".")
// Every other character is a case-sensitive literal (C# regex has no IgnoreCase flag here).
func ProjectSourceFilterMatchesPattern(path: string, pattern: string): bool {
    return ProjectSourceFilterMatchFrom(path, 0, pattern, 0)
}

// Backtracking matcher. pathIndex/patternIndex walk the slash-normalized inputs in lockstep.
func ProjectSourceFilterMatchFrom(
    path: string,
    pathIndex: int,
    pattern: string,
    patternIndex: int): bool {
    pi := pathIndex
    qi := patternIndex

    while qi < pattern.Length {
        pc := ProjectSourceFilterNormalizeSlash(pattern[qi])

        if pc == '*' {
            // Determine whether this is "**" (possibly followed by '/') or a single "*".
            isDouble := qi + 1 < pattern.Length
                && ProjectSourceFilterNormalizeSlash(pattern[qi + 1]) == '*'

            if isDouble {
                afterStars := qi + 2
                // "**/" is lazy in the C# regex (".*?/"): ".*?" consumes any characters and the
                // trailing '/' is literal, so the tail must resume immediately after some '/' at or
                // after pi. Lazy order = nearest qualifying slash first. Scan forward; each time a
                // '/' is crossed, retry the remaining pattern just past it.
                if afterStars < pattern.Length
                    && ProjectSourceFilterNormalizeSlash(pattern[afterStars]) == '/' {
                    nextPattern := afterStars + 1
                    scan := pi
                    while scan < path.Length {
                        crossedSlash := ProjectSourceFilterNormalizeSlash(path[scan]) == '/'
                        scan = scan + 1
                        if crossedSlash {
                            if ProjectSourceFilterMatchFrom(path, scan, pattern, nextPattern) {
                                return true
                            }
                        }
                    }

                    return false
                }

                // Bare "**" => ".*": greedily try the longest remaining tail first, backtracking.
                nextPattern := afterStars
                k := path.Length
                while k >= pi {
                    if ProjectSourceFilterMatchFrom(path, k, pattern, nextPattern) {
                        return true
                    }

                    k = k - 1
                }

                return false
            }

            // Single "*" => "[^/]*": match zero or more non-slash characters, greedily with
            // backtracking. Find the furthest non-slash extent, then retreat.
            limit := pi
            while limit < path.Length && ProjectSourceFilterNormalizeSlash(path[limit]) != '/' {
                limit = limit + 1
            }

            nextPattern := qi + 1
            k := limit
            while k >= pi {
                if ProjectSourceFilterMatchFrom(path, k, pattern, nextPattern) {
                    return true
                }

                k = k - 1
            }

            return false
        }

        if pc == '?' {
            // "." in regex matches any single character except newline; paths never contain '\n'.
            if pi >= path.Length {
                return false
            }

            pi = pi + 1
            qi = qi + 1
            continue
        }

        // Literal character (case-sensitive).
        if pi >= path.Length {
            return false
        }

        if ProjectSourceFilterNormalizeSlash(path[pi]) != pc {
            return false
        }

        pi = pi + 1
        qi = qi + 1
    }

    // Anchored '$': the whole path must be consumed.
    return pi == path.Length
}

func ProjectSourceFilterNormalizeSlash(ch: char): char {
    if ch == '\\' {
        return '/'
    }

    return ch
}

func ProjectSourceFilterCharEqualsIgnoreCase(left: char, right: char): bool {
    if left == right {
        return true
    }

    if left >= 'A' && left <= 'Z' && right >= 'a' && right <= 'z' {
        return left - 'A' == right - 'a'
    }

    if left >= 'a' && left <= 'z' && right >= 'A' && right <= 'Z' {
        return left - 'a' == right - 'A'
    }

    return Char.ToUpperInvariant(left) == Char.ToUpperInvariant(right)
}
