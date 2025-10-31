-- =============================================
-- 測試：買家瀏覽多個賣家物品距離計算
-- 日期：2025-10-31
-- 測試場景：
--   買家：user.id = 1
--   賣家：user.id = 2, 3, 4, 5, 6
--   目標：測試買家瀏覽各賣家物品時的距離計算
-- =============================================

-- =============================================
-- 部分 1: 驗證測試環境
-- =============================================

-- 1.1 驗證買家是否存在
-- 買家：Tao (ID: 488a4712-dd63-4938-9679-336f434ad263)
SELECT
    id,
    nickname,
    avg_rating,
    created_at
FROM public.users
WHERE id = '488a4712-dd63-4938-9679-336f434ad263'
LIMIT 1;

-- 1.2 驗證五個賣家是否存在
-- 賣家: Yo, Lee, Lin, Liao, Chen
SELECT
    id,
    nickname,
    avg_rating,
    created_at
FROM public.users
WHERE id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
ORDER BY id;

-- =============================================
-- 部分 2: 驗證買家和賣家的地點資訊
-- =============================================

-- 2.1 買家的地點設定
SELECT
    u.id as user_id,
    u.nickname,
    l.id as location_id,
    l.formatted_address,
    l.type,
    l.is_primary,
    ST_AsText(l.coordinates::geometry) as coordinates_text
FROM public.users u
LEFT JOIN public.locations l ON u.id = l.user_id
WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
ORDER BY l.is_primary DESC, l.created_at ASC;

-- 2.2 五個賣家的主要地點設定
SELECT
    u.id as seller_id,
    u.nickname as seller_nickname,
    l.id as location_id,
    l.formatted_address,
    l.type,
    l.is_primary,
    ST_AsText(l.coordinates::geometry) as coordinates_text,
    ST_AsGeoJSON(l.coordinates)::json as coordinates_geojson
FROM public.users u
LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
ORDER BY u.id;

-- =============================================
-- 部分 3: 驗證五個賣家的物品資訊
-- =============================================

-- 3.1 每個賣家有多少物品在售
SELECT
    u.id as seller_id,
    u.nickname as seller_nickname,
    COUNT(i.id) as total_items,
    SUM(CASE WHEN i.listing_status = true THEN 1 ELSE 0 END) as active_items,
    SUM(CASE WHEN i.listing_status = false THEN 1 ELSE 0 END) as inactive_items
FROM public.users u
LEFT JOIN public.items i ON u.id = i.user_id
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
GROUP BY u.id, u.nickname
ORDER BY u.id;

-- 3.2 五個賣家的所有在售物品詳情
SELECT
    u.id as seller_id,
    u.nickname as seller_nickname,
    i.id as item_id,
    i.title,
    i.price,
    i.condition,
    i.listing_status,
    i.created_at
FROM public.users u
LEFT JOIN public.items i ON u.id = i.user_id
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
    AND i.listing_status = true
ORDER BY u.id, i.created_at DESC;

-- =============================================
-- 部分 4: 計算買家與賣家位置的距離
-- =============================================

-- 4.1 直接 SQL 計算：買家主要地點 vs 五個賣家主要地點距離
WITH buyer_location AS (
    SELECT
        u.id,
        u.nickname,
        l.coordinates,
        l.formatted_address,
        ST_AsGeoJSON(l.coordinates)::json as geojson
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
),
seller_locations AS (
    SELECT
        u.id as seller_id,
        u.nickname as seller_nickname,
        l.id as location_id,
        l.formatted_address as seller_address,
        l.coordinates,
        ST_AsGeoJSON(l.coordinates)::json as seller_geojson
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
        AND l.coordinates IS NOT NULL
)
SELECT
    bl.id as buyer_id,
    bl.nickname as buyer_nickname,
    sl.seller_id,
    sl.seller_nickname,
    sl.seller_address,
    ROUND((ST_Distance(bl.coordinates, sl.coordinates) / 1000.0)::numeric, 3) as distance_km,
    CASE
        WHEN ROUND((ST_Distance(bl.coordinates, sl.coordinates) / 1000.0)::numeric, 3) < 1 THEN '很近 (< 1km)'
        WHEN ROUND((ST_Distance(bl.coordinates, sl.coordinates) / 1000.0)::numeric, 3) < 5 THEN '近 (1-5km)'
        WHEN ROUND((ST_Distance(bl.coordinates, sl.coordinates) / 1000.0)::numeric, 3) < 10 THEN '中等 (5-10km)'
        WHEN ROUND((ST_Distance(bl.coordinates, sl.coordinates) / 1000.0)::numeric, 3) < 20 THEN '較遠 (10-20km)'
        ELSE '很遠 (> 20km)'
    END as distance_category
FROM buyer_location bl
CROSS JOIN seller_locations sl
ORDER BY sl.seller_id, distance_km ASC;

-- =============================================
-- 部分 5: 買家瀏覽賣家物品時的距離（使用 RPC 函數）
-- =============================================

-- 5.1 獲取買家的主要地點座標
WITH buyer_coords AS (
    SELECT
        ST_Y(l.coordinates::geometry) as lat,
        ST_X(l.coordinates::geometry) as lng
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
    LIMIT 1
),
seller_items AS (
    SELECT
        i.id as item_id,
        u.id as seller_id,
        u.nickname as seller_nickname,
        i.title,
        i.price,
        i.condition
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    WHERE u.id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
        AND i.listing_status = true
)
SELECT
    si.seller_id,
    si.seller_nickname,
    si.item_id,
    si.title,
    si.price,
    (rpc_result->>'distance_km')::numeric as distance_km,
    (rpc_result->'location'->>'formatted_address') as seller_address,
    (rpc_result->'user_location'->>'source') as location_source
FROM seller_items si
CROSS JOIN buyer_coords bc
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(si.item_id::BIGINT, bc.lat::DECIMAL, bc.lng::DECIMAL) as rpc_result
) rpc
ORDER BY si.seller_id, distance_km ASC;

-- =============================================
-- 部分 6: 按賣家統計買家瀏覽的物品距離
-- =============================================

-- 6.1 每個賣家的物品距離統計
WITH buyer_coords AS (
    SELECT
        ST_Y(l.coordinates::geometry) as lat,
        ST_X(l.coordinates::geometry) as lng
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
    LIMIT 1
),
seller_items_distance AS (
    SELECT
        u.id as seller_id,
        u.nickname as seller_nickname,
        i.id as item_id,
        (rpc_result->>'distance_km')::numeric as distance_km
    FROM public.users u
    LEFT JOIN public.items i ON u.id = i.user_id AND i.listing_status = true
    CROSS JOIN buyer_coords bc
    CROSS JOIN LATERAL (
        SELECT public.get_item_details_with_location(i.id::BIGINT, bc.lat::DECIMAL, bc.lng::DECIMAL) as rpc_result
    ) rpc
    WHERE u.id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
)
SELECT
    seller_id,
    seller_nickname,
    COUNT(item_id) as total_items,
    ROUND(AVG(distance_km)::numeric, 3) as avg_distance_km,
    ROUND(MIN(distance_km)::numeric, 3) as min_distance_km,
    ROUND(MAX(distance_km)::numeric, 3) as max_distance_km,
    ROUND(STDDEV(distance_km)::numeric, 3) as stddev_distance_km
FROM seller_items_distance
GROUP BY seller_id, seller_nickname
ORDER BY seller_id;

-- =============================================
-- 部分 7: 綜合排名：買家瀏覽最近的物品
-- =============================================

-- 7.1 按距離排名所有物品（買家視角）
WITH buyer_coords AS (
    SELECT
        ST_Y(l.coordinates::geometry) as lat,
        ST_X(l.coordinates::geometry) as lng
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
    LIMIT 1
),
all_seller_items AS (
    SELECT
        u.id as seller_id,
        u.nickname as seller_nickname,
        i.id as item_id,
        i.title,
        i.price,
        i.condition,
        (rpc_result->>'distance_km')::numeric as distance_km,
        (rpc_result->'location'->>'formatted_address') as seller_address
    FROM public.users u
    LEFT JOIN public.items i ON u.id = i.user_id AND i.listing_status = true
    CROSS JOIN buyer_coords bc
    CROSS JOIN LATERAL (
        SELECT public.get_item_details_with_location(i.id::BIGINT, bc.lat::DECIMAL, bc.lng::DECIMAL) as rpc_result
    ) rpc
    WHERE u.id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
)
SELECT
    ROW_NUMBER() OVER (ORDER BY distance_km ASC) as rank,
    seller_id,
    seller_nickname,
    item_id,
    title,
    price,
    condition,
    distance_km,
    seller_address,
    CASE
        WHEN distance_km < 1 THEN '⭐⭐⭐⭐⭐ 非常近'
        WHEN distance_km < 5 THEN '⭐⭐⭐⭐ 很近'
        WHEN distance_km < 10 THEN '⭐⭐⭐ 中等'
        WHEN distance_km < 20 THEN '⭐⭐ 較遠'
        ELSE '⭐ 很遠'
    END as proximity_rating
FROM all_seller_items
ORDER BY distance_km ASC
LIMIT 50;

-- =============================================
-- 部分 8: 賣家分組統計（買家角度）
-- =============================================

-- 8.1 買家瀏覽每個賣家時的物品概覽
WITH buyer_coords AS (
    SELECT
        u.id as buyer_id,
        u.nickname as buyer_name,
        ST_Y(l.coordinates::geometry) as lat,
        ST_X(l.coordinates::geometry) as lng,
        l.formatted_address as buyer_address
    FROM public.users u
    LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
    LIMIT 1
)
SELECT
    bc.buyer_id,
    bc.buyer_name,
    bc.buyer_address,
    u.id as seller_id,
    u.nickname as seller_name,
    COUNT(i.id) as item_count,
    ROUND(AVG((rpc_result->>'distance_km')::numeric)::numeric, 3) as avg_distance_km,
    ROUND(MIN((rpc_result->>'distance_km')::numeric)::numeric, 3) as min_distance_km,
    ROUND(MAX((rpc_result->>'distance_km')::numeric)::numeric, 3) as max_distance_km
FROM buyer_coords bc
CROSS JOIN public.users u
LEFT JOIN public.items i ON u.id = i.user_id AND i.listing_status = true
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(i.id::BIGINT, bc.lat::DECIMAL, bc.lng::DECIMAL) as rpc_result
) rpc
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
GROUP BY bc.buyer_id, bc.buyer_name, bc.buyer_address, u.id, u.nickname
ORDER BY u.id;

-- =============================================
-- 部分 9: 詳細測試報告
-- =============================================

-- 9.1 買家完整瀏覽報告
DO $$
DECLARE
    v_buyer_id UUID;
    v_buyer_name TEXT;
    v_buyer_address TEXT;
    v_total_sellers INT;
    v_total_items INT;
BEGIN
    -- 獲取買家資訊
    SELECT id, nickname INTO v_buyer_id, v_buyer_name
    FROM public.users
    WHERE id = '488a4712-dd63-4938-9679-336f434ad263'
    LIMIT 1;

    -- 獲取買家位置
    SELECT formatted_address INTO v_buyer_address
    FROM public.locations
    WHERE user_id = v_buyer_id AND is_primary = true
    LIMIT 1;

    -- 統計賣家數量
    SELECT COUNT(DISTINCT user_id) INTO v_total_sellers
    FROM public.items
    WHERE user_id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    );

    -- 統計物品數量
    SELECT COUNT(*) INTO v_total_items
    FROM public.items
    WHERE user_id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
        AND listing_status = true;

    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════╗';
    RAISE NOTICE '║       買家瀏覽賣家物品距離計算 - 測試報告          ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '【買家資訊】';
    RAISE NOTICE '  買家 ID: %', v_buyer_id;
    RAISE NOTICE '  買家名稱: %', v_buyer_name;
    RAISE NOTICE '  買家位置: %', v_buyer_address;
    RAISE NOTICE '';
    RAISE NOTICE '【賣家資訊】';
    RAISE NOTICE '  賣家數量: 5 個 (Yo, Lee, Lin, Liao, Chen)';
    RAISE NOTICE '';
    RAISE NOTICE '【物品資訊】';
    RAISE NOTICE '  總物品數: %', v_total_items;
    RAISE NOTICE '';
    RAISE NOTICE '【測試涵蓋】';
    RAISE NOTICE '  ✅ 部分 1: 驗證買家和賣家資料';
    RAISE NOTICE '  ✅ 部分 2: 驗證地點資訊';
    RAISE NOTICE '  ✅ 部分 3: 驗證物品資訊';
    RAISE NOTICE '  ✅ 部分 4: 直接 SQL 距離計算';
    RAISE NOTICE '  ✅ 部分 5: RPC 函數距離計算';
    RAISE NOTICE '  ✅ 部分 6: 賣家統計';
    RAISE NOTICE '  ✅ 部分 7: 綜合排名';
    RAISE NOTICE '  ✅ 部分 8: 賣家分組統計';
    RAISE NOTICE '';
    RAISE NOTICE '【測試狀態】';
    RAISE NOTICE '  ✅ 測試準備完成，可開始執行各部分查詢';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 部分 10: 位置來源驗證
-- =============================================

-- 10.1 驗證不同位置來源下的距離計算
-- 場景 A: 使用瀏覽器座標（與買家不同位置）
WITH test_browser_location AS (
    SELECT
        1 as test_case,
        '瀏覽器座標'::text as location_source,
        24.2000 as test_lat,
        120.6500 as test_lng
),
seller_items AS (
    SELECT
        i.id as item_id,
        u.id as seller_id,
        u.nickname as seller_name,
        i.title
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    WHERE u.id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
        '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
        '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
    )
        AND i.listing_status = true
    LIMIT 5
)
SELECT
    tbl.test_case,
    tbl.location_source,
    si.seller_id,
    si.seller_name,
    si.item_id,
    si.title,
    (rpc_result->>'distance_km')::numeric as distance_km,
    (rpc_result->'user_location'->>'source') as actual_source
FROM test_browser_location tbl
CROSS JOIN seller_items si
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(si.item_id, tbl.test_lat::DECIMAL, tbl.test_lng::DECIMAL) as rpc_result
) rpc;

-- =============================================
-- 部分 11: 故障診斷
-- =============================================

-- 11.1 檢查買家的位置設定
SELECT
    '買家位置檢查' as check_item,
    CASE
        WHEN l.id IS NULL THEN '❌ 買家無地點設定'
        WHEN l.coordinates IS NULL THEN '❌ 買家地點座標為 NULL'
        WHEN l.is_primary = false THEN '⚠️ 買家無主要地點標記'
        ELSE '✅ 買家地點設定正常'
    END as status,
    u.id as user_id,
    u.nickname,
    l.formatted_address,
    l.is_primary
FROM public.users u
LEFT JOIN public.locations l ON u.id = l.user_id
WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263'
ORDER BY l.is_primary DESC;

-- 11.2 檢查五個賣家的主要地點設定
SELECT
    '賣家主要地點檢查' as check_item,
    u.id as seller_id,
    u.nickname as seller_name,
    CASE
        WHEN l.id IS NULL THEN '❌ 無地點設定'
        WHEN l.coordinates IS NULL THEN '❌ 座標為 NULL'
        WHEN l.is_primary = true THEN '✅ 主要地點正常'
        ELSE '⚠️ 無主要地點'
    END as status,
    l.formatted_address,
    l.is_primary
FROM public.users u
LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
ORDER BY u.id;

-- 11.3 檢查各賣家的物品數量
SELECT
    '賣家物品檢查' as check_item,
    u.id as seller_id,
    u.nickname as seller_name,
    COUNT(i.id) as total_items,
    SUM(CASE WHEN i.listing_status = true THEN 1 ELSE 0 END) as active_items,
    CASE
        WHEN COUNT(i.id) = 0 THEN '⚠️ 無物品'
        WHEN SUM(CASE WHEN i.listing_status = true THEN 1 ELSE 0 END) = 0 THEN '⚠️ 無在售物品'
        ELSE '✅ 物品正常'
    END as status
FROM public.users u
LEFT JOIN public.items i ON u.id = i.user_id
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
GROUP BY u.id, u.nickname
ORDER BY u.id;

-- =============================================
-- 部分 12: 快速測試摘要
-- =============================================

-- 12.1 一鍵測試所有核心指標
SELECT
    '測試指標' as metric,
    COUNT(*) as value,
    '項' as unit
FROM public.users
WHERE id = '488a4712-dd63-4938-9679-336f434ad263'

UNION ALL

SELECT
    '賣家數量',
    5,
    '個'

UNION ALL

SELECT
    '物品總數',
    COUNT(*),
    '件'
FROM public.items
WHERE user_id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)

UNION ALL

SELECT
    '在售物品',
    COUNT(*),
    '件'
FROM public.items
WHERE user_id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
    AND listing_status = true

UNION ALL

SELECT
    '買家地點',
    COUNT(*),
    '個'
FROM public.locations
WHERE user_id = '488a4712-dd63-4938-9679-336f434ad263'

UNION ALL

SELECT
    '買家主要地點',
    COUNT(*),
    '個'
FROM public.locations
WHERE user_id = '488a4712-dd63-4938-9679-336f434ad263'
    AND is_primary = true

ORDER BY metric;

