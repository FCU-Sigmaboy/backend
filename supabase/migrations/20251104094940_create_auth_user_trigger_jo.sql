-- 建立觸發器函數：處理新用戶註冊
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_nickname TEXT;
  final_nickname TEXT;
  counter INTEGER := 0;
  max_retries INTEGER := 100;
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
  -- 設定重試上限以防止無限迴圈
  WHILE EXISTS (SELECT 1 FROM public.users WHERE nickname = final_nickname AND id != NEW.id) LOOP
    counter := counter + 1;
    
    -- 檢查是否超過重試上限
    IF counter > max_retries THEN
      RAISE EXCEPTION 'Unable to generate unique nickname after % attempts for base nickname: %', max_retries, base_nickname;
    END IF;
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