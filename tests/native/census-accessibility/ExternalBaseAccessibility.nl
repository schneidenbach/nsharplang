namespace NSharpLang.CensusAccessibility.Tests

import System.Collections.ObjectModel
import System.IO
import System.Linq.Expressions


// WHAT A SOURCE TYPE INHERITS FROM AN EXTERNAL BASE INCLUDES ITS `protected` SURFACE.
//
// `Collection<T>` is designed to be extended through `SetItem`, `ClearItems`, `InsertItem` and
// `RemoveItem` — all `protected virtual` — and a source type that derived from it could not NAME any
// of them: metadata resolution asked for `BindingFlags.Public` only, so the analyzer answered NL303
// / NL412, and the emitter's candidate enumeration was public-only too.
//
// `Collection<string>` is a GENERIC external base and `StringWriter` is a plain one, so both shapes
// of the inherited-base walk are exercised.
class GuardedCollection: Collection<string> {
    func ReplaceThroughThis(index: int, item: string) {
        this.SetItem(index, item)
    }

    // THE SAME MEMBER NAMED WITH NO RECEIVER AT ALL. A bare name is `this.Name`, so this is the call
    // above written the other way — and it declined, because the bare-call entry gate enumerated the
    // base's PUBLIC methods only and bailed out before the arm that would have selected a `protected`
    // one ever ran.
    func ReplaceWithoutReceiver(index: int, item: string) {
        SetItem(index, item)
    }

    func InsertThroughBase(index: int, item: string) {
        base.InsertItem(index, item)
    }

    func ClearThroughBase() {
        base.ClearItems()
    }
}

// The same rule over a NON-GENERIC external base.
class LineAwareWriter: StringWriter {
    func ReleaseThroughThis() {
        this.Dispose(true)
    }

    func ReleaseThroughBase() {
        base.Dispose(true)
    }
}

// READING WHAT THE EXTERNAL BASE DECLARES, AT EVERY LEVEL A DERIVED TYPE MAY REACH AND AT EVERY
// RESULT TYPE.
//
// Calling an inherited `protected` method already worked; READING an inherited member did not, and
// it was not the accessibility that stopped it. The `this.`/bare-name read path selected a PUBLIC
// PROPERTY whose result type was on a modelled-value list, so three independent facts each declined
// the read on their own: `protected` (`Items`), being a FIELD rather than a property
// (`CoreNewLine`), and a result type off the list (`IList<string>`, `char[]`) — the last of which
// declined PUBLIC members too. An inherited external member is read by ordinary resolution now, at
// any result type the backend can hold.
class ReadingCollection: Collection<string> {

    // `Collection<T>.Items` is `protected` and typed `IList<T>` — two of the three.
    func ItemCountThroughThis(): int {
        return this.Items.Count
    }

    func ItemCountThroughBase(): int {
        return base.Items.Count
    }

    // ...and the same member named with no receiver at all, which IS `this.Items`.
    func FirstItem(): string? {
        return Items[0]
    }
}

// `TextWriter.CoreNewLine` is a `protected` FIELD typed `char[]`: storage rather than a property,
// and an array result.
class ReadingWriter: StringWriter {
    func NewLineLengthThroughThis(): int {
        return this.CoreNewLine.Length
    }

    func NewLineLengthThroughBase(): int {
        return base.CoreNewLine.Length
    }

    func NewLineFirst(): char {
        return CoreNewLine[0]
    }

    // The read is the base's own STORAGE, not a snapshot: writing the base's `NewLine` property
    // replaces the very array the two reads above address.
    func UseBangTerminator() {
        this.NewLine = "!"
    }
}

// OVERRIDING AN EXTERNAL BASE'S `protected virtual` MEMBER.
//
// Naming one already worked; TAKING ITS SLOT did not. The override-target walk enumerated the base's
// non-public members and then threw every one of them away with an `IsPublic` test, so
// `override func SetItem(...)` reported "no overridable base member matches 'SetItem'" — with or
// without a written `protected`. Behind that, the walk that recovers a closed handle's open
// `MethodDef` was public-only too, and answered "The external method's open MethodDef could not be
// recovered from its declaring type".
//
// THE ACCESSIBILITY OF THE SLOT BELONGS TO THE TYPE THAT OPENED IT. `SetItem` below writes no
// accessibility word, and its PascalCase name would otherwise make it public — but an `override` is a
// replacement of the base's member, not a decision to publish it, so it is emitted `family` like the
// member it replaces. A WRITTEN word is a statement and is honoured: `ClearItems` says `protected`
// and gets it, `InsertItem` says `public` and widens, which the CLR permits (only NARROWING an
// override is refused).
class ObservedCollection: Collection<string> {
    Replacements: int = 0
    Clears: int = 0
    Inserts: int = 0

    override func SetItem(index: int, item: string) {
        Replacements = Replacements + 1
        base.SetItem(index, item)
    }

    protected override func ClearItems() {
        Clears = Clears + 1
        base.ClearItems()
    }

    public override func InsertItem(index: int, item: string) {
        Inserts = Inserts + 1
        base.InsertItem(index, item)
    }
}

// A `protected internal` SLOT READ ACROSS THE ASSEMBLY BOUNDARY THAT DECLARED IT.
//
// `ExpressionVisitor.VisitExtension` and `ExpressionVisitor.VisitConstant` are `protected internal
// virtual` in System.Linq.Expressions. `protected internal` is a UNION — the family half reaches
// every derived type, the assembly half only the assembly that declared the member — so from HERE,
// outside that assembly, what the slot is worth is the family half alone: plain `protected`.
//
// MEASURED. `protected override func VisitExtension(...)` — the shape every converted OmniSharp
// handler has, 22 sites in one converter census — was reported NL311 "the slot it takes is
// 'protected internal' — an override cannot narrow the accessibility it inherits", which is the
// rule INVERTED: `protected` IS the accessibility inherited here, so there is nothing to narrow.
// Emitting the pair through `Reflection.Emit` and loading it settles which words the runtime takes:
// `Family` loads, `FamORAssem` loads, and only `Assembly` and `FamANDAssem` raise
// `TypeLoadException: … cannot reduce access.`
//
// BOTH ACCEPTED WORDS ARE WRITTEN BELOW, because both are statements the compiler honours and the
// runtime keeps: `VisitExtension` says `protected` and is emitted `family`, `VisitConstant` says
// `protected internal` — a widening, which adds the assembly half back on THIS side — and is
// emitted `famorassem`.
class RecordingVisitor: ExpressionVisitor {
    Extensions: int = 0
    Constants: int = 0

    protected override func VisitExtension(node: Expression): Expression {
        Extensions = Extensions + 1
        return base.VisitExtension(node)
    }

    internal protected override func VisitConstant(node: ConstantExpression): Expression {
        Constants = Constants + 1
        return base.VisitConstant(node)
    }
}
