namespace SystemsProofs.FixedCapacityMap

enum MapError {
    Ok,
    Full,
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
    actualCapacity := capacity
    if capacity < 0 {
        actualCapacity = 0
    }
    entries := alloc new Entry[actualCapacity]
    return new FixedMap { entries: entries }
}

[hot]
func Put(map: &FixedMap, key: int, value: int): MapError {
    for i := 0; i < map.entries.Length; i++ {
        if !map.entries[i].Used || map.entries[i].Key == key {
            map.entries[i] = new Entry { Key: key, Value: value, Used: true }
            return MapError.Ok
        }
    }
    return MapError.Full
}

[hot]
func Get(map: &FixedMap, key: int): Result<int, MapError> {
    for i := 0; i < map.entries.Length; i++ {
        entry := map.entries[i]
        if entry.Used {
            if entry.Key == key {
                return Ok(entry.Value)
            }
        }
    }
    return Err(MapError.Missing)
}

func Main(): int {
    map := NewMap(8)
    put := Put(ref map, 7, 99)
    if put != MapError.Ok {
        return 1
    }

    found := Get(ref map, 7)
    if found.IsOk == false {
        return 2
    }

    if found.OkValueUnchecked != 99 {
        return 3
    }

    missing := Get(ref map, 8)
    if missing.IsErr == false {
        return 4
    }

    if missing.ErrValueUnchecked != MapError.Missing {
        return 5
    }

    return 0
}
