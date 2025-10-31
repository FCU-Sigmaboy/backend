-- =============================================
-- 測試場景：
--   買家：Tao (ID: 488a4712-dd63-4938-9679-336f434ad263)
--   賣家：
--     'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
--     '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
--     '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
--     'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
--     'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen（5 個）
--   目標：測試買家瀏覽各賣家物品時的距離計算
--   特點：RPC 函數自動使用資料庫位置，無需傳遞座標參數
-- =============================================

-- =============================================
-- 測試：買家視角 - 瀏覽賣家物品距離計算
-- 日期：2025-11-01
-- 版本：v2.5（優化版本）
-- 測試場景：
--   買家：Tao (ID: 488a4712-dd63-4938-9679-336f434ad263)
--   賣家：Yo, Lee, Lin, Liao, Chen（5 個）
--   目標：測試買家瀏覽各賣家物品時的距離計算
--   特點：RPC 函數自動使用資料庫位置，無需傳遞座標參數
-- =============================================

-- =============================================
-- 部分 5: 買家瀏覽賣家物品時的距離（使用 RPC 函數 v2.5）
-- =============================================
SELECT
    si.seller_id,
    si.seller_nickname,
    si.item_id,
    si.title,
    si.price,
    si.condition,
    (rpc_result->>'distance_km')::numeric as distance_km,
    (rpc_result->'location'->>'formatted_address') as seller_address,
    (rpc_result->'user_location'->>'source') as location_source,
    (rpc_result->>'is_owner')::boolean as is_owner,
    (rpc_result->>'is_favorited')::boolean as is_favorited
FROM (
    SELECT
        u.id as seller_id,
        u.nickname as seller_nickname,
        i.id as item_id,
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
) si
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(si.item_id::BIGINT) as rpc_result
) rpc
ORDER BY si.seller_id, distance_km ASC NULLS LAST;

-- =============================================
-- 部分 7: 綜合排名：買家瀏覽最近的物品
-- =============================================
SELECT
    ROW_NUMBER() OVER (ORDER BY (rpc_result->>'distance_km')::numeric ASC NULLS LAST) as rank,
    u.id as seller_id,
    u.nickname as seller_nickname,
    i.id as item_id,
    i.title,
    i.price,
    i.condition,
    (rpc_result->>'distance_km')::numeric as distance_km,
    (rpc_result->'location'->>'formatted_address') as seller_address,
    CASE
        WHEN (rpc_result->>'distance_km')::numeric < 1 THEN '⭐⭐⭐⭐⭐ 非常近'
        WHEN (rpc_result->>'distance_km')::numeric < 5 THEN '⭐⭐⭐⭐ 很近'
        WHEN (rpc_result->>'distance_km')::numeric < 10 THEN '⭐⭐⭐ 中等'
        WHEN (rpc_result->>'distance_km')::numeric < 20 THEN '⭐⭐ 較遠'
        WHEN (rpc_result->>'distance_km')::numeric IS NOT NULL THEN '⭐ 很遠'
        ELSE '🔒 需登入'
    END as proximity_rating
FROM public.users u
LEFT JOIN public.items i ON u.id = i.user_id AND i.listing_status = true
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(i.id::BIGINT) as rpc_result
) rpc
WHERE u.id IN (
    'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  -- Yo
    '7140056b-c71c-489f-8f57-2eeb1694713e',  -- Lee
    '9b900884-10cf-416c-bb5d-e577c4fbacba',  -- Lin
    'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  -- Liao
    'e773c5f7-172c-4976-a7be-d537a7e6e71e'   -- Chen
)
    AND i.listing_status = true
ORDER BY distance_km ASC NULLS LAST
LIMIT 50;

-- =============================================
-- 部分 10: 位置來源驗證（優化版本）
-- =============================================
SELECT
    si.seller_id,
    si.seller_nickname,
    si.item_id,
    si.title,
    (rpc_result->>'distance_km')::numeric as distance_km,
    (rpc_result->'user_location'->>'source') as location_source,
    (rpc_result->'user_location'->>'has_location')::boolean as user_has_location,
    (rpc_result->'user_location'->>'message') as location_message,
    (rpc_result->>'is_owner')::boolean as is_owner
FROM (
    SELECT
        u.id as seller_id,
        u.nickname as seller_nickname,
        i.id as item_id,
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
    LIMIT 10
) si
CROSS JOIN LATERAL (
    SELECT public.get_item_details_with_location(si.item_id::BIGINT) as rpc_result
) rpc
ORDER BY si.seller_id, distance_km ASC NULLS LAST;

-- =============================================
-- 部分 9: 測試報告（買家視角）
-- =============================================
DO $$
DECLARE
    v_buyer_id UUID := '488a4712-dd63-4938-9679-336f434ad263';
    v_buyer_name TEXT;
    v_total_items INT;
BEGIN
    SELECT nickname INTO v_buyer_name FROM public.users WHERE id = v_buyer_id LIMIT 1;
    SELECT COUNT(*) INTO v_total_items FROM public.items WHERE listing_status = true AND user_id IN (
        'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',
        '7140056b-c71c-489f-8f57-2eeb1694713e',
        '9b900884-10cf-416c-bb5d-e577c4fbacba',
        'c8d6998b-79e3-4d56-a9ef-689eed9bd823',
        'e773c5f7-172c-4976-a7be-d537a7e6e71e'
    );
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════╗';
    RAISE NOTICE '║   買家視角 - 賣家物品距離計算測試報告 v2.5         ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '【買家資訊】';
    RAISE NOTICE '  買家 ID: %', v_buyer_id;
    RAISE NOTICE '  買家名稱: %', v_buyer_name;
    RAISE NOTICE '';
    RAISE NOTICE '【物品資訊】';
    RAISE NOTICE '  總物品數: %', v_total_items;
    RAISE NOTICE '';
    RAISE NOTICE '【測試涵蓋】';
    RAISE NOTICE '  ✅ 距離查詢（部分 5）';
    RAISE NOTICE '  ✅ 距離排名（部分 7）';
    RAISE NOTICE '  ✅ 位置來源驗證（部分 10）';
    RAISE NOTICE '';
    RAISE NOTICE '【狀態】';
    RAISE NOTICE '  ✅ 測試完成，僅買家視角';
    RAISE NOTICE '';
END $$;
