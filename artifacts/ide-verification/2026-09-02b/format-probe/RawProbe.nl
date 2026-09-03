namespace WeatherDemo.Models

// Format-on-save probe 3: raw strings only; must survive the save byte-for-byte.
class RawProbe {
    static func Banner(name: string): string {
        plain := """
            == weather ==
            raw "quotes" stay
            """
        interpolated := $"""
            == {name} ==
            """
        return plain + interpolated
    }
}
