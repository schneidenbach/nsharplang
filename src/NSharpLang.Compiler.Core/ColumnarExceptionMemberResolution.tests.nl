namespace NSharpLang.Compiler.Columnar

import System
import System.IO
import System.Reflection


// EVERY READABLE PROPERTY OF AN EXCEPTION, NOT A LIST OF NAMES.
//
// `Message` used to be the single modelled member of the whole exception hierarchy — not because it
// was different from the rest, but because it was the one that had been needed. `ex.ParamName`, the
// property that says WHICH argument was null and the entire reason `ArgumentNullException` carries a
// name, declined at emit; so did `StackTrace`, `Source`, and every property a derived or
// package-supplied exception type adds.
//
// The receiver's OWN type is now asked, through the same admitted-property lookup that already
// served `DateTime` and the SDK task types. These pin WHICH member was selected, not merely that one
// was: the declaring type of the selected getter is the handle the emitted `callvirt` names.
func ExceptionMemberIsSelected(receiverType: Type, member: string): bool {
    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    return ColumnarRuntimeInstanceMemberResolver.TrySelect(receiverType, member, out selection)
}

// The type that DECLARES the getter the resolver chose. Two `MethodInfo`s for one method differ when
// their `ReflectedType`s differ, so the declaring type is what identifies the member — and it is
// exactly what the emitted `callvirt` names.
func ExceptionMemberOwner(receiverType: Type, member: string): Type {
    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    if !ColumnarRuntimeInstanceMemberResolver.TrySelect(receiverType, member, out selection) {
        throw new InvalidOperationException("'" + receiverType.Name + "." + member + "' was not selected.")
    }

    getter := selection.Getter
    if getter == null {
        throw new InvalidOperationException("'" + receiverType.Name + "." + member + "' selected no getter.")
    }

    owner := getter.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("'" + receiverType.Name + "." + member + "' selected a getter with no owner.")
    }

    return owner
}

test "Message is still selected, and its getter is Exception's own" {
    assert ExceptionMemberOwner(typeof(Exception), "Message") == typeof(Exception)
}

test "an argument exception's parameter name is selected from the type that declares it" {
    // `ParamName` is declared by `ArgumentException`, the BASE of `ArgumentNullException`. A lookup
    // that asked `Exception` — which is what the single modelled name did — would never reach it.
    assert ExceptionMemberIsSelected(typeof(ArgumentNullException), "ParamName")
    assert ExceptionMemberOwner(typeof(ArgumentNullException), "ParamName") == typeof(ArgumentException)
}

test "the other properties every exception carries are selected too" {
    assert ExceptionMemberOwner(typeof(Exception), "StackTrace") == typeof(Exception)
    assert ExceptionMemberOwner(typeof(Exception), "Source") == typeof(Exception)
}

test "a property a DERIVED exception declares is selected from the derived receiver" {
    assert ExceptionMemberOwner(typeof(FileNotFoundException), "FileName") == typeof(FileNotFoundException)
}

test "the base type's own declaration is selected when the derived type does not replace it" {
    // `ArgumentNullException` inherits `ParamName` unchanged, so the declaration selected is
    // `ArgumentException`'s. `InvalidOperationException` adds nothing at all, so `Message` is
    // `Exception`'s.
    assert ExceptionMemberOwner(typeof(ArgumentNullException), "StackTrace") == typeof(Exception)
    assert ExceptionMemberOwner(typeof(InvalidOperationException), "Message") == typeof(Exception)
}

test "an override is selected in preference to the declaration it replaces" {
    // `ArgumentException` and `FileNotFoundException` both OVERRIDE `Message` — that is how the
    // parameter name and the file name reach the text. Naming the override is what C# emits for a
    // receiver of that static type, and it is what the old `Exception`-rooted lookup could not do.
    assert ExceptionMemberOwner(typeof(ArgumentException), "Message") == typeof(ArgumentException)
    assert ExceptionMemberOwner(typeof(FileNotFoundException), "Message") == typeof(FileNotFoundException)
}

test "a member no exception declares is still not selected" {
    // Widening to ordinary resolution is not widening to anything at all: a name the type does not
    // declare must still decline.
    assert !ExceptionMemberIsSelected(typeof(Exception), "NoSuchProperty")
    assert !ExceptionMemberIsSelected(typeof(ArgumentNullException), "FileName")
}
