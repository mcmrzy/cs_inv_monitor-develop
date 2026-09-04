# CSERGY SVG 图标质量验收记录

- 验收日期：2026-08-05
- 验收范围：`inv_app/assets/icons/csergy/`
- 生产任务：B（仅 SVG 质量修正与 QA 记录）
- 本轮状态：24 个 SVG 已完成统一规范化并落盘；未修改业务代码、`pubspec.yaml` 或其他资源。

## 统一生产规范

- 根节点固定为 `width="24"`、`height="24"`、`viewBox="0 0 24 24"`。
- 主轮廓和可主题化内容使用 `currentColor`，保证 Flutter `SvgPicture.asset` 可随主题着色。
- 默认线宽控制在 `1.4–1.9`，优先使用圆角端点和圆角连接；避免 24dp 下出现过细、过重或尖锐断裂。
- 所有图标保留轻量六边形角标/节点母题；不强行给会影响识别度的区域增加装饰。
- 固定业务语义色：
  - `#20C4E8`：普通态科技青、网络/设备辅助色
  - `#C9F23B`：选中态、能量/成功/下载辅助色
  - `#FFC857`：光伏/太阳能
  - `#6C63E8`：储能/电池柜
  - `#EF6B62`：告警/风险
  - `#FFFFFF`：选中态内部镂空细节
- 已移除旧版 `#1769E0`、`#32C7A5` 调色板。

## 文件覆盖

### 底部导航双态（12 个文件，6 组）

- `nav_home_normal.svg` / `nav_home_active.svg`
- `nav_devices_normal.svg` / `nav_devices_active.svg`
- `nav_alarms_normal.svg` / `nav_alarms_active.svg`
- `nav_ota_normal.svg` / `nav_ota_active.svg`
- `nav_profile_normal.svg` / `nav_profile_active.svg`
- `nav_statistics_normal.svg` / `nav_statistics_active.svg`

### 能源业务图标（12 个）

- `solar.svg`
- `grid.svg`
- `battery.svg`
- `load.svg`
- `inverter.svg`
- `storage.svg`
- `power.svg`
- `energy_flow.svg`
- `monitoring.svg`
- `warning.svg`
- `wifi.svg`
- `firmware.svg`

> 上述业务清单为 12 个；加上 12 个导航双态文件，共 24 个 SVG。

## 已执行验证

1. `System.Xml.XmlDocument` 逐文件解析：24/24 通过，未发现非法 XML。
2. 逐文件检查根节点：24/24 使用 `24×24` 与 `0 0 24 24`。
3. 逐文件检查主题色：24/24 包含 `currentColor`。
4. 逐文件检查色板：仅使用 CSERGY 生产色板及选中态白色镂空；未发现旧版蓝绿值。
5. 逐文件检查线宽：所有 `stroke-width` 均在 `1.4–1.9` 范围内。
6. 逐文件检查六边形角标/节点签名：24/24 存在可识别的六边形母题。
7. `pwsh -NoProfile -File tools/validate_csergy_assets.ps1`：通过；该脚本当前内置清单报告 22 个文件。

## 需要注意的校验缺口

仓库现有 `tools/validate_csergy_assets.ps1` 的 `requiredFiles` 漏列了 `nav_ota_normal.svg` 与 `nav_ota_active.svg`，因此它的通过输出是“22 SVG files”，不能代表完整的 24 文件门禁。本任务没有修改该脚本，因为生产任务 B 明确限制只修改图标目录和本 QA 文档；后续应由维护脚本的任务补上这两个文件。

## 剩余风险与未修项

- 未运行 Flutter 真机/模拟器的 24dp 光学验收；当前环境没有可用的 SVG 栅格化工具，浅色/深色主题下的最终对比度仍需在 App 中确认。
- 未验证低端 Android 设备上的 SVG 解码耗时与首屏包体影响。
- `currentColor` 的最终显示色取决于业务组件传入的 `color`；若页面未传入主题色，图标外观需要由 Flutter 接入层继续确认。
- 以上属于运行时/视觉验收风险，不是本轮 SVG XML、尺寸、色板、线宽或结构门禁未修问题。
