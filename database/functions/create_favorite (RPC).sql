-- ####################################################################
-- ### 新增收藏 (RPC) - 包含自我收藏檢查
-- ####################################################################

CREATE OR REPLACE FUNCTION public.add_favorite_item(
    p_item_id BIGINT -- (必填) 您要收藏的物品 ID
)
RETURNS JSON -- 回傳操作結果
AS $$
DECLARE
v_current_uid UUID := auth.uid(); -- (安全!) 自動獲取當前登入者 ID
  v_item_owner_id UUID;
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法新增收藏';
END IF;

  -- 2. *** 核心業務邏輯：檢查是否收藏自己的物品 ***
SELECT user_id INTO v_item_owner_id FROM public.items WHERE id = p_item_id;
IF v_item_owner_id IS NULL THEN
     RAISE EXCEPTION '物品不存在 (ID: %)', p_item_id;
END IF;
  IF v_current_uid = v_item_owner_id THEN
    RAISE EXCEPTION '無法收藏自己的物品';
END IF;

  -- 3. 執行插入，並優雅地處理 "重複收藏" 的情況
INSERT INTO public.favorites (user_id, item_id)
VALUES (v_current_uid, p_item_id)
    ON CONFLICT (user_id, item_id) DO NOTHING; -- 如果已收藏，則忽略

-- 4. 回傳成功訊息
RETURN json_build_object('success', true, 'message', '收藏成功或已在收藏中');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;