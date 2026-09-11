namespace SystemsProofs.AotFriendlyPublicApi

enum NormalizeError {
    Empty
}

struct NormalizedName {
    Value: string
}

class NameApi {
    [boundary]
    [aotSafe(nativeaot)]
    static func Normalize(input: string): Result<NormalizedName, NormalizeError> {
        if input.Length == 0 {
            return Err(NormalizeError.Empty)
        }

        value := input.Trim().ToUpperInvariant()
        return Ok(new NormalizedName { Value: value })
    }
}
