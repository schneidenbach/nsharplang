// Simple demonstration of file-scoped types (C# 11)
// Types marked with 'file' are only visible within this single file

// File-scoped class - internal helper
file class Logger {
    Prefix: string = "[LOG]"

    func Log(message: string) {
        print $"{Prefix} {message}"
    }
}

// File-scoped struct - lightweight data
file struct Point {
    X: double
    Y: double
}

// File-scoped interface - internal contract
file interface IProcessor {
    func Process(value: string): string
}

// File-scoped record - immutable data
file record Config {
    AppName: string
    Version: string
}

// Public class that uses file-scoped types internally
class Application {
    logger: Logger = new Logger()
    config: Config

    constructor(cfg: Config) {
        config = cfg
    }

    func Run() {
        logger.Log($"Starting {config.AppName} v{config.Version}")

        // Use file-scoped struct
        point := new Point { X: 10.5, Y: 20.3 }
        logger.Log($"Point: ({point.X}, {point.Y})")

        logger.Log("Application finished")
    }
}

func Main() {
    cfg := new Config {
        AppName: "FileScopedDemo",
        Version: "1.0.0"
    }

    app := new Application(cfg)
    app.Run()
}
