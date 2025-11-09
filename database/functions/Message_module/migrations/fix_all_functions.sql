-- ============================================================================
-- Messaging System v2 - 完整修正
-- ============================================================================
-- 修正所有欄位名稱問題:
-- 1. users.name -> users.nickname
-- 2. users.avatar_url -> users.profile_picture_url
-- 3. 使用 v_conv_id 避免變數名稱衝突
-- 4. 使用命名約束
-- ============================================================================

-- Step 1: 確保約束有名稱
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_conv_items_v2'
    ) THEN
        ALTER TABLE public.conversation_items_v2
        DROP CONSTRAINT IF EXISTS conversation_items_v2_conversation_id_item_id_key CASCADE;
        
        ALTER TABLE public.conversation_items_v2
        ADD CONSTRAINT uq_conv_items_v2 UNIQUE (conversation_id, item_id);
        
        RAISE NOTICE '✓ 已建立唯一約束: uq_conv_items_v2';
    END IF;
END $$;

-- ============================================================================
-- 函數 1: normalize_participants_v2
-- ============================================================================
CREATE OR REPLACE FUNCTION normalize_participants_v2(
    p_user_a UUID,
    p_user_b UUID
)
RETURNS TABLE(participant_1 UUID, participant_2 UUID)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_user_a < p_user_b THEN
        RETURN QUERY SELECT p_user_a, p_user_b;
    ELSE
        RETURN QUERY SELECT p_user_b, p_user_a;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION normalize_participants_v2 TO authenticated;

-- ============================================================================
-- 函數 2: create_or_get_conversation_v2
-- ============================================================================
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

-- ============================================================================
-- 函數 3: send_message_v2
-- ============================================================================
CREATE OR REPLACE FUNCTION send_message_v2(
    p_conversation_id BIGINT,
    p_content TEXT,
    p_message_type VARCHAR(20) DEFAULT 'text',
    p_related_item_id BIGINT DEFAULT NULL
)
RETURNS TABLE(
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
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT c.participant_1_id, c.participant_2_id
    INTO v_participant_1, v_participant_2
    FROM public.conversations_v2 c
    WHERE c.id = p_conversation_id;

    IF v_participant_1 IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_current_user_id != v_participant_1 AND v_current_user_id != v_participant_2 THEN
        RAISE EXCEPTION 'Not a participant of this conversation';
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

GRANT EXECUTE ON FUNCTION send_message_v2 TO authenticated;

-- ============================================================================
-- 函數 4: get_user_conversations_v2 (修正欄位名稱)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_conversations_v2(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_include_archived BOOLEAN DEFAULT false
)
RETURNS TABLE(
    conversation_id BIGINT,
    other_user_id UUID,
    other_user_name VARCHAR,
    other_user_avatar TEXT,
    initial_item_id BIGINT,
    initial_item_title VARCHAR,
    last_message_content TEXT,
    last_message_at TIMESTAMPTZ,
    unread_count BIGINT,
    is_archived BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_current_user_id UUID;
    v_offset INT;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_offset := (p_page - 1) * p_size;

    RETURN QUERY
    SELECT
        c.id,
        CASE WHEN c.participant_1_id = v_current_user_id THEN c.participant_2_id ELSE c.participant_1_id END,
        CASE WHEN c.participant_1_id = v_current_user_id THEN u2.nickname ELSE u1.nickname END,
        CASE WHEN c.participant_1_id = v_current_user_id THEN u2.profile_picture_url ELSE u1.profile_picture_url END,
        c.initial_item_id,
        i.title,
        (SELECT m.content FROM public.conversation_messages_v2 m WHERE m.conversation_id = c.id AND m.is_deleted = false ORDER BY m.created_at DESC LIMIT 1),
        c.last_message_at,
        (SELECT COUNT(*) FROM public.conversation_messages_v2 m WHERE m.conversation_id = c.id AND m.is_deleted = false AND m.sender_id != v_current_user_id AND ((c.participant_1_id = v_current_user_id AND m.read_by_participant_1 = false) OR (c.participant_2_id = v_current_user_id AND m.read_by_participant_2 = false))),
        CASE WHEN c.participant_1_id = v_current_user_id THEN c.archived_by_participant_1 ELSE c.archived_by_participant_2 END,
        c.created_at
    FROM public.conversations_v2 c
    LEFT JOIN public.users u1 ON u1.id = c.participant_1_id
    LEFT JOIN public.users u2 ON u2.id = c.participant_2_id
    LEFT JOIN public.items i ON i.id = c.initial_item_id
    WHERE
        (c.participant_1_id = v_current_user_id OR c.participant_2_id = v_current_user_id)
        AND c.is_active = true
        AND (p_include_archived = true OR ((c.participant_1_id = v_current_user_id AND c.archived_by_participant_1 = false) OR (c.participant_2_id = v_current_user_id AND c.archived_by_participant_2 = false)))
    ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_conversations_v2 TO authenticated;

-- ============================================================================
-- 函數 5: get_conversation_messages_v2 (修正欄位名稱)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_conversation_messages_v2(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE(
    message_id BIGINT,
    sender_id UUID,
    sender_name VARCHAR,
    sender_avatar TEXT,
    content TEXT,
    message_type VARCHAR,
    related_item_id BIGINT,
    related_item_title VARCHAR,
    is_deleted BOOLEAN,
    is_mine BOOLEAN,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_current_user_id UUID;
    v_offset INT;
    v_participant_1 UUID;
    v_participant_2 UUID;
    v_user_is_p1 BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT c.participant_1_id, c.participant_2_id
    INTO v_participant_1, v_participant_2
    FROM public.conversations_v2 c
    WHERE c.id = p_conversation_id;

    IF v_participant_1 IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_current_user_id != v_participant_1 AND v_current_user_id != v_participant_2 THEN
        RAISE EXCEPTION 'Not a participant of this conversation';
    END IF;

    v_user_is_p1 := (v_current_user_id = v_participant_1);
    v_offset := (p_page - 1) * p_size;

    RETURN QUERY
    SELECT
        m.id,
        m.sender_id,
        u.nickname,
        u.profile_picture_url,
        m.content,
        m.message_type,
        m.related_item_id,
        i.title,
        m.is_deleted,
        (m.sender_id = v_current_user_id),
        CASE WHEN v_user_is_p1 THEN m.read_by_participant_1 ELSE m.read_by_participant_2 END,
        m.created_at
    FROM public.conversation_messages_v2 m
    LEFT JOIN public.users u ON u.id = m.sender_id
    LEFT JOIN public.items i ON i.id = m.related_item_id
    WHERE m.conversation_id = p_conversation_id AND (p_include_deleted = true OR m.is_deleted = false)
    ORDER BY m.created_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_conversation_messages_v2 TO authenticated;

-- ============================================================================
-- 函數 6: mark_messages_as_read_v2
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_messages_as_read_v2(
    p_conversation_id BIGINT,
    p_up_to_message_id BIGINT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_participant_1 UUID;
    v_participant_2 UUID;
    v_user_is_p1 BOOLEAN;
    v_updated_count BIGINT;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT c.participant_1_id, c.participant_2_id
    INTO v_participant_1, v_participant_2
    FROM public.conversations_v2 c
    WHERE c.id = p_conversation_id;

    IF v_participant_1 IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_current_user_id != v_participant_1 AND v_current_user_id != v_participant_2 THEN
        RAISE EXCEPTION 'Not a participant of this conversation';
    END IF;

    v_user_is_p1 := (v_current_user_id = v_participant_1);

    IF v_user_is_p1 THEN
        UPDATE public.conversation_messages_v2
        SET read_by_participant_1 = true, read_at_participant_1 = now()
        WHERE conversation_id = p_conversation_id
          AND sender_id != v_current_user_id
          AND read_by_participant_1 = false
          AND (p_up_to_message_id IS NULL OR id <= p_up_to_message_id);
    ELSE
        UPDATE public.conversation_messages_v2
        SET read_by_participant_2 = true, read_at_participant_2 = now()
        WHERE conversation_id = p_conversation_id
          AND sender_id != v_current_user_id
          AND read_by_participant_2 = false
          AND (p_up_to_message_id IS NULL OR id <= p_up_to_message_id);
    END IF;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION mark_messages_as_read_v2 TO authenticated;

-- ============================================================================
-- 函數 7: get_conversation_items_v2 (修正欄位名稱)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_conversation_items_v2(
    p_conversation_id BIGINT
)
RETURNS TABLE(
    item_id BIGINT,
    item_title VARCHAR,
    item_price NUMERIC,
    item_image_url TEXT,
    item_status VARCHAR,
    added_by_user_id UUID,
    added_by_user_name VARCHAR,
    added_at TIMESTAMPTZ,
    message_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.conversations_v2 c
        WHERE c.id = p_conversation_id
          AND (c.participant_1_id = v_current_user_id OR c.participant_2_id = v_current_user_id)
    ) THEN
        RAISE EXCEPTION 'Not a participant of this conversation';
    END IF;

    RETURN QUERY
    SELECT
        ci.item_id,
        i.title,
        i.price,
        i.image_url,
        i.status,
        ci.added_by_user_id,
        u.nickname,
        ci.created_at,
        (SELECT COUNT(*) FROM public.conversation_messages_v2 m WHERE m.conversation_id = p_conversation_id AND m.related_item_id = ci.item_id AND m.is_deleted = false)
    FROM public.conversation_items_v2 ci
    LEFT JOIN public.items i ON i.id = ci.item_id
    LEFT JOIN public.users u ON u.id = ci.added_by_user_id
    WHERE ci.conversation_id = p_conversation_id AND ci.is_active = true
    ORDER BY ci.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_conversation_items_v2 TO authenticated;

-- ============================================================================
-- 函數 8: toggle_conversation_archive_v2
-- ============================================================================
CREATE OR REPLACE FUNCTION toggle_conversation_archive_v2(
    p_conversation_id BIGINT,
    p_archived BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_participant_1 UUID;
    v_participant_2 UUID;
BEGIN
    v_current_user_id := auth.uid();

    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT c.participant_1_id, c.participant_2_id
    INTO v_participant_1, v_participant_2
    FROM public.conversations_v2 c
    WHERE c.id = p_conversation_id;

    IF v_participant_1 IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_current_user_id != v_participant_1 AND v_current_user_id != v_participant_2 THEN
        RAISE EXCEPTION 'Not a participant of this conversation';
    END IF;

    IF v_current_user_id = v_participant_1 THEN
        UPDATE public.conversations_v2 SET archived_by_participant_1 = p_archived WHERE id = p_conversation_id;
    ELSE
        UPDATE public.conversations_v2 SET archived_by_participant_2 = p_archived WHERE id = p_conversation_id;
    END IF;

    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_conversation_archive_v2 TO authenticated;

-- ============================================================================
-- 完成
-- ============================================================================
SELECT '✅ Messaging System v2 所有函數已更新完成!' AS status;
