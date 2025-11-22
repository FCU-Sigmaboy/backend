# 訊息傳遞功能 API 文件

> **📌 文件狀態**: ✅ 生產就緒 | **版本**: 1.2 | **更新日期**: 2025-11-08

---

## 🎯 快速導航

<table>
<tr>
<td width="50%">

### 🚀 新手入門
- [快速開始](#-快速開始) - 立即開始使用
- [函數快速指引表](#函數快速指引表) - 所有函數一覽
- [完整使用範例](#-完整使用流程範例) - 實際應用案例

</td>
<td width="50%">

### 📖 深入了解
- [API 函數列表](#-api-函數列表) - 詳細參數說明
- [Realtime 訂閱](#-realtime-即時訊息訂閱) - 即時訊息推送
- [常見問題](#-常見問題-faq) - 疑難排解

</td>
</tr>
<tr>
<td width="50%">

### 🔧 開發參考
- [錯誤處理](#️-錯誤處理) - 錯誤訊息對照
- [效能優化](#-效能優化建議) - 最佳實踐
- [安全性](#-安全性) - 權限與驗證

</td>
<td width="50%">

### 📦 其他資源
- [資料庫架構](#️-資料庫架構參考) - 資料表結構
- [測試建議](#-測試建議) - 單元與整合測試
- [版本歷史](#-版本歷史) - 更新記錄

</td>
</tr>
</table>

---

## 📖 概述

此文件說明基於 Supabase 的使用者訊息傳遞功能的 API 使用方式。本功能允許買家和賣家針對特定物品進行即時對話。

### ✨ 核心特性

- ✅ **即時通訊** - 使用 Supabase Realtime 實現即時訊息推送
- ✅ **併發安全** - UPSERT 機制防止重複對話建立
- ✅ **軟刪除支援** - 對話可刪除與恢復,不影響對方
- ✅ **批次查詢** - 優化效能,避免 N+1 問題
- ✅ **防重複請求** - 內建去抖動機制
- ✅ **完整權限控制** - RLS 確保資料安全

---

## 📚 目錄與快速跳轉

- [函數快速指引表](#函數快速指引表)
- [快速開始](#快速開始)
- [核心功能](#api-函數列表)
  - [發起聊天](#1-發起聊天-建立或取得對話)
  - [查詢對話](#2-批次查詢對話資訊)
  - [對話列表](#3-取得我的對話列表)
  - [訊息管理](#4-取得對話中的訊息)
- [Realtime 即時訊息](#realtime-即時訊息訂閱)
- [完整使用範例](#完整使用流程範例)
- [常見問題](#常見問題-faq)

---

## 函數快速指引表

### 🔥 核心功能 (必學)

| 函數名稱 | 功能說明 | 使用頻率 | 主要用途 | 跳轉連結 |
|---------|---------|---------|---------|---------|
| `startChatSafe(itemId)` | 發起聊天(防重複) | ⭐⭐⭐ | 防止快速點擊重複請求 | [詳細說明](#startchatsafeitemid) |
| `getMyConversations(options)` | 取得對話列表 | ⭐⭐⭐ | 顯示使用者的所有對話 | [詳細說明](#getmyconversationsoptions) |
| `getConversationMessages(id, options)` | 取得訊息列表 | ⭐⭐⭐ | 顯示對話中的所有訊息 | [詳細說明](#getconversationmessagesconversationid-options) |
| `sendMessage(id, content)` | 發送訊息 | ⭐⭐⭐ | 在對話中發送新訊息 | [詳細說明](#sendmessageconversationid-content) |
| `markMessagesAsRead(id)` | 標記已讀 | ⭐⭐⭐ | 標記對話中的訊息為已讀 | [詳細說明](#markmessagesasreadconversationid) |

### 📊 進階功能

| 函數名稱 | 功能說明 | 使用頻率 | 主要用途 | 跳轉連結 |
|---------|---------|---------|---------|---------|
| `startChat(itemId)` | 發起聊天 | ⭐⭐ | 針對物品建立或取得對話(無防重複) | [詳細說明](#startchatitemid) |
| `getConversationsByIds(ids)` | 批次查詢對話 | ⭐⭐ | 一次查詢多個對話資訊(效能優化) | [詳細說明](#getconversationsbyidsconversationids) |
| `getUnreadMessageCount()` | 取得未讀數 | ⭐⭐ | 顯示總未讀訊息數量(徽章) | [詳細說明](#getunreadmessagecount) |

### 🗑️ 管理功能

| 函數名稱 | 功能說明 | 使用頻率 | 主要用途 | 跳轉連結 |
|---------|---------|---------|---------|---------|
| `deleteConversation(id)` | 刪除對話 | ⭐ | 單方面隱藏對話 | [詳細說明](#deleteconversationconversationid) |
| `restoreConversation(id)` | 恢復對話 | ⭐ | 恢復已刪除的對話 | [詳細說明](#restoreconversationconversationid) |
| `deleteMessage(id)` | 刪除訊息 | ⭐ | 刪除自己發送的訊息 | [詳細說明](#deletemessagemessageid) |

### 📖 使用說明

- **使用頻率圖例**: ⭐⭐⭐ 高頻率(必學) | ⭐⭐ 中頻率(進階) | ⭐ 低頻率(按需使用)
- **點擊「跳轉連結」** 可快速查看詳細文件
- **新手建議學習順序**: 
  1. `startChatSafe` - 發起聊天
  2. `sendMessage` - 發送訊息
  3. `getConversationMessages` - 查看訊息
  4. [Realtime 訂閱](#-realtime-即時訊息訂閱) - 即時更新
- **常用功能組合**: 
  - 💬 **發起對話**: `startChatSafe` + `sendMessage`
  - 📱 **聊天頁面**: `getConversationMessages` + `sendMessage` + `markMessagesAsRead`
  - 📋 **對話列表**: `getMyConversations` + `getUnreadMessageCount`
  - 🗑️ **對話管理**: `deleteConversation` + `restoreConversation`

### 🔄 版本 1.2 主要變更

- ✨ 加強 `startChat` 的錯誤處理
- ✨ 新增防重複請求機制 (`startChatSafe`)
- ✨ 新增批次查詢對話功能 (`getConversationsByIds`)
- ✨ 新增軟刪除功能支援 (`deleteConversation`, `restoreConversation`, `deleteMessage`)
- ✨ `getMyConversations` 支援 `role` 和 `includeDeleted` 參數

---

## 🚀 快速開始

### 引入 API 模組

```javascript
import {
  startChat,
  startChatSafe,
  getConversationsByIds,
  getMyConversations,
  getConversationMessages,
  sendMessage,
  markMessagesAsRead,
  getUnreadMessageCount,
  deleteConversation,
  restoreConversation,
  deleteMessage
} from './conversationAPI';
```

---

---

## 📡 API 函數列表

> **💡 章節摘要**: 本章節詳細說明所有 11 個 API 函數的參數、返回值、錯誤處理和使用範例。建議新手依序學習核心功能,再根據需求使用進階功能。

### 1. 發起聊天 (建立或取得對話)

> **函數簽名**: `startChat(itemId: number): Promise<Conversation>`

#### `startChat(itemId)`

**功能**: 針對特定物品發起聊天,如果對話已存在則返回現有對話。

**參數**:
- `itemId` (number, 必填) - 物品 ID

**返回值**:
```javascript
{
  conversation_id: 52,
  item_id: 101,
  buyer_id: "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  seller_id: "b2c3d4e5-xxxx-xxxx-xxxx-user002",
  created_at: "2025-10-19T10:00:00+00:00",
  updated_at: "2025-10-19T10:00:00+00:00"
}
```

**錯誤訊息**:
- `"使用者未登入,無法發起聊天"` - 未登入
- `"無效的物品 ID"` - itemId 無效或 ≤ 0
- `"此物品不存在或已下架"` - 物品不存在
- `"無法與自己的物品發起聊天"` - 嘗試對自己的物品發起聊天

**使用範例**:
```javascript
try {
  const conversation = await startChat(101);
  console.log('對話 ID:', conversation.conversation_id);
} catch (error) {
  console.error('發起聊天失敗:', error.message);
}
```

**特性**:
- ✅ 使用 UPSERT 機制,併發安全
- ✅ 自動更新 `updated_at` 時間戳記
- ✅ 資料庫層級防止重複對話建立

---

#### `startChatSafe(itemId)`

**功能**: 與 `startChat` 相同,但包含防重複請求保護機制。

> 💡 **推薦使用**: 在按鈕點擊事件中優先使用此函數

**使用場景**:
當使用者可能快速點擊多次「聯繫賣家」按鈕時使用此函數,可避免產生重複請求。

**使用範例**:
```javascript
// 推薦在按鈕點擊事件中使用
async function handleContactSeller(itemId) {
  try {
    const conversation = await startChatSafe(itemId);
    // 導航到聊天頁面
    navigateTo(`/chat/${conversation.conversation_id}`);
  } catch (error) {
    showError(error.message);
  }
}
```

---

---

### 2. 批次查詢對話資訊

> **函數簽名**: `getConversationsByIds(conversationIds: number[]): Promise<Conversation[]>`

#### `getConversationsByIds(conversationIds)`

**功能**: 批次查詢多個對話的詳細資訊,避免 N+1 查詢問題。

> ⚡ **效能優化**: 使用此函數而非多次單獨查詢

**參數**:
- `conversationIds` (number[], 必填) - 對話 ID 陣列

**返回值**:
```javascript
[
  {
    id: 51,
    item: {
      id: 101,
      title: "（全新）IKEA 檯燈",
      cover_image_url: "https://.../item101_cover.jpg"
    },
    buyer_id: "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    seller_id: "b2c3d4e5-xxxx-xxxx-xxxx-user002",
    created_at: "2025-10-19T09:00:00+00:00",
    updated_at: "2025-10-19T10:05:00+00:00"
  }
]
```

**使用範例**:
```javascript
try {
  const conversations = await getConversationsByIds([51, 52, 53]);
  console.log('查詢到的對話:', conversations);
} catch (error) {
  console.error('批次查詢失敗:', error.message);
}
```

**注意事項**:
- 若使用者未登入,返回 `null`
- 若傳入空陣列,返回 `[]`
- 只能查詢使用者參與的對話

---

---

### 3. 取得我的對話列表

> **函數簽名**: `getMyConversations(options?: ConversationListOptions): Promise<Conversation[] | null>`

#### `getMyConversations(options)`

**功能**: 取得當前使用者的所有對話列表,包含最後一則訊息和未讀訊息數量。

**參數**:
```javascript
{
  page: 1,              // (選填, 預設: 1) 頁碼
  size: 20,             // (選填, 預設: 20) 每頁筆數 (最大 100)
  role: "all",          // (選填, 預設: "all") 篩選角色: "buyer" | "seller" | "all"
  includeDeleted: false // (選填, 預設: false) 是否包含已刪除的對話
}
```

**返回值**:
```javascript
[
  {
    id: 51,
    item: {
      id: 101,
      title: "（全新）IKEA 檯燈",
      cover_image_url: "https://.../item101_cover.jpg"
    },
    other_user: {
      id: "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      nickname: "Amber",
      profile_picture_url: "https://.../amber.jpg"
    },
    last_message: "有興趣交換嗎？",
    last_message_time: "2025-10-19T10:05:00+00:00",
    unread_count: 2,
    created_at: "2025-10-19T09:00:00+00:00",
    updated_at: "2025-10-19T10:05:00+00:00",
    is_deleted: false
  },
  {
    id: 48,
    item: {
      id: 205,
      title: "二手登山背包",
      cover_image_url: "https://.../backpack.png"
    },
    other_user: {
      id: "c3d4e5f6-xxxx-xxxx-xxxx-user003",
      nickname: "Mike",
      profile_picture_url: null
    },
    last_message: "好的謝謝",
    last_message_time: "2025-10-18T15:30:00+00:00",
    unread_count: 0,
    created_at: "2025-10-18T14:00:00+00:00",
    updated_at: "2025-10-18T15:30:00+00:00",
    is_deleted: false
  }
]
```

**使用範例**:
```javascript
// 基本用法 - 取得所有對話
const conversations = await getMyConversations();

// 分頁查詢
const page2 = await getMyConversations({ page: 2, size: 10 });

// 只查詢作為買家的對話
const buyerConversations = await getMyConversations({ role: 'buyer' });

// 只查詢作為賣家的對話
const sellerConversations = await getMyConversations({ role: 'seller' });

// 包含已刪除的對話
const allIncludingDeleted = await getMyConversations({ includeDeleted: true });
```

**注意事項**:
- `last_message` 和 `last_message_time` 在新建立的對話中可能為 `null`
- `unread_count` 會自動解析為數字,若無未讀訊息則為 `0`
- 若使用者未登入,返回 `null`

---

---

### 4. 取得對話中的訊息

> **函數簽名**: `getConversationMessages(conversationId: number, options?: MessageListOptions): Promise<Message[] | null>`

#### `getConversationMessages(conversationId, options)`

**功能**: 取得指定對話中的所有訊息,包含發送者資訊。

**參數**:
```javascript
conversationId  // (number, 必填) 對話 ID

options = {
  page: 1,      // (選填, 預設: 1) 頁碼
  size: 50      // (選填, 預設: 50) 每頁筆數 (最大 100)
}
```

**返回值**:
```javascript
[
  {
    id: 1001,
    sender: {
      id: "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      nickname: "小明",
      profile_picture_url: "https://.../ming.jpg"
    },
    content: "您好,請問這個檯燈還在嗎?",
    is_read: true,
    sent_at: "2025-10-19T10:00:00+00:00"
  },
  {
    id: 1002,
    sender: {
      id: "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      nickname: "Amber",
      profile_picture_url: "https://.../amber.jpg"
    },
    content: "還在喔!",
    is_read: true,
    sent_at: "2025-10-19T10:01:00+00:00"
  },
  {
    id: 1003,
    sender: {
      id: "b2c3d4e5-xxxx-xxxx-xxxx-user002",
      nickname: "Amber",
      profile_picture_url: "https://.../amber.jpg"
    },
    content: "有興趣交換嗎?",
    is_read: false,
    sent_at: "2025-10-19T10:05:00+00:00"
  }
]
```

**使用範例**:
```javascript
try {
  const messages = await getConversationMessages(51);
  console.log('訊息列表:', messages);
  
  // 分頁載入更多訊息
  const olderMessages = await getConversationMessages(51, { page: 2 });
} catch (error) {
  console.error('取得訊息失敗:', error.message);
}
```

**注意事項**:
- 若使用者未登入或無權限,返回 `null`
- 只能查看自己參與的對話中的訊息
- RLS 會自動驗證權限

---

---

### 5. 發送訊息

> **函數簽名**: `sendMessage(conversationId: number, content: string): Promise<Message>`

#### `sendMessage(conversationId, content)`

**功能**: 在指定對話中發送新訊息。

**參數**:
- `conversationId` (number, 必填) - 對話 ID
- `content` (string, 必填) - 訊息內容

**返回值**:
```javascript
{
  id: 1004,
  sender_id: "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  content: "好的,我們約時間交換吧!",
  is_read: false,
  sent_at: "2025-10-19T10:10:00+00:00"
}
```

**錯誤訊息**:
- `"使用者未登入,無法發送訊息"` - 未登入
- `"訊息內容不能為空"` - 內容為空或僅包含空白

**使用範例**:
```javascript
try {
  const newMessage = await sendMessage(51, '你好,這個物品還有嗎?');
  console.log('訊息已發送:', newMessage);
} catch (error) {
  console.error('發送失敗:', error.message);
}
```

**特性**:
- ✅ 自動去除前後空白
- ✅ 發送後會觸發資料庫 Trigger 更新對話的 `updated_at`
- ✅ 新訊息 `is_read` 預設為 `false`

---

---

### 6. 標記訊息為已讀

> **函數簽名**: `markMessagesAsRead(conversationId: number): Promise<number>`

#### `markMessagesAsRead(conversationId)`

**功能**: 將指定對話中所有未讀訊息標記為已讀 (不包含自己發送的訊息)。

**參數**:
- `conversationId` (number, 必填) - 對話 ID

**返回值**:
```javascript
5  // 表示有 5 則訊息被標記為已讀
```

**使用範例**:
```javascript
try {
  const updatedCount = await markMessagesAsRead(51);
  console.log(`已標記 ${updatedCount} 則訊息為已讀`);
} catch (error) {
  console.error('標記失敗:', error.message);
}
```

**最佳實踐**:
```javascript
// 當使用者開啟對話頁面時
useEffect(() => {
  if (conversationId) {
    markMessagesAsRead(conversationId);
  }
}, [conversationId]);
```

---

---

### 7. 取得未讀訊息總數

> **函數簽名**: `getUnreadMessageCount(): Promise<number | null>`

#### `getUnreadMessageCount()`

**功能**: 取得當前使用者所有對話的未讀訊息總數。

**參數**: 無

**返回值**:
```javascript
12  // 表示目前有 12 則未讀訊息
```

**使用範例**:
```javascript
// 在導航列顯示未讀訊息數量
async function updateUnreadBadge() {
  const count = await getUnreadMessageCount();
  if (count === null) {
    // 使用者未登入
    return;
  }
  setBadgeCount(count);
}

// 定期更新未讀數量
setInterval(updateUnreadBadge, 30000); // 每 30 秒更新一次
```

**注意事項**:
- 若使用者未登入,返回 `null`
- 建議配合 Realtime 訂閱即時更新,而非輪詢

---

---

## 🗑️ 軟刪除功能 (Soft Delete)

### 8. 刪除對話 (單方面)

> **函數簽名**: `deleteConversation(conversationId: number): Promise<DeleteResult>`

#### `deleteConversation(conversationId)`

**功能**: 刪除對話,但不影響對方的對話列表。

**參數**:
- `conversationId` (number, 必填) - 對話 ID

**返回值**:
```javascript
{
  success: true,
  conversation_id: 51,
  deleted_by_role: "buyer",
  deleted_at: "2025-11-08T10:30:00+00:00"
}
```

**使用範例**:
```javascript
async function handleDeleteConversation(conversationId) {
  if (confirm('確定要刪除此對話嗎?')) {
    try {
      const result = await deleteConversation(conversationId);
      console.log('對話已刪除:', result);
      // 重新整理對話列表
      refreshConversations();
    } catch (error) {
      console.error('刪除失敗:', error.message);
    }
  }
}
```

**特性**:
- 🔸 買家刪除不影響賣家,反之亦然
- 🔸 對話不會從資料庫中真正移除
- 🔸 可以透過 `restoreConversation` 恢復
- 🔸 預設情況下 `getMyConversations` 不會返回已刪除的對話

---

---

### 9. 恢復已刪除的對話

> **函數簽名**: `restoreConversation(conversationId: number): Promise<RestoreResult>`

#### `restoreConversation(conversationId)`

**功能**: 撤銷使用者自己的刪除操作。

**參數**:
- `conversationId` (number, 必填) - 對話 ID

**返回值**:
```javascript
{
  success: true,
  conversation_id: 51,
  restored_by_role: "buyer",
  restored_at: "2025-11-08T10:35:00+00:00"
}
```

**使用範例**:
```javascript
try {
  const result = await restoreConversation(51);
  console.log('對話已恢復:', result);
} catch (error) {
  console.error('恢復失敗:', error.message);
}
```

---

---

### 10. 刪除訊息 (僅發送者可刪除)

> **函數簽名**: `deleteMessage(messageId: number): Promise<DeleteResult>`

#### `deleteMessage(messageId)`

**功能**: 刪除自己發送的訊息,刪除後雙方都看不到此訊息。

**參數**:
- `messageId` (number, 必填) - 訊息 ID

**返回值**:
```javascript
{
  success: true,
  message_id: 1001,
  conversation_id: 51,
  deleted_at: "2025-11-08T10:40:00+00:00"
}
```

**錯誤訊息**:
- `"您只能刪除自己發送的訊息"` - 嘗試刪除他人的訊息
- `"此訊息不存在或已被刪除"` - 訊息不存在

**使用範例**:
```javascript
async function handleDeleteMessage(messageId) {
  if (confirm('確定要刪除此訊息嗎? 此操作無法恢復')) {
    try {
      const result = await deleteMessage(messageId);
      console.log('訊息已刪除:', result);
      // 從 UI 中移除該訊息
      removeMessageFromUI(messageId);
    } catch (error) {
      alert(error.message);
    }
  }
}
```

**注意事項**:
- ⚠️ 訊息無法恢復 (與對話刪除不同)
- ⚠️ 只有發送者可以刪除
- ⚠️ 刪除後雙方都看不到

---

---

## 📡 Realtime 即時訊息訂閱

> **💡 章節摘要**: Realtime 訂閱是實現即時聊天的關鍵技術。透過監聽資料庫變更事件,可即時接收新訊息、已讀狀態更新等,無需輪詢。本章節提供三種主要訂閱場景的完整範例。

> 💡 **提示**: 使用 Realtime 訂閱可即時接收訊息更新,無需輪詢

### 訂閱新訊息

```javascript
import { supabase } from './supabaseClient';

// 訂閱特定對話的新訊息
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
      
      // 將新訊息加入 UI
      addMessageToUI(payload.new);
      
      // 如果不是自己發送的訊息,播放提示音
      if (payload.new.sender_id !== currentUserId) {
        playNotificationSound();
      }
    }
  )
  .subscribe();

// 離開頁面時取消訂閱
function cleanup() {
  channel.unsubscribe();
}
```

### 訂閱訊息已讀狀態更新

```javascript
const channel = supabase
  .channel(`conversation-messages-${conversationId}`)
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversation_messages',
      filter: `conversation_id=eq.${conversationId}`
    },
    (payload) => {
      console.log('訊息狀態更新:', payload.new);
      
      // 更新 UI 中的已讀狀態
      updateMessageReadStatus(payload.new.id, payload.new.is_read);
    }
  )
  .subscribe();
```

### 訂閱對話列表更新

```javascript
// 訂閱使用者的對話列表變化
const userId = 'current-user-uuid';

const channel = supabase
  .channel('user-conversations')
  .on(
    'postgres_changes',
    {
      event: '*',  // 監聽所有事件 (INSERT, UPDATE, DELETE)
      schema: 'public',
      table: 'conversations',
      filter: `buyer_id=eq.${userId}`
    },
    (payload) => {
      console.log('對話列表更新 (作為買家):', payload);
      refreshConversationList();
    }
  )
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'conversations',
      filter: `seller_id=eq.${userId}`
    },
    (payload) => {
      console.log('對話列表更新 (作為賣家):', payload);
      refreshConversationList();
    }
  )
  .subscribe();
```

---

---

## 💼 完整使用流程範例

> **💡 章節摘要**: 本章節提供三個完整的實際應用場景,包含 React 實作範例。涵蓋從發起聊天、即時訊息接收、到對話列表管理的完整流程。適合複製貼上後根據專案需求調整。

### 情境一: 買家想詢問某個物品

```javascript
async function contactSellerAboutItem(itemId) {
  try {
    // 1. 發起聊天 (或取得現有對話)
    const conversation = await startChatSafe(itemId);
    const conversationId = conversation.conversation_id;
    
    console.log('對話已建立:', conversationId);
    
    // 2. 導航到聊天頁面
    router.push(`/chat/${conversationId}`);
    
    // 3. (可選) 自動發送第一則訊息
    const greeting = await sendMessage(
      conversationId,
      '你好,請問這個物品還有嗎?'
    );
    
    console.log('訊息已發送:', greeting);
    
  } catch (error) {
    console.error('操作失敗:', error.message);
    alert(error.message);
  }
}
```

### 情境二: 聊天頁面的完整實作

```javascript
// React 範例
function ChatPage({ conversationId }) {
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [loading, setLoading] = useState(true);
  
  // 載入訊息
  useEffect(() => {
    loadMessages();
  }, [conversationId]);
  
  async function loadMessages() {
    try {
      setLoading(true);
      const data = await getConversationMessages(conversationId);
      setMessages(data || []);
    } catch (error) {
      console.error('載入訊息失敗:', error);
    } finally {
      setLoading(false);
    }
  }
  
  // 標記訊息為已讀
  useEffect(() => {
    markMessagesAsRead(conversationId);
  }, [conversationId]);
  
  // 訂閱新訊息
  useEffect(() => {
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
          // 將新訊息加入列表
          setMessages(prev => [...prev, transformMessage(payload.new)]);
          
          // 自動標記為已讀
          markMessagesAsRead(conversationId);
        }
      )
      .subscribe();
    
    return () => {
      channel.unsubscribe();
    };
  }, [conversationId]);
  
  // 發送訊息
  async function handleSendMessage(e) {
    e.preventDefault();
    
    if (!newMessage.trim()) return;
    
    try {
      const message = await sendMessage(conversationId, newMessage);
      setNewMessage('');
      // 訊息會透過 Realtime 自動加入列表
    } catch (error) {
      alert('發送失敗: ' + error.message);
    }
  }
  
  // 刪除訊息
  async function handleDeleteMessage(messageId) {
    if (!confirm('確定要刪除此訊息嗎?')) return;
    
    try {
      await deleteMessage(messageId);
      // 從列表中移除
      setMessages(prev => prev.filter(msg => msg.id !== messageId));
    } catch (error) {
      alert(error.message);
    }
  }
  
  function transformMessage(dbMessage) {
    return {
      id: dbMessage.id,
      sender: {
        id: dbMessage.sender_id,
        nickname: dbMessage.sender_nickname,
        profile_picture_url: dbMessage.sender_profile_picture
      },
      content: dbMessage.content,
      is_read: dbMessage.is_read,
      sent_at: dbMessage.sent_at
    };
  }
  
  if (loading) return <div>載入中...</div>;
  
  return (
    <div className="chat-page">
      <div className="messages">
        {messages.map(msg => (
          <MessageBubble 
            key={msg.id} 
            message={msg}
            onDelete={() => handleDeleteMessage(msg.id)}
          />
        ))}
      </div>
      
      <form onSubmit={handleSendMessage}>
        <input
          value={newMessage}
          onChange={e => setNewMessage(e.target.value)}
          placeholder="輸入訊息..."
        />
        <button type="submit">發送</button>
      </form>
    </div>
  );
}
```

### 情境三: 對話列表頁面

```javascript
function ConversationsListPage() {
  const [conversations, setConversations] = useState([]);
  const [role, setRole] = useState('all'); // all, buyer, seller
  const [page, setPage] = useState(1);
  
  useEffect(() => {
    loadConversations();
  }, [role, page]);
  
  async function loadConversations() {
    try {
      const data = await getMyConversations({ 
        page, 
        size: 20,
        role,
        includeDeleted: false 
      });
      setConversations(data || []);
    } catch (error) {
      console.error('載入對話列表失敗:', error);
    }
  }
  
  async function handleDeleteConversation(conversationId) {
    if (!confirm('確定要刪除此對話嗎?')) return;
    
    try {
      await deleteConversation(conversationId);
      // 從列表中移除
      setConversations(prev => 
        prev.filter(c => c.id !== conversationId)
      );
    } catch (error) {
      alert(error.message);
    }
  }
  
  return (
    <div className="conversations-list">
      <div className="filter-tabs">
        <button onClick={() => setRole('all')}>全部</button>
        <button onClick={() => setRole('buyer')}>我買的</button>
        <button onClick={() => setRole('seller')}>我賣的</button>
      </div>
      
      {conversations.map(convo => (
        <ConversationItem
          key={convo.id}
          conversation={convo}
          onDelete={() => handleDeleteConversation(convo.id)}
        />
      ))}
      
      <Pagination page={page} onPageChange={setPage} />
    </div>
  );
}
```

---

---

## 🔒 安全性

> **💡 章節摘要**: 本系統採用多層安全防護,包含身份驗證、權限驗證、資料驗證和 RLS 政策。確保使用者只能存取自己參與的對話和訊息,防止未授權存取。

所有 API 函數都包含以下安全檢查:

### 1. 身份驗證
- 使用 `auth.uid()` 確認使用者已登入
- 未登入的請求會被拒絕

### 2. 權限驗證
- 確認使用者有權限存取該對話或訊息
- RPC 函數會驗證使用者是否為對話參與者

### 3. 資料驗證
- 檢查輸入參數的有效性
- 防止 SQL 注入等攻擊

### 4. Row Level Security (RLS) 政策

以下 RLS 政策已啟用:

**conversations 表**:
- 使用者只能查看自己參與的對話 (作為買家或賣家)
- 使用者只能建立自己作為買家的對話

**conversation_messages 表**:
- 使用者只能查看自己參與的對話中的訊息
- 使用者只能在自己參與的對話中發送訊息
- 使用者只能刪除自己發送的訊息

---

---

## ⚠️ 錯誤處理

### 常見錯誤訊息

| 錯誤訊息 | 原因 | 解決方法 |
|---------|------|---------|
| `使用者未登入` | 未通過身份驗證 | 引導使用者登入 |
| `無權限查看此對話` | 使用者不是對話參與者 | 檢查對話 ID 是否正確 |
| `訊息內容不能為空` | 發送空訊息 | 驗證輸入內容 |
| `物品不存在或已下架` | 物品已刪除 | 提示使用者物品不可用 |
| `無法與自己的物品建立對話` | 嘗試對自己的物品發起聊天 | 隱藏「聯繫賣家」按鈕 |
| `您只能刪除自己發送的訊息` | 嘗試刪除他人訊息 | 只對自己的訊息顯示刪除按鈕 |

### 錯誤處理範例

```javascript
async function safeApiCall(apiFunction, ...args) {
  try {
    return await apiFunction(...args);
  } catch (error) {
    console.error('API 呼叫失敗:', error.message);
    
    // 根據錯誤訊息顯示適當的提示
    if (error.message.includes('未登入')) {
      // 導向登入頁面
      router.push('/login');
    } else if (error.message.includes('無權限')) {
      // 顯示權限錯誤
      showError('您沒有權限執行此操作');
    } else {
      // 通用錯誤提示
      showError(error.message);
    }
    
    throw error; // 繼續向上拋出錯誤
  }
}

// 使用範例
const messages = await safeApiCall(
  getConversationMessages, 
  conversationId
);
```

---

---

## ⚡ 效能優化建議

> **💡 章節摘要**: 本章節提供五個關鍵效能優化技巧,包含批次查詢、防重複請求、分頁載入、使用 Realtime 而非輪詢、以及快取策略。遵循這些建議可顯著提升應用效能和使用者體驗。

### 1. 使用批次查詢

```javascript
// ❌ 不好的做法 - N+1 查詢
for (const id of conversationIds) {
  const convo = await getConversationById(id); // 假設有此函數
}

// ✅ 好的做法 - 批次查詢
const convos = await getConversationsByIds(conversationIds);
```

### 2. 使用防重複請求機制

```javascript
// ✅ 防止使用者快速點擊造成重複請求
<button onClick={() => startChatSafe(itemId)}>
  聯繫賣家
</button>
```

### 3. 實作分頁載入

```javascript
// 實作無限捲動
async function loadMoreMessages() {
  const nextPage = page + 1;
  const olderMessages = await getConversationMessages(
    conversationId, 
    { page: nextPage, size: 50 }
  );
  
  if (olderMessages.length > 0) {
    setMessages(prev => [...olderMessages, ...prev]);
    setPage(nextPage);
  }
}
```

### 4. 使用 Realtime 而非輪詢

```javascript
// ❌ 不好的做法 - 輪詢
setInterval(async () => {
  const count = await getUnreadMessageCount();
  updateBadge(count);
}, 5000);

// ✅ 好的做法 - Realtime 訂閱
supabase
  .channel('new-messages')
  .on('postgres_changes', { ... }, () => {
    // 即時更新,無需輪詢
  })
  .subscribe();
```

### 5. 快取策略

```javascript
// 簡單的快取實作
const conversationCache = new Map();

async function getCachedConversation(conversationId) {
  if (conversationCache.has(conversationId)) {
    return conversationCache.get(conversationId);
  }
  
  const convos = await getConversationsByIds([conversationId]);
  const convo = convos[0];
  
  conversationCache.set(conversationId, convo);
  return convo;
}
```

---

---

## 🗄️ 資料庫架構參考

### conversations 表

| 欄位 | 型別 | 說明 |
|-----|------|------|
| `id` | BIGINT | 對話 ID (主鍵) |
| `item_id` | BIGINT | 關聯的物品 ID |
| `buyer_id` | UUID | 買家使用者 ID |
| `seller_id` | UUID | 賣家使用者 ID |
| `deleted_by_buyer_at` | TIMESTAMP | 買家刪除時間 |
| `deleted_by_seller_at` | TIMESTAMP | 賣家刪除時間 |
| `created_at` | TIMESTAMP | 建立時間 |
| `updated_at` | TIMESTAMP | 最後更新時間 |

**索引**:
- 唯一索引: `(item_id, buyer_id)` - 防止重複對話
- 索引: `updated_at DESC` - 優化排序查詢

### conversation_messages 表

| 欄位 | 型別 | 說明 |
|-----|------|------|
| `id` | BIGINT | 訊息 ID (主鍵) |
| `conversation_id` | BIGINT | 所屬對話 ID |
| `sender_id` | UUID | 發送者使用者 ID |
| `content` | TEXT | 訊息內容 |
| `is_read` | BOOLEAN | 是否已讀 |
| `deleted_at` | TIMESTAMP | 刪除時間 |
| `sent_at` | TIMESTAMP | 發送時間 |

**索引**:
- 索引: `(conversation_id, sent_at DESC)` - 優化訊息查詢
- 索引: `(conversation_id, is_read)` - 優化未讀訊息查詢

---

---

## 🧪 測試建議

### 1. 單元測試

```javascript
describe('conversationAPI', () => {
  it('should start chat with valid item ID', async () => {
    const conversation = await startChat(101);
    expect(conversation).toHaveProperty('conversation_id');
    expect(conversation.item_id).toBe(101);
  });
  
  it('should throw error for invalid item ID', async () => {
    await expect(startChat(-1)).rejects.toThrow('無效的物品 ID');
  });
  
  it('should send message successfully', async () => {
    const message = await sendMessage(51, 'Hello');
    expect(message).toHaveProperty('id');
    expect(message.content).toBe('Hello');
  });
});
```

### 2. 整合測試

```javascript
describe('Chat Flow Integration', () => {
  it('should complete full chat flow', async () => {
    // 1. 發起聊天
    const convo = await startChat(101);
    
    // 2. 發送訊息
    const msg = await sendMessage(convo.conversation_id, 'Hi');
    
    // 3. 取得訊息列表
    const messages = await getConversationMessages(convo.conversation_id);
    expect(messages).toContainEqual(
      expect.objectContaining({ content: 'Hi' })
    );
    
    // 4. 標記為已讀
    const count = await markMessagesAsRead(convo.conversation_id);
    expect(count).toBeGreaterThanOrEqual(0);
  });
});
```

### 3. 手動測試清單

- [ ] 測試發起新對話
- [ ] 測試重複發起對話 (應返回現有對話)
- [ ] 測試發送訊息
- [ ] 測試接收即時訊息
- [ ] 測試標記訊息為已讀
- [ ] 測試刪除對話 (單方面)
- [ ] 測試恢復已刪除對話
- [ ] 測試刪除訊息 (僅自己的)
- [ ] 測試嘗試刪除他人訊息 (應失敗)
- [ ] 測試未登入狀態 (應返回 null 或拋出錯誤)
- [ ] 測試無權限存取對話 (應失敗)
- [ ] 測試分頁功能
- [ ] 測試篩選功能 (role: buyer/seller/all)

---

---

## 🚀 後續擴展建議

1. **訊息類型擴展**
   - 支援圖片訊息
   - 支援檔案訊息
   - 支援位置訊息
   - 支援表情符號回應

2. **進階功能**
   - 訊息搜尋功能
   - 訊息置頂功能
   - 快速回覆模板
   - 自動回覆機器人

3. **通知整合**
   - 推送通知 (Push Notifications)
   - Email 通知
   - 桌面通知

4. **使用者體驗**
   - 輸入狀態指示器 ("對方正在輸入...")
   - 訊息送達/已讀回條
   - 訊息編輯功能
   - 訊息轉發功能

5. **管理功能**
   - 舉報不當訊息
   - 封鎖使用者
   - 訊息加密
   - 對話封存

---

---

## ❓ 常見問題 (FAQ)

> **💡 章節摘要**: 本章節收錄開發過程中最常遇到的 6 個問題及解決方案,包含防重複請求、輸入狀態指示器、已讀回條、未讀徽章、對話排序和無限捲動等實作技巧。

### Q1: 如何防止使用者快速點擊「聯繫賣家」造成重複請求?

**A**: 使用 `startChatSafe()` 而非 `startChat()`。此函數包含防重複請求機制。

```javascript
// ✅ 推薦
const conversation = await startChatSafe(itemId);

// 或自行實作防抖動
const debouncedStartChat = debounce(startChat, 1000);
```

### Q2: 如何實作「對方正在輸入...」的功能?

**A**: 需要使用 Supabase Presence 功能:

```javascript
const channel = supabase.channel(`conversation-${conversationId}`);

// 廣播輸入狀態
function handleTyping() {
  channel.send({
    type: 'broadcast',
    event: 'typing',
    payload: { user_id: currentUserId }
  });
}

// 監聽輸入狀態
channel.on('broadcast', { event: 'typing' }, (payload) => {
  showTypingIndicator(payload.user_id);
});
```

### Q3: 如何實作訊息已讀回條?

**A**: 訂閱訊息的 UPDATE 事件:

```javascript
supabase
  .channel(`message-${messageId}`)
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'conversation_messages',
    filter: `id=eq.${messageId}`
  }, (payload) => {
    if (payload.new.is_read) {
      showReadReceipt(messageId);
    }
  })
  .subscribe();
```

### Q4: 如何顯示未讀訊息數量徽章?

**A**: 使用 `getUnreadMessageCount()` 配合 Realtime:

```javascript
// 初始載入
const initialCount = await getUnreadMessageCount();
setBadgeCount(initialCount);

// 即時更新
supabase
  .channel('user-messages')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'conversation_messages'
  }, async () => {
    const newCount = await getUnreadMessageCount();
    setBadgeCount(newCount);
  })
  .subscribe();
```

### Q5: 對話列表如何按最新訊息排序?

**A**: `getMyConversations()` 已經按 `updated_at` DESC 排序,最新對話會在最前面。

### Q6: 如何實作無限捲動載入歷史訊息?

**A**: 使用分頁參數:

```javascript
const [page, setPage] = useState(1);
const [allMessages, setAllMessages] = useState([]);

async function loadMore() {
  const olderMessages = await getConversationMessages(
    conversationId,
    { page: page + 1, size: 50 }
  );
  
  if (olderMessages.length > 0) {
    setAllMessages(prev => [...olderMessages, ...prev]);
    setPage(prev => prev + 1);
  }
}
```

---

---

## 📋 版本歷史

### v1.2 (2025-11-08)
- ✨ 新增防重複請求機制 (`startChatSafe`)
- ✨ 新增批次查詢對話功能 (`getConversationsByIds`)
- ✨ 新增軟刪除功能 (`deleteConversation`, `restoreConversation`, `deleteMessage`)
- ✨ `getMyConversations` 支援 `role` 和 `includeDeleted` 參數
- 🐛 改善錯誤處理和訊息

### v1.1
- ✨ 新增 Realtime 訂閱支援
- 🐛 修復分頁問題

### v1.0
- 🎉 初始版本
- ✨ 基本聊天功能

---

---

## 📞 支援與回饋

如有問題或建議,請聯繫開發團隊或提交 Issue。

**文件維護者**: Backend Team  
**最後更新**: 2025-11-08

---

---

## 📋 快速參考卡片

### 最常用的 5 個函數

```javascript
// 1️⃣ 發起聊天 (防重複)
const conversation = await startChatSafe(itemId);

// 2️⃣ 取得對話列表
const conversations = await getMyConversations({ page: 1, size: 20 });

// 3️⃣ 取得訊息
const messages = await getConversationMessages(conversationId);

// 4️⃣ 發送訊息
const message = await sendMessage(conversationId, '你好!');

// 5️⃣ 標記已讀
await markMessagesAsRead(conversationId);
```

### 錯誤處理模板

```javascript
try {
  const result = await apiFunction(...args);
  // 處理成功結果
} catch (error) {
  if (error.message.includes('未登入')) {
    // 導向登入頁面
  } else if (error.message.includes('無權限')) {
    // 顯示權限錯誤
  } else {
    // 通用錯誤處理
    console.error(error.message);
  }
}
```

### Realtime 訂閱模板

```javascript
// 訂閱新訊息
const channel = supabase
  .channel(`conversation-${conversationId}`)
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'conversation_messages',
    filter: `conversation_id=eq.${conversationId}`
  }, (payload) => {
    // 處理新訊息
  })
  .subscribe();

// 記得在組件卸載時取消訂閱
return () => channel.unsubscribe();
```

---

## 🔖 常用程式碼片段索引

### 頁面實作範例
- [聊天頁面完整實作](#情境二-聊天頁面的完整實作) - React 聊天室範例
- [對話列表頁面](#情境三-對話列表頁面) - 對話列表與篩選
- [發起對話流程](#情境一-買家想詢問某個物品) - 從物品到聊天的完整流程

### 功能實作範例
- [無限捲動載入](#q6-如何實作無限捲動載入歷史訊息) - 分頁載入更多訊息
- [未讀徽章顯示](#q4-如何顯示未讀訊息數量徽章) - 導航列未讀數量
- [輸入狀態指示器](#q2-如何實作對方正在輸入的功能) - "對方正在輸入..."
- [訊息已讀回條](#q3-如何實作訊息已讀回條) - 雙勾已讀標示

### 效能優化範例
- [批次查詢對話](#1-使用批次查詢) - 避免 N+1 問題
- [防重複請求](#2-使用防重複請求機制) - 防止快速點擊
- [分頁載入](#3-實作分頁載入) - 優化大量資料
- [快取策略](#5-快取策略) - 簡單快取實作

---

## 🎓 學習路徑建議

### 初級開發者 (0-2 週)
1. ✅ 閱讀[快速開始](#-快速開始)章節
2. ✅ 學習[發起聊天](#startchatsafeitemid)功能
3. ✅ 學習[發送訊息](#sendmessageconversationid-content)功能
4. ✅ 學習[取得訊息列表](#getconversationmessagesconversationid-options)
5. ✅ 實作[情境一範例](#情境一-買家想詢問某個物品)

### 中級開發者 (2-4 週)
1. ✅ 學習[Realtime 訂閱](#-realtime-即時訊息訂閱)
2. ✅ 實作[聊天頁面完整範例](#情境二-聊天頁面的完整實作)
3. ✅ 實作[對話列表頁面](#情境三-對話列表頁面)
4. ✅ 加入[錯誤處理](#️-錯誤處理)機制
5. ✅ 實作[未讀徽章功能](#q4-如何顯示未讀訊息數量徽章)

### 高級開發者 (4+ 週)
1. ✅ 應用[效能優化建議](#-效能優化建議)
2. ✅ 實作[批次查詢](#getconversationsbyidsconversationids)功能
3. ✅ 實作[軟刪除功能](#️-軟刪除功能-soft-delete)
4. ✅ 加入[快取策略](#5-快取策略)
5. ✅ 撰寫[單元測試](#1-單元測試)

---

## 📚 相關文件連結

- **Supabase 官方文件**: [https://supabase.com/docs](https://supabase.com/docs)
- **Supabase Realtime**: [https://supabase.com/docs/guides/realtime](https://supabase.com/docs/guides/realtime)
- **Row Level Security**: [https://supabase.com/docs/guides/auth/row-level-security](https://supabase.com/docs/guides/auth/row-level-security)
- **Supabase JavaScript 客戶端**: [https://supabase.com/docs/reference/javascript](https://supabase.com/docs/reference/javascript)

---

**📝 備註**: 本文件會隨著 API 更新持續維護,建議定期查看最新版本。