-- =============================================
-- OAuth Trigger 測試腳本
-- 此檔案用於測試 OAuth 用戶註冊觸發器的功能
-- =============================================

-- 測試前置條件：確保已執行 20251104094940_create_auth_user_trigger.sql

-- =============================================
-- 測試 1: 檢查觸發器和函數是否存在
-- =============================================
\echo '測試 1: 檢查觸發器和函數是否存在'

SELECT 
  'Trigger exists' as test,
  EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_user_created'
  ) as result;

SELECT 
  'Function handle_new_user exists' as test,
  EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_new_user'
  ) as result;

SELECT 
  'Function extract_district_from_address exists' as test,
  EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'extract_district_from_address'
  ) as result;

SELECT 
  'Function get_user_district exists' as test,
  EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'get_user_district'
  ) as result;

-- =============================================
-- 測試 2: 測試地址解析函數
-- =============================================
\echo ''
\echo '測試 2: 測試地址解析函數'

-- 測試案例 1: 台中市北屯區
SELECT 
  '測試案例 1: 台中市北屯區' as test_case,
  public.extract_district_from_address('台中市北屯區文心路四段123號') as result,
  '台中市北屯區' as expected,
  public.extract_district_from_address('台中市北屯區文心路四段123號') = '台中市北屯區' as passed;

-- 測試案例 2: 台北市信義區
SELECT 
  '測試案例 2: 台北市信義區' as test_case,
  public.extract_district_from_address('台北市信義區市府路1號') as result,
  '台北市信義區' as expected,
  public.extract_district_from_address('台北市信義區市府路1號') = '台北市信義區' as passed;

-- 測試案例 3: 新北市板橋區
SELECT 
  '測試案例 3: 新北市板橋區' as test_case,
  public.extract_district_from_address('新北市板橋區縣民大道2段7號') as result,
  '新北市板橋區' as expected,
  public.extract_district_from_address('新北市板橋區縣民大道2段7號') = '新北市板橋區' as passed;

-- 測試案例 4: 高雄市鳳山區
SELECT 
  '測試案例 4: 高雄市鳳山區' as test_case,
  public.extract_district_from_address('高雄市鳳山區光復路二段132號') as result,
  '高雄市鳳山區' as expected,
  public.extract_district_from_address('高雄市鳳山區光復路二段132號') = '高雄市鳳山區' as passed;

-- 測試案例 5: 台南市東區
SELECT 
  '測試案例 5: 台南市東區' as test_case,
  public.extract_district_from_address('台南市東區大學路1號') as result,
  '台南市東區' as expected,
  public.extract_district_from_address('台南市東區大學路1號') = '台南市東區' as passed;

-- 測試案例 6: 空地址
SELECT 
  '測試案例 6: 空地址' as test_case,
  public.extract_district_from_address('') as result,
  'NULL' as expected,
  public.extract_district_from_address('') IS NULL as passed;

-- 測試案例 7: NULL 地址
SELECT 
  '測試案例 7: NULL 地址' as test_case,
  public.extract_district_from_address(NULL) as result,
  'NULL' as expected,
  public.extract_district_from_address(NULL) IS NULL as passed;

-- =============================================
-- 測試 3: 檢查現有用戶的資料完整性
-- =============================================
\echo ''
\echo '測試 3: 檢查現有用戶的資料完整性'

-- 檢查 auth.users 和 public.users 的對應關係
SELECT 
  '檢查 users 表對應' as test,
  COUNT(*) as auth_users_count,
  (SELECT COUNT(*) FROM public.users) as public_users_count,
  COUNT(*) = (SELECT COUNT(*) FROM public.users) as all_users_synced
FROM auth.users;

-- 檢查 public.users 和 public.profiles 的對應關係
SELECT 
  '檢查 profiles 表對應' as test,
  (SELECT COUNT(*) FROM public.users) as users_count,
  COUNT(*) as profiles_count,
  (SELECT COUNT(*) FROM public.users) = COUNT(*) as all_users_have_profiles
FROM public.profiles;

-- 檢查是否有重複的 nickname
SELECT 
  '檢查重複的 nickname' as test,
  COUNT(*) as duplicate_count,
  COUNT(*) = 0 as no_duplicates
FROM (
  SELECT nickname, COUNT(*) as count
  FROM public.users
  GROUP BY nickname
  HAVING COUNT(*) > 1
) duplicates;

-- =============================================
-- 測試 4: 測試 get_user_district 函數
-- =============================================
\echo ''
\echo '測試 4: 測試 get_user_district 函數'

-- 列出所有有主要地點的用戶及其行政區
SELECT 
  u.id,
  u.nickname,
  l.formatted_address,
  public.get_user_district(u.id) as district
FROM public.users u
LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
WHERE l.id IS NOT NULL
LIMIT 5;

-- =============================================
-- 測試 5: 模擬新用戶註冊（需要在 auth schema 有權限時執行）
-- =============================================
\echo ''
\echo '測試 5: 模擬新用戶註冊'
\echo '注意：此測試需要在具有 auth schema 寫入權限的環境中執行'
\echo '在本地開發環境可以執行，在生產環境應該由 Supabase Auth 自動觸發'

-- 此部分註解掉，因為直接插入 auth.users 可能會有權限問題
-- 在實際測試時，應該使用 Supabase Auth 的 OAuth 流程來觸發

/*
-- 準備測試資料
DO $$
DECLARE
  test_user_id UUID := gen_random_uuid();
BEGIN
  -- 模擬 OAuth 用戶註冊
  INSERT INTO auth.users (
    id,
    email,
    raw_user_meta_data,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at
  ) VALUES (
    test_user_id,
    'test_oauth@example.com',
    jsonb_build_object(
      'name', '測試用戶',
      'picture', 'https://example.com/avatar.jpg'
    ),
    crypt('dummy_password', gen_salt('bf')),
    NOW(),
    NOW(),
    NOW()
  );
  
  -- 檢查是否自動建立了 public.users 記錄
  IF EXISTS (SELECT 1 FROM public.users WHERE id = test_user_id) THEN
    RAISE NOTICE 'SUCCESS: public.users record created automatically';
  ELSE
    RAISE WARNING 'FAILED: public.users record not created';
  END IF;
  
  -- 檢查是否自動建立了 public.profiles 記錄
  IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = test_user_id) THEN
    RAISE NOTICE 'SUCCESS: public.profiles record created automatically';
  ELSE
    RAISE WARNING 'FAILED: public.profiles record not created';
  END IF;
  
  -- 清理測試資料
  DELETE FROM auth.users WHERE id = test_user_id;
  
  RAISE NOTICE 'Test user cleaned up';
END $$;
*/

-- =============================================
-- 測試總結
-- =============================================
\echo ''
\echo '========================================='
\echo '測試總結'
\echo '========================================='
\echo '所有測試已完成。請檢查上述結果：'
\echo '1. 觸發器和函數是否都存在'
\echo '2. 地址解析函數是否正確運作'
\echo '3. 現有用戶資料是否完整'
\echo '4. get_user_district 函數是否正確返回行政區'
\echo ''
\echo '實際的用戶註冊測試需要在前端應用中使用 OAuth 流程進行。'
\echo '========================================='
