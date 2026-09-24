namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for where a `?.` chain ends.
//
// THE SHAPE THAT MATTERS IS THE CONTINUATION, because it is the one that used to be read as an
// ordinary dereference of a maybe-null value: `a?.B.C` asked about `.C`. A wrong answer here is a
// false NL905 and an un-lifted result — the analyzer describing a program that cannot happen — so
// both directions are pinned: what the walk crosses, and what it deliberately stops at.
//
// A PARENTHESIS IS THE STOP. `(a?.B).C` is a dereference of a maybe-null value in C# too, and not
// walking the parenthesis is what makes the analyzer agree with the emitter's chain-root test,
// which stops at exactly the same node.
func ChainName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 1, 1)
}

func ChainMember(receiver: Expression, name: string, conditional: bool): MemberAccessExpression {
    return new MemberAccessExpression(receiver, name, conditional, 1, 1)
}

func ChainIndex(receiver: Expression, conditional: bool): IndexAccessExpression {
    return new IndexAccessExpression(receiver, new IntLiteralExpression("0", 1, 1), conditional, 1, 1)
}

func ChainCall(callee: Expression): CallExpression {
    return new CallExpression(callee, new List<Argument>(), null, 1, 1)
}

test "a plain member path crosses no guard" {
    access := ChainMember(ChainMember(ChainName("a"), "B", false), "C", false)
    assert !AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(access)
    assert !AnalyzerNullConditionalChainFacts.IsMemberContinuation(access)
}

test "the link that carries the question mark is the guard, not a continuation" {
    guard := ChainMember(ChainName("a"), "B", true)
    assert AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(guard)
    assert !AnalyzerNullConditionalChainFacts.IsMemberContinuation(guard)
}

test "a member written after a guard is a continuation of that chain" {
    continuation := ChainMember(ChainMember(ChainName("a"), "B", true), "C", false)
    assert AnalyzerNullConditionalChainFacts.IsMemberContinuation(continuation)
}

test "an index written after a guard is a continuation of that chain" {
    continuation := ChainIndex(ChainMember(ChainName("a"), "B", true), false)
    assert AnalyzerNullConditionalChainFacts.IsIndexContinuation(continuation)
    assert !AnalyzerNullConditionalChainFacts.IsIndexContinuation(ChainIndex(ChainName("a"), false))
}

test "an index that carries its own question mark is the guard" {
    guard := ChainIndex(ChainName("a"), true)
    assert AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(guard)
    assert !AnalyzerNullConditionalChainFacts.IsIndexContinuation(guard)
}

test "the spine walks through a nested call to reach the guard" {
    callee := ChainMember(ChainCall(ChainMember(ChainMember(ChainName("a"), "B", true), "C", false)), "D", false)
    assert AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(callee)
    assert AnalyzerNullConditionalChainFacts.IsMemberContinuation(callee)
}

test "an invocation whose callee spine crosses a guard is part of the chain" {
    call := ChainCall(ChainMember(ChainName("a"), "Trim", true))
    assert AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(call.Callee)
}

test "a parenthesis ends the chain and the member after it is an ordinary dereference" {
    parenthesised: Expression = new ParenthesizedExpression(ChainMember(ChainName("a"), "B", true), 1, 1)
    access := ChainMember(parenthesised, "C", false)
    assert !AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(access)
    assert !AnalyzerNullConditionalChainFacts.IsMemberContinuation(access)
}

test "an expression with no receiver spine at all crosses nothing" {
    assert !AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(ChainName("a"))
    assert !AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(null)
}
