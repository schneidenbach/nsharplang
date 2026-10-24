namespace NSharpLang.MemberLookup.GroupExtensionFallback

test "an overloaded source instance group retries a source extension when no overload applies" {
    target := new OverloadedArgumentTarget()
    assert overloadedArgumentExtensionCall(target) == "overloaded-extension:x"
    assert overloadedArgumentInstanceCall(target) == "instance-int:9"
}
