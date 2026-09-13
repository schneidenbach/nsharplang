namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Native contracts for the ATTRIBUTES THAT SAY WHERE CONTROL GOES, and for the owner that files what
// each call proved.
//
// (1) THE NAMES ARE MATCHED FOUR WAYS, exactly as every other attribute in this compiler is matched:
// the bare name, the `Attribute`-suffixed name, and either of those namespace-qualified. A name that
// merely ENDS with the text is not a match — `MyDoesNotReturn` is somebody else's attribute.
//
// (2) POSITION DECIDES WHICH ATTRIBUTE IS READ. `[DoesNotReturn]` is a METHOD attribute and
// `[DoesNotReturnIf(b)]` a PARAMETER one, and each reader ignores the other's — which is what keeps
// `[DoesNotReturn]` written on a parameter from silently ending every path through the call.
//
// (3) AN ARGUMENT THAT IS NOT A BOOLEAN LITERAL CONTRIBUTES NOTHING. A condition the reader cannot
// see is not one it may invent, and the same rule governs the nullability attributes beside these.
//
// (4) A SIGNATURE WITH NEITHER FACT CLEARS BOTH RATHER THAN LEAVING AN OLDER ONE STANDING, because
// the same call node is re-analysed whenever its file is.
//
// (5) A PARAMETER THAT SOMEHOW CARRIES BOTH POLARITIES GUARDS NOTHING. `[DoesNotReturnIf(true)]` and
// `[DoesNotReturnIf(false)]` together say the call never returns at all, which no surviving flow can
// act on, so no guard is filed.
func ReachabilityAttribute(name: string): AttributeNode {
    return new AttributeNode(name, new List<Argument>())
}

func ReachabilityAttributeWith(name: string, argument: Expression): AttributeNode {
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, argument))
    return new AttributeNode(name, arguments)
}

func ReachabilityAttributeList(attributes: AttributeNode[]): List<AttributeNode> {
    result := new List<AttributeNode>()
    index := 0
    while index < attributes.Length {
        result.Add(attributes[index])
        index = index + 1
    }

    return result
}

func ReachabilityBool(value: bool): Expression {
    literal: Expression = new BoolLiteralExpression(value, 1, 1)
    return literal
}

func ReachabilityCall(name: string, arguments: Expression[]): CallExpression {
    argumentList := new List<Argument>()
    index := 0
    while index < arguments.Length {
        argumentList.Add(new Argument(null, arguments[index]))
        index = index + 1
    }

    return new CallExpression(new IdentifierExpression(name, 1, 1), argumentList, null, 1, 1)
}

test "THE FOUR SPELLINGS OF EACH NAME MATCH AND A LONGER NAME DOES NOT" {
    assert ReachabilityFlowFacts.IsDoesNotReturnName("DoesNotReturn")
    assert ReachabilityFlowFacts.IsDoesNotReturnName("DoesNotReturnAttribute")
    assert ReachabilityFlowFacts.IsDoesNotReturnName("System.Diagnostics.CodeAnalysis.DoesNotReturn")
    assert ReachabilityFlowFacts.IsDoesNotReturnName("System.Diagnostics.CodeAnalysis.DoesNotReturnAttribute")
    assert !ReachabilityFlowFacts.IsDoesNotReturnName("MyDoesNotReturn")
    assert !ReachabilityFlowFacts.IsDoesNotReturnName("DoesNotReturnIf")

    assert ReachabilityFlowFacts.IsDoesNotReturnIfName("DoesNotReturnIf")
    assert ReachabilityFlowFacts.IsDoesNotReturnIfName("DoesNotReturnIfAttribute")
    assert ReachabilityFlowFacts.IsDoesNotReturnIfName("System.Diagnostics.CodeAnalysis.DoesNotReturnIf")
    assert !ReachabilityFlowFacts.IsDoesNotReturnIfName("DoesNotReturn")
}

test "THE METHOD READER SEES ONLY [DoesNotReturn], AND AN ABSENT LIST SAYS NOTHING" {
    none: List<AttributeNode>? = null

    assert ReachabilityFlowFacts.FromSourceMethodAttributes(none) == ReachabilityFlowFacts.None()
    assert ReachabilityFlowFacts.FromSourceMethodAttributes(ReachabilityAttributeList([])) == ReachabilityFlowFacts.None()
    assert ReachabilityFlowFacts.FromSourceMethodAttributes(ReachabilityAttributeList([ReachabilityAttribute("DoesNotReturn")])) == ReachabilityFlowFacts.DoesNotReturn()
    assert ReachabilityFlowFacts.FromSourceMethodAttributes(ReachabilityAttributeList([ReachabilityAttribute("MustUse"), ReachabilityAttribute("DoesNotReturnAttribute")])) == ReachabilityFlowFacts.DoesNotReturn()
    assert ReachabilityFlowFacts.FromSourceMethodAttributes(ReachabilityAttributeList([ReachabilityAttributeWith("DoesNotReturnIf", ReachabilityBool(false))])) == ReachabilityFlowFacts.None()
}

test "THE PARAMETER READER SEES ONLY [DoesNotReturnIf] AND ONLY ITS BOOLEAN LITERAL" {
    none: List<AttributeNode>? = null

    assert ReachabilityFlowFacts.FromSourceParameterAttributes(none) == ReachabilityFlowFacts.None()
    assert ReachabilityFlowFacts.FromSourceParameterAttributes(ReachabilityAttributeList([ReachabilityAttribute("DoesNotReturn")])) == ReachabilityFlowFacts.None()
    assert ReachabilityFlowFacts.FromSourceParameterAttributes(ReachabilityAttributeList([ReachabilityAttributeWith("DoesNotReturnIf", ReachabilityBool(false))])) == ReachabilityFlowFacts.DoesNotReturnIfFalse()
    assert ReachabilityFlowFacts.FromSourceParameterAttributes(ReachabilityAttributeList([ReachabilityAttributeWith("DoesNotReturnIf", ReachabilityBool(true))])) == ReachabilityFlowFacts.DoesNotReturnIfTrue()

    // An argument that is not a literal, and a list with no argument at all, are both unreadable.
    assert ReachabilityFlowFacts.FromSourceParameterAttributes(ReachabilityAttributeList([ReachabilityAttributeWith("DoesNotReturnIf", new IdentifierExpression("flag", 1, 1))])) == ReachabilityFlowFacts.None()
    assert ReachabilityFlowFacts.FromSourceParameterAttributes(ReachabilityAttributeList([ReachabilityAttribute("DoesNotReturnIf")])) == ReachabilityFlowFacts.None()
}

test "THE FILED FACT IS A CALL'S, AND A SIGNATURE WITH NOTHING TO SAY CLEARS IT" {
    calls := new AnalyzerTerminatingCalls()
    call := ReachabilityCall("Fail", [])

    assert !calls.NeverReturns(call)

    calls.Commit(call, ReachabilityFlowFacts.DoesNotReturn(), null, ReachabilityFlowFacts.None())

    assert calls.NeverReturns(call)

    calls.Commit(call, ReachabilityFlowFacts.None(), null, ReachabilityFlowFacts.None())

    assert !calls.NeverReturns(call)
}

test "A PARENTHESISED CALL IS THE SAME CALL, AND ANYTHING THAT IS NOT A CALL ANSWERS NO" {
    calls := new AnalyzerTerminatingCalls()
    call := ReachabilityCall("Fail", [])
    calls.Commit(call, ReachabilityFlowFacts.DoesNotReturn(), null, ReachabilityFlowFacts.None())

    parenthesized: Expression = new ParenthesizedExpression(call, 1, 1)

    assert calls.NeverReturns(parenthesized)
    assert !calls.NeverReturns(new IdentifierExpression("Fail", 1, 1))

    nothing: Expression? = null

    assert !calls.NeverReturns(nothing)
}

test "BEGINNING AN ANALYSIS FORGETS EVERY FACT THE PREVIOUS ONE FILED" {
    calls := new AnalyzerTerminatingCalls()
    call := ReachabilityCall("Fail", [])
    calls.Commit(call, ReachabilityFlowFacts.DoesNotReturn(), null, ReachabilityFlowFacts.None())
    calls.BeginAnalysis()

    assert !calls.NeverReturns(call)
}

test "A GUARD NAMES ITS ARGUMENT AND THE BRANCH THE SURVIVING FLOW IS ON" {
    calls := new AnalyzerTerminatingCalls()
    condition: Expression = new IdentifierExpression("present", 1, 1)
    call := ReachabilityCall("Require", [condition])

    calls.Commit(call, ReachabilityFlowFacts.None(), condition, ReachabilityFlowFacts.DoesNotReturnIfFalse())

    guardArgument: Expression = null
    survivesWhenTrue: bool = false

    assert calls.TryGetGuard(call, out guardArgument, out survivesWhenTrue)
    assert guardArgument == condition
    assert survivesWhenTrue

    calls.Commit(call, ReachabilityFlowFacts.None(), condition, ReachabilityFlowFacts.DoesNotReturnIfTrue())

    assert calls.TryGetGuard(call, out guardArgument, out survivesWhenTrue)
    assert !survivesWhenTrue
}

test "BOTH POLARITIES TOGETHER GUARD NOTHING, AND SO DOES AN ABSENT ARGUMENT" {
    calls := new AnalyzerTerminatingCalls()
    condition: Expression = new IdentifierExpression("present", 1, 1)
    call := ReachabilityCall("Require", [condition])
    both := ReachabilityFlowFacts.DoesNotReturnIfTrue() | ReachabilityFlowFacts.DoesNotReturnIfFalse()

    calls.Commit(call, ReachabilityFlowFacts.None(), condition, both)

    guardArgument: Expression = null
    survivesWhenTrue: bool = false

    assert !calls.TryGetGuard(call, out guardArgument, out survivesWhenTrue)

    calls.Commit(call, ReachabilityFlowFacts.None(), null, ReachabilityFlowFacts.DoesNotReturnIfFalse())

    assert !calls.TryGetGuard(call, out guardArgument, out survivesWhenTrue)
}
