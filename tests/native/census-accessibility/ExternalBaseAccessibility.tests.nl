namespace NSharpLang.CensusAccessibility.Tests

import System
import System.Linq.Expressions
import System.Reflection

test "a source type calls its generic external base's protected methods through this and base" {
    collection := new GuardedCollection()
    collection.Add("a")
    collection.Add("b")
    assert collection.Count == 2

    // `Collection<T>.SetItem` is `protected virtual`: named through `this`, it replaces the element.
    collection.ReplaceThroughThis(1, "y")
    assert collection[1] == "y"
    assert collection.Count == 2

    // ...and named with no receiver, which is the same `this.SetItem` written without the word.
    collection.ReplaceWithoutReceiver(0, "x")
    assert collection[0] == "x"
    assert collection.Count == 2

    // `base.InsertItem` is the same member reached through `base`, emitted as a non-virtual call.
    collection.InsertThroughBase(0, "first")
    assert collection.Count == 3
    assert collection[0] == "first"

    collection.ClearThroughBase()
    assert collection.Count == 0
}

test "a protected method of a non-generic external base is callable through this and base" {
    // `TextWriter.Dispose(bool)` is protected; both receiver forms reach it and the writer closes.
    throughThis := new LineAwareWriter()
    throughThis.Write("kept")
    assert throughThis.ToString() == "kept"
    throughThis.ReleaseThroughThis()

    throughBase := new LineAwareWriter()
    throughBase.Write("also kept")
    assert throughBase.ToString() == "also kept"
    throughBase.ReleaseThroughBase()
}

test "a protected property of a generic external base is read through this, base and no receiver" {
    collection := new ReadingCollection()
    collection.Add("alpha")
    collection.Add("beta")

    assert collection.ItemCountThroughThis() == 2
    assert collection.ItemCountThroughBase() == 2
    assert collection.FirstItem() == "alpha"

    // The read is the base's own storage, not a copy: removing through the public surface moves it.
    collection.RemoveAt(0)
    assert collection.ItemCountThroughThis() == 1
    assert collection.FirstItem() == "beta"
}

test "a protected field of a non-generic external base is read at its own array type" {
    writer := new ReadingWriter()

    assert writer.NewLineLengthThroughThis() == Environment.NewLine.Length
    assert writer.NewLineLengthThroughBase() == Environment.NewLine.Length
    assert writer.NewLineFirst() == Environment.NewLine[0]

    // It is the FIELD, so writing the base's own property is observed by the read.
    writer.UseBangTerminator()
    assert writer.NewLineLengthThroughThis() == 1
    assert writer.NewLineFirst() == '!'
}

// THE OVERRIDE REALLY TAKES THE BASE'S SLOT, which is the half a build cannot prove: a member emitted
// into a NEW slot would compile and simply never run. Every call below goes through the base's own
// PUBLIC surface — `Add`, the indexer, `Clear` — so the only way the counters move is if the base
// dispatched to the override.
test "an override of an external base's protected virtual takes its slot" {
    observed := new ObservedCollection()

    observed.Add("a")
    observed.Add("b")
    assert observed.Inserts == 2

    observed[0] = "z"
    assert observed[0] == "z"
    assert observed.Replacements == 1

    observed.Clear()
    assert observed.Clears == 1
    assert observed.Count == 0
}

// THE EMITTED ACCESSIBILITY: the slot's, unless the source said otherwise in so many words.
test "an override takes the accessibility of the member it overrides" {
    declared := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    observedType := typeof(ObservedCollection)

    // No accessibility word written, and a PascalCase name — `protected`, because the base said so.
    setItem := must observedType.GetMethod("SetItem", declared)
    assert setItem.IsFamily
    assert setItem.IsVirtual
    assert !setItem.IsPublic

    // Written `protected`: the same answer, said out loud.
    clearItems := must observedType.GetMethod("ClearItems", declared)
    assert clearItems.IsFamily

    // Written `public`: a widening the CLR permits, and a statement the compiler honours.
    insertItem := must observedType.GetMethod("InsertItem", declared)
    assert insertItem.IsPublic
    assert insertItem.IsVirtual
}

// A SLOT THE DECLARING ASSEMBLY OPENED `protected internal`, TAKEN FROM ANOTHER ASSEMBLY.
test "a protected override of an external protected internal slot compiles, loads and dispatches" {
    visitor := new RecordingVisitor()

    // The visit runs through the CLR's own virtual dispatch inside `ExpressionVisitor.Visit`, so
    // reaching the override at all proves the slot was taken rather than merely named.
    constant: Expression = Expression.Constant(7)
    visited := visitor.Visit(constant)
    assert visited != null
    assert visitor.Constants == 1

    sum: Expression = Expression.Add(Expression.Constant(1), Expression.Constant(2))
    visitor.Visit(sum)
    assert visitor.Constants == 3
    assert visitor.Extensions == 0
}

// THE CLR METADATA, which is the half a runtime assertion cannot see.
test "the override of a cross-assembly protected internal slot is emitted family, and a written protected internal widens it" {
    declared := BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    visitorType := typeof(RecordingVisitor)

    // Written `protected`, and `protected` is exactly what the slot is worth here — so the emitted
    // member is `family`, matching the C# `protected override` this was converted from.
    visitExtension := must visitorType.GetMethod("VisitExtension", declared)
    assert visitExtension.IsFamily
    assert !visitExtension.IsFamilyOrAssembly
    assert visitExtension.IsVirtual
    assert !visitExtension.IsPublic

    // Written `protected internal`: the assembly half is added back on THIS side. The CLR permits
    // it — an override may widen — so the word is honoured rather than corrected.
    visitConstant := must visitorType.GetMethod("VisitConstant", declared)
    assert visitConstant.IsFamilyOrAssembly
    assert !visitConstant.IsFamily
    assert visitConstant.IsVirtual

    // The base's own words are unchanged by any of this: both slots are `famorassem` where they
    // were declared, which is the fact the inherited-accessibility rule reads.
    baseType := must visitorType.BaseType
    assert (must baseType.GetMethod("VisitExtension", declared)).IsFamilyOrAssembly
    assert (must baseType.GetMethod("VisitConstant", declared)).IsFamilyOrAssembly
}
