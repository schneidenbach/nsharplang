namespace SystemsProofs.AotFriendlyPublicApi

import System

public enum NormalizeError {
    Empty
}

public readonly struct NormalizedName {
    Value: string
}

public class NameApi {
    [boundary]
    [aotSafe(nativeaot)]
    [trimSafe]
    public static func Normalize(input: string): Result<NormalizedName, NormalizeError> {
        if input.Length == 0 {
            return Err(NormalizeError.Empty)
        }

        value := input.Trim().ToUpperInvariant()
        return Ok(NormalizedName { Value: value })
    }
}
