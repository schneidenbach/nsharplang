namespace NSharpLang.Compiler

import System.Collections.Generic

public class FormatResult {
    Text: string
    Success: bool
    warningsValue: List<string>?

    Warnings: List<string> {
        get {
            if warningsValue == null {
                warningsValue = new List<string>()
            }

            return warningsValue
        }
        set {
            warningsValue = value
        }
    }
}
