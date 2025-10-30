-- ####################################################################
-- ### 物品搜尋 (RPC)
-- ####################################################################

-- *** 已更新為使用使用者主要地點計算距離 ***
-- *** 使用 IF/ELSIF 處理排序，已修正 JOIN ***
-- *** 修正 42702 歧義錯誤 ***

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
                      "user" JSON
                  )
    LANGUAGE plpgsql STABLE
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

    -- 3. 根據排序方向和欄位執行不同的查詢
    --    *** 修正：為 favorites 子查詢加上別名 'f' ***

    IF LOWER(p_sort_direction) = 'asc' THEN
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY distance_km ASC NULLS LAST, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.price ASC, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSE -- Default to created_at ASC
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.created_at ASC LIMIT p_size OFFSET v_offset;
        END IF;

    ELSE -- DESC (Default)
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY distance_km DESC NULLS LAST, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSIF LOWER(p_sort_by) = 'price' THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.price DESC, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSE -- Default to created_at DESC
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    -- *** 修正 42702 ***
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                         LEFT JOIN public.users u ON i.user_id = u.id
                         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                         LEFT JOIN public.locations l ON i.location_id = l.id
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.created_at DESC LIMIT p_size OFFSET v_offset;
        END IF;
    END IF;

END;
$$;

-- *** 重要：為 items.tags 建立 GIN 索引以加速標籤搜尋 ***
CREATE INDEX IF NOT EXISTS idx_items_tags ON public.items USING GIN (tags);

-- (其他 RLS 政策和函式保持不變)

