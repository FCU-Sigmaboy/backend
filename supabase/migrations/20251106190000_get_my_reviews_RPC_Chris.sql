-- ####################################################################
-- ### 獲取我的評價列表 (RPC)
-- ### Author: Chris
-- ### Date: 2025-11-06
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_my_reviews(
    p_page INT DEFAULT 1,                        -- 頁碼，預設為 1
    p_page_size INT DEFAULT 20,                  -- 每頁數量，預設為 20
    p_sort_by TEXT DEFAULT 'created_at',         -- 排序欄位：'created_at', 'score'
    p_sort_direction TEXT DEFAULT 'desc'         -- 排序方向：'asc', 'desc'
)
RETURNS TABLE (
    review_id BIGINT,
    reviewer_id UUID,
    reviewer_nickname TEXT,
    reviewer_avatar TEXT,
    score SMALLINT,
    comment TEXT,
    created_at TIMESTAMPTZ,
    transaction_id BIGINT,
    item_id BIGINT,
    item_title TEXT,
    item_image TEXT
)
AS $$
DECLARE
    v_current_user_id UUID := auth.uid();        -- 當前登入用戶 ID
    v_offset INT;                                -- 分頁偏移量
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法獲取評價列表';
    END IF;

    -- 2. 計算分頁偏移量
    v_offset := (p_page - 1) * p_page_size;

    -- 3. 查詢我收到的評價列表
    RETURN QUERY
    SELECT
        r.id AS review_id,
        r.reviewer_id,
        u.nickname AS reviewer_nickname,
        u.profile_picture_url AS reviewer_avatar,
        r.score,
        r.comment,
        r.created_at,
        r.transaction_id,
        t.item_id,
        i.title AS item_title,
        -- 取得物品的第一張圖片
        CASE
            WHEN array_length(i.image_urls, 1) > 0 THEN i.image_urls[1]
            ELSE NULL
        END AS item_image
    FROM
        public.ratings r
    INNER JOIN
        public.users u ON r.reviewer_id = u.id
    INNER JOIN
        public.transactions t ON r.transaction_id = t.id
    INNER JOIN
        public.items i ON t.item_id = i.id
    WHERE
        r.reviewed_user_id = v_current_user_id  -- 我被評價的記錄
    ORDER BY
        CASE
            WHEN p_sort_by = 'created_at' AND p_sort_direction = 'desc' THEN r.created_at
        END DESC,
        CASE
            WHEN p_sort_by = 'created_at' AND p_sort_direction = 'asc' THEN r.created_at
        END ASC,
        CASE
            WHEN p_sort_by = 'score' AND p_sort_direction = 'desc' THEN r.score
        END DESC,
        CASE
            WHEN p_sort_by = 'score' AND p_sort_direction = 'asc' THEN r.score
        END ASC
    LIMIT p_page_size
    OFFSET v_offset;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 設定函式註解
COMMENT ON FUNCTION public.get_my_reviews IS '獲取當前使用者收到的評價列表，支援分頁和排序功能';
