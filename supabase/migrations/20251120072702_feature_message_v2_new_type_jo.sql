-- ============================================================================
-- Messaging System v2 - 新增訊息類型
-- ============================================================================
-- 版本更新註釋：
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
    message_type VARCHAR(20),
    related_item_id BIGINT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_message_id BIGINT;
    v_participant_1_id UUID;
    v_participant_2_id UUID;
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空';
    END IF;

    IF p_message_type NOT IN ('text', 'image', 'system', 'item_reference', 'reply', 'transaction_link') THEN
        RAISE EXCEPTION '無效的訊息類型: %', p_message_type;
    END IF;

    SELECT participant_1_id, participant_2_id
    INTO v_participant_1_id, v_participant_2_id
    FROM public.conversations_v2
    WHERE id = p_conversation_id;

    IF v_participant_1_id IS NULL THEN
        RAISE EXCEPTION '對話不存在';
    END IF;

    IF v_current_uid != v_participant_1_id AND v_current_uid != v_participant_2_id THEN
        RAISE EXCEPTION '無權限在此對話中發送訊息';
    END IF;

    INSERT INTO public.conversation_messages_v2 (
        conversation_id,
        sender_id,
        content,
        message_type,
        related_item_id
    )
    VALUES (
        p_conversation_id,
        v_current_uid,
        p_content,
        p_message_type,
        p_related_item_id
    )
    RETURNING id INTO v_message_id;

    UPDATE public.conversations_v2
    SET last_message_at = now()
    WHERE id = p_conversation_id;

    RETURN QUERY
    SELECT
        cm.id,
        cm.conversation_id,
        cm.sender_id,
        cm.content,
        cm.message_type,
        cm.related_item_id,
        cm.created_at
    FROM public.conversation_messages_v2 cm
    WHERE cm.id = v_message_id;
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
