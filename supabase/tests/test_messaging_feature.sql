-- =============================================
-- 訊息功能測試腳本
-- =============================================
-- 此腳本用於測試訊息傳遞功能的各項 RPC 函數
-- 執行前請確保已套用 20251029091800_setup_messaging_feature.sql 遷移
-- =============================================

-- 測試環境設定
-- 注意: 這些測試假設您的資料庫中已有測試資料（使用者、物品等）

-- =============================================
-- 測試 1: 建立或取得對話
-- =============================================

-- 假設測試物品 ID 為 1
-- 此函數會建立新對話或返回現有對話
SELECT * FROM public.create_or_get_conversation(1);

-- 預期結果：
-- - 如果對話不存在，會建立新對話並返回對話資訊
-- - 如果對話已存在，會返回現有對話資訊
-- - 如果物品不存在或已下架，會拋出錯誤
-- - 如果嘗試對自己的物品建立對話，會拋出錯誤

-- =============================================
-- 測試 2: 發送訊息
-- =============================================

-- 假設對話 ID 為 1
-- 發送測試訊息
SELECT * FROM public.send_message(
    1,  -- p_conversation_id
    '你好，這個物品還有嗎？'  -- p_content
);

-- 預期結果：
-- - 返回新建立的訊息資訊
-- - 訊息的 is_read 欄位應為 false
-- - sent_at 欄位應為當前時間
-- - 如果訊息內容為空，會拋出錯誤
-- - 如果使用者不是對話參與者，會拋出錯誤

-- =============================================
-- 測試 3: 取得對話訊息
-- =============================================

-- 取得對話 ID 為 1 的所有訊息
SELECT * FROM public.get_conversation_messages(
    1,   -- p_conversation_id
    1,   -- p_page
    50   -- p_size
);

-- 預期結果：
-- - 返回對話中的所有訊息，按發送時間升序排列
-- - 包含發送者的暱稱和頭像資訊
-- - 如果使用者不是對話參與者，會拋出錯誤

-- =============================================
-- 測試 4: 標記訊息為已讀
-- =============================================

-- 標記對話 ID 為 1 的所有訊息為已讀
SELECT * FROM public.mark_messages_as_read(1);

-- 預期結果：
-- - 返回更新的訊息數量
-- - 只會更新非自己發送且未讀的訊息
-- - 如果使用者不是對話參與者，會拋出錯誤

-- =============================================
-- 測試 5: 取得使用者對話列表
-- =============================================

-- 取得當前使用者的所有對話
SELECT * FROM public.get_user_conversations(
    1,   -- p_page
    20   -- p_size
);

-- 預期結果：
-- - 返回使用者的所有對話列表
-- - 包含每個對話的最後一則訊息和未讀訊息數量
-- - 按對話更新時間降序排列（最新的在前）
-- - 包含對方使用者和物品的基本資訊

-- =============================================
-- 測試 6: 取得未讀訊息總數
-- =============================================

-- 取得當前使用者的未讀訊息總數
SELECT * FROM public.get_unread_message_count();

-- 預期結果：
-- - 返回使用者所有對話的未讀訊息總數
-- - 只計算非自己發送的訊息

-- =============================================
-- 測試 7: 驗證觸發器
-- =============================================

-- 此測試驗證當插入新訊息時，對話的 updated_at 會自動更新

-- 1. 先查看對話的當前 updated_at
SELECT id, updated_at FROM public.conversations WHERE id = 1;

-- 2. 等待幾秒後發送新訊息
SELECT pg_sleep(2);
SELECT * FROM public.send_message(1, '測試觸發器更新');

-- 3. 再次查看對話的 updated_at
SELECT id, updated_at FROM public.conversations WHERE id = 1;

-- 預期結果：
-- - 對話的 updated_at 應該等於新訊息的 sent_at
-- - updated_at 應該比步驟 1 的時間晚

-- =============================================
-- 測試 8: 驗證權限控制
-- =============================================

-- 這些測試應該會失敗（拋出錯誤），以驗證權限控制正常運作

-- 測試 8a: 嘗試查看不屬於自己的對話訊息
-- （需要用另一個使用者的 ID，假設為 999）
-- SELECT * FROM public.get_conversation_messages(999, 1, 50);
-- 預期：拋出「無權限查看此對話」錯誤

-- 測試 8b: 嘗試在不屬於自己的對話中發送訊息
-- SELECT * FROM public.send_message(999, '測試訊息');
-- 預期：拋出「無權限在此對話中發送訊息」錯誤

-- 測試 8c: 嘗試對不存在的物品建立對話
-- SELECT * FROM public.create_or_get_conversation(999999);
-- 預期：拋出「物品不存在或已下架」錯誤

-- 測試 8d: 測試分頁參數驗證
-- SELECT * FROM public.get_user_conversations(0, 20);
-- 預期：拋出「頁碼必須大於 0」錯誤

-- 測試 8e: 測試每頁數量驗證
-- SELECT * FROM public.get_user_conversations(1, 200);
-- 預期：拋出「每頁數量必須在 1 到 100 之間」錯誤

-- 測試 8f: 測試訊息查詢分頁驗證
-- SELECT * FROM public.get_conversation_messages(1, -1, 50);
-- 預期：拋出「頁碼必須大於 0」錯誤

-- =============================================
-- 測試 9: 驗證索引效能
-- =============================================

-- 檢查未讀訊息的索引是否被使用
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM public.conversation_messages cm
WHERE cm.conversation_id = 1
  AND cm.is_read = false;

-- 預期結果：
-- - 執行計畫應該顯示使用 idx_conversation_messages_unread 索引

-- 檢查對話列表排序的索引是否被使用
EXPLAIN ANALYZE
SELECT * FROM public.conversations
ORDER BY updated_at DESC
LIMIT 20;

-- 預期結果：
-- - 執行計畫應該顯示使用 idx_conversations_updated_at 索引

-- =============================================
-- 測試 10: 驗證 Realtime 發布
-- =============================================

-- 檢查 conversations 表是否在 Realtime 發布中
SELECT tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime' 
  AND tablename IN ('conversations', 'conversation_messages');

-- 預期結果：
-- - 應該返回兩行記錄，分別為 'conversations' 和 'conversation_messages'

-- =============================================
-- 清理測試資料（可選）
-- =============================================

-- 如果需要清理測試過程中建立的資料，可以執行以下命令
-- 注意：這會刪除所有測試訊息和對話，請謹慎使用

-- DELETE FROM public.conversation_messages WHERE conversation_id IN (
--     SELECT id FROM public.conversations WHERE item_id IN (SELECT id FROM public.items WHERE user_id = auth.uid())
-- );
-- DELETE FROM public.conversations WHERE item_id IN (
--     SELECT id FROM public.items WHERE user_id = auth.uid()
-- );

-- =============================================
-- 測試結果檢查清單
-- =============================================

/*
測試完成後，請確認以下項目：

✓ 建立或取得對話功能正常運作
✓ 發送訊息功能正常運作
✓ 取得對話訊息功能正常運作
✓ 標記訊息為已讀功能正常運作
✓ 取得使用者對話列表功能正常運作
✓ 取得未讀訊息總數功能正常運作
✓ 對話更新時間自動更新（觸發器）
✓ 權限控制正常運作（非參與者無法存取）
✓ 分頁參數驗證正常運作
✓ 資料庫索引正常使用
✓ Realtime 發布設定正確（冪等性）

如果以上所有項目都通過，訊息功能即可投入使用。
*/
