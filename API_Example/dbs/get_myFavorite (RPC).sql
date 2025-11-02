-- ####################################################################
-- ### 我的收藏 (RPC) - 與 search_items 結構相同  *** 已更新為自動獲取位置 ***
-- ####################################################################

-- 步驟 1: (必須) 刪除舊函式，因為我們要變更 "參數"
DROP FUNCTION IF EXISTS public.get_my_favorite_items(DOUBLE PRECISION, DOUBLE PRECISION, INT, INT, TEXT, TEXT);

-- 步驟 2: 建立新函式 (不再需要 p_user_latitude/p_user_longitude 參數)
CREATE OR REPLACE FUNCTION public.get_my_favorite_items(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'favorited_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
-- 回傳 DTO 與 search_items 幾乎相同 (多了 favorited_at)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    image_url TEXT,
    price INT,
    distance_km NUMERIC,
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    favorited_at TIMESTAMPTZ,
    "user" JSON
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
v_current_uid UUID := auth.uid();
  v_user_primary_location GEOGRAPHY(Point,4326);
  v_offset INT;
  v_sort_column TEXT;
  v_sort_dir TEXT;
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. *** 新增：獲取當前登入者的主要地點 (與 search_items 相同) ***
SELECT coordinates INTO v_user_primary_location
FROM public.locations
WHERE user_id = v_current_uid AND is_primary = true
    LIMIT 1;

IF v_user_primary_location IS NULL THEN
    RAISE NOTICE '找不到使用者的主要地點，距離計算將不可用';
END IF;

  -- 3. 計算 offset
  v_offset := (p_page - 1) * p_size;

  -- 4. 安全處理排序參數
  v_sort_dir := CASE WHEN p_sort_direction = 'asc' THEN 'ASC' ELSE 'DESC' END;
  v_sort_column := CASE
      WHEN p_sort_by = 'distance' AND v_user_primary_location IS NOT NULL THEN 'distance_km'
      WHEN p_sort_by = 'created_at' THEN 'i.created_at' -- 指 items.created_at
      WHEN p_sort_by = 'price' THEN 'i.price'
      WHEN p_sort_by = 'favorited_at' THEN 'fav.created_at' -- 指 favorites.created_at
      ELSE 'fav.created_at' -- 預設用收藏時間排序
END;

  -- 5. 建立基礎查詢 (CTE)
  --    這個查詢從 favorites 表開始 JOIN
RETURN QUERY
    WITH favorite_items AS (
      SELECT
        fav.created_at AS favorited_at, -- 收藏時間
        i.*,
        u.nickname,
        u.profile_picture_url,
        l.formatted_address,
        -- *** 更新：使用 v_user_primary_location 計算距離 ***
        ROUND((ST_Distance(l.coordinates, v_user_primary_location) / 1000.0)::numeric, 3) AS distance_km,
        (SELECT COUNT(*) FROM public.favorites f_count WHERE f_count.item_id = i.id) AS favorites_count
      FROM
        public.favorites fav
      JOIN public.items i ON fav.item_id = i.id
      LEFT JOIN public.users u ON i.user_id = u.id
      LEFT JOIN public.locations l ON i.location_id = l.id
      WHERE
        fav.user_id = v_current_uid -- *** 只抓目前登入者的收藏 ***
        AND i.listing_status = TRUE -- (可選) 只顯示還在上架的收藏
    )
-- 從 CTE 中組裝最終 DTO
SELECT
    fi.id AS item_id,
    fi.title,
    fi.image_urls[1] AS image_url,
    fi.price,
    fi.distance_km,
    fi.formatted_address,
    fi.created_at,
    fi.updated_at,
    fi.favorites_count,
    fi.favorited_at,
    json_build_object(
            'id', fi.user_id,
            'nickname', fi.nickname,
            'profile_picture_url', fi.profile_picture_url
    ) AS "user"
FROM favorite_items fi
-- 6. 加上排序和分頁
ORDER BY
    v_sort_column || ' ' || v_sort_dir || ' NULLS LAST'
    LIMIT p_size
OFFSET v_offset;

END;
$$;