import { Divider, Grid, H1, H2, Stack, Stat, Table, Text } from 'qoder/canvas';

export default function AppFiveTasksCompletionReport() {
  return (
    <Stack gap={20}>
      <H1>App 五项功能修复重构 — 完成报告</H1>
      <Text tone="secondary">
        Spec：App_五项功能修复重构_task-6d2.md · inv_app（Flutter）+ business-api（Go）
      </Text>

      <Grid columns={4} gap={16}>
        <Stat value="5 / 5" label="任务完成" tone="success" />
        <Stat value="382 / 382" label="Flutter 测试通过" tone="success" />
        <Stat value="0 / 0" label="analyze error / warning" tone="success" />
        <Stat value="12+" label="新增测试用例" />
      </Grid>

      <Divider />

      <H2>成果总结</H2>
      <Table
        headers={['任务', '成果']}
        rows={[
          ['1. 工单页排查修复', '抽取为独立模块（support 特性），提交表单补齐模板/优先级/关联设备，分页 + Tab 统计，删除文案修正，小屏溢出修复，从零补 10 个测试'],
          ['2. 闪光灯改补光灯', '状态源改为 torchState 真实状态流，相机就绪后按“自动打开”点亮，按钮高亮反映真实开关，不支持设备自动隐藏'],
          ['3. 离网直连设置重构', '更名“离网直连设置”；新增自动连接开关（ble_auto_connect）与发现设备列表（扫描缓存流 + 重新扫描 + PIN 绑定 + 已连接标记）；移除自定义服务器 / OTA / 本地离网模式入口'],
          ['4. 首启引导', '登录后无电站弹出三步向导（创建电站→添加设备→配网，实时打勾、可跳过）；品牌引导尾屏“快速开始”三入口；首页空态快捷按钮'],
          ['5. OTA 升级中心重构', '功能优先四入口：检查更新（全设备并发检查，上限 5）/ 本地升级（设备选择层）/ 固件库（按型号浏览 + 预下载 + 已下载标记）/ 升级历史（设备选择层）'],
        ]}
      />

      <H2>关键步骤</H2>
      <Table
        headers={['阶段', '内容']}
        rows={[
          ['调研', '工单前后端契约比对、mobile_scanner torch API 考证、BLE 直连链路 / OTA 链路并行子代理调研，产出实施计划并经用户确认'],
          ['修复与实现', '补光灯状态机 → 离网直连设置（含 BleDirectService 扩展）→ 首启引导三处落地 → 工单模块抽取重构 → OTA 中心四入口 + 后端接口扩展'],
          ['后端配套', 'GET /ota/app/packages 的 items 补齐 firmware_id / download_url / file_sha256 等下载元数据（仍仅已发布包），序列化抽为纯函数并补单测'],
          ['测试与验证', '新增工单测试 10 个、BLE 服务测试 2 个、后端单测 2 个；全量 analyze + test + go build/vet 逐项通过'],
        ]}
      />

      <H2>变更文件（要点）</H2>
      <Table
        headers={['文件', '变更']}
        rows={[
          ['inv_app/lib/features/support/presentation/pages/work_orders_page.dart', '新建：工单列表/提交/详情完整模块（含分页、统计、模板选择）'],
          ['inv_app/lib/features/profile/presentation/pages/help_center_page.dart', '1697 → 约 190 行，仅保留帮助中心与工单入口'],
          ['inv_app/lib/features/device/presentation/pages/add_device_page.dart', '补光灯状态机 + 自动补光 + 真实状态 UI'],
          ['inv_app/lib/features/profile/presentation/pages/offline_mode_settings_page.dart', '重构为离网直连设置（自动连接 + 发现设备列表）'],
          ['inv_app/lib/core/services/ble/ble_direct_service.dart', 'scanResults 缓存/流、rescan、setAutoConnect'],
          ['inv_app/lib/core/services/storage_service.dart', '新增 ble_auto_connect 键'],
          ['inv_app/lib/features/onboarding/**（setup_guide_page / setup_guide_storage / onboarding_page）', '首启向导 + 品牌引导尾屏快速开始'],
          ['inv_app/lib/features/station/presentation/pages/home_page.dart', '向导触发 + 空态快捷按钮'],
          ['inv_app/lib/features/ota/presentation/pages/**（ota_tab / ota_check_all / firmware_library / local_upgrade / upgrade_history）', '升级中心四入口、检查更新页、固件库页、设备选择层'],
          ['inv_app/lib/features/ota/presentation/widgets/device_picker_list.dart', '新建：共享设备选择列表组件'],
          ['inv_app/lib/core/router/app_router.dart', '注册 /setup-guide、/ota/check-all（先于 :sn）、/firmware-library'],
          ['business-api/internal/handler/ota_handler.go', 'AppListUpgradePackages 补下载元数据，抽出 buildAppUpgradePackagesPayload'],
          ['business-api/internal/handler/ota_app_packages_test.go', '新建：序列化契约单测'],
          ['inv_app/lib/l10n/app_zh.dart · app_en.dart', '新增约 40 个 key，更新工单/BLE/OTA 相关文案'],
        ]}
      />

      <H2>验证证据</H2>
      <Table
        headers={['项目', '结果']}
        rows={[
          ['flutter analyze', '0 error / 0 warning（289 条均为既有 info 基线）'],
          ['flutter test 全量', '382 通过 / 0 失败 / 4 跳过（含工单 10 个、BLE 新增 2 个、l10n key 校验）'],
          ['go build ./... + go vet ./...', '通过'],
          ['go test ./internal/handler/ ./internal/service/', '全部通过（含新增固件库序列化单测 2 个）'],
          ['l10n 契约', 'localization_key_usage_test 校验 zh/en 全量 str() key 存在'],
        ]}
        rowTone={['success', 'success', 'success', 'success', 'success']}
      />

      <H2>最终结果</H2>
      <Text>
        Spec 五项任务全部落地并通过逐项完成审计：工单页从“不可维护的 1500 行内嵌代码 + 零测试”变为独立可测模块；
        扫码补光灯与离网直连设置的交互缺陷修复；首启引导闭环（引导页→向导→空态）；OTA 升级中心改为功能优先四入口，
        固件库获得按型号浏览与预下载能力（后端接口扩展支撑）。目标已标记完成。
      </Text>
      <Text tone="secondary" size="small">
        遗留外部协作项：固件团队 BLE 会话鉴权协议（前次审查遗留）；OTA / 离网功能建议真机回归。
      </Text>
    </Stack>
  );
}
