-- =============================================
-- Migration: 更新所有 RPC 函數使用 user_id 關聯 locations
-- 日期: 2025-11-07
-- 說明:
--   更新所有 RPC 函數，將 JOIN locations 的邏輯從
--   items.location_id 改為 items.user_id
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
    LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_user_primary_location GEOGRAPHY(Point,4326);
    v_offset INT;
BEGIN
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

    v_offset := (p_page - 1) * p_size;

    -- *** 核心變更: 使用 i.user_id JOIN locations 而非 i.location_id ***
    IF LOWER(p_sort_direction) = 'asc' THEN
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
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
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.price ASC, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSE
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.created_at ASC LIMIT p_size OFFSET v_offset;
        END IF;

    ELSE
        IF LOWER(p_sort_by) = 'distance' AND v_user_primary_location IS NOT NULL THEN
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
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
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
                WHERE i.listing_status = TRUE
                  AND (p_distance_range_km IS NULL OR (v_user_primary_location IS NOT NULL AND ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) <= p_distance_range_km))
                  AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
                  AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
                  AND (p_user_id IS NULL OR i.user_id = p_user_id)
                  AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
                ORDER BY i.price DESC, i.created_at DESC LIMIT p_size OFFSET v_offset;

        ELSE
            RETURN QUERY
                SELECT
                    i.id AS item_id, i.title, i.image_urls[1] AS image_url, i.price,
                    ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                    l.formatted_address, i.created_at, i.updated_at,
                    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count,
                    json_build_object('id', i.user_id, 'nickname', u.nickname, 'profile_picture_url', u.profile_picture_url) AS "user"
                FROM public.items i
                LEFT JOIN public.users u ON i.user_id = u.id
                LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
                LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
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

COMMENT ON FUNCTION public.search_items IS
'搜尋物品 (已更新使用 user_id 關聯 locations) - v6.0';

-- =============================================
-- 2. 更新 get_my_favorite_items 函數
-- =============================================

DROP FUNCTION IF EXISTS public.get_my_favorite_items(INT, INT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_my_favorite_items(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'favorited_at',
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
        "user" JSON
    )
    LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_user_primary_location GEOGRAPHY(Point,4326);
    v_offset INT;
    v_sort_column TEXT;
    v_sort_dir TEXT;
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    SELECT coordinates INTO v_user_primary_location
    FROM public.locations
    WHERE user_id = v_current_uid AND is_primary = true
    LIMIT 1;

    IF v_user_primary_location IS NULL THEN
        RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
    END IF;

    v_offset := (p_page - 1) * p_size;

    v_sort_dir := CASE WHEN p_sort_direction = 'asc' THEN 'ASC' ELSE 'DESC' END;
    v_sort_column := CASE
        WHEN p_sort_by = 'distance' AND v_user_primary_location IS NOT NULL THEN 'distance_km'
        WHEN p_sort_by = 'created_at' THEN 'i.created_at'
        WHEN p_sort_by = 'price' THEN 'i.price'
        WHEN p_sort_by = 'favorited_at' THEN 'fav.created_at'
        ELSE 'fav.created_at'
    END;

    -- *** 核心變更: 使用 i.user_id JOIN locations 而非 i.location_id ***
    RETURN QUERY
        WITH favorite_items AS (
            SELECT
                fav.created_at AS favorited_at,
                i.*,
                u.nickname,
                u.profile_picture_url,
                l.formatted_address,
                ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
                (SELECT COUNT(*) FROM public.favorites f_count WHERE f_count.item_id = i.id) AS favorites_count
            FROM
                public.favorites fav
            JOIN public.items i ON fav.item_id = i.id
            LEFT JOIN public.users u ON i.user_id = u.id
            LEFT JOIN public.locations l ON i.user_id = l.user_id AND l.is_primary = true
            WHERE
                fav.user_id = v_current_uid
                AND i.listing_status = TRUE
        )
        SELECT
            fi.id AS item_id,
            fi.title,
            fi.image_urls[1] AS image_url,
            fi.price,
            fi.distance_km,
            fi.formatted_address,
            fi.created_at,
            fi.updated_at,
            fi.favorites_count,
            fi.favorited_at,
            json_build_object(
                'id', fi.user_id,
                'nickname', fi.nickname,
                'profile_picture_url', fi.profile_picture_url
            ) AS "user"
        FROM favorite_items fi
        ORDER BY
            v_sort_column || ' ' || v_sort_dir || ' NULLS LAST'
        LIMIT p_size
        OFFSET v_offset;

END;
$$;

COMMENT ON FUNCTION public.get_my_favorite_items IS
'取得我的收藏物品 (已更新使用 user_id 關聯 locations) - v2.0';

-- =============================================
-- 3. 更新 get_item_details_with_location 函數
-- =============================================

DROP FUNCTION IF EXISTS public.get_item_details_with_location(BIGINT);

CREATE OR REPLACE FUNCTION public.get_item_details_with_location(
    p_item_id BIGINT
)
    RETURNS JSONB
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_current_uid UUID;
    v_item_details JSONB;
BEGIN
    IF p_item_id IS NULL OR p_item_id <= 0 THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INVALID_PARAMETER',
            'message', '無效的物品 ID',
            'item_id', p_item_id
        );
    END IF;

    v_current_uid := auth.uid();

    -- *** 核心變更: 使用 i.user_id JOIN locations 而非 i.location_id ***
    WITH
    user_location AS (
        SELECT
            coordinates,
            CASE
                WHEN is_primary THEN 'database_primary'
                ELSE 'database_fallback'
            END as location_source
        FROM public.locations
        WHERE user_id = v_current_uid
          AND v_current_uid IS NOT NULL
        ORDER BY
            is_primary DESC NULLS LAST,
            created_at
        LIMIT 1
    ),
    item_data AS (
        SELECT
            i.id,
            i.title,
            i.description,
            i.condition,
            i.listing_status,
            i.price,
            i.carbon_value,
            i.image_urls,
            i.tags,
            i.created_at,
            i.updated_at,
            i.user_id as owner_id,
            u.id as seller_id,
            u.nickname as seller_nickname,
            u.profile_picture_url as seller_avatar,
            u.avg_rating as seller_rating,
            seller_loc.id as location_id,
            seller_loc.formatted_address as location_address,
            seller_loc.type as location_type,
            seller_loc.coordinates as seller_coordinates,
            sc.id as sub_category_id,
            sc.name as sub_category_name,
            mc.id as main_category_id,
            mc.name as main_category_name,
            mc.icon as main_category_icon,
            mc.color as main_category_color,
            (fav.item_id IS NOT NULL) as is_favorited,
            ul.coordinates as user_coordinates,
            ul.location_source as user_location_source
        FROM public.items i
        INNER JOIN public.users u ON i.user_id = u.id
        LEFT JOIN public.locations seller_loc ON i.user_id = seller_loc.user_id AND seller_loc.is_primary = true
        LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
        LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
        LEFT JOIN public.favorites fav ON fav.item_id = i.id AND fav.user_id = v_current_uid
        LEFT JOIN LATERAL (SELECT * FROM user_location) ul ON true
        WHERE i.id = p_item_id
          AND i.listing_status = true
    )
    SELECT
        jsonb_build_object(
            'id', id,
            'title', title,
            'description', description,
            'condition', condition,
            'listing_status', listing_status,
            'price', price,
            'carbon_value', carbon_value,
            'image_urls', image_urls,
            'tags', tags,
            'created_at', created_at,
            'updated_at', updated_at,
            'distance_km', CASE
                WHEN v_current_uid IS NOT NULL
                    AND v_current_uid != owner_id
                    AND seller_coordinates IS NOT NULL THEN
                    ROUND((ST_Distance(seller_coordinates, user_coordinates) / 1000.0)::numeric, 3)
            END,
            'is_favorited', is_favorited,
            'is_owner', CASE
                WHEN v_current_uid IS NOT NULL THEN (owner_id = v_current_uid)
                ELSE false
            END,
            'location', jsonb_build_object(
                'id', location_id,
                'formatted_address', location_address,
                'type', location_type,
                'coordinates', CASE
                    WHEN v_current_uid IS NOT NULL
                        AND v_current_uid != owner_id
                        AND seller_coordinates IS NOT NULL THEN
                        ST_AsGeoJSON(seller_coordinates)::jsonb
                END
            ),
            'user', jsonb_build_object(
                'id', seller_id,
                'nickname', seller_nickname,
                'profile_picture_url', seller_avatar,
                'avg_rating', seller_rating
            ),
            'category', jsonb_build_object(
                'sub_category_id', sub_category_id,
                'sub_category_name', sub_category_name,
                'main_category_id', main_category_id,
                'main_category_name', main_category_name,
                'main_category_icon', main_category_icon,
                'main_category_color', main_category_color
            ),
            'user_location', CASE
                WHEN v_current_uid IS NOT NULL
                    AND v_current_uid != owner_id THEN
                    CASE
                        WHEN user_coordinates IS NOT NULL THEN
                            jsonb_build_object(
                                'has_location', true,
                                'source', user_location_source,
                                'coordinates', ST_AsGeoJSON(user_coordinates)::jsonb,
                                'message', CASE user_location_source
                                    WHEN 'database_primary' THEN '使用您的主要地點'
                                    WHEN 'database_fallback' THEN '使用您設定的地點'
                                    ELSE '位置來源未知'
                                END
                            )
                        ELSE
                            jsonb_build_object(
                                'has_location', false,
                                'source', 'none',
                                'message', '無法取得位置資訊，請在個人資料中設定地點'
                            )
                    END
            END
        )
    INTO v_item_details
    FROM item_data;

    IF v_item_details IS NULL THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    RETURN v_item_details;

EXCEPTION
    WHEN no_data_found THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'ITEM_NOT_FOUND',
            'message', '找不到指定的物品',
            'item_id', p_item_id
        );
    WHEN invalid_parameter_value THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INVALID_PARAMETER',
            'message', '參數格式錯誤',
            'item_id', p_item_id,
            'detail', SQLERRM
        );
    WHEN OTHERS THEN
        RAISE WARNING '查詢物品詳情時發生錯誤: % (item_id: %)', SQLERRM, p_item_id;
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INTERNAL_ERROR',
            'message', '查詢過程發生錯誤，請稍後再試',
            'item_id', p_item_id
        );
END;
$$;

COMMENT ON FUNCTION public.get_item_details_with_location(BIGINT) IS
'取得單一物品詳情 (已更新使用 user_id 關聯 locations) - v3.0';

COMMIT;

-- =============================================
-- 記錄 migration 完成
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '====================================';
    RAISE NOTICE 'Migration 完成: 20251107000002';
    RAISE NOTICE '已更新所有 RPC 函數使用 user_id 關聯';
    RAISE NOTICE '下一步: 更新 create_item 函數';
    RAISE NOTICE '====================================';
END $$;
