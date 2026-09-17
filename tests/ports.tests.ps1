$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot) 'claude-via-server.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors.Message -join '; ') }
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($function.Extent.Text)) }
function Get-NetTCPConnection { throw 'Invalid class (regression: CIM unavailable)' }
$listenerCode = @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public sealed class SocksProbe : IDisposable {
    TcpListener listener;
    Thread worker;
    volatile bool running;
    public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
    public SocksProbe() {
        listener=new TcpListener(IPAddress.Loopback,0); listener.Start(); running=true;
        worker=new Thread(Run); worker.IsBackground=true; worker.Start();
    }
    void Run() {
        while(running) {
            try {
                using(TcpClient client=listener.AcceptTcpClient()) {
                    client.ReceiveTimeout=1000;
                    var stream=client.GetStream();
                    if(stream.ReadByte()==5 && stream.ReadByte()==1 && stream.ReadByte()==0) stream.Write(new byte[]{5,0},0,2);
                }
            } catch { if(!running) return; }
        }
    }
    public void Dispose() { running=false; listener.Stop(); worker.Join(2000); }
}
"@
Add-Type -TypeDefinition $listenerCode
$probe=New-Object SocksProbe
$port=$probe.Port
try {
    if(-not (Test-SocksReady $port)) { throw 'SOCKS handshake failed.' }
    if(-not (Test-TunnelPortOwner -Port $port -ProcessId $PID)) { throw 'Failed to identify the actual owner.' }
    if(Test-TunnelPortOwner -Port $port -ProcessId 2147483647) { throw 'Accepted another process as owner.' }
    if(-not (Test-SocksReady $port)) { throw 'Existing proxy was affected.' }
    $available = Get-FreeSocksPort -Preferred $port
    if ($available -le $port -or $available -gt [Math]::Min($port + 20, 65535)) { throw 'Occupied port was reused.' }
    if(-not (Test-SocksReady $port)) { throw 'Selecting a port affected the existing proxy.' }
    Write-Output 'PASS: SOCKS readiness + real native port ownership with CIM unavailable.'
    Write-Output 'PASS: Wrong process rejected and listener remains usable.'
} finally { $probe.Dispose() }
if(Test-TunnelPortOwner -Port $port -ProcessId $PID) { throw 'Closed listener still accepted.' }
if(Test-SocksReady $port) { throw 'Closed listener reported ready.' }
Write-Output 'PASS: Closed listener rejected.'
Write-Output 'PASS: Windows PowerShell 5.1 syntax. No private keys, real SSH or Chrome used.'
