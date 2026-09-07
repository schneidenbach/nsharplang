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
}
