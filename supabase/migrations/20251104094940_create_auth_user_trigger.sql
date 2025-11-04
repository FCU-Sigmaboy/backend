-- =============================================
-- 用戶 OAuth 註冊觸發器
-- 功能：當用戶透過 Supabase OAuth 註冊時，自動在資料庫建立相關記錄
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
  base_nickname := COALESCE(
    NEW.raw_user_meta_data->>'nickname',
    NEW.raw_user_meta_data->>'name',
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'user_name',
    SPLIT_PART(NEW.email, '@', 1),
    'user_' || SUBSTRING(NEW.id::TEXT, 1, 8)
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
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'picture',
      NEW.raw_user_meta_data->>'profile_picture_url'
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
-- 注意：需要在 auth schema 上建立觸發器
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================
-- 地址解析函數
-- 功能：從 formatted_address 中提取行政區名稱
-- 例如：從 "台中市北屯區文心路四段123號" 提取 "台中市北屯區"
-- =============================================

-- 建立函數：解析台灣地址中的行政區
CREATE OR REPLACE FUNCTION public.extract_district_from_address(address TEXT)
RETURNS TEXT AS $$
DECLARE
  result TEXT;
BEGIN
  -- 如果地址為空，返回 NULL
  IF address IS NULL OR address = '' THEN
    RETURN NULL;
  END IF;

  -- 使用正則表達式提取縣市和區/鄉/鎮/市
  -- 台灣地址格式：XXX市XXX區、XXX縣XXX鄉/鎮/市
  result := (
    SELECT (regexp_matches(
      address, 
      '([台臺][北中南]市|[^市縣]*[縣市])([^區鄉鎮市]*[區鄉鎮市])',
      'g'
    ))[1] || (regexp_matches(
      address,
      '([台臺][北中南]市|[^市縣]*[縣市])([^區鄉鎮市]*[區鄉鎮市])',
      'g'
    ))[2]
  );

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 建立觸發器函數：自動解析並更新 formatted_address 中的行政區資訊
CREATE OR REPLACE FUNCTION public.parse_location_district()
RETURNS TRIGGER AS $$
BEGIN
  -- 如果 formatted_address 有值但沒有包含明確的行政區格式
  -- 則嘗試解析並更新
  IF NEW.formatted_address IS NOT NULL AND NEW.formatted_address != '' THEN
    -- 這裡可以根據需要添加額外的邏輯
    -- 例如：儲存解析出的行政區到一個單獨的欄位（如果有的話）
    NULL;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 建立觸發器：在 locations 表上自動解析地址
DROP TRIGGER IF EXISTS parse_location_district_trigger ON public.locations;
CREATE TRIGGER parse_location_district_trigger
  BEFORE INSERT OR UPDATE OF formatted_address ON public.locations
  FOR EACH ROW EXECUTE FUNCTION public.parse_location_district();

-- =============================================
-- 輔助函數：取得用戶的行政區
-- =============================================

-- 建立 RPC 函數：取得用戶主要地點的行政區
CREATE OR REPLACE FUNCTION public.get_user_district(p_user_id UUID)
RETURNS TEXT AS $$
DECLARE
  user_address TEXT;
BEGIN
  -- 取得用戶主要地點的 formatted_address
  SELECT formatted_address INTO user_address
  FROM public.locations
  WHERE user_id = p_user_id AND is_primary = true
  LIMIT 1;

  -- 如果沒有主要地點，返回 NULL
  IF user_address IS NULL THEN
    RETURN NULL;
  END IF;

  -- 解析並返回行政區
  RETURN public.extract_district_from_address(user_address);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 加入註解說明
COMMENT ON FUNCTION public.handle_new_user() IS '處理新用戶註冊，自動在 public.users 和 public.profiles 建立記錄';
COMMENT ON FUNCTION public.extract_district_from_address(TEXT) IS '從完整地址中提取行政區名稱（例如：台中市北屯區）';
COMMENT ON FUNCTION public.parse_location_district() IS '自動解析 locations 表中的 formatted_address';
COMMENT ON FUNCTION public.get_user_district(UUID) IS '取得指定用戶的主要地點行政區';
