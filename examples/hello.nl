using System
using System.Linq

class Program {
    static func Main() {
        name := "World"
        greeting := $"Hello, {name}!"
        Console.WriteLine(greeting)

        let numbers: int[] = [1, 2, 3, 4, 5]
        doubled := numbers.Select(x => x * 2).ToList()

        Console.WriteLine("Doubled numbers:")
        foreach num in doubled {
            Console.WriteLine(num)
        }
    }
}
