# 修復 Messaging V2 欄位名稱衝突問題

## 問題描述

在 PostgreSQL 函數中,`RETURNS TABLE` 定義的欄位名稱與 `RETURN QUERY SELECT ... AS` 中的別名衝突,導致錯誤:

```
column reference "conversation_id" is ambiguous
```

## 已修正的函數

1. ✅ `create_or_get_conversation_v2()`
2. ✅ `get_user_conversations_v2()`
3. ✅ `get_conversation_messages_v2()`
4. ✅ `get_conversation_items_v2()`

## 修正內容

### 原因
當 `RETURNS TABLE(conversation_id BIGINT, ...)` 定義了欄位名稱後,在 `RETURN QUERY SELECT` 中不應再使用 `AS conversation_id`,因為 PostgreSQL 無法判斷你指的是哪一個。

### 修正前
```sql
RETURNS TABLE(
    conversation_id BIGINT,
    ...
)
...
RETURN QUERY
SELECT
    v_conversation_id AS conversation_id,  -- ❌ 衝突!
    ...
```

### 修正後
```sql
RETURNS TABLE(
    conversation_id BIGINT,
    ...
)
...
RETURN QUERY
SELECT
    v_conversation_id,  -- ✅ 正確!直接回傳,PostgreSQL 會自動對應到 RETURNS TABLE 的欄位
    ...
```

## 如何執行遷移

### 方法 1: 使用 Supabase Dashboard (推薦)

1. 登入 [Supabase Dashboard](https://supabase.com/dashboard)
2. 選擇你的專案
3. 點選左側 **SQL Editor**
4. 建立新查詢
5. 複製整個 `messaging_v2_rpc_functions.sql` 檔案內容
6. 貼上並執行 (點選 **Run**)

### 方法 2: 使用 Supabase CLI

```bash
# 1. 確保已安裝 Supabase CLI
npm install -g supabase

# 2. 登入
supabase login

# 3. 連接到你的專案
supabase link --project-ref <your-project-ref>

# 4. 執行 SQL 檔案
supabase db execute -f backend/database/functions/Message_module/migrations/messaging_v2_rpc_functions.sql
```

### 方法 3: 使用 psql (如果你有直接資料庫存取權)

```bash
psql postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres \
  -f backend/database/functions/Message_module/migrations/messaging_v2_rpc_functions.sql
```

## 驗證修正

執行以下測試查詢確認函數正常工作:

```sql
-- 測試 1: 建立或取得對話
SELECT * FROM create_or_get_conversation_v2(
  'other-user-uuid-here'::uuid,
  123  -- item_id
);

-- 測試 2: 查詢對話列表
SELECT * FROM get_user_conversations_v2(1, 20, false);

-- 測試 3: 查詢訊息
SELECT * FROM get_conversation_messages_v2(1, 1, 50, false);

-- 測試 4: 查詢對話商品
SELECT * FROM get_conversation_items_v2(1);
```

## 前端無需修改

✅ 前端代碼完全正確,無需任何修改!

```javascript
// ✅ 這段代碼在 SQL 修正後會正常運作
const conversation = await createOrGetConversation(
  sellerId.value,
  props.product.item_id
);

router.push({
  name: 'Messages',
  query: { conversationId: conversation.conversation_id }
});
```

## 檢查清單

- [ ] 已執行 `messaging_v2_rpc_functions.sql`
- [ ] 沒有 SQL 錯誤訊息
- [ ] 前端可以成功建立對話
- [ ] 前端可以查看對話列表
- [ ] 前端可以發送和接收訊息

## 常見問題

### Q: 執行 SQL 時出現 "permission denied"?
**A:** 確保你使用的是 `postgres` 角色或有足夠權限的角色。在 Supabase Dashboard 的 SQL Editor 中執行時,會自動使用正確的角色。

### Q: 函數已經存在的警告?
**A:** 這是正常的,`CREATE OR REPLACE FUNCTION` 會覆蓋現有函數,不會造成問題。

### Q: 需要重啟 Supabase 專案嗎?
**A:** 不需要,函數更新後會立即生效。

## 技術細節

### PostgreSQL 函數返回機制

當函數定義為 `RETURNS TABLE(...)` 時:
1. PostgreSQL 會自動建立一個虛擬表結構
2. `RETURN QUERY SELECT` 的欄位會**按順序**對應到 `RETURNS TABLE` 的欄位
3. **不需要**也**不應該**使用 AS 別名重新命名,除非你想改變欄位順序

### 為什麼 Supabase RPC 回傳陣列?

即使 PostgreSQL 函數只回傳一筆資料,Supabase 的 `.rpc()` 方法會將結果包裝成陣列,以保持 API 的一致性。這就是為什麼 `conversationAPI_v2.js` 中需要 `return data[0]`。

---

**最後更新**: 2024-01-15
**版本**: 2.0.1
**狀態**: ✅ 已修正