namespace NSharpLang.AssertThrowsSourceTypes.Other

import System

class OtherNamespaceException: Exception {
    constructor(m: string): base(m) {}
}

func ThrowOther() {
    throw new OtherNamespaceException("other")
}
