-- =============================================
-- 用戶 OAuth 註冊觸發器
-- 功能：當用戶透過 Supabase OAuth 註冊時，自動在資料庫建立相關記錄
-- 
-- 依賴：
--   - auth.users (Supabase Auth schema)
--   - public.users
--   - public.profiles
-- 
-- 建立日期：2025-11-04
-- 最後修改：2025-11-05 (拆分地址解析功能至獨立 migration)
-- =============================================

-- 建立觸發器函數：處理新用戶註冊
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_nickname TEXT;
  final_nickname TEXT;
  counter INTEGER := 0;
BEGIN
  -- 提取基礎暱稱
  -- 嘗試從多個可能的 OAuth metadata 欄位中提取
  base_nickname := COALESCE(
    NEW.raw_user_meta_data->>'nickname',     -- Twitter, GitHub
    NEW.raw_user_meta_data->>'name',         -- Google, GitHub
    NEW.raw_user_meta_data->>'full_name',    -- Facebook
    NEW.raw_user_meta_data->>'user_name',    -- Generic
    SPLIT_PART(NEW.email, '@', 1),           -- Email fallback
    'user_' || SUBSTRING(NEW.id::TEXT, 1, 8) -- UUID fallback
  );
  
  final_nickname := base_nickname;
  
  -- 確保 nickname 唯一性：如果有衝突，添加數字後綴
  WHILE EXISTS (SELECT 1 FROM public.users WHERE nickname = final_nickname AND id != NEW.id) LOOP
    counter := counter + 1;
    final_nickname := base_nickname || '_' || counter;
  END LOOP;

  -- 在 public.users 表中建立用戶基本資料
  INSERT INTO public.users (id, nickname, profile_picture_url, created_at, updated_at)
  VALUES (
    NEW.id,
    final_nickname,
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',          -- GitHub
      NEW.raw_user_meta_data->>'picture',             -- Google
      NEW.raw_user_meta_data->>'profile_picture_url'  -- Facebook
    ),
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    nickname = EXCLUDED.nickname,
    profile_picture_url = COALESCE(EXCLUDED.profile_picture_url, public.users.profile_picture_url),
    updated_at = NOW();

  -- 在 public.profiles 表中建立用戶詳細資料
  INSERT INTO public.profiles (user_id, balance, carbon_saved_kg, created_at, updated_at)
  VALUES (
    NEW.id,
    0,      -- 初始點數為 0
    0.00,   -- 初始減碳量為 0
    NOW(),
    NOW()
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 建立觸發器：在 auth.users 表上監聽新用戶插入
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 加入註解說明
COMMENT ON FUNCTION public.handle_new_user() IS 
  '處理新用戶 OAuth 註冊，自動在 public.users 和 public.profiles 建立初始記錄。
  
  功能：
  - 從 OAuth metadata 提取 nickname 和頭像
  - 自動處理 nickname 重複（添加數字後綴）
  - 初始化用戶 profile（balance=0, carbon_saved_kg=0）
  - 支援多種 OAuth provider（Google, GitHub, Facebook 等）
  
  觸發時機：當用戶透過 OAuth 首次登入時自動執行';

COMMENT ON TRIGGER on_auth_user_created ON auth.users IS
  '當用戶透過 OAuth 註冊時，自動建立用戶基本資料和 profile。
  此觸發器確保每個 auth.users 記錄都有對應的 public.users 和 public.profiles 記錄。';
