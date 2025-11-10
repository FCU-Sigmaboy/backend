-- ============================================================================
-- 新增訊息軟刪除功能
-- ============================================================================

-- 軟刪除訊息
CREATE OR REPLACE FUNCTION soft_delete_message_v2(p_message_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_sender_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- 檢查訊息是否存在且是當前用戶發送的
    SELECT sender_id INTO v_sender_id
    FROM public.conversation_messages_v2
    WHERE id = p_message_id;
    
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;
    
    IF v_sender_id != v_current_user_id THEN
        RAISE EXCEPTION 'Can only delete your own messages';
    END IF;
    
    -- 軟刪除 (只更新狀態,不實際刪除資料)
    UPDATE public.conversation_messages_v2
    SET 
        is_deleted = true,
        deleted_at = now()
    WHERE id = p_message_id;
    
    RETURN true;
END;
$$;

COMMENT ON FUNCTION soft_delete_message_v2 IS 'v2: 軟刪除訊息 (僅發送者可刪除)';

-- 恢復已刪除的訊息
CREATE OR REPLACE FUNCTION restore_message_v2(p_message_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_sender_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- 檢查訊息是否存在且是當前用戶發送的
    SELECT sender_id INTO v_sender_id
    FROM public.conversation_messages_v2
    WHERE id = p_message_id;
    
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;
    
    IF v_sender_id != v_current_user_id THEN
        RAISE EXCEPTION 'Can only restore your own messages';
    END IF;
    
    -- 恢復訊息
    UPDATE public.conversation_messages_v2
    SET 
        is_deleted = false,
        deleted_at = NULL
    WHERE id = p_message_id;
    
    RETURN true;
END;
$$;

COMMENT ON FUNCTION restore_message_v2 IS 'v2: 恢復已刪除的訊息 (僅發送者可恢復)';

-- 授予執行權限
GRANT EXECUTE ON FUNCTION soft_delete_message_v2 TO authenticated;
GRANT EXECUTE ON FUNCTION restore_message_v2 TO authenticated;
