using System
using System.Collections.Generic
using System.Threading.Tasks

// Example 1: Basic async stream (async iterator)
func async* GetNumbersAsync(): IAsyncEnumerable<int> {
    for i := 0; i < 10; i++ {
        await Task.Delay(100)
        yield i
    }
}

// Example 2: Async stream with data processing
func async* ProcessDataAsync(items: string[]): IAsyncEnumerable<string> {
    for item in items {
        await Task.Delay(50)
        result := item.ToUpper()
        yield result
    }
}

// Example 3: Consuming async streams with await foreach
func async ConsumeNumbersAsync() {
    print "Starting to consume numbers..."

    await foreach num in GetNumbersAsync() {
        print $"Received: {num}"
    }

    print "Done consuming numbers!"
}

// Example 4: Consuming and transforming async streams
func async ProcessAndDisplayAsync() {
    items := ["hello", "world", "async", "streams"]

    print "Processing items..."

    await foreach processed in ProcessDataAsync(items) {
        print $"Processed: {processed}"
    }

    print "All items processed!"
}

// Example 5: Async stream with infinite sequence
func async* InfiniteSequenceAsync(): IAsyncEnumerable<int> {
    i := 0
    while true {
        await Task.Delay(200)
        yield i++
    }
}

// Main function demonstrating async streams
func async Main() {
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
    await foreach num in InfiniteSequenceAsync() {
        print $"Value: {num}"
        count++
        if count >= 5 {
            break
        }
    }

    print ""
    print "=== Demo Complete ==="
}
