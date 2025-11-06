-- ####################################################################
-- ### 追蹤使用者 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.follow_user(
    p_following_id UUID -- (必填) 您要追蹤的使用者的 ID
)
              RETURNS JSON -- 回傳操作結果
              AS $$
              DECLARE
              v_follower_id UUID := auth.uid(); -- (安全!) 自動獲取當前登入者 ID
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_follower_id IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法追蹤';
END IF;

  -- 2. 安全檢查：確認不是自我追蹤
IF v_follower_id = p_following_id THEN
    RAISE EXCEPTION '無法追蹤自己';
END IF;

  -- 3. 執行插入，並優雅地處理 "重複追蹤" 的情況
INSERT INTO public.following (follower_id, following_id)
VALUES (v_follower_id, p_following_id)
ON CONFLICT (follower_id, following_id) DO NOTHING; -- 如果已追蹤，則忽略

-- 4. 回傳成功訊息
RETURN json_build_object('success', true, 'message', '追蹤成功或已追蹤');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;