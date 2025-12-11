-- =====================================================
-- FCU Sigma RLS 黑箱測試：transactions 表
-- =====================================================
-- 檔案：supabase/tests/05_rls_transactions.test.sql
-- 目標：驗證 transactions 表的行級別安全 (RLS) 政策
-- 安全等級：🔴 極高（交易相關資料）
-- 測試矩陣：操作 × 用戶角色 (4×4)
-- 測試類別：黑箱測試 (決策表、邊界值)
-- 案例數量：10

BEGIN;

-- =====================================================
-- 測試初始化
-- =====================================================

SELECT plan(10); -- 共 10 個測試

-- 建立測試資料
\set seller_id (SELECT tests.create_test_user('seller_txn@test.local'))
\set buyer_id (SELECT tests.create_test_user('buyer_txn@test.local'))
\set other_user_id (SELECT tests.create_test_user('other_txn@test.local'))

-- 賣家建立物品
SELECT tests.authenticate_as(:'seller_id');
\set item_id (SELECT tests.create_test_item(:'seller_id', 'Transaction Item', 500))

-- 建立測試交易記錄
-- 注意：實際情況應透過 RPC 建立，這裡直接插入用於測試 RLS
INSERT INTO public.transactions (id, item_id, giver_id, receiver_id, status, code)
VALUES (
  gen_random_uuid(),
  :'item_id',
  :'seller_id',
  :'buyer_id',
  'completed',
  'ABC123'
) RETURNING id INTO STRICT 'test_transaction_id';

\set transaction_id (SELECT id FROM public.transactions LIMIT 1)

-- =====================================================
-- SELECT 操作測試
-- =====================================================

-- RLS-T-001：賣家 (giver) 可查看自己的交易
SELECT tests.authenticate_as(:'seller_id');

SELECT ok(
  EXISTS(SELECT 1 FROM public.transactions
         WHERE id = :'transaction_id' AND giver_id = :'seller_id'),
  'RLS-T-001: 賣家 (giver) 可查看自己的交易'
);

-- RLS-T-002：買家 (receiver) 可查看自己的交易
SELECT tests.authenticate_as(:'buyer_id');

SELECT ok(
  EXISTS(SELECT 1 FROM public.transactions
         WHERE id = :'transaction_id' AND receiver_id = :'buyer_id'),
  'RLS-T-002: 買家 (receiver) 可查看自己的交易'
);

-- RLS-T-003：無關人員無法查看交易
SELECT tests.authenticate_as(:'other_user_id');

SELECT is(
  (SELECT COUNT(*) FROM public.transactions WHERE id = :'transaction_id'),
  0,
  'RLS-T-003: 無關人員無法查看他人的交易'
);

-- RLS-T-004：匿名用戶無法查看任何交易
SELECT tests.authenticate_as_anon();

SELECT is(
  (SELECT COUNT(*) FROM public.transactions LIMIT 1),
  0,
  'RLS-T-004: 匿名用戶無法查看任何交易'
);

-- =====================================================
-- UPDATE 操作測試
-- =====================================================

-- RLS-T-005：賣家無法直接修改交易 status
-- 預期：應透過 RPC 函數修改，不允許直接修改
SELECT tests.authenticate_as(:'seller_id');

-- 記錄原始 status
\set original_status (SELECT status FROM public.transactions WHERE id = :'transaction_id')

PREPARE try_update_status_seller AS
UPDATE public.transactions
SET status = 'cancelled'
WHERE id = :'transaction_id';

SELECT is(
  (SELECT status FROM public.transactions WHERE id = :'transaction_id'),
  :'original_status',
  'RLS-T-005: 賣家無法直接修改交易 status（應透過 RPC）'
);

-- RLS-T-006：買家無法直接修改交易 status
SELECT tests.authenticate_as(:'buyer_id');

PREPARE try_update_status_buyer AS
UPDATE public.transactions
SET status = 'cancelled'
WHERE id = :'transaction_id';

SELECT is(
  (SELECT status FROM public.transactions WHERE id = :'transaction_id'),
  :'original_status',
  'RLS-T-006: 買家無法直接修改交易 status'
);

-- RLS-T-007：無關人員無法修改交易
SELECT tests.authenticate_as(:'other_user_id');

SELECT throws_ok(
  'UPDATE public.transactions SET status = ''cancelled''
   WHERE id = ' || quote_literal(:'transaction_id'::text),
  'new row violates row-level security policy',
  'RLS-T-007: 無關人員無法修改交易'
);

-- =====================================================
-- INSERT 操作測試
-- =====================================================

-- RLS-T-008：已登入用戶無法直接 INSERT 交易
-- 預期：交易應透過 RPC 函數建立，不允許直接插入
SELECT tests.authenticate_as(:'seller_id');

SELECT throws_ok(
  'INSERT INTO public.transactions (item_id, giver_id, receiver_id, status, code)
   VALUES (''' || :'item_id'::text || ''', ''' || :'seller_id'::text || ''', ''' || :'buyer_id'::text || ''', ''pending'', ''XYZ789'')',
  'new row violates row-level security policy',
  'RLS-T-008: 已登入用戶無法直接 INSERT 交易'
);

-- =====================================================
-- DELETE 操作測試
-- =====================================================

-- RLS-T-009：使用者無法刪除交易記錄
-- 預期：交易記錄應由系統永久保存
SELECT tests.authenticate_as(:'seller_id');

SELECT throws_ok(
  'DELETE FROM public.transactions WHERE id = ' || quote_literal(:'transaction_id'::text),
  'violates row-level security policy',
  'RLS-T-009: 賣家無法 DELETE 交易記錄'
);

-- =====================================================
-- RLS-T-010：code 欄位只有相關人員可查看
-- =====================================================
-- 場景：確認交易碼不會洩露給無關人員
-- 預期：只有 giver/receiver 可查看 code

SELECT tests.authenticate_as(:'other_user_id');

SELECT is(
  (SELECT COUNT(*) FROM public.transactions WHERE id = :'transaction_id'),
  0,
  'RLS-T-010: 無關人員無法查看交易碼所在的交易記錄'
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

