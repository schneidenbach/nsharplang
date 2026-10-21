namespace NSharpLang.MemberLookup.OrdinaryExtensionFallback

class OrdinaryArgumentTarget {
    func M(value: int): string => "instance:" + value.ToString()
}

// A normal typed argument mismatch must reach the same source-extension retry as a typed lambda.
func M(this _target: OrdinaryArgumentTarget, value: string): string => "extension:" + value

func ordinaryArgumentExtensionCall(target: OrdinaryArgumentTarget): string => target.M("x")

func ordinaryArgumentInstanceCall(target: OrdinaryArgumentTarget): string => target.M(7)
