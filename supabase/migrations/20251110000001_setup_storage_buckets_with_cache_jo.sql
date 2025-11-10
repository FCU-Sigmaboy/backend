-- 版本更新註釋：2025-11-10 設定 Storage buckets 並啟用快取以減少 Egress 流量

-- =============================================
-- 建立 Storage Buckets 並設定快取
-- =============================================

-- 建立 avatars bucket (公開，用於使用者頭像)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    true,
    5242880, -- 5 MB
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

-- 建立 items bucket (公開，用於物品圖片)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'items',
    'items',
    true,
    10485760, -- 10 MB (降低從 50MB)
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

-- =============================================
-- 設定預設快取標頭 (透過 metadata)
-- =============================================

-- 注意: Supabase Storage 的快取控制主要透過：
-- 1. 上傳時在 options 中設定 cacheControl
-- 2. 透過 Supabase Dashboard 設定 bucket 層級的快取
--
-- 此 migration 確保 buckets 存在且配置正確
-- 實際快取標頭需在前端上傳時設定 (見 create_myItemAPI.js)

-- =============================================
-- 更新現有檔案的 metadata (如果需要)
-- =============================================

-- 為現有的 items bucket 物件設定快取 metadata
UPDATE storage.objects
SET metadata = COALESCE(metadata, '{}'::jsonb) ||
    '{"cacheControl": "public, max-age=31536000, immutable"}'::jsonb
WHERE bucket_id = 'items'
  AND (metadata->>'cacheControl') IS NULL;

-- 為現有的 avatars bucket 物件設定快取 metadata
UPDATE storage.objects
SET metadata = COALESCE(metadata, '{}'::jsonb) ||
    '{"cacheControl": "public, max-age=86400"}'::jsonb
WHERE bucket_id = 'avatars'
  AND (metadata->>'cacheControl') IS NULL;
