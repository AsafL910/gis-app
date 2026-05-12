using System.Diagnostics;
using System.Security.Principal;

namespace GlbDemoBootstrapper;

internal static class Program
{
    private static int Main(string[] args)
    {
        BootstrapperOptions? options = null;
        try
        {
            options = ParseArguments(args);
            if (options.ShowHelp)
            {
                PrintUsage();
                WaitForExitConfirmation(options, "Help shown.");
                return 0;
            }

            if (!IsRunningAsAdministrator() && !options.IsElevated)
            {
                return RelaunchElevated(args);
            }

            var exePath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrWhiteSpace(exePath))
            {
                Console.Error.WriteLine("Could not determine the installer path.");
                WaitForExitConfirmation(options, "Installer startup failed.");
                return 1;
            }

            var packageDir = Path.GetDirectoryName(exePath) ?? string.Empty;
            Console.WriteLine("Using deploy_package folder next to Setup.exe...");

            var installScript = Path.Combine(packageDir, "install.ps1");

            if (!File.Exists(installScript))
            {
                Console.Error.WriteLine("An install script was not found in the package.");
                WaitForExitConfirmation(options, "Installer startup failed.");
                return 1;
            }

            var scriptArguments = BuildInstallScriptArguments(options, installScript);
            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = scriptArguments,
                WorkingDirectory = packageDir,
                UseShellExecute = false
            };

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                Console.Error.WriteLine("Failed to start the install script.");
                WaitForExitConfirmation(options, "Installer startup failed.");
                return 1;
            }

            process.WaitForExit();
            Console.WriteLine("Installer finished with exit code {0}.", process.ExitCode);
            if (process.ExitCode == 0)
            {
                WaitForExitConfirmation(options, "Installation finished successfully.");
            }
            else
            {
                WaitForExitConfirmation(options, "Installation failed. Review the messages above.");
            }
            return process.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            WaitForExitConfirmation(options, "Installer crashed. Review the error above.");
            return 1;
        }
    }

    private static BootstrapperOptions ParseArguments(IEnumerable<string> args)
    {
        var options = new BootstrapperOptions();
        var items = args.ToList();

        for (var index = 0; index < items.Count; index++)
        {
            var arg = items[index];
            if (string.Equals(arg, "--elevated", StringComparison.OrdinalIgnoreCase))
            {
                options.IsElevated = true;
                continue;
            }

            if (string.Equals(arg, "/quiet", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "/silent", StringComparison.OrdinalIgnoreCase))
            {
                options.Quiet = true;
                continue;
            }

            if (string.Equals(arg, "/uninstall", StringComparison.OrdinalIgnoreCase))
            {
                options.Uninstall = true;
                continue;
            }

            if (string.Equals(arg, "/help", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "/?", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "-h", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "--help", StringComparison.OrdinalIgnoreCase))
            {
                options.ShowHelp = true;
                continue;
            }

            if (string.Equals(arg, "/log", StringComparison.OrdinalIgnoreCase) && index + 1 < items.Count)
            {
                options.LogPath = items[++index];
                continue;
            }

            if (string.Equals(arg, "/installdir", StringComparison.OrdinalIgnoreCase) && index + 1 < items.Count)
            {
                options.InstallDir = items[++index];
            }
        }

        return options;
    }

    private static bool IsRunningAsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static int RelaunchElevated(IEnumerable<string> args)
    {
        var exePath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
        if (string.IsNullOrWhiteSpace(exePath))
        {
            Console.Error.WriteLine("Could not determine the installer path for elevation.");
            return 1;
        }

        var allArgs = new List<string>(args) { "--elevated" };
        var joinedArgs = string.Join(" ", allArgs.Select(QuoteArgument));

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = exePath,
                Arguments = joinedArgs,
                UseShellExecute = true,
                Verb = "runas"
            };

            using var process = Process.Start(startInfo);
            return process is null ? 1 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Elevation failed: " + ex.Message);
            return 1;
        }
    }

    private static string QuoteArgument(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "\"\"";
        }

        if (value.IndexOf(' ') < 0 && value.IndexOf('"') < 0)
        {
            return value;
        }

        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static string BuildInstallScriptArguments(BootstrapperOptions options, string installScript)
    {
        var arguments = new List<string>
        {
            "-ExecutionPolicy", "Bypass",
            "-NoProfile",
            "-File", installScript
        };

        if (options.Uninstall)
        {
            arguments.Add("-Uninstall");
        }

        if (options.Quiet)
        {
            arguments.Add("-Quiet");
        }

        if (!string.IsNullOrWhiteSpace(options.InstallDir))
        {
            arguments.Add("-InstallDir");
            arguments.Add(options.InstallDir);
        }

        if (!string.IsNullOrWhiteSpace(options.LogPath))
        {
            arguments.Add("-LogPath");
            arguments.Add(options.LogPath);
        }

        return string.Join(" ", arguments.Select(QuoteArgument));
    }

    private static void PrintUsage()
    {
        Console.WriteLine("GLB Demo Setup");
        Console.WriteLine();
        Console.WriteLine("Interactive install:");
        Console.WriteLine("  Setup.exe");
        Console.WriteLine();
        Console.WriteLine("Silent install:");
        Console.WriteLine("  Setup.exe /quiet /log C:\\Temp\\GlbDemoInstall.log");
        Console.WriteLine();
        Console.WriteLine("Silent uninstall:");
        Console.WriteLine("  Setup.exe /uninstall /quiet /log C:\\Temp\\GlbDemoUninstall.log");
        Console.WriteLine();
        Console.WriteLine("Optional arguments:");
        Console.WriteLine("  /quiet or /silent");
        Console.WriteLine("  /uninstall");
        Console.WriteLine("  /log <path>");
        Console.WriteLine("  /installDir <path>");
        Console.WriteLine("  /help");
    }

    private static void WaitForExitConfirmation(BootstrapperOptions? options, string message)
    {
        if (options?.Quiet == true || Console.IsInputRedirected || Console.IsOutputRedirected)
        {
            return;
        }

        Console.WriteLine();
        Console.WriteLine(message);
        Console.WriteLine("Press Enter to close this window.");

        try
        {
            Console.ReadLine();
        }
        catch
        {
        }
    }

    private sealed class BootstrapperOptions
    {
        public bool IsElevated { get; set; }
        public bool Quiet { get; set; }
        public bool Uninstall { get; set; }
        public bool ShowHelp { get; set; }
        public string? InstallDir { get; set; }
        public string? LogPath { get; set; }
    }
}
