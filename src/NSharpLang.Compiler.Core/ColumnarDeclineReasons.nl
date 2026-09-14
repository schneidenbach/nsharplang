namespace NSharpLang.Compiler.Columnar

class ColumnarDeclineReason {
    siteIdValue: string
    messageValue: string
    spanStartValue: int
    spanLengthValue: int
    memberNameValue: string
    sourceFileIdValue: int
    hasSourceFileIdValue: bool

    SiteId: string => siteIdValue
    Message: string => messageValue
    SpanStart: int => spanStartValue
    SpanLength: int => spanLengthValue
    MemberName: string => memberNameValue
    SourceFileId: int => sourceFileIdValue
    HasSourceFileId: bool => hasSourceFileIdValue

    constructor(siteId: string, message: string, spanStart: int, spanLength: int, memberName: string, sourceFileId: int = 0, hasSourceFileId: bool = false) {
        siteIdValue = siteId
        messageValue = message
        spanStartValue = spanStart
        spanLengthValue = spanLength
        memberNameValue = memberName
        sourceFileIdValue = sourceFileId
        hasSourceFileIdValue = hasSourceFileId
    }
}

class ColumnarDeclineReasonFacts {
    static func ResolveFileIndex(fileLengths: int[], separatorLength: int, offset: int, sourceFileId: int, hasSourceFileId: bool): int {
        if hasSourceFileId && sourceFileId >= 0 && sourceFileId < fileLengths.Length {
            return sourceFileId
        }

        return MapMergedOffsetFileIndex(fileLengths, separatorLength, offset)
    }

    static func ResolveLocalOffset(fileLengths: int[], separatorLength: int, offset: int, sourceFileId: int, hasSourceFileId: bool): int {
        if hasSourceFileId && sourceFileId >= 0 && sourceFileId < fileLengths.Length {
            return offset
        }

        return MapMergedOffsetLocalOffset(fileLengths, separatorLength, offset)
    }

    static func MapMergedOffsetFileIndex(fileLengths: int[], separatorLength: int, offset: int): int {
        if offset < 0 {
            return -1
        }

        start := 0
        index := 0
        while index < fileLengths.Length {
            length := fileLengths[index]
            end := start + length
            if offset >= start && offset < end {
                return index
            }

            start = end + separatorLength
            index = index + 1
        }

        return -1
    }

    static func MapMergedOffsetLocalOffset(fileLengths: int[], separatorLength: int, offset: int): int {
        fileIndex := MapMergedOffsetFileIndex(fileLengths, separatorLength, offset)
        if fileIndex < 0 {
            return -1
        }

        start := 0
        index := 0
        while index < fileIndex {
            start = start + fileLengths[index] + separatorLength
            index = index + 1
        }

        return offset - start
    }

    static func LineFromOffset(source: string, offset: int): int {
        if offset < 0 || offset > source.Length {
            return 0
        }

        line := 1
        position := 0
        while position < offset {
            ch := source[position]
            if ch == '\r' {
                line = line + 1
                if position + 1 < offset && position + 1 < source.Length && source[position + 1] == '\n' {
                    position = position + 2
                    continue
                }
            } else {
                if ch == '\n' {
                    line = line + 1
                }
            }

            position = position + 1
        }

        return line
    }

    static func ColumnFromOffset(source: string, offset: int): int {
        if offset < 0 || offset > source.Length {
            return 0
        }

        lineStart := 0
        position := 0
        while position < offset {
            ch := source[position]
            if ch == '\r' {
                if position + 1 < offset && position + 1 < source.Length && source[position + 1] == '\n' {
                    position = position + 2
                } else {
                    position = position + 1
                }

                lineStart = position
                continue
            }

            if ch == '\n' {
                position = position + 1
                lineStart = position
                continue
            }

            position = position + 1
        }

        return offset - lineStart + 1
    }

    static func FormatDetail(reason: ColumnarDeclineReason, fileName: string? = null, line: int = 0, column: int = 0): string {
        detail := "Declined at " + reason.SiteId + ": " + reason.Message
        if reason.MemberName.Length > 0 {
            detail = detail + " in '" + reason.MemberName + "'"
        }

        if fileName != null && fileName.Length > 0 && line > 0 && column > 0 {
            detail = detail + " (" + fileName + ":" + line.ToString() + ":" + column.ToString() + ")"
        }

        return detail + "."
    }

    static func FormatTraceLine(reason: ColumnarDeclineReason, fileName: string? = null, line: int = 0, column: int = 0): string {
        lineText := "decline site=" + reason.SiteId + " message=\"" + reason.Message + "\"" + " span=" + reason.SpanStart.ToString() + ":" + reason.SpanLength.ToString()

        if reason.MemberName.Length > 0 {
            lineText = lineText + " member=\"" + reason.MemberName + "\""
        }

        if fileName != null && fileName.Length > 0 && line > 0 && column > 0 {
            lineText = lineText + " location=" + fileName + ":" + line.ToString() + ":" + column.ToString()
        }

        return lineText
    }
}

// THE COLUMNAR PARSE-INPUT DECLINE VOCABULARY.
//
// `ColumnarProgramInputBuilder` turns a source file into the flat columnar inputs the emitter
// consumes, and every shape it cannot model DECLINES. A decline is not an internal event: the
// primary one is rendered by `ColumnarDeclineReasonFacts.FormatDetail` into the `NL103` a developer
// reads — `Declined at parse.function.body: function body was not materialized as a supported block
// or expression body in 'Main' (Program.nl:12:1).` — so both halves of every row below are PRODUCT
// TEXT with a user on the other end.
//
// The builder is C# (it marshals arrays into sixteen N# parser kernels), so before this owner
// existed the words themselves lived in C#: 49 site ids, 49 sentences and 6 scan-stage names,
// spelled in a language that owns none of the decisions they describe. They are spelled HERE now
// and the builder consumes them, which is the same shape `ColumnarIteratorPlanner.nl` already uses
// for its own `emit.iterator.*` vocabulary. `ColumnarParseDeclineVocabulary.tests.nl` pins every
// row, so changing a word a user can read is a contract change, not a silent edit.
class ColumnarParseDecline {
    siteIdValue: string
    messageValue: string

    SiteId: string => siteIdValue
    Message: string => messageValue

    constructor(siteId: string, message: string) {
        siteIdValue = siteId
        messageValue = message
    }
}

class ColumnarParseDeclines {

    // ---- tokenization ----
    static Tokenize: ColumnarParseDecline => new ColumnarParseDecline("parse.tokenize", "columnar tokenization failed")
    static TokenizeInvalidResult: ColumnarParseDecline => new ColumnarParseDecline("parse.tokenize.invalid-result", "columnar tokenizer returned invalid token counts")

    // ---- top-level declaration scan ----
    // The stage names decode the declaration kernel's OWN negative return codes, so the code and
    // the word for it stay in one place. Anything outside -2 … -6 is the generic stage.
    static func DeclarationScan(declarationScanResult: int): ColumnarParseDecline {
        stage := "declaration scan"
        if declarationScanResult == -2 {
            stage = "function scan"
        } else if declarationScanResult == -3 {
            stage = "declaration name spans mismatched the declaration count"
        } else if declarationScanResult == -4 {
            stage = "duplicate top-level type names"
        } else if declarationScanResult == -5 {
            stage = "nominal (enum/union/interface) scan"
        } else if declarationScanResult == -6 {
            stage = "struct-like scan"
        }

        return new ColumnarParseDecline("parse.declaration-scan", "top-level declaration scan failed at " + stage + "; the source may contain an unmodeled declaration shape such as setup or teardown")
    }

    // ---- per-kind materialization (the whole pass for one declaration kind gave up) ----
    static FunctionMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.function", "function declaration materialization failed")
    static EnumMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.enum", "enum declaration materialization failed")
    static StructMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.struct", "struct/class/record declaration materialization failed")
    static UnionMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.union", "union declaration materialization failed")
    static InterfaceMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.interface", "interface declaration materialization failed")
    static TestMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.test", "test declaration materialization failed")
    static NewtypeMaterialization: ColumnarParseDecline => new ColumnarParseDecline("parse.newtype", "newtype declaration materialization failed")

    // ---- newtypes and tests ----
    static NewtypeScan: ColumnarParseDecline => new ColumnarParseDecline("parse.newtype-scan", "newtype declaration scan failed (composed underlying types are not modeled)")
    static TestScan: ColumnarParseDecline => new ColumnarParseDecline("parse.test-scan", "test declaration scan failed")
    static TestDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.test", "test declaration could not be parsed into columnar input")

    // ---- functions ----
    static FunctionDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.function", "function declaration could not be parsed into columnar input")
    static FunctionBodyOrSignature: ColumnarParseDecline => new ColumnarParseDecline("parse.function", "function body or signature could not be parsed into columnar input")
    static FunctionParameterTupleNames: ColumnarParseDecline => new ColumnarParseDecline("parse.function.param-tuple-names", "function parameter tuple-name metadata was invalid")
    static FunctionReturnTupleNames: ColumnarParseDecline => new ColumnarParseDecline("parse.function.return-tuple-names", "function return tuple-name metadata was invalid")
    static FunctionBody: ColumnarParseDecline => new ColumnarParseDecline("parse.function.body", "function body was not materialized as a supported block or expression body")
    static FunctionConstraintsWithoutTypeParameters: ColumnarParseDecline => new ColumnarParseDecline("parse.function.constraints", "function constraints were present without type parameters")
    static FunctionConstraintMetadata: ColumnarParseDecline => new ColumnarParseDecline("parse.function.constraints", "function constraint metadata was invalid")
    static FunctionBodyNodes: ColumnarParseDecline => new ColumnarParseDecline("parse.function.body-nodes", "function body node table was invalid")
    static FunctionNativeImport: ColumnarParseDecline => new ColumnarParseDecline("parse.function.native-import", "LibraryImport metadata could not be parsed into columnar input")
    static FunctionLocalFunctionMetadata: ColumnarParseDecline => new ColumnarParseDecline("parse.function.local-functions", "local-function metadata was invalid")
    static LocalFunction: ColumnarParseDecline => new ColumnarParseDecline("parse.local-function", "local function could not be parsed into columnar input")

    // ---- enums ----
    static EnumDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.enum", "enum declaration could not be parsed into columnar input")

    // ---- structs, classes and records ----
    static StructInvalidCount: ColumnarParseDecline => new ColumnarParseDecline("parse.struct.invalid-count", "struct/class/record declaration count was invalid")
    static StructDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.struct", "struct/class/record declaration could not be parsed into columnar input")
    static StructMethod: ColumnarParseDecline => new ColumnarParseDecline("parse.struct.method", "struct/class/record method could not be parsed into columnar input")
    static StructConstructor: ColumnarParseDecline => new ColumnarParseDecline("parse.struct.constructor", "constructor could not be parsed into columnar input")
    static StructProperty: ColumnarParseDecline => new ColumnarParseDecline("parse.struct.property", "property could not be parsed into columnar input")

    // ---- unions ----
    static UnionDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.union", "union declaration could not be parsed into columnar input")

    // ---- constructors ----
    static Constructor: ColumnarParseDecline => new ColumnarParseDecline("parse.constructor", "constructor body or signature could not be parsed into columnar input")
    static ConstructorBody: ColumnarParseDecline => new ColumnarParseDecline("parse.constructor.body", "constructor body was not materialized as a supported block")
    static ConstructorChain: ColumnarParseDecline => new ColumnarParseDecline("parse.constructor.chain", "constructor chain-argument metadata was invalid")
    static ConstructorBodyNodes: ColumnarParseDecline => new ColumnarParseDecline("parse.constructor.body-nodes", "constructor body node table was invalid")

    // ---- properties ----
    static PropertyDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.property", "property declaration could not be parsed into columnar input")
    static PropertyGetter: ColumnarParseDecline => new ColumnarParseDecline("parse.property.getter", "property getter body was not materialized as a supported body")
    static PropertyGetterNodes: ColumnarParseDecline => new ColumnarParseDecline("parse.property.getter-nodes", "property getter node table was invalid")
    static PropertySetter: ColumnarParseDecline => new ColumnarParseDecline("parse.property.setter", "property setter body was not materialized as a supported block")
    static PropertySetterNodes: ColumnarParseDecline => new ColumnarParseDecline("parse.property.setter-nodes", "property setter node table was invalid")
    static PropertyAccessorKind: ColumnarParseDecline => new ColumnarParseDecline("parse.property.accessor-kind", "property accessor kind was invalid")

    // ---- interfaces ----
    static InterfaceDeclaration: ColumnarParseDecline => new ColumnarParseDecline("parse.interface", "interface declaration could not be parsed into columnar input")
    static InterfaceTypeParameterMetadata: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.type-params", "interface type parameter metadata was invalid")
    static InterfaceTypeParameterName: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.type-param", "interface type parameter name was invalid")
    static InterfaceFlatParameterMetadata: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.params", "interface flat parameter metadata was invalid")
    static InterfaceParameterCount: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.params", "interface parameter metadata did not consume the expected count")
    static InterfaceMethodParameterMetadata: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.method-params", "interface method parameter metadata was invalid")
    static InterfaceMethodBody: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.method-body", "default interface method body could not be parsed into columnar input")
    static InterfaceMethodBodyFlag: ColumnarParseDecline => new ColumnarParseDecline("parse.interface.method-body-flag", "interface method body flag was invalid")
}
