-- ####################################################################
-- ### 使用者的公開 profile (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_public_user_profile(
    p_user_id UUID -- 要查詢的使用者 ID
)
RETURNS JSON
AS $$
BEGIN
  -- 使用 json_build_object 來建構您需要的 DTO
RETURN (
    SELECT
        json_build_object(
                'id', u.id,
                'nickname', u.nickname,
                'profile_picture_url', u.profile_picture_url,
                'avg_rating', u.avg_rating,
                'created_at', u.created_at, -- (來自 users 表)
        -- 'updated_at' 欄位在 users 表中不存在，移除

        -- 從 'locations' 表 JOIN 主要地址
                'formatted_address', l.formatted_address,

            -- 從 'following' 表計算「追蹤中」 (我追蹤了誰)
                'following_count', (
                    SELECT COUNT(*)
                    FROM public.following
                    WHERE follower_id = u.id
                ),

            -- 從 'following' 表計算「追蹤者」 (誰追蹤了我)
                'followers_count', (
                    SELECT COUNT(*)
                    FROM public.following
                    WHERE following_id = u.id
                )
        )
    FROM
        public.users u
            -- LEFT JOIN: 確保即使沒有 'primary' 地址，profile 依然能被找到
            LEFT JOIN
        public.locations l ON u.id = l.user_id AND l.is_primary = true
    WHERE
        u.id = p_user_id
      AND u.deleted_at IS NULL -- (確保您已移除此行，如果不需要邏輯刪除)
);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- (SECURITY DEFINER 通常非必要，除非需要特殊權限，但為保持一致性，先保留)