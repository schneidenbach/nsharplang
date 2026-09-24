namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence


// THE WHERE-AM-I QUESTION A SOURCE-DECLARED EVENT ASKS, pinned on its own.
//
// `event Changed: EventHandler` resolves to TWO different things, and which one a position gets is
// decided by exactly one predicate. Inside the declaring type the name IS the backing delegate, so
// `Changed?.Invoke(this, args)` and `Changed != null` read; everywhere else it is the EVENT, which
// has no value at all and admits only `on` / `off`. Getting this predicate wrong in either direction
// is a silent correctness failure — too permissive and a caller writes another type's private field,
// too strict and the declaring type cannot raise its own event — so it is pinned here rather than
// only through the behaviour it drives.
func SourceEventFactsClass(name: string): TypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
}

func SourceEventFactsStruct(name: string): TypeInfo {
    return new StructTypeInfo(name, 1, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

func SourceEventFactsRecord(name: string, isStruct: bool): TypeInfo {
    return new RecordTypeInfo(name, 1, 1, isStruct, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

test "the declaring type's name comes off whichever source shape declared the event" {
    assert SourceEventFacts.DeclaringTypeName(SourceEventFactsClass("Widget")) == "Widget"
    assert SourceEventFacts.DeclaringTypeName(SourceEventFactsStruct("Gauge")) == "Gauge"
    assert SourceEventFacts.DeclaringTypeName(SourceEventFactsRecord("Reading", false)) == "Reading"
    assert SourceEventFacts.DeclaringTypeName(BuiltInTypes.Int) == ""
    assert SourceEventFacts.DeclaringTypeName(null) == ""
}

// A VALUE TYPE IS THE ONE SHAPE `on` CANNOT BIND AN INSTANCE EVENT THROUGH, because the receiver it
// would subscribe to is a COPY. A record is one or the other depending on how it was declared.
test "a value declaring type is recognised, including a record struct" {
    assert !SourceEventFacts.DeclaringTypeIsValueType(SourceEventFactsClass("Widget"))
    assert SourceEventFacts.DeclaringTypeIsValueType(SourceEventFactsStruct("Gauge"))
    assert !SourceEventFacts.DeclaringTypeIsValueType(SourceEventFactsRecord("Reading", false))
    assert SourceEventFacts.DeclaringTypeIsValueType(SourceEventFactsRecord("Reading", true))
    assert !SourceEventFacts.DeclaringTypeIsValueType(null)
}

test "the declaring type's own code is inside, and a qualified ambient name is the same type" {
    owner := SourceEventFactsClass("Widget")
    assert SourceEventFacts.IsInsideDeclaringType(owner, "Widget")
    assert SourceEventFacts.IsInsideDeclaringType(owner, "App.Widget")
    assert SourceEventFacts.IsInsideDeclaringType(owner, "App.Nested.Widget")
}

// C#'S RULE, KEPT. A DERIVED type is OUTSIDE: it subscribes like any other caller and raises through
// a method the base declared for that purpose. Nothing here consults a base chain, and that absence
// is the contract rather than an omission.
test "every other type is outside, derived types included" {
    owner := SourceEventFactsClass("Widget")
    assert !SourceEventFacts.IsInsideDeclaringType(owner, "LabelledWidget")
    assert !SourceEventFacts.IsInsideDeclaringType(owner, "WidgetFactory")
    assert !SourceEventFacts.IsInsideDeclaringType(owner, "App.WidgetView")
    assert !SourceEventFacts.IsInsideDeclaringType(owner, "")
    assert !SourceEventFacts.IsInsideDeclaringType(owner, null)
    assert !SourceEventFacts.IsInsideDeclaringType(BuiltInTypes.Int, "Widget")
}

// The event's own rendering is what hover and `nlc query` read back, and it is deliberately the word
// `event` rather than the delegate's name: the delegate is not what the reader may write there.
test "a source event renders as the event it is, and carries its handler type" {
    handler: TypeInfo = BuiltInTypes.String
    sourceEvent := new SourceEventInfo("Changed", "Widget", handler, false)
    assert sourceEvent.Name == "Changed"
    assert sourceEvent.DeclaringTypeName == "Widget"
    assert !sourceEvent.DeclaringTypeIsValueType
    assert (sourceEvent as object).ToString() == "event Changed"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(sourceEvent) == "event"
}
