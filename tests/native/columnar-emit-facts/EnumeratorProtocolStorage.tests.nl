namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic

class EnumeratorProtocolStorageRow {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

func* EnumeratorProtocolStorageRows(
    row: EnumeratorProtocolStorageRow
): IEnumerable<EnumeratorProtocolStorageRow> {
    yield row
}

func EnumeratorProtocolStorageFirstValue(
    rows: IEnumerable<EnumeratorProtocolStorageRow>
): int {
    enumerator := rows.GetEnumerator()
    movement := enumerator as IEnumerator
    result := -1
    try {
        if movement == null {
            throw new NullReferenceException()
        }
        if movement.MoveNext() {
            current := enumerator.get_Current()
            result = current.Value
        }
    } finally {
        disposable := enumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }
    return result
}

test "source element generic enumerator retains its exact Current slot" {
    assert EnumeratorProtocolStorageFirstValue(
        EnumeratorProtocolStorageRows(new EnumeratorProtocolStorageRow(41))
    ) == 41
}
