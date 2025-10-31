-- ####################################################################
-- ### 單一物品詳情 (RPC) - 完整版（含地理位置修正）
-- ### 日期：2025-10-31
-- ### 功能：
-- ###   1. 支援瀏覽器位置與資料庫位置混合使用
-- ###   2. 透過 items.user_id 查詢賣家主要地點（修正版）
-- ###   3. 支援未登入用戶查詢（Demo 環境）
-- ####################################################################

-- =============================================
-- 顯示執行訊息
-- =============================================
DO $$
    BEGIN
        RAISE NOTICE '';
        RAISE NOTICE '╔════════════════════════════════════════════════════╗';
        RAISE NOTICE '║   開始部署單一物品詳情 RPC 函數（完整版）         ║';
        RAISE NOTICE '╚════════════════════════════════════════════════════╝';
        RAISE NOTICE '';
    END $$;

-- =============================================
-- 主函數：get_item_details_with_location
-- 支援瀏覽器位置作為第一選擇，資料庫位置作為備選
-- =============================================
CREATE OR REPLACE FUNCTION public.get_item_details_with_location(
    p_item_id BIGINT,                    -- (必填) 要查詢的物品 ID
    p_user_latitude DECIMAL DEFAULT NULL, -- (可選) 瀏覽器提供的緯度
    p_user_longitude DECIMAL DEFAULT NULL -- (可選) 瀏覽器提供的經度
)
    RETURNS JSON
    LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_user_location GEOGRAPHY(Point, 4326);
    v_location_source TEXT := 'none';
    v_item_details JSON;
BEGIN
    -- ⚠️ Demo 環境：允許未登入用戶查詢
    -- 正式環境請取消下方註解以啟用登入驗證
    -- IF v_current_uid IS NULL THEN
    --     RAISE EXCEPTION '使用者未登入，無法獲取物品詳情';
    -- END IF;

    -- =============================================
    -- 位置處理邏輯（三級優先級）
    -- =============================================

    -- 【第 1 優先級】優先使用瀏覽器提供的即時位置
    IF p_user_latitude IS NOT NULL AND p_user_longitude IS NOT NULL THEN
        -- 驗證座標有效性
        IF p_user_latitude BETWEEN -90 AND 90 AND p_user_longitude BETWEEN -180 AND 180 THEN
            v_user_location := ST_SetSRID(ST_MakePoint(p_user_longitude, p_user_latitude), 4326)::GEOGRAPHY;
            v_location_source := 'browser';
        END IF;
    END IF;

    -- 【第 2 優先級】如果瀏覽器位置無效或未提供，使用資料庫地點
    IF v_user_location IS NULL AND v_current_uid IS NOT NULL THEN
        -- 2a. 使用資料庫主要地點
        SELECT coordinates INTO v_user_location
        FROM public.locations
        WHERE user_id = v_current_uid AND is_primary = true
        LIMIT 1;

        IF v_user_location IS NOT NULL THEN
            v_location_source := 'database_primary';
        ELSE
            -- 2b. 如果沒有主要地點，使用資料庫第一個地點
            SELECT coordinates INTO v_user_location
            FROM public.locations
            WHERE user_id = v_current_uid
            ORDER BY created_at ASC
            LIMIT 1;

            IF v_user_location IS NOT NULL THEN
                v_location_source := 'database_fallback';
            END IF;
        END IF;
    END IF;

    -- =============================================
    -- 查詢物品詳情並計算距離
    -- 【核心邏輯】透過 items.user_id 查詢賣家的主要地點座標
    -- =============================================

    SELECT
        json_build_object(
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

            -- 距離計算：買家位置 vs 賣家主要地點
                'distance_km', CASE
                                   WHEN v_user_location IS NOT NULL AND seller_loc.coordinates IS NOT NULL THEN
                                       ROUND((ST_Distance(seller_loc.coordinates, v_user_location) / 1000.0)::numeric, 3)
                                   ELSE NULL
                    END,

            -- 使用者互動狀態
                'is_favorited', CASE
                                    WHEN v_current_uid IS NOT NULL THEN
                                        EXISTS(SELECT 1 FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid)
                                    ELSE false
                    END,

                'is_owner', CASE
                                WHEN v_current_uid IS NOT NULL THEN (i.user_id = v_current_uid)
                                ELSE false
                    END,

            -- 物品地點資訊（賣家的主要地點）
                'location', json_build_object(
                        'id', seller_loc.id,
                        'formatted_address', seller_loc.formatted_address,
                        'type', seller_loc.type,
                        'coordinates', CASE
                                           WHEN seller_loc.coordinates IS NOT NULL THEN
                                               ST_AsGeoJSON(seller_loc.coordinates)::json
                                           ELSE NULL
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

            -- 買家位置資訊（用於前端顯示）
                'user_location', CASE
                                     WHEN v_user_location IS NOT NULL THEN
                                         json_build_object(
                                                 'has_location', true,
                                                 'source', v_location_source,
                                                 'coordinates', ST_AsGeoJSON(v_user_location)::json,
                                                 'message', CASE v_location_source
                                                                WHEN 'browser' THEN '使用瀏覽器即時定位'
                                                                WHEN 'database_primary' THEN '使用您的主要地點'
                                                                WHEN 'database_fallback' THEN '使用您設定的地點'
                                                                ELSE '位置來源未知'
                                                     END
                                         )
                                     ELSE
                                         json_build_object(
                                                 'has_location', false,
                                                 'source', 'none',
                                                 'message', '無法取得位置資訊'
                                         )
                    END
        )
    INTO v_item_details
    FROM
        public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            -- ⭐ 核心修正：透過賣家 user_id 查詢其主要地點
            LEFT JOIN public.locations seller_loc ON i.user_id = seller_loc.user_id AND seller_loc.is_primary = true
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
    WHERE
        i.id = p_item_id
      AND i.listing_status = true;

    -- 如果找不到物品，回傳錯誤訊息
    IF v_item_details IS NULL THEN
        v_item_details := json_build_object(
                'error', true,
                'message', '物品不存在或已下架',
                'item_id', p_item_id
                          );
    END IF;

    RETURN v_item_details;

END;
$$;

-- =============================================
-- 輔助函數：get_item_details_with_coordinates
-- 純座標版本（必須提供座標參數）
-- =============================================
CREATE OR REPLACE FUNCTION public.get_item_details_with_coordinates(
    p_item_id BIGINT,
    p_latitude DECIMAL,
    p_longitude DECIMAL
)
    RETURNS JSON
    LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_user_location GEOGRAPHY(Point, 4326);
    v_item_details JSON;
BEGIN
    -- 驗證座標參數
    IF p_latitude IS NULL OR p_longitude IS NULL THEN
        RAISE EXCEPTION '緯度和經度參數不可為空';
    END IF;

    IF NOT (p_latitude BETWEEN -90 AND 90 AND p_longitude BETWEEN -180 AND 180) THEN
        RAISE EXCEPTION '座標參數無效：緯度須在 -90 到 90 之間，經度須在 -180 到 180 之間';
    END IF;

    -- 建立用戶位置
    v_user_location := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::GEOGRAPHY;

    -- 查詢物品詳情
    SELECT
        json_build_object(
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

            -- 距離計算
                'distance_km', CASE
                                   WHEN seller_loc.coordinates IS NOT NULL THEN
                                       ROUND((ST_Distance(seller_loc.coordinates, v_user_location) / 1000.0)::numeric, 3)
                                   ELSE NULL
                    END,

            -- 使用者互動狀態
                'is_favorited', CASE
                                    WHEN v_current_uid IS NOT NULL THEN
                                        EXISTS(SELECT 1 FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid)
                                    ELSE false
                    END,

                'is_owner', CASE
                                WHEN v_current_uid IS NOT NULL THEN (i.user_id = v_current_uid)
                                ELSE false
                    END,

            -- 物品地點資訊
                'location', json_build_object(
                        'id', seller_loc.id,
                        'formatted_address', seller_loc.formatted_address,
                        'type', seller_loc.type,
                        'coordinates', CASE
                                           WHEN seller_loc.coordinates IS NOT NULL THEN
                                               ST_AsGeoJSON(seller_loc.coordinates)::json
                                           ELSE NULL
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

            -- 買家位置資訊
                'user_location', json_build_object(
                        'has_location', true,
                        'source', 'coordinates',
                        'coordinates', ST_AsGeoJSON(v_user_location)::json,
                        'message', '使用指定座標計算距離'
                                 )
        )
    INTO v_item_details
    FROM
        public.items i
            LEFT JOIN public.users u ON i.user_id = u.id
            -- ⭐ 核心修正：透過賣家 user_id 查詢其主要地點
            LEFT JOIN public.locations seller_loc ON i.user_id = seller_loc.user_id AND seller_loc.is_primary = true
            LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
            LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
    WHERE
        i.id = p_item_id
      AND i.listing_status = true;

    -- 檢查結果
    IF v_item_details IS NULL THEN
        v_item_details := json_build_object(
                'error', true,
                'message', '物品不存在或已下架',
                'item_id', p_item_id
                          );
    END IF;

    RETURN v_item_details;

END;
$$;

-- =============================================
-- 驗證部署結果
-- =============================================
DO $$
    BEGIN
        RAISE NOTICE '';
        RAISE NOTICE '╔════════════════════════════════════════════════════╗';
        RAISE NOTICE '║          單一物品詳情 RPC 函數部署完成            ║';
        RAISE NOTICE '╚════════════════════════════════════════════════════╝';
        RAISE NOTICE '';
        RAISE NOTICE '【已部署的函數】';
        RAISE NOTICE '  ✅ get_item_details_with_location(item_id, lat?, lng?)';
        RAISE NOTICE '  ✅ get_item_details_with_coordinates(item_id, lat, lng)';
        RAISE NOTICE '';
        RAISE NOTICE '【核心特性】';
        RAISE NOTICE '  ✅ 買家位置三級優先級：瀏覽器 > 主要地點 > 任意地點';
        RAISE NOTICE '  ✅ 賣家位置：自動查詢主要地點 (is_primary=true)';
        RAISE NOTICE '  ✅ 距離計算：使用 PostGIS ST_Distance';
        RAISE NOTICE '  ✅ 支援未登入用戶（Demo 環境）';
        RAISE NOTICE '';
        RAISE NOTICE '【關鍵修正】';
        RAISE NOTICE '  舊邏輯：items.location_id → locations.id';
        RAISE NOTICE '  新邏輯：items.user_id → locations.user_id AND is_primary=true';
        RAISE NOTICE '';
        RAISE NOTICE '【使用範例】';
        RAISE NOTICE '  -- 使用瀏覽器座標';
        RAISE NOTICE '  SELECT public.get_item_details_with_location(1, 24.1800, 120.6400);';
        RAISE NOTICE '';
        RAISE NOTICE '  -- 使用登入用戶的地點';
        RAISE NOTICE '  SELECT public.get_item_details_with_location(1, NULL, NULL);';
        RAISE NOTICE '';
        RAISE NOTICE '  -- 使用純座標版本';
        RAISE NOTICE '  SELECT public.get_item_details_with_coordinates(1, 24.1800, 120.6400);';
        RAISE NOTICE '';
    END $$;

/*
====================================================================
【部署說明】

此 migration 檔案包含完整的單一物品詳情 RPC 函數，整合了以下功能：

1. 【主函數】get_item_details_with_location
   - 支援瀏覽器位置（第 1 優先級）
   - 支援資料庫主要地點（第 2 優先級）
   - 支援資料庫任意地點（第 3 優先級）
   - 支援未登入用戶查詢

2. 【輔助函數】get_item_details_with_coordinates
   - 必須提供座標參數
   - 適合外部系統整合

3. 【核心修正】
   - 賣家地點查詢方式：items.user_id → locations (where is_primary=true)
   - 自動選擇賣家的主要地點
   - 更符合真實業務邏輯

4. 【JSON 回傳結構】
   {
     "id": 1,
     "title": "物品標題",
     "distance_km": 5.234,
     "location": { 賣家地點 },
     "user": { 賣家資訊 },
     "category": { 分類資訊 },
     "user_location": {
       "source": "browser|database_primary|database_fallback|none",
       "message": "位置來源說明"
     },
     "is_favorited": false,
     "is_owner": false
   }

【部署環境】
- ✅ Local/Development：完整支援
- ✅ Staging：完整支援
- ⚠️ Production：建議啟用登入驗證

【相關測試】
- tests/test_get_oneItemDetail.sql
- tests/test_get_item_distance_demo.sql
- tests/test_buyer_viewing_sellers_distance.sql

【版本資訊】
- 建立日期：2025-10-31
- 版本：2.0 (整合修正版)
- 取代檔案：
  - 20251031123711_get_item_detail.sql
  - 20251031140000_fix_item_location_reference.sql

====================================================================
*/

