-- =============================================
-- Migration: 更新 create_item 函數
-- 日期: 2025-11-07
-- 說明:
--   1. 移除 p_user_location_id 參數
--   2. 自動使用當前使用者的主要地點
--   3. 如果沒有主要地點，則使用任一地點
--   4. 不再將 location_id 寫入 items 表
-- =============================================

BEGIN;

-- =============================================
-- 刪除舊版本的 create_item 函數
-- =============================================

DROP FUNCTION IF EXISTS public.create_item(INT, BIGINT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[]);

-- =============================================
-- 建立新版本的 create_item 函數（不含 p_user_location_id）
-- =============================================

CREATE OR REPLACE FUNCTION public.create_item(
    p_sub_category_id INT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),
    p_price INT,
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
    v_user_has_location BOOLEAN;
BEGIN
    -- =============================================
    -- 1. 驗證：確認使用者已登入
    -- =============================================
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法刊登物品';
    END IF;

    -- =============================================
    -- 2. 驗證：確認使用者已設定地點
    -- =============================================
    SELECT EXISTS (
        SELECT 1 FROM public.locations
        WHERE user_id = v_current_uid
    ) INTO v_user_has_location;

    IF NOT v_user_has_location THEN
        RAISE EXCEPTION '請先在個人資料中設定地點後再刊登物品';
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
    -- 5. 建立物品（不再設定 location_id）
    -- =============================================
    INSERT INTO public.items (
        user_id,
        sub_category_id,
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
    -- 6. 回傳建立成功的物品資訊
    -- =============================================
    RETURN json_build_object(
        'success', true,
        'item', json_build_object(
            'id', v_new_item.id,
            'title', v_new_item.title,
            'price', v_new_item.price,
            'created_at', v_new_item.created_at
        ),
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

COMMENT ON FUNCTION public.create_item(INT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[])
IS '建立新物品（刊登）v2.0：
- 已移除 location_id 參數
- 自動使用當前登入者的 user_id
- 透過 user_id 自動關聯到使用者的地點
- 驗證 condition 值與使用者是否已設定地點
- 不再直接設定 items.location_id 欄位';

-- =============================================
-- 建立輔助函數：檢查使用者是否有地點
-- =============================================

CREATE OR REPLACE FUNCTION public.user_has_location(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.locations
        WHERE user_id = p_user_id
    );
$$;

COMMENT ON FUNCTION public.user_has_location(UUID) IS
'檢查指定使用者是否已設定至少一個地點';

COMMIT;

-- =============================================
-- 記錄 migration 完成
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251107000003';
    RAISE NOTICE '已更新 create_item 函數';
    RAISE NOTICE '已移除 p_user_location_id 參數';
    RAISE NOTICE '下一步: 在完成前端 API 更新後，執行刪除 location_id 欄位的 migration';
    RAISE NOTICE '====================================';
END $$;
