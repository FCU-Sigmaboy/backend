-- ####################################################################
-- ### 更新物品 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.update_my_item(
    -- 必須傳入要更新的物品 ID
    p_item_id BIGINT,

    -- 所有 "可被更新" 的欄位 (使用 JSONB 方便傳遞部分更新)
    p_update_data JSONB -- e.g., { "title": "新標題", "price": 600, "tags": ["#新標籤"] }
)
RETURNS JSON -- 回傳更新後的物品資料
AS $$
DECLARE
v_current_uid UUID := auth.uid();
  v_updated_item items;
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法更新物品';
END IF;

  -- 2. 執行更新 (關鍵：WHERE 子句確保只能更新自己的物品)
UPDATE public.items
SET
    -- 使用 COALESCE 和 JSONB 操作符 '->>' 來安全地更新欄位
    -- 只有在 p_update_data 中存在的 key 才會被更新
    sub_category_id = COALESCE((p_update_data->>'sub_category_id')::INT, sub_category_id),
    user_location_id = COALESCE((p_update_data->>'user_location_id')::BIGINT, user_location_id),
    title = COALESCE(p_update_data->>'title', title),
    description = COALESCE(p_update_data->>'description', description),
    condition = COALESCE((p_update_data->>'condition')::public.item_condition, condition),
    listing_status = COALESCE((p_update_data->>'listing_status')::BOOLEAN, listing_status),
    price = COALESCE((p_update_data->>'price')::INT, price),
    carbon_value = COALESCE((p_update_data->>'carbon_value')::NUMERIC, carbon_value),
    -- JSONB 陣列更新需要特殊處理，確保傳入的是 JSON 陣列格式
    image_urls = CASE
                     WHEN p_update_data ? 'image_urls' THEN ARRAY(SELECT jsonb_array_elements_text(p_update_data->'image_urls'))
                     ELSE image_urls
        END,
    tags = CASE
               WHEN p_update_data ? 'tags' THEN ARRAY(SELECT jsonb_array_elements_text(p_update_data->'tags'))
               ELSE tags
        END,
    updated_at = NOW() -- 總是更新 updated_at
WHERE
    id = p_item_id
  AND user_id = v_current_uid -- *** 核心安全檢查 ***
    RETURNING * INTO v_updated_item; -- 將更新後的整筆資料存入變數

-- 3. 檢查是否有成功更新 (如果 ID 不對或不是自己的物品，v_updated_item 會是 NULL)
IF v_updated_item IS NULL THEN
     RAISE EXCEPTION '物品不存在或您沒有權限更新此物品 (ID: %)', p_item_id;
END IF;

  -- 4. 回傳更新後的物品資料 (轉換成 JSON)
RETURN row_to_json(v_updated_item);

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;