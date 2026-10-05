namespace NSharpLang.CompileTimeBench

import System.IO
import System.Text


// A DETERMINISTIC LARGE USER PROJECT, for measuring compiler throughput on something that is not the
// compiler itself.
//
// Compiler.Core is the repository's large-project case, but it is one shape: the compiler's own code,
// built together with two project references. Throughput work also needs a big ordinary program
// whose size can be dialled -- `modules x files x items` -- and whose every byte is the same on every
// machine, so a before/after pair compiles identical input. Each ITEM is ~135 lines: an enum, a union,
// a record with methods, a class over `List`/`Dictionary`/`StringBuilder`/LINQ with loops, `match`
// and interpolation, and free functions, one of which calls an item of the previous MODULE through an
// `import`, so name resolution crosses files and namespaces the way a real program's does. The
// default 10 x 10 x 6 is 80,009 lines in 101 files, and it builds with no diagnostics.
//
//     dotnet tests/native/compile-time-bench/bin/Debug/net10.0/NSharpLang.CompileTimeBench.dll \
//         --synthetic /tmp/synth80k [--synthetic-shape 10x10x6]
//     dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll build --project /tmp/synth80k --timings
func BenchSyntheticItem(module: int, file: int, item: int, modules: int): string {
    n := "M" + module.ToString() + "F" + file.ToString() + "I" + item.ToString()
    previousModule := (module + modules - 1) % modules
    other := "M" + previousModule.ToString() + "F" + file.ToString() + "I" + item.ToString()
    text := new StringBuilder()
    text.Append("\n// Order lifecycle for " + n + "\n")
    text.Append("enum " + n + "Kind {\n    Draft = 0,\n    Active = 1,\n    Archived = 2\n}\n\n")
    text.Append("union " + n + "Result {\n    Ok { value: int }\n    Failed { reason: string }\n    Skipped\n}\n\n")
    text.Append("record " + n + "Line {\n    Id: int\n    Name: string\n    Quantity: int\n    Price: double\n    Tags: List<string>\n\n")
    text.Append("    func Total(): double {\n        return Quantity * Price\n    }\n\n")
    text.Append("    func Describe(): string {\n        return $\"{Name} x{Quantity} @ {Price}\"\n    }\n}\n\n")
    text.Append("class " + n + "Service {\n    lines: List<" + n + "Line>\n    index: Dictionary<string, int>\n    kind: " + n + "Kind\n    counter: int\n\n")
    text.Append("    constructor() {\n        lines = new List<" + n + "Line>()\n        index = new Dictionary<string, int>()\n        kind = " + n + "Kind.Draft\n        counter = 0\n    }\n\n")
    text.Append("    func Add(name: string, quantity: int, price: double): " + n + "Result {\n")
    text.Append("        if name.Length == 0 {\n            return new " + n + "Result.Failed { reason: \"empty name\" }\n        }\n")
    text.Append("        if index.ContainsKey(name) {\n            return new " + n + "Result.Skipped {  }\n        }\n\n")
    text.Append("        counter = counter + 1\n        tags := new List<string>()\n        tags.Add(name.ToLower())\n")
    text.Append("        if quantity > 10 {\n            tags.Add(\"bulk\")\n        }\n")
    text.Append("        line := new " + n + "Line { Id: counter, Name: name, Quantity: quantity, Price: price, Tags: tags }\n")
    text.Append("        lines.Add(line)\n        index[name] = lines.Count - 1\n        kind = " + n + "Kind.Active\n")
    text.Append("        return new " + n + "Result.Ok { value: counter }\n    }\n\n")
    text.Append("    func Sum(): double {\n        total := 0.0\n        for line in lines {\n            total = total + line.Total()\n        }\n        return total\n    }\n\n")
    text.Append("    func Largest(): int {\n        best := 0\n        i := 0\n        while i < lines.Count {\n            if lines[i].Quantity > best {\n                best = lines[i].Quantity\n            }\n            i = i + 1\n        }\n        return best\n    }\n\n")
    text.Append("    func Names(): List<string> {\n        return lines.Where(l => l.Quantity > 0).Select(l => l.Name).ToList()\n    }\n\n")
    text.Append("    func Report(): string {\n        builder := new StringBuilder()\n        builder.Append(\"" + n + ": \")\n")
    text.Append("        for line in lines {\n            builder.Append(line.Describe())\n            builder.Append(\"; \")\n        }\n        return builder.ToString()\n    }\n\n")
    text.Append("    func KindText(): string {\n        return match kind {\n")
    text.Append("            " + n + "Kind.Draft => \"draft\",\n            " + n + "Kind.Active => \"active\",\n            " + n + "Kind.Archived => \"archived\",\n            _ => \"unknown\"\n        }\n    }\n}\n\n")
    text.Append("func Score" + n + "(result: " + n + "Result): int {\n    return match result {\n")
    text.Append("        " + n + "Result.Ok { value } => value,\n        " + n + "Result.Failed { reason } => reason.Length,\n        " + n + "Result.Skipped => 0\n    }\n}\n\n")
    text.Append("func Run" + n + "(seed: int): int {\n    service := new " + n + "Service()\n    total := 0\n")
    text.Append("    for i := 0; i < seed; i++ {\n        total = total + Score" + n + "(service.Add($\"item{i}\", i, i * 1.5))\n    }\n")
    text.Append("    if service.Sum() > 100.0 {\n        total = total + service.Largest()\n    }\n")
    text.Append("    total = total + service.Names().Count + service.KindText().Length\n")
    text.Append("    return total + Math.Max(0, Peer" + n + "(seed))\n}\n\n")
    text.Append("func Peer" + n + "(seed: int): int {\n    return Score" + other + "(new " + other + "Result.Ok { value: seed })\n}\n")
    return text.ToString()
}

// Writes the project under `root` and answers its line count.
func BenchWriteSyntheticProject(root: string, modules: int, filesPerModule: int, itemsPerFile: int): int {
    Directory.CreateDirectory(root)
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: SynthApp\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n")
    lines := 0
    module := 0
    while module < modules {
        moduleDirectory := Path.Combine(root, "M" + module.ToString())
        Directory.CreateDirectory(moduleDirectory)
        previousModule := (module + modules - 1) % modules
        file := 0
        while file < filesPerModule {
            body := new StringBuilder()
            body.Append("namespace M" + module.ToString() + "\n\nimport System\nimport System.Collections.Generic\nimport System.Linq\nimport System.Text\nimport M" + previousModule.ToString() + "\n")
            item := 0
            while item < itemsPerFile {
                body.Append(BenchSyntheticItem(module, file, item, modules))
                item = item + 1
            }
            text := body.ToString()
            File.WriteAllText(Path.Combine(moduleDirectory, "File" + file.ToString() + ".nl"), text)
            lines = lines + BenchCountNewlines(text)
            file = file + 1
        }
        module = module + 1
    }

    program := new StringBuilder()
    program.Append("namespace SynthApp\n\nimport System\n\n\nfunc main() {\n    total := 0\n")
    module = 0
    while module < modules {
        file := 0
        while file < filesPerModule {
            program.Append("    total = total + M" + module.ToString() + ".RunM" + module.ToString() + "F" + file.ToString() + "I0(3)\n")
            file = file + 1
        }
        module = module + 1
    }
    program.Append("    Console.WriteLine($\"total={total}\")\n}\n")
    programText := program.ToString()
    File.WriteAllText(Path.Combine(root, "Program.nl"), programText)
    return lines + BenchCountNewlines(programText)
}

func BenchCountNewlines(text: string): int {
    count := 0
    for ch in text {
        if ch == '\n' {
            count = count + 1
        }
    }
    return count
}

// `<modules>x<files>x<items>`, each a positive whole number, or null.
func BenchParseSyntheticShape(shape: string): int[]? {
    parts := shape.Split('x')
    if parts.Length != 3 {
        return null
    }

    values := new int[](3)
    index := 0
    while index < 3 {
        parsed := BenchParseCount(parts[index])
        if parsed <= 0 {
            return null
        }
        values[index] = parsed
        index = index + 1
    }
    return values
}
