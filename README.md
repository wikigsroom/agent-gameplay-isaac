# Isaac Jev 

面向 **The Binding of Isaac: Repentance** 的本地单人自动游玩演示。游戏内 Lua Mod 通过 Repentance API 读取结构化状态，Python 服务端在本机生成安全候选动作，并使用 Local 策略或可选的远程 Decision Provider 选择动作。

项目不包含游戏本体、游戏资源或任何 API Key。它不是官方 Mod，也不隶属于 Valve、Steam、Nicalis、Edmund McMillen、TypeSafe 或 Bocha。

> 这是实验性演示，不保证完成整局游戏。请使用独立存档和固定种子，不要用于联机、竞速、排行榜或其他会影响他人的环境。

## 功能概览

- Repentance Lua Mod：采集房间、敌人、弹幕、奖励、门、危险格和玩家反馈。
- Python 服务端：TCP 桥、动作生命周期、寻路、战斗候选、安全过滤和本地脱困。
- Local Provider：不需要网络或 API Key，可直接运行。
- 可选远程 Provider：Jev、Bocha、Laya、自托管 System One。
- 本地网页仪表盘：查看实时状态、决策、Provider、调试日志和实验统计。
- MCP stdio 控制面：查询状态、启停自动控制和紧急停止。
- 脱敏轨迹、离线回放统计和有限的本地策略调参。

## 环境要求

- Windows 10/11。
- Steam 版 The Binding of Isaac: Rebirth 和 Repentance DLC。
- Python 3.11 或更高版本；Windows 用户如果已安装 Python 3.12，推荐使用 Python 3.12。
- PowerShell 7（运行文档中的 PowerShell 命令时）。
- 游戏启动参数需要包含 `--luadebug`，以启用 Mod 使用的 LuaSocket 调试运行时。

Python 服务端只依赖标准库，不需要安装第三方运行时包。远程 Provider 是否可用取决于对应服务的地址、模型和账号权限。

## 安装 Python 服务端

在项目根目录打开 PowerShell 7：

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -e .
```

如果你安装的是其他 Python 3.11+ 版本，可将命令中的 `3.12` 替换为对应版本。先运行 `py -0p` 查看 Windows Python Launcher 已注册的版本；Python 3.10 及更低版本不满足本项目要求。

## 安装 Mod

1. 在 Steam 中打开游戏属性，将 `--luadebug` 加入启动选项。
2. 将本项目目录中的相对路径 `./mods/IsaacJev` 整个复制到 Steam 游戏根目录下的相对路径 `./mods/IsaacJev`。Steam 游戏根目录就是包含 `isaac-ng.exe` 的 `The Binding of Isaac Rebirth` 目录。

   ```text
   <Steam游戏根目录>\mods\IsaacJev
   ```

   最终应能看到：

   ```text
   ...\mods\IsaacJev\main.lua
   ...\mods\IsaacJev\metadata.xml
   ```

   也可以在项目根目录用 PowerShell 7 直接复制：

   ```powershell
   $gameRoot = Read-Host '请输入 Steam 游戏根目录（包含 isaac-ng.exe）'
   $isaacMods = Join-Path $gameRoot 'mods'
   Copy-Item -LiteralPath '.\mods\IsaacJev' -Destination $isaacMods -Recurse -Force
   ```

   如果你的 Steam 库安装在其他盘符，只需要修改 `$gameRoot`。复制完成后，游戏应能从相对路径 `./mods/IsaacJev` 读取 Mod；这个项目不使用 Documents 下的旧路径。

3. 启动游戏，在 Mods 菜单启用 **Isaac Jev**。
4. 每次更新 Mod 后，退出并重新启动游戏，确保 Lua 加载磁盘上的新版本。

Mod 只负责游戏侧状态采集和输入执行；Python 服务端必须另外启动。

## 启动服务端

### 推荐方式：本地策略和网页仪表盘

先启动 Python 服务端：

```powershell
.venv\Scripts\python.exe -m isaac_jev.cli --autopilot --web-dashboard --no-dashboard --open-dashboard
```

默认端口：

- TCP 桥：`127.0.0.1:9528`
- 网页仪表盘：<http://127.0.0.1:9529/>

看到 `Isaac Jev bridge listening on 127.0.0.1:9528` 后，再进入游戏。网页仪表盘只监听回环地址，不应通过端口转发暴露到公网。

也可以双击项目根目录的 `start_isaac_jev.cmd`。该脚本要求已经创建 `.venv` 并安装项目。

### 只使用终端面板

```powershell
.venv\Scripts\python.exe -m isaac_jev.cli --autopilot
```

关闭自动控制但保持桥接服务：

```powershell
.venv\Scripts\python.exe -m isaac_jev.cli
```

### MCP 控制面

```powershell
.venv\Scripts\python.exe -m isaac_jev.mcp_server
```

MCP 服务通过 stdio 提供 `autopilot_status`、`autopilot_enable`、`autopilot_disable`、`emergency_stop` 和 `latest_state`。它管理已经运行的本地控制器，不参与逐帧游戏决策。

## 游戏内控制

- 命令行必须带 `--autopilot`，Lua 才允许 Python 动作覆盖玩家输入。
- 游戏内按 **F8** 切换自动控制和人工输入。
- 服务端断开或动作超过约 0.75 秒没有更新时，Lua 会回退人工输入。
- 远程 Provider 超时、报错、低置信度或返回非法动作时，控制器回退到本地安全策略。
- 角色死亡后，控制器清空旧动作；Mod 会等待后尝试自动重新开始。

第一次运行建议先不带 `--autopilot`，确认网页或终端能持续收到游戏帧，再在空房间测试 F8 和人工接管。

## Provider 配置

公开仓库只提交 `config/decision_provider.example.json`。第一次启动服务端时，如果 `config/decision_provider.json` 不存在，程序会自动创建一份不含密钥、默认使用 `local` Provider 的配置；该文件已经被 `.gitignore` 排除。

如果希望启动前就填写远程 Provider，也可以手动从示例复制：

```powershell
Copy-Item -LiteralPath 'config/decision_provider.example.json' -Destination 'config/decision_provider.json'
```

默认配置选择 `local`，不需要 API Key、不需要网络服务即可运行。需要远程 Provider 时，在网页“模型与实验”页或本地配置文件中填写地址、模型、鉴权开关和 API Key。

支持的 Provider：

| Provider | 用途 | 是否需要 API Key |
| --- | --- | --- |
| `local` | 进程内确定性策略 | 否 |
| `jev` | 官方 Jev System One 端点 | 通常需要 |
| `bocha` | Bocha Jev 端点 | 通常需要 |
| `laya` | 用户自行部署的 Laya 服务 | 取决于部署方式 |
| `systemone` | 用户自行部署的兼容服务 | 取决于部署方式 |

示例中的 Laya 和 System One 地址使用 `127.0.0.1` 占位，不代表项目提供这些服务。远程服务地址和模型由用户自行确认。

配置文件会以明文保存用户填写的 API Key，仅供本机使用。不要把它提交到 Git、复制到 Issue、日志或截图中。已经暴露过的 Key 必须在服务商处撤销，删除文件不能清除既有 Git 历史。

## 日志、统计和调参

运行时数据写入 `logs/`，默认不提交到 Git：

- `episodes.jsonl`：脱敏的死亡轨迹。
- `decision_traces.jsonl`：候选、过滤、延迟和结果摘要。
- `experiment_runs.jsonl`：实验事件和增量统计。
- `policy_profile.json`：本地策略调参结果。

查看回放统计：

```powershell
.venv\Scripts\python.exe -m isaac_jev.replay --path logs/decision_traces.jsonl
```

根据已有死亡事件生成建议 profile：

```powershell
.venv\Scripts\python.exe -m isaac_jev.tuning --log-dir logs
.venv\Scripts\python.exe -m isaac_jev.tuning --log-dir logs --write
```

日志只应包含脱敏观测摘要，不应包含 API Key、完整远程请求或完整响应。提交问题前请自行检查日志内容。

## 测试

测试不连接 Steam 游戏或远程 Provider：

```powershell
.venv\Scripts\python.exe -m compileall -q src
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

CI 只执行离线检查，不会启动游戏。实机验证需要安装游戏、启用 Mod、启动 `--luadebug`，并按上面的安装顺序操作。

## 常见问题

### 网页显示无法连接控制器

确认 Python 服务端正在运行，且端口 `9528` 没有被旧实例占用。只保留一个控制器进程后重新打开 <http://127.0.0.1:9529/>。

### 游戏没有收到状态

确认游戏启动参数包含 `--luadebug`，Mod 路径下存在 `main.lua`，并且在 Mods 菜单启用了 **Isaac Jev**。更新 Mod 后必须重启游戏。

### 游戏能连接但没有自动动作

确认服务端命令包含 `--autopilot`，并且游戏内没有按 F8 切换到人工模式。先使用 Local Provider 排除远程服务问题。

### 远程 Provider 报缺少密钥

确认本机 `config/decision_provider.json` 中对应 Provider 的 `auth_required` 和 `api_key` 已正确填写。不要把密钥写入示例文件或提交到仓库。

### 角色卡在门口或持续重定位

这是实验性策略的已知边界。保存脱敏日志和游戏帧信息后提交 Issue，说明 Mod 版本、控制器版本、Provider、固定种子和房间情况；不要上传存档或密钥。

## 目录结构

```text
config/
  decision_provider.example.json   # 可公开的配置模板
mods/IsaacJev/                 # 复制到游戏 mods 目录
src/isaac_jev/                # Python 服务端
tests/                             # 离线测试
ISAAC_RULES.md                     # 决策与安全规则
PROJECT_MEMORY.md                  # 项目维护上下文
start_isaac_jev.cmd                # Windows 启动脚本
```

## 安全与限制

- 仅用于本地单人实验，不用于联机、竞速、排行榜或他人存档。
- 不要向公网暴露 TCP 桥或网页仪表盘。
- 不要提交 API Key、日志、存档、截图中的个人路径或远程服务响应。
- 远程模型只是在安全候选集合中选择动作；本地碰撞、危险格、资源和过期动作检查仍拥有最终执行权。
- 本项目不保证完成整局游戏，也不保证对所有房间布局、角色和道具组合都有效。

## 许可证

项目代码使用 [MIT License](LICENSE)。游戏本体、游戏资源、名称和商标仍属于其各自权利人；本项目不重新分发游戏本体或官方资源。

欢迎通过 [CONTRIBUTING.md](CONTRIBUTING.md) 提交改进。安全问题请阅读 [SECURITY.md](SECURITY.md)。
