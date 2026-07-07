namespace NSharpLang.Compiler.CodeIntelligence

import System

public class DocQueryBestTypeScratch {
    FullNames: string[]
    NamespaceLengths: int[]
    Scores: int[]

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Scores.Length < count {
            Scores = new int[](count)
            NamespaceLengths = new int[](count)
            FullNames = new string[](count)
        }
    }

    public func ClearFullNames(count: int) {
        EnsureInitialized()
        if count > 0 {
            Array.Clear(FullNames, 0, count)
        }
    }

    func EnsureInitialized() {
        if FullNames != null {
            return
        }

        FullNames = new string[](0)
        NamespaceLengths = new int[](0)
        Scores = new int[](0)
    }
}
