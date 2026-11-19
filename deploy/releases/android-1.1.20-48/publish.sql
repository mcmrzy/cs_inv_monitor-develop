BEGIN;
SELECT pg_advisory_xact_lock(11645);
DO $release$
BEGIN
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code > 48
             AND status = 1 AND NOT COALESCE(is_rolled_back, false)) THEN
    RAISE EXCEPTION 'A newer Android release is already live';
  END IF;
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 48
             AND (file_sha256 IS DISTINCT FROM '269ab899ebd11330aa0b54d3be179aead8c2ece2327fb8c557efc79b7ffccb2e'
                  OR status IS DISTINCT FROM 1 OR COALESCE(is_rolled_back, false)
                  OR rollout_percentage IS DISTINCT FROM 100)) THEN
    RAISE EXCEPTION 'Android release 48 already exists in a different state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 48)
     AND NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 47
                     AND file_sha256 = 'ee692a4aefeb2c6656da9b3aaf33e4abc369dbc0b711fe0ede77ee77897aa176'
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
  'android', 48, '1.1.20',
  '/firmware/apps/android/com.csergy.app1-1.1.20-48-269ab899ebd1.apk',
  45416605, '2556d7d9e967be7b761ff481c19003a7',
  '更新首次启动和快速设置引导；恢复渐变能量流图并接入电网功率；统一远程设置和蓝牙页面，读取时保留参数列表；固件升级支持查看历史发布版本及更新说明，离网时提示先下载。',
  false, 0, 100, 1, 0,
  '269ab899ebd11330aa0b54d3be179aead8c2ece2327fb8c557efc79b7ffccb2e',
  'com.csergy.app1', 'com.csergy.app1-1.1.20-48-269ab899ebd1.apk', 29, 36
WHERE NOT EXISTS (
  SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 48
);
SELECT version_name, version_code, file_sha256
FROM app_versions WHERE platform = 'android' AND version_code = 48;
COMMIT;
