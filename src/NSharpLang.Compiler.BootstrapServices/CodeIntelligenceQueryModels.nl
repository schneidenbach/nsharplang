namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

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

    Signature: string => signatureValue
    Documentation: string? => documentationValue
    DefinedIn: string? => definedInValue
    Kind: string => kindValue

    constructor(Signature: string, Documentation: string?, DefinedIn: string?, Kind: string) {
        signatureValue = Signature
        documentationValue = Documentation
        definedInValue = DefinedIn
        kindValue = Kind
    }
}
