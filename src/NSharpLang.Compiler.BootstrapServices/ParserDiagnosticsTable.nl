namespace NSharpLang.Compiler.Columnar

public class ParserDiagnosticMessageKind {
    public static func ReservedKeywordAsName(): int { return 1 }
    public static func ExpectedMemberNameAfterDot(): int { return 2 }
    public static func ExpectedDeclarationName(): int { return 3 }
}

public class ParserDiagnosticContextKind {
    public static func Unknown(): int { return 0 }
    public static func DotMember(): int { return 1 }
    public static func Parameter(): int { return 2 }
    public static func Field(): int { return 3 }
    public static func FunctionDeclaration(): int { return 4 }
    public static func ClassDeclaration(): int { return 5 }
    public static func StructDeclaration(): int { return 6 }
    public static func RecordDeclaration(): int { return 7 }
    public static func InterfaceDeclaration(): int { return 8 }
    public static func UnionDeclaration(): int { return 9 }
    public static func EnumDeclaration(): int { return 10 }
    public static func TypeAliasDeclaration(): int { return 11 }
}

public class ParserDiagnosticTable {
    SourceFileIds: int[]
    Codes: int[]
    Starts: int[]
    Lengths: int[]
    Lines: int[]
    Columns: int[]
    MessageKinds: int[]
    ContextKinds: int[]
    ArgAStarts: int[]
    ArgALengths: int[]
    ArgBStarts: int[]
    ArgBLengths: int[]
    Count: int
    PanicMode: bool

    constructor(capacity: int) {
        safeCapacity := capacity
        if capacity < 1 {
            safeCapacity = 1
        }

        SourceFileIds = new int[](safeCapacity)
        Codes = new int[](safeCapacity)
        Starts = new int[](safeCapacity)
        Lengths = new int[](safeCapacity)
        Lines = new int[](safeCapacity)
        Columns = new int[](safeCapacity)
        MessageKinds = new int[](safeCapacity)
        ContextKinds = new int[](safeCapacity)
        ArgAStarts = new int[](safeCapacity)
        ArgALengths = new int[](safeCapacity)
        ArgBStarts = new int[](safeCapacity)
        ArgBLengths = new int[](safeCapacity)
        Count = 0
        PanicMode = false
    }
}

public class ParserDiagnosticTableOps {
    public static func ResetPanicMode(table: ParserDiagnosticTable) {
        table.PanicMode = false
    }

    public static func Report(
        table: ParserDiagnosticTable,
        sourceFileId: int,
        code: int,
        start: int,
        length: int,
        line: int,
        column: int,
        messageKind: int,
        contextKind: int,
        argAStart: int,
        argALength: int,
        argBStart: int,
        argBLength: int): bool {
        if table.PanicMode {
            return false
        }

        if table.Count >= table.Codes.Length {
            return false
        }

        row := table.Count
        table.SourceFileIds[row] = sourceFileId
        table.Codes[row] = code
        table.Starts[row] = start
        table.Lengths[row] = length
        table.Lines[row] = line
        table.Columns[row] = column
        table.MessageKinds[row] = messageKind
        table.ContextKinds[row] = contextKind
        table.ArgAStarts[row] = argAStart
        table.ArgALengths[row] = argALength
        table.ArgBStarts[row] = argBStart
        table.ArgBLengths[row] = argBLength
        table.Count = table.Count + 1
        table.PanicMode = true
        return true
    }
}
