// PACKAGE-PRIVATE TYPES — a camelCase type name is not exported.
//
// This example used to demonstrate `file`, a file-private type modifier. N# does not have one: the
// unit of privacy is the NAMESPACE, not the file, because splitting one namespace across several files
// is the ordinary way to write it and the halves have to be able to see each other's helpers.
//
// The rule is the same one that already governs members and free functions: a camelCase name is
// visible to every file that declares the same namespace, and to nothing outside it. In CLR metadata
// such a type is emitted `assembly` (internal), so another assembly cannot name it even by accident.
// PascalCase exports.

// Package-private: an internal helper nothing outside this namespace should name.
class logWriter {
    Prefix: string = "[LOG]"

    func Log(message: string) {
        print $"{Prefix} {message}"
    }
}

// Package-private lightweight data.
struct coordinate {
    X: double
    Y: double
}

// Package-private contract.
interface iProcessor {
    func Process(value: string): string
}

// Package-private immutable data.
record settings {
    AppName: string
    Version: string
}

// EXPORTED, and the only exported type here. An exported type may hold package-private state; it just
// must not put one in a signature a consumer has to name.
class Application {
    writer: logWriter = new logWriter()
    readonly config: settings

    constructor(cfg: settings) {
        config = cfg
    }

    func Run() {
        writer.Log($"Starting {config.AppName} v{config.Version}")

        point := new coordinate { X: 10.5, Y: 20.3 }
        writer.Log($"Point: ({point.X}, {point.Y})")

        writer.Log("Application finished")
    }
}

func Main() {
    cfg := new settings { AppName: "PackagePrivateDemo", Version: "1.0.0" }

    app := new Application(cfg)
    app.Run()
}
