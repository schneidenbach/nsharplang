import System
import System.Linq
import System.Threading.Tasks

func hi(): int {
    throw new Exception("hi")
}

// async func hi_again(){
//     await Task.CompletedTask;
// }

func Main() {
    name := "Spencer"
    greeting := $"Hello, {name}!"
    print greeting

    i, err := hi()
    print err
    print i

    i = 5

    print i

    numbers := [1, 2, 3, 4, 5]
    doubled := numbers.Select(x => x * 2).ToList()

    print "doubled nums:"

    for num in doubled {
        print num
    }
}
