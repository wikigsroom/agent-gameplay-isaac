# PROJECT_MEMORY.md

## 项目概述

Isaac Jev 是面向 The Binding of Isaac: Repentance 的本地单人自动游玩演示。Lua Mod 采集游戏状态并接收动作，Python 控制器生成候选动作并使用本地策略或可选的远程 Decision Provider 选择动作。

## 技术栈

- Python 3.11+，运行时仅使用标准库。
- Repentance Lua Mod API 和 `--luadebug` 提供的 LuaSocket。
- 本地 TCP 桥、HTTP 仪表盘与可选 MCP stdio 控制面。

## 启动方式

1. 在 Steam 游戏启动参数添加 `--luadebug`，将项目相对路径 `mods/IsaacJev` 复制到 Steam 游戏根目录下的相对路径 `mods/IsaacJev`。
2. 在项目根目录创建 Python 虚拟环境并执行 `python -m pip install -e .`。
3. 首次启动时程序会自动创建不受 Git 跟踪的 `config/decision_provider.json`，默认使用 Local Provider；也可以先复制 `config/decision_provider.example.json` 并配置远程服务。
4. 执行 `python -m isaac_jev.cli --autopilot --web-dashboard --no-dashboard`；游戏内按 F8 切换人工/自动控制。

## 目录结构

- `mods/IsaacJev/`：游戏 Mod。
- `src/isaac_jev/`：控制器、决策、Provider、统计与网页。
- `tests/`：离线单元测试。
- `config/`：可公开的示例配置；实际配置被 `.gitignore` 排除。
- `.github/workflows/`：持续集成。

## 核心模块

- `runtime.py` 管理 Lua TCP 桥、动作生命周期和异步决策。
- `models.py` 解析游戏状态；`decision.py` 和 `navigation.py` 构造候选并执行安全约束。
- `providers.py` 对接 Local、Jev、Bocha、Laya 和通用 System One 决策服务。
- `web_dashboard.py` 提供仅供本机访问的运行状态、Provider 配置与实验统计。
- `telemetry.py`、`experiment.py`、`replay.py` 和 `tuning.py` 管理本地日志及离线评估。

## 数据库说明

无数据库。运行数据写入本地 `logs/`，不纳入版本控制。

## 外部依赖

- Steam 版 The Binding of Isaac: Rebirth 和 Repentance DLC。
- 远程 Provider 可选；需要用户自行提供服务地址和凭据。

## 历史变更

- 2026-09-24：从内部项目创建独立公开发布目录，排除历史、密钥、日志和机器环境文件；公开版默认 Local Provider。
- 2026-09-24：根据 Windows Python Launcher 的实际可用版本，将公开文档和启动脚本的推荐虚拟环境版本统一为 Python 3.12；项目最低要求仍为 Python 3.11。
- 2026-09-24：修正 Mod 安装目录说明，公开版使用 Steam 游戏根目录下的相对路径 `mods/IsaacJev`，不再写死机器盘符或指向 Documents 路径。
- 2026-09-25：首次启动且缺少配置文件时自动创建 `config/decision_provider.json`，内容不含密钥并默认选择 Local Provider。

## 注意事项

- 项目仅面向 Repentance，不保证支持 Repentance+。
- 本项目适合本地单人实验；游戏 Mod 与 Python 控制器升级后均需重启对应进程。
- `config/decision_provider.json` 会以明文保存用户自行填写的密钥，必须始终保持在 Git 忽略列表中。
