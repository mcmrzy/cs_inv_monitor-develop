-- OTA Enhancement Migration 2026-05-25
-- Adds SHA256 checksum, grayscale push strategy, and batch support

-- Add file_sha256 column to firmware_versions table
ALTER TABLE firmware_versions ADD COLUMN IF NOT EXISTS file_sha256 VARCHAR(64);

-- Add push strategy columns to ota_tasks table
ALTER TABLE ota_tasks ADD COLUMN IF NOT EXISTS push_strategy VARCHAR(20) DEFAULT 'all_at_once';
ALTER TABLE ota_tasks ADD COLUMN IF NOT EXISTS push_percentage INTEGER DEFAULT 100;
ALTER TABLE ota_tasks ADD COLUMN IF NOT EXISTS batch_size INTEGER DEFAULT 10;

-- Add mqtt_message column to ota_task_devices table for tracking MQTT notification content
ALTER TABLE ota_task_devices ADD COLUMN IF NOT EXISTS mqtt_message TEXT;
