namespace Census.FreeFunctionIdentity.MemberShadow

import System


// The namespace's free functions that `MemberShadow.nl`'s types hide from ANOTHER file. The emitter's
// sibling table holds these beside the calling file's own, and the analyzer finds them through
// project function discovery; a member of the enclosing type answers before either.
func Title(): int => 4

func Tag(): int => 5

func Pick(): int => 6

// Not hidden anywhere: the nested-lambda row routes its inner lambda through it.
func CallThrough(read: Func<string>): string => read()
