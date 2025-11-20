# Message V2 訊息類型更新說明

## 📋 更新概述

**更新日期**: 2025-11-20  
**版本**: v2.1.0  
**作者**: Jo

本次更新為 Conversation API v2 新增了兩種新的訊息類型：`reply` (回覆訊息) 和 `transaction_link` (交易連結)，以支援更豐富的對話互動功能。

---

## ✨ 新增功能

### 1. Reply 訊息類型 💬

允許用戶回覆對話中的特定訊息，建立訊息間的引用關係。

**主要特性：**
- 支援引用回覆任意訊息
- 自動關聯被回覆訊息的內容和發送者資訊
- 提供專用 API 查詢特定訊息的所有回覆
- 資料庫層級保護，確保回覆訊息在同一對話中

**使用範例：**
```javascript
const replyMsg = await sendMessage(
  conversationId,
  '我同意你的看法',
  'reply',
  null,                    // relatedItemId
  originalMessageId        // replyToMessageId
);
```

### 2. Transaction Link 訊息類型 🤝

將交易記錄連結到對話中，方便追蹤交易狀態。

**主要特性：**
- 關聯交易 ID 到訊息
- 可同時關聯商品資訊
- 適用於交易建立、狀態更新等場景

**使用範例：**
```javascript
const txMsg = await sendMessage(
  conversationId,
  '交易已建立，編號 #1001',
  'transaction_link',
  itemId,                  // relatedItemId (可選)
  null,                    // replyToMessageId
  transactionId            // transactionId
);
```

---

## 📦 檔案變更

### 新增檔案

1. **遷移檔案**
   - `backend/supabase/migrations/20251120072702_feature_message_v2_new_type_jo.sql`
   - 包含完整的資料庫結構變更和 RPC 函數更新

2. **說明文件**
   - `backend/docs/message_types_guide.md`
   - 詳細的使用指南和範例

3. **範例程式碼**
   - `backend/examples/message_types_examples.js`
   - 10 個實際使用範例

4. **本文件**
   - `backend/docs/MESSAGE_V2_UPDATE_README.md`
   - 更新說明

### 修改檔案

1. **API 合約**
   - `backend/contracts/conversationAPI/conversationAPI_v2.js`
   - 更新 `sendMessage()` 函數簽名
   - 新增 `getMessageReplies()` 函數
   - 更新 JSDoc 註解

---

## 🗄️ 資料庫變更

### 新增欄位

```sql
ALTER TABLE conversation_messages_v2
ADD COLUMN reply_to_message_id BIGINT,
ADD COLUMN transaction_id BIGINT;
```

### 更新約束

**訊息類型檢查：**
```sql
CHECK (message_type IN (
    'text',
    'image',
    'system',
    'item_reference',
    'reply',              -- 新增
    'transaction_link'    -- 新增
))
```

**業務邏輯約束：**
- reply 類型必須有 `reply_to_message_id`
- transaction_link 類型必須有 `transaction_id`
- 回覆的訊息必須在同一對話中 (觸發器保護)

### 新增索引

```sql
-- reply_to_message_id 索引
CREATE INDEX idx_conversation_messages_v2_reply_to
    ON conversation_messages_v2(reply_to_message_id)
    WHERE reply_to_message_id IS NOT NULL;

-- transaction_id 索引
CREATE INDEX idx_conversation_messages_v2_transaction
    ON conversation_messages_v2(transaction_id)
    WHERE transaction_id IS NOT NULL;

-- message_type 索引
CREATE INDEX idx_conversation_messages_v2_message_type
    ON conversation_messages_v2(message_type);
```

### 更新 RPC 函數

1. **send_message_v2**
   - 新增參數：`p_reply_to_message_id`, `p_transaction_id`
   - 新增驗證邏輯

2. **get_conversation_messages_v2**
   - 返回新欄位：`reply_to_message_id`, `reply_to_content`, `reply_to_sender_name`, `transaction_id`
   - 使用 LEFT JOIN 載入回覆訊息資訊

3. **get_message_replies_v2** (新增)
   - 查詢特定訊息的所有回覆

---

## 🚀 部署步驟

### 1. 執行資料庫遷移

```bash
# 使用 Supabase CLI
supabase db push

# 或直接執行 SQL 檔案
psql -h [host] -d [database] -U [user] \
  -f backend/supabase/migrations/20251120072702_feature_message_v2_new_type_jo.sql
```

### 2. 更新應用程式碼

```bash
# 拉取最新程式碼
git pull origin main

# 安裝依賴 (如有需要)
npm install

# 重啟應用
npm restart
```

### 3. 驗證部署

```javascript
// 測試 reply 功能
const msg1 = await sendMessage(conversationId, 'Test', 'text');
const msg2 = await sendMessage(conversationId, 'Reply', 'reply', null, msg1.message_id);
console.log('Reply 功能正常:', msg2.message_type === 'reply');

// 測試 transaction_link 功能
const msg3 = await sendMessage(conversationId, 'TX', 'transaction_link', null, null, 1001);
console.log('Transaction Link 功能正常:', msg3.message_type === 'transaction_link');
```

---

## 📖 API 變更

### sendMessage() 函數

**舊版本 (v2.0):**
```javascript
sendMessage(conversationId, content, messageType?, relatedItemId?)
```

**新版本 (v2.1):**
```javascript
sendMessage(
  conversationId, 
  content, 
  messageType?, 
  relatedItemId?,
  replyToMessageId?,    // 新增
  transactionId?        // 新增
)
```

### 新增函數

```javascript
getMessageReplies(messageId, page?, size?)
```

### getMessages() 返回資料

**新增欄位：**
- `reply_to_message_id`: 被回覆的訊息 ID
- `reply_to_content`: 被回覆的訊息內容
- `reply_to_sender_name`: 被回覆訊息的發送者
- `transaction_id`: 關聯的交易 ID

---

## 🔄 向後相容性

### ✅ 完全相容

- 所有現有的訊息類型 (`text`, `image`, `system`, `item_reference`) 正常運作
- 現有的 API 呼叫不受影響
- 新增的參數都是可選的，預設值為 `null`
- v1 和 v2 可以並存運行

### ⚠️ 注意事項

1. **前端更新建議**
   - 更新訊息渲染邏輯，支援新的訊息類型
   - 新增回覆按鈕和 UI
   - 處理交易連結的點擊事件

2. **資料遷移**
   - 現有訊息的 `reply_to_message_id` 和 `transaction_id` 會是 `NULL`
   - 不影響現有功能

---

## 💡 使用場景

### Reply 訊息

1. **快速回應特定問題**
   ```
   買家: 這個商品有現貨嗎？
   賣家: [回覆] 有的，目前還有 5 個
   ```

2. **引用討論**
   ```
   用戶A: 這個價格可以接受
   用戶B: [回覆] 我也覺得
   ```

3. **多話題對話**
   - 在討論多個商品時，清楚指出回覆的是哪個問題

### Transaction Link 訊息

1. **交易建立通知**
   ```
   系統: 交易已建立！交易編號 #1001
   ```

2. **狀態更新**
   ```
   系統: 交易 #1001 已完成付款
   ```

3. **快速存取**
   - 點擊訊息直接跳轉到交易詳情頁

---

## 🧪 測試建議

### 單元測試

```javascript
describe('Message Types v2.1', () => {
  test('發送 reply 訊息', async () => {
    const msg1 = await sendMessage(convId, 'Original', 'text');
    const msg2 = await sendMessage(convId, 'Reply', 'reply', null, msg1.message_id);
    expect(msg2.reply_to_message_id).toBe(msg1.message_id);
  });

  test('發送 transaction_link 訊息', async () => {
    const msg = await sendMessage(convId, 'TX', 'transaction_link', null, null, 1001);
    expect(msg.transaction_id).toBe(1001);
  });

  test('reply 缺少 reply_to_message_id 應失敗', async () => {
    await expect(
      sendMessage(convId, 'Reply', 'reply', null, null)
    ).rejects.toThrow();
  });
});
```

### 整合測試

1. 完整對話流程測試
2. Realtime 訂閱測試
3. 多用戶互動測試

---

## 📚 相關文件

- [訊息類型完整指南](./message_types_guide.md)
- [使用範例程式碼](../examples/message_types_examples.js)
- [API 文件](../contracts/conversationAPI/conversationAPI_v2.js)
- [遷移檔案](../supabase/migrations/20251120072702_feature_message_v2_new_type_jo.sql)

---

## 🐛 已知問題

目前沒有已知問題。

---

## 🔮 未來規劃

- [ ] 新增訊息編輯功能
- [ ] 支援訊息反應 (emoji reactions)
- [ ] 訊息撤回功能增強
- [ ] 訊息搜尋優化

---

## 📞 支援

如有問題或建議，請：
1. 查閱 [訊息類型使用指南](./message_types_guide.md)
2. 參考 [範例程式碼](../examples/message_types_examples.js)
3. 聯絡開發團隊

---

## 📝 變更日誌

### v2.1.0 (2025-11-20)

**新增：**
- ✨ 新增 `reply` 訊息類型
- ✨ 新增 `transaction_link` 訊息類型
- ✨ 新增 `getMessageReplies()` API 函數
- 📝 新增完整使用文件和範例

**資料庫：**
- 🗄️ 新增 `reply_to_message_id` 欄位
- 🗄️ 新增 `transaction_id` 欄位
- 🔍 新增相關索引以優化查詢效能
- 🛡️ 新增業務邏輯約束和觸發器

**API：**
- 🔄 更新 `send_message_v2()` RPC 函數
- 🔄 更新 `get_conversation_messages_v2()` RPC 函數
- ➕ 新增 `get_message_replies_v2()` RPC 函數

---

## ✅ 檢查清單

部署前請確認：

- [ ] 已執行資料庫遷移
- [ ] 已更新應用程式碼
- [ ] 已測試新功能
- [ ] 已更新前端 UI (如適用)
- [ ] 已通知相關團隊成員
- [ ] 已更新 API 文件

---

**最後更新**: 2025-11-20  
**維護者**: Jo