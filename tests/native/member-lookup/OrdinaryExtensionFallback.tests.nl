namespace NSharpLang.MemberLookup.OrdinaryExtensionFallback

test "an ordinary argument mismatch retries a source extension and keeps the instance winner" {
    target := new OrdinaryArgumentTarget()
    assert ordinaryArgumentExtensionCall(target) == "extension:x"
    assert ordinaryArgumentInstanceCall(target) == "instance:7"
}
