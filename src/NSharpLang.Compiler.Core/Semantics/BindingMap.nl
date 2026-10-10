namespace NSharpLang.Compiler

import System.Collections.Concurrent
import System.Collections.Generic

class SymbolDeclaration {
    nameValue: string
    fileValue: string?
    lineValue: int
    columnValue: int
    kindValue: string

    Name: string => nameValue
    File: string? => fileValue
    Line: int => lineValue
    Column: int => columnValue
    Kind: string => kindValue

    constructor(Name: string, File: string?, Line: int, Column: int, Kind: string) {
        nameValue = Name
        fileValue = File
        lineValue = Line
        columnValue = Column
        kindValue = Kind
    }

    override func Equals(value: object): bool {
        other := value as SymbolDeclaration
        if other == null {
            return false
        }

        return nameValue == other.Name && fileValue == other.File && lineValue == other.Line && columnValue == other.Column && kindValue == other.Kind
    }

    override func GetHashCode(): int {
        hash := 17
        if nameValue != null {
            hash = hash * 23 + nameValue.GetHashCode()
        }
        if fileValue != null {
            hash = hash * 23 + fileValue.GetHashCode()
        }
        hash = hash * 23 + lineValue
        hash = hash * 23 + columnValue
        if kindValue != null {
            hash = hash * 23 + kindValue.GetHashCode()
        }
        return hash
    }

    override func ToString(): string {
        fileText := fileValue
        if fileText == null {
            fileText = ""
        }

        return "SymbolDeclaration { Name = " + nameValue + ", File = " + fileText + ", Line = " + lineValue.ToString() + ", Column = " + columnValue.ToString() + ", Kind = " + kindValue + " }"
    }
}

class SymbolUsage {
    fileValue: string?
    lineValue: int
    columnValue: int
    lengthValue: int

    File: string? => fileValue
    Line: int => lineValue
    Column: int => columnValue
    Length: int => lengthValue

    constructor(File: string?, Line: int, Column: int, Length: int) {
        fileValue = File
        lineValue = Line
        columnValue = Column
        lengthValue = Length
    }

    override func Equals(value: object): bool {
        other := value as SymbolUsage
        if other == null {
            return false
        }

        return fileValue == other.File && lineValue == other.Line && columnValue == other.Column && lengthValue == other.Length
    }

    override func GetHashCode(): int {
        hash := 17
        if fileValue != null {
            hash = hash * 23 + fileValue.GetHashCode()
        }
        hash = hash * 23 + lineValue
        hash = hash * 23 + columnValue
        hash = hash * 23 + lengthValue
        return hash
    }

    override func ToString(): string {
        fileText := fileValue
        if fileText == null {
            fileText = ""
        }

        return "SymbolUsage { File = " + fileText + ", Line = " + lineValue.ToString() + ", Column = " + columnValue.ToString() + ", Length = " + lengthValue.ToString() + " }"
    }
}

class BindingPositionKey {
    fileValue: string?
    lineValue: int
    colValue: int

    File: string? => fileValue
    Line: int => lineValue
    Col: int => colValue

    constructor(File: string?, Line: int, Col: int) {
        fileValue = File
        lineValue = Line
        colValue = Col
    }

    override func Equals(value: object): bool {
        other := value as BindingPositionKey
        if other == null {
            return false
        }

        return fileValue == other.File && lineValue == other.Line && colValue == other.Col
    }

    override func GetHashCode(): int {
        hash := 17
        if fileValue != null {
            hash = hash * 23 + fileValue.GetHashCode()
        }
        hash = hash * 23 + lineValue
        hash = hash * 23 + colValue
        return hash
    }
}

class SymbolUsageBucket {
    Items: List<SymbolUsage>

    constructor() {
        Items = new List<SymbolUsage>()
    }
}

class BindingEntry {
    keyValue: BindingPositionKey
    declarationValue: SymbolDeclaration

    Key: BindingPositionKey => keyValue
    Value: SymbolDeclaration => declarationValue

    constructor(Key: BindingPositionKey, Value: SymbolDeclaration) {
        keyValue = Key
        declarationValue = Value
    }

    func Deconstruct(out key: BindingPositionKey, out declaration: SymbolDeclaration) {
        key = keyValue
        declaration = declarationValue
    }
}

class BindingEntryEnumerator {
    keys: List<BindingPositionKey>
    values: List<SymbolDeclaration>
    indexValue: int

    Current: BindingEntry => new BindingEntry(keys[indexValue], values[indexValue])

    constructor(keys: List<BindingPositionKey>, values: List<SymbolDeclaration>) {
        this.keys = keys
        this.values = values
        indexValue = -1
    }

    func MoveNext(): bool {
        indexValue = indexValue + 1
        return indexValue < keys.Count
    }
}

class BindingEntryCollection {
    keys: List<BindingPositionKey>
    values: List<SymbolDeclaration>

    Count: int => keys.Count

    constructor(sourceKeys: List<BindingPositionKey>, sourceValues: List<SymbolDeclaration>) {
        keys = new List<BindingPositionKey>()
        values = new List<SymbolDeclaration>()

        i := 0
        while i < sourceKeys.Count {
            keys.Add(sourceKeys[i])
            values.Add(sourceValues[i])
            i = i + 1
        }
    }

    func GetEnumerator(): BindingEntryEnumerator {
        return new BindingEntryEnumerator(keys, values)
    }
}

class BindingDeclarationEntryCollection {
    values: List<SymbolDeclaration>

    Count: int => values.Count
    Values: List<SymbolDeclaration> => values

    constructor(sourceValues: List<SymbolDeclaration>) {
        values = new List<SymbolDeclaration>()

        for sourceValue in sourceValues {
            values.Add(sourceValue)
        }
    }
}

class BindingReferenceResult {
    declarationValue: SymbolDeclaration?
    usagesValue: List<SymbolUsage>

    Declaration: SymbolDeclaration? => declarationValue
    Usages: List<SymbolUsage> => usagesValue

    constructor(Declaration: SymbolDeclaration?, Usages: List<SymbolUsage>) {
        declarationValue = Declaration
        usagesValue = Usages
    }

    func Deconstruct(out declaration: SymbolDeclaration?, out usages: List<SymbolUsage>) {
        declaration = declarationValue
        usages = usagesValue
    }
}

// THE INDEXES ARE KEYED BY POSITION, NOT BY TEXT. Each one maps a `BindingPositionKey` -- (file,
// line, column), compared ordinally and file-less distinct from an empty file -- to the entry's slot.
// They were keyed by a string spelling of the triple, built on every record, lookup and merge: 1.2 GB
// of strings in one Compiler.Core build, 16% of everything it allocated.
//
// THE FUZZY REFERENCE LOOKUP IS INDEXED TOO. A reference bucket missed by its exact key is still
// found through a bucket at the same line and column whose file `FilesMatch` (a file-less key, or one
// path a suffix of the other). That fallback scanned every bucket, and `GetOrAddReferenceList` asks it
// for every NEW declaration, so building or merging a project's map was quadratic in its size. The
// buckets at each (line, column) are now listed in insertion order, and the fallback scans only
// those, in that order -- the same first match the full scan found.
class BindingMap {
    bindingIndexByKey: Dictionary<BindingPositionKey, int>
    bindingKeys: List<BindingPositionKey>
    bindingDeclarations: List<SymbolDeclaration>

    declarationIndexByKey: Dictionary<BindingPositionKey, int>
    declarationKeys: List<BindingPositionKey>
    declarations: List<SymbolDeclaration>

    referenceIndexByKey: Dictionary<BindingPositionKey, int>
    referenceIndicesByPosition: Dictionary<(Line: int, Column: int), List<int>>
    // The same buckets grouped by the FILE NAME their key's spelling ends in (`ReferenceNameGroup`),
    // so a bucket lookup that misses exactly asks only the buckets that can name the same file.
    referenceIndicesByPositionAndName: Dictionary<(Line: int, Column: int, Name: string), List<int>>
    referenceKeys: List<BindingPositionKey>
    referenceBuckets: List<SymbolUsageBucket>

    versionValue: int

    AllDeclarations: List<SymbolDeclaration> {
        get {
            EnsureInitialized()
            return declarations
        }
    }

    BindingEntries: BindingEntryCollection {
        get {
            EnsureInitialized()
            return new BindingEntryCollection(bindingKeys, bindingDeclarations)
        }
    }

    DeclarationEntries: BindingDeclarationEntryCollection {
        get {
            EnsureInitialized()
            return new BindingDeclarationEntryCollection(declarations)
        }
    }

    Version: int => versionValue
    BindingCount: int {
        get {
            EnsureInitialized()
            return bindingKeys.Count
        }
    }

    func RecordBinding(usageFile: string?, usageLine: int, usageCol: int, usageLength: int, declaration: SymbolDeclaration) {
        EnsureInitialized()
        usageKey := MakeBindingKey(usageFile, usageLine, usageCol)

        bindingIndex := 0
        if bindingIndexByKey.TryGetValue(usageKey, out bindingIndex) {
            oldDecl := bindingDeclarations[bindingIndex]
            oldDeclKey := MakeBindingKey(oldDecl.File, oldDecl.Line, oldDecl.Column)
            newDeclKey := MakeBindingKey(declaration.File, declaration.Line, declaration.Column)
            if !KeysEqual(oldDeclKey, newDeclKey) {
                oldUsages := FindReferenceBucket(oldDeclKey)
                if oldUsages != null {
                    RemoveUsage(oldUsages.Items, usageFile, usageLine, usageCol)
                }
            }

            bindingKeys[bindingIndex] = usageKey
            bindingDeclarations[bindingIndex] = declaration
        } else {
            bindingIndexByKey[usageKey] = bindingKeys.Count
            bindingKeys.Add(usageKey)
            bindingDeclarations.Add(declaration)
        }

        SetDeclaration(declaration)

        declKey := MakeBindingKey(declaration.File, declaration.Line, declaration.Column)
        usages := GetOrAddReferenceList(declKey)
        usages.Add(new SymbolUsage(usageFile, usageLine, usageCol, usageLength))
        versionValue = versionValue + 1
    }

    func RecordDeclaration(declaration: SymbolDeclaration) {
        EnsureInitialized()
        key := MakeBindingKey(declaration.File, declaration.Line, declaration.Column)

        existingIndex := 0
        if declarationIndexByKey.TryGetValue(key, out existingIndex) {
            existing := declarations[existingIndex]
            if IsTypeDeclaration(existing.Kind) && IsInternalDeclaration(declaration.Name) {
                return
            }
        }

        SetDeclaration(declaration)
        GetOrAddReferenceList(key)
        versionValue = versionValue + 1
    }

    func GetBindingAt(filePath: string?, line: int, col: int): SymbolDeclaration? {
        EnsureInitialized()
        key := MakeBindingKey(filePath, line, col)

        index := 0
        if declarationIndexByKey.TryGetValue(key, out index) {
            return declarations[index]
        }

        if bindingIndexByKey.TryGetValue(key, out index) {
            return bindingDeclarations[index]
        }

        if filePath != null {
            nullFileKey := MakeBindingKey(null, line, col)

            if declarationIndexByKey.TryGetValue(nullFileKey, out index) {
                return declarations[index]
            }

            if bindingIndexByKey.TryGetValue(nullFileKey, out index) {
                return bindingDeclarations[index]
            }
        }

        return null
    }

    func GetReferences(declaration: SymbolDeclaration?): List<SymbolUsage> {
        EnsureInitialized()
        if declaration == null {
            return new List<SymbolUsage>()
        }

        key := MakeBindingKey(declaration.File, declaration.Line, declaration.Column)
        bucket := FindReferenceBucket(key)
        if bucket == null {
            storedDeclaration := FindStoredDeclarationForLookup(declaration)
            if storedDeclaration != null {
                storedKey := MakeBindingKey(storedDeclaration.File, storedDeclaration.Line, storedDeclaration.Column)
                bucket = FindReferenceBucket(storedKey)
            }
        }

        if bucket == null {
            return new List<SymbolUsage>()
        }

        return bucket.Items
    }

    func FindAllReferences(filePath: string?, line: int, col: int): BindingReferenceResult {
        EnsureInitialized()
        declaration := GetBindingAt(filePath, line, col)
        if declaration == null {
            declaration = FindDeclarationNear(filePath, line, col)
        }

        if declaration == null {
            return new BindingReferenceResult(null, new List<SymbolUsage>())
        }

        usages := GetReferences(declaration)
        return new BindingReferenceResult(declaration, usages)
    }

    func FindDeclarationNear(filePath: string?, line: int, col: int): SymbolDeclaration? {
        bestIndex := -1
        bestDistance := 2147483647

        i := 0
        while i < declarationKeys.Count {
            key := declarationKeys[i]
            if key.Line == line && FilesMatch(key.File, filePath) {
                declaration := declarations[i]
                start := declaration.Column
                end := declaration.Column + declaration.Name.Length - 1
                if col >= start && col <= end {
                    return declaration
                }

                distance := col - start
                if distance < 0 {
                    distance = 0 - distance
                }

                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = i
                }
            }

            i = i + 1
        }

        if bestIndex >= 0 {
            return declarations[bestIndex]
        }

        return null
    }

    func FindStoredDeclarationForLookup(declaration: SymbolDeclaration?): SymbolDeclaration? {
        if declaration == null {
            return null
        }

        for candidate in declarations {
            if candidate.Name == declaration.Name && candidate.Line == declaration.Line && candidate.Column == declaration.Column && FilesMatch(candidate.File, declaration.File) {
                return candidate
            }
        }

        return null
    }

    func Merge(other: BindingMap) {
        EnsureInitialized()
        other.EnsureInitialized()
        i := 0
        while i < other.declarations.Count {
            SetDeclaration(other.declarations[i])
            i = i + 1
        }

        i = 0
        while i < other.bindingKeys.Count {
            key := other.bindingKeys[i]
            bindingIndex := 0
            if bindingIndexByKey.TryGetValue(key, out bindingIndex) {
                bindingKeys[bindingIndex] = key
                bindingDeclarations[bindingIndex] = other.bindingDeclarations[i]
            } else {
                bindingIndexByKey[key] = bindingKeys.Count
                bindingKeys.Add(key)
                bindingDeclarations.Add(other.bindingDeclarations[i])
            }
            i = i + 1
        }

        i = 0
        while i < other.referenceKeys.Count {
            destination := GetOrAddReferenceList(other.referenceKeys[i])
            destination.AddRange(other.referenceBuckets[i].Items)
            i = i + 1
        }

        if other.declarations.Count > 0 || other.bindingKeys.Count > 0 || other.referenceKeys.Count > 0 {
            versionValue = versionValue + 1
        }
    }

    func SetDeclaration(declaration: SymbolDeclaration) {
        key := MakeBindingKey(declaration.File, declaration.Line, declaration.Column)
        declarationIndex := 0
        if declarationIndexByKey.TryGetValue(key, out declarationIndex) {
            declarationKeys[declarationIndex] = key
            declarations[declarationIndex] = declaration
        } else {
            declarationIndexByKey[key] = declarations.Count
            declarationKeys.Add(key)
            declarations.Add(declaration)
        }
    }

    func GetOrAddReferenceList(key: BindingPositionKey): List<SymbolUsage> {
        bucket := FindReferenceBucket(key)
        if bucket != null {
            return bucket.Items
        }

        newBucket := new SymbolUsageBucket()
        newIndex := referenceBuckets.Count
        referenceIndexByKey[key] = newIndex
        position := (Line: key.Line, Column: key.Col)
        atPosition: List<int>? = null
        if !referenceIndicesByPosition.TryGetValue(position, out atPosition) || atPosition == null {
            atPosition = new List<int>()
            referenceIndicesByPosition[position] = atPosition
        }
        atPosition.Add(newIndex)
        named := (Line: key.Line, Column: key.Col, Name: ReferenceNameGroup(key.File))
        withName: List<int>? = null
        if !referenceIndicesByPositionAndName.TryGetValue(named, out withName) || withName == null {
            withName = new List<int>()
            referenceIndicesByPositionAndName[named] = withName
        }
        withName.Add(newIndex)
        referenceKeys.Add(key)
        referenceBuckets.Add(newBucket)
        return newBucket.Items
    }

    // WHICH BUCKETS A FALLBACK LOOKUP HAS TO ASK. `FilesMatch` answers yes for two spellings of one
    // file only when they end in the same file name -- equal, equal once separators are normalised,
    // or one a path suffix of the other all keep the last segment -- so a key whose spelling is plain
    // printable ASCII can match only buckets in its own name group, plus the buckets whose spelling
    // is absent (which match anything) or not plain ASCII (whose suffix test is culture-aware), both
    // kept in the WILDCARD group. Merging the two ascending index lists keeps the full scan's
    // insertion order, and so its first match. Merging the per-file binding maps of a project whose
    // files declare at the same lines and columns had made every new bucket ask every earlier file's
    // bucket at that position: measured, 80% of a warm daemon check of an 81k-line project.
    static func ReferenceNameGroup(file: string?): string {
        if file == null {
            return ReferenceWildcardGroup()
        }

        index := 0
        while index < file.Length {
            character := file[index]
            if character < ' ' || character > '~' {
                return ReferenceWildcardGroup()
            }
            index = index + 1
        }

        normalized := file.Replace('\\', '/')
        separator := normalized.LastIndexOf('/')
        return normalized.Substring(separator + 1)
    }

    static func ReferenceWildcardGroup(): string {
        return "\u0000*"
    }

    func FindReferenceBucket(key: BindingPositionKey): SymbolUsageBucket? {
        exactIndex := 0
        if referenceIndexByKey.TryGetValue(key, out exactIndex) {
            return referenceBuckets[exactIndex]
        }

        group := ReferenceNameGroup(key.File)
        if group == ReferenceWildcardGroup() {
            atPosition: List<int>? = null
            if !referenceIndicesByPosition.TryGetValue((Line: key.Line, Column: key.Col), out atPosition) || atPosition == null {
                return null
            }

            for candidateIndex in atPosition {
                if FilesMatch(referenceKeys[candidateIndex].File, key.File) {
                    return referenceBuckets[candidateIndex]
                }
            }

            return null
        }

        emptyGroup := new List<int>()
        sameName: List<int>? = null
        if !referenceIndicesByPositionAndName.TryGetValue((Line: key.Line, Column: key.Col, Name: group), out sameName) || sameName == null {
            sameName = emptyGroup
        }
        wildcard: List<int>? = null
        if !referenceIndicesByPositionAndName.TryGetValue((Line: key.Line, Column: key.Col, Name: ReferenceWildcardGroup()), out wildcard) || wildcard == null {
            wildcard = emptyGroup
        }

        named := 0
        wild := 0
        while named < sameName.Count || wild < wildcard.Count {
            candidateIndex := 0
            if wild >= wildcard.Count || (named < sameName.Count && sameName[named] < wildcard[wild]) {
                candidateIndex = sameName[named]
                named = named + 1
            } else {
                candidateIndex = wildcard[wild]
                wild = wild + 1
            }
            if FilesMatch(referenceKeys[candidateIndex].File, key.File) {
                return referenceBuckets[candidateIndex]
            }
        }

        return null
    }

    static func MakeBindingKey(filePath: string?, line: int, col: int): BindingPositionKey {
        return new BindingPositionKey(filePath, line, col)
    }

    static func KeysEqual(left: BindingPositionKey, right: BindingPositionKey): bool {
        return left.File == right.File && left.Line == right.Line && left.Col == right.Col
    }

    // WHETHER TWO RECORDED FILE SPELLINGS NAME THE SAME FILE: equal, either one absent, equal once
    // separators are normalised, or one a path suffix of the other. Answered once per pair of
    // spellings: the reference-bucket fallback asks it of every bucket at a new declaration's line and
    // column, and the suffix tests build two strings and make two culture-aware comparisons per pair,
    // which was 0.5 GB of an 80,000-line program's allocation. The answer is a pure function of the
    // two strings; the memo is bounded and safe under parallel analysis.
    static func FilesMatch(left: string?, right: string?): bool {
        if left == right {
            return true
        }

        if left == null || right == null {
            return true
        }

        known := false
        if BindingMap.filesMatchMemo.TryGetValue((Left: left, Right: right), out known) {
            return known
        }

        answer := FilesMatchUncached(left, right)
        if BindingMap.filesMatchMemo.Count < BindingMap.FilesMatchMemoLimit {
            BindingMap.filesMatchMemo.TryAdd((Left: left, Right: right), answer)
        }
        return answer
    }

    static FilesMatchMemoLimit: int => 1000000

    private static readonly filesMatchMemo: ConcurrentDictionary<(Left: string, Right: string), bool> = new ConcurrentDictionary<(Left: string, Right: string), bool>()

    static func FilesMatchUncached(left: string, right: string): bool {
        leftText := left.Replace('\\', '/')
        rightText := right.Replace('\\', '/')

        if leftText == rightText {
            return true
        }

        if leftText.EndsWith("/" + rightText) {
            return true
        }

        if rightText.EndsWith("/" + leftText) {
            return true
        }

        return false
    }

    static func RemoveUsage(usages: List<SymbolUsage>, usageFile: string?, usageLine: int, usageCol: int) {
        index := usages.Count - 1
        while index >= 0 {
            usage := usages[index]
            if usage.File == usageFile && usage.Line == usageLine && usage.Column == usageCol {
                usages.RemoveAt(index)
            }
            index = index - 1
        }
    }

    static func IsTypeDeclaration(kind: string): bool {
        return kind == "class" || kind == "struct" || kind == "record" || kind == "soaRecord" || kind == "interface" || kind == "enum" || kind == "union"
    }

    static func IsInternalDeclaration(name: string): bool {
        return name == "this" || name == "value"
    }

    func EnsureInitialized() {
        if bindingIndexByKey != null {
            return
        }

        bindingIndexByKey = new Dictionary<BindingPositionKey, int>()
        bindingKeys = new List<BindingPositionKey>()
        bindingDeclarations = new List<SymbolDeclaration>()
        declarationIndexByKey = new Dictionary<BindingPositionKey, int>()
        declarationKeys = new List<BindingPositionKey>()
        declarations = new List<SymbolDeclaration>()
        referenceIndexByKey = new Dictionary<BindingPositionKey, int>()
        referenceIndicesByPosition = new Dictionary<(Line: int, Column: int), List<int>>()
        referenceIndicesByPositionAndName = new Dictionary<(Line: int, Column: int, Name: string), List<int>>()
        referenceKeys = new List<BindingPositionKey>()
        referenceBuckets = new List<SymbolUsageBucket>()
    }
}

class ProjectIndex {
    bindingsValue: BindingMap
    typeDeclarationFilesValue: Dictionary<string, string>

    Bindings: BindingMap => bindingsValue
    TypeDeclarationFiles: Dictionary<string, string> => typeDeclarationFilesValue

    constructor(bindings: BindingMap, typeDeclarationFiles: Dictionary<string, string>) {
        bindingsValue = bindings
        typeDeclarationFilesValue = typeDeclarationFiles
    }
}
