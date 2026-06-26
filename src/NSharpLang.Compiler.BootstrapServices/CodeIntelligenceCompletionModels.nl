namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

public class CompletionItem {
    nameValue: string
    kindValue: string
    typeValue: string?
    parametersValue: string?
    documentationValue: string?
    isStaticValue: bool

    Name: string => nameValue
    Kind: string => kindValue
    Type: string? => typeValue
    Parameters: string? => parametersValue
    Documentation: string? => documentationValue
    IsStatic: bool => isStaticValue

    constructor(Name: string, Kind: string, Type: string?, Parameters: string?, Documentation: string?, IsStatic: bool) {
        nameValue = Name
        kindValue = Kind
        typeValue = Type
        parametersValue = Parameters
        documentationValue = Documentation
        isStaticValue = IsStatic
    }
}

public class CompletionResult {
    contextValue: CompletionContext
    receiverValue: string?
    receiverTypeValue: string?
    completionsValue: Dictionary<string, List<CompletionItem>>

    Context: CompletionContext => contextValue
    Receiver: string? => receiverValue
    ReceiverType: string? => receiverTypeValue
    Completions: Dictionary<string, List<CompletionItem>> => completionsValue

    constructor(
        Context: CompletionContext,
        Receiver: string?,
        ReceiverType: string?,
        Completions: Dictionary<string, List<CompletionItem>>) {
        contextValue = Context
        receiverValue = Receiver
        receiverTypeValue = ReceiverType
        completionsValue = Completions
    }
}
