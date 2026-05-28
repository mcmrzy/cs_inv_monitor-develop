export const redisConfig = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
  password: process.env.REDIS_PASS || undefined,
  db: parseInt(process.env.REDIS_DB || '0', 10),
};
