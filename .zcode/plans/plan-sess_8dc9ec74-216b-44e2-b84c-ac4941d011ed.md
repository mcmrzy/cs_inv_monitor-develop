处理 pre-commit 钩子拦截并完成提交

背景：git commit 被 .githooks/pre-commit 拦截——新增的 inv_app/assets/images/avatar_default.png 为 1158×1270、1.26MB，超过钩子的 500KB 上限。该文件被 lib/core/theme/csergy_assets.dart:58 引用，且新增的 test/assets/asset_integrity_test.dart 断言它必须以真实 PNG 存在，因此不能从提交中剔除。

步骤：
1. 压缩图片到 500KB 以下（优先级依次尝试，取第一个达标结果）：
   a. python + PIL 可用则量化/优化重编码（保持原尺寸）
   b. 否则用 PowerShell + .NET System.Drawing 重编码
   c. 仍超标则缩到 512px 长边（与被替换的 avatar_default_512.webp 规格一致）
2. 校验：文件 <500KB 且 PNG 签名有效（asset_integrity_test 的要求）
3. git add 该文件，用已拟好的提交信息重新提交（/tmp/commit_msg.txt 已就绪）：
   feat(app): 重构认证与组织权限链路并更新品牌资源（7 条 bullet 正文）
4. git log -1 确认提交成功、钩子通过

回退方案：若压缩工具全部不可用或压缩后仍超标，改用 git commit --no-verify（钩子自带说明的逃生口，但标注不推荐），并在总结中明确告知用户。

说明：.githooks ×5 与 inv-admin-frontend ×2 的"修改"是 CRLF 行尾符幽灵改动（diff 内容为空），已刻意不纳入暂存，提交后工作区仍会显示它们为已修改，属正常现象。