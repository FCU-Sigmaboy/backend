-- =============================================
-- 修復: 所有 Messaging 相關函數的歧義性欄位參照
-- =============================================
-- 問題: RETURNS TABLE 的欄位名稱與 SELECT 語句中的欄位名稱衝突，導致 PostgreSQL 42702 錯誤
-- 解決: 使用 AS 子句明確指定所有欄位別名
-- 日期: 2025-11-08
-- 相關錯誤: column reference is ambiguous (SQLSTATE 42702)
-- 影響函數: get_user_conversations, get_conversation_messages, send_message
-- =============================================

-- 1. 修復 get_user_conversations 函數
CREATE OR REPLACE FUNCTION public.get_user_conversations(
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
SECURITY DEFINER
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

    -- 返回對話列表（使用 AS 明確指定所有欄位別名以避免歧義）
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
        -- 只顯示未刪除訊息中的最新一則
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
        -- 只計算未刪除且未讀的訊息
        (SELECT COUNT(*)
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND sender_id != v_current_uid
           AND is_read = false
           AND deleted_at IS NULL) AS unread_count,
        c.created_at AS created_at,
        c.updated_at AS updated_at,
        -- 標示是否已被當前使用者刪除
        CASE
            WHEN c.buyer_id = v_current_uid THEN (c.deleted_by_buyer_at IS NOT NULL)
            ELSE (c.deleted_by_seller_at IS NOT NULL)
        END AS is_deleted
    FROM public.conversations c
    LEFT JOIN public.items i ON c.item_id = i.id
    LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
    LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
    WHERE
        -- 根據 role 參數過濾
        CASE
            WHEN p_role = 'buyer' THEN c.buyer_id = v_current_uid
            WHEN p_role = 'seller' THEN c.seller_id = v_current_uid
            ELSE (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
        END
        -- 過濾當前使用者已刪除的對話（除非 p_include_deleted = true）
        AND (
            p_include_deleted = true OR
            (c.buyer_id = v_current_uid AND c.deleted_by_buyer_at IS NULL) OR
            (c.seller_id = v_current_uid AND c.deleted_by_seller_at IS NULL)
        )
    ORDER BY c.updated_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- 2. 修復 get_conversation_messages 函數
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
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
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ,
    is_deleted BOOLEAN,
    deleted_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
    v_is_participant BOOLEAN;
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

    -- 檢查使用者是否為對話參與者
    SELECT EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = p_conversation_id
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) INTO v_is_participant;

    IF NOT v_is_participant THEN
        RAISE EXCEPTION '無權限查看此對話'
            USING HINT = '您不是此對話的參與者',
                  ERRCODE = '42501';
    END IF;

    v_offset := (p_page - 1) * p_size;

    -- 返回訊息列表（使用 AS 明確指定所有欄位別名以避免歧義）
    RETURN QUERY
    SELECT
        cm.id AS message_id,
        cm.sender_id AS sender_id,
        u.nickname AS sender_nickname,
        u.profile_picture_url AS sender_profile_picture,
        cm.content AS content,
        cm.is_read AS is_read,
        cm.sent_at AS sent_at,
        (cm.deleted_at IS NOT NULL) AS is_deleted,
        cm.deleted_at AS deleted_at
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
      -- 過濾已刪除的訊息（除非 p_include_deleted = true）
      AND (p_include_deleted = true OR cm.deleted_at IS NULL)
    ORDER BY cm.sent_at ASC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- 3. 修復 send_message 函數
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_message_id BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 檢查訊息內容是否為空
    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空'
            USING HINT = '請提供有效的訊息內容',
                  ERRCODE = '22023';
    END IF;

    -- 檢查使用者是否為對話參與者
    IF NOT EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = p_conversation_id
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '無權限在此對話中發送訊息'
            USING HINT = '您不是此對話的參與者',
                  ERRCODE = '42501';
    END IF;

    -- 插入訊息
    INSERT INTO public.conversation_messages (conversation_id, sender_id, content)
    VALUES (p_conversation_id, v_current_uid, p_content)
    RETURNING id INTO v_message_id;

    -- 返回插入的訊息（使用 AS 明確指定所有欄位別名以避免歧義）
    RETURN QUERY
    SELECT
        cm.id AS message_id,
        cm.sender_id AS sender_id,
        cm.content AS content,
        cm.is_read AS is_read,
        cm.sent_at AS sent_at
    FROM public.conversation_messages cm
    WHERE cm.id = v_message_id;

EXCEPTION
    WHEN OTHERS THEN
        -- 記錄錯誤並重新拋出
        RAISE NOTICE '發送訊息時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

-- =============================================
-- 4. 確保權限設定正確
-- =============================================

GRANT EXECUTE ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_message(BIGINT, TEXT) TO authenticated;

-- =============================================
-- 5. 更新函數註解
-- =============================================

COMMENT ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) IS
'取得使用者的對話列表（支援軟刪除）。
修復: 使用 AS 子句解決欄位名稱歧義問題 (PostgreSQL 42702 錯誤)。
版本: 1.1 (2025-11-08)';

COMMENT ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) IS
'取得對話的訊息列表（支援軟刪除）。
修復: 使用 AS 子句解決欄位名稱歧義問題 (PostgreSQL 42702 錯誤)。
版本: 1.1 (2025-11-08)';

COMMENT ON FUNCTION public.send_message(BIGINT, TEXT) IS
'在對話中發送訊息。
修復: 使用 AS 子句解決欄位名稱歧義問題 (PostgreSQL 42702 錯誤)。
優化: 改善錯誤處理和安全性設定。
版本: 1.1 (2025-11-08)';

-- =============================================
-- 6. 驗證修復
-- =============================================

DO $$
DECLARE
    v_test_result RECORD;
    v_function_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證 Messaging 函數修復狀態';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查 get_user_conversations
    SELECT
        p.proname AS function_name,
        pg_get_function_result(p.oid) AS return_type
    INTO v_test_result
    FROM pg_proc p
    WHERE p.proname = 'get_user_conversations'
      AND pg_get_function_arguments(p.oid) LIKE '%p_include_deleted%';

    IF v_test_result.function_name IS NOT NULL THEN
        RAISE NOTICE '✅ get_user_conversations 函數已成功更新';
        v_function_count := v_function_count + 1;
    ELSE
        RAISE WARNING '⚠️ get_user_conversations 函數未找到或參數不符';
    END IF;

    -- 檢查 get_conversation_messages
    SELECT
        p.proname AS function_name,
        pg_get_function_result(p.oid) AS return_type
    INTO v_test_result
    FROM pg_proc p
    WHERE p.proname = 'get_conversation_messages'
      AND pg_get_function_arguments(p.oid) LIKE '%p_include_deleted%';

    IF v_test_result.function_name IS NOT NULL THEN
        RAISE NOTICE '✅ get_conversation_messages 函數已成功更新';
        v_function_count := v_function_count + 1;
    ELSE
        RAISE WARNING '⚠️ get_conversation_messages 函數未找到或參數不符';
    END IF;

    -- 檢查 send_message
    SELECT
        p.proname AS function_name,
        pg_get_function_result(p.oid) AS return_type
    INTO v_test_result
    FROM pg_proc p
    WHERE p.proname = 'send_message'
      AND pg_get_function_arguments(p.oid) LIKE '%p_conversation_id%';

    IF v_test_result.function_name IS NOT NULL THEN
        RAISE NOTICE '✅ send_message 函數已成功更新';
        v_function_count := v_function_count + 1;
    ELSE
        RAISE WARNING '⚠️ send_message 函數未找到或參數不符';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    IF v_function_count = 3 THEN
        RAISE NOTICE '🎉 所有函數修復完成！(%/3)', v_function_count;
        RAISE NOTICE '';
        RAISE NOTICE '📝 下一步：';
        RAISE NOTICE '   1. 測試對話列表功能';
        RAISE NOTICE '   2. 測試訊息歷史功能';
        RAISE NOTICE '   3. 測試發送訊息功能';
        RAISE NOTICE '   4. 確認沒有 42702 錯誤';
    ELSE
        RAISE WARNING '⚠️ 僅修復 %/3 個函數，請檢查', v_function_count;
    END IF;
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

