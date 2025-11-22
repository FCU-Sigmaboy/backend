-- ============================================================================
-- 對話模組 RLS 管理指令 - 測試人員使用版本
-- ============================================================================
-- 本檔案提供測試人員快速關閉和恢復 RLS 的指令
-- 用途: 測試資料遷移、資料驗證、除錯等操作時使用
--
-- ⚠️  警告: 這些指令只應在開發/測試環境使用,
--         生產環境使用會造成安全風險！
-- ============================================================================

-- ============================================================================
-- 第一部分: 查詢 RLS 目前狀態
-- ============================================================================

-- 檢查所有對話相關表的 RLS 狀態
SELECT
    tablename,
    rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN (
    'conversations_v2',
    'conversation_messages_v2',
    'conversation_items_v2'
)
ORDER BY tablename;

-- 檢查所有對話相關表的 RLS 策略
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    cmd
FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN (
    'conversations_v2',
    'conversation_messages_v2',
    'conversation_items_v2'
)
ORDER BY tablename, policyname;


-- ============================================================================
-- 第二部分: 快速關閉 RLS 的指令
-- ============================================================================
-- 用途: 測試人員需要不受限制地存取資料時使用

-- 關閉所有對話相關表的 RLS
ALTER TABLE public.conversations_v2 DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages_v2 DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_items_v2 DISABLE ROW LEVEL SECURITY;

-- 驗證 RLS 已關閉
SELECT
    tablename,
    rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN (
    'conversations_v2',
    'conversation_messages_v2',
    'conversation_items_v2'
)
ORDER BY tablename;


-- ============================================================================
-- 第三部分: 重新啟用 RLS 的指令
-- ============================================================================
-- 用途: 測試完成後,恢復安全設置

-- 啟用所有對話相關表的 RLS
ALTER TABLE public.conversations_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_items_v2 ENABLE ROW LEVEL SECURITY;

-- 驗證 RLS 已啟用
SELECT
    tablename,
    rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN (
    'conversations_v2',
    'conversation_messages_v2',
    'conversation_items_v2'
)
ORDER BY tablename;


-- ============================================================================
-- 第四部分: 進階操作 - 個別表的 RLS 管理
-- ============================================================================

-- 選項 A: 僅關閉訊息表的 RLS (保留對話表的安全)
-- 用途: 測試訊息遷移或批量操作時
ALTER TABLE public.conversation_messages_v2 DISABLE ROW LEVEL SECURITY;

-- 選項 B: 僅關閉對話表的 RLS
-- 用途: 測試對話管理功能時
ALTER TABLE public.conversations_v2 DISABLE ROW LEVEL SECURITY;

-- 選項 C: 僅關閉對話商品表的 RLS
-- 用途: 測試商品關聯功能時
ALTER TABLE public.conversation_items_v2 DISABLE ROW LEVEL SECURITY;


-- ============================================================================
-- 第五部分: 重置 RLS 策略 (完全重新套用)
-- ============================================================================
-- 用途: 如果 RLS 設置被誤改,可以重新套用完整的策略

-- 重新建立 conversations_v2 的 RLS 策略
DROP POLICY IF EXISTS conversations_v2_select_policy ON public.conversations_v2;
CREATE POLICY conversations_v2_select_policy ON public.conversations_v2
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() IN (participant_1_id, participant_2_id)
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
    USING (false);  -- 防止刪除

-- 重新建立 conversation_messages_v2 的 RLS 策略
DROP POLICY IF EXISTS conversation_messages_v2_select_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_select_policy ON public.conversation_messages_v2
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
            AND (is_deleted = false OR sender_id = auth.uid())
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
            WHERE c.id = conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_messages_v2_update_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_update_policy ON public.conversation_messages_v2
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() = sender_id
        AND EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    )
    WITH CHECK (
        auth.uid() = sender_id
    );

DROP POLICY IF EXISTS conversation_messages_v2_delete_policy ON public.conversation_messages_v2;
CREATE POLICY conversation_messages_v2_delete_policy ON public.conversation_messages_v2
    FOR DELETE
    TO authenticated
    USING (false);  -- 使用軟刪除,防止硬刪除

-- 重新建立 conversation_items_v2 的 RLS 策略
DROP POLICY IF EXISTS conversation_items_v2_select_policy ON public.conversation_items_v2;
CREATE POLICY conversation_items_v2_select_policy ON public.conversation_items_v2
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_items_v2_insert_policy ON public.conversation_items_v2;
CREATE POLICY conversation_items_v2_insert_policy ON public.conversation_items_v2
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = added_by_user_id
        AND EXISTS (
            SELECT 1 FROM public.conversations_v2 c
            WHERE c.id = conversation_id
            AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS conversation_items_v2_update_policy ON public.conversation_items_v2;
CREATE POLICY conversation_items_v2_update_policy ON public.conversation_items_v2
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() = added_by_user_id
    );

DROP POLICY IF EXISTS conversation_items_v2_delete_policy ON public.conversation_items_v2;
CREATE POLICY conversation_items_v2_delete_policy ON public.conversation_items_v2
    FOR DELETE
    TO authenticated
    USING (false);


-- ============================================================================
-- 第六部分: 測試工具 - 驗證 RLS 是否生效
-- ============================================================================

-- 測試腳本: 驗證當前用戶能否看到對話
-- 執行此查詢(需登入為認證用戶):
SELECT
    c.id,
    c.participant_1_id,
    c.participant_2_id,
    c.created_at,
    (SELECT COUNT(*) FROM public.conversation_messages_v2 m
     WHERE m.conversation_id = c.id) as message_count
FROM public.conversations_v2 c
LIMIT 10;

-- 測試腳本: 驗證訊息 RLS
-- 執行此查詢(需登入為認證用戶):
SELECT
    m.id,
    m.conversation_id,
    m.sender_id,
    m.content,
    m.is_deleted,
    m.created_at
FROM public.conversation_messages_v2 m
LIMIT 10;

-- 測試腳本: 驗證對話商品關聯 RLS
-- 執行此查詢(需登入為認證用戶):
SELECT
    ci.id,
    ci.conversation_id,
    ci.item_id,
    ci.added_by_user_id,
    ci.created_at
FROM public.conversation_items_v2 ci
LIMIT 10;


-- ============================================================================
-- 使用說明
-- ============================================================================
/*

【快速指南】

1️⃣  查詢目前 RLS 狀態:
   執行「第一部分」的 SQL 查詢

2️⃣  關閉所有對話表的 RLS (完全開放存取):
   複製並執行「第二部分」的所有 ALTER TABLE 指令

3️⃣  恢復 RLS (啟用安全限制):
   複製並執行「第三部分」的所有 ALTER TABLE 指令

4️⃣  選擇性關閉 RLS (僅特定表):
   在「第四部分」選擇所需的選項執行

5️⃣  重置 RLS 策略 (修復誤改的設置):
   執行「第五部分」重新套用完整的 RLS 策略

6️⃣  驗證 RLS 運作:
   執行「第六部分」的測試查詢


【常見場景】

📋 場景 A: 測試資料遷移
  1. 執行「第二部分」- 關閉所有 RLS
  2. 執行遷移指令 (migrate_conversations_v1_to_v2)
  3. 驗證資料
  4. 執行「第三部分」- 恢復 RLS

📋 場景 B: 除錯訊息問題
  1. 執行「第四部分 - 選項 A」- 僅關閉訊息表 RLS
  2. 執行查詢除錯
  3. 執行「第三部分」- 恢復所有 RLS

📋 場景 C: RLS 設置被誤改
  1. 執行「第五部分」- 重置所有 RLS 策略
  2. 驗證「第六部分」的測試查詢

📋 場景 D: 完整的測試流程
  1. 執行「第一部分」- 查詢目前狀態
  2. 執行「第二部分」- 關閉所有 RLS
  3. 進行測試操作
  4. 執行「第三部分」- 恢復 RLS
  5. 執行「第六部分」- 驗證 RLS 生效


【安全提示】

⚠️  僅在開發/測試環境使用本指令
⚠️  關閉 RLS 後,所有用戶都能看到所有資料
⚠️  完成測試後,務必執行「第三部分」恢復 RLS
⚠️  不要在生產環境中執行關閉 RLS 的指令
⚠️  建議在測試後驗證「第六部分」的測試查詢
⚠️  保持此檔案的備份,以便快速恢復設置

*/
