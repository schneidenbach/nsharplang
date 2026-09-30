namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// A member a method guarantees is non-null after it returns. `Condition` uses the same 0/true/false
// convention as `NullabilityPostcondition`; this model stays in Compiler.Model so source declarations
// and MetadataLoadContext reflection both feed one parser.
class NullabilityMemberPostcondition {
    MemberName: string
    Condition: int

    constructor(memberName: string, condition: int) {
        MemberName = memberName
        Condition = condition
    }
}

class NullabilityMemberPostconditions {
    static func Always(): int {
        return 0
    }

    static func WhenTrue(): int {
        return 1
    }

    static func WhenFalse(): int {
        return 2
    }

    static func IsMemberNotNullName(name: string): bool {
        return NullabilityFlowFacts.MatchesAttributeName(name, "MemberNotNull")
    }

    static func IsMemberNotNullWhenName(name: string): bool {
        return NullabilityFlowFacts.MatchesAttributeName(name, "MemberNotNullWhen")
    }

    static func FromSourceAttributes(attributes: List<AttributeNode>?): NullabilityMemberPostcondition[] {
        result := new List<NullabilityMemberPostcondition>()
        if attributes == null {
            return result.ToArray()
        }

        for attribute in attributes {
            condition := Always()
            startIndex := 0
            if IsMemberNotNullWhenName(attribute.Name) {
                if attribute.Arguments.Count < 2 {
                    continue
                }

                booleanLiteral := attribute.Arguments[0].Value as BoolLiteralExpression
                if booleanLiteral == null {
                    continue
                }

                condition = WhenFalse()
                if booleanLiteral.Value {
                    condition = WhenTrue()
                }

                startIndex = 1
            } else if !IsMemberNotNullName(attribute.Name) {
                continue
            }

            index := startIndex
            while index < attribute.Arguments.Count {
                literal := attribute.Arguments[index].Value as StringLiteralExpression
                index = index + 1
                if literal != null {
                    memberName := StringLiteralDecoder.Decode(literal.Value, literal.IsRaw)
                    if memberName.Length > 0 {
                        result.Add(new NullabilityMemberPostcondition(memberName, condition))
                    }
                }
            }
        }

        return result.ToArray()
    }

    static func FromReflectionAttributes(attributes: IList<CustomAttributeData>): NullabilityMemberPostcondition[] {
        result := new List<NullabilityMemberPostcondition>()
        falseValue: object = false
        trueValue: object = true
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            index = index + 1
            name := attribute.AttributeType.FullName ?? ""
            isConditional := IsMemberNotNullWhenName(name)
            if !isConditional && !IsMemberNotNullName(name) {
                continue
            }

            constructorArguments := attribute.ConstructorArguments
            argumentCount := NullabilityMetadataReflection.SequenceCount(constructorArguments)
            memberNamesIndex := 0
            condition := Always()
            if isConditional {
                if argumentCount != 2 {
                    continue
                }

                value := constructorArguments.get_Item(0).get_Value()
                if value == null {
                    continue
                }

                boxed: object = value
                if boxed.Equals(trueValue) {
                    condition = WhenTrue()
                } else if boxed.Equals(falseValue) {
                    condition = WhenFalse()
                } else {
                    continue
                }

                memberNamesIndex = 1
            } else if argumentCount != 1 {
                continue
            }

            AddReflectedNames(result, constructorArguments.get_Item(memberNamesIndex), condition)
        }

        return result.ToArray()
    }

    static func AddReflectedNames(result: List<NullabilityMemberPostcondition>, argument: CustomAttributeTypedArgument, condition: int) {
        value := argument.get_Value()
        if value == null {
            return
        }

        single := value as string
        if single != null {
            if single.Length > 0 {
                result.Add(new NullabilityMemberPostcondition(single, condition))
            }
            return
        }

        names := value as IList<CustomAttributeTypedArgument>
        if names == null {
            return
        }

        count := NullabilityMetadataReflection.SequenceCount(value)
        index := 0
        while index < count {
            name := names.get_Item(index).get_Value() as string
            index = index + 1
            if name != null && name.Length > 0 {
                result.Add(new NullabilityMemberPostcondition(name, condition))
            }
        }
    }
}
