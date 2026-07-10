namespace NSharpLang.Compiler.Columnar

import System

test "range handle owner selects exact CLR members" {
    handles := ColumnarRangeIndexHandles.Resolve()
    handles.CloseGetSubArray(typeof(string))
    assert true
}
