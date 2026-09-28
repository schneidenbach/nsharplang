namespace NSharpLang.FreeFunctionOverloads

import System

func CountOf(value: int?): int => value ?? -1
func CountOf(value: string?): int => value?.Length ?? -2

func Width(_value: int): string => "int"
func Width(_value: long): string => "long"

func ByArity(value: int): string => "one:" + value.ToString()
func ByArity(value: int, extra: int): string => "two:" + (value + extra).ToString()

func GenericWidth<T>(_value: T): int => 1
func GenericWidth<T>(_value: T, extra: int): int => extra

func Format(value: int): string => "int:" + value.ToString()
func Format(value: string): string => "text:" + value

func LabelBy(value: int): (Number: int, Tag: string) {
    return (Number: value, Tag: "int")
}

func LabelBy(value: string): (Text: string, Tag: string) {
    return (Text: value, Tag: "text")
}

func ApplyInt(formatter: Func<int, string>): string {
    return formatter(9)
}

func ApplyText(formatter: Func<string, string>): string {
    return formatter("ok")
}

class StaticFormatter {
    static func Format(value: int): string => "static-int:" + value.ToString()
    static func Format(value: string): string => "static-text:" + value
}

func ApplyStaticInt(formatter: Func<int, string>): string {
    return formatter(5)
}

func MainOutput(): string {
    return CountOf(3).ToString() + "\n" + CountOf("abc").ToString() + "\n" + Width(4) + "\n" + Width(4L) + "\n" + ByArity(7) + "\n" + ByArity(7, 2) + "\n" + GenericWidth(6).ToString() + "\n" + GenericWidth(6, 8).ToString() + "\n" + AcrossFiles(11) + "\n" + AcrossFiles("cross") + "\n" + ApplyInt(Format) + "\n" + ApplyText(Format) + "\n" + ApplyStaticInt(StaticFormatter.Format)
}

func main() {
    print MainOutput()
}
