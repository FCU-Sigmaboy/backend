-- =============================================
-- 使用者訊息傳遞功能設定
-- 建立日期: 2025-10-29
-- =============================================

-- =============================================
-- 資料庫觸發器：自動更新對話的 updated_at
-- =============================================

-- 建立觸發器函數：當新訊息發送時更新對話的 updated_at
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations
    SET updated_at = NEW.sent_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 建立觸發器：當新訊息插入時自動更新對話時間
CREATE TRIGGER trigger_update_conversation_on_new_message
    AFTER INSERT ON public.conversation_messages
    FOR EACH ROW EXECUTE FUNCTION update_conversation_timestamp();

-- =============================================
-- RPC 函數 1: 取得使用者的所有對話
-- =============================================

CREATE OR REPLACE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    item_title TEXT,
    item_image_url TEXT,
    other_user_id UUID,
    other_user_nickname VARCHAR(50),
    other_user_profile_picture TEXT,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    unread_count BIGINT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    v_offset := (p_page - 1) * p_size;

    RETURN QUERY
    SELECT 
        c.id,
        c.item_id,
        i.title,
        i.image_urls[1],
        CASE 
            WHEN c.buyer_id = v_current_uid THEN c.seller_id
            ELSE c.buyer_id
        END,
        CASE 
            WHEN c.buyer_id = v_current_uid THEN u_seller.nickname
            ELSE u_buyer.nickname
        END,
        CASE 
            WHEN c.buyer_id = v_current_uid THEN u_seller.profile_picture_url
            ELSE u_buyer.profile_picture_url
        END,
        (SELECT content 
         FROM public.conversation_messages 
         WHERE conversation_id = c.id 
         ORDER BY sent_at DESC 
         LIMIT 1),
        (SELECT sent_at 
         FROM public.conversation_messages 
         WHERE conversation_id = c.id 
         ORDER BY sent_at DESC 
         LIMIT 1),
        (SELECT COUNT(*) 
         FROM public.conversation_messages 
         WHERE conversation_id = c.id 
           AND sender_id != v_current_uid 
           AND is_read = false),
        c.created_at,
        c.updated_at
    FROM public.conversations c
    LEFT JOIN public.items i ON c.item_id = i.id
    LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
    LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
    WHERE c.buyer_id = v_current_uid OR c.seller_id = v_current_uid
    ORDER BY c.updated_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- RPC 函數 2: 取得對話的所有訊息
-- =============================================

CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    sender_nickname VARCHAR(50),
    sender_profile_picture TEXT,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 檢查使用者是否為對話參與者
    IF NOT EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE id = p_conversation_id 
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '無權限查看此對話';
    END IF;

    v_offset := (p_page - 1) * p_size;

    RETURN QUERY
    SELECT 
        cm.id,
        cm.sender_id,
        u.nickname,
        u.profile_picture_url,
        cm.content,
        cm.is_read,
        cm.sent_at
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
    ORDER BY cm.sent_at ASC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- RPC 函數 3: 發送訊息
-- =============================================

CREATE OR REPLACE FUNCTION public.send_message(
    p_conversation_id BIGINT,
    p_content TEXT
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_message_id BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 檢查訊息內容是否為空
    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空';
    END IF;

    -- 檢查使用者是否為對話參與者
    IF NOT EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE id = p_conversation_id 
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '無權限在此對話中發送訊息';
    END IF;

    -- 插入訊息
    INSERT INTO public.conversation_messages (conversation_id, sender_id, content)
    VALUES (p_conversation_id, v_current_uid, p_content)
    RETURNING id INTO v_message_id;

    -- 返回插入的訊息
    RETURN QUERY
    SELECT 
        cm.id,
        cm.sender_id,
        cm.content,
        cm.is_read,
        cm.sent_at
    FROM public.conversation_messages cm
    WHERE cm.id = v_message_id;
END;
$$;

-- =============================================
-- RPC 函數 4: 標記訊息為已讀
-- =============================================

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(
    p_conversation_id BIGINT
)
RETURNS TABLE (
    updated_count BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_count BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 檢查使用者是否為對話參與者
    IF NOT EXISTS (
        SELECT 1 FROM public.conversations 
        WHERE id = p_conversation_id 
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '無權限修改此對話的訊息狀態';
    END IF;

    -- 更新訊息為已讀（只更新非自己發送的未讀訊息）
    UPDATE public.conversation_messages
    SET is_read = true
    WHERE conversation_id = p_conversation_id
      AND sender_id != v_current_uid
      AND is_read = false;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN QUERY SELECT v_count;
END;
$$;

-- =============================================
-- RPC 函數 5: 建立或取得對話
-- =============================================

CREATE OR REPLACE FUNCTION public.create_or_get_conversation(
    p_item_id BIGINT
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    buyer_id UUID,
    seller_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_item_user_id UUID;
    v_conversation_id BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 取得物品擁有者
    SELECT user_id INTO v_item_user_id
    FROM public.items
    WHERE id = p_item_id AND listing_status = true;

    -- 檢查物品是否存在且上架中
    IF v_item_user_id IS NULL THEN
        RAISE EXCEPTION '物品不存在或已下架';
    END IF;

    -- 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話';
    END IF;

    -- 嘗試取得現有對話
    SELECT id INTO v_conversation_id
    FROM public.conversations
    WHERE item_id = p_item_id 
      AND buyer_id = v_current_uid 
      AND seller_id = v_item_user_id;

    -- 如果對話不存在，建立新對話
    IF v_conversation_id IS NULL THEN
        INSERT INTO public.conversations (item_id, buyer_id, seller_id)
        VALUES (p_item_id, v_current_uid, v_item_user_id)
        RETURNING id INTO v_conversation_id;
    END IF;

    -- 返回對話資訊
    RETURN QUERY
    SELECT 
        c.id,
        c.item_id,
        c.buyer_id,
        c.seller_id,
        c.created_at,
        c.updated_at
    FROM public.conversations c
    WHERE c.id = v_conversation_id;
END;
$$;

-- =============================================
-- RPC 函數 6: 取得未讀訊息總數
-- =============================================

CREATE OR REPLACE FUNCTION public.get_unread_message_count()
RETURNS TABLE (
    unread_count BIGINT
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    RETURN QUERY
    SELECT COUNT(*)
    FROM public.conversation_messages cm
    WHERE cm.sender_id != v_current_uid
      AND cm.is_read = false
      AND EXISTS (
          SELECT 1 FROM public.conversations c
          WHERE c.id = cm.conversation_id
            AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
      );
END;
$$;

-- =============================================
-- 啟用 Realtime 功能
-- =============================================

-- 為 conversations 表啟用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;

-- 為 conversation_messages 表啟用 Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_messages;

-- =============================================
-- 建立額外的索引以優化查詢效能
-- =============================================

-- 為訊息的已讀狀態和發送者建立複合索引
CREATE INDEX IF NOT EXISTS idx_conversation_messages_unread 
ON public.conversation_messages(conversation_id, sender_id, is_read) 
WHERE is_read = false;

-- 為對話的更新時間建立索引（用於排序）
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at 
ON public.conversations(updated_at DESC);

-- =============================================
-- 授予執行權限給已認證使用者
-- =============================================

GRANT EXECUTE ON FUNCTION public.get_user_conversations TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_message TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_or_get_conversation TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_message_count TO authenticated;
