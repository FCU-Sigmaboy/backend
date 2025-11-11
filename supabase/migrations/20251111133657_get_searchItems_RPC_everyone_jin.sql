-- ####################################################################
-- ### 物品搜尋 (RPC) - 使用子查詢版本
-- ####################################################################

-- 沿用自 Migration 綜合更新
-- 核心變更:
--   舊版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
--   新版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location

-- 更新：任何人皆可搜尋物品 (支援未登入搜尋)
-- 策略：
--   我們必須修改 search_items 函式，使其能夠「優雅地」處理 v_current_uid 為 NULL 的情況。
--   移除 IF v_current_uid IS NULL THEN RAISE EXCEPTION 這道強制登入的檢查。
--   修改獲取 v_user_primary_location 的邏輯：僅在 v_current_uid 不為 NULL 時才去查詢。
--   修改所有依賴 v_current_uid 的子查詢（例如距離計算、favorited_at），讓它們在 v_current_uid 為 NULL 時自動回傳 NULL。
-- 這會讓您的 RPC 函式變得極度靈活：
--   訪客（未登入）：v_current_uid 為 NULL。函式會跳過所有個人化計算（距離、收藏），回傳 distance_km: null 和 favorited_at: null。
--   會員（已登入）：v_current_uid 有值。函式會正常執行所有計算，回傳 distance_km: 1.23 和 favorited_at: '...'。

-- 步驟 1: 刪除舊函式
DROP FUNCTION IF EXISTS public.search_items(INT, INT, INT, TEXT, UUID, INT, INT, TEXT, TEXT);

-- 步驟 2: 建立新函式 (支援未登入搜尋)
CREATE
OR
REPLACE FUNCTION public.search_items(p_distance_range_km INT DEFAULT NULL,
                                     p_main_category_id INT DEFAULT NULL,
                                     p_sub_category_id INT DEFAULT NULL,
                                     p_keyword TEXT DEFAULT NULL,
                                     p_user_id UUID DEFAULT NULL,
                                     p_page INT DEFAULT 1,
                                     p_size INT DEFAULT 20,
                                     p_sort_by TEXT DEFAULT 'created_at',
                                     p_sort_direction TEXT DEFAULT 'desc')
-- *** 修正：新增 favorited_at 欄位 ***
    RETURNS TABLE (item_id BIGINT,
                   title VARCHAR (50),
    image_url TEXT,
    price INT,
    distance_km NUMERIC,
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    favorited_at TIMESTAMPTZ, -- <<< *** 新增的欄位 ***
    "user" JSON
    -- debug_user_location_wkb TEXT, -- (我們保留除錯欄位)
    -- debug_item_location_wkb TEXT
    )
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
    DECLARE
    v_current_uid UUID := auth.uid(); -- 取得當前使用者 ID (未登入則為 NULL)
v_user_primary_location GEOGRAPHY(Point, 4326); -- (預設為 NULL)
v_offset INT;
BEGIN
    -- =============================================
    -- 0. 廢棄驗證使用者登入
    -- =============================================

    -- =============================================
    -- 1. 獲取買家位置 (僅在登入時)
    -- =============================================
    IF v_current_uid IS NOT NULL THEN
SELECT coordinates
INTO v_user_primary_location
FROM public.locations
WHERE user_id = v_current_uid
  AND is_primary = true
LIMIT 1;

IF v_user_primary_location IS NULL THEN
            RAISE NOTICE '使用者(%)已登入，但找不到主要地點，距離計算將不可用', v_current_uid;
END IF;
ELSE
        RAISE NOTICE '使用者未登入，距離計算將不可用';
END IF;

    -- =============================================
    -- 2. 計算分頁偏移量
    -- =============================================
v_offset := (p_page - 1) * p_size;

    -- =============================================
    -- 4. 根據排序方式執行查詢
    -- =============================================

    -- *** 核心變更: 使用 i.use_primary_location 來 JOIN 對應的賣家地點 ***
    -- 舊版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
    -- 新版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location


    -- (邏輯簡化：由於 IF/ELSIF 內的查詢主體幾乎完全相同，
    --  我們將 v_user_primary_location 作為參數傳遞給 CTE，
    --  並在外部動態 ORDER BY，以大幅減少程式碼重複)

    -- *** 注意：為了保持您原有的 IF/ELSIF 結構，我將繼續使用它，
    --    但請注意 v_user_primary_location 現在可能是 NULL ***

IF LOWER(p_sort_direction) = 'asc' THEN
        -- ========== ASC 排序 ==========
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            -- 按距離升序
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location  -- ✅ 新版：根據物品設定選擇地點
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY distance_km ASC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格升序
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price ASC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- 按創建時間升序
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.created_at ASC
LIMIT p_size OFFSET v_offset;
END IF;

ELSE
        -- ========== DESC 排序 ==========
        IF LOWER(p_sort_by) = 'distance' THEN
            -- 按距離降序
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY distance_km DESC NULLS LAST, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格降序
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
  AND (p_user_id IS NULL OR i.user_id = p_user_id)
  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
ORDER BY i.price DESC, i.created_at DESC
LIMIT p_size OFFSET v_offset;

ELSE
            -- 按創建時間降序（預設）
            RETURN QUERY
SELECT i.id                                                                                                     AS item_id,
       i.title,
       i.image_urls[1]                                                                                          AS image_url,
       i.price,
       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
             3)                                                                                                 AS distance_km,
       l.formatted_address,
       i.created_at,
       i.updated_at,
       (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id)                                         AS favorites_count,
       (SELECT f.created_at
        FROM public.favorites f
        WHERE f.item_id = i.id
          AND f.user_id = v_current_uid)                                                                        AS favorited_at,
       json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url',
                         u.profile_picture_url)                                                                 AS "user"
-- ST_AsText(v_user_primary_location)                                                                       AS debug_user_location_wkb,
-- ST_AsText(l.coordinates)                                                                                 AS debug_item_location_wkb
FROM public.items i
         LEFT JOIN public.users u ON i.user_id = u.id
         LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
         LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
WHERE i.listing_status = TRUE
  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND
                                       ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0) ::numeric,
                                             3) <= p_distance_range_km))
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

-- (索引保持不變)