-- 測試改進後的地址解析函數
-- 此檔案用於驗證新的正則表達式模式

-- 定義測試用的正則表達式模式（與函數中的模式一致）
DO $$
DECLARE
  test_pattern TEXT := '(台北市|新北市|[台臺]中市|[台臺]南市|高雄市|桃園市|基隆市|新竹市|嘉義市)([^區]+區)|([^縣]+縣)([^鄉鎮市]+[鄉鎮市])';
BEGIN
  -- 測試案例：直轄市 + 區
  RAISE NOTICE '===== 測試直轄市 + 區 =====';
  
  RAISE NOTICE '測試: 台北市信義區';
  RAISE NOTICE '結果: %', regexp_matches('台北市信義區市府路1號', test_pattern);
  
  RAISE NOTICE '測試: 新北市板橋區';
  RAISE NOTICE '結果: %', regexp_matches('新北市板橋區縣民大道2段7號', test_pattern);
  
  RAISE NOTICE '測試: 台中市北屯區';
  RAISE NOTICE '結果: %', regexp_matches('台中市北屯區文心路四段123號', test_pattern);

  RAISE NOTICE '測試: 高雄市鳳山區';
  RAISE NOTICE '結果: %', regexp_matches('高雄市鳳山區光復路二段132號', test_pattern);

  -- 測試案例：縣 + 鄉鎮市
  RAISE NOTICE '===== 測試縣 + 鄉鎮市 =====';
  
  RAISE NOTICE '測試: 彰化縣員林市';
  RAISE NOTICE '結果: %', regexp_matches('彰化縣員林市中山路123號', test_pattern);
  
  RAISE NOTICE '測試: 南投縣草屯鎮';
  RAISE NOTICE '結果: %', regexp_matches('南投縣草屯鎮中正路100號', test_pattern);

  RAISE NOTICE '測試: 苗栗縣竹南鎮';
  RAISE NOTICE '結果: %', regexp_matches('苗栗縣竹南鎮中山路50號', test_pattern);
END $$;

-- 使用實際函數進行測試
\echo ''
\echo '===== 使用 extract_district_from_address 函數測試 ====='

SELECT '台北市信義區市府路1號' as address, 
       public.extract_district_from_address('台北市信義區市府路1號') as district,
       '台北市信義區' as expected;

SELECT '新北市板橋區縣民大道2段7號' as address,
       public.extract_district_from_address('新北市板橋區縣民大道2段7號') as district,
       '新北市板橋區' as expected;

SELECT '台中市北屯區文心路四段123號' as address,
       public.extract_district_from_address('台中市北屯區文心路四段123號') as district,
       '台中市北屯區' as expected;

SELECT '彰化縣員林市中山路123號' as address,
       public.extract_district_from_address('彰化縣員林市中山路123號') as district,
       '彰化縣員林市' as expected;

SELECT '南投縣草屯鎮中正路100號' as address,
       public.extract_district_from_address('南投縣草屯鎮中正路100號') as district,
       '南投縣草屯鎮' as expected;

