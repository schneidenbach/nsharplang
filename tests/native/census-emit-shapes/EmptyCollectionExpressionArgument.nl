namespace NSharpLang.CensusEmitShapes.Tests

import System.Security.Cryptography


// AN EMPTY COLLECTION EXPRESSION IS TARGET-TYPED LIKE EVERY OTHER ONE.
//
// `[]` carries no element, so the pre-pass that types arguments before a candidate is chosen can
// only give it `unknown[]`; asking whether `unknown` converts to the parameter's element type then
// answered no at every reflected array parameter, and `sha.TransformFinalBlock([], 0, 0)` reported
// that no overload accepts three arguments with these types — for a call with exactly ONE overload.
// Applicability for an empty collection expression is a question about the TARGET alone
// (C# §12.6.4.4), and that is what decides it now.
class EmptyCollectionArguments {

    // A reflected array parameter, reached with no element to infer from.
    static func FinalizeEmpty(hash: SHA256): byte[] {
        return hash.TransformFinalBlock([], 0, 0)
    }

    // The same literal where its element type comes from the parameter and the call still runs.
    static func BlockThenFinal(hash: SHA256, block: byte[]): byte[] {
        hash.TransformBlock(block, 0, block.Length, null, 0)
        return hash.TransformFinalBlock([], 0, 0)
    }
}
