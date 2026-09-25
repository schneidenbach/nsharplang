namespace Census.ExternalNullableMembers

import NSharpLang.Compiler
import Xunit


// A HOLDER WHOSE FIELD IS THE EXTERNAL RECEIVER, so the write reaches its target through a chain hop
// rather than straight off a parameter.
class ConfigurationHolder {
    Config: TestAssemblyConfiguration

    constructor(config: TestAssemblyConfiguration) {
        Config = config
    }
}

// WRITING A `Nullable<T>` MEMBER THAT LIVES IN ANOTHER ASSEMBLY.
//
// A member's PROVENANCE decides which instruction stores it — `stfld` for a field, a `set_X` call for
// a property — and never which values may be stored. These helpers write the same three things a
// same-compilation member already accepted (an underlying value, `null`, and an already-lifted
// value) through a C#-emitted property (`Xunit.TestAssemblyConfiguration`, the shape the N# test
// runner host has to write) and an N#-emitted field (`FunctionTypeInfo.RequiredParameterCount`).
class ExternalNullableMemberFacts {
    static valueReads: int = 0

    static func ResetCounters(): void {
        valueReads = 0
    }

    static func ValueReadCount(): int {
        return valueReads
    }

    // A VALUE THAT COUNTS ITS OWN EVALUATIONS, so a store can be asserted to evaluate it once.
    static func CountedFlag(value: bool): bool {
        valueReads = valueReads + 1
        return value
    }

    // A C#-EMITTED `bool?` PROPERTY, written with a plain `bool`.
    static func SetShadowCopy(config: TestAssemblyConfiguration, value: bool): void {
        config.ShadowCopy = value
    }

    // The same property, written with `null`.
    static func ClearShadowCopy(config: TestAssemblyConfiguration): void {
        config.ShadowCopy = null
    }

    // The same property, written with a value that is ALREADY `bool?` — the one shape that emitted
    // before this seam was shared, kept as the control.
    static func SetShadowCopyLifted(config: TestAssemblyConfiguration, value: bool?): void {
        config.ShadowCopy = value
    }

    // A C#-EMITTED `int?` PROPERTY, written with a plain `int`.
    static func SetMaxParallelThreads(config: TestAssemblyConfiguration, value: int): void {
        config.MaxParallelThreads = value
    }

    // THE SAME WRITE THROUGH A CHAIN HOP, with a value that counts its own evaluations.
    static func SetShadowCopyThroughHolder(holder: ConfigurationHolder, value: bool): void {
        holder.Config.ShadowCopy = CountedFlag(value)
    }

    static func ShadowCopyIsUnset(config: TestAssemblyConfiguration): bool {
        return config.ShadowCopy == null
    }

    static func ShadowCopyValue(config: TestAssemblyConfiguration): bool {
        return must config.ShadowCopy
    }

    static func MaxParallelThreadsValue(config: TestAssemblyConfiguration): int {
        return must config.MaxParallelThreads
    }

    // AN N#-EMITTED `int?` FIELD in a referenced assembly, written with a plain `int` and with `null`.
    static func SetRequiredParameterCount(signature: FunctionTypeInfo, value: int): void {
        signature.RequiredParameterCount = value
    }

    static func ClearRequiredParameterCount(signature: FunctionTypeInfo): void {
        signature.RequiredParameterCount = null
    }

    static func RequiredParameterCountIsUnset(signature: FunctionTypeInfo): bool {
        return signature.RequiredParameterCount == null
    }

    static func RequiredParameterCountValue(signature: FunctionTypeInfo): int {
        return must signature.RequiredParameterCount
    }
}
