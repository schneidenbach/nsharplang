// File-scoped types (C# 11 feature)
// Types marked with 'file' are only visible within this file

// File-scoped class - only visible in this file
file class InternalCache {
    _data: Dictionary<string, string> = new Dictionary<string, string>()

    func Set(key: string, value: string) {
        _data[key] = value
    }

    func Get(key: string): string? {
        let temp: string
        success := _data.TryGetValue(key, out temp)
        return success ? temp : null
    }
}

// File-scoped struct - lightweight helper
file struct ValidationResult {
    IsValid: bool
    ErrorMessage: string

    static func Success(): ValidationResult {
        return new ValidationResult { IsValid: true, ErrorMessage: "" }
    }

    static func Failure(message: string): ValidationResult {
        return new ValidationResult { IsValid: false, ErrorMessage: message }
    }
}

// File-scoped interface - internal contract
file interface IValidator {
    func Validate(input: string): ValidationResult
}

// File-scoped record - immutable data
file record CacheEntry {
    Key: string
    Value: string
    Timestamp: DateTime
}

// Public class that uses file-scoped types internally
class UserService {
    cache: InternalCache = new InternalCache()
    validator: IValidator

    constructor(val: IValidator) {
        validator = val
    }

    func StoreUser(username: string, email: string): bool {
        // Validate input using file-scoped validator
        result := validator.Validate(username)

        if !result.IsValid {
            print $"Validation failed: {result.ErrorMessage}"
            return false
        }

        // Store in file-scoped cache
        cache.Set(username, email)
        print $"User {username} stored successfully"
        return true
    }

    func GetUserEmail(username: string): string? {
        return cache.Get(username)
    }
}

// File-scoped validator implementation
file class UsernameValidator : IValidator {
    func Validate(input: string): ValidationResult {
        if input.Length < 3 {
            return ValidationResult.Failure("Username must be at least 3 characters")
        }

        if input.Length > 20 {
            return ValidationResult.Failure("Username must be at most 20 characters")
        }

        return ValidationResult.Success()
    }
}

// Main program - demonstrates file-scoped types
print "=== File-Scoped Types Demo ==="
print ""

// Create service with file-scoped validator
service := new UserService(new UsernameValidator())

// Test valid username
print "Testing valid username:"
service.StoreUser("alice_cooper", "alice@example.com")
email := service.GetUserEmail("alice_cooper")
print $"Retrieved email: {email ?? \"not found\"}"
print ""

// Test invalid username (too short)
print "Testing invalid username (too short):"
service.StoreUser("ab", "invalid@example.com")
print ""

// Test invalid username (too long)
print "Testing invalid username (too long):"
service.StoreUser("this_username_is_way_too_long_to_be_valid", "invalid@example.com")
print ""

print "=== Demo Complete ==="
print ""
print "NOTE: File-scoped types (InternalCache, ValidationResult, IValidator, etc.)"
print "are only visible within this file and cannot be used from other files."
print "This is perfect for implementation details that shouldn't be exposed!"
