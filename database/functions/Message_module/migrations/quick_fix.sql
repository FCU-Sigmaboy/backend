-- 快速修正:只更新有問題的函數

-- 1. 先確保約束有名稱
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_conv_items_v2'
    ) THEN
        ALTER TABLE public.conversation_items_v2
        DROP CONSTRAINT IF EXISTS conversation_items_v2_conversation_id_item_id_key CASCADE;
        
        ALTER TABLE public.conversation_items_v2
        ADD CONSTRAINT uq_conv_items_v2 UNIQUE (conversation_id, item_id);
    END IF;
END $$;

-- 2. 更新函數
CREATE OR REPLACE FUNCTION create_or_get_conversation_v2(
    p_other_user_id UUID,
    p_initial_item_id BIGINT DEFAULT NULL
)
RETURNS TABLE(
    conversation_id BIGINT,
    participant_1_id UUID,
    participant_2_id UUID,
    initial_item_id BIGINT,
    is_new BOOLEAN,
    current_user_is_participant_1 BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_participant_1 UUID;
    v_participant_2 UUID;
    v_conv_id BIGINT;
    v_is_new BOOLEAN := false;
    v_user_is_p1 BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_current_user_id = p_other_user_id THEN
        RAISE EXCEPTION 'Cannot create conversation with yourself';
    END IF;

    SELECT p1, p2 INTO v_participant_1, v_participant_2
    FROM normalize_participants_v2(v_current_user_id, p_other_user_id) AS t(p1, p2);

    v_user_is_p1 := (v_current_user_id = v_participant_1);

    SELECT id INTO v_conv_id
    FROM public.conversations_v2
    WHERE public.conversations_v2.participant_1_id = v_participant_1
      AND public.conversations_v2.participant_2_id = v_participant_2
    LIMIT 1;

    IF v_conv_id IS NULL THEN
        INSERT INTO public.conversations_v2 (participant_1_id, participant_2_id, initial_item_id)
        VALUES (v_participant_1, v_participant_2, p_initial_item_id)
        RETURNING id INTO v_conv_id;

        v_is_new := true;

        IF p_initial_item_id IS NOT NULL THEN
            INSERT INTO public.conversation_items_v2 (conversation_id, item_id, added_by_user_id)
            VALUES (v_conv_id, p_initial_item_id, v_current_user_id)
            ON CONFLICT ON CONSTRAINT uq_conv_items_v2 DO NOTHING;
        END IF;
    ELSE
        IF p_initial_item_id IS NOT NULL THEN
            INSERT INTO public.conversation_items_v2 (conversation_id, item_id, added_by_user_id)
            VALUES (v_conv_id, p_initial_item_id, v_current_user_id)
            ON CONFLICT ON CONSTRAINT uq_conv_items_v2 DO NOTHING;
        END IF;
    END IF;

    RETURN QUERY
    SELECT v_conv_id, v_participant_1, v_participant_2, p_initial_item_id, v_is_new, v_user_is_p1;
END;
$$;

GRANT EXECUTE ON FUNCTION create_or_get_conversation_v2 TO authenticated;

SELECT 'create_or_get_conversation_v2 函數已更新!' AS status;
