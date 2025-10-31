-- =============================================
-- 開放 Locations 表的 RLS 權限 - Demo 環境專用
-- 建立日期: 2025-10-31
-- 目的: 解決未登入用戶無法查詢物品距離的問題
-- 警告：此檔案僅適用於 Demo/測試環境，正式環境請勿使用！
-- =============================================

-- 顯示執行訊息
DO $$
BEGIN
    RAISE NOTICE '開始設定 locations 表的開放式 RLS 權限...';
END $$;

-- =============================================
-- 1. 確保 RLS 已啟用（但使用寬鬆的策略）
-- =============================================

-- 啟用 RLS（如果尚未啟用）
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 2. 刪除現有的限制性策略
-- =============================================

-- 刪除舊的限制性策略（如果存在）
DROP POLICY IF EXISTS "users_can_view_own_locations" ON public.locations;
DROP POLICY IF EXISTS "users_can_insert_own_locations" ON public.locations;
DROP POLICY IF EXISTS "users_can_update_own_locations" ON public.locations;
DROP POLICY IF EXISTS "users_can_delete_own_locations" ON public.locations;

-- =============================================
-- 3. 建立開放式 Demo 策略
-- =============================================

-- 策略 1: 任何人都可以查看所有地點（包括未登入用戶）
CREATE POLICY "Demo - Anyone can view all locations"
ON public.locations
FOR SELECT
TO public
USING (true);

-- 策略 2: 已登入用戶可以新增自己的地點
CREATE POLICY "Demo - Authenticated users can insert own locations"
ON public.locations
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- 策略 3: 已登入用戶可以更新自己的地點
CREATE POLICY "Demo - Authenticated users can update own locations"
ON public.locations
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 策略 4: 已登入用戶可以刪除自己的地點
CREATE POLICY "Demo - Authenticated users can delete own locations"
ON public.locations
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- 策略 5: 允許匿名用戶新增地點（Demo 專用）
CREATE POLICY "Demo - Anonymous users can insert locations"
ON public.locations
FOR INSERT
TO anon
WITH CHECK (true);

-- =============================================
-- 4. 確保權限已授予
-- =============================================

-- 授予 SELECT 權限給所有角色（包括 anon 和 authenticated）
GRANT SELECT ON public.locations TO anon, authenticated;

-- 授予完整權限給 authenticated 角色
GRANT INSERT, UPDATE, DELETE ON public.locations TO authenticated;

-- 授予 INSERT 權限給 anon 角色（Demo 專用）
GRANT INSERT ON public.locations TO anon;

-- 授予序列使用權限
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO anon, authenticated;

-- =============================================
-- 5. 修改相關 RPC 函數，移除登入驗證
-- =============================================

-- 修改主函數：允許未登入用戶查詢
CREATE OR REPLACE FUNCTION public.get_item_details_with_location(
    p_item_id BIGINT,
    p_user_latitude DECIMAL DEFAULT NULL,
    p_user_longitude DECIMAL DEFAULT NULL
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
    -- ⚠️ 移除登入驗證，允許 Demo 環境未登入查詢
    -- 註解掉原有的驗證邏輯
    -- IF v_current_uid IS NULL THEN
    --     RAISE EXCEPTION '使用者未登入，無法獲取物品詳情';
    -- END IF;

    -- 位置處理邏輯
    -- 優先使用瀏覽器提供的位置
    IF p_user_latitude IS NOT NULL AND p_user_longitude IS NOT NULL THEN
        IF p_user_latitude BETWEEN -90 AND 90 AND p_user_longitude BETWEEN -180 AND 180 THEN
            v_user_location := ST_SetSRID(ST_MakePoint(p_user_longitude, p_user_latitude), 4326)::GEOGRAPHY;
            v_location_source := 'browser';
        END IF;
    END IF;

    -- 只有登入用戶才查詢資料庫地點
    IF v_user_location IS NULL AND v_current_uid IS NOT NULL THEN
        -- 使用資料庫主要地點
        SELECT coordinates INTO v_user_location
        FROM public.locations
        WHERE user_id = v_current_uid AND is_primary = true
        LIMIT 1;

        IF v_user_location IS NOT NULL THEN
            v_location_source := 'database_primary';
        ELSE
            -- 使用資料庫第一個地點
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

    -- 查詢物品詳情
    SELECT
        json_build_object(
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
            'distance_km', CASE
                WHEN v_user_location IS NOT NULL AND l.coordinates IS NOT NULL THEN
                    ROUND((ST_Distance(l.coordinates, v_user_location) / 1000.0)::numeric, 3)
                ELSE NULL
            END,
            'is_favorited', CASE
                WHEN v_current_uid IS NOT NULL THEN
                    EXISTS(SELECT 1 FROM public.favorites f WHERE f.item_id = i.id AND f.user_id = v_current_uid)
                ELSE false
            END,
            'is_owner', (v_current_uid IS NOT NULL AND i.user_id = v_current_uid),
            'location', json_build_object(
                'id', l.id,
                'formatted_address', l.formatted_address,
                'type', l.type,
                'coordinates', CASE
                    WHEN l.coordinates IS NOT NULL THEN ST_AsGeoJSON(l.coordinates)::json
                    ELSE NULL
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
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    LEFT JOIN public.locations l ON i.location_id = l.id
    LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
    LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
    WHERE i.id = p_item_id AND i.listing_status = true;

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
-- 6. 驗證設定結果
-- =============================================

DO $$
DECLARE
    v_policy_count INT;
BEGIN
    -- 檢查策略數量
    SELECT COUNT(*) INTO v_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'locations'
    AND policyname LIKE 'Demo -%';

    RAISE NOTICE '=== Locations 表 RLS 權限設定完成 ===';
    RAISE NOTICE '✅ RLS 已啟用但使用開放式策略';
    RAISE NOTICE '✅ 已建立 % 個 Demo 專用策略', v_policy_count;
    RAISE NOTICE '✅ 任何人都可以查看所有地點資料';
    RAISE NOTICE '✅ 已登入用戶可以管理自己的地點';
    RAISE NOTICE '✅ 已移除 get_item_details_with_location 函數的登入驗證';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  警告：這是 Demo 環境設定，正式環境請勿使用！';
    RAISE NOTICE '⚠️  正式環境應該限制地點資料只能由擁有者查看';
END $$;

-- =============================================
-- 7. 測試查詢（可選）
-- =============================================

-- 驗證任何人都可以查詢 locations
DO $$
DECLARE
    v_location_count INT;
BEGIN
    SELECT COUNT(*) INTO v_location_count FROM public.locations;
    RAISE NOTICE '✅ 測試通過：locations 表共有 % 筆資料', v_location_count;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ 測試失敗：無法查詢 locations 表';
        RAISE NOTICE '錯誤訊息：%', SQLERRM;
END $$;

/*
===================================================================
恢復原始 RLS 設定（正式環境使用）:

-- 刪除 Demo 策略
DROP POLICY IF EXISTS "Demo - Anyone can view all locations" ON public.locations;
DROP POLICY IF EXISTS "Demo - Authenticated users can insert own locations" ON public.locations;
DROP POLICY IF EXISTS "Demo - Authenticated users can update own locations" ON public.locations;
DROP POLICY IF EXISTS "Demo - Authenticated users can delete own locations" ON public.locations;
DROP POLICY IF EXISTS "Demo - Anonymous users can insert locations" ON public.locations;

-- 撤銷過度權限
REVOKE ALL ON public.locations FROM anon;
REVOKE SELECT ON public.locations FROM public;

-- 建立正式環境的限制性策略
CREATE POLICY "Users can view own locations"
ON public.locations FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can insert own locations"
ON public.locations FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own locations"
ON public.locations FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own locations"
ON public.locations FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- 恢復 get_item_details_with_location 函數的登入驗證
-- （重新執行 20251031123711_get_item_detail.sql）

===================================================================
*/

