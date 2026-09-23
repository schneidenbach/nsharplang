// PACKAGE-PRIVATE TYPES, the larger shape: a service whose whole implementation is unexported.
//
// This example used to demonstrate `file`, a file-private type modifier. N# does not have one, because
// its unit of privacy is the NAMESPACE: a namespace spread over several files is one package, and the
// halves have to see each other's helpers. A camelCase type name is the package boundary — visible to
// every file of this namespace and to nothing outside it, and emitted `assembly` in CLR metadata.
import System
import System.Collections.Generic


// Package-private: the cache is an implementation detail.
class internalCache {
    data: Dictionary<string, string> = new Dictionary<string, string>()

    func Set(key: string, value: string) {
        data[key] = value
    }

    func Get(key: string): string? {
        if data.ContainsKey(key) {
            return data[key]
        }

        return null
    }
}

// Package-private lightweight result.
struct validationResult {
    IsValid: bool
    ErrorMessage: string

    static func Failure(message: string): validationResult {
        return new validationResult { IsValid: false, ErrorMessage: message }
    }
}

// Package-private contract. The casing convention applies to an interface exactly as it does to a
// class: the leading letter is the whole rule, and `I` is only a naming habit.
interface iValidator {
    func Validate(input: string): validationResult
}

// Package-private immutable data.
record cacheEntry {
    Key: string
    Value: string
    Timestamp: DateTime
}

// EXPORTED. Its constructor takes a package-private interface, which is why an outside caller cannot
// construct one — a signature is only as reachable as the types in it.
class UserService {
    cache: internalCache = new internalCache()
    readonly validator: iValidator

    constructor(val: iValidator) {
        validator = val
    }

    func StoreUser(username: string, email: string): bool {
        result := validator.Validate(username)

        if !result.IsValid {
            print $"Validation failed: {result.ErrorMessage}"
            return false
        }

        cache.Set(username, email)
        print $"User {username} stored successfully"
        return true
    }

    func GetUserEmail(username: string): string? {
        return cache.Get(username)
    }
}

// Package-private implementation of a package-private contract.
class usernameValidator: iValidator {
    func Validate(input: string): validationResult {
        if input.Length < 3 {
            return validationResult.Failure("Username must be at least 3 characters")
        }

        if input.Length > 20 {
            return validationResult.Failure("Username must be at most 20 characters")
        }

        return new validationResult { IsValid: true, ErrorMessage: "" }
    }
}

func Main() {
    print "=== Package-Private Types Demo ==="
    print ""

    service := new UserService(new usernameValidator())

    print "Testing valid username:"
    service.StoreUser("alice_cooper", "alice@example.com")
    email := service.GetUserEmail("alice_cooper")
    missingEmail := "not found"
    print $"Retrieved email: {email ?? missingEmail}"
    print ""

    print "Testing invalid username (too short):"
    service.StoreUser("ab", "invalid@example.com")
    print ""

    print "Testing invalid username (too long):"
    service.StoreUser("this_username_is_way_too_long_to_be_valid", "invalid@example.com")
    print ""

    print "=== Demo Complete ==="
    print ""
    print "NOTE: internalCache, validationResult, iValidator and usernameValidator are camelCase, so"
    print "they are package-private: every file of this namespace can name them and nothing outside"
    print "the package can. UserService is PascalCase and is the package's whole exported surface."
}
