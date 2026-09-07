namespace NSharpLang.ReflectionEmitBootstrap.Tests

class MethodVisibilityEmitFacts {
    func PascalByConvention(): int {
        return 1
    }

    func camelByConvention(): int {
        return 2
    }

    public func forcedPublic(): int {
        return 3
    }

    private func ForcedPrivate(): int {
        return 4
    }

    internal func InternalInterop(): int {
        return 5
    }

    protected func ProtectedInterop(): int {
        return 6
    }

    private static func PrivateStatic(): int {
        return 7
    }

    func ReadPrivateAndInternal(): int {
        return ForcedPrivate() + camelByConvention() + PrivateStatic()
    }
}

class MethodVisibilityDerivedFacts: MethodVisibilityEmitFacts {
    func ReadProtected(): int {
        return ProtectedInterop()
    }
}

class MethodVisibilityAssemblyPeerFacts {
    func ReadInternal(target: MethodVisibilityEmitFacts): int {
        return target.camelByConvention()
    }
}
