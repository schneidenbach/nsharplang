import System
import System.Collections.Generic
import System.Threading.Tasks


// Example 1: Basic async stream (async iterator)
async func* GetNumbersAsync(): IAsyncEnumerable<int> {
    for i := 0; i < 10; i++ {
        await Task.Delay(100)
        yield i
    }
}

// Example 2: Async stream with data processing
async func* ProcessDataAsync(items: string[]): IAsyncEnumerable<string> {
    for item in items {
        await Task.Delay(50)
        result := item.ToUpper()
        yield result
    }
}

// Example 3: Consuming async streams with await foreach
async func ConsumeNumbersAsync() {
    print "Starting to consume numbers..."

    print "Done consuming numbers!"
}

// Example 4: Consuming and transforming async streams
async func ProcessAndDisplayAsync() {
    items := ["hello", "world", "async", "streams"]

    print "Processing items..."

    print "All items processed!"
}

// Example 5: Async stream with infinite sequence
async func* InfiniteSequenceAsync(): IAsyncEnumerable<int> {
    i := 0
    while true {
        await Task.Delay(200)
        yield i++
    }
}

// Main function demonstrating async streams
async func Main() {
    print "=== Async Streams Demo ==="
    print ""

    // Example 1: Basic consumption
    await ConsumeNumbersAsync()
    print ""

    // Example 2: Data processing
    await ProcessAndDisplayAsync()
    print ""

    // Example 3: Manual iteration
    print "Manual iteration with limited count:"
    count := 0

    print ""
    print "=== Demo Complete ==="
}
