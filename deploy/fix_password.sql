UPDATE users
SET password_hash = '$2a$10$8K1p/a0dL1LXMc0RBi9bKOBz.3wFLEV9bQVGS7bPBxHCJ1Wl2mH5e'
WHERE phone = '13800138000';

SELECT id, phone, password_hash, nickname, role, status FROM users WHERE phone = '13800138000';
