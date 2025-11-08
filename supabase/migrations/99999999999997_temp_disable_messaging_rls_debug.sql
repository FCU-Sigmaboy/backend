-- =============================================
-- 臨時除錯用遷移：停用 Messaging 相關 RLS
-- =============================================
-- ⚠️ 警告：此檔案僅供開發環境除錯使用
-- ⚠️ 不要在生產環境執行此遷移
-- ⚠️ 除錯完成後請使用 99999999999996_restore_messaging_rls.sql 恢復
-- =============================================
-- 日期: 2024-XX-XX
-- 目的: 暫時停用 RLS 以便除錯資料存取問題
-- 影響資料表: conversations, conversation_messages
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  ⚠️  停用 Messaging RLS (除錯模式)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '注意: 此遷移會暫時移除資料安全性';
    RAISE NOTICE '      完成除錯後請立即恢復';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 1. 備份現有的 RLS 政策資訊
-- =============================================
DO $$
DECLARE
    v_policy RECORD;
    v_policy_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  備份現有政策';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 列出 conversations 表的所有政策
    FOR v_policy IN
        SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename IN ('conversations', 'conversation_messages')
        ORDER BY tablename, policyname
    LOOP
        RAISE NOTICE '政策: %.% (%)', v_policy.tablename, v_policy.policyname, v_policy.cmd;
        v_policy_count := v_policy_count + 1;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '找到 % 個政策', v_policy_count;
    RAISE NOTICE '';
END $$;

-- =============================================
-- 2. 刪除 conversations 表的所有 RLS 政策
-- =============================================
DROP POLICY IF EXISTS "Conversation participants can view conversations" ON public.conversations;
DROP POLICY IF EXISTS "Buyers can initiate conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can view their own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_delete_policy" ON public.conversations;

-- =============================================
-- 3. 刪除 conversation_messages 表的所有 RLS 政策
-- =============================================
DROP POLICY IF EXISTS "Conversation participants can view messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Conversation participants can send messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_select_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_insert_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_update_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_delete_policy" ON public.conversation_messages;

-- =============================================
-- 4. 停用 RLS
-- =============================================
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages DISABLE ROW LEVEL SECURITY;

-- =============================================
-- 5. 驗證 RLS 狀態
-- =============================================
DO $$
DECLARE
    v_conversations_rls BOOLEAN;
    v_messages_rls BOOLEAN;
    v_policy_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證 RLS 狀態';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查 RLS 是否已停用
    SELECT relrowsecurity INTO v_conversations_rls
    FROM pg_class
    WHERE relname = 'conversations' AND relnamespace = 'public'::regnamespace;

    SELECT relrowsecurity INTO v_messages_rls
    FROM pg_class
    WHERE relname = 'conversation_messages' AND relnamespace = 'public'::regnamespace;

    -- 計算剩餘政策數量
    SELECT COUNT(*) INTO v_policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename IN ('conversations', 'conversation_messages');

    IF v_conversations_rls THEN
        RAISE WARNING '⚠️  conversations 表 RLS 仍然啟用';
    ELSE
        RAISE NOTICE '✅ conversations 表 RLS 已停用';
    END IF;

    IF v_messages_rls THEN
        RAISE WARNING '⚠️  conversation_messages 表 RLS 仍然啟用';
    ELSE
        RAISE NOTICE '✅ conversation_messages 表 RLS 已停用';
    END IF;

    RAISE NOTICE '剩餘政策數量: %', v_policy_count;

    IF v_policy_count > 0 THEN
        RAISE WARNING '⚠️  仍有 % 個政策存在', v_policy_count;
    ELSE
        RAISE NOTICE '✅ 所有政策已移除';
    END IF;

    RAISE NOTICE '';
END $$;

-- =============================================
-- 6. 建立臨時的除錯檢視
-- =============================================
CREATE OR REPLACE VIEW debug_conversations_raw AS
SELECT
    c.id,
    c.item_id,
    c.buyer_id,
    c.seller_id,
    c.created_at,
    c.updated_at,
    c.deleted_by_buyer_at,
    c.deleted_by_seller_at,
    i.title as item_title,
    u_buyer.nickname as buyer_nickname,
    u_seller.nickname as seller_nickname,
    (SELECT COUNT(*) FROM conversation_messages WHERE conversation_id = c.id) as total_messages,
    (SELECT COUNT(*) FROM conversation_messages WHERE conversation_id = c.id AND deleted_at IS NULL) as active_messages
FROM conversations c
LEFT JOIN items i ON c.item_id = i.id
LEFT JOIN users u_buyer ON c.buyer_id = u_buyer.id
LEFT JOIN users u_seller ON c.seller_id = u_seller.id
ORDER BY c.updated_at DESC;

CREATE OR REPLACE VIEW debug_messages_raw AS
SELECT
    cm.id,
    cm.conversation_id,
    cm.sender_id,
    cm.content,
    cm.sent_at,
    cm.is_read,
    cm.deleted_at,
    u.nickname as sender_nickname,
    c.item_id
FROM conversation_messages cm
LEFT JOIN users u ON cm.sender_id = u.id
LEFT JOIN conversations c ON cm.conversation_id = c.id
ORDER BY cm.sent_at DESC;

-- 授權除錯檢視給所有認證使用者
GRANT SELECT ON debug_conversations_raw TO authenticated;
GRANT SELECT ON debug_messages_raw TO authenticated;

-- =============================================
-- 完成訊息
-- =============================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  ✅ Messaging RLS 已暫時停用';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '變更內容:';
    RAISE NOTICE '  • conversations 表: RLS 已停用';
    RAISE NOTICE '  • conversation_messages 表: RLS 已停用';
    RAISE NOTICE '  • 所有相關政策已移除';
    RAISE NOTICE '  • 建立除錯檢視: debug_conversations_raw';
    RAISE NOTICE '  • 建立除錯檢視: debug_messages_raw';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  重要提醒:';
    RAISE NOTICE '  1. 現在所有認證使用者都能存取所有對話';
    RAISE NOTICE '  2. 這是嚴重的安全性風險';
    RAISE NOTICE '  3. 僅用於本地開發除錯';
    RAISE NOTICE '  4. 除錯完成後請立即恢復';
    RAISE NOTICE '  5. 絕對不要在生產環境執行';
    RAISE NOTICE '';
    RAISE NOTICE '除錯檢視使用方法:';
    RAISE NOTICE '  SELECT * FROM debug_conversations_raw;';
    RAISE NOTICE '  SELECT * FROM debug_messages_raw;';
    RAISE NOTICE '';
    RAISE NOTICE '恢復方法:';
    RAISE NOTICE '  執行 99999999999996_restore_messaging_rls.sql';
    RAISE NOTICE '  或使用 git 恢復到之前的版本';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
