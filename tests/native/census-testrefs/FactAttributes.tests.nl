namespace NSharpLang.CensusTestRefs

import System
import Xunit

// THE ATTRIBUTES ARE DECLARED HERE AND WRITTEN IN THE OTHER FILE, WHICH IS THE POINT.
//
// A source attribute class used to be looked up in the analyzer's scope stack alone, so one declared
// in a sibling file reported "Attribute type 'SlowFact' not found" even though a `func Make():
// SlowFactAttribute` on the next line resolved. Both attribute families below are written from
// `TestRefs.tests.nl`.
//
// They also derive from `Xunit.FactAttribute`, which the compiler can only see once the test
// reference set resolves to assemblies that EXIST: `xunit` is a metapackage that ships no dll, and
// `xunit.core.dll` lives in a package called `xunit.extensibility.core`.

// A fact-derived attribute that says nothing extra: a test carrying it is an ordinary test.
sealed class SlowFactAttribute: FactAttribute {
    public constructor() {
    }
}

// A fact-derived attribute that sets `Skip` — the property its EXTERNAL base declares. Writing it
// from a source constructor is the write half of inherited-external member access.
sealed class UnavailableFactAttribute: FactAttribute {
    public constructor() {
        Skip = "the census fixture declares this prerequisite unavailable"
    }
}

// The same write spelled with an explicit `this`, so both spellings are pinned.
sealed class ExplicitSkipFactAttribute: FactAttribute {
    public constructor() {
        this.Skip = "written through an explicit this"
    }
}

// An ordinary source attribute that has nothing to do with tests, so the cross-file binding rule is
// pinned independently of the test framework.
sealed class MarkerAttribute: Attribute {
    Note: string

    public constructor(note: string) {
        Note = note
    }
}
