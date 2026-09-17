# Run from a source checkout. Only these public files enter the ZIP.
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$files = @(
    '1-配置.bat', '2-记住密钥口令.bat', '3-打开Claude.bat',
    'config.example.json', 'config.ps1', 'edit-config.ps1',
    'remember-key.ps1', 'claude-via-server.ps1', 'browser.ps1',
    'README.md', 'LICENSE', 'docs/TROUBLESHOOTING.md'
)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$zipPath = Join-Path $output 'claude-trans-v1.0.0.zip'
if (Test-Path -LiteralPath $zipPath) { throw 'Output already exists. Use another output directory or remove the old ZIP yourself.' }
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in $files) {
        $source = Join-Path $PSScriptRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing release file: $relative" }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, ('claude-trans/' + $relative), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zipPath + '.sha256'), ($hash + '  ' + [IO.Path]::GetFileName($zipPath) + "`n"), [Text.UTF8Encoding]::new($false))
Write-Output $zipPath
Write-Output ('SHA256: ' + $hash)
