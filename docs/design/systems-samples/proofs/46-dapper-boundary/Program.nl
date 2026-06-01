namespace SystemsProofs.DapperBoundary

import System
import System.Collections.Generic
import System.Data
import Dapper

record UserRow {
    Id: int
    Name: string
}

record UserDto {
    Id: int
    Name: string
}

[boundary]
func LoadUsers(db: IDbConnection): Result<List<UserDto>, string> {
    try {
        rows := db.Query<UserRow>("select Id, Name from Users")
        users := alloc new List<UserDto>()
        for row in rows {
            users.Add(UserDto { Id: row.Id, Name: row.Name })
        }
        return Ok(users)
    } catch ex {
        return Err(ex.Message)
    }
}

func Main() {
    print "database boundary proof"
}
