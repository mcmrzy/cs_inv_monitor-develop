# CI 错误修复设计

## 目标

修复 `develop` 分支最新 GitHub Actions 中已确认的前端覆盖率与 API 文档失败，并将被放行的 OpenAPI 结构错误改为正式阻断，避免后续文档产物带病生成。

## 根因与设计

1. 前端工作流把 `json-summary` 作为 Vitest 测试 reporter 传入；它实际属于 coverage reporter。工作流应使用 `--coverage.reporter` 命名空间。
2. API 文档工作流安装了不存在的 `openapi-to-postman` 包。改用提供 `openapi2postmanv2` 命令的 `openapi-to-postmanv2@6.3.3`，并在生成前显式创建 `docs/postman/`。
3. `RemoveMemberResponse`、`ActivateResponse`、`DeactivateResponse` 的 `message` 被误缩进到 boolean `success` 内。修正为与 `success`、`data` 同级，并取消 Redocly lint 的 `continue-on-error`。
4. PowerShell 验证脚本与 API 文档说明同步使用相同的固定工具版本，防止本地与 CI 漂移。

## 验证

- 使用 Node 24 干净依赖运行前端 coverage 命令，要求全部测试通过并生成 `coverage-summary.json`。
- bundle 后运行 Redocly lint，要求无 error。
- 在临时目录运行 Postman 转换，要求命令退出 0、产物非空且可由 `jq` 读取。
- 仅检查本次五个目标文件的 diff，避开 WSL/Git LFS 图片噪声。
