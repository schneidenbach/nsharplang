namespace WeatherDemo.Models

import System
import System.Threading.Tasks

// Format-on-save probe: hand-wrapped call, long single-line call, hugged lambda block,
// multi-line attribute and raw string. Only the hand-wrapped call may change on save.
class FormatProbe {
    [memory(safe)]
    [trusted(reason = "probe: nothing unsafe happens here", owner = "ide-verification", review = "2026-12-01")]
    static func Describe(names: string[]): string {
        joined := String.Join(
            ", ",
            names
        )
        longLine := String.Join(" | ", "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu")
        job := Task.Run(() => {
            print "background"
        })
        job.Wait()
        return joined + longLine
    }
}
