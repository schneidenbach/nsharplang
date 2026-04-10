using System.Collections.Generic;
using System.Threading.Tasks;

namespace NSharpLang.Tests;

public static class ILCompilerAsyncHelpers
{
    public static Task<int> GetValueAsync(int value)
    {
        return Task.FromResult(value);
    }

    public static async IAsyncEnumerable<int> GetNumbersAsync()
    {
        yield return 1;
        await Task.Yield();
        yield return 2;
        await Task.Yield();
        yield return 3;
    }
}
