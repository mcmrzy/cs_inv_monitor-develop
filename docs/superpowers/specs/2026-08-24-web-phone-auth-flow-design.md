# Web 注册与验证码登录流程设计

## 目标

修复 Web 端手机号验证码登录和注册流程：未注册手机号在登录发码阶段立即得到明确提示，注册成功后直接建立登录态并进入系统。

## 现状与根因

- `business-api/internal/handler/auth_handler.go` 的 `/auth/send-code` 仅对手机号验证码重置密码拦截未注册账号，登录场景仍会发送验证码；`/auth/phone-code-login` 直到验证码校验后才检查用户是否存在。
- `/auth/register` 和 `/auth/email-register` 已返回登录所需的 access token、refresh token、用户和权限，但 `inv-admin-frontend/src/pages/login/index.tsx` 的注册回调只显示成功消息并切回登录视图，未消费响应中的登录信息。

## 设计

1. 在后端发短信验证码入口增加 `type == "login" && existingUser == nil` 的 4001 业务错误；保留 `register` 允许未注册手机号、`reset_password` 要求已注册手机号的现有语义。
2. Web 前端将注册响应解析为统一登录响应，调用现有 `authStore.login(...)`，显示注册成功消息后使用 `navigate('/dashboard', { replace: true })` 进入系统。手机号和邮箱注册保持一致。
3. Web 发码错误沿用现有统一错误码映射，并为手机号登录发码使用明确的“手机号未注册”文案；不在前端增加独立的用户查询接口，避免先查后发的竞态和额外暴露。

## 验收标准

- WHEN 未注册手机号在验证码登录页面点击发送验证码 THEN Web 显示手机号未注册，且后端不调用短信发送服务。
- WHEN 已注册手机号在验证码登录页面点击发送验证码 THEN 现有滑块校验、发送频率限制和发送成功倒计时行为保持不变。
- WHEN 手机号或邮箱注册接口成功返回登录响应 THEN Web 保存 token、用户和权限，跳转到 `/dashboard`，无需再次输入账号密码。
- WHEN 注册接口返回业务错误 THEN Web 保持在注册页面并显示原有错误提示，不写入登录态。

## 测试策略

- 前端 LoginPage 测试覆盖未注册手机号发码错误、手机号注册成功自动登录与跳转；保留现有登录和注册请求字段测试。
- 后端保留接口级逻辑的最小改动，运行 Go handler/service 测试与构建验证；前端运行 LoginPage 定向测试、类型检查和构建。
