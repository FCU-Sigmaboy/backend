-- =============================================
-- 恢復遷移：重新啟用 SECURITY DEFINER
-- =============================================
-- 用途: 恢復原本的安全設定
-- 使用時機: 除錯完成後執行此遷移
-- =============================================
-- 日期: 2024-XX-XX
-- 影響函數: get_user_conversations, get_conversation_messages, send_message 等
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  🔒 恢復 SECURITY DEFINER (正常模式)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '正在恢復安全設定...';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 先刪除現有函數以避免簽名衝突
-- =============================================
DROP FUNCTION IF EXISTS public.get_user_conversations(INT, INT, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN);
DROP FUNCTION IF EXISTS public.send_message(BIGINT, TEXT);

-- =============================================
-- 1. 重新建立 get_user_conversations (含 SECURITY DEFINER)
-- =============================================
CREATE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_role TEXT DEFAULT 'all',
    p_include_deleted BOOLEAN DEFAULT false
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
    updated_at TIMESTAMPTZ,
    is_deleted BOOLEAN
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER  -- 已恢復
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 驗證分頁參數
    IF p_page < 1 THEN
        RAISE EXCEPTION '頁碼必須大於 0';
    END IF;
    IF p_size < 1 OR p_size > 100 THEN
        RAISE EXCEPTION '每頁數量必須在 1 到 100 之間';
    END IF;

    -- 驗證 role 參數
    IF p_role NOT IN ('buyer', 'seller', 'all') THEN
        RAISE EXCEPTION 'role 參數必須是 buyer, seller 或 all';
    END IF;

    v_offset := (p_page - 1) * p_size;

    -- 返回對話列表
    RETURN QUERY
    SELECT
        c.id AS conversation_id,
        c.item_id AS item_id,
        i.title AS item_title,
        i.image_urls[1] AS item_image_url,
        CASE
            WHEN c.buyer_id = v_current_uid THEN c.seller_id
            ELSE c.buyer_id
        END AS other_user_id,
        CASE
            WHEN c.buyer_id = v_current_uid THEN u_seller.nickname
            ELSE u_buyer.nickname
        END AS other_user_nickname,
        CASE
            WHEN c.buyer_id = v_current_uid THEN u_seller.profile_picture_url
            ELSE u_buyer.profile_picture_url
        END AS other_user_profile_picture,
        (SELECT content
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND deleted_at IS NULL
         ORDER BY sent_at DESC
         LIMIT 1) AS last_message,
        (SELECT sent_at
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND deleted_at IS NULL
         ORDER BY sent_at DESC
         LIMIT 1) AS last_message_time,
        (SELECT COUNT(*)
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND sender_id != v_current_uid
           AND is_read = false
           AND deleted_at IS NULL) AS unread_count,
        c.created_at AS created_at,
        c.updated_at AS updated_at,
        CASE
            WHEN c.buyer_id = v_current_uid THEN (c.deleted_by_buyer_at IS NOT NULL)
            ELSE (c.deleted_by_seller_at IS NOT NULL)
        END AS is_deleted
    FROM public.conversations c
    LEFT JOIN public.items i ON c.item_id = i.id
    LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
    LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
    WHERE
        CASE
            WHEN p_role = 'buyer' THEN c.buyer_id = v_current_uid
            WHEN p_role = 'seller' THEN c.seller_id = v_current_uid
            ELSE (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
        END
        AND (
            p_include_deleted = true OR
            (c.buyer_id = v_current_uid AND c.deleted_by_buyer_at IS NULL) OR
            (c.seller_id = v_current_uid AND c.deleted_by_seller_at IS NULL)
        )
    ORDER BY c.updated_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- 2. 重新建立 get_conversation_messages (含 SECURITY DEFINER)
-- =============================================
CREATE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    sender_nickname VARCHAR(50),
    sender_profile_picture TEXT,
    content TEXT,
    sent_at TIMESTAMPTZ,
    is_read BOOLEAN,
    is_deleted BOOLEAN
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER  -- 已恢復
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
    v_is_participant BOOLEAN;
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    IF p_page < 1 THEN
        RAISE EXCEPTION '頁碼必須大於 0';
    END IF;
    IF p_size < 1 OR p_size > 100 THEN
        RAISE EXCEPTION '每頁數量必須在 1 到 100 之間';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = p_conversation_id
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) INTO v_is_participant;

    IF NOT v_is_participant THEN
        RAISE EXCEPTION '使用者不是此對話的參與者';
    END IF;

    v_offset := (p_page - 1) * p_size;

    RETURN QUERY
    SELECT
        cm.id AS message_id,
        cm.sender_id AS sender_id,
        u.nickname AS sender_nickname,
        u.profile_picture_url AS sender_profile_picture,
        cm.content AS content,
        cm.sent_at AS sent_at,
        cm.is_read AS is_read,
        (cm.deleted_at IS NOT NULL) AS is_deleted
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
      AND (p_include_deleted = true OR cm.deleted_at IS NULL)
    ORDER BY cm.sent_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- 3. 重新建立 send_message (含 SECURITY DEFINER)
-- =============================================
CREATE FUNCTION public.send_message(
    p_conversation_id BIGINT,
    p_content TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER  -- 已恢復
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_is_participant BOOLEAN;
    v_message_id BIGINT;
    v_conversation_deleted BOOLEAN;
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空';
    END IF;

    IF LENGTH(p_content) > 1000 THEN
        RAISE EXCEPTION '訊息內容不能超過 1000 字元';
    END IF;

    SELECT
        EXISTS (
            SELECT 1 FROM public.conversations
            WHERE id = p_conversation_id
              AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
        ),
        EXISTS (
            SELECT 1 FROM public.conversations
            WHERE id = p_conversation_id
              AND (
                (buyer_id = v_current_uid AND deleted_by_buyer_at IS NOT NULL) OR
                (seller_id = v_current_uid AND deleted_by_seller_at IS NOT NULL)
              )
        )
    INTO v_is_participant, v_conversation_deleted;

    IF NOT v_is_participant THEN
        RAISE EXCEPTION '使用者不是此對話的參與者';
    END IF;

    IF v_conversation_deleted THEN
        UPDATE public.conversations
        SET
            deleted_by_buyer_at = CASE WHEN buyer_id = v_current_uid THEN NULL ELSE deleted_by_buyer_at END,
            deleted_by_seller_at = CASE WHEN seller_id = v_current_uid THEN NULL ELSE deleted_by_seller_at END,
            updated_at = NOW()
        WHERE id = p_conversation_id;
    END IF;

    INSERT INTO public.conversation_messages (conversation_id, sender_id, content)
    VALUES (p_conversation_id, v_current_uid, p_content)
    RETURNING id INTO v_message_id;

    UPDATE public.conversations
    SET updated_at = NOW()
    WHERE id = p_conversation_id;

    RETURN v_message_id;
END;
$$;

-- =============================================
-- 重新授予權限
-- =============================================
GRANT EXECUTE ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_message(BIGINT, TEXT) TO authenticated;

-- =============================================
-- 更新函數註解
-- =============================================
COMMENT ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) IS
'取得使用者的對話列表（支援軟刪除）。
安全模式: SECURITY DEFINER 已恢復。
版本: 1.2 (已恢復安全設定)';

COMMENT ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) IS
'取得對話訊息列表（支援軟刪除）。
安全模式: SECURITY DEFINER 已恢復。
版本: 1.2 (已恢復安全設定)';

COMMENT ON FUNCTION public.send_message(BIGINT, TEXT) IS
'發送訊息到指定對話。
安全模式: SECURITY DEFINER 已恢復。
版本: 1.2 (已恢復安全設定)';

-- =============================================
-- 完成訊息
-- =============================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  ✅ SECURITY DEFINER 已成功恢復';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '恢復內容:';
    RAISE NOTICE '  • get_user_conversations: SECURITY INVOKER → SECURITY DEFINER';
    RAISE NOTICE '  • get_conversation_messages: SECURITY INVOKER → SECURITY DEFINER';
    RAISE NOTICE '  • send_message: SECURITY INVOKER → SECURITY DEFINER';
    RAISE NOTICE '';
    RAISE NOTICE '✅ 所有安全設定已恢復正常';
    RAISE NOTICE '✅ 函數現在以定義者權限執行';
    RAISE NOTICE '✅ 除錯訊息已移除';
    RAISE NOTICE '';
    RAISE NOTICE '後續步驟:';
    RAISE NOTICE '  1. 可以刪除除錯用的遷移檔案';
    RAISE NOTICE '  2. 測試功能是否正常運作';
    RAISE NOTICE '  3. 確認安全性設定正確';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
