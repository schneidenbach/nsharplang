namespace NSharpLang.Cli.Daemon

import System.IO

// The project a fresh workspace server compiles before any client asks it to: small, but touching
// what nearly every real project touches — a class, a record, a union and a match, generics,
// collections, lambdas, interpolation — so the parser, analyzer, planner and emitter are JIT-compiled
// and the framework reference metadata is loaded by the time the first real command arrives. It lives
// in the temp directory under the server's build identity, so two builds never share one.
class DaemonWarmup {
    static func PrepareProject(identity: string): string {
        directory := Path.Combine(Path.Combine(Path.GetTempPath(), "nlc-daemon-warmup"), identity)
        Directory.CreateDirectory(directory)
        WriteIfChanged(Path.Combine(directory, "project.yml"), GetProjectYml())
        WriteIfChanged(Path.Combine(directory, "Program.nl"), GetProgramSource())
        return directory
    }

    static func Run(directory: string) {
        check := new string[](1)
        check[0] = "check"
        DaemonExecHost.RunUnobserved(check, directory)
        build := new string[](1)
        build[0] = "build"
        DaemonExecHost.RunUnobserved(build, directory)
    }

    static func WriteIfChanged(path: string, content: string) {
        if File.Exists(path) && File.ReadAllText(path) == content {
            return
        }

        File.WriteAllText(path, content)
    }

    static func GetProjectYml(): string {
        return "name: NlcDaemonWarmup\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n"
    }

    static func GetProgramSource(): string {
        return "namespace NlcDaemonWarmup\n\nimport System\nimport System.Collections.Generic\nimport System.Linq\n\nunion Shape {\n    Circle(radius: double)\n    Square(side: double)\n}\n\nrecord Point(X: int, Y: int)\n\nclass Inventory {\n    items: List<string>\n\n    constructor() {\n        items = new List<string>()\n    }\n\n    func Add(name: string) {\n        items.Add(name)\n    }\n\n    func Count(): int {\n        return items.Count\n    }\n}\n\nfunc Area(shape: Shape): double {\n    return match shape {\n        Circle(radius) => Math.PI * radius * radius\n        Square(side) => side * side\n    }\n}\n\nfunc Largest<T>(values: List<T>, key: Func<T, int>): T? {\n    best: T? = default\n    bestKey := Int32.MinValue\n    for value in values {\n        current := key(value)\n        if current > bestKey {\n            bestKey = current\n            best = value\n        }\n    }\n\n    return best\n}\n\nfunc main() {\n    inventory := new Inventory()\n    inventory.Add(\"widget\")\n    counts := new Dictionary<string, int>()\n    counts[\"widget\"] = inventory.Count()\n    points := new List<Point>()\n    points.Add(new Point(1, 2))\n    evens := points.Where(p => p.X % 2 == 0).Count()\n    longest := Largest(new List<string> { \"a\", \"bb\" }, s => s.Length)\n    print $\"{Area(Shape.Circle(1.0))} {counts.Count} {evens} {longest}\"\n}\n"
    }

    static func GetCompletedMessage(elapsedMilliseconds: long): string {
        return "[daemon] Warm-up finished in " + elapsedMilliseconds.ToString() + " ms"
    }

    static func GetFailedMessage(messageText: string): string {
        return "[daemon] Warm-up failed: " + messageText
    }
}
