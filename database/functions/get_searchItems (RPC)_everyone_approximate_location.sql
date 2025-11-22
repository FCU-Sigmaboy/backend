-- 整合 use_primary_location + approximate_location + main_category_id + sub_category_id)

-- =============================================
-- 1. 刪除舊函式（因為回傳結構將再次改變）
-- =============================================
-- (我們使用舊的參數簽名來刪除)
DROP FUNCTION IF EXISTS public.search_items(INT, INT, INT, TEXT, UUID, INT, INT, TEXT, TEXT);

-- =============================================
-- 2. 建立最終版函式
-- =============================================
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
-- *** 最終回傳結構：新增 main_category_id 和 sub_category_id ***
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
              favorited_at TIMESTAMPTZ,
              approximate_location JSONB,
              "user" JSON,
              main_category_id INT, -- <<< *** 新增的欄位 ***
              sub_category_id INT   -- <<< *** 新增的欄位 ***
              )
              LANGUAGE plpgsql STABLE SECURITY DEFINER
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_user_primary_location GEOGRAPHY(Point, 4326);
v_offset INT;
BEGIN
    -- 1. 獲取買家位置 (僅在登入時)
    IF v_current_uid IS NOT NULL THEN
SELECT coordinates INTO v_user_primary_location
FROM public.locations
WHERE user_id = v_current_uid AND is_primary = true
LIMIT 1;
IF v_user_primary_location IS NULL THEN
            RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
END IF;
ELSE
        RAISE NOTICE '使用者未登入，距離計算和收藏狀態將不可用';
END IF;

    -- 2. 計算 offset
v_offset := (p_page - 1) * p_size;

    -- 3. 根據排序方式執行查詢
IF LOWER(p_sort_direction) = 'asc' THEN
        -- ========== ASC 排序 ==========
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY distance_km ASC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address,
    i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price ASC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address,
    i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at ASC
LIMIT p_size OFFSET v_offset;
END IF;

ELSE
        -- ========== DESC 排序（預設） ==========
        IF LOWER(p_sort_by) = 'distance' THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address,
    i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY distance_km DESC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address,
    i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price DESC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- 按創建時間降序（預設）
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address,
    i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user",
    sc.main_category_id, -- *** 新增 ***
    i.sub_category_id    -- *** 新增 ***
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at DESC
LIMIT p_size OFFSET v_offset;
END IF;
END IF;

END;
$$;

-- (索引保持不變)-- (索引保持不變)