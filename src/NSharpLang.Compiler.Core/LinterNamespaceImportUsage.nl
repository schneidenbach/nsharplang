namespace NSharpLang.Compiler

import System
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

        if ContainsAnyType(codeIdentifiers, knownTypes) {
            return true
        }

        return ContainsAny(memberAccessNames, knownMembers)
    }

    // AN ATTRIBUTE TYPE HAS TWO LEGAL SPELLINGS and a file may write either: `[Obsolete]` and
    // `typeof(ObsoleteAttribute)` name the same type, and the second is the only spelling that works
    // outside attribute position. The type half therefore asks for the written name AND its
    // `Attribute`-suffixed form, so the row that names `Obsolete` answers for both. The member half
    // does not: a method name has one spelling.
    static func ContainsAnyType(names: HashSet<string>, candidates: string[]): bool {
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if names.Contains(candidate) || names.Contains(candidate + "Attribute") {
                return true
            }

            index = index + 1
        }

        return false
    }

    // AN ALIASED IMPORT IS USED WHEN ITS ALIAS IS WRITTEN, and it is the ONLY spelling that can use
    // it: an alias-qualified reference never writes one of the namespace's own type names, so the
    // known-name tables above cannot answer for one and every aliased import was reported unused.
    //
    // THE ALIAS APPEARS IN TWO SHAPES and both count. In expression position `Txt.Encoding` records
    // the receiver identifier `Txt`; at a type position `new Txt.StringBuilder()` records the WHOLE
    // dotted spelling `Txt.StringBuilder`, because a type reference is collected by its written name.
    // So a bare match answers the first and a dotted-root match answers the second.
    static func IsAliasUsed(aliasName: string, codeIdentifiers: HashSet<string>, memberAccessNames: HashSet<string>): bool {
        if aliasName == null || aliasName.Length == 0 {
            return false
        }

        if codeIdentifiers.Contains(aliasName) || memberAccessNames.Contains(aliasName) {
            return true
        }

        return HasDottedRoot(codeIdentifiers, aliasName) || HasDottedRoot(memberAccessNames, aliasName)
    }

    static func HasDottedRoot(names: HashSet<string>, rootName: string): bool {
        prefix := rootName + "."
        for name in names {
            if name.StartsWith(prefix, StringComparison.Ordinal) {
                return true
            }
        }

        return false
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
        return ["List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "SortedDictionary", "SortedList", "SortedSet", "KeyValuePair", "Comparer", "EqualityComparer", "IEnumerable", "IList", "ICollection", "IDictionary", "ISet", "IReadOnlyList", "IReadOnlyCollection", "IReadOnlyDictionary", "IAsyncEnumerable", "IEnumerator", "IComparer", "IEqualityComparer"]
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

    // The synchronisation primitives belong here as much as the handles do: a file whose only use of
    // `System.Threading` is `Interlocked.Exchange(...)` or `Monitor.Enter(...)` was told its import
    // was dead, and removing it on that advice broke the build.
    static func ThreadingTypeNames(): string[] {
        return ["CancellationToken", "CancellationTokenSource", "SemaphoreSlim", "Mutex", "Timer", "Thread", "Interlocked", "Monitor", "Volatile", "ThreadPool", "ThreadLocal", "ReaderWriterLockSlim", "ManualResetEvent", "ManualResetEventSlim", "AutoResetEvent", "EventWaitHandle", "WaitHandle", "SpinLock", "SpinWait", "Barrier", "CountdownEvent", "LazyInitializer"]
    }

    // THE ATTRIBUTE TYPES BELONG IN THIS ROW AS MUCH AS THE EXCEPTIONS DO, and for the same reason the
    // `System.Threading` row gives above: a file whose only use of `System` is `[Obsolete("…")]` or
    // `[Flags]` was told its import was dead, and removing it on that advice broke the build. An
    // attribute is asked for by BOTH spellings — `[Obsolete]` and `[ObsoleteAttribute]` name one type —
    // and `LinterWalkState.NoteAttributeName` records both, so only one spelling is listed here.
    //
    // A ROW IS A CLOSED-WORLD CLAIM, AND A GAP IN ONE IS A FALSE POSITIVE — not a missed report.
    // `IsUsed` reads a namespace WITH a row as "these are all the names it supplies", so a spelling
    // the row omits makes the import look dead, and NL010 is an ERROR whose `nlc fix` DELETES the
    // line. The census found exactly that: `import System` beside `func F(r: Range)` was reported
    // unused, because `Range` was missing here while its sibling `Index` was present. Every addition
    // below closes that kind of gap BY SIBLING — a spelling whose neighbours in this row are already
    // listed — rather than by taste: the numeric aliases beside `Int32`, the date/time-only types
    // beside `DateTime`, the async-disposable interface beside `IDisposable`, the common runtime
    // exceptions beside the argument ones, and `Range` beside `Index`.
    static func SystemTypeNames(): string[] {
        return ["DateTime", "DateTimeOffset", "DateOnly", "TimeOnly", "TimeSpan", "TimeProvider", "Guid", "HashCode", "Uri", "UriKind", "Tuple", "Lazy", "Action", "Func", "Console", "Math", "MathF", "Char", "Exception", "ArgumentException", "ArgumentNullException", "ArgumentOutOfRangeException", "InvalidOperationException", "NotSupportedException", "NotImplementedException", "FormatException", "OverflowException", "InvalidCastException", "IndexOutOfRangeException", "NullReferenceException", "DivideByZeroException", "ObjectDisposedException", "TimeoutException", "AggregateException", "ArithmeticException", "SystemException", "ApplicationException", "Random", "Convert", "Array", "ArraySegment", "Type", "Attribute", "Environment", "Activator", "BitConverter", "Buffer", "GC", "WeakReference", "Progress", "Boolean", "Byte", "SByte", "Int16", "UInt16", "Int32", "UInt32", "Int64", "UInt64", "Single", "Double", "Decimal", "Half", "IntPtr", "UIntPtr", "Enum", "ValueType", "Delegate", "MulticastDelegate", "String", "StringSplitOptions", "IDisposable", "IAsyncDisposable", "IComparable", "IEquatable", "IFormattable", "IFormatProvider", "IServiceProvider", "EventHandler", "EventArgs", "Predicate", "Comparison", "Converter", "Comparer", "AsyncCallback", "ConsoleCancelEventHandler", "ConsoleCancelEventArgs", "ConsoleColor", "ConsoleKey", "ConsoleKeyInfo", "Nullable", "Span", "Memory", "ReadOnlySpan", "ReadOnlyMemory", "StringComparison", "StringComparer", "ValueTuple", "Version", "Index", "Range", "Obsolete", "Flags", "Serializable", "NonSerialized", "AttributeUsage", "AttributeTargets", "CLSCompliant", "ThreadStatic", "STAThread", "MTAThread", "ParamArray"]
    }

    static func LinqTypeNames(): string[] {
        return ["Enumerable", "Queryable", "IQueryable", "IOrderedEnumerable", "IGrouping", "ILookup", "Lookup"]
    }

    static func LinqMemberNames(): string[] {
        return ["Select", "SelectMany", "Where", "OrderBy", "OrderByDescending", "ThenBy", "ThenByDescending", "GroupBy", "GroupJoin", "Join", "Distinct", "DistinctBy", "Union", "UnionBy", "Intersect", "IntersectBy", "Except", "ExceptBy", "Skip", "SkipWhile", "Take", "TakeWhile", "First", "FirstOrDefault", "Last", "LastOrDefault", "Single", "SingleOrDefault", "ElementAt", "ElementAtOrDefault", "Count", "LongCount", "Sum", "Min", "MinBy", "Max", "MaxBy", "Average", "Aggregate", "Any", "All", "Contains", "ToList", "ToArray", "ToDictionary", "ToHashSet", "ToLookup", "Zip", "Concat", "Append", "Prepend", "Reverse", "SequenceEqual", "DefaultIfEmpty", "OfType", "Cast", "AsEnumerable", "Chunk", "SkipLast", "TakeLast", "TryGetNonEnumeratedCount", "CountBy", "AggregateBy", "Index", "Order", "OrderDescending"]
    }
}
