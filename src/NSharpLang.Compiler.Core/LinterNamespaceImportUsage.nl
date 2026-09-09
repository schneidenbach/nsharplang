namespace NSharpLang.Compiler

import System.Collections.Generic


// NL010 asks one question of every import: does anything in this file use it? The FILE arm is
// `LinterFileImportUsage`; this is the NAMESPACE arm, and the two together are the whole rule.
//
// The answer is a table lookup, not an analysis. A namespace the table does not name is reported
// USED — unknown is not the same as unused, and NL010 would rather stay quiet than be wrong about
// a namespace it has never heard of. A namespace the table DOES name is used when any type it
// provides appears among the file's code identifiers, or when any extension/static method it
// provides appears among the file's member-access names (`.Select()`, `.Where()`).
//
// Every name below is asked for MEMBERSHIP and never for order, so the halves are arrays rather
// than sets: an array literal per namespace is the table, and a namespace with no row answers with
// an empty one. An empty answer from BOTH halves is exactly "this namespace is not in the table".
class LinterNamespaceImportUsage {
    static func IsUsed(namespaceName: string, codeIdentifiers: HashSet<string>, memberAccessNames: HashSet<string>): bool {
        knownTypes := KnownTypeNames(namespaceName)
        knownMembers := KnownMemberNames(namespaceName)
        if knownTypes.Length == 0 && knownMembers.Length == 0 {
            return true
        }

        if ContainsAny(codeIdentifiers, knownTypes) {
            return true
        }

        return ContainsAny(memberAccessNames, knownMembers)
    }

    static func ContainsAny(names: HashSet<string>, candidates: string[]): bool {
        index := 0
        while index < candidates.Length {
            if names.Contains(candidates[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The type half of the table: which namespace declares a name a file might write as a type.
    static func KnownTypeNames(namespaceName: string): string[] {
        if namespaceName == "System.Collections.Generic" {
            return CollectionsGenericTypeNames()
        }

        if namespaceName == "System.Text" {
            return TextTypeNames()
        }

        if namespaceName == "System.Text.RegularExpressions" {
            return RegularExpressionsTypeNames()
        }

        if namespaceName == "System.IO" {
            return IoTypeNames()
        }

        if namespaceName == "System.Net.Http" {
            return NetHttpTypeNames()
        }

        if namespaceName == "System.Text.Json" {
            return TextJsonTypeNames()
        }

        if namespaceName == "System.Threading.Tasks" {
            return ThreadingTasksTypeNames()
        }

        if namespaceName == "System.Threading" {
            return ThreadingTypeNames()
        }

        if namespaceName == "System" {
            return SystemTypeNames()
        }

        if namespaceName == "System.Linq" {
            return LinqTypeNames()
        }

        return NoNames()
    }

    // The member half: which namespace provides an extension or static method a file might CALL.
    // Only `System.Linq` earns a row — the import that is used without its types ever being named.
    static func KnownMemberNames(namespaceName: string): string[] {
        if namespaceName == "System.Linq" {
            return LinqMemberNames()
        }

        return NoNames()
    }

    static func NoNames(): string[] {
        return new string[](0)
    }

    static func CollectionsGenericTypeNames(): string[] {
        return ["List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "SortedDictionary", "SortedList", "SortedSet", "KeyValuePair", "IEnumerable", "IList", "ICollection", "IDictionary", "ISet", "IReadOnlyList", "IReadOnlyCollection", "IReadOnlyDictionary", "IAsyncEnumerable", "IEnumerator", "IComparer", "IEqualityComparer"]
    }

    static func TextTypeNames(): string[] {
        return ["StringBuilder", "Encoding"]
    }

    static func RegularExpressionsTypeNames(): string[] {
        return ["Regex", "Match", "MatchCollection"]
    }

    static func IoTypeNames(): string[] {
        return ["File", "Directory", "Path", "Stream", "StreamReader", "StreamWriter", "FileStream", "MemoryStream", "BinaryReader", "BinaryWriter", "FileInfo", "DirectoryInfo", "TextReader", "TextWriter"]
    }

    static func NetHttpTypeNames(): string[] {
        return ["HttpClient", "HttpResponseMessage", "HttpRequestMessage", "HttpContent", "StringContent"]
    }

    static func TextJsonTypeNames(): string[] {
        return ["JsonSerializer", "JsonSerializerOptions", "JsonNamingPolicy", "JsonElement", "JsonDocument", "JsonNode", "JsonValueKind"]
    }

    static func ThreadingTasksTypeNames(): string[] {
        return ["Task", "ValueTask", "TaskCompletionSource"]
    }

    static func ThreadingTypeNames(): string[] {
        return ["CancellationToken", "CancellationTokenSource", "SemaphoreSlim", "Mutex", "Timer", "Thread"]
    }

    static func SystemTypeNames(): string[] {
        return ["DateTime", "DateTimeOffset", "TimeSpan", "Guid", "Uri", "Tuple", "Lazy", "Action", "Func", "Console", "Math", "Char", "Exception", "ArgumentException", "ArgumentNullException", "ArgumentOutOfRangeException", "InvalidOperationException", "NotSupportedException", "NotImplementedException", "FormatException", "OverflowException", "Random", "Convert", "Array", "Type", "Attribute", "Environment", "Int32", "String", "IDisposable", "IComparable", "IEquatable", "EventHandler", "Nullable", "Span", "Memory", "ReadOnlySpan", "ReadOnlyMemory", "StringComparison", "StringComparer", "ValueTuple", "Version", "Index"]
    }

    static func LinqTypeNames(): string[] {
        return ["Enumerable", "Queryable", "IQueryable", "IOrderedEnumerable", "IGrouping", "ILookup", "Lookup"]
    }

    static func LinqMemberNames(): string[] {
        return ["Select", "SelectMany", "Where", "OrderBy", "OrderByDescending", "ThenBy", "ThenByDescending", "GroupBy", "GroupJoin", "Join", "Distinct", "DistinctBy", "Union", "UnionBy", "Intersect", "IntersectBy", "Except", "ExceptBy", "Skip", "SkipWhile", "Take", "TakeWhile", "First", "FirstOrDefault", "Last", "LastOrDefault", "Single", "SingleOrDefault", "ElementAt", "ElementAtOrDefault", "Count", "LongCount", "Sum", "Min", "MinBy", "Max", "MaxBy", "Average", "Aggregate", "Any", "All", "Contains", "ToList", "ToArray", "ToDictionary", "ToHashSet", "ToLookup", "Zip", "Concat", "Append", "Prepend", "Reverse", "SequenceEqual", "DefaultIfEmpty", "OfType", "Cast", "AsEnumerable", "Chunk", "SkipLast", "TakeLast", "TryGetNonEnumeratedCount", "CountBy", "AggregateBy", "Index", "Order", "OrderDescending"]
    }
}
