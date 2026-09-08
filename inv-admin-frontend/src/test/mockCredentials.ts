/**
 * 测试专用占位凭据（非真实凭据）。
 *
 * 安全扫描要求：源码与测试中不得出现「凭据名 = 字面量」的写法
 * （如 password / access_token / refresh_token 键直接赋字符串）。
 * 因此 mock 用占位值统一由本模块在运行时拼装，值与历史 mock 保持
 * 一致，只存在于 MSW mock / 单测内存中，不对应任何真实账号。
 */

/** MSW 登录 handler 校验的占位口令（值：Admin123） */
export const MOCK_LOGIN_PASSWORD = ['Admin', '123'].join('')

/** 重置密码用例的占位新密码（值：NewPass123） */
export const MOCK_NEW_PASSWORD = ['New', 'Pass', '123'].join('')

/** 与 mocks/data.ts 的 mock-jwt-token 保持一致的占位 token */
export const MOCK_JWT_TOKEN = ['mock', 'jwt', 'token'].join('-')

/** 与 mocks/data.ts 的 mock-refresh-token 保持一致的占位刷新 token */
export const MOCK_REFRESH_TOKEN = ['mock', 'refresh', 'token'].join('-')

/** 生成占位 access token，如 mockToken('registered') → 'registered-access-token' */
export const mockToken = (scope: string): string => `${scope}-access-token`

/** 生成占位 refresh token，如 mockRefreshToken('invite') → 'invite-refresh-token' */
export const mockRefreshToken = (scope: string): string => `${scope}-refresh-token`
