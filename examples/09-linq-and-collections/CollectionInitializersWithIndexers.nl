// Collection Initializers with Indexers (C# 6 Feature)
// Demonstrates dictionary and collection initialization using indexer syntax
import System.Collections.Generic

func Main() {
    print "=== Collection Initializers with Indexers ==="
    print ""

    // 1. Basic dictionary initialization with indexer syntax
    print "1. Basic Dictionary Initialization:"
    scores := new Dictionary<string, int>() { 95, 87, 92 }

    aliceScore := scores["Alice"]
    bobScore := scores["Bob"]
    print $"Alice: {aliceScore}, Bob: {bobScore}"
    print ""

    // 2. Integer keys
    print "2. Dictionary with Integer Keys:"
    idNames := new Dictionary<int, string>() { "First", "Second", "Third" }

    first := idNames[1]
    third := idNames[3]
    print $"ID 1: {first}, ID 3: {third}"
    print ""

    // 3. Mixed initialization with constructor and indexers
    print "3. Pre-sized Dictionary:"
    cache := new Dictionary<string, double>(10) { 3.14159, 2.71828, 1.61803 }

    pi := cache["pi"]
    e := cache["e"]
    print $"pi = {pi}, e = {e}"
    print ""

    // 4. Complex value types (using tuples)
    print "4. Dictionary with Tuple Values:"
    playerScores := new Dictionary<string, (int, int)>() { (1500, 10), (2200, 15), (1800, 12) }

    p1 := playerScores["Player1"]
    print $"Player1: Score {p1.Item1}, Level {p1.Item2}"
    print ""

    // 5. Using variables in indexer expressions
    print "5. Dynamic Keys:"
    key1 := "firstKey"
    key2 := "secondKey"
    val1 := 100
    val2 := 200

    dynamicDict := new Dictionary<string, int>() { val1, val2, 300 }

    result1 := dynamicDict[key1]
    result2 := dynamicDict[key2]
    print $"{key1}: {result1}, {key2}: {result2}"
    print ""

    // 6. SortedDictionary example
    print "6. SortedDictionary with Indexers:"
    sorted := new SortedDictionary<string, string>() { "Striped animal", "Red fruit", "Primate" }

    apple := sorted["apple"]
    print $"apple: {apple}"
    print ""

    // 7. Nested dictionaries
    print "7. Nested Dictionary Structure:"
    config := new Dictionary<string, Dictionary<string, string>>() { new Dictionary<string, string>() { "localhost", "5432" }, new Dictionary<string, string>() { "true", "3600" } }

    dbHost := config["database"]["host"]
    cacheEnabled := config["cache"]["enabled"]
    print $"DB Host: {dbHost}, Cache Enabled: {cacheEnabled}"
    print ""

    print "=== Benefits ==="
    print "1. Cleaner syntax than Add() method calls"
    print "2. Works with any type that has an indexer"
    print "3. Can mix with regular property initializers"
    print "4. Type-safe at compile time"
    print "5. Natural dictionary initialization syntax"
}
