# 開發測試環境快速指南

## 🎯 目的

本指南說明如何在開發/測試環境中移除 `conversations` 和 `conversation_messages` 表的 RLS 限制，方便開發人員測試訊息功能。

**⚠️ 警告:** 此設定僅適用於開發/測試環境，**絕對不要**在生產環境使用！

---

## 🚀 快速開始

### 執行開發環境設定

```bash
# 方法 1: 使用 Supabase CLI
supabase db push

# 方法 2: 執行特定 migration
psql $DATABASE_URL -f backend/supabase/migrations/20251109100000_dev_disable_messaging_rls_jo.sql

# 方法 3: 在 Supabase Dashboard 的 SQL Editor 中執行
# 複製 20251109100000_dev_disable_messaging_rls_jo.sql 的內容並執行
```

---

## ✅ 執行後會發生什麼？

### 1. RLS 被停用
- ✅ `conversations` 表的 RLS 已停用
- ✅ `conversation_messages` 表的 RLS 已停用
- ✅ 所有 RLS 政策已被刪除

### 2. 權限已開放
- ✅ `anon` 角色可以存取所有對話和訊息（未登入也可以測試）
- ✅ `authenticated` 角色可以存取所有對話和訊息

### 3. 開發工具已建立

#### 📊 視圖
- `dev_all_conversations` - 查看所有對話摘要
- `dev_all_messages` - 查看所有訊息

#### 🛠️ 函數
- `dev_create_test_conversation()` - 快速建立測試對話
- `dev_create_test_message()` - 快速建立測試訊息
- `dev_clear_all_conversations()` - 清空所有測試資料

---

## 📝 使用範例

### 查看所有對話

```sql
-- 查看所有對話摘要（包含訊息統計）
SELECT * FROM public.dev_all_conversations;

-- 查看特定物品的對話
SELECT * FROM public.dev_all_conversations
WHERE item_id = 1;

-- 查看特定使用者的對話
SELECT * FROM public.dev_all_conversations
WHERE buyer_id = 'uuid-here' OR seller_id = 'uuid-here';
```

### 查看所有訊息

```sql
-- 查看所有訊息
SELECT * FROM public.dev_all_messages;

-- 查看特定對話的訊息
SELECT * FROM public.dev_all_messages
WHERE conversation_id = 1;

-- 查看特定使用者發送的訊息
SELECT * FROM public.dev_all_messages
WHERE sender_id = 'uuid-here';

-- 查看未讀訊息
SELECT * FROM public.dev_all_messages
WHERE is_read = false;
```

### 建立測試對話

```sql
-- 建立測試對話
SELECT public.dev_create_test_conversation(
    p_item_id := 1,                                    -- 物品 ID
    p_buyer_id := '00000000-0000-0000-0000-000000000001'::uuid,  -- 買家 UUID
    p_seller_id := '00000000-0000-0000-0000-000000000002'::uuid  -- 賣家 UUID
);

-- 會回傳新建立的 conversation_id
```

### 建立測試訊息

```sql
-- 建立測試訊息
SELECT public.dev_create_test_message(
    p_conversation_id := 1,                            -- 對話 ID
    p_sender_id := '00000000-0000-0000-0000-000000000001'::uuid,  -- 發送者 UUID
    p_content := '這是一則測試訊息'                     -- 訊息內容
);

-- 會回傳新建立的 message_id
```

### 批次建立測試資料

```sql
-- 建立多筆測試對話和訊息
DO $$
DECLARE
    v_conversation_id BIGINT;
    v_buyer_uuid UUID := '00000000-0000-0000-0000-000000000001';
    v_seller_uuid UUID := '00000000-0000-0000-0000-000000000002';
BEGIN
    -- 建立對話
    v_conversation_id := public.dev_create_test_conversation(
        p_item_id := 1,
        p_buyer_id := v_buyer_uuid,
        p_seller_id := v_seller_uuid
    );

    -- 建立買家的訊息
    PERFORM public.dev_create_test_message(
        p_conversation_id := v_conversation_id,
        p_sender_id := v_buyer_uuid,
        p_content := '您好，請問這個物品還在嗎？'
    );

    -- 建立賣家的回覆
    PERFORM public.dev_create_test_message(
        p_conversation_id := v_conversation_id,
        p_sender_id := v_seller_uuid,
        p_content := '在的！歡迎詢問'
    );

    -- 建立更多訊息
    PERFORM public.dev_create_test_message(
        p_conversation_id := v_conversation_id,
        p_sender_id := v_buyer_uuid,
        p_content := '可以面交嗎？'
    );

    PERFORM public.dev_create_test_message(
        p_conversation_id := v_conversation_id,
        p_sender_id := v_seller_uuid,
        p_content := '可以的，台北車站方便嗎？'
    );

    RAISE NOTICE '✅ 測試資料建立完成！';
END $$;
```

### 清空測試資料

```sql
-- ⚠️ 警告：這會刪除所有對話和訊息資料！
SELECT public.dev_clear_all_conversations();

-- 會回傳刪除的統計資訊
-- 範例: {"conversations_deleted": 10, "messages_deleted": 45, "sequences_reset": true}
```

---

## 🧪 前端測試

### TypeScript 範例

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// 1. 查看所有對話（不需要登入）
const { data: conversations } = await supabase
  .from('dev_all_conversations')
  .select('*');

console.log('所有對話:', conversations);

// 2. 查看所有訊息（不需要登入）
const { data: messages } = await supabase
  .from('dev_all_messages')
  .select('*')
  .eq('conversation_id', 1);

console.log('對話訊息:', messages);

// 3. 直接插入對話（不需要驗證權限）
const { data: newConversation, error } = await supabase
  .from('conversations')
  .insert({
    item_id: 1,
    buyer_id: 'buyer-uuid',
    seller_id: 'seller-uuid'
  })
  .select()
  .single();

// 4. 直接插入訊息（不需要驗證權限）
const { data: newMessage } = await supabase
  .from('conversation_messages')
  .insert({
    conversation_id: 1,
    sender_id: 'sender-uuid',
    content: '測試訊息'
  })
  .select()
  .single();

// 5. 使用開發專用函數
const { data: conversationId } = await supabase
  .rpc('dev_create_test_conversation', {
    p_item_id: 1,
    p_buyer_id: 'buyer-uuid',
    p_seller_id: 'seller-uuid'
  });

const { data: messageId } = await supabase
  .rpc('dev_create_test_message', {
    p_conversation_id: conversationId,
    p_sender_id: 'sender-uuid',
    p_content: '測試訊息'
  });
```

---

## 🔍 驗證設定

### 檢查 RLS 狀態

```sql
-- 檢查 conversations 表的 RLS 狀態
SELECT
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE tablename IN ('conversations', 'conversation_messages');

-- 預期結果: rls_enabled 都應該是 false
```

### 檢查政策數量

```sql
-- 檢查 RLS 政策
SELECT
    schemaname,
    tablename,
    policyname
FROM pg_policies
WHERE tablename IN ('conversations', 'conversation_messages');

-- 預期結果: 應該沒有任何政策
```

### 檢查權限設定

```sql
-- 檢查 anon 角色權限
SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
AND table_name IN ('conversations', 'conversation_messages')
AND grantee = 'anon';

-- 預期結果: 應該有 INSERT, SELECT, UPDATE, DELETE 等權限
```

---

## 🔄 如何恢復 RLS

### 方法 1: 執行恢復 SQL

```sql
-- 1. 刪除開發工具
DROP VIEW IF EXISTS public.dev_all_conversations CASCADE;
DROP VIEW IF EXISTS public.dev_all_messages CASCADE;
DROP FUNCTION IF EXISTS public.dev_create_test_conversation(BIGINT, UUID, UUID);
DROP FUNCTION IF EXISTS public.dev_create_test_message(BIGINT, UUID, TEXT);
DROP FUNCTION IF EXISTS public.dev_clear_all_conversations();

-- 2. 撤銷過度權限
REVOKE ALL ON public.conversations FROM anon;
REVOKE ALL ON public.conversation_messages FROM anon;

-- 3. 重新啟用 RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

-- 4. 重新建立 RLS 政策
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
```

### 方法 2: 建立恢復 Migration

建立新檔案 `20251109110000_restore_messaging_rls_jo.sql`，內容包含上述恢復 SQL。

```bash
# 執行恢復 migration
supabase db push
```

---

## ⚠️ 重要注意事項

### 安全性警告

1. **絕對不要在生產環境使用** 🚫
   - 任何人都可以存取所有對話和訊息
   - 沒有權限控制
   - 資料完全暴露

2. **只在開發/測試環境使用** ✅
   - 本機開發環境
   - CI/CD 測試環境
   - 獨立的測試資料庫

3. **測試完成後請恢復 RLS** ⚡
   - 避免忘記恢復而部署到生產環境
   - 定期檢查環境設定

### 資料安全

- 🔒 不要在開發環境使用真實使用者資料
- 🔒 使用假資料進行測試
- 🔒 定期清空測試資料

### 最佳實踐

1. **使用環境變數區分環境**
   ```typescript
   const isProduction = process.env.NODE_ENV === 'production';
   if (isProduction) {
     // 禁止執行開發專用函數
     throw new Error('Development functions are not allowed in production');
   }
   ```

2. **建立獨立的測試資料庫**
   - 不要在生產資料庫上測試
   - 使用 Supabase 的分支功能

3. **定期檢查設定**
   ```sql
   -- 定期執行檢查
   SELECT * FROM pg_tables 
   WHERE tablename IN ('conversations', 'conversation_messages')
   AND rowsecurity = false;
   
   -- 如果在生產環境發現 RLS 被停用，立即恢復！
   ```

---

## 📊 常見問題

### Q1: 執行 migration 後前端仍然無法存取？

**A:** 檢查以下項目：
1. Migration 是否執行成功？
2. RLS 是否真的被停用？（執行驗證 SQL）
3. 前端是否正確連接到測試環境？

### Q2: 如何確認是否在開發環境？

**A:** 執行以下 SQL：
```sql
SELECT current_database();
-- 確認資料庫名稱是否為測試環境
```

### Q3: 可以只停用特定使用者的 RLS 嗎？

**A:** RLS 是表級別的設定，無法針對特定使用者停用。建議使用獨立的測試資料庫。

### Q4: 開發工具會影響生產環境的函數嗎？

**A:** 不會。開發工具都有 `dev_` 前綴，與生產環境函數分離。但仍建議測試完成後刪除。

---

## 📚 相關文件

- **Migration 檔案:** `20251109100000_dev_disable_messaging_rls_jo.sql`
- **清理指南:** `CLEANUP_GUIDE.md`
- **評估報告:** `DEPRECATED_FUNCTIONS_EVALUATION.md`
- **Migrations 總覽:** `README.md`

---

## 🆘 需要協助？

如果遇到問題，請聯絡：

- **Backend Team** - 資料庫設定問題
- **DevOps Team** - 環境配置問題
- **Security Team** - 安全性疑慮

---

**文件版本:** 1.0  
**建立日期:** 2024-11-09  
**適用環境:** 開發/測試環境  
**維護者:** Backend Team