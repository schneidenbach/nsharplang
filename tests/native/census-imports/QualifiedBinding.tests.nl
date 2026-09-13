namespace Census.Imports.Tests

import System
import System.Collections.Generic
import System.Reflection
import Census.Imports.Left
import Census.Imports.Right


// TWO IMPORTS THAT SUPPLY ONE SIMPLE NAME, AND THE SPELLING THAT SETTLES IT.
//
// This file imports both halves of a deliberate collision: `Census.Imports.Left` and
// `Census.Imports.Right` each declare `Marker` and `Box<T>`. A BARE `Marker` here is NL209 — the
// analyzer's contract for that lives beside its owner — and what these assertions execute is the
// other half of the rule: a QUALIFIED spelling names exactly one of the two, in every position, and
// the emitted IL agrees with what the analyzer chose.
//
// The assertions run against real emitted IL, so a resolver that quietly picked the first import
// would fail here rather than in a reading of the diagnostics. Identity is checked twice over: by
// BEHAVIOUR (each type answers its own side) and by CLR METADATA (`typeof(...)` carries the
// declaring namespace), because a wrong binding that happened to agree behaviourally would still be
// the wrong type.
class QualifiedFacts {
    static func NamespaceOf(candidate: Type): string {
        return candidate.get_Namespace() ?? "<global>"
    }
}

test "a qualified spelling binds the type it names when two imports collide" {
    left := new Census.Imports.Left.Marker()
    right := new Census.Imports.Right.Marker()

    assert left.Side() == "left"
    assert right.Side() == "right"
}

test "each qualified spelling carries its own declaring namespace in metadata" {
    leftType: Type = typeof(Census.Imports.Left.Marker)
    rightType: Type = typeof(Census.Imports.Right.Marker)

    assert QualifiedFacts.NamespaceOf(leftType) == "Census.Imports.Left"
    assert QualifiedFacts.NamespaceOf(rightType) == "Census.Imports.Right"
    assert leftType.Name == rightType.Name
    assert leftType.FullName != rightType.FullName
}

test "a qualified generic head and a qualified type argument keep the two apart" {
    leftBox := new Census.Imports.Left.Box<int>()
    rightBox := new Census.Imports.Right.Box<int>()

    assert leftBox.Side() == "left"
    assert rightBox.Side() == "right"

    leftMarkers := new List<Census.Imports.Left.Marker>()
    rightMarkers := new List<Census.Imports.Right.Marker>()
    leftMarkers.Add(new Census.Imports.Left.Marker())
    rightMarkers.Add(new Census.Imports.Right.Marker())

    assert leftMarkers[0].Side() == "left"
    assert rightMarkers[0].Side() == "right"
}

test "a qualified spelling answers is and as against the type it names" {
    leftValue: object = new Census.Imports.Left.Marker()

    assert leftValue is Census.Imports.Left.Marker
    assert !(leftValue is Census.Imports.Right.Marker)
    assert (leftValue as Census.Imports.Right.Marker) == null

    narrowed := leftValue as Census.Imports.Left.Marker
    assert narrowed != null
    assert narrowed.Side() == "left"
}
