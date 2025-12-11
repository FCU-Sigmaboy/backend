-- =====================================================
-- FCU Sigma RLS 黑箱測試：profiles 表
-- =====================================================
-- 檔案：supabase/tests/02_rls_profiles.test.sql
-- 目標：驗證 profiles 表的行級別安全 (RLS) 政策
-- 安全等級：🔴 極高（涉及用戶積點/餘額）
-- 測試類別：黑箱測試 (等價劃分、邊界值)
-- 案例數量：8

BEGIN;

-- =====================================================
-- 測試初始化
-- =====================================================

SELECT plan(8); -- 共 8 個測試

-- 建立測試資料
\set user_a_id (SELECT tests.create_test_user('alice_profiles@test.local'))
\set user_b_id (SELECT tests.create_test_user('bob_profiles@test.local'))

-- =====================================================
-- RLS-P-001：用戶只能查看自己的餘額
-- =====================================================
-- 場景：UserA 登入後查詢自己的 balance
-- 預期結果：可見
-- 安全重要性：🔴 極高

SELECT tests.authenticate_as(:'user_a_id');

SELECT ok(
  (SELECT balance FROM public.profiles WHERE id = :'user_a_id') IS NOT NULL,
  'RLS-P-001: 用戶可查看自己的 balance'
);

-- =====================================================
-- RLS-P-002：用戶無法查看他人的餘額
-- =====================================================
-- 場景：UserA 嘗試查詢 UserB 的 balance
-- 預期結果：查詢無結果
-- 安全重要性：🔴 極高

SELECT is(
  (SELECT COUNT(*) FROM public.profiles WHERE id = :'user_b_id'),
  0,
  'RLS-P-002: 已登入用戶無法查看他人的 balance'
);

-- =====================================================
-- RLS-P-003：無法直接修改 balance
-- =====================================================
-- 場景：嘗試直接 UPDATE balance（應由交易 RPC 管理）
-- 預期結果：更新失敗或無影響
-- 安全重要性：🔴 極高（防止點數作弊）

SELECT tests.authenticate_as(:'user_a_id');

-- 記錄原始餘額
\set original_balance (SELECT balance FROM public.profiles WHERE id = :'user_a_id')

PREPARE try_update_balance AS
UPDATE public.profiles
SET balance = 999999
WHERE id = :'user_a_id';

-- 驗證餘額未被修改
SELECT is(
  (SELECT balance FROM public.profiles WHERE id = :'user_a_id'),
  :'original_balance',
  'RLS-P-003: 用戶無法直接修改自己的 balance'
);

-- =====================================================
-- RLS-P-004：無法直接修改 carbon_saved
-- =====================================================
-- 場景：嘗試直接修改 carbon_saved（應由交易系統計算）
-- 預期結果：更新失敗或無影響
-- 安全重要性：🟡 高

SELECT tests.authenticate_as(:'user_a_id');

-- 記錄原始值
\set original_carbon (SELECT carbon_saved_kg FROM public.profiles WHERE id = :'user_a_id')

PREPARE try_update_carbon AS
UPDATE public.profiles
SET carbon_saved_kg = 9999.99
WHERE id = :'user_a_id';

-- 驗證值未被修改
SELECT is(
  (SELECT carbon_saved_kg FROM public.profiles WHERE id = :'user_a_id'),
  :'original_carbon',
  'RLS-P-004: 用戶無法直接修改 carbon_saved_kg'
);

-- =====================================================
-- RLS-P-005：匿名用戶無法 INSERT profiles
-- =====================================================
-- 場景：未登入用戶嘗試插入 profiles 記錄
-- 預期結果：拋出權限錯誤

SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'INSERT INTO public.profiles (id, balance) VALUES (gen_random_uuid(), 0)',
  'new row violates row-level security policy',
  'RLS-P-005: 匿名用戶無法 INSERT profiles 記錄'
);

-- =====================================================
-- RLS-P-006：已登入用戶無法 UPDATE 他人的 profiles
-- =====================================================
-- 場景：UserA 嘗試更新 UserB 的 profiles
-- 預期結果：更新失敗

SELECT tests.authenticate_as(:'user_a_id');

-- 記錄 UserB 原始値
\set user_b_original_balance (SELECT balance FROM public.profiles WHERE id = :'user_b_id')

PREPARE try_update_other_profile AS
UPDATE public.profiles
SET balance = 999999
WHERE id = :'user_b_id';

-- 驗證 UserB 的 balance 未被修改
SELECT is(
  (SELECT balance FROM public.profiles WHERE id = :'user_b_id'),
  COALESCE(:'user_b_original_balance'::bigint, 0),
  'RLS-P-006: 用戶無法修改他人的 profiles'
);

-- =====================================================
-- RLS-P-007：用戶無法 DELETE 自己的 profiles
-- =====================================================
-- 場景：防止用戶刪除自己的 profiles 記錄
-- 預期結果：拋出權限錯誤

SELECT tests.authenticate_as(:'user_a_id');

SELECT throws_ok(
  'DELETE FROM public.profiles WHERE id = ' || quote_literal(:'user_a_id'::text),
  'violates row-level security policy',
  'RLS-P-007: 用戶無法 DELETE 自己的 profiles 記錄'
);

-- =====================================================
-- RLS-P-008：匿名用戶無法查看任何 profiles
-- =====================================================
-- 場景：未登入用戶查詢 profiles 表
-- 預期結果：查詢無結果

SELECT tests.authenticate_as_anon();

SELECT is(
  (SELECT COUNT(*) FROM public.profiles LIMIT 1),
  0,
  'RLS-P-008: 匿名用戶無法查看任何 profiles 記錄'
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

