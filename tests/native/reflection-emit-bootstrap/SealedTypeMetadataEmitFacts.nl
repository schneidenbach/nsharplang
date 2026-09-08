namespace NSharpLang.ReflectionEmitBootstrap.Tests

sealed class SealedTypeMetadataEmitFacts {
    private sealed class NestedClass {
    }

    private sealed record NestedRecord(Value: int) {
    }
}

class OpenTypeMetadataEmitControl {
}

struct ValueTypeMetadataEmitControl {
    Value: int
}
