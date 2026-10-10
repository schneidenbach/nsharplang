namespace Census.Imports.GenericPrecedence

import System.Collections.Generic


// AN EXPLICIT IMPORT OUTRANKS AUTO-DISCOVERY, FOR A GENERIC TYPE AS MUCH AS A PLAIN ONE.
//
// `Census.Imports.Shadow` declares its own `List<T>`; this file sits in a SIBLING namespace and never
// imports it, so the bare
// `List<int>` written here means the one `import System.Collections.Generic` brought in. The generic
// half of that rule used to be unreachable: the guard asked metadata for the DISPLAY name, which is
// the identity with its arity suffix stripped, and no assembly declares a type called `List` — so the
// source class took the name back and `items.Add(1)` reported NL303.
test "an imported CLR generic outranks a project-wide source type of the same spelling" {
    items := new List<int>()
    items.Add(1)
    items.Add(2)

    assert items.Count == 2
    assert items[1] == 2
    assert (typeof(List<int>).get_Namespace() ?? "") == "System.Collections.Generic"
}

test "the shadowed source generic is still reachable by its qualified spelling" {
    shadow := new Census.Imports.Shadow.List<int>()

    assert shadow.Side() == "shadow"
    assert (typeof(Census.Imports.Shadow.List<int>).get_Namespace() ?? "") == "Census.Imports.Shadow"
}
