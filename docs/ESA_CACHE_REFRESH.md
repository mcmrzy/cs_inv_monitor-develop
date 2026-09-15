# ESA 缓存自动规则 + 发布后刷新

## 背景

下载页 `download.jiuxiaoyw.online` 读取公开接口拿最新 APK 元数据：

- `/app-release-info`（同源别名，前端容灾回退）
- `/api/v1/ota/app/latest`（权威路径）
- 或跨域 `https://api.jiuxiaoyw.online/api/v1/ota/app/latest`

阿里云 ESA 在未遵循源站 `no-store` 时会对上述路径缓存旧对象（实测最长 30 天），
导致 App 已发 1.0.4、页面仍显示 1.0.1。

后端做两层自动化（均需配齐 AK/SiteId）：

1. **启动时 `EnsureCacheRules`**：向 ESA 写入缓存规则  
   - `/api/*`、`/app-release-info` → `EdgeCacheMode=off`（禁止边缘缓存）  
   - `/`、`/download` → `follow_origin`  
   同名规则存在则更新，不存在则创建。
2. **发布/回滚/恢复/删除 App 版本后** 异步 `RefreshESAObjectCaches` 兜底。

## 配置

写到服务器 `deploy/.env.prod`（**不要提交仓库**）：

```bash
ESA_CACHE_REFRESH_ENABLED=true
ALIYUN_ACCESS_KEY_ID=你的AccessKeyId
ALIYUN_ACCESS_KEY_SECRET=你的AccessKeySecret
ESA_SITE_ID=你的ESA站点ID
# 可选，默认 download.jiuxiaoyw.online
# ESA_REFRESH_HOST=download.jiuxiaoyw.online
```

任一关键项为空时自动跳过（Noop），发布流程不受影响，只打一条 info 日志。

## 如何获取三项配置

### 1. AccessKey ID / Secret

1. 登录 [RAM 控制台](https://ram.console.aliyun.com/users)
2. 建议**新建 RAM 子账号**（不要用主账号 AK）
   - 访问方式：编程访问
   - 记下 AccessKey ID / Secret（Secret 只显示一次）
3. 给子账号授权（最小权限）：
   - 自定义策略或系统策略，至少允许：
     - `esa:RefreshObjectCaches`（刷新缓存）
     - `esa:ListSites`（查站点 ID，可选）
   - 示例自定义策略：

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["esa:RefreshObjectCaches", "esa:DescribeSites", "esa:ListSites"],
      "Resource": "*"
    }
  ]
}
```

> 若策略 Action 名称在控制台提示无效，可在 RAM「系统策略」里搜 `ESA`，
> 给只读站点 + 刷新缓存相关权限，或临时用 `AliyunESAFullAccess` 验证后再收紧。

### 2. ESA Site ID

任选一种：

**控制台**：[ESA 站点管理](https://esa.console.aliyun.com/) → 选中 `download.jiuxiaoyw.online`（或主站）→ 站点信息里有 **Site ID**。

**命令行**（配好 AK 后）：

```bash
# 在 business-api 目录
go run ./cmd/esa-purge -list-sites
```

或用阿里云 CLI：

```bash
aliyun esa ListSitesESA --PageSize 50
```

Site ID 通常是数字串（例如 `1234567890123456789`）。

### 3. 刷新目标主机

默认刷新 `https://download.jiuxiaoyw.online` 下的：

- `/app-release-info`
- `/api/v1/ota/app/latest`

若你的下载域不同，设置 `ESA_REFRESH_HOST`。

## 手动刷新一次

### 推荐：Python 脚本（服务器无 Go 也能用）

```bash
export ALIYUN_ACCESS_KEY_ID='LTAI...'
export ALIYUN_ACCESS_KEY_SECRET='真实Secret'   # 不要写 <占位符>
export ESA_SITE_ID='172343211966680'
python3 deploy/scripts/esa-refresh.py

# 只列站点
ESA_LIST_SITES=1 python3 deploy/scripts/esa-refresh.py
```

### 或：Go CLI（本机/有 Go 的环境）

```bash
cd business-api
ALIYUN_ACCESS_KEY_ID=... ALIYUN_ACCESS_KEY_SECRET=... go run ./cmd/esa-purge -list-sites
ALIYUN_ACCESS_KEY_ID=... ALIYUN_ACCESS_KEY_SECRET=... \
  go run ./cmd/esa-purge -site-id 172343211966680
```

### 生产 SiteId（download.jiuxiaoyw.online）

`ESA_SITE_ID=172343211966680` —— 写入服务器 `deploy/.env.prod`，**不要提交仓库**。

## 验证

发布新 APK 后：

```bash
curl -s "https://api.jiuxiaoyw.online/api/v1/ota/app/latest?platform=android"
# 应返回最新 version_name

curl -sI "https://download.jiuxiaoyw.online/app-release-info"
# 不应再长期出现 Age 很大的 HIT 旧 1.0.x 对象
```

## 相关文件

- `deploy/scripts/esa-refresh.py` — 无 Go 环境下的手动刷新脚本
- `business-api/internal/service/esa_cache.go` — 发布后自动刷新
- `business-api/internal/handler/ota_handler.go` — 发布后挂钩
- `business-api/cmd/esa-purge` — 手动刷新 / 列站点 CLI
- `deploy/.env.prod.example` — 环境变量模板
