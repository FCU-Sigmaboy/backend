-- 整合 use_primary_location + approximate_location + main_category_id + sub_category_id + rating_count + avg_rating)
-- 可接受經緯度版

-- =============================================
-- 1. 先不刪除舊函式 (參數簽名改變)，兩種都留
-- =============================================
-- DROP FUNCTION IF EXISTS public.search_items(INT, INT, INT, TEXT, UUID, INT, INT, TEXT, TEXT);

-- =============================================
-- 2. 建立可接受經緯度版函式
-- =============================================
CREATE OR REPLACE FUNCTION public.search_items_tudeVer(
    -- *** 新增：優先使用的前端座標 ***
    p_user_latitude DOUBLE PRECISION DEFAULT NULL,
    p_user_longitude DOUBLE PRECISION DEFAULT NULL,

    -- 原有參數
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
              main_category_id INT,
              sub_category_id INT
              )
              LANGUAGE plpgsql STABLE SECURITY DEFINER
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_reference_location GEOGRAPHY(Point, 4326); -- 最終用來計算距離的參考點
v_offset INT;
BEGIN
    -- =============================================
    -- 1. 決定參考座標 (優先權邏輯)
    -- =============================================

    -- 情況 A: 前端有傳入座標 -> 直接使用
    IF p_user_latitude IS NOT NULL AND p_user_longitude IS NOT NULL THEN
        v_reference_location := ST_SetSRID(ST_MakePoint(p_user_longitude, p_user_latitude), 4326)::geography;

-- 情況 B: 前端沒傳，但使用者已登入 -> 查資料庫的主要地點
ELSIF v_current_uid IS NOT NULL THEN
SELECT coordinates INTO v_reference_location
FROM public.locations
WHERE user_id = v_current_uid AND is_primary = true
LIMIT 1;
END IF;

    -- 如果兩者都沒有，v_reference_location 會是 NULL，距離計算將回傳 NULL (這是允許的)

    -- =============================================
    -- 2. 計算分頁
    -- =============================================
v_offset := (p_page - 1) * p_size;

    -- =============================================
    -- 3. 執行查詢 (將 v_user_primary_location 替換為 v_reference_location)
    -- =============================================

IF LOWER(p_sort_direction) = 'asc' THEN
        -- ========== ASC 排序 ==========
        
        -- 如果要按距離排序，必須有參考座標
        IF LOWER(p_sort_by) = 'distance' AND v_reference_location IS NOT NULL THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object(
            'latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3),
            'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3),
            'accuracy_m', 150
    ) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY distance_km ASC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            -- (Price ASC)
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object('latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3), 'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3), 'accuracy_m', 150) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price ASC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- (Created At ASC - Default)
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object('latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3), 'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3), 'accuracy_m', 150) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at ASC
LIMIT p_size OFFSET v_offset;
END IF;

ELSE
        -- ========== DESC 排序 (Default) ==========
        
        IF LOWER(p_sort_by) = 'distance' AND v_reference_location IS NOT NULL THEN
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object('latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3), 'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3), 'accuracy_m', 150) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
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
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object('latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3), 'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3), 'accuracy_m', 150) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price DESC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- (Created At DESC - Default)
            RETURN QUERY
SELECT
    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
    ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) AS distance_km,
    l.formatted_address, i.created_at, i.updated_at,
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
    (SELECT f.created_at FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid) AS favorited_at,
    jsonb_build_object('latitude', ROUND(ST_Y(l.coordinates::geometry)::numeric, 3), 'longitude', ROUND(ST_X(l.coordinates::geometry)::numeric, 3), 'accuracy_m', 150) AS approximate_location,
    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url, 'avg_rating', u.avg_rating, 'rating_count', (SELECT COUNT(*) FROM public.ratings r WHERE r.reviewed_user_id = u.id)) AS "user",
    sc.main_category_id, i.sub_category_id
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_reference_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_reference_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
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