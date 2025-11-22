-- ============================================================================
-- Messaging System v2 - RPC Functions Fix
-- ============================================================================
-- 描述: 修正欄位名稱衝突問題的 v2 訊息系統 RPC 函數
-- 版本: 2.0.2
-- 日期: 2024-01-15
-- 修正: 改用 ON CONSTRAINT 避免欄位名稱歧義
-- ============================================================================

-- 5.1 輔助函數:標準化參與者順序
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

COMMENT ON FUNCTION normalize_participants_v2 IS 'v2: 標準化參與者順序,確保 participant_1 < participant_2';

-- 5.2 建立或取得對話
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
    v_conversation_id BIGINT;
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

    SELECT id INTO v_conversation_id
    FROM public.conversations_v2
    WHERE public.conversations_v2.participant_1_id = v_participant_1
      AND public.conversations_v2.participant_2_id = v_participant_2
    LIMIT 1;

    IF v_conversation_id IS NULL THEN
        INSERT INTO public.conversations_v2 (
            participant_1_id,
            participant_2_id,
            initial_item_id
        ) VALUES (
            v_participant_1,
            v_participant_2,
            p_initial_item_id
        )
        RETURNING id INTO v_conversation_id;

        v_is_new := true;

        IF p_initial_item_id IS NOT NULL THEN
            INSERT INTO public.conversation_items_v2 (
                conversation_id,
                item_id,
                added_by_user_id
            ) VALUES (
                v_conversation_id,
                p_initial_item_id,
                v_current_user_id
            )
            ON CONFLICT ON CONSTRAINT conversation_items_v2_conversation_id_item_id_key DO NOTHING;
        END IF;
    ELSE
        IF p_initial_item_id IS NOT NULL THEN
            INSERT INTO public.conversation_items_v2 (
                conversation_id,
                item_id,
                added_by_user_id
            ) VALUES (
                v_conversation_id,
                p_initial_item_id,
                v_current_user_id
            )
            ON CONFLICT ON CONSTRAINT conversation_items_v2_conversation_id_item_id_key DO NOTHING;
        END IF;
    END IF;

    RETURN QUERY
    SELECT
        v_conversation_id,
        v_participant_1,
        v_participant_2,
        p_initial_item_id,
        v_is_new,
        v_user_is_p1;
END;
$$;

COMMENT ON FUNCTION create_or_get_conversation_v2 IS 'v2: 建立或取得兩個用戶之間的對話';

GRANT EXECUTE ON FUNCTION create_or_get_conversation_v2 TO authenticated;

-- 5.3 發送訊息
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
    v_message_id BIGINT;
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
        conversation_id,
        sender_id,
        content,
        message_type,
        related_item_id,
        read_by_participant_1,
        read_by_participant_2,
        read_at_participant_1,
        read_at_participant_2
    ) VALUES (
        p_conversation_id,
        v_current_user_id,
        p_content,
        p_message_type,
        p_related_item_id,
        v_user_is_p1,
        NOT v_user_is_p1,
        CASE WHEN v_user_is_p1 THEN now() ELSE NULL END,
        CASE WHEN v_user_is_p1 THEN NULL ELSE now() END
    )
    RETURNING id INTO v_message_id;

    IF p_related_item_id IS NOT NULL THEN
        INSERT INTO public.conversation_items_v2 (
            conversation_id,
            item_id,
            added_by_user_id,
            added_via_message_id
        ) VALUES (
            p_conversation_id,
            p_related_item_id,
            v_current_user_id,
            v_message_id
        )
        ON CONFLICT ON CONSTRAINT conversation_items_v2_conversation_id_item_id_key DO NOTHING;
    END IF;

    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.sender_id,
        m.content,
        m.message_type,
        m.related_item_id,
        m.created_at
    FROM public.conversation_messages_v2 m
    WHERE m.id = v_message_id;
END;
$$;

COMMENT ON FUNCTION send_message_v2 IS 'v2: 發送訊息,支援商品引用';

GRANT EXECUTE ON FUNCTION send_message_v2 TO authenticated;

-- 5.4 查詢對話列表
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
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN c.participant_2_id
            ELSE c.participant_1_id
        END,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN u2.name
            ELSE u1.name
        END,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN u2.avatar_url
            ELSE u1.avatar_url
        END,
        c.initial_item_id,
        i.title,
        (
            SELECT m.content
            FROM public.conversation_messages_v2 m
            WHERE m.conversation_id = c.id
              AND m.is_deleted = false
            ORDER BY m.created_at DESC
            LIMIT 1
        ),
        c.last_message_at,
        (
            SELECT COUNT(*)
            FROM public.conversation_messages_v2 m
            WHERE m.conversation_id = c.id
              AND m.is_deleted = false
              AND m.sender_id != v_current_user_id
              AND (
                  (c.participant_1_id = v_current_user_id AND m.read_by_participant_1 = false)
                  OR
                  (c.participant_2_id = v_current_user_id AND m.read_by_participant_2 = false)
              )
        ),
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN c.archived_by_participant_1
            ELSE c.archived_by_participant_2
        END,
        c.created_at
    FROM public.conversations_v2 c
    LEFT JOIN public.users u1 ON u1.id = c.participant_1_id
    LEFT JOIN public.users u2 ON u2.id = c.participant_2_id
    LEFT JOIN public.items i ON i.id = c.initial_item_id
    WHERE
        (c.participant_1_id = v_current_user_id OR c.participant_2_id = v_current_user_id)
        AND c.is_active = true
        AND (
            p_include_archived = true
            OR
            (
                (c.participant_1_id = v_current_user_id AND c.archived_by_participant_1 = false)
                OR
                (c.participant_2_id = v_current_user_id AND c.archived_by_participant_2 = false)
            )
        )
    ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
    LIMIT p_size
    OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION get_user_conversations_v2 IS 'v2: 查詢用戶對話列表';

GRANT EXECUTE ON FUNCTION get_user_conversations_v2 TO authenticated;

-- 5.5 查詢對話訊息
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
        u.name,
        u.avatar_url,
        m.content,
        m.message_type,
        m.related_item_id,
        i.title,
        m.is_deleted,
        (m.sender_id = v_current_user_id),
        CASE
            WHEN v_user_is_p1 THEN m.read_by_participant_1
            ELSE m.read_by_participant_2
        END,
        m.created_at
    FROM public.conversation_messages_v2 m
    LEFT JOIN public.users u ON u.id = m.sender_id
    LEFT JOIN public.items i ON i.id = m.related_item_id
    WHERE
        m.conversation_id = p_conversation_id
        AND (p_include_deleted = true OR m.is_deleted = false)
    ORDER BY m.created_at DESC
    LIMIT p_size
    OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION get_conversation_messages_v2 IS 'v2: 查詢對話訊息';

GRANT EXECUTE ON FUNCTION get_conversation_messages_v2 TO authenticated;

-- 5.6 標記訊息為已讀
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
        SET
            read_by_participant_1 = true,
            read_at_participant_1 = now()
        WHERE
            conversation_id = p_conversation_id
            AND sender_id != v_current_user_id
            AND read_by_participant_1 = false
            AND (p_up_to_message_id IS NULL OR id <= p_up_to_message_id);
    ELSE
        UPDATE public.conversation_messages_v2
        SET
            read_by_participant_2 = true,
            read_at_participant_2 = now()
        WHERE
            conversation_id = p_conversation_id
            AND sender_id != v_current_user_id
            AND read_by_participant_2 = false
            AND (p_up_to_message_id IS NULL OR id <= p_up_to_message_id);
    END IF;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    RETURN v_updated_count;
END;
$$;

COMMENT ON FUNCTION mark_messages_as_read_v2 IS 'v2: 標記訊息為已讀';

GRANT EXECUTE ON FUNCTION mark_messages_as_read_v2 TO authenticated;

-- 5.7 查詢對話中的商品
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
        i.title AS item_title,
        i.price AS item_price,
        i.image_urls[1] AS item_image_url,
        i.status AS item_status,
        ci.added_by_user_id,
        u.name AS added_by_user_name,
        ci.created_at AS added_at,
        (
            SELECT COUNT(*)
            FROM public.conversation_messages_v2 m
            WHERE m.conversation_id = p_conversation_id
              AND m.related_item_id = ci.item_id
              AND m.is_deleted = false
        )
    FROM public.conversation_items_v2 ci
    LEFT JOIN public.items i ON i.id = ci.item_id
    LEFT JOIN public.users u ON u.id = ci.added_by_user_id
    WHERE
        ci.conversation_id = p_conversation_id
        AND ci.is_active = true
    ORDER BY ci.created_at ASC;
END;
$$;

COMMENT ON FUNCTION get_conversation_items_v2 IS 'v2: 查詢對話中討論過的所有商品';

GRANT EXECUTE ON FUNCTION get_conversation_items_v2 TO authenticated;

-- 5.8 歸檔/取消歸檔對話
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
        UPDATE public.conversations_v2
        SET archived_by_participant_1 = p_archived
        WHERE id = p_conversation_id;
    ELSE
        UPDATE public.conversations_v2
        SET archived_by_participant_2 = p_archived
        WHERE id = p_conversation_id;
    END IF;

    RETURN true;
END;
$$;

COMMENT ON FUNCTION toggle_conversation_archive_v2 IS 'v2: 歸檔或取消歸檔對話';

GRANT EXECUTE ON FUNCTION toggle_conversation_archive_v2 TO authenticated;

-- ============================================================================
-- 完成
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Messaging System v2 RPC Functions 修正完成!';
    RAISE NOTICE '版本: 2.0.2';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '已修正並更新的 RPC 函數:';
    RAISE NOTICE '  對話管理:';
    RAISE NOTICE '    ✓ normalize_participants_v2()';
    RAISE NOTICE '    ✓ create_or_get_conversation_v2()';
    RAISE NOTICE '    ✓ get_user_conversations_v2()';
    RAISE NOTICE '    ✓ toggle_conversation_archive_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '  訊息管理:';
    RAISE NOTICE '    ✓ send_message_v2()';
    RAISE NOTICE '    ✓ get_conversation_messages_v2()';
    RAISE NOTICE '    ✓ mark_messages_as_read_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '  商品管理:';
    RAISE NOTICE '    ✓ get_conversation_items_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '修正內容:';
    RAISE NOTICE '  - 使用 ON CONSTRAINT 代替欄位名稱';
    RAISE NOTICE '  - 移除 RETURN QUERY SELECT 中的 AS 別名';
    RAISE NOTICE '  - 解決 "column reference is ambiguous" 錯誤';
    RAISE NOTICE '';
    RAISE NOTICE '所有函數已授予 authenticated 角色執行權限';
    RAISE NOTICE '========================================';
END $$;
