namespace Census.ExternalTypeReach

test "a forwarded type is constructible and its members read" {
    assert ExternalTypeReachFacts.Host("https://example.com/a/b?x=1") == "example.com"
    assert ExternalTypeReachFacts.PathAndQuery("https://example.com/a/b?x=1") == "/a/b?x=1"
    assert ExternalTypeReachFacts.LocalPath("file:///tmp/probe.nl") == "/tmp/probe.nl"
}

test "a forwarded type is a typed local, including through an out argument" {
    assert ExternalTypeReachFacts.RoundTrip("https://example.com/a") == "https://example.com/a"
    assert ExternalTypeReachFacts.RoundTrip("not a uri") == ""
}

test "a forwarded type answers a static call" {
    assert ExternalTypeReachFacts.Escaped("a b") == "a%20b"
    assert ExternalTypeReachFacts.IsWellFormed("https://example.com/a")
    assert !ExternalTypeReachFacts.IsWellFormed("not a uri")
}

test "a forwarded type is a typeof target" {
    assert ExternalTypeReachFacts.TypeName() == "Uri"
    assert ExternalTypeReachFacts.TypeNamespace() == "System"
}

test "a forwarded enum is a typed local and compares" {
    assert ExternalTypeReachFacts.KindIsAbsolute()
}

test "the rule is about the forwarded assembly, not about one name" {
    assert ExternalTypeReachFacts.BuiltUri("example.com", "/a/b") == "https://example.com/a/b"
    assert ExternalTypeReachFacts.MalformedIsReported("not a uri")
}
