# Messaging System v2 API 參考文件

## 📚 目錄

- [建立或取得對話](#建立或取得對話)
- [發送訊息](#發送訊息)
- [查詢對話列表](#查詢對話列表)
- [查詢對話訊息](#查詢對話訊息)
- [標記訊息為已讀](#標記訊息為已讀)
- [查詢對話中的商品](#查詢對話中的商品)
- [歸檔對話](#歸檔對話)

---

## 建立或取得對話

建立新對話或取得兩個用戶之間已存在的對話。

### 函數名稱
```sql
create_or_get_conversation_v2(p_other_user_id, p_initial_item_id)
```

### 參數

| 參數名稱 | 類型 | 必填 | 說明 |
|---------|------|------|------|
| `p_other_user_id` | UUID | ✅ | 對方用戶 ID |
| `p_initial_item_id` | BIGINT | ❌ | 初始商品 ID (可選) |

### 回傳值

| 欄位名稱 | 類型 | 說明 |
|---------|------|------|
| `conversation_id` | BIGINT | 對話 ID |
| `participant_1_id` | UUID | 參與者 1 (UUID 較小者) |
| `participant_2_id` | UUID | 參與者 2 (UUID 較大者) |
| `initial_item_id` | BIGINT | 初始商品 ID |
| `is_new` | BOOLEAN | 是否為新建立的對話 |
| `current_user_is_participant_1` | BOOLEAN | 當前用戶是否為參與者 1 |

### TypeScript 範例

```typescript
const { data, error } = await supabase.rpc('create_or_get_conversation_v2', {
  p_other_user_id: 'user-uuid-here',
  p_initial_item_id: 123
});

// data[0] = {
//   conversation_id: 456,
//   participant_1_id: 'uuid-1',
//   participant_2_id: 'uuid-2',
//   initial_item_id: 123,
//   is_new: true,
//   current_user_is_participant_1: false
// }
```

### 注意事項

- 🔒 需要認證
- 🚫 不能與自己建立對話
- ♻️ 兩個用戶之間只會有一個對話 (去角色化設計)
- 📦 可以不提供商品 ID (純聊天對話)

---

## 發送訊息

在指定對話中發送訊息。

### 函數名稱
```sql
send_message_v2(p_conversation_id, p_content, p_message_type, p_related_item_id)
```

### 參數

| 參數名稱 | 類型 | 必填 | 預設值 | 說明 |
|---------|------|------|--------|------|
| `p_conversation_id` | BIGINT | ✅ | - | 對話 ID |
| `p_content` | TEXT | ✅ | - | 訊息內容 |
| `p_message_type` | VARCHAR(20) | ❌ | 'text' | 訊息類型 |
| `p_related_item_id` | BIGINT | ❌ | NULL | 關聯的商品 ID |

### 訊息類型

| 類型 | 說明 |
|------|------|
| `text` | 純文字訊息 |
| `image` | 圖片訊息 |
| `system` | 系統訊息 |
| `item_reference` | 商品引用訊息 |

### 回傳值

| 欄位名稱 | 類型 | 說明 |
|---------|------|------|
| `message_id` | BIGINT | 訊息 ID |
| `conversation_id` | BIGINT | 對話 ID |
| `sender_id` | UUID | 發送者 ID |
| `content` | TEXT | 訊息內容 |
| `message_type` | VARCHAR | 訊息類型 |
| `related_item_id` | BIGINT | 關聯商品 ID |
| `created_at` | TIMESTAMPTZ | 建立時間 |

### TypeScript 範例

```typescript
// 發送純文字訊息
const { data, error } = await supabase.rpc('send_message_v2', {
  p_conversation_id: 456,
  p_content: 'Hello! 這個商品還有嗎?',
  p_message_type: 'text',
  p_related_item_id: null
});

// 發送帶商品引用的訊息
const { data, error } = await supabase.rpc('send_message_v2', {
  p_conversation_id: 456,
  p_content: '我想詢問這個商品的細節',
  p_message_type: 'item_reference',
  p_related_item_id: 789
});
```

### 自動處理

- ✅ 自動標記發送者為已讀
- ✅ 自動更新對話的 `last_message_at`
- ✅ 如有商品引用,自動加入到 `conversation_items_v2`

---

## 查詢對話列表

取得當前用戶的所有對話列表。

### 函數名稱
```sql
get_user_conversations_v2(p_page, p_size, p_include_archived)
```

### 參數

| 參數名稱 | 類型 | 必填 | 預設值 | 說明 |
|---------|------|------|--------|------|
| `p_page` | INT | ❌ | 1 | 頁碼 (從 1 開始) |
| `p_size` | INT | ❌ | 20 | 每頁筆數 |
| `p_include_archived` | BOOLEAN | ❌ | false | 是否包含已歸檔對話 |

### 回傳值

| 欄位名稱 | 類型 | 說明 |
|---------|------|------|
| `conversation_id` | BIGINT | 對話 ID |
| `other_user_id` | UUID | 對方用戶 ID |
| `other_user_name` | VARCHAR | 對方用戶名稱 |
| `other_user_avatar` | TEXT | 對方用戶頭像 URL |
| `initial_item_id` | BIGINT | 初始商品 ID |
| `initial_item_title` | VARCHAR | 初始商品標題 |
| `last_message_content` | TEXT | 最後一則訊息內容 |
| `last_message_at` | TIMESTAMPTZ | 最後訊息時間 |
| `unread_count` | BIGINT | 未讀訊息數量 |
| `is_archived` | BOOLEAN | 是否已歸檔 |
| `created_at` | TIMESTAMPTZ | 對話建立時間 |

### TypeScript 範例

```typescript
// 取得第一頁 (20 筆)
const { data, error } = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 20,
  p_include_archived: false
});

// data = [
//   {
//     conversation_id: 456,
//     other_user_id: 'uuid-here',
//     other_user_name: '張三',
//     other_user_avatar: 'https://...',
//     initial_item_id: 123,
//     initial_item_title: 'iPhone 15 Pro',
//     last_message_content: '請問還有嗎?',
//     last_message_at: '2024-01-15T10:30:00Z',
//     unread_count: 3,
//     is_archived: false,
//     created_at: '2024-01-10T08:00:00Z'
//   },
//   // ...
// ]
```

### 排序規則

- 📅 按 `last_message_at` 降序排列 (最新訊息在前)
- 📌 無訊息的對話按 `created_at` 排序

---

## 查詢對話訊息

取得指定對話的訊息列表。

### 函數名稱
```sql
get_conversation_messages_v2(p_conversation_id, p_page, p_size, p_include_deleted)
```

### 參數

| 參數名稱 | 類型 | 必填 | 預設值 | 說明 |
|---------|------|------|--------|------|
| `p_conversation_id` | BIGINT | ✅ | - | 對話 ID |
| `p_page` | INT | ❌ | 1 | 頁碼 |
| `p_size` | INT | ❌ | 50 | 每頁筆數 |
| `p_include_deleted` | BOOLEAN | ❌ | false | 是否包含已刪除訊息 |

### 回傳值

| 欄位名稱 | 類型 | 說明 |
|---------|------|------|
| `message_id` | BIGINT | 訊息 ID |
| `sender_id` | UUID | 發送者 ID |
| `sender_name` | VARCHAR | 發送者名稱 |
| `sender_avatar` | TEXT | 發送者頭像 URL |
| `content` | TEXT | 訊息內容 |
| `message_type` | VARCHAR | 訊息類型 |
| `related_item_id` | BIGINT | 關聯商品 ID |
| `related_item_title` | VARCHAR | 關聯商品標題 |
| `is_deleted` | BOOLEAN | 是否已刪除 |
| `is_mine` | BOOLEAN | 是否為當前用戶發送 |
| `is_read` | BOOLEAN | 當前用戶是否已讀 |
| `created_at` | TIMESTAMPTZ | 建立時間 |

### TypeScript 範例

```typescript
const { data, error } = await supabase.rpc('get_conversation_messages_v2', {
  p_conversation_id: 456,
  p_page: 1,
  p_size: 50,
  p_include_deleted: false
});

// data = [
//   {
//     message_id: 789,
//     sender_id: 'uuid-here',
//     sender_name: '張三',
//     sender_avatar: 'https://...',
//     content: '請問這個商品還有嗎?',
//     message_type: 'text',
//     related_item_id: null,
//     related_item_title: null,
//     is_deleted: false,
//     is_mine: false,
//     is_read: true,
//     created_at: '2024-01-15T10:30:00Z'
//   },
//   // ...
// ]
```

### 排序規則

- 📅 按 `created_at` 降序排列 (最新訊息在後面)
- 💡 建議前端反轉陣列顯示

---

## 標記訊息為已讀

標記對話中的訊息為已讀狀態。

### 函數名稱
```sql
mark_messages_as_read_v2(p_conversation_id, p_up_to_message_id)
```

### 參數

| 參數名稱 | 類型 | 必填 | 預設值 | 說明 |
|---------|------|------|--------|------|
| `p_conversation_id` | BIGINT | ✅ | - | 對話 ID |
| `p_up_to_message_id` | BIGINT | ❌ | NULL | 標記到哪個訊息 ID (不提供則全部標記) |

### 回傳值

| 類型 | 說明 |
|------|------|
| BIGINT | 更新的訊息數量 |

### TypeScript 範例

```typescript
// 標記所有未讀訊息為已讀
const { data, error } = await supabase.rpc('mark_messages_as_read_v2', {
  p_conversation_id: 456,
  p_up_to_message_id: null
});

// data = 5 (更新了 5 則訊息)

// 標記到特定訊息 ID
const { data, error } = await supabase.rpc('mark_messages_as_read_v2', {
  p_conversation_id: 456,
  p_up_to_message_id: 789
});
```

### 自動處理

- ✅ 只標記對方發送的訊息 (自己的訊息已經是已讀)
- ✅ 自動判斷當前用戶是參與者 1 還是參與者 2
- ✅ 記錄已讀時間

---

## 查詢對話中的商品

取得對話中討論過的所有商品。

### 函數名稱
```sql
get_conversation_items_v2(p_conversation_id)
```

### 參數

| 參數名稱 | 類型 | 必填 | 說明 |
|---------|------|------|------|
| `p_conversation_id` | BIGINT | ✅ | 對話 ID |

### 回傳值

| 欄位名稱 | 類型 | 說明 |
|---------|------|------|
| `item_id` | BIGINT | 商品 ID |
| `item_title` | VARCHAR | 商品標題 |
| `item_price` | NUMERIC | 商品價格 |
| `item_image_url` | TEXT | 商品圖片 URL |
| `item_status` | VARCHAR | 商品狀態 |
| `added_by_user_id` | UUID | 加入者 ID |
| `added_by_user_name` | VARCHAR | 加入者名稱 |
| `added_at` | TIMESTAMPTZ | 加入時間 |
| `message_count` | BIGINT | 討論此商品的訊息數量 |

### TypeScript 範例

```typescript
const { data, error } = await supabase.rpc('get_conversation_items_v2', {
  p_conversation_id: 456
});

// data = [
//   {
//     item_id: 123,
//     item_title: 'iPhone 15 Pro',
//     item_price: 35000,
//     item_image_url: 'https://...',
//     item_status: 'available',
//     added_by_user_id: 'uuid-here',
//     added_by_user_name: '張三',
//     added_at: '2024-01-10T08:00:00Z',
//     message_count: 15
//   },
//   {
//     item_id: 456,
//     item_title: 'AirPods Pro',
//     item_price: 7000,
//     item_image_url: 'https://...',
//     item_status: 'available',
//     added_by_user_id: 'uuid-here',
//     added_by_user_name: '李四',
//     added_at: '2024-01-12T10:00:00Z',
//     message_count: 8
//   }
// ]
```

### 使用場景

- 📦 在對話頂部顯示所有討論的商品
- 🔍 快速切換討論的商品
- 📊 追蹤商品討論熱度

---

## 歸檔對話

歸檔或取消歸檔對話 (不會刪除資料)。

### 函數名稱
```sql
toggle_conversation_archive_v2(p_conversation_id, p_archived)
```

### 參數

| 參數名稱 | 類型 | 必填 | 說明 |
|---------|------|------|------|
| `p_conversation_id` | BIGINT | ✅ | 對話 ID |
| `p_archived` | BOOLEAN | ✅ | true=歸檔, false=取消歸檔 |

### 回傳值

| 類型 | 說明 |
|------|------|
| BOOLEAN | 操作是否成功 |

### TypeScript 範例

```typescript
// 歸檔對話
const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
  p_conversation_id: 456,
  p_archived: true
});

// 取消歸檔
const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
  p_conversation_id: 456,
  p_archived: false
});
```

### 注意事項

- 📁 歸檔是針對個別用戶的 (A 歸檔不影響 B)
- 🔄 可以隨時取消歸檔
- 👁️ 預設查詢對話列表不包含已歸檔對話

---

## 🔔 Realtime 訂閱

### 訂閱新訊息

```typescript
const subscription = supabase
  .channel(`conversation_v2_${conversationId}`)
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'conversation_messages_v2',
      filter: `conversation_id=eq.${conversationId}`,
    },
    (payload) => {
      console.log('New message:', payload.new);
      // 更新 UI
    }
  )
  .subscribe();

// 記得取消訂閱
subscription.unsubscribe();
```

### 訂閱已讀狀態更新

```typescript
const subscription = supabase
  .channel(`conversation_v2_${conversationId}_read_status`)
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversation_messages_v2',
      filter: `conversation_id=eq.${conversationId}`,
    },
    (payload) => {
      console.log('Read status updated:', payload.new);
      // 更新已讀狀態
    }
  )
  .subscribe();
```

---

## ⚠️ 錯誤處理

### 常見錯誤

| 錯誤訊息 | 原因 | 解決方案 |
|---------|------|---------|
| `Not authenticated` | 未登入 | 確保用戶已通過 Supabase Auth 認證 |
| `Conversation not found` | 對話不存在 | 檢查 conversation_id 是否正確 |
| `Not a participant of this conversation` | 無權訪問 | 用戶不是對話參與者 |
| `Cannot create conversation with yourself` | 與自己對話 | 檢查 other_user_id 不等於當前用戶 |

### TypeScript 錯誤處理範例

```typescript
try {
  const { data, error } = await supabase.rpc('send_message_v2', {
    p_conversation_id: conversationId,
    p_content: content,
  });

  if (error) throw error;
  
  // 成功處理
  return data;
  
} catch (error) {
  if (error.message.includes('Not a participant')) {
    // 處理權限錯誤
    showError('您不是此對話的參與者');
  } else if (error.message.includes('Not authenticated')) {
    // 處理認證錯誤
    redirectToLogin();
  } else {
    // 其他錯誤
    showError('操作失敗,請稍後再試');
  }
}
```

---

## 📊 效能建議

### 分頁查詢

```typescript
// ✅ 推薦: 使用分頁
const conversations = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 20
});

// ❌ 避免: 一次載入過多資料
const conversations = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 1000  // 太多!
});
```

### 使用 Realtime

```typescript
// ✅ 推薦: 使用 Realtime 訂閱
const subscription = MessagingV2.subscribeToMessages(
  conversationId,
  handleNewMessage
);

// ❌ 避免: 輪詢
setInterval(async () => {
  const messages = await MessagingV2.getMessages(conversationId);
}, 1000);  // 不要這樣做!
```

---

## 🔗 相關文件

- [完整設計文件](./角色互換改造方案_v2平滑過渡.md)
- [實施指南](./IMPLEMENTATION_GUIDE_V2.md)
- [遷移 SQL 腳本](./migrations/messaging_v2_complete.sql)

---

**版本**: 2.0.0  
**最後更新**: 2024-01-XX