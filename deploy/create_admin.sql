DELETE FROM users WHERE phone = '13800138000';

INSERT INTO users (phone, email, password_hash, nickname, role, status, created_at, updated_at)
VALUES (
  '13800138000',
  'admin@example.com',
  '$2b$10$nCKVzRd3n8haY2WnRY6LjuHD2eha25sKELxlPAK3AfxsjZFT1j4fK',
  '管理员',
  0,
  1,
  NOW(),
  NOW()
);

SELECT id, phone, email, nickname, role, status, password_hash FROM users WHERE phone = '13800138000';
