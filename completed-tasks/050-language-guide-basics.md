# Task 050: Language Guide (Basics)

**Effort:** Small (6-8 hours)
**Depends:** Task 049
**Ships:** Basic language documentation

## Goal

Document core N# syntax and features.

## Deliverable

Markdown docs covering basics.

## Content

**docs/guide/basics.md:**

### Variables
```n#
x := 5              // Type inference
y: int = 10         // Explicit type
name: string = "Alice"
```

### Functions
```n#
func add(a: int, b: int): int {
    return a + b
}

func greet(name: string) {
    print $"Hello, {name}!"
}
```

### Control Flow
```n#
if x > 5 {
    print "big"
} else {
    print "small"
}

while x > 0 {
    x -= 1
}

for item in items {
    print item
}
```

### Collections
```n#
numbers := [1, 2, 3]
person := new { name: "Alice", age: 30 }
```

### Types
```n#
class Person {
    Name: string
    Age: int
}

enum Status {
    Active = "active",
    Inactive = "inactive"
}
```

## Structure

```
docs/
├── README.md (index)
├── guide/
│   ├── basics.md
│   ├── functions.md (later)
│   └── types.md (later)
```

## Done When

- [ ] Basics documented
- [ ] Code examples work
- [ ] Linked from website
- [ ] Searchable
