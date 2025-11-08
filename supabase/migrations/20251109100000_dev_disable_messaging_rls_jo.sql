-- =============================================
-- Migration: 開發測試環境 - 停用訊息功能 RLS
-- 檔案: 20251109100000_dev_disable_messaging_rls_jo.sql
-- 建立日期: 2025-11-09
-- 目標: 移除 conversations 和 conversation_messages 的 RLS 限制，方便開發人員測試
-- ⚠️  警告: 此檔案僅適用於開發/測試環境，生產環境請勿使用！
-- =============================================

-- =============================================
-- 環境檢查 (建議但不強制)
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '⚠️  開發環境 RLS 停用程序';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '目標表格:';
    RAISE NOTICE '  - public.conversations';
    RAISE NOTICE '  - public.conversation_messages';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  這將允許任何人存取所有對話和訊息';
    RAISE NOTICE '⚠️  請確認這是開發/測試環境！';
    RAISE NOTICE '';
    RAISE NOTICE '執行中...';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 第一步: 停用 Row Level Security
-- =============================================

-- 停用 conversations 表的 RLS
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- 停用 conversation_messages 表的 RLS
ALTER TABLE public.conversation_messages DISABLE ROW LEVEL SECURITY;

-- =============================================
-- 第二步: 刪除現有的 RLS 政策（如果存在）
-- =============================================

-- 刪除 conversations 表的所有政策
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'conversations'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname);
        RAISE NOTICE '  已刪除政策: conversations.%', pol.policyname;
    END LOOP;
END $$;

-- 刪除 conversation_messages 表的所有政策
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'conversation_messages'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversation_messages', pol.policyname);
        RAISE NOTICE '  已刪除政策: conversation_messages.%', pol.policyname;
    END LOOP;
END $$;

-- =============================================
-- 第三步: 授予完整權限
-- =============================================

-- 授予 anon 角色完整權限（未登入用戶也可以測試）
GRANT ALL ON public.conversations TO anon;
GRANT ALL ON public.conversation_messages TO anon;

-- 授予 authenticated 角色完整權限
GRANT ALL ON public.conversations TO authenticated;
GRANT ALL ON public.conversation_messages TO authenticated;

-- 授予序列使用權限
GRANT USAGE, SELECT ON SEQUENCE conversations_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE conversation_messages_id_seq TO anon, authenticated;

-- =============================================
-- 第四步: 建立開發專用的輔助視圖
-- =============================================

-- 建立視圖：快速查看所有對話
CREATE OR REPLACE VIEW public.dev_all_conversations AS
SELECT
    c.id AS conversation_id,
    c.item_id,
    i.title AS item_title,
    c.buyer_id,
    u_buyer.nickname AS buyer_nickname,
    c.seller_id,
    u_seller.nickname AS seller_nickname,
    c.created_at,
    c.updated_at,
    c.deleted_by_buyer_at,
    c.deleted_by_seller_at,
    COUNT(cm.id) AS message_count,
    COUNT(cm.id) FILTER (WHERE cm.deleted_at IS NULL) AS active_message_count
FROM public.conversations c
LEFT JOIN public.items i ON c.item_id = i.id
LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
LEFT JOIN public.conversation_messages cm ON c.id = cm.conversation_id
GROUP BY c.id, i.title, u_buyer.nickname, u_seller.nickname
ORDER BY c.updated_at DESC;

COMMENT ON VIEW public.dev_all_conversations IS
'開發專用視圖：顯示所有對話的摘要資訊，包含訊息統計。
僅用於開發/測試環境。';

-- 建立視圖：快速查看所有訊息
CREATE OR REPLACE VIEW public.dev_all_messages AS
SELECT
    cm.id AS message_id,
    cm.conversation_id,
    c.item_id,
    i.title AS item_title,
    cm.sender_id,
    u.nickname AS sender_nickname,
    cm.content,
    cm.is_read,
    cm.sent_at,
    cm.deleted_at,
    cm.deleted_by
FROM public.conversation_messages cm
JOIN public.conversations c ON cm.conversation_id = c.id
LEFT JOIN public.items i ON c.item_id = i.id
LEFT JOIN public.users u ON cm.sender_id = u.id
ORDER BY cm.sent_at DESC;

COMMENT ON VIEW public.dev_all_messages IS
'開發專用視圖：顯示所有訊息的完整資訊。
僅用於開發/測試環境。';

-- 授予視圖查詢權限
GRANT SELECT ON public.dev_all_conversations TO anon, authenticated;
GRANT SELECT ON public.dev_all_messages TO anon, authenticated;

-- =============================================
-- 第五步: 建立開發專用的快速測試函數
-- =============================================

-- 函數：快速建立測試對話
CREATE OR REPLACE FUNCTION public.dev_create_test_conversation(
    p_item_id BIGINT,
    p_buyer_id UUID,
    p_seller_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conversation_id BIGINT;
BEGIN
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, p_buyer_id, p_seller_id)
    RETURNING id INTO v_conversation_id;

    RAISE NOTICE '✅ 建立測試對話成功，ID: %', v_conversation_id;

    RETURN v_conversation_id;
END;
$$;

COMMENT ON FUNCTION public.dev_create_test_conversation(BIGINT, UUID, UUID) IS
'開發專用函數：快速建立測試對話，無需驗證權限。
僅用於開發/測試環境。';

-- 函數：快速建立測試訊息
CREATE OR REPLACE FUNCTION public.dev_create_test_message(
    p_conversation_id BIGINT,
    p_sender_id UUID,
    p_content TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_message_id BIGINT;
BEGIN
    INSERT INTO public.conversation_messages (conversation_id, sender_id, content)
    VALUES (p_conversation_id, p_sender_id, p_content)
    RETURNING id INTO v_message_id;

    RAISE NOTICE '✅ 建立測試訊息成功，ID: %', v_message_id;

    RETURN v_message_id;
END;
$$;

COMMENT ON FUNCTION public.dev_create_test_message(BIGINT, UUID, TEXT) IS
'開發專用函數：快速建立測試訊息，無需驗證權限。
僅用於開發/測試環境。';

-- 函數：清空所有測試資料
CREATE OR REPLACE FUNCTION public.dev_clear_all_conversations()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_messages_deleted INT;
    v_conversations_deleted INT;
BEGIN
    -- 刪除所有訊息
    DELETE FROM public.conversation_messages;
    GET DIAGNOSTICS v_messages_deleted = ROW_COUNT;

    -- 刪除所有對話
    DELETE FROM public.conversations;
    GET DIAGNOSTICS v_conversations_deleted = ROW_COUNT;

    -- 重置序列
    ALTER SEQUENCE conversations_id_seq RESTART WITH 1;
    ALTER SEQUENCE conversation_messages_id_seq RESTART WITH 1;

    RAISE NOTICE '✅ 已刪除 % 筆對話和 % 筆訊息', v_conversations_deleted, v_messages_deleted;

    RETURN jsonb_build_object(
        'conversations_deleted', v_conversations_deleted,
        'messages_deleted', v_messages_deleted,
        'sequences_reset', true
    );
END;
$$;

COMMENT ON FUNCTION public.dev_clear_all_conversations() IS
'開發專用函數：清空所有對話和訊息資料，重置序列。
⚠️  警告：這會刪除所有資料！僅用於開發/測試環境。';

-- 授予函數執行權限
GRANT EXECUTE ON FUNCTION public.dev_create_test_conversation(BIGINT, UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dev_create_test_message(BIGINT, UUID, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dev_clear_all_conversations() TO anon, authenticated;

-- =============================================
-- 第六步: 驗證設定
-- =============================================

DO $$
DECLARE
    v_conversations_rls BOOLEAN;
    v_messages_rls BOOLEAN;
    v_conversations_policies INT;
    v_messages_policies INT;
BEGIN
    -- 檢查 RLS 狀態
    SELECT relrowsecurity INTO v_conversations_rls
    FROM pg_class
    WHERE relname = 'conversations' AND relnamespace = 'public'::regnamespace;

    SELECT relrowsecurity INTO v_messages_rls
    FROM pg_class
    WHERE relname = 'conversation_messages' AND relnamespace = 'public'::regnamespace;

    -- 檢查政策數量
    SELECT COUNT(*) INTO v_conversations_policies
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'conversations';

    SELECT COUNT(*) INTO v_messages_policies
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'conversation_messages';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 驗證結果:';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'conversations 表:';
    RAISE NOTICE '  - RLS 狀態: %', CASE WHEN v_conversations_rls THEN '❌ 啟用 (異常)' ELSE '✅ 停用' END;
    RAISE NOTICE '  - 政策數量: %', v_conversations_policies;
    RAISE NOTICE '';
    RAISE NOTICE 'conversation_messages 表:';
    RAISE NOTICE '  - RLS 狀態: %', CASE WHEN v_messages_rls THEN '❌ 啟用 (異常)' ELSE '✅ 停用' END;
    RAISE NOTICE '  - 政策數量: %', v_messages_policies;
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🛠️  開發工具已建立:';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '視圖:';
    RAISE NOTICE '  - dev_all_conversations';
    RAISE NOTICE '  - dev_all_messages';
    RAISE NOTICE '';
    RAISE NOTICE '函數:';
    RAISE NOTICE '  - dev_create_test_conversation()';
    RAISE NOTICE '  - dev_create_test_message()';
    RAISE NOTICE '  - dev_clear_all_conversations()';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📝 使用範例:';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '-- 查看所有對話';
    RAISE NOTICE 'SELECT * FROM dev_all_conversations;';
    RAISE NOTICE '';
    RAISE NOTICE '-- 查看所有訊息';
    RAISE NOTICE 'SELECT * FROM dev_all_messages;';
    RAISE NOTICE '';
    RAISE NOTICE '-- 建立測試對話';
    RAISE NOTICE 'SELECT dev_create_test_conversation(';
    RAISE NOTICE '    p_item_id := 1,';
    RAISE NOTICE '    p_buyer_id := ''uuid-here'',';
    RAISE NOTICE '    p_seller_id := ''uuid-here''';
    RAISE NOTICE ');';
    RAISE NOTICE '';
    RAISE NOTICE '-- 建立測試訊息';
    RAISE NOTICE 'SELECT dev_create_test_message(';
    RAISE NOTICE '    p_conversation_id := 1,';
    RAISE NOTICE '    p_sender_id := ''uuid-here'',';
    RAISE NOTICE '    p_content := ''測試訊息''';
    RAISE NOTICE ');';
    RAISE NOTICE '';
    RAISE NOTICE '-- 清空所有測試資料';
    RAISE NOTICE 'SELECT dev_clear_all_conversations();';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    IF v_conversations_rls OR v_messages_rls THEN
        RAISE WARNING '⚠️  RLS 未完全停用，請檢查設定！';
    ELSE
        RAISE NOTICE '✅ RLS 已成功停用！';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '⚠️  重要提醒';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. 這是開發/測試環境專用設定';
    RAISE NOTICE '2. 任何人都可以存取所有對話和訊息';
    RAISE NOTICE '3. 生產環境請勿使用此設定';
    RAISE NOTICE '4. 測試完成後請恢復 RLS（參考下方註解）';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 恢復 RLS 的 SQL (請保存此段用於之後恢復)
-- =============================================

/*
========================================
如何恢復 RLS 設定
========================================

方法 1: 執行恢復 SQL
----------------------------------------

-- 1. 刪除開發工具
DROP VIEW IF EXISTS public.dev_all_conversations;
DROP VIEW IF EXISTS public.dev_all_messages;
DROP FUNCTION IF EXISTS public.dev_create_test_conversation(BIGINT, UUID, UUID);
DROP FUNCTION IF EXISTS public.dev_create_test_message(BIGINT, UUID, TEXT);
DROP FUNCTION IF EXISTS public.dev_clear_all_conversations();

-- 2. 撤銷過度權限
REVOKE ALL ON public.conversations FROM anon;
REVOKE ALL ON public.conversation_messages FROM anon;

-- 3. 重新啟用 RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

-- 4. 重新建立 RLS 政策（參考 20251025101010_setup_row_level_security.sql）
-- 或者執行以下腳本重新套用原始 RLS 設定


方法 2: 建立並執行恢復 Migration
----------------------------------------

-- 建立新的 migration 檔案，例如：
-- 20251109110000_restore_messaging_rls_jo.sql

-- 內容包含上述的恢復 SQL


方法 3: 從備份恢復
----------------------------------------

-- 如果有備份，可以直接恢復
psql $DATABASE_URL < backup_before_dev.sql


========================================
重新建立 RLS 政策範例
========================================

-- conversations 表政策
CREATE POLICY "Users can view their own conversations"
ON public.conversations FOR SELECT
TO authenticated
USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

CREATE POLICY "Users can create conversations"
ON public.conversations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id);

-- conversation_messages 表政策
CREATE POLICY "Users can view messages in their conversations"
ON public.conversation_messages FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
);

CREATE POLICY "Users can send messages in their conversations"
ON public.conversation_messages FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = sender_id AND
    EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = conversation_id
        AND (buyer_id = auth.uid() OR seller_id = auth.uid())
    )
);

CREATE POLICY "Users can update their own messages"
ON public.conversation_messages FOR UPDATE
TO authenticated
USING (sender_id = auth.uid());

CREATE POLICY "Users can delete their own messages"
ON public.conversation_messages FOR DELETE
TO authenticated
USING (sender_id = auth.uid());

========================================
*/
