-- =============================================
-- 恢復遷移：重新啟用 Messaging RLS
-- =============================================
-- 用途: 恢復原本的 RLS 安全設定
-- 使用時機: 除錯完成後執行此遷移
-- =============================================
-- 日期: 2024-XX-XX
-- 影響資料表: conversations, conversation_messages
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  🔒 恢復 Messaging RLS (正常模式)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '正在恢復安全設定...';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 1. 刪除除錯檢視
-- =============================================
DROP VIEW IF EXISTS debug_conversations_raw;
DROP VIEW IF EXISTS debug_messages_raw;

-- =============================================
-- 2. 刪除所有可能存在的舊政策（確保乾淨狀態）
-- =============================================
DROP POLICY IF EXISTS "Conversation participants can view conversations" ON public.conversations;
DROP POLICY IF EXISTS "Buyers can initiate conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can view their own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_delete_policy" ON public.conversations;

DROP POLICY IF EXISTS "Conversation participants can view messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Conversation participants can send messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_select_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_insert_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_update_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_delete_policy" ON public.conversation_messages;

-- =============================================
-- 3. 重新啟用 RLS
-- =============================================
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 4. 重新建立 conversations 表的 RLS 政策
-- =============================================

-- 允許對話參與者查看對話
CREATE POLICY "Users can view their own conversations"
ON public.conversations FOR SELECT
TO authenticated
USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- 允許買家建立對話
CREATE POLICY "Users can create conversations"
ON public.conversations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id);

-- 允許對話參與者更新對話（例如軟刪除）
CREATE POLICY "Users can update their own conversations"
ON public.conversations FOR UPDATE
TO authenticated
USING (auth.uid() = buyer_id OR auth.uid() = seller_id)
WITH CHECK (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- =============================================
-- 5. 重新建立 conversation_messages 表的 RLS 政策
-- =============================================

-- 允許對話參與者查看訊息
CREATE POLICY "Users can view messages in their conversations"
ON public.conversation_messages FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_messages.conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
);

-- 允許對話參與者發送訊息
CREATE POLICY "Users can send messages in their conversations"
ON public.conversation_messages FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_messages.conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
);

-- 允許訊息發送者更新自己的訊息（例如軟刪除、標記已讀）
CREATE POLICY "Users can update messages in their conversations"
ON public.conversation_messages FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_messages.conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_messages.conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
);

-- =============================================
-- 6. 驗證 RLS 狀態
-- =============================================
DO $$
DECLARE
    v_conversations_rls BOOLEAN;
    v_messages_rls BOOLEAN;
    v_conversations_policy_count INT;
    v_messages_policy_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證 RLS 狀態';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查 RLS 是否已啟用
    SELECT relrowsecurity INTO v_conversations_rls
    FROM pg_class
    WHERE relname = 'conversations' AND relnamespace = 'public'::regnamespace;

    SELECT relrowsecurity INTO v_messages_rls
    FROM pg_class
    WHERE relname = 'conversation_messages' AND relnamespace = 'public'::regnamespace;

    -- 計算政策數量
    SELECT COUNT(*) INTO v_conversations_policy_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'conversations';

    SELECT COUNT(*) INTO v_messages_policy_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'conversation_messages';

    IF NOT v_conversations_rls THEN
        RAISE WARNING '⚠️  conversations 表 RLS 未啟用';
    ELSE
        RAISE NOTICE '✅ conversations 表 RLS 已啟用';
    END IF;

    IF NOT v_messages_rls THEN
        RAISE WARNING '⚠️  conversation_messages 表 RLS 未啟用';
    ELSE
        RAISE NOTICE '✅ conversation_messages 表 RLS 已啟用';
    END IF;

    RAISE NOTICE 'conversations 政策數量: %', v_conversations_policy_count;
    RAISE NOTICE 'conversation_messages 政策數量: %', v_messages_policy_count;

    IF v_conversations_policy_count < 2 THEN
        RAISE WARNING '⚠️  conversations 表政策數量不足（預期至少 2 個）';
    END IF;

    IF v_messages_policy_count < 2 THEN
        RAISE WARNING '⚠️  conversation_messages 表政策數量不足（預期至少 2 個）';
    END IF;

    RAISE NOTICE '';
END $$;

-- =============================================
-- 7. 列出已建立的政策
-- =============================================
DO $$
DECLARE
    v_policy RECORD;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '  已建立的政策列表';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    FOR v_policy IN
        SELECT tablename, policyname, cmd
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename IN ('conversations', 'conversation_messages')
        ORDER BY tablename, policyname
    LOOP
        RAISE NOTICE '  • %.% (%)', v_policy.tablename, v_policy.policyname, v_policy.cmd;
    END LOOP;

    RAISE NOTICE '';
END $$;

-- =============================================
-- 完成訊息
-- =============================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  ✅ Messaging RLS 已成功恢復';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '恢復內容:';
    RAISE NOTICE '  • conversations 表: RLS 已啟用';
    RAISE NOTICE '  • conversation_messages 表: RLS 已啟用';
    RAISE NOTICE '  • 所有安全政策已重新建立';
    RAISE NOTICE '  • 除錯檢視已移除';
    RAISE NOTICE '';
    RAISE NOTICE '✅ 所有安全設定已恢復正常';
    RAISE NOTICE '✅ 使用者只能存取自己的對話和訊息';
    RAISE NOTICE '✅ 系統已恢復生產環境安全等級';
    RAISE NOTICE '';
    RAISE NOTICE '後續步驟:';
    RAISE NOTICE '  1. 可以刪除除錯用的遷移檔案';
    RAISE NOTICE '  2. 測試功能是否正常運作';
    RAISE NOTICE '  3. 確認安全性設定正確';
    RAISE NOTICE '  4. 使用真實使用者測試權限隔離';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
