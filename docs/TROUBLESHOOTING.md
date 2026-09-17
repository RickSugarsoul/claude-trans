# 常见问题

先根据错误发生的位置排查：配置打不开 → SSH 接不通 → 密钥认证失败 → Chrome 打不开 → 网页无法访问。服务器的连接信息以你自己的 `config.json` 为准。

## 私钥、口令、公钥分别是什么

| 名称 | 常见样子 | 用途 |
| --- | --- | --- |
| 私钥文件 | 本机 `.ssh` 文件夹里的 `claude_trans`，也可能有 `.pem` 等后缀 | 留在本机；在 `PrivateKeyPath` 中填写它的路径。 |
| 私钥口令 | `Enter passphrase for key ...` 后输入的文字 | 解锁私钥；通过 `2-记住密钥口令.bat` 输入，不写入配置。 |
| 公钥文件 | `claude_trans.pub`；内容通常是一整行 `ssh-ed25519 ...` | 放到服务器对应用户的 `~/.ssh/authorized_keys`。 |
| 服务器账号密码 | `your-user@server's password:` 后输入的文字 | 与私钥口令不同；本工具按密钥方式使用 SSH。 |

私钥没有强制后缀。把公钥或一段口令保存成 `.txt`，都不能变成可用的私钥。已有完整私钥文件时直接使用原文件，避免手工复制损坏格式。详情见 [Microsoft OpenSSH 密钥管理](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)。

## 配置报错、文件找不到

- 配置必须是有效 JSON：双引号、英文逗号，最后一项后面没有多余逗号。
- 路径推荐使用 `/`，例如 `C:/Keys/server_key`；反斜杠要写成 `\\`。
- `PrivateKeyPath` 指向私钥文件，不能是目录，也不能是 `.pub`。
- `%USERPROFILE%`、`%LOCALAPPDATA%` 是配置可用的环境变量格式；不要写 `$env:USERPROFILE`。
- 从 ZIP 中完整解压后再运行，确保 `.bat`、`.ps1` 和配置位于同一套文件夹内。

Windows 资源管理器可开启“查看 → 文件扩展名”，检查是否意外保存为 `config.json.txt`。

## 找不到 ssh，或 ssh-agent 服务不存在

在 PowerShell 运行 `ssh -V`。没有此命令时，按 README 安装 Windows **OpenSSH 客户端**。不要只安装 Git 附带的 SSH 来代替本工具使用的 Windows 服务。

安装后重新打开终端，再运行 `2-记住密钥口令.bat`。若电脑由组织管理而无法安装可选功能，需要由管理员处理。

## 仍然每次要求输入私钥口令

重新双击 `2-记住密钥口令.bat`。成功添加密钥后，在日常使用的同一 Windows 账号下启动工具。

可以在普通 PowerShell 检查代理：

```powershell
Get-Service ssh-agent
& "$env:WINDIR\System32\OpenSSH\ssh-add.exe" -l
```

服务应为 `Running`，第二条应列出已添加密钥的指纹。它不会显示私钥。如果提示 `The agent has no identities`，再执行一次记住口令步骤。如果你配置了不同的私钥，也需要添加新密钥。

若曾用其他管理员账号运行设置，密钥可能添加到了另一 Windows 账号。服务启用与日常添加密钥应分开：服务可由管理员启用，密钥应由日常账号添加。工具正常启动不需要用另一个管理员账号运行。

不要为省略输入而把口令写进脚本、文本文件或 JSON。

## Connection timed out / Connection refused

这是 SSH 连接阶段的问题。先在本机 PowerShell 测试，把服务器和端口换成自己的值：

```powershell
Test-NetConnection your-server.example.com -Port 22
```

`TcpTestSucceeded : False` 表示没有成功建立 TCP 连接。依次检查服务器公网地址、SSH 端口、云控制台防火墙/安全组、服务器自身防火墙和 SSH 服务。Ping 的成败不能代替 SSH 端口检查。

通过已有 Workbench 或云控制台，在 Ubuntu/Debian 服务器查看：

```bash
sudo ss -lntp
sudo systemctl status ssh --no-pager
sudo ufw status verbose
```

确认 SSH 实际监听端口后，按云厂商界面放行该 TCP 端口，来源尽量限制为你本机的公网地址。其他 Linux 发行版的服务可能名为 `sshd`。不要随意重置防火墙或关闭已有管理会话。

`Connection refused` 常见于目标端口没有服务监听；`Connection timed out` 常见于地址、路由或防火墙问题，但都不能单凭一行报错锁定原因。

## Permission denied (publickey)

网络已到达 SSH 服务，但密钥认证没有成功。检查：

1. `User` 是否为正确的服务器用户，而非云平台登录名。
2. `PrivateKeyPath` 是否对应添加到服务器的那把公钥。
3. 服务器公钥是否放在这个用户的 `~/.ssh/authorized_keys`，不是其他账号的目录。
4. 该目录权限是否为 `700`、文件权限是否为 `600`，且归属目标用户。

通过已有服务器会话切换到目标用户，用 `whoami` 确认后查看权限：

```bash
ls -ld ~/.ssh
ls -l ~/.ssh/authorized_keys
```

再从本机单独验证一次，替换示例参数：

```powershell
ssh -i "$env:USERPROFILE\.ssh\claude_trans" -o IdentitiesOnly=yes -p 22 -l your-user your-server.example.com whoami
```

Workbench 登录成功不等于本机公钥已授权。无需为了本工具开启服务器密码登录。

## 第一次提示指纹 / Host key verification failed

SSH 首次连接会要求确认服务器身份。可以通过可信的服务器控制台查看主机公钥指纹，例如：

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

比对客户端提示的算法和指纹；如果提示的是另一算法，应检查对应主机公钥。确认一致后接受。

如果以前连过却提示主机密钥改变，先查明是否重装或更换了服务器，再处理已保存的记录。不要直接清空全部 `known_hosts`，也不要关闭主机校验。[OpenSSH 连接与主机身份说明](https://man.openbsd.org/ssh)

## 本地 1080 端口被占用

可能上次中转仍在运行，或其他代理软件正在使用它。先关闭之前的专用 Chrome 和中转窗口，再启动一次。也可双击 `1-配置.bat`，将 `LocalSocksPort` 改成未被占用的端口，如 `1081`。

这是本机端口，无需去云服务器防火墙放行 1080。不要为排错结束所有 SSH 进程。

## SSH 连上了，但网页提示 ERR_PROXY_CONNECTION_FAILED

查看启动窗口中是否有 SSH 退出、连接断开、`administratively prohibited` 等报错。后者可能表示服务器禁止 TCP 转发，需要服务器管理员检查针对该用户或密钥的转发限制。

关闭全部专用 Chrome 窗口，再双击 `3-打开Claude.bat`。不要在中转退出后继续复用旧的专用窗口。

若 TCP 连接成功仍无法访问网站，可通过服务器终端检查它到目标网站的 HTTPS 连接。SSH 端口可达与服务器访问网站可达是两件事。

## Chrome 没找到 / 提示专用 Chrome 已运行

`ChromePath` 留空时，工具尝试自动找到 Chrome。非标准安装位置可填写 `chrome.exe` 的完整路径，例如：

```json
"ChromePath": "C:/Program Files/Google/Chrome/Application/chrome.exe"
```

提示专用 Chrome 已运行时，关闭这个专用目录对应的所有窗口再启动。工具使用独立浏览器目录是为了让代理参数生效并保留自己的登录状态；不要把 `ChromeProfilePath` 改成日常 Chrome 的用户数据目录。

## 网页出现 Cloudflare 验证、403 或访问限制

SSH 中转只改变网络出口，不保证网站接受该出口 IP。在专用 Chrome 中按页面提示手动完成验证。如果仍被拒绝，检查服务器出口、网站支持范围、浏览器状态和账号条件。

`curl` 返回的 `cf-mitigated: challenge` 表示请求触发了 Cloudflare 挑战；不能据此断定 SSH 配置有错。[Cloudflare 说明](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/)

本工具不自动处理或跳过验证码，不提供付费权益。Claude 网页与 Claude Code 的使用条件应分别查看。

## 启动时报“无效类”

旧脚本若依赖 Windows WMI/CIM 网络或进程查询，可能遇到“无效类”。请先确认完整更新了本工具的 `.bat` 和 `.ps1`，没有混用旧文件；保留自己的 `config.json`，并对照新模板检查配置项。

当前公开版的端口检查和专用浏览器监测不依赖这些 WMI/CIM 查询。若新版仍报错，记录发生的步骤、脚本文件名和行号再反馈。不要仅凭这条错误就重置 Windows WMI 存储库。

## 浏览器在本机还是服务器运行

浏览器在本机运行，只是网页请求通过 SSH 连接从服务器发出。它不是服务器远程桌面，也不是全机 VPN；其他应用不会因为启动它而自动走服务器。

Chrome 的 SOCKS 参数主要作用于网页请求；不同组件、扩展与系统设置可能影响网络行为。请保持专用窗口的代理设置，不要安装会修改代理的扩展。[Chromium 说明](https://www.chromium.org/developers/design-documents/network-stack/socks-proxy/)

## 如何停止和清除保存的数据

关闭所有专用 Chrome 窗口，工具会结束自己创建的 SSH 中转。使用中请保留启动窗口；异常退出时先关闭专用 Chrome，检查原中转窗口是否仍在运行。

如果只想从 Windows 代理移除这把密钥，在普通 PowerShell 执行下列命令，并替换为自己的实际私钥路径：

```powershell
& "$env:WINDIR\System32\OpenSSH\ssh-add.exe" -d "$env:USERPROFILE\.ssh\claude_trans"
```

这不会删除私钥文件，也不会移除服务器上的公钥授权。不要使用移除全部密钥的选项，以免影响其他项目。

如要清除网页登录记录，先退出专用 Chrome，再处理 `ChromeProfilePath` 指向的专用目录；删除它会清除该窗口的 Cookie、历史和登录记录。不要误删日常 Chrome 目录。

## 反馈问题时提供什么

提供 Windows 版本、Chrome 版本、运行了哪个入口、最后一段错误和可复现步骤即可。分享截图或输出前去掉个人服务器地址、账号和路径。不要附上私钥、口令、真实 `config.json` 或浏览器数据目录。
