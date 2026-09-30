namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic

interface IRootValue {
    func Value(): int
}
interface ILeftValue: IRootValue {
}
interface IRightValue: IRootValue {
}
interface IDiamondValue: ILeftValue, IRightValue {
}
class DiamondValue: IDiamondValue {
    func Value(): int {
        return 37
    }
}

interface IIdentity<T> {
    func Identity(value: T): T
}
class IntIdentity: IIdentity<int> {
    func Identity(value: int): int {
        return value + 1
    }
}

interface IDescribe {
    func ToString(): string
}
class CombinedDescription: Exception, IDescribe {
    override func ToString(): string {
        return "combined-slot"
    }
}

interface IFirst {
    func First(): int
}
interface ISecond {
    func Second(): int
}
class DistinctSlots: IFirst, ISecond {
    func First(): int {
        return 11
    }
    func Second(): int {
        return 22
    }
}

func PutOverrideControlArgument(arguments: object?[], index: int, value: object?) {
    arguments[index] = value
}

func* ValuesForNongeneric(): IEnumerable<int> {
    yield 3
    yield 7
}

test "inherited diamond source interfaces dispatch through every arm" {
    value := new DiamondValue()
    root: IRootValue = value
    left: ILeftValue = value
    right: IRightValue = value
    diamond: IDiamondValue = value
    assert root.Value() == 37
    leftRoot: IRootValue = left
    rightRoot: IRootValue = right
    diamondLeft: ILeftValue = diamond
    diamondRoot: IRootValue = diamondLeft
    assert leftRoot.Value() == 37
    assert rightRoot.Value() == 37
    assert diamondRoot.Value() == 37
}

test "closed generic source interface dispatch preserves its int signature" {
    concrete := new IntIdentity()
    interfaceType := typeof(IIdentity<int>)
    method := interfaceType.GetMethod("Identity")
    if method == null {
        throw new InvalidOperationException("Missing closed interface method")
    }
    arguments := new object?[](1)
    PutOverrideControlArgument(arguments, 0, 40)
    assert Convert.ToInt32(method.Invoke(concrete, arguments)) == 41
}

test "one method serves its external base and source interface slots" {
    concrete := new CombinedDescription()
    baseValue: Exception = concrete
    interfaceValue: IDescribe = concrete
    assert baseValue.ToString() == "combined-slot"
    assert interfaceValue.ToString() == "combined-slot"
    method := typeof(CombinedDescription).GetMethod("ToString")
    if method == null {
        throw new InvalidOperationException("Missing combined method")
    }
    assert Convert.ToInt32(method.get_Attributes()) == 230
}

test "separate source interface slots retain their distinct bodies" {
    concrete := new DistinctSlots()
    first: IFirst = concrete
    second: ISecond = concrete
    assert first.First() == 11
    assert second.Second() == 22
}

test "iterator dispatches through nongeneric enumerable and enumerator slots" {
    sequence := ValuesForNongeneric()
    boxed: object = sequence
    nongeneric := (IEnumerable)boxed
    enumerator := nongeneric.GetEnumerator()
    assert enumerator.MoveNext()
    assert Convert.ToInt32(enumerator.get_Current()) == 3
    assert enumerator.MoveNext()
    assert Convert.ToInt32(enumerator.get_Current()) == 7
    assert !enumerator.MoveNext()
    assert throws NotSupportedException {
        enumerator.Reset()
    }
    disposable := enumerator as IDisposable
    if disposable != null {
        disposable.Dispose()
    }
}
