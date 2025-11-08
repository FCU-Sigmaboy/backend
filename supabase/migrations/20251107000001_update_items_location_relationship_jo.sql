-- =============================================
-- Migration: 更新 items 表的 location 關聯機制
-- 日期: 2025-11-07
-- 說明:
--   1. 移除 items.location_id 外鍵約束
--   2. 保留 location_id 欄位（暫時），但允許 NULL
--   3. 更新所有 RPC 函數，改用 user_id JOIN locations
--   4. 這是第一階段 migration，之後會完全移除 location_id
-- =============================================

BEGIN;

-- =============================================
-- 步驟 1: 移除外鍵約束
-- =============================================

-- 檢查並移除 items 表的 location_id 外鍵約束
DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    -- 找出 location_id 的外鍵約束名稱
    SELECT tc.constraint_name INTO constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_schema = 'public'
        AND tc.table_name = 'items'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'location_id';

    -- 如果找到約束，則刪除
    IF constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.items DROP CONSTRAINT %I', constraint_name);
        RAISE NOTICE '已移除外鍵約束: %', constraint_name;
    ELSE
        RAISE NOTICE '未找到 location_id 的外鍵約束';
    END IF;
END $$;

-- =============================================
-- 步驟 2: 修改 location_id 欄位為可選
-- =============================================

-- 將 location_id 改為允許 NULL（保留欄位以便向後相容）
ALTER TABLE public.items
    ALTER COLUMN location_id DROP NOT NULL;

COMMENT ON COLUMN public.items.location_id IS
'[已棄用] 此欄位將在未來版本中移除。請改用 user_id 關聯 locations 表。';

-- =============================================
-- 步驟 3: 更新索引策略
-- =============================================

-- 確保有適當的索引支援新的查詢模式
CREATE INDEX IF NOT EXISTS idx_locations_user_id_primary
    ON public.locations(user_id, is_primary)
    WHERE is_primary = true;

CREATE INDEX IF NOT EXISTS idx_items_user_id_listing_status
    ON public.items(user_id, listing_status)
    WHERE listing_status = true;

-- =============================================
-- 驗證資料完整性
-- =============================================

-- 檢查是否所有活動物品的使用者都有 location
DO $$
DECLARE
    missing_location_count INT;
BEGIN
    SELECT COUNT(*) INTO missing_location_count
    FROM public.items i
    WHERE i.listing_status = true
        AND NOT EXISTS (
            SELECT 1 FROM public.locations l
            WHERE l.user_id = i.user_id
        );

    IF missing_location_count > 0 THEN
        RAISE WARNING '發現 % 個活動物品的使用者沒有設定地點', missing_location_count;
    ELSE
        RAISE NOTICE '所有活動物品的使用者都有設定地點';
    END IF;
END $$;

COMMIT;

-- =============================================
-- 說明與注意事項
-- =============================================

COMMENT ON TABLE public.items IS
'物品表 - 已更新為使用 user_id 關聯 locations，不再直接使用 location_id';

-- 記錄 migration 版本
DO $$
BEGIN
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251107000001';
    RAISE NOTICE '已更新 items 表的 location 關聯機制';
    RAISE NOTICE '下一步: 更新所有 RPC 函數';
    RAISE NOTICE '====================================';
END $$;
