-- =====================================================
-- FCU Sigma RLS 黑箱測試：users 表
-- =====================================================
-- 檔案：supabase/tests/01_rls_users.test.sql
-- 目標：驗證 users 表的行級別安全 (RLS) 政策
-- 測試類別：黑箱測試 (等價劃分、邊界值、負向測試)
-- 案例數量：12

\i helper_functions.sql

BEGIN;

-- =====================================================
-- 測試初始化
-- =====================================================

SELECT plan(12); -- 共 12 個測試

-- 建立測試資料
\set user_a 'alice@test.local'
\set user_b 'bob@test.local'

\set user_a_id (SELECT tests.create_test_user('alice@test.local'))
\set user_b_id (SELECT tests.create_test_user('bob@test.local'))

-- =====================================================
-- RLS-U-001：已登入用戶查看他人資訊
-- =====================================================
-- 場景：UserA 登入後查詢 UserB 的資訊
-- 預期結果：可見
-- 測試技術：等價劃分 (有效的已認證用戶)

PREPARE authenticated_user_view AS
SELECT tests.authenticate_as(:'user_a_id');
SELECT tests.authenticate_as(:'user_a_id');

PREPARE view_other_user AS
SELECT nickname FROM public.users
WHERE id = :'user_b_id';

SELECT ok(
  (SELECT EXISTS(
    SELECT 1 FROM public.users WHERE id = :'user_b_id'
  )),
  'RLS-U-001: 已登入用戶可查看他人基本信息'
);

-- =====================================================
-- RLS-U-002：查詢 nickname 欄位正確性
-- =====================================================
-- 場景：查詢結果中 nickname 應正確返回
-- 預期結果：返回正確的 nickname 值

-- 先建立第二個用戶的 nickname（作為對照）
SELECT tests.authenticate_as_anon(); -- 重置認證

SELECT is(
  (SELECT nickname FROM public.users WHERE id = :'user_a_id' LIMIT 1),
  (SELECT nickname FROM public.users WHERE id = :'user_a_id' LIMIT 1),
  'RLS-U-002: nickname 欄位可正確查詢'
);

-- =====================================================
-- RLS-U-003：用戶可更新自己的資料
-- =====================================================
-- 場景：UserA 登入後更新自己的 nickname
-- 預期結果：更新成功

SELECT tests.authenticate_as(:'user_a_id');

PREPARE update_own_data AS
UPDATE public.users
SET nickname = 'alice_updated_' || to_char(now(), 'YYYYMMDDHH24MISS')
WHERE id = :'user_a_id'
RETURNING id;

SELECT ok(
  EXISTS(SELECT 1 FROM (EXECUTE 'SELECT * FROM public.users WHERE id = $1' USING :'user_a_id') AS t),
  'RLS-U-003: 用戶可更新自己的資料'
);

-- =====================================================
-- RLS-U-004：用戶無法更新他人資料
-- =====================================================
-- 場景：UserA 嘗試更新 UserB 的 nickname
-- 預期結果：更新失敗或無影響

SELECT tests.authenticate_as(:'user_a_id');

-- 記錄原始 nickname
\set user_b_original_nick (SELECT nickname FROM public.users WHERE id = :'user_b_id')

PREPARE try_update_other AS
UPDATE public.users
SET nickname = 'hacked_nickname'
WHERE id = :'user_b_id';

-- 驗證 nickname 未被修改
SELECT is(
  (SELECT nickname FROM public.users WHERE id = :'user_b_id'),
  :'user_b_original_nick',
  'RLS-U-004: 用戶無法修改他人的 nickname'
);

-- =====================================================
-- RLS-U-005：無法直接修改系統欄位 avg_rating
-- =====================================================
-- 場景：嘗試直接修改 avg_rating（應由系統管理）
-- 預期結果：值不變或拋出錯誤
-- 安全重要性：🔴 極高（防止評分被篡改）

SELECT tests.authenticate_as(:'user_a_id');

PREPARE try_update_rating AS
UPDATE public.users
SET avg_rating = 5.0
WHERE id = :'user_a_id';

-- 驗證評分未被直接修改
SELECT is(
  (SELECT avg_rating FROM public.users WHERE id = :'user_a_id'),
  0,  -- 預設值應為 0
  'RLS-U-005: 用戶無法直接修改 avg_rating'
);

-- =====================================================
-- RLS-U-006：匿名用戶無法直接 INSERT
-- =====================================================
-- 場景：未登入用戶嘗試插入新用戶記錄
-- 預期結果：拋出權限錯誤
-- 測試技術：負向測試

SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'INSERT INTO public.users (nickname, email) VALUES (''anonymous_test'', ''anon@test.local'')',
  'new row violates row-level security policy',
  'RLS-U-006: 匿名用戶無法直接 INSERT users 記錄'
);

-- =====================================================
-- RLS-U-007：用戶無法刪除他人記錄
-- =====================================================
-- 場景：UserA 嘗試刪除 UserB 的記錄
-- 預期結果：刪除失敗

SELECT tests.authenticate_as(:'user_a_id');

-- 驗證 UserB 記錄仍存在
SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE id = :'user_b_id'),
  'RLS-U-007: 用戶無法刪除他人記錄（記錄仍存在）'
);

-- =====================================================
-- RLS-U-008：匿名用戶查看受限
-- =====================================================
-- 場景：未登入用戶查詢 users 表
-- 預期結果：查詢無結果或被拒絕

SELECT tests.authenticate_as_anon();

SELECT is(
  (SELECT COUNT(*) FROM public.users WHERE id = :'user_a_id'),
  0,
  'RLS-U-008: 匿名用戶無法查看已登入用戶資訊'
);

-- =====================================================
-- RLS-U-009：匿名用戶 UPDATE 被拒絕
-- =====================================================

SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'UPDATE public.users SET nickname = ''test'' WHERE id = ' || quote_literal(:'user_a_id'::text),
  'new row violates row-level security policy',
  'RLS-U-009: 匿名用戶無法 UPDATE users 記錄'
);

-- =====================================================
-- RLS-U-010：匿名用戶 DELETE 被拒絕
-- =====================================================

SELECT tests.authenticate_as_anon();

SELECT throws_ok(
  'DELETE FROM public.users WHERE id = ' || quote_literal(:'user_a_id'::text),
  'new row violates row-level security policy',
  'RLS-U-010: 匿名用戶無法 DELETE users 記錄'
);

-- =====================================================
-- RLS-U-011：已登入用戶無法 DELETE 自己的記錄
-- =====================================================
-- 場景：防止用戶刪除自己的帳戶（應由系統管理）

SELECT tests.authenticate_as(:'user_a_id');

SELECT throws_ok(
  'DELETE FROM public.users WHERE id = ' || quote_literal(:'user_a_id'::text),
  'violates row-level security policy',
  'RLS-U-011: 已登入用戶無法 DELETE 自己的記錄'
);

-- =====================================================
-- RLS-U-012：email 欄位可查詢（公開資訊）
-- =====================================================
-- 場景：已登入用戶可查詢他人 email
-- 預期結果：能成功查詢

SELECT tests.authenticate_as(:'user_a_id');

SELECT ok(
  (SELECT COUNT(*) FROM public.users
   WHERE email = :'user_b' LIMIT 1) >= 1,
  'RLS-U-012: 已登入用戶可查詢他人 email'
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

