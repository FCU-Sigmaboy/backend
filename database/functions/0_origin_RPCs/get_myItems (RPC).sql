CREATE OR REPLACE FUNCTION public.get_my_items(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'created_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
-- *** 修正 42804：將 condition TEXT 改為 VARCHAR(20) ***
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    image_url TEXT,
    price INT,
    listing_status BOOLEAN,
    --condition VARCHAR(20), -- *** 修正 *** (匹配 items.condition 類型)
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
v_current_uid UUID := auth.uid();
  v_offset INT;
  v_sort_column TEXT;
  v_sort_dir TEXT;
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法獲取個人物品';
END IF;

  -- 2. 計算 offset
  v_offset := (p_page - 1) * p_size;

  -- 3. 安全處理排序參數
  v_sort_dir := CASE WHEN p_sort_direction = 'asc' THEN 'ASC' ELSE 'DESC' END;
  v_sort_column := CASE 
      WHEN p_sort_by = 'price' THEN 'i.price'
      WHEN p_sort_by = 'updated_at' THEN 'i.updated_at'
      ELSE 'i.created_at' -- 預設
END;

  -- 4. 執行查詢
RETURN QUERY
SELECT
    i.id AS item_id,
    i.title,
    i.image_urls[1] AS image_url,
    i.price,
    i.listing_status,
    -- i.condition, -- *** 修正 *** (移除 ::TEXT 轉換)
    i.created_at,
    i.updated_at,
    -- *** 核心：計算收藏數 ***
    (SELECT count(*) FROM public.favorites f WHERE f.item_id = i.id) AS favorites_count
FROM
    public.items i
WHERE
    i.user_id = v_current_uid -- *** 核心：只抓 "我的" ***
ORDER BY
    v_sort_column || ' ' || v_sort_dir
    LIMIT p_size
OFFSET v_offset;

END;
$$;
