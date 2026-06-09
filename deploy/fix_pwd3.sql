UPDATE users SET password_hash = '$2b$10$3eKctLeE.UX24vah2tgu3e7FM6GK3YyLC3vdB8RuUh2jm49yUovTm' WHERE phone = '13800138000';
SELECT id, phone, nickname, role, password_hash FROM users WHERE phone = '13800138000';
