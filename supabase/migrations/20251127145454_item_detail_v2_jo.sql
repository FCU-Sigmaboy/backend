-- =============================================
-- v5.2.0 (2025-11-27)
-- 符合 Supabase 最佳實踐：使用 JSONB、添加 search_path、改進參數驗證和錯誤處理
-- =============================================

CREATE OR REPLACE FUNCTION public.get_item_details_with_location_v2(
    p_item_id bigint,
    p_user_lat double precision DEFAULT NULL,
    p_user_lng double precision DEFAULT NULL,
    p_use_secondary_location boolean DEFAULT FALSE
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_current_uid UUID;
    v_is_owner BOOLEAN := FALSE;
    v_user_location GEOGRAPHY(Point, 4326);
    v_user_location_source TEXT := 'none';
    v_user_location_message TEXT := '未設定地點';
    v_result JSONB;
    v_seller_id UUID;
    v_item_use_primary_location BOOLEAN;
    v_listing_status BOOLEAN;
BEGIN
    -- ========================================
    -- 步驟 1: 參數驗證
    -- ========================================
    IF p_item_id IS NULL OR p_item_id <= 0 THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'INVALID_PARAMETER',
            'message', '無效的物品 ID',
            'item_id', p_item_id
        );
    END IF;

    IF (p_user_lat IS NOT NULL AND p_user_lng IS NULL) OR
       (p_user_lat IS NULL AND p_user_lng IS NOT NULL) THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'INVALID_COORDINATES',
            'message', '經緯度參數必須同時提供或同時為空',
            'item_id', p_item_id
        );
    END IF;

    IF p_user_lat IS NOT NULL THEN
        IF p_user_lat < -90 OR p_user_lat > 90 THEN
            RETURN jsonb_build_object(
                'error', TRUE,
                'code', 'INVALID_COORDINATES',
                'message', '緯度必須在 -90 到 90 之間',
                'item_id', p_item_id
            );
        END IF;

        IF p_user_lng < -180 OR p_user_lng > 180 THEN
            RETURN jsonb_build_object(
                'error', TRUE,
                'code', 'INVALID_COORDINATES',
                'message', '經度必須在 -180 到 180 之間',
                'item_id', p_item_id
            );
        END IF;
    END IF;

    -- 取得當前用戶 ID
    v_current_uid := auth.uid();

    -- ========================================
    -- 步驟 2: 驗證物品存在性與取得基本資訊
    -- ========================================
    SELECT i.user_id, i.use_primary_location, i.listing_status
    INTO v_seller_id, v_item_use_primary_location, v_listing_status
    FROM items i
    WHERE i.id = p_item_id;

    IF v_seller_id IS NULL THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- ========================================
    -- 步驟 3: 判定查詢者身份
    -- ========================================
    IF v_current_uid IS NOT NULL THEN
        v_is_owner := (v_seller_id = v_current_uid);
    END IF;

    -- ========================================
    -- 步驟 4: 上架狀態驗證（非擁有者）
    -- ========================================
    IF v_is_owner IS NOT TRUE AND v_listing_status IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- ========================================
    -- 步驟 5: 驗證賣家的地點存在性（非擁有者）
    -- ========================================
    IF v_is_owner IS NOT TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM locations
            WHERE user_id = v_seller_id
              AND is_primary = v_item_use_primary_location
            LIMIT 1
        ) THEN
            RETURN jsonb_build_object(
                'error', TRUE,
                'code', 'LOCATION_NOT_FOUND',
                'message', CASE
                    WHEN v_item_use_primary_location = TRUE THEN '賣家未設定主要地點'
                    ELSE '賣家未設定次要地點'
                END,
                'item_id', p_item_id
            );
        END IF;
    END IF;

    -- ========================================
    -- 步驟 6: 取得買家位置（優化版）
    -- ========================================
    IF v_current_uid IS NOT NULL AND NOT v_is_owner THEN
        IF p_user_lat IS NOT NULL AND p_user_lng IS NOT NULL THEN
            -- 優先級 1: 使用前端傳入的當前位置
            v_user_location := ST_MakePoint(p_user_lng, p_user_lat)::geography;
            v_user_location_source := 'current_position';
            v_user_location_message := '使用您的當前位置';
        ELSE
            -- 優先級 2-3: 使用資料庫地點（單次查詢優化）
            SELECT
                coordinates,
                CASE WHEN is_primary THEN 'database_primary' ELSE 'database_secondary' END,
                CASE WHEN is_primary THEN '使用您的主要地點' ELSE '使用您的次要地點' END
            INTO
                v_user_location,
                v_user_location_source,
                v_user_location_message
            FROM (
                SELECT
                    coordinates,
                    is_primary,
                    ROW_NUMBER() OVER (
                        PARTITION BY is_primary
                        ORDER BY updated_at DESC
                    ) as rn
                FROM locations
                WHERE user_id = v_current_uid
                  AND (
                      (p_use_secondary_location = FALSE AND is_primary = TRUE) OR
                      (p_use_secondary_location = TRUE AND is_primary = FALSE) OR
                      (p_use_secondary_location = FALSE AND is_primary = FALSE)
                  )
            ) ranked_locations
            WHERE rn = 1
            ORDER BY
                CASE
                    WHEN p_use_secondary_location = TRUE AND is_primary = FALSE THEN 1
                    WHEN is_primary = TRUE THEN 2
                    ELSE 3
                END
            LIMIT 1;

            IF v_user_location IS NULL THEN
                v_user_location_source := 'none';
                v_user_location_message := CASE
                    WHEN p_use_secondary_location = TRUE THEN '未設定次要地點'
                    ELSE '未設定地點'
                END;
            END IF;
        END IF;
    END IF;

    -- ========================================
    -- 步驟 7: 構建完整 JSON 結果（優化版 - 使用 CTE）
    -- ========================================
    WITH cte_item_with_user AS (
        SELECT
            i.*,
            u.id as seller_id,
            u.nickname,
            u.profile_picture_url,
            u.avg_rating
        FROM items i
        INNER JOIN users u ON i.user_id = u.id
        WHERE i.id = p_item_id
    ),
    cte_categories AS (
        SELECT
            sc.id as sub_category_id,
            sc.name as sub_category_name,
            mc.id as main_category_id,
            mc.name as main_category_name,
            mc.icon as main_category_icon,
            mc.color as main_category_color
        FROM cte_item_with_user i
        LEFT JOIN sub_categories sc ON i.sub_category_id = sc.id
        LEFT JOIN main_categories mc ON sc.main_category_id = mc.id
    ),
    cte_seller_location AS (
        SELECT
            l.id,
            l.formatted_address,
            l.type,
            l.is_primary,
            l.coordinates
        FROM cte_item_with_user i
        LEFT JOIN locations l
            ON i.user_id = l.user_id
           AND l.is_primary = i.use_primary_location
    ),
    cte_favorite_status AS (
        SELECT EXISTS (
            SELECT 1 FROM favorites f
            INNER JOIN cte_item_with_user i ON f.item_id = i.id
            WHERE f.user_id = v_current_uid
        ) as is_favorited
    )
    SELECT jsonb_build_object(
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
        'use_primary_location', i.use_primary_location,

        'distance_km', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            WHEN v_user_location IS NULL THEN NULL
            WHEN l.coordinates IS NULL THEN NULL
            ELSE ROUND((ST_Distance(l.coordinates, v_user_location) / 1000.0)::numeric, 3)
        END,

        'is_favorited', CASE
            WHEN v_current_uid IS NULL THEN NULL
            ELSE f.is_favorited
        END,
        'is_owner', v_is_owner,

        'location', jsonb_build_object(
            'id', l.id,
            'formatted_address', l.formatted_address,
            'type', l.type,
            'is_primary', l.is_primary,
            'coordinates', CASE
                WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
                WHEN l.coordinates IS NOT NULL THEN ST_AsGeoJSON(l.coordinates)::jsonb
                ELSE NULL
            END
        ),

        'user', jsonb_build_object(
            'id', i.seller_id,
            'nickname', i.nickname,
            'profile_picture_url', i.profile_picture_url,
            'avg_rating', i.avg_rating
        ),

        'category', jsonb_build_object(
            'sub_category_id', c.sub_category_id,
            'sub_category_name', c.sub_category_name,
            'main_category_id', c.main_category_id,
            'main_category_name', c.main_category_name,
            'main_category_icon', c.main_category_icon,
            'main_category_color', c.main_category_color
        ),

        'user_location', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            ELSE jsonb_build_object(
                'has_location', (v_user_location IS NOT NULL),
                'source', v_user_location_source,
                'coordinates', CASE
                    WHEN v_user_location IS NOT NULL
                    THEN ST_AsGeoJSON(v_user_location)::jsonb
                    ELSE NULL
                END,
                'message', v_user_location_message
            )
        END
    ) INTO v_result
    FROM cte_item_with_user i
    CROSS JOIN cte_categories c
    LEFT JOIN cte_seller_location l ON TRUE
    CROSS JOIN cte_favorite_status f;

    IF v_result IS NULL THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '無法獲取物品詳情',
            'item_id', p_item_id
        );
    END IF;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'error', TRUE,
            'code', 'INTERNAL_ERROR',
            'message', '系統發生錯誤，請稍後再試'
        );
END;
$function$;

-- ========================================
-- 效能優化：建立索引
-- ========================================

-- 複合索引：優化次要地點查詢（包含排序）
CREATE INDEX IF NOT EXISTS idx_locations_user_primary_updated
ON locations(user_id, is_primary, updated_at DESC);

-- 覆蓋索引：優化收藏查詢
CREATE INDEX IF NOT EXISTS idx_favorites_item_user_covering
ON favorites(item_id, user_id);

-- 函數說明
COMMENT ON FUNCTION public.get_item_details_with_location_v2(BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN) IS
'v5.2.0 (2025-11-27) - 支援當前位置與次要地點切換（符合 Supabase 最佳實踐）
- 安全性: 添加 SET search_path = public 防止 schema 注入攻擊
- 效能: 使用 JSONB 替代 JSON，支持索引和更高效查詢
- 驗證: 改進參數驗證，包含 p_item_id <= 0 檢查
- 錯誤處理: 改進 EXCEPTION 處理，避免暴露內部錯誤訊息
- 位置優先級: 當前位置 > 主要地點 > 次要地點 > 無位置
- 效能優化: 使用 CTE 減少重複查詢，將 12 次查詢優化至 4-5 次
- 效能優化: 買家位置查詢合併為單次查詢（使用窗口函數）
- 效能優化: 新增複合索引和覆蓋索引
- 向後兼容: 不傳參數時行為與 v4.1.1 一致
- 僅註冊用戶可使用位置功能';
