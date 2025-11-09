-- =============================================
-- Migration: 新增 use_primary_location 欄位到 items 表
-- 日期: 2025-11-08
-- 說明:
--   1. 新增 items.use_primary_location (BOOLEAN) 欄位
--   2. 預設值為 true (使用主要地點)
--   3. 移除 items.location_id 欄位 (如果尚未移除)
--   4. 建立 items_with_location View 方便查詢
--   5. 更新索引策略
--
-- 設計理念:
--   - 使用者限制: 1個主要地點 + 1個次要地點 (最多2個)
--   - 透過 boolean 欄位 JOIN locations 表
--   - 不儲存 location_id，避免數據冗餘
-- =============================================

BEGIN;

-- =============================================
-- Step 1: 移除舊的 location_id 欄位 (如果存在)
-- =============================================

DO $$
BEGIN
    -- 檢查 location_id 欄位是否存在
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name = 'location_id'
    ) THEN
        -- 先移除相關的外鍵約束 (如果有)
        DECLARE
            constraint_name TEXT;
        BEGIN
            SELECT tc.constraint_name INTO constraint_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
            WHERE tc.table_schema = 'public'
                AND tc.table_name = 'items'
                AND tc.constraint_type = 'FOREIGN KEY'
                AND kcu.column_name = 'location_id';

            IF constraint_name IS NOT NULL THEN
                EXECUTE format('ALTER TABLE public.items DROP CONSTRAINT %I', constraint_name);
                RAISE NOTICE '✓ 已移除外鍵約束: %', constraint_name;
            END IF;
        END;

        -- 移除欄位
        ALTER TABLE public.items DROP COLUMN location_id;
        RAISE NOTICE '✓ 已移除 items.location_id 欄位';
    ELSE
        RAISE NOTICE '✓ items.location_id 欄位不存在，跳過移除';
    END IF;
END $$;

-- =============================================
-- Step 2: 新增 use_primary_location 欄位 (若不存在則新增)
-- =============================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name = 'use_primary_location'
    ) THEN
        EXECUTE 'ALTER TABLE public.items ADD COLUMN use_primary_location BOOLEAN NOT NULL DEFAULT true';
        COMMENT ON COLUMN public.items.use_primary_location IS
        '指定物品使用主要地點或次要地點：\n- true: 使用主要地點 (locations.is_primary = true)\n- false: 使用次要地點 (locations.is_primary = false)\n透過 JOIN locations 表來動態獲取實際地點資訊';
        RAISE NOTICE '✓ 已新增 items.use_primary_location 欄位';
    ELSE
        RAISE NOTICE '✓ items.use_primary_location 欄位已存在，跳過新增';
    END IF;
END $$;

-- =============================================
-- Step 3: 建立索引優化查詢效能
-- =============================================

-- 為常見的查詢模式建立索引
CREATE INDEX IF NOT EXISTS idx_items_user_id_use_primary_location
    ON public.items(user_id, use_primary_location);

CREATE INDEX IF NOT EXISTS idx_items_listing_status_use_primary
    ON public.items(listing_status, use_primary_location)
    WHERE listing_status = true;

-- 確保 locations 表有適當的索引
CREATE INDEX IF NOT EXISTS idx_locations_user_id_is_primary
    ON public.locations(user_id, is_primary);

RAISE NOTICE '✓ 已建立索引優化';

-- =============================================
-- Step 4: 建立 View 方便查詢物品及其地點資訊
-- =============================================

CREATE OR REPLACE VIEW items_with_location AS
SELECT
    i.*,
    l.id AS location_id,
    l.coordinates AS location_coordinates,
    l.type AS location_type,
    l.formatted_address AS location_address,
    l.is_primary AS location_is_primary,
    l.created_at AS location_created_at
FROM public.items i
LEFT JOIN public.locations l
    ON l.user_id = i.user_id
    AND l.is_primary = i.use_primary_location;

COMMENT ON VIEW items_with_location IS
'物品及其關聯地點的完整資訊視圖
自動根據 use_primary_location 欄位 JOIN 對應的地點
使用範例: SELECT * FROM items_with_location WHERE id = 123';

RAISE NOTICE '✓ 已建立 items_with_location View';

-- =============================================
-- Step 5: 驗證資料完整性
-- =============================================

DO $$
DECLARE
    items_without_primary_location INT;
    items_without_secondary_location INT;
BEGIN
    -- 檢查有多少物品的使用者缺少主要地點
    SELECT COUNT(*) INTO items_without_primary_location
    FROM items i
    WHERE i.listing_status = true
        AND i.use_primary_location = true
        AND NOT EXISTS (
            SELECT 1 FROM locations l
            WHERE l.user_id = i.user_id
                AND l.is_primary = true
        );

    -- 檢查有多少物品的使用者缺少次要地點
    SELECT COUNT(*) INTO items_without_secondary_location
    FROM items i
    WHERE i.listing_status = true
        AND i.use_primary_location = false
        AND NOT EXISTS (
            SELECT 1 FROM locations l
            WHERE l.user_id = i.user_id
                AND l.is_primary = false
        );

    IF items_without_primary_location > 0 THEN
        RAISE WARNING '發現 % 個活動物品設定使用主要地點，但使用者缺少主要地點', items_without_primary_location;
    END IF;

    IF items_without_secondary_location > 0 THEN
        RAISE WARNING '發現 % 個活動物品設定使用次要地點，但使用者缺少次要地點', items_without_secondary_location;
    END IF;

    IF items_without_primary_location = 0 AND items_without_secondary_location = 0 THEN
        RAISE NOTICE '✓ 所有活動物品都有對應的地點設定';
    END IF;
END $$;

-- =============================================
-- Step 6: 更新統計資訊
-- =============================================

ANALYZE items;
ANALYZE locations;

COMMIT;

-- =============================================
-- Migration 完成通知
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251108000001';
    RAISE NOTICE '====================================';
    RAISE NOTICE '✓ 已新增 items.use_primary_location 欄位';
    RAISE NOTICE '✓ 已移除 items.location_id 欄位（如有）';
    RAISE NOTICE '✓ 已建立 items_with_location View';
    RAISE NOTICE '✓ 已優化索引策略';
    RAISE NOTICE '';
    RAISE NOTICE '下一步：';
    RAISE NOTICE '1. 執行 Migration 2: 更新 create_item RPC 函數';
    RAISE NOTICE '2. 更新前端 API';
    RAISE NOTICE '====================================';
    RAISE NOTICE '';
END $$;
