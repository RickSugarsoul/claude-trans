# Enable the Windows SSH key agent once, then add the key as the original user.
[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'config.ps1')
    $config = Read-ClaudeConfig
    $keyPath = $config.PrivateKeyPath
    $sshAdd = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-add.exe'
    if (-not (Test-Path -LiteralPath $sshAdd -PathType Leaf)) { throw '找不到 Windows OpenSSH 的 ssh-add.exe，请安装 Windows OpenSSH 客户端。' }
    $service = Get-Service -Name ssh-agent -ErrorAction Stop
    if ($CheckOnly) {
        Write-Output '检查通过。未修改服务、未解锁密钥。'
        exit 0
    }
    if ($service.Status -ne 'Running' -or $service.StartType -ne 'Automatic') {
        Write-Host '首次设置需要启用 Windows SSH 密钥服务。若出现系统权限窗口，请点“是”。'
        # Only service management runs elevated; never add the key under another user.
        $serviceSetup = @'
$ErrorActionPreference = 'Stop'
try {
    Set-Service -Name ssh-agent -StartupType Automatic
    Start-Service -Name ssh-agent
    (Get-Service -Name ssh-agent).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
    exit 0
} catch { exit 1 }
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($serviceSetup))
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $elevated = Start-Process -FilePath $powershell -ArgumentList "-NoLogo -NoProfile -EncodedCommand $encoded" -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if ($elevated.ExitCode -ne 0) { throw '启用密钥服务未成功，请用有本机管理员权限的账号完成系统授权。' }
    }
    if ((Get-Service ssh-agent).Status -ne 'Running') { throw 'Windows SSH 密钥服务未运行。' }
    Write-Host "将使用已有私钥：$keyPath"
    Write-Host '接下来输入你之前 Enter passphrase 提示后填写的那个密码。输入时不会显示字符。' -ForegroundColor Cyan
    Write-Host '口令只在这里输入，程序不会将口令写进配置文件。'
    & $sshAdd $keyPath
    if ($LASTEXITCODE -ne 0) { throw '密钥未加入 Windows 密钥服务，请重新运行并确认口令正确。' }
    Write-Host '设置完成。以后双击 3-打开Claude.bat 即可。' -ForegroundColor Green
    Write-Host '如果更换 Windows 用户、重置密钥服务或清空缓存，需要再运行一次本设置。'
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
