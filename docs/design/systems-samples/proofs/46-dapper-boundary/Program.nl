namespace SystemsProofs.DapperBoundary

duck interface UserRowSource {
    func ReadFirst(): UserRow
}

struct UserRow {
    Id: int
    NameLength: int
    Active: bool
}

struct UserDto {
    Id: int
    NameLength: int
    Active: bool
}

enum DbError {
    NoRows,
    InvalidName
}

class InMemoryRows {
    func ReadFirst(): UserRow {
        return new UserRow { Id: 7, NameLength: 5, Active: true }
    }
}

[boundary]
func LoadFirstUser(rows: UserRowSource): Result<UserDto, DbError> {
    scratch := alloc new byte[8]
    row := rows.ReadFirst()

    if row.Id <= 0 {
        return Err(DbError.NoRows)
    }
    if row.NameLength <= 0 {
        return Err(DbError.InvalidName)
    }

    scratch[0] = (byte)row.NameLength
    nameLength := (int)scratch[0]
    return Ok(new UserDto { Id: row.Id, NameLength: nameLength, Active: row.Active })
}

[hot]
func IsActiveUser(user: UserDto): bool {
    return user.Active && user.Id > 0 && user.NameLength > 0
}

[boundary]
func Main(): int {
    rows := new InMemoryRows()
    result := LoadFirstUser(rows)
    if result.IsOk == false {
        return 1
    }
    if IsActiveUser(result.OkValueUnchecked) == false {
        return 2
    }
    return 0
}
