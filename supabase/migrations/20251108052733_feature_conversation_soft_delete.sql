-- =============================================
-- Migration: 實作軟刪除機制 (Soft Deletes)
-- 檔案: 20251108052733_feature_conversation_soft_delete.sql
-- 目標: 允許使用者刪除對話/訊息但不真正移除資料，支援單方面刪除
-- =============================================

-- =============================================
-- 1. 資料表結構調整
-- =============================================

-- 對話表：支援雙方分別刪除
-- deleted_by_buyer_at: 買家刪除對話的時間
-- deleted_by_seller_at: 賣家刪除對話的時間
ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS deleted_by_buyer_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS deleted_by_seller_at TIMESTAMPTZ NULL;

-- 訊息表：支援發送者刪除（刪除後雙方都不可見）
-- deleted_at: 訊息被刪除的時間
-- deleted_by: 刪除訊息的使用者 ID
ALTER TABLE public.conversation_messages
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS deleted_by UUID NULL REFERENCES public.users(id) ON DELETE SET NULL;

-- =============================================
-- 2. 建立索引以提升查詢效能
-- =============================================

-- 加速查詢未刪除的訊息
CREATE INDEX IF NOT EXISTS idx_messages_not_deleted
ON public.conversation_messages(conversation_id, sent_at DESC)
WHERE deleted_at IS NULL;

-- 加速查詢買家未刪除的對話
CREATE INDEX IF NOT EXISTS idx_conversations_buyer_not_deleted
ON public.conversations(buyer_id, updated_at DESC)
WHERE deleted_by_buyer_at IS NULL;

-- 加速查詢賣家未刪除的對話
CREATE INDEX IF NOT EXISTS idx_conversations_seller_not_deleted
ON public.conversations(seller_id, updated_at DESC)
WHERE deleted_by_seller_at IS NULL;

-- =============================================
-- 3. RPC 函數：刪除對話（單方面）
-- =============================================

CREATE OR REPLACE FUNCTION public.delete_conversation(
    p_conversation_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_buyer_id UUID;
    v_seller_id UUID;
    v_is_buyer BOOLEAN;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 取得對話資訊
    SELECT buyer_id, seller_id
    INTO v_buyer_id, v_seller_id
    FROM public.conversations
    WHERE id = p_conversation_id;

    -- 檢查對話是否存在
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION '對話不存在'
            USING HINT = '請確認對話 ID 是否正確',
                  ERRCODE = '22023';
    END IF;

    -- 檢查是否為對話參與者
    IF v_current_uid != v_buyer_id AND v_current_uid != v_seller_id THEN
        RAISE EXCEPTION '無權限刪除此對話'
            USING HINT = '您不是此對話的參與者',
                  ERRCODE = '42501';
    END IF;

    -- 判斷使用者角色
    v_is_buyer := (v_current_uid = v_buyer_id);

    -- 根據使用者角色更新對應的刪除時間戳
    IF v_is_buyer THEN
        UPDATE public.conversations
        SET deleted_by_buyer_at = now()
        WHERE id = p_conversation_id
          AND deleted_by_buyer_at IS NULL; -- 防止重複刪除
    ELSE
        UPDATE public.conversations
        SET deleted_by_seller_at = now()
        WHERE id = p_conversation_id
          AND deleted_by_seller_at IS NULL; -- 防止重複刪除
    END IF;

    -- 返回刪除結果
    RETURN jsonb_build_object(
        'success', true,
        'conversation_id', p_conversation_id,
        'deleted_by_role', CASE WHEN v_is_buyer THEN 'buyer' ELSE 'seller' END,
        'deleted_at', now()
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '刪除對話時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

-- =============================================
-- 4. RPC 函數：恢復已刪除的對話
-- =============================================

CREATE OR REPLACE FUNCTION public.restore_conversation(
    p_conversation_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_buyer_id UUID;
    v_seller_id UUID;
    v_is_buyer BOOLEAN;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 取得對話資訊
    SELECT buyer_id, seller_id
    INTO v_buyer_id, v_seller_id
    FROM public.conversations
    WHERE id = p_conversation_id;

    -- 檢查對話是否存在
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION '對話不存在';
    END IF;

    -- 檢查是否為對話參與者
    IF v_current_uid != v_buyer_id AND v_current_uid != v_seller_id THEN
        RAISE EXCEPTION '無權限恢復此對話';
    END IF;

    -- 判斷使用者角色
    v_is_buyer := (v_current_uid = v_buyer_id);

    -- 根據使用者角色清除刪除時間戳
    IF v_is_buyer THEN
        UPDATE public.conversations
        SET deleted_by_buyer_at = NULL
        WHERE id = p_conversation_id;
    ELSE
        UPDATE public.conversations
        SET deleted_by_seller_at = NULL
        WHERE id = p_conversation_id;
    END IF;

    -- 返回恢復結果
    RETURN jsonb_build_object(
        'success', true,
        'conversation_id', p_conversation_id,
        'restored_by_role', CASE WHEN v_is_buyer THEN 'buyer' ELSE 'seller' END,
        'restored_at', now()
    );
END;
$$;

-- =============================================
-- 5. RPC 函數：刪除訊息
-- =============================================

CREATE OR REPLACE FUNCTION public.delete_message(
    p_message_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_sender_id UUID;
    v_conversation_id BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 取得訊息的發送者和對話 ID
    SELECT sender_id, conversation_id
    INTO v_sender_id, v_conversation_id
    FROM public.conversation_messages
    WHERE id = p_message_id
      AND deleted_at IS NULL; -- 已刪除的訊息不能再次刪除

    -- 檢查訊息是否存在
    IF v_sender_id IS NULL THEN
        RAISE EXCEPTION '訊息不存在或已被刪除'
            USING HINT = '請確認訊息 ID 是否正確',
                  ERRCODE = '22023';
    END IF;

    -- 只有發送者可以刪除訊息
    IF v_current_uid != v_sender_id THEN
        RAISE EXCEPTION '只能刪除自己發送的訊息'
            USING HINT = '您沒有權限刪除其他人的訊息',
                  ERRCODE = '42501';
    END IF;

    -- 標記訊息為已刪除
    UPDATE public.conversation_messages
    SET deleted_at = now(),
        deleted_by = v_current_uid
    WHERE id = p_message_id;

    -- 返回刪除結果
    RETURN jsonb_build_object(
        'success', true,
        'message_id', p_message_id,
        'conversation_id', v_conversation_id,
        'deleted_at', now()
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '刪除訊息時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

-- =============================================
-- 6. RPC 函數：清理雙方都已刪除的對話
-- =============================================

CREATE OR REPLACE FUNCTION public.cleanup_deleted_conversations(
    p_days_threshold INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted_count INTEGER;
    v_threshold_date TIMESTAMPTZ;
BEGIN
    -- 計算閾值日期
    v_threshold_date := now() - (p_days_threshold || ' days')::INTERVAL;

    -- 刪除雙方都已刪除且超過閾值天數的對話
    WITH deleted_conversations AS (
        DELETE FROM public.conversations
        WHERE deleted_by_buyer_at IS NOT NULL
          AND deleted_by_seller_at IS NOT NULL
          AND deleted_by_buyer_at < v_threshold_date
          AND deleted_by_seller_at < v_threshold_date
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_count FROM deleted_conversations;

    -- 返回清理結果
    RETURN jsonb_build_object(
        'success', true,
        'deleted_count', v_deleted_count,
        'threshold_days', p_days_threshold,
        'threshold_date', v_threshold_date,
        'cleaned_at', now()
    );
END;
$$;

-- =============================================
-- 7. 修改現有函數：get_user_conversations
-- =============================================

-- 刪除舊版本的函數（如果存在）以避免函數簽名衝突
DROP FUNCTION IF EXISTS public.get_user_conversations(INT, INT);

CREATE OR REPLACE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_role TEXT DEFAULT 'all',
    p_include_deleted BOOLEAN DEFAULT false  -- 新增參數：是否包含已刪除的對話
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
    is_deleted BOOLEAN  -- 新增欄位：標示是否已被當前使用者刪除
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
        -- 只顯示未刪除訊息中的最新一則
        (SELECT content
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND deleted_at IS NULL
         ORDER BY sent_at DESC
         LIMIT 1),
        (SELECT sent_at
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND deleted_at IS NULL
         ORDER BY sent_at DESC
         LIMIT 1),
        -- 只計算未刪除且未讀的訊息
        (SELECT COUNT(*)
         FROM public.conversation_messages
         WHERE conversation_id = c.id
           AND sender_id != v_current_uid
           AND is_read = false
           AND deleted_at IS NULL),
        c.created_at,
        c.updated_at,
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

-- =============================================
-- 8. 修改現有函數：get_conversation_messages
-- =============================================

-- 刪除舊版本的函數（如果存在）以避免函數簽名衝突
DROP FUNCTION IF EXISTS public.get_conversation_messages(BIGINT, INT, INT);

CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false  -- 新增參數：是否包含已刪除的訊息
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    sender_nickname VARCHAR(50),
    sender_profile_picture TEXT,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ,
    is_deleted BOOLEAN,  -- 新增欄位：標示訊息是否已刪除
    deleted_at TIMESTAMPTZ  -- 新增欄位：刪除時間
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

    RETURN QUERY
    SELECT
        cm.id,
        cm.sender_id,
        u.nickname,
        u.profile_picture_url,
        cm.content,
        cm.is_read,
        cm.sent_at,
        (cm.deleted_at IS NOT NULL) AS is_deleted,
        cm.deleted_at
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
      -- 過濾已刪除的訊息（除非 p_include_deleted = true）
      AND (p_include_deleted = true OR cm.deleted_at IS NULL)
    ORDER BY cm.sent_at ASC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- 9. 註解說明
-- =============================================

COMMENT ON COLUMN public.conversations.deleted_by_buyer_at IS
'買家刪除此對話的時間戳。NULL 表示未刪除，買家仍可見此對話';

COMMENT ON COLUMN public.conversations.deleted_by_seller_at IS
'賣家刪除此對話的時間戳。NULL 表示未刪除，賣家仍可見此對話';

COMMENT ON COLUMN public.conversation_messages.deleted_at IS
'訊息被刪除的時間戳。刪除後雙方都不可見';

COMMENT ON COLUMN public.conversation_messages.deleted_by IS
'刪除此訊息的使用者 ID（通常是發送者）';

COMMENT ON FUNCTION public.delete_conversation(BIGINT) IS
'單方面刪除對話。買家刪除不影響賣家，反之亦然';

COMMENT ON FUNCTION public.restore_conversation(BIGINT) IS
'恢復已刪除的對話。使用者可以撤銷自己的刪除操作';

COMMENT ON FUNCTION public.delete_message(BIGINT) IS
'刪除訊息。只有發送者可以刪除，刪除後雙方都不可見';

COMMENT ON FUNCTION public.cleanup_deleted_conversations(INT) IS
'清理雙方都已刪除且超過指定天數的對話。建議透過 pg_cron 定期執行';

-- =============================================
-- 10. 權限設定
-- =============================================

-- 新增的軟刪除函數權限
GRANT EXECUTE ON FUNCTION public.delete_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_message(BIGINT) TO authenticated;
-- cleanup 函數只允許管理員執行，不開放給一般使用者
REVOKE EXECUTE ON FUNCTION public.cleanup_deleted_conversations(INT) FROM PUBLIC;

-- 重新授予被修改函數的權限（因為 DROP FUNCTION 會移除權限）
GRANT EXECUTE ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) TO authenticated;

-- =============================================
-- 11. 設定定期清理任務 (使用 pg_cron)
-- =============================================

-- 注意：需要先啟用 pg_cron 擴充
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 每週日凌晨 3 點執行清理（刪除 30 天前雙方都已刪除的對話）
-- SELECT cron.schedule(
--     'cleanup-deleted-conversations',
--     '0 3 * * 0',
--     $$SELECT public.cleanup_deleted_conversations(30)$$
-- );

-- =============================================
-- 12. 驗證與統計
-- =============================================

DO $$
DECLARE
    v_total_conversations INT;
    v_soft_deleted_conversations INT;
    v_soft_deleted_messages INT;
BEGIN
    -- 統計對話總數
    SELECT COUNT(*) INTO v_total_conversations FROM public.conversations;

    -- 統計至少被一方刪除的對話數
    SELECT COUNT(*) INTO v_soft_deleted_conversations
    FROM public.conversations
    WHERE deleted_by_buyer_at IS NOT NULL OR deleted_by_seller_at IS NOT NULL;

    -- 統計被軟刪除的訊息數
    SELECT COUNT(*) INTO v_soft_deleted_messages
    FROM public.conversation_messages
    WHERE deleted_at IS NOT NULL;

    RAISE NOTICE '========================================';
    RAISE NOTICE '✓ 軟刪除功能 Migration 執行成功！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 統計資訊:';
    RAISE NOTICE '  - 對話總數: %', v_total_conversations;
    RAISE NOTICE '  - 已軟刪除對話: %', v_soft_deleted_conversations;
    RAISE NOTICE '  - 已軟刪除訊息: %', v_soft_deleted_messages;
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎯 已完成項目:';
    RAISE NOTICE '  1. ✓ 新增軟刪除欄位';
    RAISE NOTICE '  2. ✓ 建立效能索引';
    RAISE NOTICE '  3. ✓ 實作 delete_conversation (單方面刪除)';
    RAISE NOTICE '  4. ✓ 實作 restore_conversation (恢復刪除)';
    RAISE NOTICE '  5. ✓ 實作 delete_message (刪除訊息)';
    RAISE NOTICE '  6. ✓ 實作 cleanup_deleted_conversations (清理)';
    RAISE NOTICE '  7. ✓ 更新 get_user_conversations';
    RAISE NOTICE '  8. ✓ 更新 get_conversation_messages';
    RAISE NOTICE '========================================';
    RAISE NOTICE '💡 後續步驟:';
    RAISE NOTICE '  - 在前端 conversationAPI.js 新增對應函數';
    RAISE NOTICE '  - 設定 pg_cron 定期清理任務';
    RAISE NOTICE '  - 更新 RLS 政策（如已啟用）';
    RAISE NOTICE '  - 進行完整的功能測試';
    RAISE NOTICE '========================================';
END $$;
