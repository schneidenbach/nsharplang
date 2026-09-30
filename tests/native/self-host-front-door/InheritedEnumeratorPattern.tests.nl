namespace NSharpLang.SelfHostFrontDoor

import System
import System.Collections.Generic
import System.Collections.ObjectModel

test "a foreach over a collection whose GetEnumerator is inherited iterates every element" {
    rows := InheritedEnumeratorPattern.Rows()
    assert InheritedEnumeratorPattern.SumValues(rows) == 12
    assert InheritedEnumeratorPattern.JoinLabels(rows) == "two,three,seven"
}

test "the same inherited pattern rebinds through a second base type" {
    rows := InheritedEnumeratorPattern.Rows()
    assert InheritedEnumeratorPattern.SumReadOnly(rows) == 12
}

test "an emitted loop over an inherited pattern reads whatever the collection holds" {
    longer := new List<Row>()
    longer.Add(new Row(2, "two"))
    longer.Add(new Row(3, "three"))
    longer.Add(new Row(7, "seven"))
    longer.Add(new Row(10, "ten"))
    rows := InheritedEnumeratorPattern.RowsOf(longer)
    assert InheritedEnumeratorPattern.SumValues(rows) == 22
    assert InheritedEnumeratorPattern.JoinLabels(rows) == "two,three,seven,ten"

    empty := InheritedEnumeratorPattern.RowsOf(new List<Row>())
    assert InheritedEnumeratorPattern.SumValues(empty) == 0
    assert InheritedEnumeratorPattern.JoinLabels(empty) == ""
}

// WHY THE REBIND NEEDED FIXING, stated as the reflection fact the code generator has to respect.
// `TypeBuilder.GetMethod` is the only legal member resolution on a construction over a type this
// assembly is still building, and it refuses any method whose declaring type is not the generic type
// DEFINITION. An inherited method never satisfies that on its own.
test "reflection answers an inherited generic method on a constructed owner, not on the definition" {
    observableDefinition := typeof(ObservableCollection<int>).GetGenericTypeDefinition()
    inherited := observableDefinition.GetMethod("GetEnumerator", new Type[](0))
    assert inherited != null
    declaring := inherited.get_DeclaringType()
    assert declaring != null
    assert declaring.get_IsGenericType()
    assert !declaring.get_IsGenericTypeDefinition()
    assert declaring.get_ContainsGenericParameters()
    assert declaring.GetGenericTypeDefinition() == typeof(Collection<int>).GetGenericTypeDefinition()
}

test "the emitted loop body reads the element type the collection declares" {
    method := typeof(InheritedEnumeratorPattern).GetMethod("SumValues")
    assert method != null
    parameters := method.GetParameters()
    assert parameters.Length == 1
    parameterType := parameters[0].get_ParameterType()
    assert parameterType.get_IsGenericType()
    assert parameterType.GetGenericTypeDefinition() == typeof(ObservableCollection<int>).GetGenericTypeDefinition()
    assert parameterType.GetGenericArguments()[0] == typeof(Row)
    assert method.get_ReturnType() == typeof(int)
}
