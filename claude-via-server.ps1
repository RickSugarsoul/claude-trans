# Windows PowerShell 5.1. Save this file as UTF-8 with BOM.
[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'

function Join-NativeArguments {
    param([string[]]$Items)
    # Start-Process joins ArgumentList without quoting. Apply Windows argv rules.
    $quoted = foreach ($item in $Items) {
        $value = [regex]::Replace($item, '(\\*)"', '$1$1\"')
        $value = [regex]::Replace($value, '(\\+)$', '$1$1')
        '"' + $value + '"'
    }
    $quoted -join ' '
}

function Test-SocksReady {
    param([int]$Port)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $pending.Wait(300) -or -not $client.Connected) { return $false }
        $stream = $client.GetStream()
        $stream.ReadTimeout = 500
        $stream.WriteTimeout = 500
        $hello = [byte[]](5, 1, 0)
        $stream.Write($hello, 0, $hello.Length)
        return ($stream.ReadByte() -eq 5 -and $stream.ReadByte() -eq 0)
    } catch { return $false }
    finally { $client.Dispose() }
}

function Get-FreeSocksPort {
    param([int]$Preferred)
    foreach ($candidate in $Preferred..([Math]::Min($Preferred + 20, 65535))) {
        $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $candidate)
        try {
            $listener.Server.ExclusiveAddressUse = $true
            $listener.Start()
            return $candidate
        } catch [Net.Sockets.SocketException] {
            # An existing tunnel or application keeps ownership of its port.
        } finally { $listener.Stop() }
    }
    throw '找不到空闲的本地中转端口，请修改配置文件中的 LocalSocksPort。'
}

function Test-TunnelPortOwner {
    param([int]$Port, [int]$ProcessId)
    # netstat uses native TCP APIs instead of the optional NetTCPIP CIM provider.
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'
    $rows = @(& $netstat -ano -p tcp)
    if ($LASTEXITCODE -ne 0) { throw '无法检查本地中转端口归属。' }
    $pattern = '^\s*TCP\s+127\.0\.0\.1:' + $Port + '\s+0\.0\.0\.0:0\s+\S+\s+' + $ProcessId + '\s*$'
    return @($rows | Where-Object { $_ -match $pattern }).Count -gt 0
}

$sshProcess = $null
$mutex = $null
$hasMutex = $false
$resultCode = 0
$stage = '读取配置'

try {
    . (Join-Path $PSScriptRoot 'config.ps1')
    $config = Read-ClaudeConfig
    $sshPort = [int]$config.SshPort
    $preferredPort = [int]$config.LocalSocksPort
    $timeout = [int]$config.ConnectTimeoutSeconds
    $keyPath = $config.PrivateKeyPath
    $chromePath = Find-ChromeExecutable $config.ChromePath
    $profilePath = $config.ChromeProfilePath
    $sshExe = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
    if (-not (Test-Path -LiteralPath $sshExe -PathType Leaf)) { throw '找不到 Windows OpenSSH 客户端。' }
    if ($CheckOnly) {
        Write-Host '配置与文件路径检查通过。未连接服务器，也未启动浏览器。' -ForegroundColor Green
        return
    }

    $mutex = New-Object Threading.Mutex($false, 'Local\ClaudeViaServerLauncher')
    try { $hasMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $hasMutex = $true }
    if (-not $hasMutex) {
        Write-Host '启动器已经在运行，请使用已打开的 Claude 窗口。'
        return
    }
    $stage = '检查专用 Chrome'
    . (Join-Path $PSScriptRoot 'browser.ps1')
    if (@(Get-ProfileBrowsers $profilePath).Count -gt 0) {
        throw '专用 Chrome 仍在运行。请关闭该专用浏览器后重新双击启动器。'
    }

    $stage = '选择本地中转端口'
    $socksPort = Get-FreeSocksPort $preferredPort
    $sshArgs = @(
        '-i', $keyPath, '-p', [string]$sshPort, '-l', [string]$config.User,
        '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=ask',
        '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=20',
        '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
        '-N', '-D', "127.0.0.1:$socksPort", [string]$config.Server
    )
    Write-Host '正在启动 Claude 服务器中转…' -ForegroundColor Cyan
    Write-Host "连接：$($config.User)@$($config.Server):$sshPort"
    Write-Host '先完成 2-记住密钥口令.bat 后，Windows 会自动提供密钥，无需每次输入口令。'
    Write-Host '首次连接若出现主机指纹，请与服务器核对后输入 yes。'
    # Share this console so OpenSSH can interactively request a key passphrase.
    $stage = '连接 SSH'
    $sshProcess = Start-Process -FilePath $sshExe -ArgumentList (Join-NativeArguments $sshArgs) -NoNewWindow -PassThru
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $ready = $false
    while ($timer.Elapsed.TotalSeconds -lt $timeout) {
        if ($sshProcess.HasExited) { throw 'SSH 连接失败，请查看上方的 SSH 错误。Permission denied 通常表示用户名或密钥不匹配。' }
        if (Test-SocksReady $socksPort) {
            # Do not mistake another process taking the port for our own tunnel.
            $stage = '核对 SSH 中转端口'
            if (-not (Test-TunnelPortOwner -Port $socksPort -ProcessId $sshProcess.Id) -or $sshProcess.HasExited) { throw '中转端口没有由本次 SSH 连接持有，请重试。' }
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 400
    }
    if (-not $ready) { throw '等待 SSH 登录超时，请重新启动并完成密钥口令或主机指纹确认。' }

    $stage = '打开 Chrome'
    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
    $chromeArgs = @(
        "--user-data-dir=$profilePath", "--proxy-server=socks5://127.0.0.1:$socksPort",
        '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
        '--disable-quic', '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
        '--disable-background-mode', '--no-first-run', '--no-default-browser-check',
        '--new-window', 'https://claude.ai'
    )
    Start-Process -FilePath $chromePath -ArgumentList (Join-NativeArguments $chromeArgs) | Out-Null
    Write-Host '中转已建立，正在打开 Claude 页面。' -ForegroundColor Green
    Write-Host '请保持此窗口打开；关闭所有专用 Chrome 窗口后，中转会自动结束。'
    Write-Host '网页登录和验证请在 Chrome 中完成。'

    $stage = '等待专用 Chrome 关闭'
    $startup = [Diagnostics.Stopwatch]::StartNew()
    $seenBrowser = $false
    $emptyChecks = 0
    while ($true) {
        if ($sshProcess.HasExited) { throw 'SSH 中转已断开。请关闭专用 Chrome 窗口后重新双击启动器。' }
        $browsers = @(Get-ProfileBrowsers $profilePath)
        if ($browsers.Count -gt 0) {
            $seenBrowser = $true
            $emptyChecks = 0
        } elseif ($seenBrowser) {
            $emptyChecks++
            if ($emptyChecks -ge 2) { break }
        } elseif ($startup.Elapsed.TotalSeconds -gt 30) {
            throw '未检测到专用 Chrome 启动，请检查 Chrome 是否受到系统策略限制。'
        }
        Start-Sleep -Seconds 2
    }
    Write-Host '专用 Chrome 已关闭，正在结束中转。'
} catch {
    $resultCode = 1
    Write-Host "`n未能完成启动（$stage）：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host ('出错行：' + $_.InvocationInfo.ScriptLineNumber)
} finally {
    if ($null -ne $sshProcess) {
        if (-not $sshProcess.HasExited) {
            # Stop only the process created by this launcher, never other SSHs.
            $sshProcess.Kill()
            $sshProcess.WaitForExit(3000) | Out-Null
        }
        $sshProcess.Dispose()
    }
    if ($hasMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $resultCode
