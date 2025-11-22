-- ####################################################################
-- ### 物品搜尋 (RPC) - 使用子查詢版本
-- ####################################################################

-- 步驟 1: 刪除舊函式
DROP FUNCTION IF EXISTS public.search_items(INT, INT, INT, TEXT, UUID, INT, INT, TEXT, TEXT);

-- 步驟 2: 建立新函式 (已新增 favorited_at 欄位)
CREATE OR REPLACE FUNCTION public.search_items(
    p_distance_range_km INT DEFAULT NULL,
    p_main_category_id INT DEFAULT NULL,
    p_sub_category_id INT DEFAULT NULL,
    p_keyword TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'created_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
-- *** 修正：新增 favorited_at 欄位 ***
              RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
              image_url TEXT,
              price INT,
              distance_km NUMERIC,
              formatted_address TEXT,
              created_at TIMESTAMPTZ,
              updated_at TIMESTAMPTZ,
              favorites_count BIGINT,
              favorited_at TIMESTAMPTZ, -- <<< *** 新增的欄位 ***
              "user" JSON,
              debug_user_location_wkb TEXT,
              debug_item_location_wkb TEXT
              )
              LANGUAGE plpgsql STABLE SECURITY DEFINER
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();  -- 取得當前使用者 ID
v_offset INT;  -- 分頁偏移量
BEGIN
    -- ========================================
    -- 1. 驗證使用者登入狀態
    -- ========================================
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法執行搜尋';
END IF;

    -- ========================================
    -- 2. 檢查使用者是否有主要地點（用於提示）
    -- ========================================
    -- 注意：這裡只是檢查，不儲存到變數
IF NOT EXISTS (
        SELECT 1
        FROM public.locations
        WHERE user_id = v_current_uid AND is_primary = true
    ) THEN
        RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
END IF;

    -- ========================================
    -- 3. 計算分頁偏移量
    -- ========================================
v_offset := (p_page - 1) * p_size;

    -- ========================================
    -- 4. 根據排序方式執行查詢
    -- ========================================
    -- 使用子查詢直接在 SELECT 中取得使用者位置

IF LOWER(p_sort_direction) = 'asc' THEN
        -- ============ ASC 排序 ============
        IF LOWER(p_sort_by) = 'distance' THEN
            -- 按距離升序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                          -- 子查詢取得使用者的主要地點座標
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位：使用者位置（子查詢）
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    -- Debug 欄位：物品位置
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  -- 距離篩選條件（使用子查詢）
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  -- 主分類篩選
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  -- 子分類篩選
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  -- 使用者篩選
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  -- 關鍵字搜尋（標題或標籤）
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
-- 按距離排序（使用子查詢）
ORDER BY (
             SELECT ROUND((ST_Distance(
                                   l.coordinates,
                                   (SELECT coordinates
                                    FROM public.locations
                                    WHERE user_id = v_current_uid
                                      AND is_primary = true
                                    LIMIT 1)
                           ) / 1000.0)::numeric, 3)
         ) ASC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格升序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price ASC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- 預設：按建立時間升序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at ASC
LIMIT p_size OFFSET v_offset;
END IF;

ELSE
        -- ============ DESC 排序（預設） ============
        IF LOWER(p_sort_by) = 'distance' THEN
            -- 按距離降序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
-- 按距離排序（使用子查詢）
ORDER BY (
             SELECT ROUND((ST_Distance(
                                   l.coordinates,
                                   (SELECT coordinates
                                    FROM public.locations
                                    WHERE user_id = v_current_uid
                                      AND is_primary = true
                                    LIMIT 1)
                           ) / 1000.0)::numeric, 3)
         ) DESC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格降序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price DESC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- 預設：按建立時間降序排序
            RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    -- 使用子查詢計算距離
    (
        SELECT ROUND((ST_Distance(
                              l.coordinates,
                              (SELECT coordinates
                               FROM public.locations
                               WHERE user_id = v_current_uid
                                 AND is_primary = true
                               LIMIT 1)
                      ) / 1000.0)::numeric, 3)
    ) AS distance_km,
    l.formatted_address,
    i.created_at,
    i.updated_at,
    -- 子查詢計算收藏數
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    -- *** 新增：獲取 "我" 的收藏時間 ***
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    -- 建立使用者資訊 JSON
    json_build_object(
            'id', i.user_id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
    ) AS "user",
    -- Debug 欄位
    (
        SELECT ST_AsText(coordinates)
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1
    ) AS debug_user_location_wkb,
    ST_AsText(l.coordinates) AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.location_id = l.id
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR
       (
           SELECT ROUND((ST_Distance(
                                 l.coordinates,
                                 (SELECT coordinates
                                  FROM public.locations
                                  WHERE user_id = v_current_uid
                                    AND is_primary = true
                                  LIMIT 1)
                         ) / 1000.0)::numeric, 3)
       ) <= p_distance_range_km)
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR
       (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at DESC
LIMIT p_size OFFSET v_offset;
END IF;
END IF;

END;
$$;

-- ========================================
-- 建立索引以提升效能
-- ========================================
-- 為標籤欄位建立 GIN 索引，加速標籤搜尋
CREATE INDEX IF NOT EXISTS idx_items_tags ON public.items USING GIN (tags);

-- 為地理位置欄位建立 GIST 索引，加速距離計算
CREATE INDEX IF NOT EXISTS idx_locations_coordinates ON public.locations USING GIST (coordinates);

-- 為常用的篩選欄位建立索引
CREATE INDEX IF NOT EXISTS idx_items_listing_status ON public.items (listing_status);
CREATE INDEX IF NOT EXISTS idx_items_user_id ON public.items (user_id);
CREATE INDEX IF NOT EXISTS idx_items_sub_category_id ON public.items (sub_category_id);

-- 為 locations 的查詢條件建立複合索引（重要！）
CREATE INDEX IF NOT EXISTS idx_locations_user_primary
    ON public.locations (user_id, is_primary)
    WHERE is_primary = true;