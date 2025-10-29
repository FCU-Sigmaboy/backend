-- ####################################################################
-- ### 物品搜尋 (RPC)
-- ####################################################################

-- *** 已更新為使用使用者主要地點計算距離 ***
-- *** 使用 IF/ELSIF 處理排序，已修正 JOIN ***


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
-- *** 已加入 favorites_count ***
              RETURNS TABLE (
    item_id BIGINT,
    title TEXT,
    image_url TEXT,
    price INT,
    distance_km NUMERIC,
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    "user" JSON
)
-- *** 加入 STABLE ***
              LANGUAGE plpgsql STABLE -- Indicates the function cannot modify the database and always returns the same results for the same arguments within a single transaction.
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_user_primary_location GEOGRAPHY(Point,4326);
v_offset INT;
BEGIN
    -- 1. 安全檢查 & 獲取主要地點
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法執行搜尋';
END IF;

SELECT coordinates INTO v_user_primary_location
FROM public.locations
WHERE user_id = v_current_uid AND is_primary = true
LIMIT 1;

IF v_user_primary_location IS NULL THEN
        RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
END IF;

    -- 2. 計算 offset
v_offset := (p_page - 1) * p_size;

    -- 3. 根據排序方向和欄位執行不同的查詢 (避免動態 SQL)
    --    使用 CTE 預先計算距離和 JOIN
    --    使用 LEFT JOIN 子查詢計算 favorites_count

IF LOWER(p_sort_direction) = 'asc' THEN
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.distance_km ASC NULLS LAST, iwd.created_at DESC LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.price ASC, iwd.created_at DESC LIMIT p_size OFFSET v_offset;

ELSE -- Default to created_at ASC
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.created_at ASC LIMIT p_size OFFSET v_offset;
END IF;

ELSE -- DESC (Default)
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.distance_km DESC NULLS LAST, iwd.created_at DESC LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.price DESC, iwd.created_at DESC LIMIT p_size OFFSET v_offset;

ELSE -- Default to created_at DESC
            RETURN QUERY
                WITH items_with_distance AS (
                    SELECT
                        i.*, u.nickname, u.profile_picture_url, sc.main_category_id, l.formatted_address, l.coordinates AS item_coordinates, -- *** 獲取物品座標 ***
                        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km -- *** 使用 l.coordinates 計算 ***
                    FROM public.items i
                             LEFT JOIN public.users u ON i.user_id = u.id
                             LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                             LEFT JOIN public.locations l ON i.location_id = l.id -- *** 確保 JOIN locations ***
                    WHERE i.listing_status = TRUE
                )
SELECT iwd.id, iwd.title, iwd.image_urls[1], iwd.price, iwd.distance_km, iwd.formatted_address, iwd.created_at, iwd.updated_at,
       COALESCE(fav.count, 0), json_build_object('id', iwd.user_id, 'nickname', iwd.nickname, 'profile_picture_url', iwd.profile_picture_url)
FROM items_with_distance iwd
         LEFT JOIN (SELECT item_id, count(*) FROM public.favorites GROUP BY item_id) fav ON iwd.id = fav.item_id
WHERE (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND iwd.distance_km <= p_distance_range_km)) AND (p_main_category_id IS NULL OR iwd.main_category_id = p_main_category_id) AND (p_sub_category_id IS NULL OR iwd.sub_category_id = p_sub_category_id) AND (p_user_id IS NULL OR iwd.user_id = p_user_id) AND (p_keyword IS NULL OR (iwd.title ILIKE '%' || p_keyword || '%' OR iwd.tags @> ARRAY[p_keyword]))
ORDER BY iwd.created_at DESC LIMIT p_size OFFSET v_offset;
END IF;
END IF;

END;
$$;

-- *** 重要：為 items.tags 建立 GIN 索引以加速標籤搜尋 ***
CREATE INDEX IF NOT EXISTS idx_items_tags ON public.items USING GIN (tags);

-- (其他 RLS 政策和函式保持不變)
-- ... existing policies and other functions ...

