-- =============================================
-- Hotfix: get_item_details_with_location 函數優化
-- 日期: 2025-11-18
-- 版本: v4.1.1
-- 修復: 所有者無法查看已下架物品的缺陷
-- =============================================

CREATE OR REPLACE FUNCTION public.get_item_details_with_location(p_item_id bigint)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $function$
DECLARE
    v_current_uid UUID := auth.uid();
    v_is_owner BOOLEAN := FALSE;
    v_user_primary_location GEOGRAPHY(Point, 4326);
    v_result JSON;
    v_seller_id UUID;
    v_item_use_primary_location BOOLEAN;
    v_listing_status BOOLEAN;
BEGIN

    -- ========================================
    -- 步驟 1: 驗證物品存在性與取得基本資訊
    -- ========================================
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

    -- ========================================
    -- 步驟 2: 判定查詢者身份（擁有者 vs 非擁有者）
    -- ========================================
    IF v_current_uid IS NOT NULL THEN
        v_is_owner := (v_seller_id = v_current_uid);
    END IF;

    -- ========================================
    -- 步驟 3: 上架狀態驗證（非擁有者）
    -- ========================================
    IF v_is_owner IS NOT TRUE AND v_listing_status IS NOT TRUE THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- ========================================
    -- 步驟 4: 驗證賣家的地點存在性（非擁有者）
    -- ========================================
    -- 【關鍵修復】只針對非擁有者驗證地點
    -- 原因：擁有者可能正在編輯物品，地點可能尚未完全設定
    IF v_is_owner IS NOT TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.locations
            WHERE user_id = v_seller_id
              AND is_primary = v_item_use_primary_location
        ) THEN
            RETURN json_build_object(
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
    -- 步驟 5: 取得買家主要地點（距離計算用）
    -- ========================================
    IF v_current_uid IS NOT NULL AND NOT v_is_owner THEN
        SELECT coordinates INTO v_user_primary_location
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = TRUE
        LIMIT 1;
    END IF;

    -- ========================================
    -- 步驟 6: 構建完整 JSON 結果
    -- ========================================
    SELECT json_build_object(
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
            WHEN v_user_primary_location IS NULL THEN NULL
            ELSE ROUND((ST_Distance(seller_loc.coordinates, v_user_primary_location) / 1000.0)::numeric, 3)
        END,

        'is_favorited', CASE
            WHEN v_current_uid IS NULL THEN NULL
            ELSE EXISTS (
                SELECT 1 FROM public.favorites
                WHERE user_id = v_current_uid AND item_id = i.id
            )
        END,
        'is_owner', v_is_owner,

        'location', json_build_object(
            'id', seller_loc.id,
            'formatted_address', seller_loc.formatted_address,
            'type', seller_loc.type,
            'is_primary', seller_loc.is_primary,
            'coordinates', CASE
                WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
                ELSE ST_AsGeoJSON(seller_loc.coordinates)::json
            END
        ),

        'user', json_build_object(
            'id', u.id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url,
            'avg_rating', u.avg_rating
        ),

        'category', json_build_object(
            'sub_category_id', sc.id,
            'sub_category_name', sc.name,
            'main_category_id', mc.id,
            'main_category_name', mc.name,
            'main_category_icon', mc.icon,
            'main_category_color', mc.color
        ),

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
    LEFT JOIN public.locations seller_loc
        ON i.user_id = seller_loc.user_id
       AND seller_loc.is_primary = i.use_primary_location
    WHERE i.id = p_item_id;

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
$function$;

-- =============================================
-- 函數元資料與版本說明
-- =============================================
COMMENT ON FUNCTION public.get_item_details_with_location(BIGINT) IS
'取得物品詳情 v4.1.1 (Hotfix) - 修復所有者無法查看已下架物品：
- 【修復】地點驗證僅針對非所有者執行
- 【保證】所有者始終可查看自己的物品（無論上架狀態）
- 賣家地點：根據 items.use_primary_location 動態選擇主要或次要地點
- 買家地點：僅登入買家使用其主要地點進行距離計算
- 距離計算：買家主要地點 ↔ 賣家物品地點（主要或次要）
- 座標隱私：未登入使用者和擁有者不顯示座標資訊
- 上架驗證：非擁有者只能查看已上架物品
- 隱私保護：分離擁有者與買家的資訊可見性
- 返回格式：包含物品、賣家、分類、距離、收藏、位置等完整資訊';
