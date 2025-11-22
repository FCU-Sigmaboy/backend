-- ####################################################################
-- ### 單一物品詳情 (RPC) - v3.0 優化版本
-- ### 日期：2025-11-09
-- ### 版本：v3.0（支援 use_primary_location）
-- ### 改進項目：
-- ###   1. ✅ 新增 items.use_primary_location 支援
-- ###   2. ✅ 根據 use_primary_location 欄位決定使用哪個地點
-- ###   3. ✅ 物品可選擇使用主要或次要地點
-- ###   4. 添加完整的異常處理
-- ###   5. 使用 JSONB 替代 JSON（更好的效能）
-- ###   6. 使用 CTE 減少多次查詢
-- ###   7. 優化 EXISTS 子查詢為 LEFT JOIN
-- ###   8. 添加參數驗證
-- ###   9. 添加函數註解
-- ###   10. 標準化錯誤訊息格式
-- ###   11. 使用 LEFT JOIN LATERAL 優化語意
-- ###   12. 提前過濾 listing_status（減少資料處理）
-- ###   13. 添加地理空間索引（GiST）
-- ###   14. 移除未使用變數
-- ###   15. 修正冗餘 COALESCE 和 NULL 檢查
-- ####################################################################

-- =============================================
-- 主函數：get_item_details_with_location (優化版)
-- =============================================
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
    -- =============================================
    -- 1. 參數驗證
    -- =============================================
    IF p_item_id IS NULL OR p_item_id <= 0 THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INVALID_PARAMETER',
            'message', '無效的物品 ID',
            'item_id', p_item_id
        );
    END IF;

    -- =============================================
    -- 2. 獲取當前用戶 ID
    -- =============================================
    v_current_uid := auth.uid();

    -- =============================================
    -- 3. 使用 CTE 優化查詢
    -- =============================================
    WITH
    -- 獲取用戶位置（優先主要地點，僅當用戶已登入時查詢）
    user_location AS (
        SELECT
            coordinates,
            CASE
                WHEN is_primary THEN 'database_primary'
                ELSE 'database_fallback'
            END as location_source
        FROM public.locations
        WHERE user_id = v_current_uid
          AND v_current_uid IS NOT NULL  -- 優化：避免未登入時的無效查詢
        ORDER BY
            is_primary DESC NULLS LAST,
            created_at
        LIMIT 1
    ),
    -- 主要物品查詢（提前過濾 listing_status）
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
            i.use_primary_location,  -- 新增：物品使用位置設定
            -- 賣家資訊
            u.id as seller_id,
            u.nickname as seller_nickname,
            u.profile_picture_url as seller_avatar,
            u.avg_rating as seller_rating,
            -- 賣家位置（根據 use_primary_location 決定使用主要或次要地點）
            seller_loc.id as location_id,
            seller_loc.formatted_address as location_address,
            seller_loc.type as location_type,
            seller_loc.coordinates as seller_coordinates,
            -- 分類資訊
            sc.id as sub_category_id,
            sc.name as sub_category_name,
            mc.id as main_category_id,
            mc.name as main_category_name,
            mc.icon as main_category_icon,
            mc.color as main_category_color,
            -- 收藏狀態（優化：使用 LEFT JOIN 而非 EXISTS）
            (fav.item_id IS NOT NULL) as is_favorited,
            -- 用戶位置（使用 CROSS JOIN LATERAL 更清晰的語意）
            ul.coordinates as user_coordinates,
            ul.location_source as user_location_source
        FROM public.items i
        INNER JOIN public.users u ON i.user_id = u.id  -- 改為 INNER JOIN：物品必須有擁有者
        LEFT JOIN public.locations seller_loc ON i.user_id = seller_loc.user_id AND seller_loc.is_primary = i.use_primary_location
        LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
        LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
        LEFT JOIN public.favorites fav ON fav.item_id = i.id AND fav.user_id = v_current_uid
        LEFT JOIN LATERAL (SELECT * FROM user_location) ul ON true  -- LEFT JOIN 允許 NULL 值
        WHERE i.id = p_item_id
          AND i.listing_status = true  -- 優化：提前過濾，減少後續處理
    )
    -- =============================================
    -- 4. 構建返回的 JSON 物件
    -- =============================================
    SELECT
        jsonb_build_object(
            -- 物品基本資訊
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
            'use_primary_location', use_primary_location,

            -- 距離計算（僅在已登入且非擁有者時顯示）
            'distance_km', CASE
                WHEN v_current_uid IS NOT NULL
                    AND v_current_uid != owner_id
                    AND seller_coordinates IS NOT NULL THEN
                    ROUND((ST_Distance(seller_coordinates, user_coordinates) / 1000.0)::numeric, 3)
            END,

            -- 使用者互動狀態
            'is_favorited', is_favorited,
            'is_owner', CASE
                WHEN v_current_uid IS NOT NULL THEN (owner_id = v_current_uid)
                ELSE false
            END,

            -- 物品地點資訊（隱私保護）
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

            -- 賣家資訊
            'user', jsonb_build_object(
                'id', seller_id,
                'nickname', seller_nickname,
                'profile_picture_url', seller_avatar,
                'avg_rating', seller_rating
            ),

            -- 分類資訊
            'category', jsonb_build_object(
                'sub_category_id', sub_category_id,
                'sub_category_name', sub_category_name,
                'main_category_id', main_category_id,
                'main_category_name', main_category_name,
                'main_category_icon', main_category_icon,
                'main_category_color', main_category_color
            ),

            -- 買家位置資訊（用於前端顯示）
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

    -- =============================================
    -- 5. 檢查結果並返回
    -- =============================================
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
    -- =============================================
    -- 6. 異常處理
    -- =============================================
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
        -- 記錄錯誤但不暴露內部細節給客戶端
        RAISE WARNING '查詢物品詳情時發生錯誤: % (item_id: %)', SQLERRM, p_item_id;
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INTERNAL_ERROR',
            'message', '查詢過程發生錯誤，請稍後再試',
            'item_id', p_item_id
        );
END;
$$;

-- =============================================
-- 添加函數註解
-- =============================================
COMMENT ON FUNCTION public.get_item_details_with_location(BIGINT) IS
'取得單一物品詳情，包含距離計算和隱私保護。
v3.0 更新 (2025-11-09):
- 根據 items.use_primary_location 欄位決定使用賣家的主要或次要地點
- 支援物品選擇使用主要位置 (true) 或次要位置 (false)
- 買家始終使用資料庫主要地點計算距離
- 未登入或查看自己的物品時，不顯示距離資訊和精確座標
- 優化版本：使用 CTE、JSONB、完整的錯誤處理
- 版本：v3.0
- 最後更新：2025-11-09';


-- =============================================
-- 建立必要的索引（如果不存在）
-- =============================================
DO $$
BEGIN
    -- 物品查詢索引（部分索引：僅索引上架的物品）
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_listing_status') THEN
        CREATE INDEX idx_items_listing_status ON public.items(listing_status)
        WHERE listing_status = true;
        RAISE NOTICE '✅ 已建立索引: idx_items_listing_status';
    END IF;

    -- 物品主鍵和上架狀態組合索引
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_id_listing_status') THEN
        CREATE INDEX idx_items_id_listing_status ON public.items(id, listing_status)
        WHERE listing_status = true;
        RAISE NOTICE '✅ 已建立索引: idx_items_id_listing_status';
    END IF;

    -- 位置查詢索引（組合索引）
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_locations_user_primary') THEN
        CREATE INDEX idx_locations_user_primary ON public.locations(user_id, is_primary);
        RAISE NOTICE '✅ 已建立索引: idx_locations_user_primary';
    END IF;

    -- 地理空間索引（GiST）- 優化 ST_Distance 查詢
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_locations_coordinates_gist') THEN
        CREATE INDEX idx_locations_coordinates_gist ON public.locations USING GIST(coordinates);
        RAISE NOTICE '✅ 已建立地理空間索引: idx_locations_coordinates_gist';
    END IF;

    -- 收藏查詢索引（組合索引）
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_favorites_item_user') THEN
        CREATE INDEX idx_favorites_item_user ON public.favorites(item_id, user_id);
        RAISE NOTICE '✅ 已建立索引: idx_favorites_item_user';
    END IF;

    -- 物品擁有者索引
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_user_id') THEN
        CREATE INDEX idx_items_user_id ON public.items(user_id);
        RAISE NOTICE '✅ 已建立索引: idx_items_user_id';
    END IF;

    -- 分類關聯索引
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_sub_category') THEN
        CREATE INDEX idx_items_sub_category ON public.items(sub_category_id);
        RAISE NOTICE '✅ 已建立索引: idx_items_sub_category';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_sub_categories_main') THEN
        CREATE INDEX idx_sub_categories_main ON public.sub_categories(main_category_id);
        RAISE NOTICE '✅ 已建立索引: idx_sub_categories_main';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════╗';
    RAISE NOTICE '║     單一物品詳情 RPC 優化版本部署完成（v2.5）    ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '【優化項目】';
    RAISE NOTICE '  ✅ 使用 JSONB 替代 JSON（更好的效能）';
    RAISE NOTICE '  ✅ 使用 CTE 減少查詢次數';
    RAISE NOTICE '  ✅ 優化 EXISTS 為 LEFT JOIN';
    RAISE NOTICE '  ✅ 添加完整的異常處理';
    RAISE NOTICE '  ✅ 添加參數驗證';
    RAISE NOTICE '  ✅ 添加函數註解';
    RAISE NOTICE '  ✅ 標準化錯誤訊息格式';
    RAISE NOTICE '  ✅ 建立必要的索引';
    RAISE NOTICE '  ✅ 設定 search_path 防止注入';
    RAISE NOTICE '  ✅ 使用 LEFT JOIN LATERAL 優化語意';
    RAISE NOTICE '  ✅ 提前過濾 listing_status';
    RAISE NOTICE '  ✅ 添加地理空間索引（GiST）';
    RAISE NOTICE '  ✅ 移除未使用變數';
    RAISE NOTICE '  ✅ 修正冗餘 COALESCE 和 NULL 檢查';
    RAISE NOTICE '  ✅ 移除冗餘 ELSE NULL 語句';
    RAISE NOTICE '  ✅ 簡化排序語句';
    RAISE NOTICE '  ✅ 移除向後相容函數（精簡代碼）';
    RAISE NOTICE '';
    RAISE NOTICE '【效能提升】';
    RAISE NOTICE '  🚀 減少資料庫查詢次數（4次 → 1次）';
    RAISE NOTICE '  🚀 使用 JSONB 加快 JSON 處理';
    RAISE NOTICE '  🚀 優化子查詢為 JOIN';
    RAISE NOTICE '  🚀 添加適當的索引（含 GiST）';
    RAISE NOTICE '  🚀 提前過濾減少資料處理量';
    RAISE NOTICE '  🚀 避免未登入用戶的無效查詢';
    RAISE NOTICE '';
    RAISE NOTICE '【安全性提升】';
    RAISE NOTICE '  🔒 添加參數驗證';
    RAISE NOTICE '  🔒 完整的異常處理';
    RAISE NOTICE '  🔒 設定 search_path';
    RAISE NOTICE '  🔒 錯誤訊息不暴露內部細節';
    RAISE NOTICE '';
    RAISE NOTICE '【使用方式】';
    RAISE NOTICE '  SELECT public.get_item_details_with_location(1);';
    RAISE NOTICE '';
END $$;

/*
====================================================================
【優化說明】

版本：v2.5 (精簡版本)
日期：2025-11-01
類型：代碼精簡與維護性優化

【v2.5 核心改進】

1. 移除向後相容函數
   - 移除 get_item_details_with_coordinates 函數
   - 原因：新專案無需維護舊 API 兼容性
   - 效果：減少代碼維護負擔，降低複雜度

2. 精簡代碼庫
   - 移除未使用的參數警告來源
   - 清理冗餘的包裝函數
   - 提高代碼可讀性

【效能影響】
- 減少函數數量，降低命名空間污染
- 簡化部署和維護流程
- 專注於單一、清晰的 API 介面

【v2.4 核心改進】

1. 移除冗餘 COALESCE
   - is_favorited: COALESCE(fav.item_id IS NOT NULL, false) → (fav.item_id IS NOT NULL)
   - 布林表達式本身已處理 NULL，無需 COALESCE

2. 簡化 NULL 檢查
   - 移除不必要的 user_coordinates IS NOT NULL 檢查
   - 在需要使用座標時才檢查 seller_coordinates

3. 移除冗餘 ELSE NULL
   - CASE 語句中移除不必要的 ELSE NULL
   - SQL 預設未匹配條件返回 NULL

4. 簡化排序語句
   - created_at ASC → created_at（ASC 是預設值）

5. 邏輯簡化
   - user_location 欄位重構，減少條件重複
   - 更清晰的條件判斷層次

6. 修正 JOIN 類型
   - CROSS JOIN LATERAL → LEFT JOIN LATERAL
   - 正確處理用戶無位置的情況

【v2.3 核心改進】

1. 返回類型：JSON → JSONB
   - 更好的效能（二進制格式）
   - 支援索引
   - 符合 Supabase 最佳實踐

2. 查詢優化：使用 CTE
   - 4次獨立查詢 → 1次 CTE 查詢
   - 減少資料庫往返次數
   - 提升整體效能

3. 子查詢優化：EXISTS → LEFT JOIN
   - 避免相關子查詢的效能問題
   - 在主查詢中一次性獲取所有數據

4. LEFT JOIN LATERAL 優化
   - 更清晰的語意表達
   - 更好的查詢規劃
   - 正確處理 NULL 值

5. 提前過濾優化
   - 在 WHERE 子句中提前過濾 listing_status
   - 減少後續資料處理量
   - 避免未登入用戶的無效位置查詢

6. 異常處理
   - 添加完整的 EXCEPTION 區塊
   - 標準化錯誤訊息格式
   - 錯誤碼系統（INVALID_PARAMETER, ITEM_NOT_FOUND, INTERNAL_ERROR）

7. 參數驗證
   - 檢查 NULL 和無效值
   - 提前返回錯誤，避免不必要的查詢

8. 安全性
   - 設定 search_path 防止 schema 注入
   - 錯誤訊息不暴露內部細節
   - 使用 RAISE WARNING 記錄錯誤供管理員查看

9. 索引管理
   - 自動檢查並創建必要的索引
   - 添加地理空間索引（GiST）優化 ST_Distance
   - 添加組合索引優化多條件查詢
   - 提升查詢效能

10. 程式碼清理
    - 移除未使用的變數
    - 統一 NULL 處理方式
    - 改善程式碼可讀性

11. 文檔完善
    - 使用 COMMENT ON FUNCTION 添加標準註解
    - 易於維護和理解

【效能測試建議】

1. 比較優化前後的執行時間：
   EXPLAIN ANALYZE SELECT public.get_item_details_with_location(1);

2. 監控查詢計劃：
   確認索引被正確使用

3. 負載測試：
   模擬高並發場景

4. 檢查地理空間查詢效能：
   EXPLAIN ANALYZE 檢查 GiST 索引是否被使用

【遷移步驟】

1. 在開發環境部署並測試
2. 使用 EXPLAIN ANALYZE 驗證效能提升
3. 進行完整的功能測試
4. 驗證索引創建成功
5. 在生產環境部署

【Supabase 最佳實踐遵循】

✅ 使用 SECURITY DEFINER 但設定 search_path
✅ 使用 STABLE 標記純查詢函數
✅ 使用 JSONB 而非 JSON
✅ 適當的索引策略（含 GiST）
✅ 完整的錯誤處理
✅ 參數驗證
✅ 函數註解文檔
✅ 避免不必要的查詢
✅ 使用 CTE 優化複雜查詢
✅ 移除冗餘程式碼
✅ 簡化邏輯判斷
✅ 精簡 API 介面（單一函數）

====================================================================
*/

