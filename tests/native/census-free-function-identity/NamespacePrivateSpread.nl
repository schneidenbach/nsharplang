namespace Census.FreeFunctionIdentity.Spread


// The camelCase half of the namespace's surface, declared in ITS OWN FILE. A camelCase top-level
// function is NAMESPACE-private, not file-private, so `NamespacePrivateSpreadUse.nl` — another file
// of this same namespace — reaches it with no import and no export.
func spreadHelper(value: int): string {
    return "spread:" + value.ToString()
}

func spreadLabel(): string {
    return "label"
}
