// Duck Interfaces Example
// Demonstrates structural typing with duck interfaces

using System

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
    Console.WriteLine($"Read: {content}")
}

// Function that accepts any IWriter
func ProcessWriter(writer: IWriter) {
    writer.Write("Hello from duck interface!")
}

// Function that accepts any IReadWriter
func ProcessReadWriter(rw: IReadWriter) {
    rw.Write("Test data")
    result := rw.Read()
    Console.WriteLine($"Read/Write result: {result}")
}

// Main function demonstrating duck interface usage
func Main() {
    Console.WriteLine("=== Duck Interface Demo ===")
    Console.WriteLine()

    // FileReader only implements Read, so it works with IReader
    Console.WriteLine("1. FileReader as IReader:")
    fileReader := new FileReader("/path/to/file.txt")
    ProcessReader(fileReader)
    Console.WriteLine()

    // MemoryStore implements both Read and Write
    Console.WriteLine("2. MemoryStore as IReader:")
    memStore := new MemoryStore()
    ProcessReader(memStore)
    Console.WriteLine()

    Console.WriteLine("3. MemoryStore as IWriter:")
    ProcessWriter(memStore)
    Console.WriteLine()

    Console.WriteLine("4. MemoryStore as IReadWriter:")
    ProcessReadWriter(memStore)
    Console.WriteLine()

    // NetworkStream also implements both
    Console.WriteLine("5. NetworkStream as IReadWriter:")
    stream := new NetworkStream("https://example.com")
    ProcessReadWriter(stream)
    Console.WriteLine()

    // Can assign to duck interface variables
    Console.WriteLine("6. Variable assignment with duck interfaces:")
    let reader: IReader = new FileReader("/another/file.txt")
    content := reader.Read()
    Console.WriteLine(content)
    Console.WriteLine()

    Console.WriteLine("=== Demo Complete ===")
}
