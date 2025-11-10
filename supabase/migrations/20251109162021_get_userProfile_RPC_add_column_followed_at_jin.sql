-- ####################################################################
-- ### 使用者的公開 profile (RPC)
-- ####################################################################

-- 獲取公開使用者個人檔案 (RPC)
-- *** 已更新，加入 carbon_saved_kg ***
-- *** 已更新，加入 created_at ***
-- *** 已更新，加入是否已追蹤的欄位 followed_at ***
CREATE OR REPLACE FUNCTION public.get_public_user_profile(
    p_user_id UUID -- 要查詢的使用者 ID
)
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid(); -- *** 獲取 "當前登入者" ID ***
BEGIN
    -- 使用 json_build_object 來建構您需要的 DTO
    RETURN (
               SELECT
                   json_build_object(
                           'id', u.id,
                           'nickname', u.nickname,
                           'profile_picture_url', u.profile_picture_url,
                           'avg_rating', u.avg_rating,
                           'created_at', u.created_at,
                           'carbon_saved_kg', p.carbon_saved_kg,

                           'following_count', (
                               SELECT COUNT(*)
                               FROM public.following
                               WHERE follower_id = u.id -- u.id = p_user_id
                           ),
                           'followers_count', (
                               SELECT COUNT(*)
                               FROM public.following
                               WHERE following_id = u.id -- u.id = p_user_id
                           ),

                       -- *** 新增的欄位 ***
                       -- 檢查 "我" (v_current_uid) 是否追蹤了 "這個人" (p_user_id)
                           'followed_at', (
                               SELECT f.created_at
                               FROM public.following f
                               WHERE f.follower_id = v_current_uid -- "我"
                                 AND f.following_id = p_user_id  -- "這個 profile 的人"
                           )
                   )
               FROM
                   public.users u
                       LEFT JOIN
                   public.profiles p ON u.id = p.user_id
               WHERE
                   u.id = p_user_id
           );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;