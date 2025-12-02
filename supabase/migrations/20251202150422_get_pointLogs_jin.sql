-- ####################################################################
-- ### 查詢點數變動紀錄 (RPC 版)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_point_logs(
    p_log_type TEXT DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20
)
              RETURNS TABLE (
              amount INT,
              type VARCHAR(50),
              description TEXT,
              created_at TIMESTAMPTZ,
              transaction_id BIGINT
              )
              LANGUAGE plpgsql STABLE SECURITY DEFINER
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_offset INT;
BEGIN
    -- 1. 安全檢查
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
END IF;

    -- 2. 計算 offset
v_offset := (p_page - 1) * p_size;

    -- 3. 執行查詢
RETURN QUERY
SELECT
    pl.amount,
    pl.type::VARCHAR(50), -- 確保回傳類型匹配
    pl.description,
    pl.created_at,
    pl.transaction_id
FROM public.point_logs pl
WHERE pl.user_id = v_current_uid -- 核心篩選：只抓自己的紀錄
  AND (p_log_type IS NULL OR pl.type = p_log_type)
ORDER BY pl.created_at DESC
LIMIT p_size
    OFFSET v_offset;
END;
$$;