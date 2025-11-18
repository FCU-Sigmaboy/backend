-- =============================================
-- Hotfix: get_item_details_with_location 函數優化
-- 日期: 2025-11-18
-- 版本: v4.1
-- 說明:
--   本次修復針對物品詳情查詢函數進行完善，確保：
--   1. 正確處理物品上架狀態與所有者判斷邏輯
--   2. 驗證賣家地點存在性（支援主要/次要地點選擇）
--   3. 完整的隱私保護機制（座標、距離對未登入/所有者隱藏）
--   4. 精確的距離計算（基於實際物品地點設定）
--
-- 核心邏輯流程:
--   Step 1: 取得物品 & 賣家資訊
--   Step 2: 判斷當前用戶是否為物品所有者
--   Step 3: 非所有者必須檢查物品上架狀態
--   Step 4: 驗證賣家的對應地點是否存在
--   Step 5: 取得買家主要地點（用於距離計算）
--   Step 6: 組建完整的JSON回應（含距離、分類、用戶資訊）
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
    -- ===== STEP 1: 物品存在性檢查 & 基本資訊獲取 =====
    -- 從 items 表獲取：
    --   - 賣家ID (user_id): 用於後續所有權判斷和地點驗證
    --   - use_primary_location: 決定使用主要還是次要地點
    --   - listing_status: 決定非所有者是否可見
    SELECT u.id, i.use_primary_location, i.listing_status
    INTO v_seller_id, v_item_use_primary_location, v_listing_status
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    WHERE i.id = p_item_id;

    -- 提早返回：物品不存在
    IF v_seller_id IS NULL THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- ===== STEP 2: 所有者判斷 =====
    -- 判斷當前登入用戶是否為物品擁有者
    -- 影響後續的：隱私保護、距離計算、座標顯示
    IF v_current_uid IS NOT NULL THEN
        v_is_owner := (v_seller_id = v_current_uid);
    END IF;

    -- ===== STEP 3: 上架狀態檢查（非所有者） =====
    -- 業務規則：
    --   - 所有者始終可見自己的物品（包括已下架）
    --   - 非所有者只能看已上架的物品
    -- 此檢查必須在第2步後，因為需要先判斷是否為所有者
    IF v_is_owner IS NOT TRUE AND v_listing_status IS NOT TRUE THEN
        RETURN json_build_object(
            'error', TRUE,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    -- ===== STEP 4: 賣家地點有效性驗證 =====
    -- 確保賣家具有物品指定的地點類型（主要或次要）
    -- 驗證條件：
    --   - 地點必須屬於賣家 (user_id = v_seller_id)
    --   - is_primary 必須與 items.use_primary_location 相符
    -- 這是必須的驗證，確保後續 JOIN 會找到有效的地點記錄
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

    -- ===== STEP 5: 買家地點取得（用於距離計算） =====
    -- 取得當前用戶的主要地點（geographic point）
    -- 使用條件：
    --   - 用戶必須已登入 (v_current_uid IS NOT NULL)
    --   - 用戶不能是物品擁有者 (NOT v_is_owner)
    -- 此地點用於計算「買家到賣家」的距離
    IF v_current_uid IS NOT NULL AND NOT v_is_owner THEN
        SELECT coordinates INTO v_user_primary_location
        FROM public.locations
        WHERE user_id = v_current_uid
          AND is_primary = TRUE
        LIMIT 1;
    END IF;

    -- ===== STEP 6: 物品詳情組建（核心查詢） =====
    -- 構建回應JSON，包含以下關鍵邏輯：
    --
    -- 【距離計算】distance_km
    --   計算條件（三者都需滿足，否則為 NULL）：
    --     1. 用戶已登入 (v_current_uid IS NOT NULL)
    --     2. 用戶不是擁有者 (NOT v_is_owner)
    --     3. 用戶設有主要地點 (v_user_primary_location IS NOT NULL)
    --   計算方式：ST_Distance 返回公尺，除以1000轉換為公里，保留3位小數
    --
    -- 【收藏狀態】is_favorited
    --   查詢條件：用戶已登入
    --   回傳：若已登入，返回布林值；未登入則為 NULL
    --
    -- 【座標隱私】coordinates (location.coordinates 和 user_location.coordinates)
    --   隱私規則：未登入用戶和物品所有者看不到座標（ST_AsGeoJSON 返回 NULL）
    --   僅有潛在買家（已登入且非所有者）可見座標
    --
    -- 【用戶位置資訊】user_location (僅非所有者可見)
    --   提供買家位置狀態：是否有設定、來源、座標、人類可讀訊息
    --
    -- 【JOIN 策略】seller_loc 的 is_primary 匹配
    --   使用 items.use_primary_location 動態決定要 JOIN 主要或次要地點
    --   確保距離計算基於物品實際指定的地點
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

        -- 距離欄位：僅對非所有者且已登入且有地點的買家計算
        'distance_km', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            WHEN v_user_primary_location IS NULL THEN NULL
            ELSE ROUND((ST_Distance(seller_loc.coordinates, v_user_primary_location) / 1000.0)::numeric, 3)
        END,

        -- 收藏狀態：已登入用戶顯示，未登入為 NULL
        'is_favorited', CASE
            WHEN v_current_uid IS NULL THEN NULL
            ELSE EXISTS (
                SELECT 1 FROM public.favorites
                WHERE user_id = v_current_uid AND item_id = i.id
            )
        END,
        'is_owner', v_is_owner,

        -- 賣家地點資訊：座標根據用戶身份隱藏
        'location', json_build_object(
            'id', seller_loc.id,
            'formatted_address', seller_loc.formatted_address,
            'type', seller_loc.type,
            'is_primary', seller_loc.is_primary,
            -- 座標隱私：只有潛在買家（非所有者 + 已登入）能看
            'coordinates', CASE
                WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
                ELSE ST_AsGeoJSON(seller_loc.coordinates)::json
            END
        ),

        -- 賣家用戶資訊
        'user', json_build_object(
            'id', u.id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url,
            'avg_rating', u.avg_rating
        ),

        -- 物品分類資訊（子分類 -> 主分類）
        'category', json_build_object(
            'sub_category_id', sc.id,
            'sub_category_name', sc.name,
            'main_category_id', mc.id,
            'main_category_name', mc.name,
            'main_category_icon', mc.icon,
            'main_category_color', mc.color
        ),

        -- 買家位置資訊：僅非所有者且已登入時提供
        -- 用途：前端判斷是否成功取得買家地點，決定是否計算距離
        'user_location', CASE
            WHEN v_current_uid IS NULL OR v_is_owner THEN NULL
            ELSE json_build_object(
                'has_location', (v_user_primary_location IS NOT NULL),
                'source', CASE
                    WHEN v_user_primary_location IS NOT NULL THEN 'database_primary'
                    ELSE 'none'
                END,
                -- 座標隱私：買家的座標不向賣家暴露（本來就是 v_user_primary_location，前端已知）
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
    -- 【關鍵 JOIN】根據 items.use_primary_location 動態選擇賣家的地點
    -- 確保距離計算基於物品設定的地點（主要或次要）
    INNER JOIN public.locations seller_loc
        ON i.user_id = seller_loc.user_id
       AND seller_loc.is_primary = i.use_primary_location
    WHERE i.id = p_item_id;

    -- ===== STEP 7: 結果檢查 =====
    -- 驗證查詢是否成功取得結果
    -- 若仍為 NULL，表示在多表JOIN時出現問題（通常不應發生，因已在Step 4驗證）
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
-- 函數文檔
-- =============================================
COMMENT ON FUNCTION public.get_item_details_with_location(bigint) IS
'獲取物品詳情 v4.1 - Hotfix版本
【核心功能】
  獲取單一物品的完整詳情，包含賣家資訊、地點、距離計算

【輸入參數】
  p_item_id: 物品ID (bigint)

【隱私保護機制】
  - 座標隱藏: 只有潛在買家（已登入 + 非所有者）可見座標
  - 距離隱藏: 未登入用戶與物品所有者看不到距離
  - 上架檢查: 非所有者僅能查看已上架物品

【距離計算】
  - 基準: 買家主要地點 → 賣家物品地點
  - 賣家地點類型: 由 items.use_primary_location 決定（主要或次要）
  - 單位: 公里 (km)，精度3位小數

【返回結構】
  成功: 完整物品JSON對象
  失敗: 包含 error=true, code, message 的JSON對象

【版本歷史】
  v4.0: 支援 use_primary_location 動態地點選擇
  v4.1: Hotfix - 完整化邏輯註解，確保隱私保護機制清晰';
