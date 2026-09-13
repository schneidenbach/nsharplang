namespace Census.Imports.Left.Nested

import Census.Imports.Left
import Census.Imports.Right


// LEXICAL BEATS IMPORTED, AND IT IS NOT A TIE. This file declares its own `Marker` and imports two
// namespaces that each declare one; the bare name means the file's own, with no diagnostic, because
// a lexically closer declaration is nearer than any import (`SimpleNamePrecedence` rules 1 and 2).
// An ENCLOSING namespace is nearer too, and `Census.Imports.Left` is this file's — which is why the
// import of it is redundant rather than a second candidate.
test "a declaration in the file's own namespace outranks two colliding imports" {
    bare := new Marker()

    assert bare.Side() == "nested"
    assert typeof(Marker).get_Namespace() == "Census.Imports.Left.Nested"
}

test "the imported spellings are still reachable in full from the same file" {
    assert new Census.Imports.Left.Marker().Side() == "left"
    assert new Census.Imports.Right.Marker().Side() == "right"
}
