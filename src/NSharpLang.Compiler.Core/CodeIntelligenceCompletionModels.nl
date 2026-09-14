namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class CompletionItem {
    nameValue: string
    kindValue: string
    typeValue: string?
    parametersValue: string?
    documentationValue: string?
    isStaticValue: bool
    overloadsValue: int
    importNamespaceValue: string?

    Name: string => nameValue
    Kind: string => kindValue
    Type: string? => typeValue
    Parameters: string? => parametersValue
    Documentation: string? => documentationValue
    IsStatic: bool => isStaticValue

    // HOW MANY DECLARATIONS WEAR THIS NAME. One, for everything that is not an overload set — so a
    // caller that never thought about overloads gets the honest answer without asking. A collapsed
    // row carries the count of the rows it stands for, which is the only place the information a
    // reader lost when the duplicates went can still be said.
    Overloads: int => overloadsValue

    // THE NAMESPACE A CALLER MUST IMPORT TO WRITE THIS NAME FROM WHERE THEY ARE, or null when the
    // name is already reachable. It is null for everything in scope, and it is the whole reason a
    // cross-namespace offer is honest rather than a trap: an exported free function of another
    // namespace of the same project is NL412 until its `import` line exists, so an offer that did
    // not carry the namespace would be an offer the very next diagnostic underlines.
    ImportNamespace: string? => importNamespaceValue

    constructor(Name: string, Kind: string, Type: string?, Parameters: string?, Documentation: string?, IsStatic: bool, Overloads: int = 1, ImportNamespace: string? = null) {
        importNamespaceValue = ImportNamespace
        nameValue = Name
        kindValue = Kind
        typeValue = Type
        parametersValue = Parameters
        documentationValue = Documentation
        isStaticValue = IsStatic
        overloadsValue = Overloads
    }
}

class CompletionResult {
    contextValue: CompletionContext
    receiverValue: string?
    receiverTypeValue: string?
    completionsValue: Dictionary<string, List<CompletionItem>>

    Context: CompletionContext => contextValue
    Receiver: string? => receiverValue
    ReceiverType: string? => receiverTypeValue
    Completions: Dictionary<string, List<CompletionItem>> => completionsValue

    constructor(Context: CompletionContext, Receiver: string?, ReceiverType: string?, Completions: Dictionary<string, List<CompletionItem>>) {
        contextValue = Context
        receiverValue = Receiver
        receiverTypeValue = ReceiverType
        completionsValue = Completions
    }
}
