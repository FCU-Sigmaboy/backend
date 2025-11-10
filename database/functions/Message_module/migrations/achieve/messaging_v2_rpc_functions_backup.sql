-- ============================================================================
-- Messaging System v2 - Complete Migration Script
-- ============================================================================
-- 描述: 建立完整的 v2 訊息系統,支援去角色化設計和多商品對話
-- 版本: 2.0.0
-- 日期: 2024-01-XX
--
-- 重要提醒:
-- 1. 此腳本不會修改或刪除 v1 資料表
-- 2. v1 和 v2 可以並存運行
-- 3. 建議在測試環境先執行
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECTION 1: 輔助函數
-- ============================================================================

-- 1.1 更新 updated_at 時間戳記函數 (如果不存在)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.update_updated_at_column IS '自動更新 updated_at 欄位';

-- ============================================================================
-- SECTION 2: 資料表結構
-- ============================================================================

-- 2.1 對話表 v2 (去角色化設計)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.conversations_v2 (
    id BIGSERIAL PRIMARY KEY,

    -- 參與者 (去角色化,確保 participant_1_id < participant_2_id)
    participant_1_id UUID NOT NULL,
    participant_2_id UUID NOT NULL,

    -- 對話元數據
    initial_item_id BIGINT,  -- 初始商品 (可為 NULL,支援純聊天)

    -- 狀態管理
    is_active BOOLEAN NOT NULL DEFAULT true,
    archived_by_participant_1 BOOLEAN NOT NULL DEFAULT false,
    archived_by_participant_2 BOOLEAN NOT NULL DEFAULT false,

    -- 時間戳記
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ,

    -- 外鍵約束
    FOREIGN KEY (participant_1_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (participant_2_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (initial_item_id) REFERENCES public.items(id) ON DELETE SET NULL,

    -- 唯一約束 (確保兩個用戶只有一個對話)
    CONSTRAINT conversations_v2_participants_unique
        UNIQUE (participant_1_id, participant_2_id),

    -- 檢查約束 (防止自己跟自己對話)
    CONSTRAINT conversations_v2_different_participants
        CHECK (participant_1_id != participant_2_id),

    -- 檢查約束 (確保參與者順序正確)
    CONSTRAINT conversations_v2_participant_order
        CHECK (participant_1_id < participant_2_id)
);

-- 索引優化
CREATE INDEX IF NOT EXISTS idx_conversations_v2_participant_1
    ON public.conversations_v2(participant_1_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversations_v2_participant_2
    ON public.conversations_v2(participant_2_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversations_v2_initial_item
    ON public.conversations_v2(initial_item_id)
    WHERE initial_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_v2_last_message
    ON public.conversations_v2(last_message_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_conversations_v2_active
    ON public.conversations_v2(is_active)
    WHERE is_active = true;

-- 觸發器
DROP TRIGGER IF EXISTS update_conversations_v2_updated_at ON public.conversations_v2;
CREATE TRIGGER update_conversations_v2_updated_at
    BEFORE UPDATE ON public.conversations_v2
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 註解
COMMENT ON TABLE public.conversations_v2 IS 'v2版本對話表,支援去角色化設計和多商品討論';
COMMENT ON COLUMN public.conversations_v2.participant_1_id IS '參與者1 (UUID較小者)';
COMMENT ON COLUMN public.conversations_v2.participant_2_id IS '參與者2 (UUID較大者)';
COMMENT ON COLUMN public.conversations_v2.initial_item_id IS '對話起始商品,可為NULL';
COMMENT ON COLUMN public.conversations_v2.archived_by_participant_1 IS '參與者1是否歸檔此對話';
COMMENT ON COLUMN public.conversations_v2.archived_by_participant_2 IS '參與者2是否歸檔此對話';

-- 2.2 訊息表 v2 (增強版)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.conversation_messages_v2 (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    sender_id UUID NOT NULL,

    -- 訊息內容
    content TEXT NOT NULL,
    message_type VARCHAR(20) NOT NULL DEFAULT 'text',

    -- 商品引用 (新功能)
    related_item_id BIGINT,

    -- 訊息狀態
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMPTZ,

    -- 已讀狀態 (拆分為兩個參與者)
    read_by_participant_1 BOOLEAN NOT NULL DEFAULT false,
    read_by_participant_2 BOOLEAN NOT NULL DEFAULT false,
    read_at_participant_1 TIMESTAMPTZ,
    read_at_participant_2 TIMESTAMPTZ,

    -- 時間戳記
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 外鍵約束
    FOREIGN KEY (conversation_id) REFERENCES public.conversations_v2(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (related_item_id) REFERENCES public.items(id) ON DELETE SET NULL,

    -- 檢查約束
    CONSTRAINT conversation_messages_v2_valid_type
        CHECK (message_type IN ('text', 'image', 'system', 'item_reference'))
);

-- 索引優化
CREATE INDEX IF NOT EXISTS idx_conversation_messages_v2_conversation
    ON public.conversation_messages_v2(conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversation_messages_v2_sender
    ON public.conversation_messages_v2(sender_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversation_messages_v2_related_item
    ON public.conversation_messages_v2(related_item_id)
    WHERE related_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversation_messages_v2_unread
    ON public.conversation_messages_v2(conversation_id, sender_id)
    WHERE NOT is_deleted;

-- 觸發器
DROP TRIGGER IF EXISTS update_conversation_messages_v2_updated_at ON public.conversation_messages_v2;
CREATE TRIGGER update_conversation_messages_v2_updated_at
    BEFORE UPDATE ON public.conversation_messages_v2
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 註解
COMMENT ON TABLE public.conversation_messages_v2 IS 'v2版本訊息表,支援商品引用和增強的已讀狀態';
COMMENT ON COLUMN public.conversation_messages_v2.related_item_id IS '此訊息討論的商品ID';
COMMENT ON COLUMN public.conversation_messages_v2.read_by_participant_1 IS '參與者1是否已讀';
COMMENT ON COLUMN public.conversation_messages_v2.read_by_participant_2 IS '參與者2是否已讀';

-- 2.3 對話商品關聯表
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.conversation_items_v2 (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    item_id BIGINT NOT NULL,

    -- 商品加入對話的方式
    added_by_user_id UUID NOT NULL,
    added_via_message_id BIGINT,

    -- 狀態
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- 時間戳記
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 外鍵約束
    FOREIGN KEY (conversation_id) REFERENCES public.conversations_v2(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE,
    FOREIGN KEY (added_by_user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (added_via_message_id) REFERENCES public.conversation_messages_v2(id) ON DELETE SET NULL,

    -- 唯一約束
    UNIQUE(conversation_id, item_id)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_conversation_items_v2_conversation
    ON public.conversation_items_v2(conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversation_items_v2_item
    ON public.conversation_items_v2(item_id);

-- 註解
COMMENT ON TABLE public.conversation_items_v2 IS '追蹤對話中討論過的所有商品';

-- ============================================================================
-- SECTION 3: 觸發器函數
-- ============================================================================

-- 3.1 更新對話的 last_message_at
CREATE OR REPLACE FUNCTION update_conversation_v2_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations_v2
    SET
        last_message_at = NEW.created_at,
        updated_at = now()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_conversation_v2_last_message ON public.conversation_messages_v2;
CREATE TRIGGER trigger_update_conversation_v2_last_message
    AFTER INSERT ON public.conversation_messages_v2
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_v2_last_message();

COMMENT ON FUNCTION update_conversation_v2_last_message IS 'v2: 自動更新對話的最後訊息時間';

-- ============================================================================
-- SECTION 4: RLS 安全性策略
-- ============================================================================

-- 4.1 conversations_v2 表 RLS
ALTER TABLE public.conversations_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversations_v2_select_policy ON public.conversations_v2;
CREATE POLICY conversations_v2_select_policy ON public.conversations_v2
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = participant_1_id
        OR auth.uid() = participant_2_id
    );

DROP POLICY IF EXISTS conversations_v2_insert_policy ON public.conversations_v2;
CREATE POLICY conversations_v2_insert_policy ON public.conversations_v2
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() IN (participant_1_id, participant_2_id)
    );

DROP POLICY IF EXISTS conversations_v2_update_policy ON public.conversations_v2;
CREATE POLICY conversations_v2_update_policy ON public.conversations_v2
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() = participant_1_id
        OR auth.uid() = participant_2_id
    )
    WITH CHECK (
        auth.uid() = participant_1_id
        OR auth.uid() = participant_2_id
    );

DROP POLICY IF EXISTS conversations_v2_delete_policy ON public.conversations_v2;
CREATE POLICY conversations_v2_delete_policy ON public.conversations_v2
    FOR DELETE
    TO authenticated
    USING (false);

-- 4.2 conversation_messages_v2 表 RLS
ALTER TABLE public.conversation_messages_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversation_messages_v2_select_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_select_policy ON public.conversation_messages_v2
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = public.conversation_messages_v2.conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_messages_v2_insert_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_insert_policy ON public.conversation_messages_v2
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = sender_id
        AND EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = public.conversation_messages_v2.conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_messages_v2_update_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_update_policy ON public.conversation_messages_v2
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = public.conversation_messages_v2.conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_messages_v2_delete_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_delete_policy ON public.conversation_messages_v2
    FOR DELETE
    TO authenticated
    USING (false);

-- 4.3 conversation_items_v2 表 RLS
ALTER TABLE public.conversation_items_v2 ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversation_items_v2_select_policy ON public.conversation_items_v2;
CREATE POLICY conversation_items_v2_select_policy ON public.conversation_items_v2
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = public.conversation_items_v2.conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

-- ============================================================================
-- SECTION 5: RPC 函數
-- ============================================================================

-- 5.1 輔助函數:標準化參與者順序
CREATE OR REPLACE FUNCTION normalize_participants_v2(
    p_user_a UUID,
    p_user_b UUID
)
RETURNS TABLE(participant_1 UUID, participant_2 UUID)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_user_a < p_user_b THEN
        RETURN QUERY SELECT p_user_a AS participant_1, p_user_b AS participant_2;
    ELSE
        RETURN QUERY SELECT p_user_b AS participant_1, p_user_a AS participant_2;
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
            ON CONFLICT (conversation_id, item_id) DO NOTHING;
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
            ON CONFLICT (conversation_id, item_id) DO NOTHING;
        END IF;
    END IF;

    RETURN QUERY
    SELECT
        v_conversation_id AS conversation_id,
        v_participant_1 AS participant_1_id,
        v_participant_2 AS participant_2_id,
        p_initial_item_id AS initial_item_id,
        v_is_new AS is_new,
        v_user_is_p1 AS current_user_is_participant_1;
END;
$$;

COMMENT ON FUNCTION create_or_get_conversation_v2 IS 'v2: 建立或取得兩個用戶之間的對話';

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
        ON CONFLICT (conversation_id, item_id) DO NOTHING;
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
        c.id AS conversation_id,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN c.participant_2_id
            ELSE c.participant_1_id
        END AS other_user_id,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN u2.name
            ELSE u1.name
        END AS other_user_name,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN u2.avatar_url
            ELSE u1.avatar_url
        END AS other_user_avatar,
        c.initial_item_id,
        i.title AS initial_item_title,
        (
            SELECT m.content
            FROM public.conversation_messages_v2 m
            WHERE m.conversation_id = c.id
              AND m.is_deleted = false
            ORDER BY m.created_at DESC
            LIMIT 1
        ) AS last_message_content,
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
        ) AS unread_count,
        CASE
            WHEN c.participant_1_id = v_current_user_id THEN c.archived_by_participant_1
            ELSE c.archived_by_participant_2
        END AS is_archived,
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
        m.id AS message_id,
        m.sender_id,
        u.name AS sender_name,
        u.avatar_url AS sender_avatar,
        m.content,
        m.message_type,
        m.related_item_id,
        i.title AS related_item_title,
        m.is_deleted,
        (m.sender_id = v_current_user_id) AS is_mine,
        CASE
            WHEN v_user_is_p1 THEN m.read_by_participant_1
            ELSE m.read_by_participant_2
        END AS is_read,
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
        i.image_url AS item_image_url,
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
        ) AS message_count
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

-- ============================================================================
-- SECTION 6: 數據遷移函數
-- ============================================================================

-- 6.1 v1 到 v2 批次遷移
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
            ON CONFLICT (participant_1_id, participant_2_id) DO UPDATE SET
                updated_at = EXCLUDED.updated_at,
                initial_item_id = COALESCE(EXCLUDED.initial_item_id, EXCLUDED.initial_item_id);

            -- 查詢已插入或更新的對話 ID
            SELECT id INTO v_new_conv_id
            FROM public.conversations_v2
            WHERE participant_1_id = v_participant_1
              AND participant_2_id = v_participant_2;

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
            ON CONFLICT DO NOTHING;

            GET DIAGNOSTICS v_msg_count = ROW_COUNT;

            v_migrated_msg := v_migrated_msg + v_msg_count;

        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(
                v_errors,
                format('Error migrating conversation %s: %s', v_conv_record.id, SQLERRM)
            );
        END;
    END LOOP;

    RETURN QUERY SELECT v_migrated_conv AS migrated_conversations, v_migrated_msg AS migrated_messages, v_errors AS errors;
END;
$$;

COMMENT ON FUNCTION migrate_conversations_v1_to_v2 IS '批次遷移 v1 對話和訊息到 v2 (修正版 - 適配 v1 實際欄位)';

-- 6.2 驗證遷移完整性
CREATE OR REPLACE FUNCTION verify_migration_v1_to_v2()
RETURNS TABLE(
    check_name TEXT,
    v1_count BIGINT,
    v2_count BIGINT,
    is_valid BOOLEAN,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        'Conversation Count'::TEXT,
        (SELECT COUNT(*) FROM public.conversations)::BIGINT,
        (SELECT COUNT(*) FROM public.conversations_v2)::BIGINT,
        (SELECT COUNT(*) FROM public.conversations) <= (SELECT COUNT(*) FROM public.conversations_v2),
        'v2 should have equal or more conversations'::TEXT;

    RETURN QUERY
    SELECT
        'Message Count'::TEXT,
        (SELECT COUNT(*) FROM public.conversation_messages)::BIGINT,
        (SELECT COUNT(*) FROM public.conversation_messages_v2)::BIGINT,
        (SELECT COUNT(*) FROM public.conversation_messages) = (SELECT COUNT(*) FROM public.conversation_messages_v2),
        'Message counts should match'::TEXT;

    RETURN QUERY
    SELECT
        'Participant Order'::TEXT,
        NULL::BIGINT,
        (SELECT COUNT(*) FROM public.conversations_v2 WHERE participant_1_id >= participant_2_id)::BIGINT,
        (SELECT COUNT(*) FROM public.conversations_v2 WHERE participant_1_id >= participant_2_id) = 0,
        'All conversations should have participant_1_id < participant_2_id'::TEXT;
END;
$$;

COMMENT ON FUNCTION verify_migration_v1_to_v2 IS '驗證 v1 到 v2 遷移的完整性';

-- ============================================================================
-- SECTION 7: 完成
-- ============================================================================

COMMIT;

-- 輸出成功訊息
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Messaging System v2 安裝完成!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '已建立的資料表:';
    RAISE NOTICE '  - conversations_v2';
    RAISE NOTICE '  - conversation_messages_v2';
    RAISE NOTICE '  - conversation_items_v2';
    RAISE NOTICE '';
    RAISE NOTICE '已建立的函數:';
    RAISE NOTICE '  - create_or_get_conversation_v2()';
    RAISE NOTICE '  - send_message_v2()';
    RAISE NOTICE '  - get_user_conversations_v2()';
    RAISE NOTICE '  - get_conversation_messages_v2()';
    RAISE NOTICE '  - mark_messages_as_read_v2()';
    RAISE NOTICE '  - get_conversation_items_v2()';
    RAISE NOTICE '  - toggle_conversation_archive_v2()';
    RAISE NOTICE '  - migrate_conversations_v1_to_v2()';
    RAISE NOTICE '  - verify_migration_v1_to_v2()';
    RAISE NOTICE '';
    RAISE NOTICE '下一步:';
    RAISE NOTICE '  1. 執行數據遷移: SELECT * FROM migrate_conversations_v1_to_v2();';
    RAISE NOTICE '  2. 驗證遷移結果: SELECT * FROM verify_migration_v1_to_v2();';
    RAISE NOTICE '  3. 更新前端代碼以使用 v2 API';
    RAISE NOTICE '';
END $$;
