\set ON_ERROR_STOP on

-- This bootstrap script intentionally contains no default credentials.
-- Generate a bcrypt hash outside the database, then invoke with psql:
--   psql --set=admin_phone=... --set=admin_email=... \
--     --set=admin_nickname=... --set=admin_password_hash=... \
--     -f create_admin.sql
-- Use a newly generated password and pass the hash through a protected
-- environment/secret manager. Do not place it in source control or shell history.

\if :{?admin_phone}
\else
  \echo 'ERROR: admin_phone is required'
  \quit
\endif
\if :{?admin_email}
\else
  \echo 'ERROR: admin_email is required'
  \quit
\endif
\if :{?admin_nickname}
\else
  \echo 'ERROR: admin_nickname is required'
  \quit
\endif
\if :{?admin_password_hash}
\else
  \echo 'ERROR: admin_password_hash is required'
  \quit
\endif

BEGIN;

INSERT INTO users (phone, email, password_hash, nickname, role, status, created_at, updated_at)
VALUES (
  :'admin_phone',
  :'admin_email',
  :'admin_password_hash',
  :'admin_nickname',
  0,
  1,
  NOW(),
  NOW()
)
ON CONFLICT (phone) DO UPDATE SET
  email = EXCLUDED.email,
  password_hash = EXCLUDED.password_hash,
  nickname = EXCLUDED.nickname,
  role = 0,
  status = 1,
  updated_at = NOW()
RETURNING id, phone, email, nickname, role, status;

COMMIT;
