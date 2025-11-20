# Conversation API v2 - 訊息類型使用指南

## 概述

此文件說明 Conversation API v2 支援的所有訊息類型及其使用方式。

## 支援的訊息類型

### 1. `text` - 文字訊息 ✉️

最基本的訊息類型，用於發送純文字內容。

**使用範例：**
```javascript
const message = await sendMessage(
  456,           // conversationId
  'Hello!',      // content
  'text'         // messageType
);
```

**必要欄位：**
- `content`: 訊息內容

---

### 2. `image` - 圖片訊息 🖼️

用於發送圖片訊息，`content` 欄位應包含圖片的 URL。

**使用範例：**
```javascript
const message = await sendMessage(
  456,
  'https://example.com/image.jpg',
  'image'
);
```

**必要欄位：**
- `content`: 圖片 URL

---

### 3. `system` - 系統訊息 ⚙️

系統自動產生的訊息，例如：「對話已建立」、「商品已售出」等。

**使用範例：**
```javascript
const message = await sendMessage(
  456,
  '對話已建立',
  'system'
);
```

**必要欄位：**
- `content`: 系統訊息內容

**注意事項：**
- 通常由後端自動產生，前端較少直接使用

---

### 4. `item_reference` - 商品引用 📦

在對話中引用特定商品，適用於多商品對話場景。

**使用範例：**
```javascript
const message = await sendMessage(
  456,
  '這個商品還有嗎？',
  'item_reference',
  789  // relatedItemId
);
```

**必要欄位：**
- `content`: 訊息內容
- `relatedItemId`: 關聯的商品 ID

**返回資料包含：**
- `related_item_id`: 商品 ID
- `related_item_title`: 商品標題（在 getMessages 時提供）

---

### 5. `reply` - 回覆訊息 💬 (新增)

回覆對話中的特定訊息，建立訊息間的引用關係。

**使用範例：**
```javascript
const message = await sendMessage(
  456,
  '我也這麼覺得！',
  'reply',
  null,  // relatedItemId (不需要)
  789    // replyToMessageId (被回覆的訊息 ID)
);
```

**必要欄位：**
- `content`: 回覆內容
- `replyToMessageId`: 被回覆的訊息 ID

**返回資料包含：**
- `reply_to_message_id`: 被回覆的訊息 ID
- `reply_to_content`: 被回覆的訊息內容（在 getMessages 時提供）
- `reply_to_sender_name`: 被回覆訊息的發送者名稱（在 getMessages 時提供）

**業務邏輯限制：**
- 被回覆的訊息必須存在於同一對話中
- 不能回覆已刪除的訊息

**取得訊息的所有回覆：**
```javascript
const replies = await getMessageReplies(
  789,   // messageId
  1,     // page
  20     // size
);

// 返回：
// [
//   {
//     message_id: 790,
//     sender_id: 'uuid-here',
//     sender_name: '李四',
//     sender_avatar: 'https://...',
//     content: '我同意你的看法',
//     created_at: '2024-01-15T10:35:00Z'
//   }
// ]
```

---

### 6. `transaction_link` - 交易連結 🤝 (新增)

關聯交易記錄，用於在對話中顯示交易相關訊息。

**使用範例：**
```javascript
const message = await sendMessage(
  456,
  '交易已建立，請盡快完成付款',
  'transaction_link',
  null,   // relatedItemId (可選)
  null,   // replyToMessageId (不需要)
  1001    // transactionId
);
```

**必要欄位：**
- `content`: 訊息內容
- `transactionId`: 關聯的交易 ID

**可選欄位：**
- `relatedItemId`: 可以同時關聯商品

**返回資料包含：**
- `transaction_id`: 交易 ID

**常見使用場景：**
- 買家發起交易後，系統自動發送交易連結訊息
- 賣家確認訂單時，發送確認訊息
- 交易狀態變更時，發送通知訊息

---

## 完整 API 使用範例

### 發送不同類型的訊息

```javascript
import {
  sendMessage,
  getMessages,
  getMessageReplies
} from './conversationAPI_v2.js';

// 1. 發送文字訊息
const textMsg = await sendMessage(456, 'Hello!', 'text');

// 2. 發送圖片訊息
const imageMsg = await sendMessage(
  456,
  'https://example.com/photo.jpg',
  'image'
);

// 3. 發送商品引用訊息
const itemMsg = await sendMessage(
  456,
  '請問這個還有貨嗎？',
  'item_reference',
  789  // 商品 ID
);

// 4. 發送回覆訊息
const replyMsg = await sendMessage(
  456,
  '同意你的看法',
  'reply',
  null,
  textMsg.message_id  // 回覆第一則訊息
);

// 5. 發送交易連結訊息
const txMsg = await sendMessage(
  456,
  '交易已建立，編號 #1001',
  'transaction_link',
  789,    // 可選：關聯商品
  null,
  1001    // 交易 ID
);
```

### 查詢訊息時的資料結構

```javascript
const messages = await getMessages(456);

// 訊息資料結構：
// [
//   {
//     message_id: 1,
//     sender_id: 'uuid-1',
//     sender_name: '張三',
//     sender_avatar: 'https://...',
//     content: 'Hello!',
//     message_type: 'text',
//     related_item_id: null,
//     related_item_title: null,
//     reply_to_message_id: null,
//     reply_to_content: null,
//     reply_to_sender_name: null,
//     transaction_id: null,
//     is_deleted: false,
//     is_mine: false,
//     is_read: true,
//     created_at: '2024-01-15T10:30:00Z'
//   },
//   {
//     message_id: 2,
//     sender_id: 'uuid-2',
//     sender_name: '李四',
//     sender_avatar: 'https://...',
//     content: '同意你的看法',
//     message_type: 'reply',
//     related_item_id: null,
//     related_item_title: null,
//     reply_to_message_id: 1,
//     reply_to_content: 'Hello!',
//     reply_to_sender_name: '張三',
//     transaction_id: null,
//     is_deleted: false,
//     is_mine: true,
//     is_read: false,
//     created_at: '2024-01-15T10:31:00Z'
//   }
// ]
```

---

## 資料庫層級說明

### 新增欄位

```sql
-- conversation_messages_v2 表新增欄位
ALTER TABLE conversation_messages_v2
ADD COLUMN reply_to_message_id BIGINT,
ADD COLUMN transaction_id BIGINT;
```

### CHECK 約束

```sql
-- message_type 必須是以下其中之一
CHECK (message_type IN (
    'text',
    'image',
    'system',
    'item_reference',
    'reply',             -- 新增
    'transaction_link'   -- 新增
))

-- reply 類型必須有 reply_to_message_id
CHECK (
    message_type != 'reply' OR reply_to_message_id IS NOT NULL
)

-- transaction_link 類型必須有 transaction_id
CHECK (
    message_type != 'transaction_link' OR transaction_id IS NOT NULL
)
```

### 觸發器保護

- `check_reply_in_same_conversation()`: 確保回覆的訊息在同一對話中

---

## 前端實作建議

### UI 渲染建議

#### 1. reply 訊息的顯示

```jsx
// React 範例
function MessageItem({ message }) {
  if (message.message_type === 'reply') {
    return (
      <div className="message-reply">
        {/* 顯示被回覆的訊息 */}
        <div className="reply-reference">
          <span className="reply-sender">{message.reply_to_sender_name}</span>
          <p className="reply-content">{message.reply_to_content}</p>
        </div>
        
        {/* 顯示回覆內容 */}
        <div className="reply-message">
          <p>{message.content}</p>
        </div>
      </div>
    );
  }
  
  // ... 其他類型
}
```

#### 2. transaction_link 訊息的顯示

```jsx
function MessageItem({ message }) {
  if (message.message_type === 'transaction_link') {
    return (
      <div className="message-transaction">
        <div className="transaction-card">
          <span className="transaction-icon">🤝</span>
          <p>{message.content}</p>
          <button onClick={() => viewTransaction(message.transaction_id)}>
            查看交易詳情
          </button>
        </div>
      </div>
    );
  }
  
  // ... 其他類型
}
```

### 互動功能建議

```jsx
// 回覆功能
function MessageActions({ message }) {
  const handleReply = () => {
    // 設定回覆狀態
    setReplyingTo(message);
  };
  
  return (
    <button onClick={handleReply}>
      回覆
    </button>
  );
}

// 發送回覆
function sendReply() {
  if (replyingTo) {
    await sendMessage(
      conversationId,
      inputText,
      'reply',
      null,
      replyingTo.message_id
    );
    setReplyingTo(null);
  }
}
```

---

## 錯誤處理

### 常見錯誤

```javascript
try {
  await sendMessage(456, '回覆', 'reply', null, null);
} catch (error) {
  // Error: reply 類型訊息必須指定 reply_to_message_id
}

try {
  await sendMessage(456, '交易', 'transaction_link', null, null, null);
} catch (error) {
  // Error: transaction_link 類型訊息必須指定 transaction_id
}

try {
  await sendMessage(456, '回覆', 'reply', null, 999999);
} catch (error) {
  // Error: 被回覆的訊息必須在同一對話中
}
```

---

## 遷移指南

### 從 v1 升級到 v2

如果您目前使用 v1 版本的訊息系統：

1. v1 和 v2 可以並存運行
2. 新功能建議使用 v2 API
3. v1 不支援 `reply` 和 `transaction_link` 類型

### 執行遷移

```bash
# 在 Supabase 中執行遷移檔案
psql -h [your-host] -d [your-db] -f backend/supabase/migrations/20251120072702_feature_message_v2_new_type_jo.sql
```

---

## 效能優化建議

### 索引

遷移檔案已自動建立以下索引：

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

### 查詢優化

```javascript
// 分頁載入訊息，避免一次載入過多資料
const messages = await getMessages(
  conversationId,
  1,   // page
  50   // size - 根據需求調整
);

// 只在需要時載入回覆
const replies = await getMessageReplies(messageId);
```

---

## 安全性考量

### Row Level Security (RLS)

確保已設定適當的 RLS 政策：

```sql
-- 只有對話參與者可以查看訊息
CREATE POLICY "Users can view messages in their conversations"
ON conversation_messages_v2
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM conversations_v2
    WHERE id = conversation_id
    AND (participant_1_id = auth.uid() OR participant_2_id = auth.uid())
  )
);
```

### 資料驗證

- 前端驗證：確保必要欄位已填寫
- 後端驗證：RPC 函數已包含完整驗證邏輯
- 觸發器保護：防止不合法的資料關聯

---

## 測試範例

```javascript
// 測試 reply 功能
describe('Reply Message Type', () => {
  it('should send a reply message', async () => {
    const originalMsg = await sendMessage(456, 'Original', 'text');
    const replyMsg = await sendMessage(
      456,
      'Reply',
      'reply',
      null,
      originalMsg.message_id
    );
    
    expect(replyMsg.message_type).toBe('reply');
    expect(replyMsg.reply_to_message_id).toBe(originalMsg.message_id);
  });
  
  it('should fail without reply_to_message_id', async () => {
    await expect(
      sendMessage(456, 'Reply', 'reply', null, null)
    ).rejects.toThrow('reply 類型訊息必須指定 reply_to_message_id');
  });
});

// 測試 transaction_link 功能
describe('Transaction Link Message Type', () => {
  it('should send a transaction link message', async () => {
    const txMsg = await sendMessage(
      456,
      'Transaction created',
      'transaction_link',
      null,
      null,
      1001
    );
    
    expect(txMsg.message_type).toBe('transaction_link');
    expect(txMsg.transaction_id).toBe(1001);
  });
});
```

---

## 相關資源

- [Conversation API v2 原始碼](../contracts/conversationAPI/conversationAPI_v2.js)
- [遷移檔案](../supabase/migrations/20251120072702_feature_message_v2_new_type_jo.sql)
- [Supabase 官方文件](https://supabase.com/docs)

---

## 版本歷史

- **v2.1.0** (2025-11-20): 新增 `reply` 和 `transaction_link` 訊息類型
- **v2.0.0**: 初始 v2 版本，支援去角色化設計

---

## 聯絡資訊

如有問題或建議，請聯絡開發團隊。