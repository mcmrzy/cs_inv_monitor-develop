# 缓存策略（源站 + 阿里云 ESA）

本文件是 `deploy/nginx-proxy.conf` 里 Cache-Control 的配套说明：**源站负责声明每类资源的缓存语义，ESA 只负责执行**。
按下面的配置，ESA 站点缓存模式设为「**优先遵循源站缓存策略（如果存在），否则不缓存**」即可，无需再为每个路径单独建缓存规则。

## 1. 资源分类与源站响应头

| 路径 | 资源 | 源站 Cache-Control | 依据 |
|---|---|---|---|
| `/`（含所有 SPA 路由） | 前端入口 `index.html` | `no-cache` | 每次回源校验，发版后用户立刻拿到新入口 |
| `/assets/` | Vite 构建产物（文件名带内容 hash） | `public, max-age=31536000, immutable, s-maxage=31536000` | 内容与文件名绑定，可永久缓存 |
| `*.png/jpg/jpeg/gif/svg/ico/woff/woff2/ttf/webp/mp4` | 固定名静态资源 | `public, max-age=86400, must-revalidate, s-maxage=86400` | 可能原 URL 覆盖更新，1 天后强制校验 |
| `/uploads/` | 用户上传（头像/电站图/工单附件） | `public, max-age=31536000, immutable, s-maxage=31536000` | 后端生成唯一文件名（`prefix_userid_rand_time.ext`），内容不可变 |
| `/firmware/` | 设备固件 + App 安装包 | `public, max-age=31536000, immutable, s-maxage=31536000` | 文件名带时间戳，内容不可变；**App 更新包走这里** |
| `/api/` | 动态接口、SSE | `no-store` | 绝不能缓存（历史上出现过 CDN 吐旧数据） |
| `/ws/` | WebSocket 升级 | `no-store` | 升级请求不得缓存 |

补充说明：

- `s-maxage` 与 `max-age` 取值相同，显式声明 CDN 侧 TTL——ESA 在两者同时存在时**以 s-maxage 为准**。
- 响应体压缩由 nginx `gzip_vary on` 保证 `Vary: Accept-Encoding`，ESA 与浏览器按编码分桶缓存。
- `emqx.jiuxiaoyw.online`、`sim.jiuxiaoyw.online` **不在 ESA 后面**（直连 nginx），不受本策略影响。
- 根域 `jiuxiaoyw.online` 只提供 `/firmware/`（设备下载），其余路径 404。

## 2. ESA 控制台设置

| 项 | 取值 | 原因 |
|---|---|---|
| 边缘缓存过期时间（站点级/默认规则） | **优先遵循源站缓存策略（如果存在），否则不缓存** | 源站已为每类资源声明语义；没有声明的路径（如 `/livez`、`/ws/`）一律不缓存，避免误缓存 |
| 查询字符串（Cachekey） | 保留全部参数 | 避免不同查询参数共用缓存对象 |
| 自定义缓存规则 | 不需要（按需临时加） | 站点级模式已足够；如需给某个路径单独设 TTL，用「优先遵循源站，否则自定义 TTL」 |
| 刷新/预热 | 发版后对 `/` 与 `*.apk` 各预热一次 | 首次请求必然回源（MISS），预热可让首个用户也走边缘 |

> 切换前 ESA 的行为是「忽略源站、统一 max-age=30」，这也是之前固件/安装包下载慢的原因：每次都回源到源站。

## 3. 验证方法

```bash
# 源站实际响应头（在服务器上执行，绕过 ESA）
bash deploy/scripts/verify-cache-headers.sh origin

# 公网响应头（经 ESA，切换模式后应与源站一致）
bash deploy/scripts/verify-cache-headers.sh public
```

关注两点：

1. `Cache-Control` 与上表一致；
2. 第二次请求同一资源时，响应头出现 `X-Site-Cache-Status: HIT`（或 `Age` 增大）说明边缘已命中。

```bash
# 单条快速确认边缘是否命中
curl -s -D - -o /dev/null -r 0-0 https://www.jiuxiaoyw.online/firmware/<apk> | grep -i x-site-cache-status
```

## 4. 改动记录

- 2026-09-09：`/uploads/` 由 `no-cache` 改为 immutable（上传文件名唯一）；`/ws/` 补 `no-store`；所有长缓存路径补 `s-maxage`；`/firmware/`、`/assets/`、`/api/`、`/` 原有语义保持不变。
