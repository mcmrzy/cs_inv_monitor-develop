# 硬件版本兼容 OTA

用户已确认 2026-10-12 的设计并授权实施。第一阶段在当前仓库实现云端、管理后台和 App 的兼容检查，保留现有 V1 固件签名；设备写入前校验需要另行升级真实固件，不能把第一阶段当作设备端保护已经完成。

## 数据和接口

- `device_hardware_versions` 按 `model + version` 管理标准硬件版本，`version` 只 trim + uppercase，不剥离 HW/V 前缀、不猜测别名。`description` 可选。迁移从设备已上报的非空值建立目录，不推断缺失值。
- 固件 JSON 新增 `hardware_versions: string[]`。上传 multipart 使用同名字段的 JSON 数组；JSON 创建也使用数组。至少选一个目录中存在的版本。无范围的旧固件不允许设备安装。
- `firmware_hardware_versions` 关联每份固件与明确硬件版本。数据库保证同型号、模块、软件版本、硬件版本只关联一份固件；不同硬件可有相同软件版本和不同文件。保留文件 SHA256 和固件 ID。
- `GET /ota/hardware-versions?model=...` 返回标准目录数组 `{model, version, description}`。
- `POST /ota/hardware-versions` 创建 `{model, version, description}`，限系统管理员，记录审计。
- `PUT /ota/firmware/:id/hardware-versions` 补录 `{hardware_versions:[...]}`，限系统管理员；允许草稿调整和没有范围的历史固件一次补录。发布过且已有范围的固件不可改兼容范围。
- 固件列表、上传、详情、发布确认显示硬件范围，目录支持在上传表单添加版本。管理端硬件筛选不改变设备身份。
- 设备固件概览新增 `hardware_version`（原始上报值）和 `hardware_state` (`known`/`unknown`)；模块增加 `compatibility_reason` (`hardware_version_unknown`/`no_compatible_firmware` 或空)。升级历史新增 `hardware_version` 快照。

## 判断和执行

- 云端只展示型号、模块和已发布硬件范围兼容的固件，再应用现有范围/灰度。空设备硬件、未登记版本、空固件范围均拒绝。
- 创建任务、重试、手动安装、回退、下发前均读取最新设备信息并校验；强制原因不能绕过硬件不兼容。历史回退 ID 查找也按当前硬件筛选。
- 同设备多模块任务创建为一个事务，任一不兼容则不创建部分任务。排队到执行期间兼容失效则记失败原因并推进队列。
- App 下载元数据持久化 `hardware_versions`。本地 BLE/WiFi OTA 从实际连接设备 INFO 读取硬件，上传前严格匹配；旧缓存缺范围不可安装但可删除/重新下载。不增加覆盖设备硬件的用户选项。
- 签名 V1 不变化，以免破坏在用设备。第二阶段协议文档说明 V2 必须签入型号、完整有序硬件范围；旧设备无法宣称已有设备端兼容保护。

## 验收

同型号 HW-1/HW-2 各自获得自己的固件；通用文件可兼容两者；未知硬件与空范围拒绝；发布、回退、重试和下发无绕过；同硬件同版本冲突由数据库拒绝；本地缓存重启后保留范围并在上传前检查。执行 Go 构建/测试/vet、Web 类型检查/构建/OTA 测试、Flutter analyze/OTA 测试；数据库集成验证独立测试库，不连接生产。
