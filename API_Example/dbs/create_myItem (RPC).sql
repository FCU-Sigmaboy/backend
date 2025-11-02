-- ####################################################################
-- ### 刊登物品 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.create_item(
    -- Item 表的欄位 (前端需要傳入)
    p_sub_category_id INT,
    p_user_location_id BIGINT,
    p_title TEXT,
    p_description TEXT,
    p_condition public.item_condition,
    p_price INT,
    p_carbon_value NUMERIC,
    p_image_urls TEXT[], -- 圖片 URL 陣列
    p_tags TEXT[] -- 標籤名稱陣列
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

  -- 2. 插入物品資料到 public.items 表
INSERT INTO public.items (
    user_id, -- (安全!) 使用後端獲取的 ID，而非前端傳入
    sub_category_id,
    user_location_id,
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
           p_carbon_value,
           p_image_urls,
           p_tags,
           NOW(),
           NOW()
       )
    RETURNING * INTO v_new_item; -- 將新插入的整筆資料存入變數

-- 3. 回傳一個簡單的 DTO，包含新物品的 ID 和 Title
RETURN json_build_object('id', v_new_item.id, 'title', v_new_item.title);

END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- SECURITY DEFINER 允許函式內部安全地使用 auth.uid()