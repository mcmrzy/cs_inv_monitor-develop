---
name: auto-git-commit
description: 每次代码修改完成后，自动执行 git add 和 git commit，提交信息用中文描述。当完成文件编辑、bug修复、功能开发等代码修改任务后，自动触发此技能。
---

# 自动 Git 提交

## 触发时机

在以下场景完成后**立即自动执行**：
- 完成一个功能开发或代码修改
- 修复一个 Bug
- 完成一轮重构
- 用户要求提交代码时

**不需要确认**，修改完成即自动提交。

## 执行步骤

### 1. 检查变更

```bash
git status --short
```

如果有未暂存或未提交的变更，继续执行。如果没有变更，跳过提交。

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
