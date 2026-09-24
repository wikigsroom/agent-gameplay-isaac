# 开源发布检查清单

这个目录已经是可公开发布的源码快照。推送 GitHub 前仍需完成以下本地操作。

## 凭据和历史

- [ ] 撤销原项目及其历史中曾出现过的 API Key。
- [ ] 确认新目录没有 `config/decision_provider.json`、日志、存档或远程响应。
- [ ] 使用 Gitleaks 或 GitHub Secret Scanning 检查当前文件和提交历史。
- [ ] 如果从旧仓库复制 Git 历史，先清理历史；本目录默认没有旧 `.git` 历史。
- [ ] 生成新的 API Key 后只填写本机被忽略的配置文件。

## 功能和文档

- [ ] 按 README 完成一次 Python 安装、Mod 安装和 Local Provider 启动。
- [ ] 在没有远程 Provider 和 API Key 时确认 Local Provider 可以运行。
- [ ] 在固定种子、空房间和单房间战斗中验证 F8 人工接管。
- [ ] 更新 README 中的版本、已知限制和实际可用的远程 Provider。
- [ ] 不要在截图、日志或 Issue 中暴露 API Key、存档路径和个人目录。

## GitHub 仓库

- [ ] 创建新的私有 GitHub 仓库或确认目标仓库为空。
- [ ] 将本目录初始化为 Git 仓库并推送到目标远程。
- [ ] 设置仓库描述、Topics、默认分支和分支保护。
- [ ] 打开 Issues、Pull Requests、Dependabot 和 Secret Scanning。
- [ ] 首次发布使用版本标签，例如 `v0.1.0`。
- [ ] 在仓库页面检查 Code、Actions、Releases 和历史提交后再改为 Public。

示例命令（请替换成自己的 GitHub 地址）：

```powershell
git init -b main
git add .
git status
git commit -m "chore: prepare public release"
git remote add origin https://github.com/<owner>/<repository>.git
git push -u origin main
```

如果仓库从旧项目迁移，不要把旧仓库的 `.git` 目录复制进来。旧历史中已经出现过的密钥必须先撤销，即使新仓库不再包含旧配置文件。
