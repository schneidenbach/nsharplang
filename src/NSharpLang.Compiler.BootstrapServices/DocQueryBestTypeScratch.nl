namespace NSharpLang.Compiler.CodeIntelligence

import System

public class DocQueryBestTypeScratch {
    FullNames: string[] = new string[](0)
    NamespaceLengths: int[] = new int[](0)
    Scores: int[] = new int[](0)

    public func EnsureCapacity(count: int) {
        if Scores.Length < count {
            Scores = new int[](count)
            NamespaceLengths = new int[](count)
            FullNames = new string[](count)
        }
    }

    public func ClearFullNames(count: int) {
        if count > 0 {
            Array.Clear(FullNames, 0, count)
        }
    }
}
