namespace NSharpLang.Cli.Daemon

import System.IO

public class DaemonProtocolKernels {
    public static func GetSocketPath(canonicalRoot: string, socketDir: string, socketName: string, tempPath: string, hashPrefix: string, useProjectLocalSocket: bool): string {
        dir := Path.Combine(canonicalRoot, socketDir)
        projectLocalPath := Path.Combine(dir, socketName)

        if useProjectLocalSocket {
            Directory.CreateDirectory(dir)
            return projectLocalPath
        }

        runtimeRoot := Path.Combine(tempPath, "nlc-daemon")
        runtimeDir := Path.Combine(runtimeRoot, hashPrefix)
        Directory.CreateDirectory(runtimeDir)
        return Path.Combine(runtimeDir, socketName)
    }
}
