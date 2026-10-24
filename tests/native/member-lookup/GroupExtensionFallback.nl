namespace NSharpLang.MemberLookup.GroupExtensionFallback

class OverloadedArgumentTarget {
    func M(value: int): string => "instance-int:" + value.ToString()

    func M(value: bool): string => "instance-bool:" + value.ToString()
}

// This separate namespace gives the emitter one in-scope source extension named M, so the runtime
// check exercises extension fallback after the source instance overload group rejects its argument.
func M(this _target: OverloadedArgumentTarget, value: string): string => "overloaded-extension:" + value

func overloadedArgumentExtensionCall(target: OverloadedArgumentTarget): string => target.M("x")

func overloadedArgumentInstanceCall(target: OverloadedArgumentTarget): string => target.M(9)
