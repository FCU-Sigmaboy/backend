-- ====================================================================
-- 刊登物品函數 (Create Item Function)
-- ====================================================================
-- 修改日期: 2025-11-02
-- 修改者: Claude Code
-- 修改內容:
--   1. 修正 p_condition 型別從 public.item_condition 改為 VARCHAR(20)
--   2. 修正 INSERT 欄位名稱從 user_location_id 改為 location_id
--   3. 新增 condition 值驗證
--   4. 新增 location 所有權驗證
--   5. 【2025-11-02】將 p_carbon_value, p_image_urls, p_tags 改為可選參數
--   6. 【2025-11-02】使用 COALESCE 處理 NULL 值
-- ====================================================================

CREATE OR REPLACE FUNCTION public.create_item(
    p_sub_category_id INT,
    p_user_location_id BIGINT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),
    p_price INT,
    p_carbon_value NUMERIC DEFAULT NULL,
    p_image_urls TEXT[] DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL
)
RETURNS JSON
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_new_item items;
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法刊登物品';
    END IF;

    IF p_condition NOT IN ('全新', '近全新', '良好', '普通', '需修理') THEN
        RAISE EXCEPTION '無效的物品狀況: %。有效值為：全新、近全新、良好、普通、需修理', p_condition;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.locations
        WHERE id = p_user_location_id AND user_id = v_current_uid
    ) THEN
        RAISE EXCEPTION 'Invalid location or not owned by user';
    END IF;

    INSERT INTO public.items (
        user_id,
        sub_category_id,
        location_id,
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
        p_user_location_id,
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

    RETURN json_build_object(
        'id', v_new_item.id,
        'title', v_new_item.title,
        'created_at', v_new_item.created_at
    );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.create_item(INT, BIGINT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[])
IS 'Create new item listing with validation';
