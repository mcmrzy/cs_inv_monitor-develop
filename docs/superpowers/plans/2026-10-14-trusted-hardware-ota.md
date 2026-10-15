# 可信模块硬件 OTA 实施计划

> 执行方法：writing-plans、subagent-driven-development；独立文件边界采用并行任务，集成和评审顺序执行。用户已授权实施，无需再次询问。

目标：落实已确认完整设计，优先交付阶段 A 的可操作端到端系统；实现后续保护契约及客户端安全门槛，真实设备能力不足时拒绝开放离线安装。

架构：可信 SN/模块档案与原始观测分离；后端所有 OTA 入口按统一可信身份与目标板卡矩阵判定；管理端完成台账核实、固件范围配置和冲突处理。协议与设备工程独立交付，不以服务端字段宣称实机能力。

技术栈：Go/Gin/pgx/PostgreSQL，React/TypeScript/Ant Design，Flutter/Dart。

用户新增硬约束：不修改 ARM、DSP、BMS 应用或 Bootloader。将此限制纳入交付范围，不用外部工程副本替代。服务端与 App 可落实可信台账和守门；通信管理器未经过真实身份/写前验证时，离线授权保持关闭。

工作区：保留当前未提交内容；已保存相关文件和全量旧 diff 到 `.tmp/trusted-hardware-ota/before` 与 `pre-existing.patch`。新 worktree 不含当前已改权限/App 内容，本次在当前工作区限定编辑，测试使用独立输出目录。

## Chunk 1：可信档案与校验

- [ ] 新增迁移 131（实施前复核编号）与 schema 基线：板卡目录、SN 核实档案、模块配置、历史、观测、固件板卡矩阵、任务快照。不上报自动核实，不改既有迁移 129/130。
- [ ] 新增 `internal/model/hardware_registry.go`、`repository/hardware_registry.go`、`service/hardware_registry.go`、`handler/hardware_registry.go` 与测试：校验、乐观锁、审计、核实、纠正、冻结、换板；台账 staging 预览/选择提交，不改变 devices 归属。
- [ ] 内部 INFO 写独立观测，保留原始意义；可信型号/硬件不被上报覆盖；修复普通 Create/Update 的 hardwareVersion→firmwareEsp 错位。
- [ ] 修改 OTARepository 查询/创建/回退/结果同步与实际下发：按可信型号、目标板卡、模块状态及发行策略检查；快照修订变化拒绝；历史不反写。
- [ ] 对未具备设备保护的目标，只通过系统管理员明确 SN/目标/固件摘要/期限的兼容窗口执行云端迁移，普通 force 不能放行；本地离线不放行。

## Chunk 2：可操作界面与 App

- [ ] 管理端新增独立 hardwareApi/types、档案 Drawer/导入核实界面、固件板卡范围配置组件，接入现有设备与 OTA 页面；使用权限守卫、错误说明与中英语言。
- [ ] App 解析新的 identity_state、protection_level、模块身份，阻断未经授权的本地升级；升级成功要求实际读回，fallbackVersion 只展示目标版本。
- [ ] 规范 V2 对象与授权契约、长度上限、签名用途、单次序号/取消/恢复规则。未有真实设备身份挑战及 V2 更新器时不启用离线授权，不生成伪授权或假安装成功。

## Chunk 3：验证、评审和交付

- [ ] 核实/冲突/并发导入/固件唯一性/任务修订集成测试使用独立本地 PostgreSQL；优先已有本机工具，Docker 未启动时如可用则启动本地测试环境。
- [ ] 四个 Go 模块 build/test/vet；管理端类型检查、构建和相关组件测试；Flutter analyze 与 OTA/缓存/控制器回归。
- [ ] 独立评审：规格符合性，再代码正确性/安全性；修复所有真实阻断项，保留验证日志。
- [ ] 记录实际完成范围、未完成设备端源代码/板卡/密钥/分区条件和实施入口；绝不宣称部署、生产迁移、刷写或实机验收已经发生。

真实固件阶段 B 在实施前需要确认每目标实际源码、受保护 UID、恢复和分区布局。现有读取权限允许研究 D:/CS_INV_WIFI 工程，但本次授权工作区没有该目录写权限；可准备协议/固件适配改动并在必要时申请具体路径权限，不以外部副本冒充在用工程。

验证命令：各 Go 模块目录 `go build ./...`、`go test ./... -count=1`、`go vet ./...`；Web 目录 `npm run build:check`、`npm run test:run -- <相关测试>`；App 目录 `flutter analyze --no-pub`、`flutter test <相关测试>`。每个行为先增加失败用例，再实现并确认通过。
