namespace NSharpLang.ReadOnlyDictionaryWidening.Tests

import System.Collections.Generic

// THE EXECUTABLE HALF OF THE `IReadOnlyDictionary<K, V>` WIDENING ROW (task 020 slice 10, stage 1).
//
// `Dictionary<K, V>` did not widen to `IReadOnlyDictionary<K, V>` in ANY position — finding 97.6 —
// even though the columnar emitter's upcast row and the analyser's `IsKnownGenericConversion` row
// had BOTH been published a slice earlier. The reason was a third half nobody had looked at:
// `AnalyzerAssignabilityFacts.ClassifyKnownGenericAssignability` consults the conversion table only
// after `TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition` admits BOTH sides, and that table
// carried ONE-ARGUMENT heads only. The estate contracts state those three rows directly; this
// project states what they are FOR, by running it.
//
// EVERY SUBJECT IS PARAMETER-SHAPED. Nothing here widens a literal at its use site: each entry point
// receives its concrete collection as an argument, so the conversion is a real one on a real value
// rather than something the emitter could fold away. The `List<T>` -> `IReadOnlyList<T>` rows are
// carried alongside as CONTROLS in the same positions, because they are the one-argument relation
// this two-argument one mirrors, and they were already green before the row.
//
// THE READ-BACKS ARE THE POINT, NOT THE COMPILE. `EmitValueCoercion` is known to no-op silently for
// closed generics over emitted user types, which turns a missing check into garbage rather than an
// error, so every contract here reads a VALUE back through the widened view and compares it. Two of
// them use user-declared element types — one reference, one value — and one asserts the widened view
// is the SAME OBJECT by observing a later write through the concrete map.
//
// `Count` IS ABSENT FROM THIS FILE ON PURPOSE. `IReadOnlyDictionary<K, V>.Count` is inherited from
// `IReadOnlyCollection<T>` and does not resolve (`NL303`); `IReadOnlySet<T>` fails identically, so
// the gap is the read-only heads' shared one and predates this row. `ContainsKey`, `TryGetValue` and
// the indexer are what the interface declares itself, and all three are exercised below.

class WideningWidget {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

struct WideningPoint {
    X: int

    constructor(x: int) {
        X = x
    }
}

class WideningSubject {

    // ── ARGUMENT POSITION ────────────────────────────────────────────────
    static func ReadThroughArgument(map: IReadOnlyDictionary<string, string>, key: string): string {
        text := ""
        if map.TryGetValue(key, out text) {
            return text
        }

        return "<none>"
    }

    static func ContainsThroughArgument(map: IReadOnlyDictionary<string, string>, key: string): bool {
        return map.ContainsKey(key)
    }

    static func IndexThroughArgument(map: IReadOnlyDictionary<string, string>, key: string): string {
        return map[key]
    }

    static func ReadIntThroughArgument(map: IReadOnlyDictionary<string, int>, key: string): int {
        value := 0
        if map.TryGetValue(key, out value) {
            return value
        }

        return -1
    }

    // ── RETURN POSITION ──────────────────────────────────────────────────
    static func WidenReturn(map: Dictionary<string, string>): IReadOnlyDictionary<string, string> {
        return map
    }

    static func WidenSortedReturn(map: SortedDictionary<string, int>): IReadOnlyDictionary<string, int> {
        return map
    }

    // ── ELEMENT TYPES THE COERCION COULD HAVE FAKED ──────────────────────
    static func WidgetName(map: IReadOnlyDictionary<string, WideningWidget>, key: string): string {
        widget := map[key]
        return widget.Name
    }

    static func PointX(map: IReadOnlyDictionary<string, WideningPoint>, key: string): int {
        point := map[key]
        return point.X
    }

    static func SameObject(concrete: Dictionary<string, string>, widened: IReadOnlyDictionary<string, string>): bool {
        return Object.ReferenceEquals(concrete, widened)
    }

    // ── THE ONE-ARGUMENT CONTROLS, IN THE SAME POSITIONS ─────────────────
    static func FirstThroughArgument(values: IReadOnlyList<string>): string {
        return values[0]
    }

    static func WidenListReturn(values: List<string>): IReadOnlyList<string> {
        return values
    }

    // ── THE BARE-INT CONTROL ─────────────────────────────────────────────
    static func BareInt(seed: int): int {
        return seed + 1
    }
}

// FIELD POSITION, over both relations at once: the constructor receives concrete collections and
// stores them in interface-typed fields, which is the assignment `ProjectSnapshot`'s own constructor
// performs nine times.
class WideningFieldHolder {
    mapValue: IReadOnlyDictionary<string, string>
    valuesValue: IReadOnlyList<string>

    Map: IReadOnlyDictionary<string, string> => mapValue
    Values: IReadOnlyList<string> => valuesValue

    constructor(map: Dictionary<string, string>, values: List<string>) {
        mapValue = map
        valuesValue = values
    }
}

// THE SNAPSHOT'S OWN CONSTRUCTOR SHAPE, STATED POSITIONALLY. `ProjectSnapshot` takes three
// read-only dictionaries and two read-only lists interleaved with a string and three nullable
// references, and callers hand it concrete `Dictionary`/`List` values at exactly these positions —
// which is what this row unblocked. 020 slice 10 then spent it: the estate's
// `OutputFormatterDiagnosticKernels.tests.nl` now BUILDS a real `ProjectSnapshot` in this shape and
// asks `CodeIntelligenceQueries.Diagnostics` of it. The real type still cannot be CONSTRUCTED from
// a native project — building any type that lives in a referenced assembly declines at
// `emit.local.initializer`, which is why every native project reaches production types by
// reflection — so the shape is stated here with the same parameter list and read back member by
// member.
class WideningSnapshotShape {
    rootValue: string
    unitsValue: IReadOnlyDictionary<string, string>
    modelsValue: IReadOnlyDictionary<string, int>
    errorsValue: IReadOnlyList<string>
    filesValue: IReadOnlyList<string>
    textsValue: IReadOnlyDictionary<string, string>

    Root: string => rootValue
    Units: IReadOnlyDictionary<string, string> => unitsValue
    Models: IReadOnlyDictionary<string, int> => modelsValue
    Errors: IReadOnlyList<string> => errorsValue
    Files: IReadOnlyList<string> => filesValue
    Texts: IReadOnlyDictionary<string, string> => textsValue

    constructor(root: string, units: IReadOnlyDictionary<string, string>, models: IReadOnlyDictionary<string, int>, errors: IReadOnlyList<string>, files: IReadOnlyList<string>, texts: IReadOnlyDictionary<string, string>) {
        rootValue = root
        unitsValue = units
        modelsValue = models
        errorsValue = errors
        filesValue = files
        textsValue = texts
    }
}

func WideningStringMap(key: string, value: string): Dictionary<string, string> {
    map := new Dictionary<string, string>()
    map[key] = value
    return map
}

func WideningIntMap(key: string, value: int): Dictionary<string, int> {
    map := new Dictionary<string, int>()
    map[key] = value
    return map
}

func WideningOneList(value: string): List<string> {
    values := new List<string>()
    values.Add(value)
    return values
}

test "a bare int still answers, and the one-argument relation is unmoved" {
    assert WideningSubject.BareInt(41) == 42

    values := WideningOneList("control")
    assert WideningSubject.FirstThroughArgument(values) == "control"
    assert WideningSubject.WidenListReturn(values)[0] == "control"

    holder := new WideningFieldHolder(WideningStringMap("k", "field"), values)
    assert holder.Values[0] == "control"
}

test "a concrete dictionary crosses into a read-only parameter and every declared reader answers" {
    map := WideningStringMap("k", "argument")

    assert WideningSubject.ReadThroughArgument(map, "k") == "argument"
    assert WideningSubject.ReadThroughArgument(map, "absent") == "<none>"
    assert WideningSubject.ContainsThroughArgument(map, "k")
    assert WideningSubject.ContainsThroughArgument(map, "absent") == false
    assert WideningSubject.IndexThroughArgument(map, "k") == "argument"
}

test "a concrete dictionary crosses in return position and the entry survives the crossing" {
    widened := WideningSubject.WidenReturn(WideningStringMap("k", "returned"))

    text := ""
    assert widened.TryGetValue("k", out text)
    assert text == "returned"
    assert widened.ContainsKey("k")
}

test "a concrete dictionary crosses in field position and the entry survives the crossing" {
    holder := new WideningFieldHolder(WideningStringMap("k", "field"), WideningOneList("v"))

    text := ""
    assert holder.Map.TryGetValue("k", out text)
    assert text == "field"
    assert holder.Map["k"] == "field"
}

test "the sorted dictionary reaches the same read-only head, in both positions" {
    sorted := new SortedDictionary<string, int>()
    sorted["k"] = 42

    assert WideningSubject.ReadIntThroughArgument(sorted, "k") == 42
    widened := WideningSubject.WidenSortedReturn(sorted)
    value := 0
    assert widened.TryGetValue("k", out value)
    assert value == 42

    // The concrete dictionary reaches the same parameter with the same value type.
    assert WideningSubject.ReadIntThroughArgument(WideningIntMap("k", 7), "k") == 7
}

test "the widened view is the SAME object, so it is a reference conversion and not a copy" {
    concrete := WideningStringMap("k", "first")
    widened := WideningSubject.WidenReturn(concrete)

    assert WideningSubject.SameObject(concrete, widened)
    assert WideningSubject.ReadThroughArgument(widened, "k") == "first"

    // A write through the concrete map is visible through the widened view. A silent no-op coercion
    // that handed back a snapshot — or garbage — could not answer this.
    concrete["k"] = "second"
    assert WideningSubject.ReadThroughArgument(widened, "k") == "second"
}

test "a dictionary over a user-declared reference element widens and hands back the real instance" {
    widgets := new Dictionary<string, WideningWidget>()
    widgets["w"] = new WideningWidget("gadget")

    assert WideningSubject.WidgetName(widgets, "w") == "gadget"

    widgets["w"] = new WideningWidget("replacement")
    assert WideningSubject.WidgetName(widgets, "w") == "replacement"
}

test "a dictionary over a user-declared VALUE element widens and reads its field back" {
    points := new Dictionary<string, WideningPoint>()
    points["p"] = new WideningPoint(7)

    assert WideningSubject.PointX(points, "p") == 7

    points["p"] = new WideningPoint(-3)
    assert WideningSubject.PointX(points, "p") == -3
}

test "the pair's own constructor shape binds from concrete collections at every position" {
    shape := new WideningSnapshotShape(
        "/project",
        WideningStringMap("Program.nl", "unit"),
        WideningIntMap("Program.nl", 3),
        WideningOneList("NL301"),
        WideningOneList("Program.nl"),
        WideningStringMap("Program.nl", "func Main() {}"))

    assert shape.Root == "/project"

    unit := ""
    assert shape.Units.TryGetValue("Program.nl", out unit)
    assert unit == "unit"

    model := 0
    assert shape.Models.TryGetValue("Program.nl", out model)
    assert model == 3

    assert shape.Errors[0] == "NL301"
    assert shape.Files[0] == "Program.nl"
    assert shape.Texts["Program.nl"] == "func Main() {}"
}
