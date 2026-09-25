namespace Census.ExternalNullableMembers

import NSharpLang.Compiler
import Xunit

test "a C#-emitted bool? property starts unset and reads back as a nullable, not a bool" {
    config := new TestAssemblyConfiguration()
    assert ExternalNullableMemberFacts.ShadowCopyIsUnset(config)
}

test "a plain bool stores into a C#-emitted bool? property" {
    config := new TestAssemblyConfiguration()
    ExternalNullableMemberFacts.SetShadowCopy(config, true)
    assert !ExternalNullableMemberFacts.ShadowCopyIsUnset(config)
    assert ExternalNullableMemberFacts.ShadowCopyValue(config)
    ExternalNullableMemberFacts.SetShadowCopy(config, false)
    assert !ExternalNullableMemberFacts.ShadowCopyValue(config)
}

test "null stores into a C#-emitted bool? property" {
    config := new TestAssemblyConfiguration()
    ExternalNullableMemberFacts.SetShadowCopy(config, true)
    ExternalNullableMemberFacts.ClearShadowCopy(config)
    assert ExternalNullableMemberFacts.ShadowCopyIsUnset(config)
}

test "an already-lifted bool? still stores into the same property" {
    config := new TestAssemblyConfiguration()
    lifted: bool? = true
    ExternalNullableMemberFacts.SetShadowCopyLifted(config, lifted)
    assert ExternalNullableMemberFacts.ShadowCopyValue(config)
    ExternalNullableMemberFacts.SetShadowCopyLifted(config, null)
    assert ExternalNullableMemberFacts.ShadowCopyIsUnset(config)
}

test "a plain int stores into a C#-emitted int? property" {
    config := new TestAssemblyConfiguration()
    ExternalNullableMemberFacts.SetMaxParallelThreads(config, 7)
    assert ExternalNullableMemberFacts.MaxParallelThreadsValue(config) == 7
}

test "the stored value is evaluated exactly once, through a chain hop" {
    holder := new ConfigurationHolder(new TestAssemblyConfiguration())
    ExternalNullableMemberFacts.ResetCounters()
    ExternalNullableMemberFacts.SetShadowCopyThroughHolder(holder, true)
    assert ExternalNullableMemberFacts.ValueReadCount() == 1
    assert ExternalNullableMemberFacts.ShadowCopyValue(holder.Config)
}

test "a plain int stores into an N#-emitted int? field in another assembly" {
    signature := new FunctionTypeInfo()
    assert ExternalNullableMemberFacts.RequiredParameterCountIsUnset(signature)
    ExternalNullableMemberFacts.SetRequiredParameterCount(signature, 3)
    assert !ExternalNullableMemberFacts.RequiredParameterCountIsUnset(signature)
    assert ExternalNullableMemberFacts.RequiredParameterCountValue(signature) == 3
}

test "null stores into an N#-emitted int? field in another assembly" {
    signature := new FunctionTypeInfo()
    ExternalNullableMemberFacts.SetRequiredParameterCount(signature, 3)
    ExternalNullableMemberFacts.ClearRequiredParameterCount(signature)
    assert ExternalNullableMemberFacts.RequiredParameterCountIsUnset(signature)
}
