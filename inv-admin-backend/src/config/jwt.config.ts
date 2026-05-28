export const jwtConfig = {
  secret: process.env.JWT_SECRET || 'inv-mqtt-jwt-secret-key-2026',
  accessTokenExpires: process.env.JWT_ACCESS_EXPIRES || '15m',
  refreshTokenExpires: process.env.JWT_REFRESH_EXPIRES || '7d',
};
