-- 創建 RPC 函數來獲取使用者的主要位置
-- 此函數會提取 PostGIS POINT 的經緯度座標

CREATE OR REPLACE FUNCTION get_user_primary_location(p_user_id UUID)
RETURNS TABLE (
  id BIGINT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  type VARCHAR(50),
  is_primary BOOLEAN,
  formatted_address TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    l.id,
    ST_Y(l.coordinates::geometry) AS latitude,
    ST_X(l.coordinates::geometry) AS longitude,
    l.type,
    l.is_primary,
    l.formatted_address,
    l.created_at,
    l.updated_at
  FROM locations l
  WHERE l.user_id = p_user_id
    AND l.is_primary = true
  LIMIT 1;
END;
$$;

-- 設定函數權限
GRANT EXECUTE ON FUNCTION get_user_primary_location(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_primary_location(UUID) TO service_role;

-- 添加註解
COMMENT ON FUNCTION get_user_primary_location(UUID) IS '獲取使用者的主要位置，並將 PostGIS POINT 格式轉換為經緯度';
