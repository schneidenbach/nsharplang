#region Configuration
class Config {
    AppName: string = "MyApp"
    Version: string = "1.0.0"
}

#endregion

#region Math Operations
class Calculator {
    func Add(a: int, b: int): int {
        return a + b
    }

    func Multiply(x: int, y: int): int {
        return x * y
    }
}

#endregion

func Main() {
    config := new Config()
    calc := new Calculator()

    print $"App: {config.AppName} v{config.Version}"

    #if DEBUG
    print "Running in DEBUG mode"
    #else
    print "Running in RELEASE mode"
    #endif

    sum := calc.Add(5, 3)
    print $"5 + 3 = {sum}"

    product := calc.Multiply(4, 7)
    print $"4 * 7 = {product}"

    #region Cleanup
    print "Done!"
    #endregion
}
