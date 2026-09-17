$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot) 'claude-via-server.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | ForEach-Object { Write-Host $_.Message }; exit 1 }
Write-Output ('PASS: Windows PowerShell ' + $PSVersionTable.PSVersion + ' parser.')
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
$cs = @"
using System;
using System.Runtime.InteropServices;
public static class ArgvCheck {
  [DllImport("shell32.dll", SetLastError=true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string line, out int count);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr handle);
  public static string[] Parse(string line) {
    int count; IntPtr p = CommandLineToArgvW(line, out count);
    if (p == IntPtr.Zero) throw new Exception("CommandLineToArgvW failed");
    try { string[] result = new string[count]; for(int i=0;i<count;i++) result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(p,i*IntPtr.Size)); return result; }
    finally { LocalFree(p); }
  }
}
"@
Add-Type -TypeDefinition $cs
$expected = @('program.exe', '-i', 'C:\Users\Name With Space\我的密钥', '--user-data-dir=C:\A B\Profile\', '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1', 'quoted"value', '', 'slash\"quote', 'https://claude.ai')
$actual = [ArgvCheck]::Parse((Join-NativeArguments $expected))
if ($actual.Count -ne $expected.Count) { throw 'Argument count mismatch.' }
for ($i = 0; $i -lt $expected.Count; $i++) { if ($actual[$i] -cne $expected[$i]) { throw ('Argument mismatch: ' + $i) } }
Write-Output 'PASS: Windows argv round-trip with spaces, Unicode, quotes, empty argument, trailing backslash and DNS rule.'
