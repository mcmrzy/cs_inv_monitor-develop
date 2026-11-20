BEGIN;
SELECT pg_advisory_xact_lock(11645);
DO $release$
BEGIN
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code > 49
             AND status = 1 AND NOT COALESCE(is_rolled_back, false)) THEN
    RAISE EXCEPTION 'A newer Android release is already live';
  END IF;
  IF EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 49
             AND (file_sha256 IS DISTINCT FROM 'f49ffb3e8fa081c1a963266bb34574ef5b62d07d5f57bc9c2a1e87a568f74a5e'
                  OR status IS DISTINCT FROM 1 OR COALESCE(is_rolled_back, false)
                  OR rollout_percentage IS DISTINCT FROM 100)) THEN
    RAISE EXCEPTION 'Android release 49 already exists in a different state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 49)
     AND NOT EXISTS (SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 48
                     AND file_sha256 = '269ab899ebd11330aa0b54d3be179aead8c2ece2327fb8c557efc79b7ffccb2e'
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
  'android', 49, '1.1.21',
  '/firmware/apps/android/com.csergy.app1-1.1.21-49-f49ffb3e8fa0.apk',
  44985453, 'e3ff0546ca2a1203387fdd9e0e987f20',
  '远程设置和蓝牙设置改用彩色分类图标和分组列表，参数右侧显示当前值。远程充电电流按机型支持的档位选择。更新蓝牙直连设备卡和首页底部导航。',
  false, 0, 100, 1, 0,
  'f49ffb3e8fa081c1a963266bb34574ef5b62d07d5f57bc9c2a1e87a568f74a5e',
  'com.csergy.app1', 'com.csergy.app1-1.1.21-49-f49ffb3e8fa0.apk', 29, 36
WHERE NOT EXISTS (
  SELECT 1 FROM app_versions WHERE platform = 'android' AND version_code = 49
);
SELECT version_name, version_code, file_sha256
FROM app_versions WHERE platform = 'android' AND version_code = 49;
COMMIT;
