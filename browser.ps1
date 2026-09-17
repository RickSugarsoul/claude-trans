# Windows PowerShell 5.1; no CIM/WMI provider is required.
# Chromium identifies the browser for a user-data directory using a message-only
# window with class Chrome_MessageWindow and the directory path as its title.
# https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/win/chrome_process_finder.cc
# https://chromium.googlesource.com/chromium/src/+/lkgr/base/win/message_window.cc
# The caller supplies the same absolute path passed to --user-data-dir.
if (-not ('ClaudeLauncher.NativeProfileBrowser' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ClaudeLauncher {
    public static class NativeProfileBrowser {
        [DllImport("user32.dll", EntryPoint = "FindWindowExW", ExactSpelling = true,
            CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter,
            string className, string title);

        [DllImport("user32.dll", ExactSpelling = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        public static uint FindProcessId(string profile) {
            if (String.IsNullOrEmpty(profile)) return 0;
            IntPtr window = FindWindowEx(new IntPtr(-3), IntPtr.Zero,
                "Chrome_MessageWindow", profile);
            if (window == IntPtr.Zero) return 0;
            uint processId;
            if (GetWindowThreadProcessId(window, out processId) == 0) return 0;
            return processId;
        }
    }
}
'@
}

function Get-ProfileBrowsers {
    param([string]$Profile)
    $browserProcessId = [ClaudeLauncher.NativeProfileBrowser]::FindProcessId($Profile)
    if ($browserProcessId -ne 0) {
        [pscustomobject]@{ ProcessId = $browserProcessId }
    }
}
