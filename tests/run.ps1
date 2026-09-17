$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors.Message -join '; ') }
}
Write-Output 'PASS: all PowerShell files parse.'
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
foreach ($test in @('config.tests.ps1', 'arguments.tests.ps1', 'ports.tests.ps1', 'browser.tests.ps1')) {
    & $powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
Write-Output 'PASS: local regression tests completed. No real SSH login or Claude access tested.'
