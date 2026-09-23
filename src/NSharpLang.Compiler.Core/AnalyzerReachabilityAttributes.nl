namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE ATTRIBUTES A SIGNATURE USES TO SAY WHERE CONTROL GOES, as a bit set — the reachability
// companion of `NullabilityFlowFacts`, which says what a signature leaves BEHIND.
//
// A RETURN TYPE SAYS WHAT A CALL PRODUCES; THESE SAY WHETHER IT PRODUCES ANYTHING AT ALL.
// `ThrowHelper.Fail(message)` is declared `void` and never gets there: it always throws, and
// `[DoesNotReturn]` is the only way the signature can say so. `Debug.Assert(condition)` returns only
// when the condition held, which is `[DoesNotReturnIf(false)]` on the parameter — the guard clause
// `if !condition { throw }` written as a call.
//
// THE BITS ARE READ FROM BOTH SIDES OF THE SAME FENCE, exactly as the nullability bits are: a
// reflected member carries them as `CustomAttributeData` and a source-declared one as the
// `AttributeNode`s the parser kept, and one vocabulary is produced from either — so an N# signature
// can say precisely what a BCL signature says.
//
// N# GOES FURTHER THAN C# HERE, DELIBERATELY. C# reads `[DoesNotReturn]` for its nullable analysis
// and still demands a `return` after a call to such a method; N# treats it as what it says — the end
// point of that statement is unreachable — so a function whose last statement is a
// `[DoesNotReturn]` call needs no return after it, and a statement written after one is reported as
// unreachable just as it is after a `throw`. The annotation is a CONTRACT: a method that carries it
// and returns anyway falls out of a body that promised a value, which is why the emitter still
// writes a terminator there.
class ReachabilityFlowFacts {
    static func None(): int {
        return 0
    }

    // The call never returns, however it turns out.
    static func DoesNotReturn(): int {
        return 1
    }

    // The call never returns when this argument is TRUE.
    static func DoesNotReturnIfTrue(): int {
        return 2
    }

    // The call never returns when this argument is FALSE.
    static func DoesNotReturnIfFalse(): int {
        return 4
    }

    static func Has(facts: int, bit: int): bool {
        return (facts & bit) != 0
    }

    static func WhenBit(whenTrue: bool): int {
        if whenTrue {
            return DoesNotReturnIfTrue()
        }

        return DoesNotReturnIfFalse()
    }

    // THE NAMES, MATCHED THE WAY EVERY OTHER ATTRIBUTE IN THIS COMPILER IS MATCHED: the bare name,
    // the `Attribute`-suffixed name, and either of those namespace-qualified.
    static func IsDoesNotReturnName(name: string): bool {
        return NullabilityFlowFacts.MatchesAttributeName(name, "DoesNotReturn")
    }

    static func IsDoesNotReturnIfName(name: string): bool {
        return NullabilityFlowFacts.MatchesAttributeName(name, "DoesNotReturnIf")
    }

    // The facts a SOURCE declaration's own attribute list carries. `[DoesNotReturnIf]` is a
    // PARAMETER attribute and is not read here; a `[DoesNotReturn]` written on a parameter is not
    // read either, because each attribute means something only where its own `AttributeUsage` puts it.
    static func FromSourceMethodAttributes(attributes: List<AttributeNode>?): int {
        if attributes == null {
            return None()
        }

        for attribute in attributes {
            if IsDoesNotReturnName(attribute.Name) {
                return DoesNotReturn()
            }
        }

        return None()
    }

    // The facts a SOURCE parameter's attribute list carries. An attribute whose boolean argument is
    // not a literal contributes nothing: a condition this reader cannot see is not one it may invent.
    static func FromSourceParameterAttributes(attributes: List<AttributeNode>?): int {
        if attributes == null {
            return None()
        }

        facts := None()
        index := 0
        while index < attributes.Count {
            attribute := attributes[index]
            index = index + 1
            if !IsDoesNotReturnIfName(attribute.Name) {
                continue
            }

            literal: bool = false
            if NullabilityFlowFacts.TryReadSourceBooleanArgument(attribute, out literal) {
                facts = facts | WhenBit(literal)
            }
        }

        return facts
    }
}

// The reflection half of the same reader, separate for the reason the nullability one is separate:
// everything above is a pure function of names and literals, and everything here touches
// `CustomAttributeData`, whose `Count` lives on a non-generic interface and whose boolean argument
// arrives BOXED — under a MetadataLoadContext the argument's own type is a projected
// `System.Boolean` that is not `typeof(bool)`, so the value is compared against a boxed constant.
class ReachabilityFlowAttributeReflection {
    static func FromMethodAttributes(attributes: IList<CustomAttributeData>): int {
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            if ReachabilityFlowFacts.IsDoesNotReturnName(attributes.get_Item(index).AttributeType.FullName ?? "") {
                return ReachabilityFlowFacts.DoesNotReturn()
            }

            index = index + 1
        }

        return ReachabilityFlowFacts.None()
    }

    static func FromParameter(parameter: ParameterInfo): int {
        return FromParameterAttributes(parameter.GetCustomAttributesData())
    }

    static func FromParameterAttributes(attributes: IList<CustomAttributeData>): int {
        facts := ReachabilityFlowFacts.None()
        falseValue: object = false
        trueValue: object = true
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            index = index + 1
            if !ReachabilityFlowFacts.IsDoesNotReturnIfName(attribute.AttributeType.FullName ?? "") {
                continue
            }

            constructorArguments := attribute.ConstructorArguments
            if NullabilityMetadataReflection.SequenceCount(constructorArguments) != 1 {
                continue
            }

            argumentValue := constructorArguments.get_Item(0).get_Value()
            if argumentValue == null {
                continue
            }

            boxedValue: object = argumentValue
            if boxedValue.Equals(trueValue) {
                facts = facts | ReachabilityFlowFacts.WhenBit(true)
            } else if boxedValue.Equals(falseValue) {
                facts = facts | ReachabilityFlowFacts.WhenBit(false)
            }
        }

        return facts
    }
}
