-- =============================================
-- Migration: 更新 create_item 函數支援 use_primary_location
-- 日期: 2025-11-08
-- 說明:
--   1. 更新 create_item 函數，新增 p_use_primary_location 參數
--   2. 預設使用主要地點 (true)
--   3. 驗證使用者是否有對應的地點
--   4. 建立物品時記錄 use_primary_location
--
-- 設計理念:
--   - 最小化變更，只更新核心刊登函數
--   - 保持向後相容（預設行為與 v2.0 相同）
--   - 透過 boolean 欄位實現地點選擇
-- =============================================

BEGIN;

-- =============================================
-- 刪除舊版本的 create_item 函數
-- =============================================

DROP FUNCTION IF EXISTS public.create_item(INT, BIGINT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS public.create_item(INT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[]);

-- =============================================
-- 建立新版本的 create_item 函數（支援 use_primary_location）
-- =============================================

CREATE OR REPLACE FUNCTION public.create_item(
    p_sub_category_id INT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),
    p_price INT,
    p_use_primary_location BOOLEAN DEFAULT true,  -- 新增參數，預設使用主要地點
    p_carbon_value NUMERIC DEFAULT NULL,
    p_image_urls TEXT[] DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_new_item items;
    v_location_exists BOOLEAN;
    v_location_info JSON;
BEGIN
    -- =============================================
    -- 1. 驗證：確認使用者已登入
    -- =============================================
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法刊登物品';
    END IF;

    -- =============================================
    -- 2. 驗證：確認使用者有對應的地點
    -- =============================================
    SELECT EXISTS (
        SELECT 1 FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = p_use_primary_location
    ) INTO v_location_exists;

    IF NOT v_location_exists THEN
        IF p_use_primary_location THEN
            RAISE EXCEPTION '請先在個人資料中設定主要地點後再刊登物品';
        ELSE
            RAISE EXCEPTION '請先在個人資料中設定次要地點後再刊登物品';
        END IF;
    END IF;

    -- =============================================
    -- 3. 驗證：確認物品狀況有效
    -- =============================================
    IF p_condition NOT IN ('全新', '近全新', '良好', '普通', '需修理') THEN
        RAISE EXCEPTION '無效的物品狀況: %。有效值為：全新、近全新、良好、普通、需修理', p_condition;
    END IF;

    -- =============================================
    -- 4. 驗證：確認子分類存在
    -- =============================================
    IF NOT EXISTS (
        SELECT 1 FROM public.sub_categories
        WHERE id = p_sub_category_id
    ) THEN
        RAISE EXCEPTION '無效的子分類 ID: %', p_sub_category_id;
    END IF;

    -- =============================================
    -- 5. 建立物品（包含 use_primary_location）
    -- =============================================
    INSERT INTO public.items (
        user_id,
        sub_category_id,
        use_primary_location,  -- 新增欄位
        title,
        description,
        condition,
        listing_status,
        price,
        carbon_value,
        image_urls,
        tags,
        created_at,
        updated_at
    )
    VALUES (
        v_current_uid,
        p_sub_category_id,
        p_use_primary_location,  -- 記錄使用主要或次要地點
        p_title,
        p_description,
        p_condition,
        TRUE,
        p_price,
        COALESCE(p_carbon_value, 0),
        COALESCE(p_image_urls, ARRAY[]::TEXT[]),
        COALESCE(p_tags, ARRAY[]::TEXT[]),
        NOW(),
        NOW()
    )
    RETURNING * INTO v_new_item;

    -- =============================================
    -- 6. 獲取地點資訊（用於回傳）
    -- =============================================
    SELECT json_build_object(
        'id', l.id,
        'formatted_address', l.formatted_address,
        'type', l.type,
        'is_primary', l.is_primary
    ) INTO v_location_info
    FROM locations l
    WHERE l.user_id = v_current_uid
      AND l.is_primary = p_use_primary_location
    LIMIT 1;

    -- =============================================
    -- 7. 回傳建立成功的物品資訊（包含地點資訊）
    -- =============================================
    RETURN json_build_object(
        'success', true,
        'item', json_build_object(
            'id', v_new_item.id,
            'title', v_new_item.title,
            'price', v_new_item.price,
            'use_primary_location', v_new_item.use_primary_location,
            'created_at', v_new_item.created_at
        ),
        'location', v_location_info,
        'message', '物品刊登成功'
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '建立物品時發生錯誤: %', SQLERRM;
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM,
            'message', '物品刊登失敗，請稍後再試'
        );
END;
$$;

-- =============================================
-- 設定函數註解
-- =============================================

COMMENT ON FUNCTION public.create_item(INT, TEXT, TEXT, VARCHAR, INT, BOOLEAN, NUMERIC, TEXT[], TEXT[])
IS '建立新物品（刊登）v3.0：
- 新增 p_use_primary_location 參數（預設 true）
  * true: 使用主要地點 (is_primary=true)
  * false: 使用次要地點 (is_primary=false)
- 透過 user_id + is_primary 自動關聯到對應的地點
- 驗證使用者是否有對應的地點設定
- 回傳物品資訊及其使用的地點資訊

使用範例:
-- 使用主要地點（預設）
SELECT create_item(1, ''標題'', ''描述'', ''良好'', 100);

-- 使用次要地點
SELECT create_item(1, ''標題'', ''描述'', ''良好'', 100, false);';

-- =============================================
-- Migration 完成通知
-- =============================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251108000002';
    RAISE NOTICE '====================================';
    RAISE NOTICE '✓ 已更新 create_item 函數';
    RAISE NOTICE '';
    RAISE NOTICE '函數簽名：';
    RAISE NOTICE 'create_item(';
    RAISE NOTICE '  p_sub_category_id INT,';
    RAISE NOTICE '  p_title TEXT,';
    RAISE NOTICE '  p_description TEXT,';
    RAISE NOTICE '  p_condition VARCHAR(20),';
    RAISE NOTICE '  p_price INT,';
    RAISE NOTICE '  p_use_primary_location BOOLEAN DEFAULT true,  -- 新增';
    RAISE NOTICE '  p_carbon_value NUMERIC DEFAULT NULL,';
    RAISE NOTICE '  p_image_urls TEXT[] DEFAULT NULL,';
    RAISE NOTICE '  p_tags TEXT[] DEFAULT NULL';
    RAISE NOTICE ')';
    RAISE NOTICE '';
    RAISE NOTICE '下一步：更新前端 API';
    RAISE NOTICE '====================================';
    RAISE NOTICE '';
END $$;
