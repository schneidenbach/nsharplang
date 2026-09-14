namespace NSharpLang.CensusInterfaces.Tests

import System.Collections.Generic
import System.Reflection

// WHAT AN INTERFACE'S VALUE MEMBER IS, MEASURED THROUGH THE DISPATCH IT EXISTS FOR.
//
// Before this slice every interface in `InterfaceMembers.nl` declined at `parse.interface` with
// NL103 — the columnar interface scanner knew `func` and `event` and nothing else — so a C#
// interface with a property (`IDocumentState.Uri`, `ITestCase.DisplayName`) could not be written at
// all. Each test below reads the member THROUGH the interface type, because a read through the
// implementer would pass whether or not the slot exists.
test "a value member is read through the interface, from a class that spelled it bare" {
    state: IDocumentState = new DocumentState("file:///a.nl")
    assert ReadUri(state) == "file:///a.nl"
}

test "the same slot is filled by a computed property, and the caller cannot tell" {
    state: IDocumentState = new ComputedState("https", "example.com")
    assert ReadUri(state) == "https://example.com"
}

test "a STRUCT implementer fills the slot, and the boxed receiver answers it" {
    point := new PointState { Uri: "mem://p" }
    boxed: IDocumentState = point
    assert ReadUri(boxed) == "mem://p"
    assert boxed.Touch() == 7
}

test "a value member and a `func` slot live in one interface without disturbing each other" {
    state: IDocumentState = new DocumentState("file:///b.nl")
    assert ReadUriAndTouch(state) == "file:///b.nl#1"
    assert ReadUriAndTouch(state) == "file:///b.nl#2"
}

test "several value members of several types are each their own slot" {
    tags: string[] = ["fast", "unit"]
    testCase: ITestCase = new TestCase("reads a file", 3, false, tags)
    assert Describe(testCase) == "3/False/2"
    assert testCase.Run() == "reads a file:3"
}

test "a BASE interface's value member is inherited by the derived interface's implementers" {
    tags: string[] = []
    testCase: ITestCase = new TestCase("inherited", 1, true, tags)
    // The slot `DisplayName` was declared on `INamed`; the class that declares `ITestCase` fills it,
    // and a caller reads it through the interface that declared it.
    named: INamed = testCase
    assert DescribeAsNamed(named) == "inherited"
    assert named.DisplayName == "inherited"
}

test "a DEFAULT implementation reads the value slot beside it" {
    labelled: ILabelled = new Labelled("core")
    assert DescribeLabelled(labelled) == "<core>"
    assert labelled.Label == "core"
}

test "an interface declaring an EVENT and a VALUE member is filled from one class, at runtime" {
    channel: IChannel = new Channel("alerts")
    assert WatchChannel(channel) == "alerts=2"
}

test "a GENERIC interface's value member is typed by its own parameter" {
    openSlot := must typeof(IBox<int>).GetGenericTypeDefinition().GetProperty("Value")
    assert openSlot.get_PropertyType().get_IsGenericParameter()
    assert (must openSlot.GetGetMethod()).get_IsAbstract()

    // Closing the interface closes the slot with it.
    assert (must typeof(IBox<int>).GetProperty("Value")).get_PropertyType() == typeof(int)
}

test "a DUCK interface's value member is matched structurally and filled like any other" {
    assert ReadShaped(new Tile(4)) == "tile:4"

    // The type that has the `func` and NOT the value member is not a match, so nothing was
    // registered on it — the whole program would have failed to load if it had been.
    unmatched := new Unmatched()
    assert unmatched.Describe() == "unmatched"

    matched := false
    for candidate in typeof(Tile).GetInterfaces() {
        if candidate == typeof(IShaped) {
            matched = true
        }
    }

    assert matched

    for candidate in typeof(Unmatched).GetInterfaces() {
        assert candidate != typeof(IShaped)
    }
}

// ---------------------------------------------------------------------------------------------
// THE METADATA, READ BACK. A slot that reads correctly could still be the wrong metadata — a
// non-virtual method, or no `PropertyInfo` at all — and every other language sees the metadata
// rather than the dispatch.
// ---------------------------------------------------------------------------------------------

func DeclaredFlags(): BindingFlags {
    return BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
}

test "the interface carries a PROPERTY row whose getter is abstract and virtual" {
    declaring := typeof(IDocumentState)
    assert declaring.get_IsInterface()

    property := must declaring.GetProperty("Uri")
    assert property.get_PropertyType() == typeof(string)
    assert property.get_CanRead()

    getter := must property.GetGetMethod()
    assert getter.get_Name() == "get_Uri"
    assert getter.get_IsAbstract()
    assert getter.get_IsVirtual()
    assert getter.GetParameters().Length == 0
    assert getter.get_DeclaringType() == declaring
}

test "an interface's value member is a READ slot — it declares no setter" {
    property := must typeof(IDocumentState).GetProperty("Uri")
    assert !property.get_CanWrite()
    assert property.GetSetMethod() == null
}

test "the bare-field implementer fills the slot with a virtual, final reader over its own field" {
    implementer := typeof(DocumentState)

    getter := must implementer.GetMethod("get_Uri", DeclaredFlags())
    assert getter.get_IsVirtual()
    assert getter.get_IsFinal()
    assert !getter.get_IsAbstract()
    assert getter.get_ReturnType() == typeof(string)

    // THE CLASS'S OWN `Uri` IS STILL A FIELD — that is what its source says, and a second
    // `PropertyInfo` row of the same name would make the name ambiguous to every other language.
    assert implementer.GetField("Uri", DeclaredFlags()) != null
    assert implementer.GetProperty("Uri", DeclaredFlags()) == null
}

test "the accessor-spelling implementer keeps its own property row and fills the slot with it" {
    implementer := typeof(ComputedState)

    property := must implementer.GetProperty("Uri", DeclaredFlags())
    getter := must property.GetGetMethod(true)
    assert getter.get_IsVirtual()
    assert getter.get_IsFinal()
}

test "the interface is the implementer's declared interface, and its map points at the filler" {
    implementer := typeof(DocumentState)
    found := false
    for candidate in implementer.GetInterfaces() {
        if candidate == typeof(IDocumentState) {
            found = true
        }
    }

    assert found

    mapping := implementer.GetInterfaceMap(typeof(IDocumentState))
    matched := 0
    for i := 0; i < mapping.InterfaceMethods.Length; i++ {
        if mapping.InterfaceMethods[i].get_Name() == "get_Uri" {
            matched = matched + 1
            assert mapping.TargetMethods[i].get_Name() == "get_Uri"
            assert mapping.TargetMethods[i].get_DeclaringType() == implementer
        }
    }

    assert matched == 1
}

test "an interface's event and value member each emit their own metadata row" {
    declaring := typeof(IChannel)
    assert declaring.GetEvent("Changed") != null
    assert declaring.GetProperty("Name") != null
    assert declaring.GetProperty("Changed") == null
    assert declaring.GetEvent("Name") == null
}

test "a base interface's slot is declared on the base, and the derived interface inherits it" {
    assert typeof(INamed).GetProperty("DisplayName") != null
    assert typeof(ITestCase).GetProperty("Ordinal") != null

    derived := typeof(ITestCase)
    inheritsNamed := false
    for candidate in derived.GetInterfaces() {
        if candidate == typeof(INamed) {
            inheritsNamed = true
        }
    }

    assert inheritsNamed
}

// A BASE INTERFACE'S MEMBERS, READ THROUGH THE DERIVED INTERFACE'S OWN RECEIVER.
test "a base interface's value member is read through the DERIVED interface, with no cast" {
    entry: IDocumentRecord = new DocumentRecord("k-1", 4, "ada", "/src/a.nl")
    // `Path` is the derived interface's own slot; `Revision` comes from `ITracked`, `Key` from
    // `IIdentified` one level above that, and `Auditor` from the SECOND base in the written list.
    assert ReadThroughDerived(entry) == "/src/a.nl/4/k-1/ada"
}

test "a base interface's `func` slot is called through the DERIVED interface" {
    entry: IDocumentRecord = new DocumentRecord("k-2", 9, "grace", "/src/b.nl")
    assert DescribeThroughDerived(entry) == "k-2@9"
}

test "the same reads work one level up the interface chain" {
    entry: IDocumentRecord = new DocumentRecord("k-3", 1, "linus", "/src/c.nl")
    tracked: ITracked = entry
    assert ReadOneLevelUp(tracked) == "k-3#1"
}

// THE SLOT BELONGS TO THE INTERFACE THAT DECLARED IT, which is the fact a runtime assertion cannot
// see: a derived interface does not re-declare an inherited member, it inherits the row.
test "an inherited interface member is declared once, on the interface that opened it" {
    declared := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly

    assert typeof(IIdentified).GetProperty("Key", declared) != null
    assert typeof(ITracked).GetProperty("Key", declared) == null
    assert typeof(IDocumentRecord).GetProperty("Key", declared) == null

    assert typeof(ITracked).GetProperty("Revision", declared) != null
    assert typeof(IAudited).GetProperty("Auditor", declared) != null
    assert typeof(IDocumentRecord).GetProperty("Path", declared) != null

    assert typeof(IIdentified).GetMethod("Describe", declared) != null
    assert typeof(IDocumentRecord).GetMethod("Describe", declared) == null

    // …and the derived interface really does inherit them, which is what makes the reads above
    // ordinary `callvirt`s on the declaring interface's slot.
    interfaces := typeof(IDocumentRecord).GetInterfaces()
    names := new List<string>()
    for candidate in interfaces {
        names.Add(candidate.Name)
    }
    assert names.Contains("ITracked")
    assert names.Contains("IAudited")
    assert names.Contains("IIdentified")
}

// A CLASS THAT CLOSES A GENERIC SOURCE INTERFACE — the type LOADS, and the slot dispatches.
test "a class closing a generic source interface loads and dispatches through the closed slot" {
    box: IBox<int> = new IntBox(5)
    assert ReadIntBox(box) == "int:5/5"
    assert box.Describe() == "int:5"
    assert box.Value == 5
}

test "a generic class closing the same interface with its OWN parameter loads and dispatches" {
    box: IBox<string> = new GenBox<string>("hi")
    assert ReadStringBox(box) == "gen/hi"
    assert box.Value == "hi"
}

// THE INTERFACE MAP, which is the half a runtime assertion cannot see: ONE implementation per slot,
// bound to the CLOSED interface.
test "the closed generic interface is the one in the implementer's interface map" {
    boxInterfaces := typeof(IntBox).GetInterfaces()
    closed := new List<string>()
    for candidate in boxInterfaces {
        closed.Add(candidate.ToString())
    }
    assert closed.Count == 1
    assert closed[0].Contains("IBox")
    assert closed[0].Contains("Int32")

    map := typeof(IntBox).GetInterfaceMap(boxInterfaces[0])
    assert map.InterfaceMethods.Length == map.TargetMethods.Length
    targets := new List<string>()
    for target in map.TargetMethods {
        targets.Add(target.Name)
    }
    assert targets.Contains("Describe")
    assert targets.Contains("get_Value")
}
