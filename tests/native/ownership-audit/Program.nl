namespace NSharpLang.OwnershipAudit

import System

func main(): void {
    result := OwnershipAudit.AuditLiveRepository()
    if !result.Succeeded {
        throw new InvalidOperationException(result.Report())
    }

    print "N# ownership growth audit passed."
}
