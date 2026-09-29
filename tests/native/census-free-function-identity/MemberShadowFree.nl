namespace Census.FreeFunctionIdentity.MemberShadow

import System


// The namespace's free functions that collide by name with members in `MemberShadow.nl`. Member
// call sites use `this.` to select their member group; an unqualified collision reports NL209.
func Title(): int => 4

func Tag(): int => 5

func Pick(): int => 6

// Not hidden anywhere: the nested-lambda row routes its inner lambda through it.
func CallThrough(read: Func<string>): string => read()
