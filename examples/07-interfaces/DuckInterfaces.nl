// Duck Interfaces Example
// Demonstrates structural typing with duck interfaces

// Define a duck interface for anything that can read
duck interface IReader {
    func Read(): string
}

// Define a duck interface for anything that can write
duck interface IWriter {
    func Write(data: string)
}

// Define a duck interface combining read and write
duck interface IReadWriter {
    func Read(): string
    func Write(data: string)
}

// FileReader implements IReader without explicit declaration
class FileReader {
    path: string

    constructor(p: string) {
        path = p
    }

    func Read(): string {
        return $"Reading from file: {path}"
    }
}

// MemoryStore implements both IReader and IWriter (and thus IReadWriter)
class MemoryStore {
    data: string

    constructor() {
        data = ""
    }

    func Read(): string {
        return data
    }

    func Write(d: string) {
        data = d
    }
}

// NetworkStream implements IReadWriter
class NetworkStream {
    url: string
    buffer: string

    constructor(u: string) {
        url = u
        buffer = ""
    }

    func Read(): string {
        return $"Data from {url}: {buffer}"
    }

    func Write(d: string) {
        buffer = d
    }
}

// Function that accepts any IReader
func ProcessReader(reader: IReader) {
    content := reader.Read()
    print $"Read: {content}"
}

// Function that accepts any IWriter
func ProcessWriter(writer: IWriter) {
    writer.Write("Hello from duck interface!")
}

// Function that accepts any IReadWriter
func ProcessReadWriter(rw: IReadWriter) {
    rw.Write("Test data")
    result := rw.Read()
    print $"Read/Write result: {result}"
}

// Main function demonstrating duck interface usage
func Main() {
    print "=== Duck Interface Demo ==="
    print ""

    // FileReader only implements Read, so it works with IReader
    print "1. FileReader as IReader:"
    fileReader := new FileReader("/path/to/file.txt")
    ProcessReader(fileReader)
    print ""

    // MemoryStore implements both Read and Write
    print "2. MemoryStore as IReader:"
    memStore := new MemoryStore()
    ProcessReader(memStore)
    print ""

    print "3. MemoryStore as IWriter:"
    ProcessWriter(memStore)
    print ""

    print "4. MemoryStore as IReadWriter:"
    ProcessReadWriter(memStore)
    print ""

    // NetworkStream also implements both
    print "5. NetworkStream as IReadWriter:"
    stream := new NetworkStream("https://example.com")
    ProcessReadWriter(stream)
    print ""

    // Can assign to duck interface variables
    print "6. Variable assignment with duck interfaces:"
    reader: IReader = new FileReader("/another/file.txt")
    content := reader.Read()
    print content
    print ""

    print "=== Demo Complete ==="
}
