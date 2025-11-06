-- ####################################################################
-- ### API 13: 查找或建立聊天室 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.find_or_create_conversation(
    p_item_id BIGINT -- (必填) 您要針對哪個物品發起聊天
)
RETURNS JSON -- 回傳包含 conversation_id 的 JSON 物件
AS $$
DECLARE
v_buyer_id UUID := auth.uid(); -- (安全!) 自動獲取當前登入者 ID (買家)
  v_seller_id UUID;
  v_conversation_id BIGINT;
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION '使用者未登入，無法發起聊天';
END IF;

  -- 2. 查找物品擁有者 (賣家) ID
SELECT user_id INTO v_seller_id FROM public.items WHERE id = p_item_id;
IF v_seller_id IS NULL THEN
     RAISE EXCEPTION '物品不存在 (ID: %)', p_item_id;
END IF;

  -- 3. 安全檢查：確認不是自己跟自己聊天
  IF v_buyer_id = v_seller_id THEN
    RAISE EXCEPTION '無法與自己發起聊天';
END IF;

  -- 4. 嘗試查找現有的聊天室
SELECT id INTO v_conversation_id
FROM public.conversations
WHERE item_id = p_item_id AND buyer_id = v_buyer_id;

-- 5. 如果找不到，則建立新的聊天室
IF v_conversation_id IS NULL THEN
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_buyer_id, v_seller_id)
    -- ON CONFLICT (item_id, buyer_id) DO NOTHING; -- 雖然前面查過，加上 ON CONFLICT 更保險
    -- 我們需要 ID，所以不用 DO NOTHING，而是用 RETURNING
    RETURNING id INTO v_conversation_id;
ELSE
    -- 如果找到了，更新 updated_at (可選，讓它置頂)
UPDATE public.conversations SET updated_at = NOW() WHERE id = v_conversation_id;
END IF;

  -- 6. 回傳聊天室 ID
RETURN json_build_object('conversation_id', v_conversation_id);

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;