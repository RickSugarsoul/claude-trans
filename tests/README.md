# Local regression tests

Run from the repository root on Windows with Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/run.ps1
```

The tests cover configuration preservation and validation, Windows argument quoting, SOCKS negotiation, TCP listener ownership, occupied ports and native browser profile discovery.

Fixtures use temporary files, loopback sockets and test message windows. They do not read real private keys, start Chrome or connect to a real SSH server. Live SSH authentication and Claude access require separate manual verification in the user's environment.
