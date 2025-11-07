-- ####################################################################
-- ### 獲取我的追蹤者列表 (RPC)
-- ### Author: Chris
-- ### Date: 2025-11-06
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_my_followers(
    p_page INT DEFAULT 1,                        -- 頁碼，預設為 1
    p_page_size INT DEFAULT 20,                  -- 每頁數量，預設為 20
    p_sort_by TEXT DEFAULT 'followed_at',        -- 排序欄位：'followed_at', 'nickname'
    p_sort_direction TEXT DEFAULT 'desc',        -- 排序方向：'asc', 'desc'
    p_search TEXT DEFAULT ''                     -- 搜尋關鍵字
)
RETURNS TABLE (
    user_id UUID,
    nickname TEXT,
    profile_picture_url TEXT,
    followed_at TIMESTAMPTZ,
    is_following_back BOOLEAN
)
AS $$
DECLARE
    v_current_user_id UUID := auth.uid();        -- 當前登入用戶 ID
    v_offset INT;                                -- 分頁偏移量
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法獲取追蹤者列表';
    END IF;

    -- 2. 計算分頁偏移量
    v_offset := (p_page - 1) * p_page_size;

    -- 3. 查詢追蹤我的人列表
    RETURN QUERY
    SELECT
        p.id AS user_id,
        p.nickname,
        p.profile_picture_url,
        f.created_at AS followed_at,
        -- 檢查我是否也追蹤了這個人（互相追蹤）
        EXISTS(
            SELECT 1
            FROM public.following f2
            WHERE f2.follower_id = v_current_user_id
              AND f2.following_id = p.id
        ) AS is_following_back
    FROM
        public.following f
    INNER JOIN
        public.profiles p ON f.follower_id = p.id
    WHERE
        f.following_id = v_current_user_id  -- 追蹤我的人（following_id 是我）
        AND (
            p_search = ''
            OR p.nickname ILIKE '%' || p_search || '%'  -- 搜尋用戶名稱
        )
    ORDER BY
        CASE
            WHEN p_sort_by = 'followed_at' AND p_sort_direction = 'desc' THEN f.created_at
        END DESC,
        CASE
            WHEN p_sort_by = 'followed_at' AND p_sort_direction = 'asc' THEN f.created_at
        END ASC,
        CASE
            WHEN p_sort_by = 'nickname' AND p_sort_direction = 'desc' THEN p.nickname
        END DESC,
        CASE
            WHEN p_sort_by = 'nickname' AND p_sort_direction = 'asc' THEN p.nickname
        END ASC
    LIMIT p_page_size
    OFFSET v_offset;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 設定函式註解
COMMENT ON FUNCTION public.get_my_followers IS '獲取追蹤我的人列表，支援分頁、排序和搜尋功能';
