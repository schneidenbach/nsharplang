namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler


// THE THREE SORTS OF REFLECTED MEMBER, CARRIED SEPARATELY BECAUSE `MemberInfo` IS NOT A COLUMNAR
// SURFACE. Naming the base class declines the whole assembly at
// `emit.declaration.method-return` — measured, not assumed — and the estate already has this rule:
// `AnalyzerIndexAccess` reaches `GetDefaultMembers()`'s answer "without naming `MemberInfo`" for
// exactly the same reason, and `AnalyzerExpressionStatements` calls `get_Name()` "the estate's
// spelling for a `MemberInfo` name on the columnar surface". So the base class is replaced by the
// three concrete types a member lookup can actually return, and EXACTLY ONE of them is non-null.
//
// The name and the declaring type are read ONCE, at construction, by the owner that did the
// reflecting. That keeps every later reader — the renderer, the hover result — free of reflection
// calls that could throw in a different type universe than the one that resolved the member.
class ReflectedMemberHandle {
    propertyValue: PropertyInfo?
    fieldValue: FieldInfo?
    methodValue: MethodInfo?
    nameValue: string
    declaringTypeValue: string?
    typeOverrideValue: AnalyzerReflectionTypeOverride?
    overloadCountValue: int

    Property: PropertyInfo? => propertyValue
    Field: FieldInfo? => fieldValue
    Method: MethodInfo? => methodValue
    Name: string => nameValue
    DeclaringType: string? => declaringTypeValue

    // NON-NULL EXACTLY WHEN THE MEMBER WAS FOUND ON A GENERIC DEFINITION. A member of
    // `List<WeatherForecast>` is read off `List<>`, because `WeatherForecast` has no CLR type to
    // close over, so every type this member mentions is still written in terms of `T` and has to be
    // mapped back through this before it is shown to anyone.
    TypeOverride: AnalyzerReflectionTypeOverride? => typeOverrideValue

    // How many methods of this name the receiver has. One means the signature shown is the only one.
    OverloadCount: int => overloadCountValue

    constructor(Property: PropertyInfo?, Field: FieldInfo?, Method: MethodInfo?, Name: string, DeclaringType: string?, TypeOverride: AnalyzerReflectionTypeOverride? = null, OverloadCount: int = 1) {
        propertyValue = Property
        fieldValue = Field
        methodValue = Method
        nameValue = Name
        declaringTypeValue = DeclaringType
        typeOverrideValue = TypeOverride
        overloadCountValue = OverloadCount
    }
}

class InspectSummarySymbolResult {
    nameValue: string
    kindValue: string

    Name: string => nameValue
    Kind: string => kindValue

    constructor(Name: string, Kind: string) {
        nameValue = Name
        kindValue = Kind
    }
}

class InspectSummaryTypeResult {
    nameValue: string
    resolvedTypeValue: string
    kindValue: string
    nullabilityValue: string?

    Name: string => nameValue
    ResolvedType: string => resolvedTypeValue
    Kind: string => kindValue
    Nullability: string? => nullabilityValue

    constructor(Name: string, ResolvedType: string, Kind: string, Nullability: string? = null) {
        nameValue = Name
        resolvedTypeValue = ResolvedType
        kindValue = Kind
        nullabilityValue = Nullability
    }
}

class InspectSummaryCompletionsResult {
    contextValue: string
    receiverValue: string?
    receiverTypeValue: string?
    totalCountValue: int
    groupCountsValue: Dictionary<string, int>
    groupsValue: Dictionary<string, string[]>

    Context: string => contextValue
    Receiver: string? => receiverValue
    ReceiverType: string? => receiverTypeValue
    TotalCount: int => totalCountValue
    GroupCounts: Dictionary<string, int> => groupCountsValue
    Groups: Dictionary<string, string[]> => groupsValue

    constructor(Context: string, Receiver: string?, ReceiverType: string?, TotalCount: int, GroupCounts: Dictionary<string, int>, Groups: Dictionary<string, string[]>) {
        contextValue = Context
        receiverValue = Receiver
        receiverTypeValue = ReceiverType
        totalCountValue = TotalCount
        groupCountsValue = GroupCounts
        groupsValue = Groups
    }
}

class HoverResult {
    signatureValue: string
    documentationValue: string?
    definedInValue: string?
    kindValue: string
    declaringTypeValue: string?

    Signature: string => signatureValue
    Documentation: string? => documentationValue
    DefinedIn: string? => definedInValue
    Kind: string => kindValue

    // WHERE A SYMBOL WITH NO FILE COMES FROM. `DefinedIn` is a PATH — it is normalised as one on the
    // way out — so a metadata member's declaring type cannot be carried there without lying about
    // what the field means. It is a fifth, defaulted parameter rather than a second constructor
    // because every existing caller is answering about source, where there is nothing to say.
    DeclaringType: string? => declaringTypeValue

    constructor(Signature: string, Documentation: string?, DefinedIn: string?, Kind: string, DeclaringType: string? = null) {
        signatureValue = Signature
        documentationValue = Documentation
        definedInValue = DefinedIn
        kindValue = Kind
        declaringTypeValue = DeclaringType
    }
}
