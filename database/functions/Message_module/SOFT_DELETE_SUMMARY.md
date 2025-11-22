# v2 軟刪除功能總結

## ✅ 現有功能

### 1. 訊息軟刪除 (已實作資料表欄位)

**資料表設計**:
```sql
-- conversation_messages_v2 表
is_deleted BOOLEAN NOT NULL DEFAULT false,
deleted_at TIMESTAMPTZ,
```

**查詢過濾**:
- `get_conversation_messages_v2` 函數預設排除已刪除訊息
- 可選參數 `p_include_deleted` 控制是否顯示

**安全性**:
- RLS 政策禁止硬刪除 (DELETE)
- 只能通過軟刪除更新狀態

### 2. 對話歸檔 (取代軟刪除)

**資料表設計**:
```sql
-- conversations_v2 表
archived_by_participant_1 BOOLEAN NOT NULL DEFAULT false,
archived_by_participant_2 BOOLEAN NOT NULL DEFAULT false,
```

**功能**:
- 每個參與者可獨立歸檔對話
- 歸檔的對話預設不顯示在列表中
- 可隨時取消歸檔

## 🆕 新增功能 (補充)

### API 函數

```javascript
// 軟刪除訊息 (僅發送者可刪除)
await deleteMessage(messageId);

// 恢復已刪除的訊息
await restoreMessage(messageId);
```

### SQL 函數

```sql
-- 軟刪除訊息
SELECT soft_delete_message_v2(message_id);

-- 恢復訊息
SELECT restore_message_v2(message_id);
```

## 📊 完整對照表

| 項目 | 對話 | 訊息 |
|------|------|------|
| **刪除方式** | 歸檔 | 軟刪除 |
| **欄位** | `archived_by_participant_1/2` | `is_deleted`, `deleted_at` |
| **權限** | 參與者可歸檔 | 僅發送者可刪除 |
| **可恢復** | ✅ 是 | ✅ 是 |
| **雙向獨立** | ✅ 是 | ❌ 否 |
| **API 函數** | `archiveConversation()` | `deleteMessage()`, `restoreMessage()` |

## 🔒 安全規則

### 訊息刪除限制
- ✅ 只能刪除自己發送的訊息
- ✅ 不能刪除別人的訊息
- ✅ 需要認證才能操作
- ✅ 禁止硬刪除 (資料永久保留)

### 對話歸檔限制
- ✅ 只能歸檔自己的對話視圖
- ✅ 不影響對方的對話視圖
- ✅ 需要認證才能操作
- ✅ 禁止硬刪除

## 📝 使用範例

### 訊息軟刪除
```javascript
import { deleteMessage, restoreMessage, getMessages } from './conversationAPI_v2.js';

// 刪除訊息
await deleteMessage(789);

// 查詢時預設不顯示已刪除訊息
const messages = await getMessages(456);
// 已刪除的訊息不會出現

// 恢復訊息
await restoreMessage(789);
```

### 對話歸檔
```javascript
import { archiveConversation, getConversations } from './conversationAPI_v2.js';

// 歸檔對話
await archiveConversation(456, true);

// 查詢時預設不顯示已歸檔對話
const conversations = await getConversations();
// 已歸檔的對話不會出現

// 包含已歸檔對話
const allConversations = await getConversations(1, 20, true);

// 取消歸檔
await archiveConversation(456, false);
```

## 🎯 設計理念

### 為什麼對話用歸檔而非軟刪除?

1. **用戶體驗**: 歸檔更符合聊天軟體的使用習慣 (如 Telegram, WhatsApp)
2. **雙向獨立**: 兩個用戶可以獨立管理自己的對話視圖
3. **可恢復性**: 隨時可以取消歸檔,找回對話
4. **語意清晰**: "歸檔"比"刪除"更準確表達功能

### 為什麼訊息用軟刪除?

1. **資料保留**: 防止誤刪,可以恢復
2. **審計需求**: 保留刪除記錄和時間
3. **法律合規**: 某些場景需要保留歷史訊息
4. **發送者控制**: 只有發送者可以刪除自己的訊息

## 📋 安裝步驟

```bash
# 執行軟刪除函數腳本
psql -U postgres -d your_database \
  -f migrations/add_soft_delete_functions.sql
```

## ✅ 總結

v2 方案**有完整的軟刪除設計**:

- ✅ 訊息: 軟刪除 + 恢復功能
- ✅ 對話: 歸檔機制 (更適合的替代方案)
- ✅ RLS 安全性保護
- ✅ API 完整封裝
- ✅ 符合最佳實踐
