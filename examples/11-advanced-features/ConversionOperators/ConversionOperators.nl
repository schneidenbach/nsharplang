// Conversion Operators Example
// Demonstrates implicit and explicit user-defined type conversions

// Temperature conversion example - implicit conversion (safe)
class Celsius {
    Value: double

    // Implicit conversion to Fahrenheit (always safe)
    implicit operator Fahrenheit(c: Celsius) {
        return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
    }

    // Explicit conversion to Kelvin (for demonstration)
    explicit operator Kelvin(c: Celsius) {
        return new Kelvin { Value: c.Value + 273.15 }
    }
}

class Fahrenheit {
    Value: double

    // Implicit conversion back to Celsius
    implicit operator Celsius(f: Fahrenheit) {
        return new Celsius { Value: (f.Value - 32.0) * 5.0 / 9.0 }
    }
}

class Kelvin {
    Value: double

    // Explicit conversion to Celsius (requires cast)
    explicit operator Celsius(k: Kelvin) {
        return new Celsius { Value: k.Value - 273.15 }
    }
}

// Fraction to double conversion - explicit (lossy)
struct Fraction {
    Numerator: int
    Denominator: int

    // Explicit conversion to double (lossy - requires explicit cast)
    explicit operator double(f: Fraction) {
        return f.Numerator / (double)f.Denominator
    }

    // Explicit conversion from double to Fraction
    static func FromDouble(value: double, precision: int = 1000): Fraction {
        numerator := (int)(value * precision)
        return new Fraction { Numerator: numerator, Denominator: precision }
    }
}

// Money type with currency conversion
class Money {
    Amount: double
    Currency: string

    // Implicit conversion to double (just the amount)
    implicit operator double(m: Money) {
        return m.Amount
    }

    func ToString(): string {
        return $"{Amount:F2} {Currency}"
    }
}

// Meters/Centimeters - natural implicit conversions
class Meters {
    Value: double

    // Implicit conversion to Centimeters (always safe, no data loss)
    implicit operator Centimeters(m: Meters) {
        return new Centimeters { Value: m.Value * 100.0 }
    }
}

class Centimeters {
    Value: double

    // Explicit conversion to Meters (may lose precision)
    explicit operator Meters(cm: Centimeters) {
        return new Meters { Value: cm.Value / 100.0 }
    }
}

// Main demonstration
func Main() {
    print "=== Temperature Conversions ==="

    // Implicit conversion (no cast needed)
    celsius := new Celsius { Value: 20.0 }
    fahrenheit: Fahrenheit = celsius
    // Implicit conversion
    print $"20°C = {fahrenheit.Value:F1}°F"

    // Conversion chain
    c2: Celsius = fahrenheit
    // Implicit conversion back
    print $"{fahrenheit.Value:F1}°F = {c2.Value:F1}°C"

    // Explicit conversion (requires cast)
    kelvin := (Kelvin)celsius
    // Explicit cast required
    print $"20°C = {kelvin.Value:F2}K"

    print ""
    print "=== Fraction Conversions ==="

    frac := new Fraction { Numerator: 3, Denominator: 4 }
    value := (double)frac
    // Explicit cast required
    print $"3/4 = {value}"

    print ""
    print "=== Money Conversions ==="

    usd := new Money { Amount: 100.50, Currency: "USD" }
    amount: double = usd
    // Implicit conversion to double
    print $"Money: {usd.ToString()}"
    print $"Amount only: {amount}"

    print ""
    print "=== Distance Conversions ==="

    meters := new Meters { Value: 5.0 }
    cm: Centimeters = meters
    // Implicit conversion
    print $"5 meters = {cm.Value} centimeters"

    cm2 := new Centimeters { Value: 250.0 }
    m2 := (Meters)cm2
    // Explicit cast required
    print $"250 cm = {m2.Value} meters"

    print ""
    print "=== Practical Use Case ==="

    // Temperature calculation using implicit conversions
    temps: Celsius[] = [new Celsius { Value: 0.0 }, new Celsius { Value: 20.0 }, new Celsius { Value: 30.0 }, new Celsius { Value: 100.0 }]

    for temp in temps {
        f: Fahrenheit = temp
        // Implicit conversion
        print $"{temp.Value}°C = {f.Value:F1}°F"
    }
}
