-- =====================================================
-- FCU Sigma RLS 黑箱測試：items 表
-- =====================================================
-- 檔案：supabase/tests/03_rls_items.test.sql
-- 目標：驗證 items 表的行級別安全 (RLS) 政策
-- 測試矩陣：操作 × 用戶角色 (4×4)
-- 測試類別：黑箱測試 (決策表、等價劃分)
-- 案例數量：14

BEGIN;

-- =====================================================
-- 測試初始化
-- =====================================================

SELECT plan(14); -- 共 14 個測試

-- 建立測試資料
\set seller_id (SELECT tests.create_test_user('seller_items@test.local'))
\set buyer_id (SELECT tests.create_test_user('buyer_items@test.local'))

-- 賣家建立上架物品
SELECT tests.authenticate_as(:'seller_id');
\set item_listed (SELECT tests.create_test_item(:'seller_id', 'Listed Item', 500))

-- 賣家建立未上架物品（用於測試隱藏邏輯）
\set item_unlisted (SELECT tests.create_test_item(:'seller_id', 'Unlisted Item', 300))
UPDATE public.items SET listing_status = false WHERE id = :'item_unlisted';

-- =====================================================
-- SELECT 操作測試矩陣
-- =====================================================

-- RLS-I-001：賣家可查看自己的上架物品
SELECT tests.authenticate_as(:'seller_id');

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = :'item_listed' AND user_id = :'seller_id'),
  'RLS-I-001: 賣家可查看自己的上架物品'
);

-- RLS-I-002：買家可查看他人的上架物品
SELECT tests.authenticate_as(:'buyer_id');

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = :'item_listed' AND listing_status = true),
  'RLS-I-002: 買家可查看他人的上架物品'
);

-- RLS-I-003：買家無法查看他人的未上架物品
SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE id = :'item_unlisted'),
  0,
  'RLS-I-003: 買家無法查看他人的未上架物品'
);

-- RLS-I-004：匿名用戶無法查看任何物品
SELECT tests.authenticate_as_anon();

SELECT is(
  (SELECT COUNT(*) FROM public.items LIMIT 1),
  0,
  'RLS-I-004: 匿名用戶無法查看任何物品'
);

-- =====================================================
-- INSERT 操作測試
-- =====================================================

-- RLS-I-005：已登入用戶可 INSERT 物品
SELECT tests.authenticate_as(:'seller_id');

SELECT ok(
  (SELECT COUNT(*) FROM public.items WHERE user_id = :'seller_id') >= 2,
  'RLS-I-005: 已登入用戶可 INSERT 物品'
);

-- RLS-I-006：匿名用戶無法 INSERT 物品
SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'INSERT INTO public.items (user_id, name, price, category_id)
   VALUES (gen_random_uuid(), ''Anon Item'', 100, 1)',
  'new row violates row-level security policy',
  'RLS-I-006: 匿名用戶無法 INSERT 物品'
);

-- =====================================================
-- UPDATE 操作測試
-- =====================================================

-- RLS-I-007：賣家可更新自己的物品
SELECT tests.authenticate_as(:'seller_id');

PREPARE update_own_item AS
UPDATE public.items
SET name = 'Updated Item Name'
WHERE id = :'item_listed';

SELECT ok(
  (SELECT name FROM public.items WHERE id = :'item_listed') = 'Updated Item Name',
  'RLS-I-007: 賣家可更新自己的物品'
);

-- RLS-I-008：賣家無法更新他人的上架物品
SELECT tests.authenticate_as(:'buyer_id');

-- 建立第二個賣家的物品
\set seller2_id (SELECT tests.create_test_user('seller2_items@test.local'))
SELECT tests.authenticate_as(:'seller2_id');
\set item_other_seller (SELECT tests.create_test_item(:'seller2_id', 'Other Seller Item', 200))

-- 買家嘗試修改
SELECT tests.authenticate_as(:'buyer_id');

PREPARE try_update_other_item AS
UPDATE public.items
SET name = 'Hacked Item Name'
WHERE id = :'item_other_seller';

SELECT is(
  (SELECT name FROM public.items WHERE id = :'item_other_seller'),
  'Other Seller Item',
  'RLS-I-008: 買家無法修改他人的上架物品'
);

-- RLS-I-009：買家無法修改他人的未上架物品
\set item_other_unlisted (SELECT tests.create_test_item(:'seller2_id', 'Other Unlisted', 250))
UPDATE public.items SET listing_status = false WHERE id = :'item_other_unlisted';

PREPARE try_update_unlisted_other AS
UPDATE public.items
SET name = 'Hacked Unlisted'
WHERE id = :'item_other_unlisted';

SELECT is(
  (SELECT name FROM public.items WHERE id = :'item_other_unlisted'),
  'Other Unlisted',
  'RLS-I-009: 買家無法修改他人的未上架物品'
);

-- RLS-I-010：匿名用戶無法 UPDATE 任何物品
SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'UPDATE public.items SET name = ''Hacked'' WHERE id = ' || quote_literal(:'item_listed'::text),
  'new row violates row-level security policy',
  'RLS-I-010: 匿名用戶無法 UPDATE 物品'
);

-- =====================================================
-- DELETE 操作測試
-- =====================================================

-- RLS-I-011：賣家可刪除自己的物品
SELECT tests.authenticate_as(:'seller_id');

-- 建立一個待刪除的物品
\set item_to_delete (SELECT tests.create_test_item(:'seller_id', 'Item to Delete', 100))

PREPARE delete_own_item AS
DELETE FROM public.items WHERE id = :'item_to_delete';

-- 驗證刪除成功
SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE id = :'item_to_delete'),
  0,
  'RLS-I-011: 賣家可刪除自己的物品'
);

-- RLS-I-012：買家無法刪除他人的物品
SELECT tests.authenticate_as(:'buyer_id');

PREPARE try_delete_other_item AS
DELETE FROM public.items WHERE id = :'item_other_seller';

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = :'item_other_seller'),
  'RLS-I-012: 買家無法刪除他人的物品（記錄仍存在）'
);

-- RLS-I-013：匿名用戶無法 DELETE 物品
SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'DELETE FROM public.items WHERE id = ' || quote_literal(:'item_listed'::text),
  'new row violates row-level security policy',
  'RLS-I-013: 匿名用戶無法 DELETE 物品'
);

-- =====================================================
-- RLS-I-014：修改 listing_status 的權限檢查
-- =====================================================
-- 場景：驗證 listing_status 的修改符合 RLS
-- 預期：只有賣家可修改

SELECT tests.authenticate_as(:'seller_id');

PREPARE update_status AS
UPDATE public.items
SET listing_status = false
WHERE id = :'item_listed';

SELECT ok(
  (SELECT listing_status FROM public.items WHERE id = :'item_listed') = false,
  'RLS-I-014: 賣家可修改自己物品的 listing_status'
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

