-- =============================================
-- Migration: 更新 search_items 和 get_item_details_with_location RPC
-- 日期: 2025-11-08
-- 說明:
--   1. 更新 search_items 函數，使用 items.use_primary_location 來 JOIN 正確的地點
--   2. 更新 get_item_details_with_location 函數，同樣使用 use_primary_location
--   3. 確保距離計算使用賣家物品設定的地點（主要或次要）
--   4. 買家位置仍使用主要地點
--
-- 核心變更:
--   舊版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
--   新版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location
--
-- 設計理念:
--   - 賣家地點：根據物品的 use_primary_location 欄位動態選擇
--   - 買家地點：固定使用主要地點（用於計算距離）
--   - 距離計算：買家主要地點 ↔ 賣家物品地點
-- =============================================

BEGIN;

-- =============================================
-- 1. 更新 search_items 函數
-- =============================================

DROP FUNCTION IF EXISTS public.search_items(INT, INT, INT, TEXT, UUID, INT, INT, TEXT, TEXT);

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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_user_primary_location GEOGRAPHY(Point, 4326);
    v_offset INT;
BEGIN
    -- =============================================
    -- 1. 驗證使用者已登入
    -- =============================================
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法執行搜尋';
    END IF;

    -- =============================================
    -- 2. 獲取買家的主要地點（用於計算距離）
    -- =============================================
    SELECT coordinates INTO v_user_primary_location
    FROM public.locations
    WHERE user_id = v_current_uid
      AND is_primary = true
    LIMIT 1;

    IF v_user_primary_location IS NULL THEN
        RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
    END IF;

    -- =============================================
    -- 3. 計算分頁偏移量
    -- =============================================
    v_offset := (p_page - 1) * p_size;

    -- =============================================
    -- 4. 執行查詢（根據排序條件）
    -- =============================================

    -- *** 核心變更: 使用 i.use_primary_location 來 JOIN 對應的賣家地點 ***
    -- 舊版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
    -- 新版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location

    IF LOWER(p_sort_direction) = 'asc' THEN
        -- ========== ASC 排序 ==========

        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            -- 按距離升序
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版：根據物品設定選擇地點
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY distance_km ASC NULLS LAST, i.created_at DESC
            LIMIT p_size OFFSET v_offset;

        ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格升序
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY i.price ASC, i.created_at DESC
            LIMIT p_size OFFSET v_offset;

        ELSE
            -- 按創建時間升序
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY i.created_at ASC
            LIMIT p_size OFFSET v_offset;
        END IF;

    ELSE
        -- ========== DESC 排序 ==========

        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            -- 按距離降序
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY distance_km DESC NULLS LAST, i.created_at DESC
            LIMIT p_size OFFSET v_offset;

        ELSIF LOWER(p_sort_by) = 'price' THEN
            -- 按價格降序
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY i.price DESC, i.created_at DESC
            LIMIT p_size OFFSET v_offset;

        ELSE
            -- 按創建時間降序（預設）
            RETURN QUERY
            SELECT
                i.id AS item_id,
                i.title,
                i.image_urls[1] AS image_url,
                i.price,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                l.formatted_address,
                i.created_at,
                i.updated_at,
                (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                json_build_object(
                    'id', i.user_id,
                    'nickname', u.nickname,
                    'profile_picture_url', u.profile_picture_url
                ) AS "user"
            FROM public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.locations l
                ON i.user_id = l.user_id
                AND l.is_primary = i.use_primary_location  -- ✅ 新版
            WHERE i.listing_status = TRUE
              AND (p_distance_range_km IS NULL OR (
                  v_user_primary_location IS NOT NULL
                  AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km
              ))
              AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
              AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
              AND (p_user_id IS NULL OR i.user_id = p_user_id)
              AND (p_keyword IS NULL OR (
                  i.title ILIKE '%' || p_keyword || '%'
                  OR i.tags @> ARRAY[p_keyword]
              ))
            ORDER BY i.created_at DESC
            LIMIT p_size OFFSET v_offset;
        END IF;
    END IF;

END;
$$;

COMMENT ON FUNCTION public.search_items IS
'搜尋物品 v7.0 - 支援 use_primary_location：
- 賣家地點：根據 items.use_primary_location 動態選擇主要或次要地點
- 買家地點：固定使用買家的主要地點
- 距離計算：買家主要地點 ↔ 賣家物品地點（主要或次要）
- 支援按距離、價格、創建時間排序
- 支援關鍵字搜尋、分類篩選、距離篩選';

DO $$
BEGIN
    RAISE NOTICE '✓ 已更新 search_items 函數支援 use_primary_location';
END $$;

-- =============================================
-- 2. 更新 get_item_details_with_location 函數
-- =============================================

-- 查找現有函數的完整簽名
DROP FUNCTION IF EXISTS public.get_item_details_with_location(BIGINT);

CREATE OR REPLACE FUNCTION public.get_item_details_with_location(
    p_item_id BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_is_owner BOOLEAN := FALSE;
    v_user_primary_location GEOGRAPHY(Point, 4326);
    v_result JSON;
    v_seller_id UUID;
    v_item_use_primary_location BOOLEAN;
    v_listing_status BOOLEAN;
BEGIN
    -- =============================================
    -- 1. 檢查物品是否存在且已上架
    -- =============================================
    SELECT u.id, i.use_primary_location, i.listing_status
    INTO v_seller_id, v_item_use_primary_location, v_listing_status
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    WHERE i.id = p_item_id;

    IF v_seller_id IS NULL THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    IF v_listing_status IS NOT TRUE THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- =============================================
    -- 2. 檢查是否為物品擁有者
    -- =============================================
    IF v_current_uid IS NOT NULL THEN
        SELECT (i.user_id = v_current_uid) INTO v_is_owner
        FROM public.items i
        WHERE i.id = p_item_id;
    END IF;

    -- =============================================
    -- 3. 驗證賣家是否有對應的地點（根據 use_primary_location）
    -- =============================================
    IF NOT EXISTS (
        SELECT 1 FROM public.locations
        WHERE user_id = v_seller_id
          AND is_primary = v_item_use_primary_location
    ) THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'LOCATION_NOT_FOUND',
            'message', CASE
                WHEN v_item_use_primary_location = true THEN '賣家未設定主要地點'
                ELSE '賣家未設定次要地點'
            END,
            'item_id', p_item_id
        );
    END IF;

    -- =============================================
    -- 4. 獲取買家的主要地點（僅已登入且非擁有者）
    -- =============================================
    IF v_current_uid IS NOT NULL AND NOT v_is_owner THEN
        SELECT coordinates INTO v_user_primary_location
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = true
        LIMIT 1;
    END IF;

    -- =============================================
    -- 4. 查詢物品詳情（使用 use_primary_location）
    -- =============================================

    -- *** 核心變更: 使用 i.use_primary_location 來 JOIN 賣家地點 ***
    SELECT json_build_object(
        -- 物品基本資訊
        'id', i.id,
        'title', i.title,
        'description', i.description,
        'condition', i.condition,
        'listing_status', i.listing_status,
        'price', i.price,
        'carbon_value', i.carbon_value,
        'image_urls', i.image_urls,
        'tags', i.tags,
        'created_at', i.created_at,
        'updated_at', i.updated_at,
        'use_primary_location', i.use_primary_location,  -- ✅ 新增：顯示使用哪種地點

        -- 距離資訊（僅已登入且非擁有者可見）
        'distance_km', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            WHEN v_user_primary_location IS NULL THEN NULL
            ELSE ROUND((ST_Distance(seller_loc.coordinates, v_user_primary_location) / 1000.0)::numeric, 3)
        END,

        -- 互動狀態
        'is_favorited', CASE
            WHEN v_current_uid IS NULL THEN NULL
            ELSE EXISTS (
                SELECT 1 FROM public.favorites
                WHERE user_id = v_current_uid AND item_id = i.id
            )
        END,
        'is_owner', v_is_owner,

        -- 賣家地點資訊
        'location', json_build_object(
            'id', seller_loc.id,
            'formatted_address', seller_loc.formatted_address,
            'type', seller_loc.type,
            'is_primary', seller_loc.is_primary,  -- ✅ 新增：顯示是主要還是次要地點
            'coordinates', CASE
                WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
                ELSE ST_AsGeoJSON(seller_loc.coordinates)::json
            END
        ),

        -- 賣家資訊
        'user', json_build_object(
            'id', u.id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url,
            'avg_rating', u.avg_rating
        ),

        -- 分類資訊
        'category', json_build_object(
            'sub_category_id', sc.id,
            'sub_category_name', sc.name,
            'main_category_id', mc.id,
            'main_category_name', mc.name,
            'main_category_icon', mc.icon,
            'main_category_color', mc.color
        ),

        -- 買家位置資訊（僅已登入且非擁有者可見）
        'user_location', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            ELSE json_build_object(
                'has_location', (v_user_primary_location IS NOT NULL),
                'source', CASE
                    WHEN v_user_primary_location IS NOT NULL THEN 'database_primary'
                    ELSE 'none'
                END,
                'coordinates', CASE
                    WHEN v_user_primary_location IS NOT NULL
                    THEN ST_AsGeoJSON(v_user_primary_location)::json
                    ELSE NULL
                END,
                'message', CASE
                    WHEN v_user_primary_location IS NOT NULL
                    THEN '使用資料庫主要地點'
                    ELSE '未設定地點'
                END
            )
        END

    ) INTO v_result
    FROM public.items i
    INNER JOIN public.users u ON i.user_id = u.id
    LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
    LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
    INNER JOIN public.locations seller_loc
        ON i.user_id = seller_loc.user_id
        AND seller_loc.is_primary = i.use_primary_location
    WHERE i.id = p_item_id;

    -- =============================================
    -- 5. 檢查查詢結果
    -- =============================================
    IF v_result IS NULL THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '無法獲取物品詳情',
            'item_id', p_item_id
        );
    END IF;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'INTERNAL_ERROR',
            'message', SQLERRM
        );
END;
$$;

COMMENT ON FUNCTION public.get_item_details_with_location IS
'獲取物品詳情 v4.0 - 支援 use_primary_location：
- 賣家地點：根據 items.use_primary_location 動態選擇主要或次要地點
- 買家地點：使用買家的主要地點
- 距離計算：買家主要地點 ↔ 賣家物品地點（主要或次要）
- 隱私保護：未登入和擁有者不顯示距離與座標
- 回傳物品完整資訊、賣家資訊、分類資訊、距離資訊';

DO $$
BEGIN
    RAISE NOTICE '✓ 已更新 get_item_details_with_location 函數支援 use_primary_location';
END $$;

COMMIT;

-- =============================================
-- Migration 完成通知
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251108000003';
    RAISE NOTICE '====================================';
    RAISE NOTICE '✓ 已更新 search_items 函數（v7.0）';
    RAISE NOTICE '✓ 已更新 get_item_details_with_location 函數（v4.0）';
    RAISE NOTICE '';
    RAISE NOTICE '核心變更：';
    RAISE NOTICE '  舊版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true';
    RAISE NOTICE '  新版: LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = i.use_primary_location';
    RAISE NOTICE '';
    RAISE NOTICE '距離計算邏輯：';
    RAISE NOTICE '  - 買家位置：固定使用主要地點';
    RAISE NOTICE '  - 賣家位置：根據物品的 use_primary_location 選擇';
    RAISE NOTICE '  - 如果 use_primary_location = true → 使用主要地點';
    RAISE NOTICE '  - 如果 use_primary_location = false → 使用次要地點';
    RAISE NOTICE '';
    RAISE NOTICE '測試建議：';
    RAISE NOTICE '  1. 測試搜尋功能（距離計算）';
    RAISE NOTICE '  2. 測試物品詳情（距離計算）';
    RAISE NOTICE '  3. 測試不同 use_primary_location 值的物品';
    RAISE NOTICE '====================================';
    RAISE NOTICE '';
END $$;
