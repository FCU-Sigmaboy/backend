# Messaging System v2 - RPC Functions 使用說明

## 📋 目錄

- [概述](#概述)
- [前置需求](#前置需求)
- [安裝步驟](#安裝步驟)
- [函數清單](#函數清單)
- [使用範例](#使用範例)
- [錯誤處理](#錯誤處理)
- [效能優化](#效能優化)

---

## 概述

`messaging_v2_rpc_functions.sql` 包含了 Messaging System v2 的所有 RPC (Remote Procedure Call) 函數實作。

**主要特性:**
- ✅ 去角色化設計 (無買家/賣家區分)
- ✅ 支援多商品對話
- ✅ 雙向已讀狀態追蹤
- ✅ 訊息軟刪除
- ✅ 對話歸檔功能
- ✅ 完整的權限驗證
- ✅ 所有欄位完全限定 (避免 42702 錯誤)

---

## 前置需求

在執行 RPC 函數腳本之前,必須先建立資料表結構:

```bash
# 1. 先執行主要 migration (建立資料表、觸發器、RLS)
psql -f messaging_v2_complete.sql

# 2. 再執行 RPC 函數 (本檔案)
psql -f messaging_v2_rpc_functions.sql
```

**或使用 Supabase CLI:**

```bash
supabase db push
```

---

## 安裝步驟

### 方法 1: 直接在 Supabase SQL Editor 執行

1. 登入 Supabase Dashboard
2. 進入 SQL Editor
3. 複製 `messaging_v2_rpc_functions.sql` 內容
4. 執行腳本

### 方法 2: 使用 Supabase CLI

```bash
# 將檔案放在 supabase/migrations/ 目錄下
cp messaging_v2_rpc_functions.sql supabase/migrations/20240120000002_messaging_v2_rpc_functions.sql

# 執行 migration
supabase db push
```

### 方法 3: 使用 psql

```bash
psql -h db.your-project.supabase.co \
     -U postgres \
     -d postgres \
     -f messaging_v2_rpc_functions.sql
```

---

## 函數清單

### 🔧 輔助函數

| 函數名稱 | 說明 | 權限 |
|---------|------|------|
| `normalize_participants_v2()` | 標準化參與者順序 | authenticated |

### 💬 對話管理函數

| 函數名稱 | 說明 | 權限 |
|---------|------|------|
| `create_or_get_conversation_v2()` | 建立或取得對話 | authenticated |
| `get_user_conversations_v2()` | 查詢用戶對話列表 | authenticated |
| `toggle_conversation_archive_v2()` | 歸檔/取消歸檔對話 | authenticated |

### 📨 訊息管理函數

| 函數名稱 | 說明 | 權限 |
|---------|------|------|
| `send_message_v2()` | 發送訊息 | authenticated |
| `get_conversation_messages_v2()` | 查詢對話訊息 | authenticated |
| `mark_messages_as_read_v2()` | 標記訊息為已讀 | authenticated |

### 🛍️ 商品管理函數

| 函數名稱 | 說明 | 權限 |
|---------|------|------|
| `get_conversation_items_v2()` | 查詢對話中的商品 | authenticated |

---

## 使用範例

### 1. 建立或取得對話

```typescript
const { data, error } = await supabase.rpc('create_or_get_conversation_v2', {
  p_other_user_id: '550e8400-e29b-41d4-a716-446655440000',
  p_initial_item_id: 12345 // 可選
});

if (error) throw error;

const conversation = data[0];
console.log('Conversation ID:', conversation.conversation_id);
console.log('Is new:', conversation.is_new);
```

**回傳值:**
```json
[{
  "conversation_id": 1,
  "participant_1_id": "...",
  "participant_2_id": "...",
  "initial_item_id": 12345,
  "is_new": true,
  "current_user_is_participant_1": true
}]
```

### 2. 發送訊息

```typescript
const { data, error } = await supabase.rpc('send_message_v2', {
  p_conversation_id: 1,
  p_content: 'Hello! Is this item still available?',
  p_message_type: 'text', // 預設值
  p_related_item_id: 12345 // 可選,引用商品
});

if (error) throw error;

const message = data[0];
console.log('Message ID:', message.message_id);
```

**回傳值:**
```json
[{
  "message_id": 100,
  "conversation_id": 1,
  "sender_id": "...",
  "content": "Hello! Is this item still available?",
  "message_type": "text",
  "related_item_id": 12345,
  "created_at": "2024-01-20T10:30:00Z"
}]
```

### 3. 查詢對話列表

```typescript
const { data, error } = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 20,
  p_include_archived: false
});

if (error) throw error;

data.forEach(conv => {
  console.log(`${conv.other_user_name}: ${conv.last_message_content}`);
  console.log(`未讀數: ${conv.unread_count}`);
});
```

**回傳值:**
```json
[{
  "conversation_id": 1,
  "other_user_id": "...",
  "other_user_name": "張三",
  "other_user_avatar": "https://...",
  "initial_item_id": 12345,
  "initial_item_title": "二手 MacBook Pro",
  "last_message_content": "好的,謝謝!",
  "last_message_at": "2024-01-20T15:30:00Z",
  "unread_count": 3,
  "is_archived": false,
  "created_at": "2024-01-15T10:00:00Z"
}]
```

### 4. 查詢對話訊息

```typescript
const { data, error } = await supabase.rpc('get_conversation_messages_v2', {
  p_conversation_id: 1,
  p_page: 1,
  p_size: 50,
  p_include_deleted: false
});

if (error) throw error;

data.forEach(msg => {
  console.log(`${msg.sender_name}: ${msg.content}`);
  console.log(`已讀: ${msg.is_read}`);
});
```

### 5. 標記訊息為已讀

```typescript
// 標記所有未讀訊息
const { data: count1, error } = await supabase.rpc('mark_messages_as_read_v2', {
  p_conversation_id: 1
});

// 或標記到特定訊息為止
const { data: count2, error } = await supabase.rpc('mark_messages_as_read_v2', {
  p_conversation_id: 1,
  p_up_to_message_id: 100
});

console.log('已標記訊息數:', count1 || count2);
```

### 6. 查詢對話中的商品

```typescript
const { data, error } = await supabase.rpc('get_conversation_items_v2', {
  p_conversation_id: 1
});

if (error) throw error;

data.forEach(item => {
  console.log(`${item.item_title}: $${item.item_price}`);
  console.log(`相關訊息數: ${item.message_count}`);
});
```

### 7. 歸檔對話

```typescript
// 歸檔
const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
  p_conversation_id: 1,
  p_archived: true
});

// 取消歸檔
const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
  p_conversation_id: 1,
  p_archived: false
});
```

---

## 錯誤處理

### 常見錯誤碼

| 錯誤訊息 | 原因 | 解決方案 |
|---------|------|---------|
| `Not authenticated` | 未登入 | 確保使用者已通過 Supabase Auth 認證 |
| `Conversation not found` | 對話不存在 | 檢查 conversation_id 是否正確 |
| `Not a participant of this conversation` | 無權限存取此對話 | 僅對話參與者可存取 |
| `Cannot create conversation with yourself` | 嘗試與自己建立對話 | 確保 p_other_user_id 不是當前用戶 |

### TypeScript 錯誤處理範例

```typescript
try {
  const { data, error } = await supabase.rpc('create_or_get_conversation_v2', {
    p_other_user_id: otherUserId,
    p_initial_item_id: itemId
  });

  if (error) {
    switch (error.message) {
      case 'Not authenticated':
        // 導向登入頁
        router.push('/login');
        break;
      case 'Cannot create conversation with yourself':
        alert('不能與自己對話');
        break;
      default:
        console.error('Unexpected error:', error);
    }
    return;
  }

  const conversation = data[0];
  // 處理成功邏輯...
} catch (err) {
  console.error('Failed to create conversation:', err);
}
```

---

## 效能優化

### 1. 分頁查詢

所有列表查詢都支援分頁,避免一次載入過多資料:

```typescript
// ✅ 好的做法
const { data } = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 20
});

// ❌ 不好的做法 (載入過多資料)
const { data } = await supabase.rpc('get_user_conversations_v2', {
  p_page: 1,
  p_size: 1000
});
```

### 2. 索引使用

所有查詢都已優化使用資料庫索引:

- `conversations_v2`: `participant_1_id`, `participant_2_id`, `last_message_at`
- `conversation_messages_v2`: `conversation_id + created_at`
- `conversation_items_v2`: `conversation_id`, `item_id`

### 3. 快取策略

建議在前端實作快取:

```typescript
// 使用 SWR 或 React Query
import useSWR from 'swr';

const { data, error, mutate } = useSWR(
  ['conversations', page],
  () => supabase.rpc('get_user_conversations_v2', { p_page: page }),
  {
    revalidateOnFocus: false,
    dedupingInterval: 60000 // 1 分鐘內不重複請求
  }
);
```

### 4. Realtime 訂閱

結合 Supabase Realtime 實現即時更新:

```typescript
// 訂閱新訊息
const channel = supabase
  .channel('conversation_messages')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'conversation_messages_v2',
      filter: `conversation_id=eq.${conversationId}`
    },
    (payload) => {
      console.log('New message:', payload.new);
      // 更新本地狀態
    }
  )
  .subscribe();
```

---

## 安全性注意事項

### ✅ 已實作的安全機制

1. **RLS (Row Level Security)**: 所有資料表都啟用 RLS
2. **權限驗證**: 所有函數都驗證 `auth.uid()`
3. **參與者檢查**: 確保只有對話參與者能存取資料
4. **完全限定欄位**: 避免 SQL 注入和欄位模糊問題

### 🔒 使用建議

```typescript
// ✅ 安全: 使用 Supabase Auth
const { data: { user } } = await supabase.auth.getUser();
if (!user) {
  router.push('/login');
  return;
}

// ❌ 不安全: 直接使用 localStorage 的 user_id
const userId = localStorage.getItem('user_id'); // 可被竄改
```

---

## 版本資訊

- **版本**: 2.0.0
- **最後更新**: 2024-01-20
- **相容性**: PostgreSQL 13+, Supabase

---

## 相關文件

- [messaging_v2_complete.sql](./messaging_v2_complete.sql) - 完整 migration (包含資料表、觸發器、RLS)
- [add_soft_delete_functions.sql](./add_soft_delete_functions.sql) - 軟刪除功能
- [fix_migration_function.sql](./fix_migration_function.sql) - v1 到 v2 遷移工具

---

## 問題回報

如遇到問題,請提供以下資訊:

1. 錯誤訊息完整內容
2. 使用的函數名稱和參數
3. PostgreSQL 版本
4. Supabase CLI 版本 (如適用)

---

**Made with ❤️ for FCU-Sigma Project**