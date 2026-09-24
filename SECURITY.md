# Security Policy

## Supported versions

仅维护当前 `main` 分支。历史演示版本不单独维护安全补丁。

## Reporting a vulnerability

请通过 GitHub 仓库的 **Security > Report a vulnerability** 私下报告安全问题；不要先在公开 Issue 中披露密钥或可利用细节。

如果意外提交了密钥，请立即在相应服务商处撤销并重建。删除文件或修改 `.gitignore` 无法从既有 Git 历史中移除密钥。

## Local deployment

控制器 TCP 桥和网页仪表盘默认监听 `127.0.0.1`。不要通过端口转发或公开代理将它们暴露到互联网。`config/decision_provider.json` 会明文保存用户自行配置的凭据，并已被 Git 忽略；请只在可信本机使用。
