-- ============================================================================
-- 修正遷移函數 - 適配 v1 實際欄位
-- ============================================================================

CREATE OR REPLACE FUNCTION migrate_conversations_v1_to_v2(
    p_batch_size INT DEFAULT 1000,
    p_offset INT DEFAULT 0
)
RETURNS TABLE(
    migrated_conversations BIGINT,
    migrated_messages BIGINT,
    errors TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_migrated_conv BIGINT := 0;
    v_migrated_msg BIGINT := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_conv_record RECORD;
    v_new_conv_id BIGINT;
    v_participant_1 UUID;
    v_participant_2 UUID;
    v_msg_count BIGINT;
BEGIN
    FOR v_conv_record IN
        SELECT * FROM public.conversations
        ORDER BY id
        LIMIT p_batch_size
        OFFSET p_offset
    LOOP
        BEGIN
            -- 標準化參與者順序
            SELECT p1, p2 INTO v_participant_1, v_participant_2
            FROM normalize_participants_v2(
                v_conv_record.buyer_id,
                v_conv_record.seller_id
            ) AS t(p1, p2);

            -- 插入到 v2 (或取得已存在的對話)
            INSERT INTO public.conversations_v2 (
                participant_1_id,
                participant_2_id,
                initial_item_id,
                created_at,
                updated_at
            ) VALUES (
                v_participant_1,
                v_participant_2,
                v_conv_record.item_id,
                v_conv_record.created_at,
                v_conv_record.updated_at
            )
            ON CONFLICT (participant_1_id, participant_2_id)
            DO UPDATE SET 
                updated_at = EXCLUDED.updated_at,
                -- 如果新對話有初始商品,更新它
                initial_item_id = COALESCE(EXCLUDED.initial_item_id, conversations_v2.initial_item_id)
            RETURNING id INTO v_new_conv_id;

            -- 確保初始商品在 conversation_items_v2 中
            INSERT INTO public.conversation_items_v2 (
                conversation_id,
                item_id,
                added_by_user_id,
                created_at
            ) VALUES (
                v_new_conv_id,
                v_conv_record.item_id,
                v_conv_record.buyer_id,  -- 假設買家發起
                v_conv_record.created_at
            )
            ON CONFLICT (conversation_id, item_id) DO NOTHING;

            v_migrated_conv := v_migrated_conv + 1;

            -- 遷移此對話的所有訊息
            -- v1 欄位: id, conversation_id, sender_id, content, is_read, sent_at
            -- v2 欄位: id, conversation_id, sender_id, content, message_type, is_deleted, 
            --          read_by_participant_1, read_by_participant_2, created_at, updated_at
            
            WITH migrated AS (
                INSERT INTO public.conversation_messages_v2 (
                    conversation_id,
                    sender_id,
                    content,
                    message_type,
                    is_deleted,
                    read_by_participant_1,
                    read_by_participant_2,
                    read_at_participant_1,
                    read_at_participant_2,
                    created_at,
                    updated_at
                )
                SELECT 
                    v_new_conv_id,
                    cm.sender_id,
                    cm.content,
                    'text'::VARCHAR(20),  -- v1 沒有 message_type,預設為 text
                    false,  -- v1 沒有軟刪除功能
                    -- 根據發送者判斷已讀狀態
                    CASE 
                        WHEN cm.sender_id = v_participant_1 THEN true  -- 發送者自己已讀
                        ELSE cm.is_read  -- 接收者的已讀狀態
                    END,
                    CASE 
                        WHEN cm.sender_id = v_participant_2 THEN true  -- 發送者自己已讀
                        ELSE cm.is_read  -- 接收者的已讀狀態
                    END,
                    -- 已讀時間 (v1 沒有,設為 NULL)
                    NULL,
                    NULL,
                    cm.sent_at,  -- v1 的 sent_at 對應 v2 的 created_at
                    cm.sent_at   -- 使用 sent_at 作為 updated_at
                FROM public.conversation_messages cm
                WHERE cm.conversation_id = v_conv_record.id
                ON CONFLICT DO NOTHING
                RETURNING 1
            )
            SELECT COUNT(*) INTO v_msg_count
            FROM migrated;
            
            v_migrated_msg := v_migrated_msg + v_msg_count;

        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(
                v_errors,
                format('Error migrating conversation %s: %s', v_conv_record.id, SQLERRM)
            );
        END;
    END LOOP;

    RETURN QUERY SELECT v_migrated_conv, v_migrated_msg, v_errors;
END;
$$;

COMMENT ON FUNCTION migrate_conversations_v1_to_v2 IS '批次遷移 v1 對話和訊息到 v2 (修正版 - 適配 v1 實際欄位)';
