-- ####################################################################
-- ### 使用者的公開 profile (RPC)
-- ####################################################################

-- 獲取公開使用者個人檔案 (RPC)
-- *** 已更新，加入 carbon_saved_kg ***
-- *** 已更新，加入 created_at ***
CREATE
OR
REPLACE FUNCTION public.get_public_user_profile(p_user_id UUID -- 要查詢的使用者 ID
)
    RETURNS JSON
    AS $$
BEGIN
    -- 使用 json_build_object 來建構您需要的 DTO
    RETURN
(SELECT json_build_object(
                'id', u.id,
                'nickname', u.nickname,
                'profile_picture_url', u.profile_picture_url,
                'avg_rating', u.avg_rating,

            -- *** 新增的欄位 (來自 users 表) ***
                'created_at', u.created_at,
            -- *** 新增欄位 ***
                'carbon_saved_kg', p.carbon_saved_kg,

            -- 從 'following' 表計算「追蹤中」 (我追蹤了誰)
                'following_count', (SELECT COUNT(*)
                                    FROM public.following
                                    WHERE follower_id = u.id),

            -- 從 'following' 表計算「追蹤者」 (誰追蹤了我)
                'followers_count', (SELECT COUNT(*)
                                    FROM public.following
                                    WHERE following_id = u.id)
        )
 FROM public.users u
          -- *** 新增 JOIN ***
          LEFT JOIN
      public.profiles p ON u.id = p.user_id
 WHERE u.id = p_user_id
    -- AND u.deleted_at IS NULL -- (根據您的指示，已移除邏輯刪除)
);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;