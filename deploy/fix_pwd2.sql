UPDATE users SET password_hash = '$2b$10$zumGzMu/aL2jeJIAQJVwA.FrWisbsYuPzldp7SI2vXoIzFLFSNy4y' WHERE phone = '13800138000';
SELECT id, phone, nickname, role, status FROM users;
