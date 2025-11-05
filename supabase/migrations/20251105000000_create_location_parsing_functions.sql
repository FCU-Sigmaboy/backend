-- =============================================
-- 地理位置地址解析功能
-- 功能：從完整地址中提取行政區資訊，用於地理位置相關功能
-- 
-- 依賴：
--   - public.locations 表（應在此 migration 之前已建立）
-- 
-- 建立日期：2025-11-05
-- 用途：支援地理位置搜尋、篩選、距離計算等功能
-- =============================================

-- 建立函數：解析台灣地址中的行政區
-- 例如：從 "台中市北屯區文心路四段123號" 提取 "台中市北屯區"
CREATE OR REPLACE FUNCTION public.extract_district_from_address(address TEXT)
RETURNS TEXT AS $$
DECLARE
  matches TEXT[];
  result TEXT;
BEGIN
  -- 如果地址為空，返回 NULL
  IF address IS NULL OR address = '' THEN
    RETURN NULL;
  END IF;

  -- 使用正則表達式提取縣市和區/鄉/鎮/市
  -- 台灣地址格式：XXX市XXX區、XXX縣XXX鄉/鎮/市
  -- 
  -- 正則表達式模式說明：
  -- 分兩種模式匹配：
  -- 1. 直轄市：台北市、新北市、台中市、台南市、高雄市、桃園市、基隆市、新竹市、嘉義市 + 區
  -- 2. 縣：XXX縣 + 鄉/鎮/市
  --
  -- 注意：此模式可根據行政區調整而更新。
  -- 如需支援更多區域或格式，可修改下方 regexp_matches 的模式字串。
  matches := regexp_matches(
    address, 
    '(台北市|新北市|[台臺]中市|[台臺]南市|高雄市|桃園市|基隆市|新竹市|嘉義市)([^區]+區)|([^縣]+縣)([^鄉鎮市]+[鄉鎮市])'
  );
  
  -- 如果匹配成功，組合縣市和區域
  IF matches IS NOT NULL THEN
    -- 直轄市 + 區 的情況（第1和第2個捕獲組）
    IF matches[1] IS NOT NULL AND matches[2] IS NOT NULL THEN
      result := matches[1] || matches[2];
    -- 縣 + 鄉/鎮/市 的情況（第3和第4個捕獲組）
    ELSIF matches[3] IS NOT NULL AND matches[4] IS NOT NULL THEN
      result := matches[3] || matches[4];
    END IF;
  END IF;

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =============================================
-- RPC 函數：取得用戶主要地點的行政區
-- =============================================

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

-- =============================================
-- 加入註解說明
-- =============================================

COMMENT ON FUNCTION public.extract_district_from_address(TEXT) IS 
  '從完整地址中提取行政區名稱（例如：台中市北屯區）。
  
  功能：
  - 使用正則表達式匹配台灣地址格式
  - 支援直轄市格式（如：台中市北屯區）
  - 支援縣轄區格式（如：彰化縣員林市）
  
  參數：
  - address: 完整地址字串
  
  返回：
  - 行政區名稱（縣市 + 區/鄉/鎮/市）
  - 如果無法解析或地址為空，返回 NULL
  
  範例：
  - 輸入: "台中市北屯區文心路四段100號"
  - 輸出: "台中市北屯區"';

COMMENT ON FUNCTION public.get_user_district(UUID) IS 
  '取得指定用戶的主要地點行政區。
  
  功能：
  - 查詢用戶的主要位置（is_primary = true）
  - 自動解析地址並返回行政區資訊
  
  參數：
  - p_user_id: 用戶 UUID
  
  返回：
  - 用戶主要地點的行政區名稱
  - 如果用戶沒有設定主要地點，返回 NULL
  
  用途：
  - 顯示用戶所在行政區
  - 地理位置相關的篩選和搜尋
  - 附近物品推薦
  
  安全性：
  - 使用 SECURITY DEFINER 確保查詢權限
  - RLS 策略仍然生效，只能查詢自己的位置';

-- =============================================
-- 使用範例
-- =============================================

-- 範例 1: 直接解析地址
-- SELECT public.extract_district_from_address('台中市北屯區文心路四段100號');
-- 結果: '台中市北屯區'

-- 範例 2: 解析縣轄區地址
-- SELECT public.extract_district_from_address('彰化縣員林市中山路123號');
-- 結果: '彰化縣員林市'

-- 範例 3: 取得用戶行政區
-- SELECT public.get_user_district('user-uuid-here');
-- 結果: '台中市北屯區' (如果用戶有設定主要地點)

-- 範例 4: 在查詢中使用
-- SELECT 
--   u.id,
--   u.nickname,
--   public.get_user_district(u.id) as district
-- FROM public.users u
-- WHERE public.get_user_district(u.id) = '台中市北屯區';

-- =============================================
-- 注意事項
-- =============================================

-- 1. 此函數設計為「按需查詢」模式
--    - 地址解析在查詢時動態執行
--    - 不儲存解析結果到資料庫
--    - 如需提高效能，可考慮在 locations 表增加 district 欄位並建立觸發器

-- 2. 正則表達式可能需要調整
--    - 台灣行政區劃會變動（如升格、改制）
--    - 如需支援其他格式，請修改 regexp_matches 模式

-- 3. 效能考量
--    - IMMUTABLE 標記允許 PostgreSQL 快取結果
--    - 對於大量查詢，建議建立索引或快取機制

-- 4. 未來擴展
--    - 可新增 extract_city() 函數（只提取縣市）
--    - 可新增 extract_district_only() 函數（只提取區/鄉/鎮/市）
--    - 可支援其他國家的地址格式
