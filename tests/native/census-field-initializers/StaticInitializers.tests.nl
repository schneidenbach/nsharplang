namespace NSharpLang.CensusFieldInitializers.Tests

import System.Reflection
import System.Runtime.CompilerServices

test "a static readonly field of enum type accepts a member access and a binary expression over two members" {
    assert RuntimeHotPath.Inlining == MethodImplOptions.AggressiveInlining
    assert RuntimeHotPath.HotPathImpl == (MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)
    // AggressiveInlining is 256 and AggressiveOptimization is 512, so the combined value is the
    // arithmetic OR the initializer computed rather than either member alone.
    assert (int)RuntimeHotPath.HotPathImpl == 768
    assert (int)RuntimeHotPath.Inlining == 256
}

test "every census static initializer shape produces its value at runtime" {
    assert CensusStatics.Limit == 2147483647
    assert CensusStatics.Negative == -1
    assert CensusStatics.Names != null
    assert CensusStatics.Names.Count == 0
    assert CensusStatics.None == null
    assert CensusStatics.Sum == 7
    assert CensusStatics.Label == "ab"
    assert CensusStatics.Seed == 8
    assert CensusStatics.Mutable == 10
}

test "static initializers run once, in textual order, and each sees the earlier field's value" {
    assert OrderedStatics.First == 1
    assert OrderedStatics.Second == 2
    assert OrderedStatics.Third == 3
    assert OrderedStatics.Trace == "first;second;third;"
}

test "a static initializer that reads a later static field sees that field's default" {
    assert ForwardReadingStatics.Later == 7
    assert ForwardReadingStatics.Early == 5
}

test "a const field keeps its compile-time value and needs no type initializer" {
    assert ConstantStatics.Read() == 7
    assert typeof(ConstantStatics).TypeInitializer == null
}

test "static storage on a generic type belongs to the instantiation" {
    assert PerInstantiation<int>.Bump() == 101
    assert PerInstantiation<int>.Bump() == 102
    assert PerInstantiation<string>.Bump() == 101
    assert PerInstantiation<int>.Count == 102
    assert PerInstantiation<string>.Count == 101
}

test "a static readonly field is initonly in metadata and a mutable static field is not" {
    limitField := typeof(CensusStatics).GetField("Limit", BindingFlags.Public | BindingFlags.Static)
    mutableField := typeof(CensusStatics).GetField("Mutable", BindingFlags.Public | BindingFlags.Static)
    assert limitField != null, "the static readonly field Limit must be present"
    assert mutableField != null, "the mutable static field Mutable must be present"
    if limitField != null {
        assert limitField.get_IsInitOnly(), "a static readonly field must be emitted initonly"
        assert limitField.get_IsStatic()
    }
    if mutableField != null {
        assert !mutableField.get_IsInitOnly(), "a mutable static field must not be emitted initonly"
    }
}

test "a const field is a literal with a compile-time constant, not a stored field" {
    constField := typeof(ConstantStatics).GetField("Limit", BindingFlags.Public | BindingFlags.Static)
    assert constField != null, "the const field Limit must be present"
    if constField != null {
        assert constField.get_IsLiteral(), "a const field must be emitted as a literal"
        constValue := constField.GetRawConstantValue()
        assert constValue != null
        if constValue != null {
            assert constValue.ToString() == "7"
        }
    }
}

test "a type with static field initializers has a type initializer and one without has none" {
    assert typeof(CensusStatics).TypeInitializer != null
    assert typeof(RuntimeHotPath).TypeInitializer != null
    assert typeof(NoStaticInitializers).TypeInitializer == null
}

test "every emitted source type carries beforefieldinit, matching a C# type with no static constructor" {
    assert (typeof(CensusStatics).Attributes & TypeAttributes.BeforeFieldInit) == TypeAttributes.BeforeFieldInit
    assert (typeof(NoStaticInitializers).Attributes & TypeAttributes.BeforeFieldInit) == TypeAttributes.BeforeFieldInit
    assert (typeof(InstanceCensus).Attributes & TypeAttributes.BeforeFieldInit) == TypeAttributes.BeforeFieldInit
}
