namespace SystemsProofs.FixedCapacityMap

import System

enum MapError {
    Full
    Missing
}

struct Entry {
    Key: int
    Value: int
    Used: bool
}

struct FixedMap {
    entries: Entry[]
}

[boundary]
func NewMap(capacity: int): FixedMap {
    return FixedMap { entries: alloc new Entry[capacity] }
}

[hot]
func Put(map: &FixedMap, key: int, value: int): Result<Unit, MapError> {
    for i := 0; i < map.entries.Length; i++ {
        if !map.entries[i].Used || map.entries[i].Key == key {
            map.entries[i] = Entry { Key: key, Value: value, Used: true }
            return Ok(unit)
        }
    }
    return Err(MapError.Full)
}

[hot]
func Get(map: &FixedMap, key: int): Result<int, MapError> {
    for i := 0; i < map.entries.Length; i++ {
        if map.entries[i].Used && map.entries[i].Key == key {
            return Ok(map.entries[i].Value)
        }
    }
    return Err(MapError.Missing)
}

func Main() {
    map := NewMap(8)
    _ = Put(ref map, 7, 99)
    print Get(ref map, 7)
}
