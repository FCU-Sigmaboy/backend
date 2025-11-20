-- ============================================================================
-- Messaging System v2 - 新增訊息類型
-- ============================================================================
-- 版本更新註釋：
-- v1.3.0 (2025-11-20): 修復 SECURITY DEFINER 缺失導致的權限錯誤，補全已讀狀態和商品關聯邏輯
-- v1.2.0 (2025-11-20): 修正 reply 和 transaction_link 使用 JSON content 格式，移除額外欄位
-- v1.1.0 (2025-11-20): 修正 transaction_link 使用 JSON content 格式，移除 transaction_id 欄位
-- v1.0.0 (2025-11-20): 初始版本，新增 reply 和 transaction_link 訊息類型
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: 更新 message_type 檢查約束
-- ============================================================================

-- 1.1 刪除舊的檢查約束
ALTER TABLE public.conversation_messages_v2
DROP CONSTRAINT IF EXISTS conversation_messages_v2_valid_type;

-- 1.2 新增包含新類型的檢查約束
ALTER TABLE public.conversation_messages_v2
ADD CONSTRAINT conversation_messages_v2_valid_type
    CHECK (message_type IN (
        'text',
        'image',
        'system',
        'item_reference',
        'reply',
        'transaction_link'
    ));

-- ============================================================================
-- SECTION 2: 更新現有 RPC 函數以支援新類型
-- ============================================================================

-- 2.1 更新 send_message_v2 函數
CREATE OR REPLACE FUNCTION public.send_message_v2(
    p_conversation_id BIGINT,
    p_content TEXT,
    p_message_type VARCHAR(20) DEFAULT 'text',
    p_related_item_id BIGINT DEFAULT NULL
)
RETURNS TABLE (
    message_id BIGINT,
    conversation_id BIGINT,
    sender_id UUID,
    content TEXT,
    message_type VARCHAR,
    related_item_id BIGINT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_msg_id BIGINT;
    v_participant_1 UUID;
    v_participant_2 UUID;
    v_user_is_p1 BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT c.participant_1_id, c.participant_2_id
    INTO v_participant_1, v_participant_2
    FROM public.conversations_v2 c
    WHERE c.id = p_conversation_id;

    IF v_participant_1 IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_current_user_id != v_participant_1 AND v_current_user_id != v_participant_2 THEN
        RAISE EXCEPTION 'Access denied: not a participant';
    END IF;

    v_user_is_p1 := (v_current_user_id = v_participant_1);

    INSERT INTO public.conversation_messages_v2 (
        conversation_id, sender_id, content, message_type, related_item_id,
        read_by_participant_1, read_by_participant_2,
        read_at_participant_1, read_at_participant_2
    ) VALUES (
        p_conversation_id, v_current_user_id, p_content, p_message_type, p_related_item_id,
        v_user_is_p1, NOT v_user_is_p1,
        CASE WHEN v_user_is_p1 THEN now() ELSE NULL END,
        CASE WHEN v_user_is_p1 THEN NULL ELSE now() END
    )
    RETURNING id INTO v_msg_id;

    IF p_related_item_id IS NOT NULL THEN
        INSERT INTO public.conversation_items_v2 (conversation_id, item_id, added_by_user_id, added_via_message_id)
        VALUES (p_conversation_id, p_related_item_id, v_current_user_id, v_msg_id)
        ON CONFLICT ON CONSTRAINT uq_conv_items_v2 DO NOTHING;
    END IF;

    RETURN QUERY
    SELECT m.id, m.conversation_id, m.sender_id, m.content, m.message_type, m.related_item_id, m.created_at
    FROM public.conversation_messages_v2 m
    WHERE m.id = v_msg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_message_v2(BIGINT, TEXT, VARCHAR, BIGINT) TO authenticated;

COMMENT ON FUNCTION public.send_message_v2 IS 'v2版本發送訊息函數，支援 reply 和 transaction_link 類型（使用 JSON content 格式）';

-- ============================================================================
-- 完成遷移
-- ============================================================================

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✅ 遷移完成: 已成功新增 reply 和 transaction_link 訊息類型';
    RAISE NOTICE '📝 支援的訊息類型: text, image, system, item_reference, reply, transaction_link';
    RAISE NOTICE '💡 reply 使用 JSON 格式: {"回覆的訊息內容":"xxx","你的訊息內容":"xxx","reply_to_message_id":649}';
    RAISE NOTICE '💡 transaction_link 使用 JSON 格式: {"transaction_id":95}';
END $$;
