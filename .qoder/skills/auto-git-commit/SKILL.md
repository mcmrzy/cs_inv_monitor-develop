---
name: auto-git-commit
description: 每次代码修改完成后，自动执行 git add、git commit、cherry-pick 合并到主项目 develop 分支，并重新编译部署 Docker 服务。当完成文件编辑、bug修复、功能开发等代码修改任务后，自动触发此技能。
---

# 自动 Git 提交 + 合并 + 部署

## 触发时机

在以下场景完成后**立即自动执行**：
- 完成一个功能开发或代码修改
- 修复一个 Bug
- 完成一轮重构
- 用户要求提交代码时

**不需要确认**，修改完成即自动执行全部流程。

## 执行步骤

### 1. 检查变更

```bash
git status --short
```

如果有未暂存或未提交的变更，继续执行。如果没有变更，跳过后续所有步骤。

### 2. 暂存所有变更

```bash
git add -A
```

### 3. 分析变更并生成中文提交信息

查看 diff 内容：

```bash
git diff --cached --stat
git diff --cached
```

根据变更内容，生成**中文**提交信息，格式如下：

```
<类型>: <简要描述>

<详细说明（可选，多行）>
```

**类型映射**：

| 类型 | 适用场景 |
|------|----------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `refactor` | 重构 |
| `style` | 样式/格式调整 |
| `docs` | 文档更新 |
| `chore` | 构建/配置变更 |
| `perf` | 性能优化 |

### 4. 提交

```bash
git commit -m "<提交信息>"
```

记录此 commit 的 hash 值（如 `e43a33a6`），后续合并步骤需要用到。

### 5. 合并到主项目 develop 分支

当前环境是 worktree（detached HEAD），需要将刚提交的变更 cherry-pick 到主项目的 develop 分支：

```bash
# 5.1 进入主项目目录
# 主项目路径: D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop

cd D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop

# 5.2 暂存主项目未提交的改动（避免冲突）
git stash push -m "temp: stash before cherry-pick"

# 5.3 Cherry-pick worktree 的提交到 develop
git cherry-pick <commit_hash>

# 5.4 恢复之前暂存的改动
git stash pop
```

如果 cherry-pick 出现冲突：
- 手动解决冲突后执行 `git cherry-pick --continue`
- 如果冲突无法解决，执行 `git cherry-pick --abort` 并通知用户

### 6. 重新编译部署 Docker 服务

合并完成后，在主项目目录下重新构建并启动 Docker 服务：

```bash
cd D:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop

# 使用 Makefile 一键编译部署
make docker-up
```

这等价于：
```bash
docker compose -f deploy/docker-compose.yml up -d --build
```

部署后验证服务健康状态：
```bash
docker compose -f deploy/docker-compose.yml ps
```

如果 `make docker-up` 失败：
- 检查具体错误日志：`docker compose -f deploy/docker-compose.yml logs`
- 通知用户具体的错误信息

## 提交信息规范

- **标题**：一行，不超过 72 个字符
- **语言**：中文
- **风格**：简洁准确，描述做了什么

### 示例

```
fix: 修复本地OTA升级页面UI闪烁问题

- 合并扫描和连接流程为单一方法，减少setState次数
- 移除build方法中的addPostFrameCallback，改为_goToStep中触发
- 删除废弃的_scanForDeviceHotspot和_connectToAp方法
```

```
feat: 本地OTA上传支持ARM芯片（multipart方式）

- uploadFirmware新增target参数，区分esp(octet-stream)和arm(multipart)
- LocalOTAPage增加targetChip参数
- 路由增加target_chip查询参数
- 轮询时根据芯片类型读取对应版本字段
```

```
fix: 修复预下载固件404问题

后端CheckUpdate接口download_url从相对路径改为完整URL
```

## 注意事项

- 如果变更涉及多个模块，在详细说明中分点列出
- 不要提交空变更（`git status` 无内容时跳过）
- 提交后输出提交 hash 和提交信息供用户确认
- 合并到主项目后输出主项目的新 commit hash
- Docker 部署完成后输出各服务的运行状态
- 如果当前不在 worktree 环境（直接在主项目目录工作），跳过步骤 5，直接在主项目提交即可
- Docker 部署仅在代码变更影响运行时（Go/Flutter/Frontend/配置）时执行；纯文档变更（README、docs/）可跳过部署步骤
