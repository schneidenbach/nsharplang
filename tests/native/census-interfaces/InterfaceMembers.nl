namespace NSharpLang.CensusInterfaces.Tests

import System

// THE SHAPES A CONVERTED C# INTERFACE ACTUALLY HAS. Every interface in this file declared a value
// member and declined the whole declaration at `parse.interface` before this slice, so the file
// COMPILING is half of each contract below; the other half is reading the member THROUGH the
// interface, which is the dispatch the slot exists for.

// A value member written bare, beside a `func`. `Uri` is one abstract `get_Uri` slot plus the
// `PropertyInfo` row naming it — the shape `IDocumentState.Uri` has in the code being converted.
interface IDocumentState {
    Uri: string

    func Touch(): int
}

// THE FIELD SPELLING FILLS THE SLOT. A class writes its value members bare, so this is the way the
// converted code fills one, and the reader the slot needs is synthesized over the field.
class DocumentState: IDocumentState {
    Uri: string
    touches: int

    constructor(uri: string) {
        Uri = uri
        touches = 0
    }

    func Touch(): int {
        touches = touches + 1
        return touches
    }
}

// THE ACCESSOR SPELLING FILLS THE SAME SLOT — the member is computed rather than stored, and the
// interface cannot tell the difference.
class ComputedState: IDocumentState {
    scheme: string
    host: string

    constructor(scheme: string, host: string) {
        this.scheme = scheme
        this.host = host
    }

    Uri: string {
        get {
            return scheme + "://" + host
        }
    }

    func Touch(): int {
        return 0
    }
}

// A STRUCT MAY FILL A SLOT TOO. The receiver is boxed at the interface, which is where the copy is
// taken, so the read runs against the boxed value.
struct PointState: IDocumentState {
    Uri: string

    func Touch(): int {
        return 7
    }
}

func ReadUri(state: IDocumentState): string {
    return state.Uri
}

func ReadUriAndTouch(state: IDocumentState): string {
    count := state.Touch()
    return state.Uri + "#" + count.ToString()
}

// SEVERAL VALUE MEMBERS, OF SEVERAL TYPES, plus a base interface whose own value member is inherited
// by the derived one — a slot is a slot wherever in the closure it was declared.
interface INamed {
    DisplayName: string
}

interface ITestCase: INamed {
    Ordinal: int
    Skipped: bool
    Tags: string[]

    func Run(): string
}

class TestCase: ITestCase {
    DisplayName: string
    Ordinal: int
    Skipped: bool
    Tags: string[]

    constructor(displayName: string, ordinal: int, skipped: bool, tags: string[]) {
        DisplayName = displayName
        Ordinal = ordinal
        Skipped = skipped
        Tags = tags
    }

    func Run(): string {
        return DisplayName + ":" + Ordinal.ToString()
    }
}

func Describe(testCase: ITestCase): string {
    return testCase.Ordinal.ToString() + "/" + testCase.Skipped.ToString() + "/" + testCase.Tags.Length.ToString()
}

func DescribeAsNamed(named: INamed): string {
    return named.DisplayName
}

// A DEFAULT IMPLEMENTATION READS THE SLOT BESIDE IT. `Describe` has a body, so every implementer
// inherits it, and the body reaches `Label` through the same dispatch an outside caller uses.
interface ILabelled {
    Label: string

    func Describe(): string {
        return "<" + Label + ">"
    }
}

class Labelled: ILabelled {
    Label: string

    constructor(label: string) {
        Label = label
    }
}

func DescribeLabelled(labelled: ILabelled): string {
    return labelled.Describe()
}

// AN EVENT AND A VALUE MEMBER IN ONE INTERFACE, filled from one class. Both are slots the
// implementing type fills, and neither spelling disturbs the other.
interface IChannel {
    event Changed: EventHandler

    Name: string

    func Touch()
}

class Channel: IChannel {
    event Changed: EventHandler
    Name: string

    constructor(name: string) {
        Name = name
    }

    func Touch() {
        Changed?.Invoke(this, EventArgs.Empty)
    }
}

func WatchChannel(channel: IChannel): string {
    seen := 0
    sub := on channel.Changed (sender, args) => {
        seen = seen + 1
    }
    channel.Touch()
    channel.Touch()
    off sub
    channel.Touch()
    return channel.Name + "=" + seen.ToString()
}

// A GENERIC INTERFACE'S VALUE MEMBER IS TYPED BY ITS OWN PARAMETER, and closing the interface closes
// the slot with it. No implementer is written here: a CLASS closing a generic SOURCE interface
// load-fails today for reasons that have nothing to do with value members — `class IntBox: IBox<int>`
// with only a `func Describe(): string` in the interface already throws
// `tried to override method 'Describe' but does not implement or inherit that method` — so this
// declaration pins the SLOT's metadata and leaves that gap to its own slice.
interface IBox<T> {
    Value: T

    func Describe(): string
}

// A DUCK INTERFACE'S VALUE MEMBER IS A SLOT LIKE ANY OTHER. Structural matching used to count only
// the interface's `Methods`, so `IShaped` would have matched EVERY type in the program — a value
// member is not a method — and the CLR then refused to load each one ("Method 'get_Size' in type
// 'Unmatched' does not have an implementation"). The match now asks for the value members too, and
// the reader each match needs is synthesized exactly as a declared interface's is.
duck interface IShaped {
    Size: int

    func Describe(): string
}

class Tile {
    Size: int

    constructor(size: int) {
        Size = size
    }

    func Describe(): string {
        return "tile"
    }
}

// Same `func`, NO `Size` — so this one does not match, and nothing is registered on it.
class Unmatched {
    func Describe(): string {
        return "unmatched"
    }
}

func ReadShaped(shaped: IShaped): string {
    return shaped.Describe() + ":" + shaped.Size.ToString()
}
