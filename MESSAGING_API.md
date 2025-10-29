# 訊息傳遞功能 API 文件

## 概述

此文件說明基於 Supabase 的使用者訊息傳遞功能的 API 使用方式。本功能允許買家和賣家針對特定物品進行即時對話。

## 資料庫架構

### 主要資料表

1. **conversations** - 對話表
   - `id`: 對話 ID
   - `item_id`: 關聯的物品 ID
   - `buyer_id`: 買家使用者 ID
   - `seller_id`: 賣家使用者 ID
   - `created_at`: 建立時間
   - `updated_at`: 最後更新時間

2. **conversation_messages** - 訊息表
   - `id`: 訊息 ID
   - `conversation_id`: 所屬對話 ID
   - `sender_id`: 發送者使用者 ID
   - `content`: 訊息內容
   - `is_read`: 是否已讀
   - `sent_at`: 發送時間

## RPC 函數 API

### 1. 取得使用者的所有對話

**函數名稱**: `get_user_conversations`

**說明**: 取得當前使用者的所有對話列表，包含最後一則訊息和未讀訊息數量。

**參數**:
- `p_page` (INT, 選填, 預設: 1) - 頁碼
- `p_size` (INT, 選填, 預設: 20) - 每頁數量

**返回欄位**:
- `conversation_id`: 對話 ID
- `item_id`: 物品 ID
- `item_title`: 物品標題
- `item_image_url`: 物品圖片 URL
- `other_user_id`: 對方使用者 ID
- `other_user_nickname`: 對方暱稱
- `other_user_profile_picture`: 對方頭像 URL
- `last_message`: 最後一則訊息內容
- `last_message_time`: 最後訊息時間
- `unread_count`: 未讀訊息數量
- `created_at`: 對話建立時間
- `updated_at`: 對話更新時間

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('get_user_conversations', {
    p_page: 1,
    p_size: 20
  });
```

---

### 2. 取得對話的所有訊息

**函數名稱**: `get_conversation_messages`

**說明**: 取得特定對話中的所有訊息。

**參數**:
- `p_conversation_id` (BIGINT, 必填) - 對話 ID
- `p_page` (INT, 選填, 預設: 1) - 頁碼
- `p_size` (INT, 選填, 預設: 50) - 每頁數量

**返回欄位**:
- `message_id`: 訊息 ID
- `sender_id`: 發送者 ID
- `sender_nickname`: 發送者暱稱
- `sender_profile_picture`: 發送者頭像 URL
- `content`: 訊息內容
- `is_read`: 是否已讀
- `sent_at`: 發送時間

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('get_conversation_messages', {
    p_conversation_id: 123,
    p_page: 1,
    p_size: 50
  });
```

---

### 3. 發送訊息

**函數名稱**: `send_message`

**說明**: 在指定對話中發送新訊息。

**參數**:
- `p_conversation_id` (BIGINT, 必填) - 對話 ID
- `p_content` (TEXT, 必填) - 訊息內容

**返回欄位**:
- `message_id`: 新訊息 ID
- `sender_id`: 發送者 ID
- `content`: 訊息內容
- `is_read`: 是否已讀 (新訊息預設為 false)
- `sent_at`: 發送時間

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('send_message', {
    p_conversation_id: 123,
    p_content: '你好，這個物品還有嗎？'
  });
```

---

### 4. 標記訊息為已讀

**函數名稱**: `mark_messages_as_read`

**說明**: 將指定對話中所有未讀訊息標記為已讀（不包含自己發送的訊息）。

**參數**:
- `p_conversation_id` (BIGINT, 必填) - 對話 ID

**返回欄位**:
- `updated_count`: 更新的訊息數量

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('mark_messages_as_read', {
    p_conversation_id: 123
  });
```

---

### 5. 建立或取得對話

**函數名稱**: `create_or_get_conversation`

**說明**: 針對特定物品建立新對話，或取得已存在的對話。

**參數**:
- `p_item_id` (BIGINT, 必填) - 物品 ID

**返回欄位**:
- `conversation_id`: 對話 ID
- `item_id`: 物品 ID
- `buyer_id`: 買家 ID
- `seller_id`: 賣家 ID
- `created_at`: 建立時間
- `updated_at`: 更新時間

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('create_or_get_conversation', {
    p_item_id: 456
  });
```

---

### 6. 取得未讀訊息總數

**函數名稱**: `get_unread_message_count`

**說明**: 取得當前使用者所有對話的未讀訊息總數。

**參數**: 無

**返回欄位**:
- `unread_count`: 未讀訊息總數

**使用範例** (JavaScript):
```javascript
const { data, error } = await supabase
  .rpc('get_unread_message_count');
```

---

## Realtime 即時訊息訂閱

### 訂閱新訊息

**使用範例** (JavaScript):
```javascript
// 訂閱特定對話的新訊息
const channel = supabase
  .channel('conversation-123')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'conversation_messages',
      filter: `conversation_id=eq.123`
    },
    (payload) => {
      console.log('新訊息:', payload.new);
      // 處理新訊息
    }
  )
  .subscribe();

// 取消訂閱
// channel.unsubscribe();
```

### 訂閱訊息已讀狀態更新

**使用範例** (JavaScript):
```javascript
// 訂閱訊息已讀狀態變更
const channel = supabase
  .channel('conversation-messages-123')
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversation_messages',
      filter: `conversation_id=eq.123`
    },
    (payload) => {
      console.log('訊息狀態更新:', payload.new);
      // 處理已讀狀態更新
    }
  )
  .subscribe();
```

### 訂閱對話列表更新

**使用範例** (JavaScript):
```javascript
// 訂閱使用者的對話列表變化
const userId = 'current-user-uuid';
const channel = supabase
  .channel('user-conversations')
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'conversations',
      filter: `buyer_id=eq.${userId}`
    },
    (payload) => {
      console.log('對話列表更新:', payload);
      // 重新載入對話列表
    }
  )
  .subscribe();
```

---

## 安全性

所有 RPC 函數都包含以下安全檢查：

1. **身份驗證**: 使用 `auth.uid()` 確認使用者已登入
2. **權限驗證**: 確認使用者有權限存取該對話或訊息
3. **資料驗證**: 檢查輸入參數的有效性

Row Level Security (RLS) 政策已啟用：
- 使用者只能查看自己參與的對話
- 使用者只能在自己參與的對話中發送訊息
- 使用者只能查看自己參與的對話中的訊息

---

## 完整使用流程範例

### 情境：買家想詢問某個物品

```javascript
// 1. 買家點擊物品上的「聯繫賣家」按鈕
const { data: conversation, error: convError } = await supabase
  .rpc('create_or_get_conversation', {
    p_item_id: 456
  });

if (convError) {
  console.error('建立對話失敗:', convError);
  return;
}

const conversationId = conversation[0].conversation_id;

// 2. 發送第一則訊息
const { data: message, error: msgError } = await supabase
  .rpc('send_message', {
    p_conversation_id: conversationId,
    p_content: '你好，這個物品還有嗎？'
  });

// 3. 訂閱即時訊息
const channel = supabase
  .channel(`conversation-${conversationId}`)
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'conversation_messages',
      filter: `conversation_id=eq.${conversationId}`
    },
    (payload) => {
      console.log('收到新訊息:', payload.new);
      // 更新 UI 顯示新訊息
    }
  )
  .subscribe();

// 4. 當使用者查看對話時，標記訊息為已讀
const { data: readCount } = await supabase
  .rpc('mark_messages_as_read', {
    p_conversation_id: conversationId
  });
```

---

## 效能優化

1. **索引優化**: 
   - 已為 `conversation_messages` 表的未讀訊息建立複合索引
   - 已為 `conversations` 表的 `updated_at` 建立降序索引

2. **分頁支援**: 
   - 所有列表查詢都支援分頁，避免一次載入過多資料

3. **觸發器自動化**:
   - 當新訊息插入時，自動更新對話的 `updated_at` 時間戳

---

## 錯誤處理

所有 RPC 函數在遇到錯誤時會拋出例外，常見錯誤訊息：

- `使用者未登入` - 未通過身份驗證
- `無權限查看此對話` - 使用者不是對話參與者
- `訊息內容不能為空` - 發送空訊息
- `物品不存在或已下架` - 嘗試對不存在的物品建立對話
- `無法與自己的物品建立對話` - 嘗試對自己的物品建立對話

**錯誤處理範例**:
```javascript
const { data, error } = await supabase
  .rpc('send_message', {
    p_conversation_id: 123,
    p_content: '你好'
  });

if (error) {
  console.error('發送訊息失敗:', error.message);
  // 根據錯誤訊息顯示適當的提示
}
```

---

## 測試建議

1. 使用 Supabase CLI 在本地測試：
```bash
supabase start
supabase migration up
```

2. 在 Supabase Studio 中測試 RPC 函數

3. 使用不同的使用者帳號測試權限控制

4. 測試 Realtime 訂閱是否正常運作

---

## 後續擴展建議

1. **訊息類型擴展**: 支援圖片、檔案等多媒體訊息
2. **訊息刪除**: 允許使用者刪除或撤回訊息
3. **對話封存**: 允許使用者封存不活躍的對話
4. **訊息搜尋**: 在對話中搜尋特定訊息
5. **推送通知**: 整合推送通知服務
6. **訊息模板**: 提供快速回覆模板
7. **舉報功能**: 允許使用者舉報不當訊息
