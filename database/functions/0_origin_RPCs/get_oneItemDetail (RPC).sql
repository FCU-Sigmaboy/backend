-- ####################################################################
-- ### 單一物品詳情 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_item_details(
    p_item_id BIGINT, -- (必填) 要查詢的物品 ID
    -- (必填) 當前使用者的位置，用來計算距離
    p_user_latitude DOUBLE PRECISION,
    p_user_longitude DOUBLE PRECISION
)
-- *** 回傳 DTO 包含所有詳情欄位 ***
RETURNS JSON -- 回傳單一 JSON 物件
AS $$
DECLARE
v_user_location GEOGRAPHY;
  v_item_details JSON;
BEGIN
  -- 1. 建立使用者當前位置
  v_user_location := ST_MakePoint(p_user_longitude, p_user_latitude)::geography;

  -- 2. 查詢物品詳情，並組裝成 JSON
SELECT
    json_build_object(
            'id', i.id,
            'title', i.title,
            'description', i.description,
            'condition', i.condition,
            'listing_status', i.listing_status,
            'price', i.price,
            'carbon_value', i.carbon_value,
            'image_urls', i.image_urls, -- *** 完整圖片陣列 ***
            'tags', i.tags,           -- *** 完整標籤陣列 ***
            'created_at', i.created_at,
            'updated_at', i.updated_at,

        -- 計算距離
            'distance_km', ROUND((ST_Distance(i.coordinates, v_user_location) / 1000.0)::numeric, 3),

        -- 計算收藏次數
            'favorites_count', (SELECT COUNT(*) FROM public.favorites f WHERE f.item_id = i.id),

        -- 物品地點資訊
            'location', json_build_object(
                    'id', l.id,
                    'formatted_address', l.formatted_address,
                    'coordinates', ST_AsGeoJSON(i.coordinates) -- 將 GEOGRAPHY 轉為 GeoJSON
                        ),

        -- 物品擁有者資訊 (巢狀)
            'user', json_build_object(
                    'id', u.id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url,
                    'avg_rating', u.avg_rating
                    ),

        -- (可選) 分類資訊 (巢狀)
            'category', json_build_object(
                    'sub_category_id', sc.id,
                    'sub_category_name', sc.name,
                    'main_category_id', mc.id,
                    'main_category_name', mc.name
                        )
    )
INTO v_item_details -- 將查詢結果存入變數
FROM
    public.items i
        LEFT JOIN public.users u ON i.user_id = u.id
        LEFT JOIN public.locations l ON i.user_location_id = l.id
        LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
        LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
WHERE
    i.id = p_item_id
  -- AND i.deleted_at IS NULL -- (如果不需要邏輯刪除，移除此行)
  AND i.listing_status = TRUE; -- (通常詳情頁只顯示上架中的)

-- 3. 回傳查詢結果 (如果找不到物品，會回傳 NULL)
RETURN v_item_details;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;