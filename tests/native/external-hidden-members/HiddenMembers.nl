namespace NSharpLang.ExternalHiddenMembers.Tests

import Microsoft.EntityFrameworkCore

// `DbContextOptionsBuilder<TContext>.Options` is declared `new DbContextOptions<TContext> Options`
// over the base class's `DbContextOptions Options`: two instance properties of one name, the derived
// one hiding the base one. Reading it used to abort the build with an `AmbiguousMatchException`
// carrying no code and no position.
class Db: DbContext {
    constructor(options: DbContextOptions<Db>): base(options) {
    }
}

func typedOptionsContext(): string {
    builder := new DbContextOptionsBuilder<Db>()
    return builder.Options.ContextType.Name
}

func baseOptionsContext(): string {
    builder := new DbContextOptionsBuilder()
    return builder.Options.ContextType.Name
}

func baseSpelledOptionsContext(): string {
    typed := new DbContextOptionsBuilder<Db>()
    builder: DbContextOptionsBuilder = typed
    return builder.Options.ContextType.Name
}

func contextFromHiddenOptions(): bool {
    builder := new DbContextOptionsBuilder<Db>()
    db := new Db(builder.Options)
    return db != null
}
