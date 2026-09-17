$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "ASSERTION FAILED: $Message" }
}
function Get-CimInstance { throw 'Invalid class' }
$implementation = Join-Path (Split-Path $PSScriptRoot) 'browser.ps1'
$tokens = $null; $parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($implementation, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Native browser module parses.'
. $implementation
. $implementation
Write-Output 'PASS: native module can load twice without CIM.'
# This fixture creates real Win32 message-only windows on its own thread.
# All handles belong to the test process; it never opens or controls Chrome.
if (-not ('ClaudeBrowserWindowFixture' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public sealed class ClaudeBrowserWindowFixture : IDisposable {
    private delegate IntPtr WindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX {
        public uint cbSize;
        public uint style;
        public WindowProc lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MSG {
        public IntPtr hWnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int x;
        public int y;
        public uint lPrivate;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassExW(ref WNDCLASSEX value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string className, string title,
        uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu,
        IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DefWindowProcW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetMessageW(out MSG message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr DispatchMessageW(ref MSG message);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostThreadMessageW(uint threadId, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool UnregisterClassW(string className, IntPtr instance);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandleW(string module);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    private readonly Thread thread;
    private readonly string className;
    private readonly string[] titles;
    private readonly WindowProc windowProc;
    private readonly ManualResetEvent ready = new ManualResetEvent(false);
    private Exception startupError;
    private uint threadId;
    private bool disposed;
    public bool CleanupSucceeded { get; private set; }

    public ClaudeBrowserWindowFixture(string windowClass, string[] windowTitles) {
        className = windowClass;
        titles = windowTitles;
        windowProc = DefWindowProcW;
        thread = new Thread(Run);
        thread.IsBackground = true;
        thread.Start();
        if (!ready.WaitOne(5000)) { Dispose(); throw new TimeoutException("Fixture startup timed out."); }
        if (startupError != null) { Dispose(); throw startupError; }
    }
    private void Run() {
        IntPtr instance = GetModuleHandleW(null);
        var windows = new List<IntPtr>();
        bool registered = false;
        try {
            threadId = GetCurrentThreadId();
            var windowClass = new WNDCLASSEX();
            windowClass.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
            windowClass.lpfnWndProc = windowProc;
            windowClass.hInstance = instance;
            windowClass.lpszClassName = className;
            if (RegisterClassExW(ref windowClass) == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            registered = true;
            foreach (string title in titles) {
                IntPtr handle = CreateWindowExW(0, className, title, 0, 0, 0, 0, 0,
                    new IntPtr(-3), IntPtr.Zero, instance, IntPtr.Zero);
                if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                windows.Add(handle);
            }
            ready.Set();
            MSG message;
            int result;
            while ((result = GetMessageW(out message, IntPtr.Zero, 0, 0)) > 0) {
                DispatchMessageW(ref message);
            }
            if (result == -1) throw new Win32Exception(Marshal.GetLastWin32Error());
        } catch (Exception error) {
            startupError = error;
            ready.Set();
        } finally {
            bool cleaned = true;
            foreach (IntPtr handle in windows) cleaned &= DestroyWindow(handle);
            if (registered) cleaned &= UnregisterClassW(className, instance);
            CleanupSucceeded = cleaned;
        }
    }
    public void Dispose() {
        if (disposed) return;
        disposed = true;
        if (thread.IsAlive && threadId != 0) PostThreadMessageW(threadId, 0x0012, UIntPtr.Zero, IntPtr.Zero);
        if (!thread.Join(5000)) throw new TimeoutException("Fixture thread failed to stop.");
        ready.Dispose();
        GC.KeepAlive(windowProc);
    }
}
'@
}

$unique = [Guid]::NewGuid().ToString('N')
$profile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('fixture profile ' + $unique)))
$sibling = $profile + '-sibling'
$wrongClassProfile = $profile + '-wrong-class'
$fixture = $null
$wrongClassFixture = $null
try {
    $fixture = New-Object ClaudeBrowserWindowFixture('Chrome_MessageWindow', [string[]]@($profile, $sibling))
    $wrongClassFixture = New-Object ClaudeBrowserWindowFixture('ClaudeBrowser_QA_MessageWindow', [string[]]@($wrongClassProfile))
    # Catches falling back to WMI, matching only prefixes, or dropping ProcessId.
    $found = @(Get-ProfileBrowsers $profile)
    Assert-True ($found.Count -eq 1) 'Exactly the requested profile is returned.'
    Assert-True ($found[0].ProcessId -eq $PID) 'Returned ProcessId is the real window owner.'
    Assert-True (@(Get-ProfileBrowsers $sibling).Count -eq 1) 'Another exact profile remains discoverable.'
    Assert-True (@(Get-ProfileBrowsers ($profile + '-missing')).Count -eq 0) 'A missing profile returns no elements.'
    Assert-True (@(Get-ProfileBrowsers ($profile.Substring(0, $profile.Length - 1))).Count -eq 0) 'A profile prefix must not match.'
    Assert-True (@(Get-ProfileBrowsers $wrongClassProfile).Count -eq 0) 'A same-title window with another class must not match.'
    Write-Output 'PASS: real native windows are found by exact profile and correct ProcessId without CIM.'
} finally {
    if ($null -ne $wrongClassFixture) { $wrongClassFixture.Dispose() }
    if ($null -ne $fixture) { $fixture.Dispose() }
}
Assert-True $fixture.CleanupSucceeded 'Test windows and class are destroyed.'
Assert-True $wrongClassFixture.CleanupSucceeded 'Other-class test windows and class are destroyed.'
Assert-True (@(Get-ProfileBrowsers $profile).Count -eq 0) 'Closed profile is no longer present.'
Write-Output 'PASS: closing the fixture removes the tracked profile; all test windows were cleaned up.'
Write-Output ('PASS: completed on Windows PowerShell ' + $PSVersionTable.PSVersion.ToString())
