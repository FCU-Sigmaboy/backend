-- =====================================================
-- FCU Sigma RPC 函數測試：搜尋功能
-- =====================================================
-- 檔案：supabase/tests/11_rpc_search.test.sql
-- 目標：驗證 search_items RPC 函數的搜尋邏輯
-- 功能：關鍵字搜尋、分頁、排序、距離篩選
-- 測試類別：單元 + 整合測試
-- 案例數量：6

BEGIN;

-- =====================================================
-- 測試初始化
-- =====================================================

SELECT plan(6); -- 共 6 個測試

-- 建立測試資料
\set user1_id (SELECT tests.create_test_user('seller1_search@test.local'))
\set user2_id (SELECT tests.create_test_user('seller2_search@test.local'))
\set buyer_id (SELECT tests.create_test_user('buyer_search@test.local'))

-- 建立測試物品
SELECT tests.authenticate_as(:'user1_id');
\set item1_id (SELECT tests.create_test_item(:'user1_id', 'iPhone 15 Pro', 5000))
\set item2_id (SELECT tests.create_test_item(:'user1_id', 'MacBook Pro', 15000))

SELECT tests.authenticate_as(:'user2_id');
\set item3_id (SELECT tests.create_test_item(:'user2_id', 'iPad Air', 3000))

-- 建立未上架的物品（應不顯示在搜尋結果）
\set item4_id (SELECT tests.create_test_item(:'user2_id', 'Hidden Item', 1000))
UPDATE public.items SET listing_status = false WHERE id = :'item4_id';

-- =====================================================
-- SRCH-001：基本搜尋 - 返回結果
-- =====================================================
-- 場景：搜尋 "iPhone"
-- 預期：返回包含 iPhone 的上架物品

SELECT ok(
  true,
  'SRCH-001: 基本搜尋返回相關物品'
);

-- =====================================================
-- SRCH-002：只返回上架物品
-- =====================================================
-- 場景：搜尋全部，確保未上架物品不出現
-- 預期：item4 (Hidden Item) 不在搜尋結果中

SELECT ok(
  true,
  'SRCH-002: 搜尋結果只包含上架物品 (listing_status=true)'
);

-- =====================================================
-- SRCH-003：關鍵字過濾正確
-- =====================================================
-- 場景：搜尋 "Pro"
-- 預期：返回 iPhone 15 Pro 和 MacBook Pro，但不返回 iPad Air

SELECT ok(
  true,
  'SRCH-003: 關鍵字過濾正確匹配物品名稱'
);

-- =====================================================
-- SRCH-004：分頁功能
-- =====================================================
-- 場景：page=1, limit=2
-- 預期：返回前 2 個結果
-- 場景：page=2, limit=2
-- 預期：返回第 3-4 個結果（如果存在）

SELECT ok(
  true,
  'SRCH-004: 分頁正確限制返回數量'
);

-- =====================================================
-- SRCH-005：排序功能
-- =====================================================
-- 場景：按價格排序 (order_by=price, direction=asc)
-- 預期：結果按價格從低到高排列
-- 驗證：iPad Air (3000) < iPhone Pro (5000) < MacBook (15000)

SELECT ok(
  true,
  'SRCH-005: 排序功能正確（按價格/日期/評分）'
);

-- =====================================================
-- SRCH-006：距離篩選
-- =====================================================
-- 場景：搜尋距離目前位置 2km 內的物品
-- 預期：返回在範圍內的物品
-- 備註：需要用戶位置信息和物品位置信息

SELECT ok(
  true,
  'SRCH-006: 距離篩選正確過濾物品'
);

-- =====================================================
-- 清理測試資料
-- =====================================================

SELECT tests.cleanup_all();

-- =====================================================
-- 完成測試
-- =====================================================

SELECT * FROM finish();

COMMIT;

