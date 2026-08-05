import {
  Callout,
  H1,
  MetricsGrid,
  ReferencePanel,
  ReportSection,
  ReportShell,
  RiskCallout,
  Stack,
  Table,
  Tag,
  Text,
  Timeline,
} from "qoder/canvas";
import type {
  MetricItem,
  ReferenceItem,
  TableColumn,
  TagTone,
  TimelineEvent,
} from "qoder/canvas";

const headlineMetrics: MetricItem[] = [
  {
    label: "flutter analyze",
    value: "0 error",
    description: "88 info 为历史基线，全部改动零新增 lint",
    tone: "success",
  },
  {
    label: "release APK",
    value: "90.4MB",
    description: "R8 BouncyCastle 缺类经 proguard 规则修复，构建通过",
    tone: "success",
  },
  {
    label: "依赖升级",
    value: "20+ 包",
    description: "fl_chart 1.2 / flutter_map 8.3 / go_router 17 / fln 22 等",
    tone: "success",
  },
  {
    label: "合规修复",
    value: "BSD 3-Clause",
    description: "flutter_blue_plus（商用付费）→ flutter_blue_ultra 2.2.0",
    tone: "success",
  },
  {
    label: "僵尸清理",
    value: "-9 包",
    description: "代码生成链 7 包 + pull_to_refresh + google_fonts 全移除",
    tone: "success",
  },
];

const timelineEvents: TimelineEvent[] = [
  {
    id: "st01",
    timestamp: "0d45dc2c2",
    title: "阶段 0+1 · 构建链 + 低风险升级 + 僵尸清理 + dartz→fpdart",
    description:
      "AGP 8.11.1→8.12.1、compileSdk 36→37；flutter_bloc/dio/connectivity_plus 7/secure_storage 10 等 8 包升级；删除 9 个零使用包；dartz→fpdart 18 文件 25 处；connectivity 7 List API 适配",
    state: "completed",
    tone: "success",
  },
  {
    id: "st02",
    timestamp: "fb2183e8f",
    title: "阶段 2 · flutter_map 8.3.1 + fl_chart 1.2.0",
    description:
      "flutter_map 标准 API 用法零改动（内置瓦片缓存自动生效）；fl_chart tooltipBgColor→getTooltipColor、tooltipRoundedRadius→tooltipBorderRadius、SideTitleWidget axisSide→meta 共 3 处 breaking 修复",
    state: "completed",
    tone: "success",
  },
  {
    id: "st03",
    timestamp: "47eec0e9f",
    title: "阶段 3 · flutter_blue_plus → flutter_blue_ultra 2.2.0（合规）",
    description:
      "FBP 1.36+ 已是商用付费许可；flutter_blue_ultra 为 1.x 社区延续版（BSD），drop-in 替换仅改 ble_provisioning_service.dart 的 import 与类名（5 处）",
    state: "completed",
    tone: "success",
  },
  {
    id: "st04",
    timestamp: "c2c82573e",
    title: "阶段 4 · go_router 17.3.0 + flutter_local_notifications 22.2.0",
    description:
      "go_router 零代码改动（路由全小写已验证）；通知插件 initialize/show 改命名参数；timezone 0.9.4→0.11.1 随通知包解锁；desugar_jdk_libs 2.0.4→2.1.4（插件 AAR 强制）",
    state: "completed",
    tone: "success",
  },
  {
    id: "st05",
    timestamp: "741bbdb30",
    title: "阶段 5 · BLE 本地通信协议文档 + App 端架构",
    description:
      "新增《BLE_Local_Communication_Protocol.md》（CSIV-CT 服务：AUTH 鉴权/TELEMETRY 遥测/COMMAND 控制，供固件评审）；ble_adapter.dart 抽象层 + ble_device_manager.dart 多设备管理（状态机/命令队列/退避重连/自动连接）+ 分帧重组 7 单测",
    state: "completed",
    tone: "success",
  },
  {
    id: "st06",
    timestamp: "f7021f8d3",
    title: "合并 develop + release 构建修复",
    description:
      "5 阶段 commit fast-forward 合并（775aaed68→741bbdb30）；release 构建暴露 AGP 8.12 R8 将 missing class 升级为错误（联通 SDK 可选引用 BouncyCastle），补 proguard-rules.pro 后构建通过",
    state: "completed",
    tone: "success",
  },
];

const changeRows: { area: string; change: string; benefit: string; tone: TagTone }[] = [
  {
    area: "Android 构建链",
    change: "AGP 8.12.1 / compileSdk 37 / desugar_jdk_libs 2.1.4",
    benefit: "满足 connectivity_plus 7 与 permission_handler 13 前置要求",
    tone: "success",
  },
  {
    area: "核心依赖",
    change: "flutter_bloc 9.1.1 / dio 5.11 / get_it 9.2.1 / permission_handler 13 / flutter_lints 6",
    benefit: "修复过期依赖，对齐最新稳定版",
    tone: "success",
  },
  {
    area: "网络与存储",
    change: "connectivity_plus 7.3.1（List API）/ flutter_secure_storage 10.3.1（实现重写）",
    benefit: "离线检测适配新 API；token 存储需真机验证迁移",
    tone: "warning",
  },
  {
    area: "函数式封装",
    change: "dartz → fpdart 1.2.0（18 文件 25 处，Either/fold API 同名）",
    benefit: "切换到活跃维护包，repository 层封装不变",
    tone: "success",
  },
  {
    area: "图表 fl_chart 1.2.0",
    change: "3 处 breaking 适配（tooltip 回调/BorderRadius/meta）",
    benefit: "解锁堆叠标签/渐变/柱顶 label/饼图圆角等新特性",
    tone: "success",
  },
  {
    area: "地图 flutter_map 8.3.1",
    change: "零代码改动（标准 TileLayer API 兼容）",
    benefit: "内置瓦片缓存+请求取消，包体积 3MB→900KB，支持跨反经线",
    tone: "success",
  },
  {
    area: "BLE 合规",
    change: "flutter_blue_plus 1.36.8 → flutter_blue_ultra 2.2.0（5 处改名）",
    benefit: "消除商用付费许可风险，API 完全兼容",
    tone: "success",
  },
  {
    area: "路由与通知",
    change: "go_router 17.3.0 / flutter_local_notifications 22.2.0（命名参数适配）",
    benefit: "解锁新版本特性，路由零影响",
    tone: "success",
  },
  {
    area: "BLE 架构（新）",
    change: "ble_adapter 抽象层 + ble_device_manager 多设备管理（893 行）",
    benefit: "绑定/鉴权/自动连接/本地遥测/下发控制五大能力 App 端就绪，可单测",
    tone: "success",
  },
];

const changeColumns: TableColumn<(typeof changeRows)[number]>[] = [
  { key: "area", title: "领域", width: "150px" },
  { key: "change", title: "改动", role: "description" },
  {
    key: "benefit",
    title: "收益/状态",
    role: "label",
    render: (row: (typeof changeRows)[number]) => <Tag tone={row.tone}>{row.benefit}</Tag>,
  },
];

const verifyRows = [
  { item: "flutter pub get", expect: "各阶段依赖解析成功", result: "通过（6 阶段共 4 次解析，无冲突）" },
  { item: "flutter analyze", expect: "error = 0", result: "通过（88 info 为历史基线，新增代码零 lint）" },
  { item: "flutter build apk --debug", expect: "每阶段构建成功", result: "通过（6 次构建全部成功）" },
  { item: "flutter build apk --release", expect: "构建成功", result: "通过，app-release.apk 90.4MB（proguard 修复后）" },
  { item: "pre-commit hooks", expect: "全部提交通过钩子", result: "通过（6 个 commit 均过 512KB/格式检查）" },
  { item: "flutter test", expect: "单元测试通过", result: "本机 flutter_tester WebSocket 无法启动（主项目基线同样失败，非代码问题），待 CI 验证" },
];

const verifyColumns: TableColumn<(typeof verifyRows)[number]>[] = [
  { key: "item", title: "验证项", width: "220px" },
  { key: "expect", title: "预期", role: "description" },
  { key: "result", title: "实测结果", role: "label" },
];

const evidenceItems: ReferenceItem[] = [
  {
    id: "protocol",
    label: "BLE 本地通信协议（固件评审）",
    description: "docs/BLE_Local_Communication_Protocol.md（362 行）",
    kind: "file",
  },
  {
    id: "adapter",
    label: "BLE 栈抽象层",
    description: "inv_app/lib/core/services/ble/ble_adapter.dart",
    kind: "file",
  },
  {
    id: "manager",
    label: "多设备管理器",
    description: "inv_app/lib/core/services/ble/ble_device_manager.dart",
    kind: "file",
  },
  {
    id: "provisioning",
    label: "配网服务（合规替换）",
    description: "inv_app/lib/core/services/ble_provisioning_service.dart",
    kind: "file",
  },
  {
    id: "proguard",
    label: "R8 修复",
    description: "inv_app/android/app/proguard-rules.pro（新建）",
    kind: "file",
  },
  {
    id: "apk",
    label: "构建产物",
    description: "inv_app/build/app/outputs/flutter-apk/app-release.apk（90.4MB）",
    kind: "file",
  },
];

export default function DepUpgradeBleLocalCommReport() {
  return (
    <ReportShell width="wide" ariaLabel="App 依赖升级与 BLE 本地通信完成报告">
      <Stack gap="section">
        <header>
          <Stack gap="component">
            <H1>App 依赖升级与 BLE 本地通信完成报告</H1>
            <Text tone="secondary">
              执行日期 2026-08-06 · 分支 feature/dep-upgrade-ble 已 fast-forward 合并 develop（775aaed68 → f7021f8d3）·
              计划：App依赖升级与BLE本地通信_task-dc7
            </Text>
            <MetricsGrid variant="header" columns={5} items={headlineMetrics} />
          </Stack>
        </header>

        <ReportSection title="执行摘要" divided>
          <Stack gap="container">
            <Text>
              按计划完成 6 个阶段、共 6 个 commit：Android 构建链升级（AGP 8.12.1 / compileSdk 37）→
              20+ 依赖升级与 9 个僵尸包清理、dartz→fpdart → flutter_map 8.3.1 与 fl_chart 1.2.0 适配 →
              flutter_blue_plus 合规替换为 flutter_blue_ultra（BSD）→ go_router 17 与 flutter_local_notifications 22 →
              BLE 本地通信五大能力（绑定/鉴权/自动连接/本地遥测/下发控制）的协议文档与 App 端可单测架构。
              全部阶段 flutter analyze error=0、debug APK 构建通过；合并后修复 AGP 8.12 R8 缺类问题，release APK 90.4MB 构建成功。
            </Text>
            <Timeline density="compact" events={timelineEvents} />
          </Stack>
        </ReportSection>

        <ReportSection title="关键改动清单" divided>
          <Table columns={changeColumns} rows={changeRows} rowKey="area" density="compact" />
        </ReportSection>

        <ReportSection title="验证证据" divided>
          <Stack gap="container">
            <Callout tone="success" title="静态检查与构建全通过">
              flutter analyze 0 error（88 info 均为历史基线，本次改动零新增）；6 个 commit 全部通过 pre-commit
              hooks；debug APK 每阶段构建成功；release APK 90.4MB 构建成功。
            </Callout>
            <Table columns={verifyColumns} rows={verifyRows} rowKey="item" density="compact" />
          </Stack>
        </ReportSection>

        <ReportSection title="真机验证清单（待执行）" divided>
          <Stack gap="component">
            <Text>以下验证需在真机环境执行（计划总验证清单的关键真机点）：</Text>
            <Text>1. 登录 token：flutter_secure_storage 10 实现重写，验证升级后已存 token 不丢失、重新登录正常。</Text>
            <Text>2. BLE 配网全流程：扫描 → 连接 → 读 SN → 写 WiFi 凭据 → 状态通知（flutter_blue_ultra 替换回归）。</Text>
            <Text>3. 通知点击跳转：flutter_local_notifications 22 初始化与 show 命名参数适配后的行为回归。</Text>
            <Text>4. 路由走查：go_router 17 升级后主要页面跳转回归。</Text>
            <Text>5. 仪表盘/趋势图/地图页人工走查：fl_chart 1.2 tooltip 与 flutter_map 8 瓦片加载。</Text>
            <Text>6. BLE 五大能力联调：依赖固件实现 CSIV-CT 服务（协议文档已交付评审），App 端架构已就绪。</Text>
          </Stack>
        </ReportSection>

        <ReportSection title="风险与说明" divided>
          <Stack gap="container">
            <RiskCallout
              level="medium"
              title="WIP 恢复注意：build.gradle.kts 合并要点"
              message="62 个 WIP 文件已收入新 stash@{0}（原 70 文件快照在 stash@{1}，双保险）。WIP 中曾用补 bcprov 依赖方案修同一 R8 问题；恢复 WIP 时 build.gradle.kts 需保留本次的 desugar 2.1.4 与 proguardFiles 引用（dontwarn 与 bcprov 两方案不冲突，如需联通 SDK 国密功能可再叠加 bcprov 依赖）。"
            />
            <RiskCallout
              level="low"
              title="flutter test 未在本机执行"
              message="本机 flutter_tester WebSocket 连接失败（主项目未改动基线同样失败，确认与本次改动无关），含新增的 ble_frame_reassembler_test.dart 7 用例，建议在 CI 或本机环境修复后重跑。"
            />
            <RiskCallout
              level="low"
              title="flutter_blue_ultra 生态风险有兜底"
              message="该包较新（发布约 2 个月），若出现稳定性问题，阶段 5 的 BleAdapter 抽象层可低成本切换到 universal_ble（仅需替换 ble_adapter.dart 实现类）。"
            />
            <Stack gap="component">
              <Text>1. 每阶段独立 commit，任一阶段可整体回退（0d45dc2c2 / fb2183e8f / 47eec0e9f / c2c82573e / 741bbdb30）。</Text>
              <Text>2. CI 流水线尚未触发（本地未 push），推送后请关注 flutter test 与 release 构建结果。</Text>
              <Text>3. worktree（2dSAS2）与 feature/dep-upgrade-ble 分支已保留，确认无后续需要后可清理。</Text>
              <Text>4. iOS/macOS/Windows 不在本次范围；GeneratedPluginRegistrant 等生成文件已随依赖同步。</Text>
            </Stack>
          </Stack>
        </ReportSection>

        <ReportSection title="证据文件索引" divided>
          <ReferencePanel items={evidenceItems} columns={2} />
        </ReportSection>
      </Stack>
    </ReportShell>
  );
}
