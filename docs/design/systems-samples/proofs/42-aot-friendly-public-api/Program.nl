namespace SystemsProofs.AotFriendlyPublicApi

public enum NormalizeError {
    Empty
}

public struct NormalizedName {
    Value: string
}

public class NameApi {
    [boundary]
    [aotSafe(nativeaot)]
    public static func Normalize(input: string): Result<NormalizedName, NormalizeError> {
        if input.Length == 0 {
            return Err(NormalizeError.Empty)
        }

        value := input.Trim().ToUpperInvariant()
        return Ok(new NormalizedName { Value: value })
    }
}
