namespace NSharpLang.QualifiedNames.Tests

import System.Text
import System.Text as Txt


// A NAMESPACE ALIAS AT A TYPE POSITION, IN EVERY SLOT A TYPE CAN BE WRITTEN IN.
//
// `Txt.StringBuilder` and `StringBuilder` name one type. The alias table the analyzer carries is
// keyed by the ALIAS alone, so an alias-QUALIFIED reference matched nothing and fell out of the
// resolution walk as an unresolved-external placeholder — a second instance beside the one the bare
// spelling resolves to, with nothing assignable across the two. These declarations are the slots
// that fork: a field with an initializer, a parameter, a return type and a local annotation.
class AliasTypedHolder {
    Qualified: Txt.StringBuilder = new StringBuilder()
    Bare: StringBuilder = new Txt.StringBuilder()

    func Write(text: string): string {
        Qualified.Append(text)
        Bare.Append(text)
        return Qualified.ToString() + Bare.ToString()
    }
}

func AliasQualifiedToBare(builder: Txt.StringBuilder): StringBuilder {
    return builder
}

func BareToAliasQualified(builder: StringBuilder): Txt.StringBuilder {
    return builder
}

func AliasAnnotatedLocal(text: string): string {
    local: Txt.StringBuilder = new StringBuilder()
    local.Append(text)
    return local.ToString()
}
