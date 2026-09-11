namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Reflection
import System.Reflection.PortableExecutable


// 023/1e — THE TWO CONSTANT CONVERSIONS, PER POSITION, END TO END.
//
// The owner's own contracts live beside `ConstantConversionFacts`; what is pinned HERE is that each
// POSITION asks it, because the positions are separate owners and a rule that reaches three of four is
// the per-member enum defect 023/1a deleted, one layer up. Before this slice: `f: AssemblyFlags = 0`
// was `Variable 'f' is typed as 'AssemblyFlags', but the value is 'int'`, and `b[0] = 65` on a `byte[]`
// declined at `emit.statement.block-child` while `v: byte = 65` and `Take(65)` both compiled — the rule
// existed, the array store just never asked for it.
func ConstantFactsTakesFlags(value: AssemblyFlags): int {
    return Convert.ToInt32(value)
}

func ConstantFactsTakesByte(value: byte): int {
    if value > 200 {
        return 1
    }

    return 0
}

func ConstantFactsTakesCorFlags(value: CorFlags): int {
    return Convert.ToInt32(value)
}

test "the literal zero converts to an external enum in a typed local" {
    // §10.2.4. `AssemblyFlags` publishes no zero-named member, so before this slice the absent-flags
    // column could not be spelled honestly at all — the writer wrote `PublicKey & Retargetable`.
    flags: AssemblyFlags = 0
    assert Convert.ToInt32(flags) == 0

    corFlags: CorFlags = 0
    assert Convert.ToInt32(corFlags) == 0

    // An enum that DOES publish a zero-named member is unaffected either way.
    hash: AssemblyHashAlgorithm = 0
    assert Convert.ToInt32(hash) == Convert.ToInt32(AssemblyHashAlgorithm.None)
}

test "the literal zero converts to an external enum in an argument position" {
    assert ConstantFactsTakesFlags(0) == 0
    assert ConstantFactsTakesCorFlags(0) == 0
}

test "an in-range integer constant stores into a byte array element" {
    // §10.2.11, and the position this slice added. The ECMA public key token is the shape that wanted
    // it: eight byte constants that previously each needed a `Convert.ToByte` call.
    token := new byte[](8)
    token[0] = 176
    token[1] = 63
    token[2] = 95
    token[3] = 127
    token[4] = 17
    token[5] = 213
    token[6] = 10
    token[7] = 58

    assert Convert.ToInt32(token[0]) == 176
    assert Convert.ToInt32(token[3]) == 127
    assert Convert.ToInt32(token[7]) == 58
}

test "an in-range integer constant reaches the typed local and the argument positions too" {
    small: byte = 65
    assert Convert.ToInt32(small) == 65

    wide: short = 32767
    assert Convert.ToInt32(wide) == 32767

    assert ConstantFactsTakesByte(255) == 1
    assert ConstantFactsTakesByte(65) == 0
}

test "the narrowing element store is not a general int-to-byte conversion" {
    // The rule is CONSTANT-only. A variable of type `int` still does not store into a `byte[]`, which
    // is what keeps this from becoming an implicit narrowing conversion the language does not have.
    // (`b[0] = n`, `b[0] = 300` and `b[0] = -1` are all refused; they cannot be written here because
    // they do not compile, and they are pinned as probes in the slice's decode.)
    values := new byte[](2)
    source: byte = 12
    values[0] = source
    values[1] = 34
    assert Convert.ToInt32(values[0]) == 12
    assert Convert.ToInt32(values[1]) == 34
}
