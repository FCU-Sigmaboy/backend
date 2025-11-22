-- ============================================================================
-- Messaging System v2 - 啟用 Realtime
-- ============================================================================
-- 描述: 為 v2 訊息系統啟用 Supabase Realtime 功能
-- 版本: 1.0.0
-- 日期: 2024-01-15
-- ============================================================================

-- Step 1: 設定 REPLICA IDENTITY (必要,讓 Realtime 知道如何追蹤變更)
-- ============================================================================

-- conversations_v2 表
ALTER TABLE public.conversations_v2 REPLICA IDENTITY FULL;

-- conversation_messages_v2 表 (最重要 - 訊息即時推送)
ALTER TABLE public.conversation_messages_v2 REPLICA IDENTITY FULL;

-- conversation_items_v2 表
ALTER TABLE public.conversation_items_v2 REPLICA IDENTITY FULL;

-- Step 2: 將表加入 Realtime Publication
-- ============================================================================

-- 檢查並創建 publication (Supabase 預設使用 'supabase_realtime')
DO $$
BEGIN
    -- 確保 publication 存在
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        CREATE PUBLICATION supabase_realtime;
        RAISE NOTICE '✓ 已創建 publication: supabase_realtime';
    END IF;
END $$;

-- 將表加入 publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations_v2;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_messages_v2;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_items_v2;

-- Step 3: 授予必要的權限
-- ============================================================================

-- 授予 authenticated 用戶 SELECT 權限 (Realtime 需要)
GRANT SELECT ON public.conversations_v2 TO authenticated;
GRANT SELECT ON public.conversation_messages_v2 TO authenticated;
GRANT SELECT ON public.conversation_items_v2 TO authenticated;

-- 授予 anon 用戶 SELECT 權限 (如果需要未登入用戶也能訂閱)
-- GRANT SELECT ON public.conversations_v2 TO anon;
-- GRANT SELECT ON public.conversation_messages_v2 TO anon;
-- GRANT SELECT ON public.conversation_items_v2 TO anon;

-- Step 4: 創建 RLS 策略以保護 Realtime 訂閱
-- ============================================================================

-- conversations_v2 RLS 策略
ALTER TABLE public.conversations_v2 ENABLE ROW LEVEL SECURITY;

-- 用戶只能查看自己參與的對話
CREATE POLICY "Users can view their own conversations"
ON public.conversations_v2
FOR SELECT
TO authenticated
USING (
    auth.uid() = participant_1_id
    OR auth.uid() = participant_2_id
);

-- conversation_messages_v2 RLS 策略
ALTER TABLE public.conversation_messages_v2 ENABLE ROW LEVEL SECURITY;

-- 用戶只能查看自己對話中的訊息
CREATE POLICY "Users can view messages in their conversations"
ON public.conversation_messages_v2
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations_v2 c
        WHERE c.id = conversation_messages_v2.conversation_id
        AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
    )
);

-- conversation_items_v2 RLS 策略
ALTER TABLE public.conversation_items_v2 ENABLE ROW LEVEL SECURITY;

-- 用戶只能查看自己對話中的商品
CREATE POLICY "Users can view items in their conversations"
ON public.conversation_items_v2
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.conversations_v2 c
        WHERE c.id = conversation_items_v2.conversation_id
        AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
    )
);

-- ============================================================================
-- 驗證配置
-- ============================================================================

DO $$
DECLARE
    v_conversations_realtime BOOLEAN;
    v_messages_realtime BOOLEAN;
    v_items_realtime BOOLEAN;
BEGIN
    -- 檢查表是否在 publication 中
    SELECT EXISTS(
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'conversations_v2'
    ) INTO v_conversations_realtime;

    SELECT EXISTS(
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'conversation_messages_v2'
    ) INTO v_messages_realtime;

    SELECT EXISTS(
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'conversation_items_v2'
    ) INTO v_items_realtime;

    -- 顯示結果
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Realtime 配置驗證';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'conversations_v2: %', CASE WHEN v_conversations_realtime THEN '✅ 已啟用' ELSE '❌ 未啟用' END;
    RAISE NOTICE 'conversation_messages_v2: %', CASE WHEN v_messages_realtime THEN '✅ 已啟用' ELSE '❌ 未啟用' END;
    RAISE NOTICE 'conversation_items_v2: %', CASE WHEN v_items_realtime THEN '✅ 已啟用' ELSE '❌ 未啟用' END;
    RAISE NOTICE '';

    IF v_conversations_realtime AND v_messages_realtime AND v_items_realtime THEN
        RAISE NOTICE '✅ 所有表都已成功啟用 Realtime!';
    ELSE
        RAISE EXCEPTION '❌ 部分表未能啟用 Realtime,請檢查配置';
    END IF;

    RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- 使用說明
-- ============================================================================

/*
執行此腳本後,前端可以這樣訂閱 Realtime 更新:

1. 訂閱新訊息 (已在 conversationAPI_v2.js 中實現):

   const subscription = supabase
     .channel('conversation_456')
     .on('postgres_changes', {
       event: 'INSERT',
       schema: 'public',
       table: 'conversation_messages_v2',
       filter: 'conversation_id=eq.456'
     }, (payload) => {
       console.log('New message:', payload.new);
     })
     .subscribe();

2. 訂閱對話更新 (例如 last_message_at 變更):

   const subscription = supabase
     .channel('my_conversations')
     .on('postgres_changes', {
       event: 'UPDATE',
       schema: 'public',
       table: 'conversations_v2',
       filter: `participant_1_id=eq.${userId}`
     }, (payload) => {
       console.log('Conversation updated:', payload.new);
     })
     .subscribe();

3. 訂閱訊息已讀狀態:

   const subscription = supabase
     .channel('conversation_456_updates')
     .on('postgres_changes', {
       event: 'UPDATE',
       schema: 'public',
       table: 'conversation_messages_v2',
       filter: 'conversation_id=eq.456'
     }, (payload) => {
       console.log('Message updated:', payload.new);
     })
     .subscribe();

注意事項:
- RLS 策略已啟用,用戶只能訂閱自己的對話
- 使用 REPLICA IDENTITY FULL 確保所有欄位變更都會被推送
- 記得在不使用時 unsubscribe() 以釋放資源
*/
