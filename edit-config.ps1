$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'config.ps1')
    $path = Initialize-ClaudeConfig
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/notepad.exe') -ArgumentList ('"' + $path + '"')
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
