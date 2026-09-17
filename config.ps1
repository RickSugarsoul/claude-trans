# Windows PowerShell 5.1; UTF-8 with BOM for Chinese messages.
function Initialize-ClaudeConfig {
    param([string]$Directory = $PSScriptRoot)
    $destination = Join-Path $Directory 'config.json'
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        # No overwrite, including a concurrent first-time setup.
        [IO.File]::Copy((Join-Path $Directory 'config.example.json'), $destination, $false)
    }
    return $destination
}

function Resolve-ConfiguredPath {
    param([string]$Value, [string]$BaseDirectory = $PSScriptRoot)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw '配置文件中的路径不能为空。' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    if ($expanded -match '%[^%]+%') { throw '路径包含未定义的环境变量，请填写完整路径。' }
    if (-not [IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $BaseDirectory $expanded }
    return [IO.Path]::GetFullPath($expanded)
}

function Read-ClaudeConfig {
    param([string]$Path = (Join-Path $PSScriptRoot 'config.json'))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '请先双击 1-配置.bat，填写并保存 config.json。' }
    try { $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw 'config.json 格式错误。请使用英文双引号和逗号，路径中的分隔符建议写 /。' }
    if ($null -eq $config -or $config -isnot [pscustomobject]) { throw 'config.json 必须是一个 JSON 对象。' }
    $required = @('Server', 'User', 'SshPort', 'PrivateKeyPath', 'ChromePath', 'LocalSocksPort', 'ChromeProfilePath', 'ConnectTimeoutSeconds')
    foreach ($field in $required) {
        if ($config.PSObject.Properties.Name -notcontains $field) { throw "config.json 缺少字段：$field。请对照 config.example.json 补齐。" }
    }
    foreach ($field in $config.PSObject.Properties.Name) {
        if ($required -notcontains $field) { throw "config.json 包含不支持的字段：$field。不要把口令或私钥内容写入配置。" }
    }
    foreach ($field in @('Server', 'User', 'PrivateKeyPath', 'ChromePath', 'ChromeProfilePath')) {
        if ($config.$field -isnot [string]) { throw "$field 必须是用双引号括起的文字。" }
    }
    if ($config.Server -notmatch '\A[a-zA-Z0-9][a-zA-Z0-9.:-]*\z') { throw 'Server 请填写服务器 IP 或主机名，不要填写网址。' }
    if ($config.User -notmatch '\A[a-zA-Z_][a-zA-Z0-9_.-]*\z') { throw 'User 请填写 SSH 用户名。' }
    foreach ($spec in @(@('SshPort', 1, 65535), @('LocalSocksPort', 1024, 65535), @('ConnectTimeoutSeconds', 15, 600))) {
        $value = $config.($spec[0])
        if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt $spec[1] -or $value -gt $spec[2]) {
            throw "$($spec[0]) 必须是 $($spec[1]) 到 $($spec[2]) 之间的整数，不要加引号。"
        }
    }
    if ([string]::IsNullOrWhiteSpace($config.PrivateKeyPath)) { throw 'PrivateKeyPath 请填写已有私钥文件的路径，不是私钥口令。' }
    $base = Split-Path ([IO.Path]::GetFullPath($Path))
    $config.PrivateKeyPath = Resolve-ConfiguredPath $config.PrivateKeyPath $base
    if ($config.PrivateKeyPath -match '\.pub$') { throw 'PrivateKeyPath 不能填写 .pub 公钥文件，请使用对应私钥。' }
    if (-not (Test-Path -LiteralPath $config.PrivateKeyPath -PathType Leaf)) { throw '找不到 PrivateKeyPath 指定的私钥文件，请检查路径。' }
    $config.ChromeProfilePath = (Resolve-ConfiguredPath $config.ChromeProfilePath $base).TrimEnd('\', '/')
    $defaultProfile = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Google/Chrome/User Data'))
    if ($config.ChromeProfilePath -ieq $defaultProfile -or $config.ChromeProfilePath.StartsWith($defaultProfile + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ChromeProfilePath 必须使用独立目录，不能使用日常 Chrome 用户数据目录。'
    }
    if ($config.ChromeProfilePath -eq [IO.Path]::GetPathRoot($config.ChromeProfilePath).TrimEnd('\', '/')) { throw 'ChromeProfilePath 不能使用磁盘根目录。' }
    if (-not [string]::IsNullOrWhiteSpace($config.ChromePath)) { $config.ChromePath = Resolve-ConfiguredPath $config.ChromePath $base }
    return $config
}

function Find-ChromeExecutable {
    param([string]$ConfiguredPath)
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) { $candidates = @($ConfiguredPath) }
    else {
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if ($root) { $candidates += Join-Path $root 'Google/Chrome/Application/chrome.exe' }
        }
    }
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and [IO.Path]::GetFileName($candidate) -ieq 'chrome.exe') { return [IO.Path]::GetFullPath($candidate) }
    }
    throw '找不到 Google Chrome。请先安装 Chrome，或在 config.json 的 ChromePath 中填写 chrome.exe 的完整路径。'
}
