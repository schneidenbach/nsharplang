// N# Open-Ended Ranges Example
// Demonstrates C# 8+ open-ended range operators
func PrintArray(arr: int[]) {
    result := "["
    for i := 0; i < arr.Length; i++ {
        result = result + arr[i].ToString()
        if i < arr.Length - 1 {
            result = result + ", "
        }
    }

    result = result + "]"
    print result
}

func Main() {
    numbers := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

    print "Original array:"
    PrintArray(numbers)

    // Open-ended range - from start to index
    print "\nFirst 5 elements (..5):"
    first5 := numbers[..5]
    PrintArray(first5)

    // Open-ended range - from index to end
    print "\nLast 5 elements (5..):"
    last5 := numbers[5..]
    PrintArray(last5)

    // Fully open range - entire array (copy)
    print "\nEntire array copy (..):"
    copy := numbers[..]
    PrintArray(copy)

    // Open-ended with index from end
    print "\nAll except last 2 (..^2):"
    exceptLast := numbers[..^2]
    PrintArray(exceptLast)

    // From index from end to end
    print "\nLast 3 elements (^3..):"
    lastThree := numbers[^3..]
    PrintArray(lastThree)

    // Middle slice combining regular and open-ended
    print "\nMiddle elements (2..^2):"
    middle := numbers[2..^2]
    PrintArray(middle)

    // Strings also support ranges!
    text := "Hello, World!"
    print "\nOriginal string: " + text

    print "First 5 chars (..5): " + text[..5]
    print "Last 6 chars (7..): " + text[7..]
    print "Middle chars (3..^3): " + text[3..^3]

    // Practical example: pagination
    print "\n--- Pagination Example ---"
    items := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    pageSize := 5
    totalPages := (items.Length + pageSize - 1) / pageSize

    for i := 0; i < totalPages; i++ {
        start := i * pageSize
        end := start + pageSize

        // Use open-ended range if on last page
        page := i == totalPages - 1 ? items[start..] : items[start..end]

        print $"Page {i + 1}:"
        PrintArray(page)
    }
}
