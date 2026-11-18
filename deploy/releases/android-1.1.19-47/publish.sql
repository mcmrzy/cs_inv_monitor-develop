BEGIN;
SELECT pg_advisory_xact_lock(11645);
DO $release$
BEGIN
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code > 47
             AND status = 1 AND NOT COALESCE(is_rolled_back, false)) THEN
    RAISE EXCEPTION 'A newer Android release is already live';
  END IF;
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 47
             AND (file_sha256 IS DISTINCT FROM 'ee692a4aefeb2c6656da9b3aaf33e4abc369dbc0b711fe0ede77ee77897aa176'
                  OR status IS DISTINCT FROM 1 OR COALESCE(is_rolled_back, false)
                  OR rollout_percentage IS DISTINCT FROM 100)) THEN
    RAISE EXCEPTION 'Android release 47 already exists in a different state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 47)
     AND NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 46
                     AND file_sha256 = '50bc22b50711ec6fe69cd6350cd4f2da097942c84dddf81d52ae7f5d2b2a659f'
                     AND status = 1 AND NOT COALESCE(is_rolled_back, false)) THEN
    RAISE EXCEPTION 'The current Android release differs from the verified upgrade base';
  END IF;
END
$release$;
INSERT INTO app_versions (
  platform, version_code, version_name, download_url, file_size, file_md5, changelog,
  is_force, min_supported_version, rollout_percentage, status, created_by,
  file_sha256, package_name, file_name, min_sdk, target_sdk
)
SELECT
  'android', 47, '1.1.19',
  '/firmware/apps/android/com.csergy.app1-1.1.19-47-ee692a4aefeb.apk',
  45327185, '70532651bb06978cc2684057181ac56d',
  '重新设计远程设置、蓝牙设置、蓝牙连接和固件升级页面，优化首页数据加载和缓存。',
  false, 0, 100, 1, 0,
  'ee692a4aefeb2c6656da9b3aaf33e4abc369dbc0b711fe0ede77ee77897aa176',
  'com.csergy.app1', 'com.csergy.app1-1.1.19-47-ee692a4aefeb.apk', 29, 36
WHERE NOT EXISTS (
  SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 47
);
SELECT version_name, version_code, file_sha256
FROM app_versions WHERE platform = 'android' AND version_code = 47;
COMMIT;
