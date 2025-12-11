-- =====================================================
-- FCU Sigma 測試輔助函數
-- =====================================================
-- 提供測試環境所需的核心助手函數
-- 依照相依性順序定義

BEGIN;

-- 建立測試 schema
CREATE SCHEMA IF NOT EXISTS tests;

-- =====================================================
-- 1. create_test_user() - 核心函數：建立測試用戶
-- =====================================================
-- 目的：在 auth.users 和 public.users/profiles 建立測試用戶
-- 參數：p_email - 測試用戶信箱
-- 回傳：uuid - 建立的用戶 ID

CREATE OR REPLACE FUNCTION tests.create_test_user(p_email text)
RETURNS uuid AS $$
DECLARE
  v_user_id uuid;
  v_nickname text;
BEGIN
  -- 產生 nickname（從 email 提取前綴）
  v_nickname := split_part(p_email, '@', 1) || '_test_' ||
                to_char(now(), 'YYYYMMDDHH24MISS');

  -- 插入到 public.users
  INSERT INTO public.users (id, nickname, email)
  VALUES (gen_random_uuid(), v_nickname, p_email)
  RETURNING id INTO v_user_id;

  -- 為該用戶建立 profiles 記錄
  INSERT INTO public.profiles (id)
  VALUES (v_user_id)
  ON CONFLICT (id) DO NOTHING;

  RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 2. authenticate_as() - 認證模擬：模擬指定用戶登入
-- =====================================================
-- 目的：模擬用戶已認證的狀態，用於 RLS 測試
-- 參數：p_user_id - 要模擬的用戶 ID

CREATE OR REPLACE FUNCTION tests.authenticate_as(p_user_id uuid)
RETURNS void AS $$
BEGIN
  -- 設定 JWT claims，讓 auth.uid() 返回該用戶
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user_id::text,
      'aud', 'authenticated',
      'role', 'authenticated',
      'email', 'test@example.com'
    )::text,
    true -- 僅當前事務有效
  );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. authenticate_as_anon() - 匿名模擬：模擬未登入用戶
-- =====================================================
-- 目的：模擬匿名用戶狀態

CREATE OR REPLACE FUNCTION tests.authenticate_as_anon()
RETURNS void AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'aud', 'unauthenticated',
      'role', 'anon'
    )::text,
    true
  );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 4. create_test_location() - 地點輔助：建立測試地點
-- =====================================================
-- 目的：為測試用戶建立測試地點
-- 參數：p_user_id - 用戶 ID，p_address - 地址
-- 回傳：uuid - 地點 ID

CREATE OR REPLACE FUNCTION tests.create_test_location(
  p_user_id uuid,
  p_address text DEFAULT '台北市信義區'
)
RETURNS uuid AS $$
DECLARE
  v_location_id uuid;
BEGIN
  INSERT INTO public.locations (
    user_id,
    address,
    latitude,
    longitude,
    is_primary
  )
  VALUES (
    p_user_id,
    p_address,
    25.0330,  -- 台北信義區示例座標
    121.5654,
    true
  )
  RETURNING id INTO v_location_id;

  RETURN v_location_id;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. create_test_item() - 物品輔助：建立測試物品
-- =====================================================
-- 目的：為測試用戶建立上架物品
-- 參數：
--   p_user_id - 賣家 ID
--   p_name - 物品名稱
--   p_price - 物品價格（積點）
--   p_category_id - 分類 ID（可選）
-- 回傳：uuid - 物品 ID

CREATE OR REPLACE FUNCTION tests.create_test_item(
  p_user_id uuid,
  p_name text DEFAULT 'Test Item',
  p_price integer DEFAULT 100,
  p_category_id integer DEFAULT 1
)
RETURNS uuid AS $$
DECLARE
  v_item_id uuid;
BEGIN
  INSERT INTO public.items (
    user_id,
    name,
    price,
    category_id,
    listing_status,
    description
  )
  VALUES (
    p_user_id,
    p_name,
    p_price,
    p_category_id,
    true,
    'Test description for ' || p_name
  )
  RETURNING id INTO v_item_id;

  RETURN v_item_id;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. cleanup_all() - 清理函數：清除測試資料
-- =====================================================
-- 目的：清理測試產生的所有資料

CREATE OR REPLACE FUNCTION tests.cleanup_all()
RETURNS void AS $$
BEGIN
  -- 清理測試用戶相關資料（依照外鍵關係順序）
  -- 注意：實際清理順序需根據 database schema 的外鍵約束調整

  DELETE FROM public.transactions
  WHERE giver_id IN (
    SELECT id FROM public.users WHERE email LIKE '%_test_%'
  ) OR receiver_id IN (
    SELECT id FROM public.users WHERE email LIKE '%_test_%'
  );

  DELETE FROM public.items
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE '%_test_%'
  );

  DELETE FROM public.locations
  WHERE user_id IN (
    SELECT id FROM public.users WHERE email LIKE '%_test_%'
  );

  DELETE FROM public.profiles
  WHERE id IN (
    SELECT id FROM public.users WHERE email LIKE '%_test_%'
  );

  DELETE FROM public.users
  WHERE email LIKE '%_test_%';

  -- 重置 auto-increment sequences（如需要）
  -- TRUNCATE TABLE public.items RESTART IDENTITY CASCADE;

END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 輔助函數定義完成
-- =====================================================

COMMIT;

-- =====================================================
-- 測試輔助函數驗證查詢（開發/調試用）
-- =====================================================

-- 驗證 create_test_user
-- SELECT tests.create_test_user('alice@test.local');

-- 驗證 authenticate_as 和 auth.uid()
-- SELECT tests.authenticate_as('<uuid>');
-- SELECT auth.uid();

-- 驗證 create_test_location
-- SELECT tests.create_test_location('<user-uuid>', '台北市信義區');

-- 驗證 create_test_item
-- SELECT tests.create_test_item('<user-uuid>', 'iPhone 15', 500);

-- 驗證 cleanup_all
-- SELECT tests.cleanup_all();

