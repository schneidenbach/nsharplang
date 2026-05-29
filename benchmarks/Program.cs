using BenchmarkDotNet.Running;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Entry point for the N#-vs-C# performance corpus. Run with:
///   dotnet run -c Release --project benchmarks -- --filter '*'
/// or target one family, e.g. --filter '*ForeachArray*'.
/// </summary>
public static class Program
{
    public static void Main(string[] args) =>
        BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
}
