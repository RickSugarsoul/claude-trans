# Run with Windows PowerShell 5.1. No network or private key contents are used.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
if (-not (Test-Path (Join-Path $repo 'config.ps1'))) { throw 'Configuration module is missing.' }
. (Join-Path $repo 'config.ps1')
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "Unexpected error: $($_.Exception.Message)"
    }
    throw "Expected rejection: $Pattern"
}
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('claude-trans-config-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    Copy-Item (Join-Path $repo 'config.example.json') $scratch
    $path = Initialize-ClaudeConfig -Directory $scratch
    $raw = [IO.File]::ReadAllText($path)
    $example = $raw | ConvertFrom-Json
    Assert-True ([string]::IsNullOrEmpty($example.Server) -and [string]::IsNullOrEmpty($example.User) -and [string]::IsNullOrEmpty($example.PrivateKeyPath)) 'Template must have no personal settings.'
    Assert-Throws { Read-ClaudeConfig -Path $path } 'Server'
    $example.Server = 'server.example.com'
    $example.User = 'exampleuser'
    $example.PrivateKeyPath = './key with spaces'
    [IO.File]::WriteAllText((Join-Path $scratch 'key with spaces'), 'test fixture, not a key')
    [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
    $expected = [IO.File]::ReadAllText($path)
    Initialize-ClaudeConfig -Directory $scratch | Out-Null
    Assert-True ([IO.File]::ReadAllText($path) -ceq $expected) 'Setup overwrote user config.'
    $loaded = Read-ClaudeConfig -Path $path
    Assert-True ($loaded.PrivateKeyPath -eq (Join-Path $scratch 'key with spaces')) 'Relative key path resolved against wrong directory.'
    Assert-True ($loaded.ChromeProfilePath -eq (Join-Path $env:LOCALAPPDATA 'ClaudeTrans/ChromeProfile')) 'Environment expansion failed.'
    foreach ($invalid in @('https://server.example.com', '-oProxyCommand=bad', "server`nexample")) {
        $example.Server = $invalid
        [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
        Assert-Throws { Read-ClaudeConfig -Path $path } 'Server'
    }
    $example.Server = 'server.example.com'
    foreach ($invalid in @(0, 65536, 22.5, '22')) {
        $example.SshPort = $invalid
        [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
        Assert-Throws { Read-ClaudeConfig -Path $path } 'SshPort'
    }
    $example.SshPort = 22
    $example.PrivateKeyPath = './key.pub'
    [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
    Assert-Throws { Read-ClaudeConfig -Path $path } '\.pub'
    $example.PrivateKeyPath = './key with spaces'
    $example.ChromeProfilePath = '%LOCALAPPDATA%/Google/Chrome/User Data'
    [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
    Assert-Throws { Read-ClaudeConfig -Path $path } 'ChromeProfilePath'
    $example.ChromeProfilePath = '%LOCALAPPDATA%/ClaudeTrans/ChromeProfile'
    $example | Add-Member -NotePropertyName Password -NotePropertyValue 'test-only'
    [IO.File]::WriteAllText($path, ($example | ConvertTo-Json))
    Assert-Throws { Read-ClaudeConfig -Path $path } 'Password'
    Write-Output 'PASS: config initialization, preservation, paths and invalid input rejection.'
} finally {
    if ([IO.Path]::GetFileName($scratch) -like 'claude-trans-config-test-*') { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
