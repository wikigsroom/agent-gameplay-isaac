# Contributing

欢迎提交 Bug 报告和改进。请先确认问题发生在 Repentance（非 Repentance+），并搜索现有 Issue。

## 开发环境

在 Windows PowerShell 7 中：

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -e .
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

请勿提交 `config/decision_provider.json`、API Key、游戏存档、日志或完整远程请求/响应。报告问题时说明游戏版本、Python 版本、Mod 与控制器版本、复现步骤和脱敏后的相关错误。

修改 Lua Mod 时请同时检查 Python 状态模型和相关离线测试。提交 PR 前运行测试，并在说明中写清已验证和未验证的实机行为。项目代码使用 MIT 许可证；贡献即表示同意将贡献按该许可证发布。
