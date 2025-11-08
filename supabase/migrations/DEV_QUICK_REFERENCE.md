# 開發環境快速參考卡 🚀

> **⚠️ 僅限開發/測試環境使用！**

---

## 📦 一鍵設定

```bash
# 執行開發環境 migration
supabase db push
```

或在 SQL Editor 執行：
```sql
-- 檔案: 20251109100000_dev_disable_messaging_rls_jo.sql
```

---

## 🛠️ 開發工具

### 視圖（查看資料）

```sql
-- 查看所有對話
SELECT * FROM dev_all_conversations;

-- 查看所有訊息
SELECT * FROM dev_all_messages;
```

### 函數（建立測試資料）

```sql
-- 建立測試對話
SELECT dev_create_test_conversation(
    p_item_id := 1,
    p_buyer_id := 'uuid-here'::uuid,
    p_seller_id := 'uuid-here'::uuid
);

-- 建立測試訊息
SELECT dev_create_test_message(
    p_conversation_id := 1,
    p_sender_id := 'uuid-here'::uuid,
    p_content := '測試訊息內容'
);

-- 清空所有資料 ⚠️
SELECT dev_clear_all_conversations();
```

---

## 🧪 前端測試

### 無需登入即可存取

```typescript
// 查看所有對話（無需認證）
const { data } = await supabase
  .from('dev_all_conversations')
  .select('*');

// 直接插入訊息（無需驗證）
const { data } = await supabase
  .from('conversation_messages')
  .insert({
    conversation_id: 1,
    sender_id: 'any-uuid',
    content: '測試訊息'
  });
```

---

## ✅ 驗證設定

```sql
-- 檢查 RLS 狀態（應該是 false）
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename IN ('conversations', 'conversation_messages');

-- 檢查政策數量（應該是 0）
SELECT COUNT(*) FROM pg_policies 
WHERE tablename IN ('conversations', 'conversation_messages');
```

---

## 🔄 恢復 RLS（測試完成後）

```sql
-- 1. 刪除開發工具
DROP VIEW IF EXISTS dev_all_conversations CASCADE;
DROP VIEW IF EXISTS dev_all_messages CASCADE;
DROP FUNCTION IF EXISTS dev_create_test_conversation;
DROP FUNCTION IF EXISTS dev_create_test_message;
DROP FUNCTION IF EXISTS dev_clear_all_conversations;

-- 2. 撤銷權限
REVOKE ALL ON conversations FROM anon;
REVOKE ALL ON conversation_messages FROM anon;

-- 3. 啟用 RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_messages ENABLE ROW LEVEL SECURITY;

-- 4. 重建政策（參考 DEV_TESTING_GUIDE.md）
```

---

## 📝 快速測試腳本

```sql
-- 批次建立測試資料
DO $$
DECLARE
    v_conv_id BIGINT;
    v_buyer UUID := gen_random_uuid();
    v_seller UUID := gen_random_uuid();
BEGIN
    -- 建立對話
    v_conv_id := dev_create_test_conversation(1, v_buyer, v_seller);
    
    -- 建立對話訊息
    PERFORM dev_create_test_message(v_conv_id, v_buyer, '嗨！');
    PERFORM dev_create_test_message(v_conv_id, v_seller, '你好！');
    PERFORM dev_create_test_message(v_conv_id, v_buyer, '還在嗎？');
    
    RAISE NOTICE '✅ 測試資料建立完成！對話 ID: %', v_conv_id;
END $$;
```

---

## ⚠️ 安全提醒

| ❌ 不要 | ✅ 要 |
|--------|------|
| 在生產環境使用 | 僅在開發環境使用 |
| 使用真實資料測試 | 使用假資料測試 |
| 忘記恢復 RLS | 測試完立即恢復 |
| 部署到正式環境 | 定期檢查環境設定 |

---

## 📚 完整文件

- **詳細指南:** `DEV_TESTING_GUIDE.md`
- **Migration:** `20251109100000_dev_disable_messaging_rls_jo.sql`

---

**版本:** 1.0 | **更新:** 2024-11-09 | **環境:** Dev/Test Only