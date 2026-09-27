namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler


// `[DoesNotReturn]` AS THE DECLARATION PLANNER READS IT — the emit-side half of the same attribute
// the diagnostics pass reads through `ReachabilityFlowFacts`, and the same name-matching rules.
//
// A `MethodBuilder` CANNOT BE ASKED FOR ITS OWN ATTRIBUTES before its owner is baked, so the fact is
// read off the DECLARATION INPUT once, when the member is declared, and carried on the signature
// record every call site already consults. That is the same reason every other signature fact on
// those records is carried rather than reflected.
class ColumnarReachabilityAttributeFacts {

    // THE `[DoesNotReturnIf(b)]` EACH PARAMETER CARRIES, as `ReachabilityFlowFacts` bits and in
    // declaration order. An argument this reader cannot see as the literal `true` or `false`
    // contributes nothing, which is the diagnostics pass's rule for the same attribute.
    static func ParameterDoesNotReturnIf(parameterAttributes: ColumnarSourceAttributeInput[][]?): int[] {
        if parameterAttributes == null {
            return new int[](0)
        }

        result := new int[](parameterAttributes.Length)
        index := 0
        while index < parameterAttributes.Length {
            result[index] = ReadParameterFacts(parameterAttributes[index])
            index = index + 1
        }

        return result
    }

    static func ReadParameterFacts(attributes: ColumnarSourceAttributeInput[]?): int {
        if attributes == null {
            return ReachabilityFlowFacts.None()
        }

        facts := ReachabilityFlowFacts.None()
        index := 0
        while index < attributes.Length {
            attribute := attributes[index]
            index = index + 1
            if !ReachabilityFlowFacts.IsDoesNotReturnIfName(attribute.Name) {
                continue
            }

            texts := attribute.ArgumentTexts
            if texts == null || texts.Length != 1 {
                continue
            }

            literal := texts[0].Trim()
            if literal == "true" {
                facts = facts | ReachabilityFlowFacts.WhenBit(true)
            } else if literal == "false" {
                facts = facts | ReachabilityFlowFacts.WhenBit(false)
            }
        }

        return facts
    }

    static func DeclaresDoesNotReturn(attributes: ColumnarSourceAttributeInput[]?): bool {
        if attributes == null {
            return false
        }

        for attribute in attributes {
            if ReachabilityFlowFacts.IsDoesNotReturnName(attribute.Name) {
                return true
            }
        }

        return false
    }
}
