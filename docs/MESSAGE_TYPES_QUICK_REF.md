# 訊息類型快速參考卡

## 🎯 所有支援的訊息類型

| 類型 | 圖示 | 必要參數 | 可選參數 | 用途 |
|------|------|----------|----------|------|
| `text` | ✉️ | `content` | - | 普通文字訊息 |
| `image` | 🖼️ | `content` (URL) | - | 圖片訊息 |
| `system` | ⚙️ | `content` | - | 系統自動訊息 |
| `item_reference` | 📦 | `content`, `relatedItemId` | - | 引用商品 |
| `reply` | 💬 | `content`, `replyToMessageId` | - | 回覆特定訊息 |
| `transaction_link` | 🤝 | `content`, `transactionId` | `relatedItemId` | 關聯交易記錄 |

---

## 📝 快速使用範例

### Text 文字訊息
```javascript
await sendMessage(conversationId, 'Hello!', 'text');
```

### Image 圖片訊息
```javascript
await sendMessage(conversationId, 'https://example.com/image.jpg', 'image');
```

### Item Reference 商品引用
```javascript
await sendMessage(conversationId, '請看這個商品', 'item_reference', 789);
```

### Reply 回覆訊息 (新)
```javascript
await sendMessage(conversationId, '同意', 'reply', null, originalMessageId);
```

### Transaction Link 交易連結 (新)
```javascript
await sendMessage(conversationId, '交易已建立', 'transaction_link', null, null, txId);
```

---

## 🔧 API 函數簽名

```javascript
sendMessage(
  conversationId,      // BIGINT - 對話 ID
  content,             // TEXT - 訊息內容
  messageType?,        // VARCHAR - 訊息類型 (預設 'text')
  relatedItemId?,      // BIGINT - 關聯商品 ID
  replyToMessageId?,   // BIGINT - 回覆的訊息 ID
  transactionId?       // BIGINT - 交易 ID
)
```

```javascript
getMessageReplies(
  messageId,           // BIGINT - 訊息 ID
  page?,               // INT - 頁碼 (預設 1)
  size?                // INT - 每頁筆數 (預設 20)
)
```

---

## 📊 返回資料結構

```javascript
{
  message_id: 123,
  conversation_id: 456,
  sender_id: 'uuid',
  sender_name: '張三',
  sender_avatar: 'https://...',
  content: '訊息內容',
  message_type: 'text',
  
  // 商品相關
  related_item_id: 789,
  related_item_title: '商品名稱',
  
  // 回覆相關 (新)
  reply_to_message_id: 100,
  reply_to_content: '被回覆的內容',
  reply_to_sender_name: '李四',
  
  // 交易相關 (新)
  transaction_id: 1001,
  
  // 狀態
  is_deleted: false,
  is_mine: true,
  is_read: false,
  created_at: '2024-01-15T10:30:00Z'
}
```

---

## ✅ 驗證規則

### Reply 類型
- ✔️ 必須提供 `replyToMessageId`
- ✔️ 被回覆的訊息必須存在
- ✔️ 被回覆的訊息必須在同一對話中
- ❌ 不能回覆已刪除的訊息

### Transaction Link 類型
- ✔️ 必須提供 `transactionId`
- ✔️ 可選擇性關聯 `relatedItemId`

---

## ⚠️ 常見錯誤

```javascript
// ❌ 錯誤：reply 沒有 replyToMessageId
await sendMessage(conversationId, 'Reply', 'reply');

// ✅ 正確
await sendMessage(conversationId, 'Reply', 'reply', null, messageId);
```

```javascript
// ❌ 錯誤：transaction_link 沒有 transactionId
await sendMessage(conversationId, 'TX', 'transaction_link');

// ✅ 正確
await sendMessage(conversationId, 'TX', 'transaction_link', null, null, txId);
```

---

## 🎨 UI 渲染建議

### Reply 訊息
```jsx
<div className="message-reply">
  {/* 引用區塊 */}
  <div className="reply-reference">
    <span>{reply_to_sender_name}</span>
    <p>{reply_to_content}</p>
  </div>
  {/* 回覆內容 */}
  <p>{content}</p>
</div>
```

### Transaction Link 訊息
```jsx
<div className="message-transaction">
  <div className="transaction-card">
    <span>🤝</span>
    <p>{content}</p>
    <button onClick={() => viewTransaction(transaction_id)}>
      查看交易
    </button>
  </div>
</div>
```

---

## 📁 相關檔案

- 📖 [完整使用指南](./message_types_guide.md)
- 💻 [範例程式碼](../examples/message_types_examples.js)
- 📋 [更新說明](./MESSAGE_V2_UPDATE_README.md)
- 🔧 [API 原始碼](../contracts/conversationAPI/conversationAPI_v2.js)

---

## 🚀 快速開始

1. **執行遷移**
   ```bash
   supabase db push
   ```

2. **測試功能**
   ```javascript
   const msg = await sendMessage(456, 'Test', 'reply', null, 789);
   console.log(msg.message_type); // 'reply'
   ```

3. **更新 UI**
   - 新增回覆按鈕
   - 處理新的訊息類型渲染

---

**版本**: v2.1.0  
**最後更新**: 2025-11-20