-- ####################################################################
-- ### 刊登物品 (RPC)
-- ####################################################################
-- 最後修改: 2025-11-02 by Claude Code
-- 修改內容:
--   1. 修正 line 11: p_condition 型別從 public.item_condition 改為 VARCHAR(20)
--   2. 修正 line 32: 欄位名稱從 user_location_id 改為 location_id
--   3. 新增 condition 值驗證 (line 28-30)
--   4. 新增 location 所有權驗證 (line 32-39)
--   5. 新增函數註解 (line 70)
--   6. 【2025-11-02】將 p_carbon_value, p_image_urls, p_tags 改為可選參數 (DEFAULT NULL)
--   7. 【2025-11-02】使用 COALESCE 處理 NULL 值，設定預設值
-- ####################################################################

CREATE OR REPLACE FUNCTION public.create_item(
    -- Item 表的欄位 (前端需要傳入)
    p_sub_category_id INT,
    p_user_location_id BIGINT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),  -- 【修改 2025-11-01】改用 VARCHAR(20)，原為 public.item_condition
    p_price INT,
    p_carbon_value NUMERIC DEFAULT NULL,  -- 【修改 2025-11-02】可選參數，允許 NULL
    p_image_urls TEXT[] DEFAULT NULL,      -- 【修改 2025-11-02】可選參數，允許 NULL
    p_tags TEXT[] DEFAULT NULL             -- 【修改 2025-11-02】可選參數，允許 NULL
)
RETURNS JSON -- 回傳新物品的 ID 和 Title
AS $$
DECLARE
    v_current_uid UUID := auth.uid(); -- (安全!) 自動獲取當前登入者 ID
    v_new_item items; -- 用於接收 INSERT 結果
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法刊登物品';
    END IF;

    -- 【新增 2025-11-01】2. 驗證 condition 值是否合法
    IF p_condition NOT IN ('全新', '近全新', '良好', '普通', '需修理') THEN
        RAISE EXCEPTION '無效的物品狀況: %。有效值為：全新、近全新、良好、普通、需修理', p_condition;
    END IF;

    -- 【新增 2025-11-01】3. 驗證 location 是否屬於當前使用者
    IF NOT EXISTS (
        SELECT 1 FROM public.locations
        WHERE id = p_user_location_id
          AND user_id = v_current_uid
    ) THEN
        RAISE EXCEPTION '無效的地點 ID 或該地點不屬於當前使用者';
    END IF;

    -- 4. 插入物品資料到 public.items 表
    INSERT INTO public.items (
        user_id, -- (安全!) 使用後端獲取的 ID，而非前端傳入
        sub_category_id,
        location_id,  -- 【修改 2025-11-01】原為 user_location_id，修正為 location_id
        title,
        description,
        condition,
        listing_status, -- 預設為 TRUE (上架中)
        price,
        carbon_value,
        image_urls,
        tags,
        created_at, -- 自動設為 NOW()
        updated_at -- 自動設為 NOW()
    )
    VALUES (
        v_current_uid,
        p_sub_category_id,
        p_user_location_id,
        p_title,
        p_description,
        p_condition,
        TRUE, -- 預設刊登狀態
        p_price,
        COALESCE(p_carbon_value, 0),           -- 【修改 2025-11-02】NULL 時預設為 0
        COALESCE(p_image_urls, ARRAY[]::TEXT[]), -- 【修改 2025-11-02】NULL 時預設為空陣列
        COALESCE(p_tags, ARRAY[]::TEXT[]),      -- 【修改 2025-11-02】NULL 時預設為空陣列
        NOW(),
        NOW()
    )
    RETURNING * INTO v_new_item; -- 將新插入的整筆資料存入變數

    -- 5. 回傳一個簡單的 DTO，包含新物品的 ID 和 Title
    RETURN json_build_object(
        'id', v_new_item.id,
        'title', v_new_item.title,
        'created_at', v_new_item.created_at  -- 【新增 2025-11-01】回傳建立時間
    );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- SECURITY DEFINER 允許函式內部安全地使用 auth.uid()

-- 【新增 2025-11-01】設定函數註解
COMMENT ON FUNCTION public.create_item(INT, BIGINT, TEXT, TEXT, VARCHAR, INT, NUMERIC, TEXT[], TEXT[])
IS '建立新物品（刊登）- 自動使用當前登入者的 user_id，並驗證 condition 值與 location 所有權';
