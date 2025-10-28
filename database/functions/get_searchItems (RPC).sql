-- ####################################################################
-- ### 物品搜尋 (RPC)
-- ####################################################################

-- *** 已更新為使用使用者主要地點計算距離 ***

CREATE OR REPLACE FUNCTION public.search_items(
    -- *** 移除了 p_user_latitude, p_user_longitude ***

    -- 篩選參數 (全部可選)
    p_distance_range_km INT DEFAULT NULL,
    p_main_category_id INT DEFAULT NULL,
    p_sub_category_id INT DEFAULT NULL,
    p_keyword TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL, -- 用於查看某特定使用者的物品

    -- 分頁與排序
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'created_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
-- 回傳 DTO 保持不變
              RETURNS TABLE (
    item_id BIGINT,
    title TEXT,
    image_url TEXT,
    price INT,
    distance_km NUMERIC,
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    "user" JSON
)
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid(); -- *** 自動獲取當前登入者 ***
v_user_primary_location GEOGRAPHY(Point, 4326);
v_sql TEXT;
v_offset INT;
v_sort_column TEXT;
v_sort_dir TEXT;
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法執行搜尋';
END IF;

  -- 2. *** 新增：查找當前登入者的主要地點 ***
SELECT coordinates INTO v_user_primary_location
FROM public.locations
WHERE user_id = v_current_uid AND is_primary = true
LIMIT 1;

-- (可選) 處理找不到主要地點的情況
IF v_user_primary_location IS NULL THEN
     -- 方案 A: 拋出錯誤
     -- RAISE EXCEPTION '請先設定您的主要地點';
     -- 方案 B: 允許搜尋，但距離相關功能失效 (distance_km 會是 NULL)
     -- (下面的 SQL 查詢會因為 v_user_primary_location 是 NULL 而自動讓 ST_Distance 回傳 NULL)
     RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
END IF;

  -- 3. 處理分頁
v_offset := (p_page - 1) * p_size;

  -- 4. 安全地處理排序參數
v_sort_dir := CASE WHEN p_sort_direction = 'asc' THEN 'ASC' ELSE 'DESC' END;
v_sort_column := CASE
      WHEN p_sort_by = 'distance' AND v_user_primary_location IS NOT NULL THEN 'distance_km' -- 只有找到地點才能按距離排
      WHEN p_sort_by = 'created_at' THEN 'i.created_at'
      WHEN p_sort_by = 'price' THEN 'i.price'
      ELSE 'i.created_at'
END;

  -- 5. 建立基礎查詢 (CTE)
v_sql := '
    WITH items_with_distance AS (
      SELECT
        i.*,
        u.nickname,
        u.profile_picture_url,
        sc.main_category_id,
        l.formatted_address,
        -- *** 修改：使用 v_user_primary_location (參數 $1) 計算距離 ***
        -- 如果 $1 是 NULL，ST_Distance 會回傳 NULL
        ROUND((ST_Distance(i.coordinates, $1) / 1000.0)::numeric, 3) AS distance_km
      FROM
        public.items i
      LEFT JOIN public.users u ON i.user_id = u.id
      LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
      LEFT JOIN public.locations l ON i.user_location_id = l.id
      WHERE
        i.listing_status = TRUE
    )
    SELECT
      id AS item_id,
      title,
      image_urls[1] AS image_url,
      price,
      distance_km, -- *** 距離可能是 NULL ***
      formatted_address,
      created_at,
      updated_at,
      (SELECT COUNT(*) FROM public.favorites f WHERE f.item_id = items_with_distance.id) AS favorites_count,
      json_build_object(
        ''id'', user_id,
        ''nickname'', nickname,
        ''profile_picture_url'', profile_picture_url
      ) AS "user"
    FROM items_with_distance
    WHERE 1=1
  ';

  -- 6. 動態附加 WHERE 條件
  -- *** 修改：距離篩選只有在 v_user_primary_location 存在時才有效 ***
IF p_distance_range_km IS NOT NULL AND v_user_primary_location IS NOT NULL THEN
    v_sql := v_sql || ' AND distance_km <= ' || quote_literal(p_distance_range_km);
END IF;
  -- (其他篩選條件保持不變)
IF p_main_category_id IS NOT NULL THEN
    v_sql := v_sql || ' AND main_category_id = ' || quote_literal(p_main_category_id);
END IF;
IF p_sub_category_id IS NOT NULL THEN
    v_sql := v_sql || ' AND sub_category_id = ' || quote_literal(p_sub_category_id);
END IF;
IF p_user_id IS NOT NULL THEN
    v_sql := v_sql || ' AND user_id = ' || quote_literal(p_user_id);
END IF;
IF p_keyword IS NOT NULL THEN
    v_sql := v_sql || ' AND (title ILIKE ''%'' || ' || quote_literal(p_keyword) || ' || ''%'' OR tags @> ARRAY[' || quote_literal(p_keyword) || '])';
END IF;

  -- 7. 加上排序和分頁
v_sql := v_sql || '
    ORDER BY ' || v_sort_column || ' ' || v_sort_dir || ' NULLS LAST' -- 將 NULL 排在後面
    ' LIMIT ' || quote_literal(p_size) || '
    OFFSET ' || quote_literal(v_offset);

  -- 8. 執行動態 SQL，傳入 $1 參數 (v_user_primary_location)
RETURN QUERY EXECUTE v_sql
    USING v_user_primary_location; -- *** 使用查找到的地點 ***

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;