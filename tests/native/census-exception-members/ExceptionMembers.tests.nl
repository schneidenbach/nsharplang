namespace Census.ExceptionMembers

import System

test "an exception property whose type the backend supports is readable, list or no list" {
    error: Exception = new InvalidOperationException("boom")
    assert ExceptionMemberFacts.DataCount(error) == 0
    assert ExceptionMemberFacts.DataIsEmpty(error)
}

test "an aggregate exception's inner collection is readable and indexable" {
    aggregate := ExceptionMemberFacts.Build()
    assert ExceptionMemberFacts.InnerCount(aggregate) == 2
    assert ExceptionMemberFacts.FirstInnerMessage(aggregate) == "first"
}

test "the properties that already read still read" {
    error: Exception = new InvalidOperationException("boom")
    assert ExceptionMemberFacts.Text(error) == "boom"
    assert ExceptionMemberFacts.Code(error) != 0
    assert ExceptionMemberFacts.Origin(error) == null
}
