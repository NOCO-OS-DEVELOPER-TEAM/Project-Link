using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

namespace ProjectLink.Core;

public static class AppLauncher
{
    public static IReadOnlyList<(string Name, string Path)> Search(string query, int limit = 12)
    {
        var q = query.Trim();
        if (q.Length == 0) return Array.Empty<(string, string)>();
        var results = new List<(string, string)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void Consider(string name, string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;
            if (!name.Contains(q, StringComparison.OrdinalIgnoreCase) &&
                !Path.GetFileNameWithoutExtension(path).Contains(q, StringComparison.OrdinalIgnoreCase))
                return;
            if (!seen.Add(path)) return;
            results.Add((name, path));
        }

        // Start Menu shortcuts
        var dirs = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)
        };
        foreach (var dir in dirs)
        {
            if (!Directory.Exists(dir)) continue;
            foreach (var lnk in Directory.EnumerateFiles(dir, "*.lnk", SearchOption.AllDirectories).Take(400))
            {
                Consider(Path.GetFileNameWithoutExtension(lnk), ResolveShortcut(lnk) ?? lnk);
                if (results.Count >= limit) return results;
            }
        }

        // App Paths registry
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths");
            if (key != null)
            {
                foreach (var sub in key.GetSubKeyNames())
                {
                    using var sk = key.OpenSubKey(sub);
                    var path = sk?.GetValue("") as string;
                    if (path != null) Consider(Path.GetFileNameWithoutExtension(sub), path.Trim('"'));
                    if (results.Count >= limit) break;
                }
            }
        }
        catch { }

        return results;
    }

    public static bool Launch(string pathOrQuery)
    {
        try
        {
            if (File.Exists(pathOrQuery))
            {
                Process.Start(new ProcessStartInfo(pathOrQuery) { UseShellExecute = true });
                return true;
            }
            var hits = Search(pathOrQuery, 1);
            if (hits.Count > 0)
            {
                Process.Start(new ProcessStartInfo(hits[0].Path) { UseShellExecute = true });
                return true;
            }
            // Shell execute as-is (URI / command)
            Process.Start(new ProcessStartInfo(pathOrQuery) { UseShellExecute = true });
            return true;
        }
        catch { return false; }
    }

    static string? ResolveShortcut(string lnk)
    {
        try
        {
            // Minimal: return .lnk itself — ShellExecute resolves it
            return lnk;
        }
        catch { return null; }
    }
}
