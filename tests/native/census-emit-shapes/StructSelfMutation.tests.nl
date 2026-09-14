namespace NSharpLang.CensusEmitShapes.Tests

test "a struct method's write to its own field persists in the caller's local" {
    counter := new Counter()
    assert counter.Bump()
    assert counter.Read() == 1
    assert counter.Bump()
    assert counter.Read() == 2
    assert !counter.Bump()
    assert counter.Read() == 3
}

test "the explicit this spelling writes the same storage" {
    counter := new Counter()
    counter.Add(5)
    assert counter.Read() == 5
    counter.Reset()
    assert counter.Read() == 0
}

test "a returned value and the mutation agree, in that order" {
    counter := new Counter()
    assert counter.Add(2) == 2
    assert counter.Add(3) == 5
    assert counter.Read() == 5
}

test "a struct FIELD of a class is mutated in place" {
    holder := new Holder()
    assert holder.BumpTwice() == 2
    assert holder.Counter.Read() == 2
}

test "a struct parameter is this frame's own variable, and copying in is value semantics" {
    counter := new Counter()
    counter.Add(10)
    assert BumpParameter(counter) == 12
    assert counter.Read() == 10
}
