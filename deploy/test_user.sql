SELECT count(*) as user_count FROM users;

SELECT id, phone, email, nickname, role, status, deleted_at, length(password_hash) as pwd_len FROM users;

DELETE FROM users;

INSERT INTO users (phone, email, password_hash, nickname, role, status)
VALUES ('13800138000', 'admin@test.com', '$2b$10$nCKVzRd3n8haY2WnRY6LjuHD2eha25sKELxlPAK3AfxsjZFT1j4fK', 'admin', 0, 1);

SELECT id, phone, email, nickname, role, status, deleted_at, length(password_hash) as pwd_len FROM users;
