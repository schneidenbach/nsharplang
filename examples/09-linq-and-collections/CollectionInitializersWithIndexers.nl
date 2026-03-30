// Collection Initialization Examples
// Demonstrates creating and populating dictionaries and collections
import System.Collections.Generic

func Main() {
    print "=== Collection Initialization Examples ==="
    print ""

    // 1. Basic dictionary initialization
    print "1. Basic Dictionary Initialization:"
    scores := new Dictionary<string, int>()
    scores["Alice"] = 95
    scores["Bob"] = 87
    scores["Charlie"] = 92

    aliceScore := scores["Alice"]
    bobScore := scores["Bob"]
    print $"Alice: {aliceScore}, Bob: {bobScore}"
    print ""

    // 2. Integer keys
    print "2. Dictionary with Integer Keys:"
    idNames := new Dictionary<int, string>()
    idNames[1] = "First"
    idNames[2] = "Second"
    idNames[3] = "Third"

    first := idNames[1]
    third := idNames[3]
    print $"ID 1: {first}, ID 3: {third}"
    print ""

    // 3. Pre-sized Dictionary
    print "3. Pre-sized Dictionary:"
    cache := new Dictionary<string, double>(10)
    cache["pi"] = 3.14159
    cache["e"] = 2.71828
    cache["phi"] = 1.61803

    pi := cache["pi"]
    e := cache["e"]
    print $"pi = {pi}, e = {e}"
    print ""

    // 4. Using variables as keys
    print "4. Dynamic Keys:"
    key1 := "firstKey"
    key2 := "secondKey"

    dynamicDict := new Dictionary<string, int>()
    dynamicDict[key1] = 100
    dynamicDict[key2] = 200
    dynamicDict["thirdKey"] = 300

    result1 := dynamicDict[key1]
    result2 := dynamicDict[key2]
    print $"{key1}: {result1}, {key2}: {result2}"
    print ""

    // 5. SortedDictionary example
    print "5. SortedDictionary:"
    sorted := new SortedDictionary<string, string>()
    sorted["zebra"] = "Striped animal"
    sorted["apple"] = "Red fruit"
    sorted["monkey"] = "Primate"

    apple := sorted["apple"]
    print $"apple: {apple}"
    print ""

    // 6. Nested dictionaries
    print "6. Nested Dictionary Structure:"
    dbConfig := new Dictionary<string, string>()
    dbConfig["host"] = "localhost"
    dbConfig["port"] = "5432"

    cacheConfig := new Dictionary<string, string>()
    cacheConfig["enabled"] = "true"
    cacheConfig["ttl"] = "3600"

    config := new Dictionary<string, Dictionary<string, string>>()
    config["database"] = dbConfig
    config["cache"] = cacheConfig

    dbHost := config["database"]["host"]
    cacheEnabled := config["cache"]["enabled"]
    print $"DB Host: {dbHost}, Cache Enabled: {cacheEnabled}"
    print ""

    print "=== Benefits ==="
    print "1. Cleaner syntax than verbose initialization"
    print "2. Works with any type that has an indexer"
    print "3. Type-safe at compile time"
    print "4. Natural dictionary initialization syntax"
}
