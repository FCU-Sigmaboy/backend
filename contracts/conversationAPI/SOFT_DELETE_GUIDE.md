# 軟刪除功能使用指南

**版本**: 1.0  
**建立日期**: 2025-11-08  
**適用範圍**: 對話與訊息軟刪除功能  

---

## 📋 目錄

1. [功能概述](#功能概述)
2. [核心概念](#核心概念)
3. [前端 API 函數](#前端-api-函數)
4. [使用範例](#使用範例)
5. [UI/UX 建議](#uiux-建議)
6. [注意事項](#注意事項)
7. [測試清單](#測試清單)

---

## 功能概述

### 什麼是軟刪除？

軟刪除（Soft Delete）是一種資料刪除策略，**不會真正從資料庫移除資料**，而是透過標記欄位來隱藏資料。這樣做的好處包括：

- ✅ 資料可恢復（撤銷刪除）
- ✅ 避免另一方使用者的資料出錯
- ✅ 保留歷史記錄用於分析
- ✅ 支援單方面刪除的使用情境

### 支援的功能

| 功能 | 說明 | 影響範圍 |
|-----|------|---------|
| **刪除對話** | 使用者可以刪除對話 | 只影響自己，對方仍可見 |
| **恢復對話** | 撤銷刪除操作 | 對話重新出現在列表中 |
| **刪除訊息** | 發送者可刪除自己的訊息 | 雙方都不可見 |
| **自動清理** | 30 天後永久刪除 | 雙方都刪除的對話 |

---

## 核心概念

### 1. 單方面刪除（對話）

```
情境：買家刪除對話
┌─────────────────────────────────────────┐
│ 買家視角                                 │
├─────────────────────────────────────────┤
│ 對話列表：                               │
│ ❌ 不顯示此對話（已刪除）                 │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 賣家視角                                 │
├─────────────────────────────────────────┤
│ 對話列表：                               │
│ ✅ 仍然顯示此對話（未刪除）               │
└─────────────────────────────────────────┘
```

### 2. 雙方都刪除（對話）

```
情境：買家和賣家都刪除對話
┌─────────────────────────────────────────┐
│ 系統行為                                 │
├─────────────────────────────────────────┤
│ 1. 雙方列表都不顯示                       │
│ 2. 對話暫時保留在資料庫                   │
│ 3. 30 天後自動永久刪除                    │
└─────────────────────────────────────────┘
```

### 3. 刪除訊息

```
情境：發送者刪除訊息
┌─────────────────────────────────────────┐
│ 影響範圍                                 │
├─────────────────────────────────────────┤
│ ✅ 發送者：訊息消失                       │
│ ✅ 接收者：訊息消失                       │
│ ❌ 無法恢復（永久刪除）                   │
└─────────────────────────────────────────┘
```

---

## 前端 API 函數

### 1. 刪除對話

```javascript
/**
 * 刪除對話（單方面）
 * @param {number} conversationId - 對話 ID
 * @returns {Promise<Object>} - 刪除結果
 */
export async function deleteConversation(conversationId) {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  
  if (authError || !user) {
    throw new Error("使用者未登入，無法刪除對話");
  }

  const { data, error } = await supabase.rpc("delete_conversation", {
    p_conversation_id: conversationId,
  });

  if (error) {
    console.error(`刪除對話失敗 (ID: ${conversationId}):`, error);
    throw new Error(error.message);
  }

  return data;
}

/* 回傳範例
{
  "success": true,
  "conversation_id": 51,
  "deleted_by_role": "buyer",
  "deleted_at": "2025-11-08T10:30:00+00:00"
}
*/
```

### 2. 恢復對話

```javascript
/**
 * 恢復已刪除的對話
 * @param {number} conversationId - 對話 ID
 * @returns {Promise<Object>} - 恢復結果
 */
export async function restoreConversation(conversationId) {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  
  if (authError || !user) {
    throw new Error("使用者未登入，無法恢復對話");
  }

  const { data, error } = await supabase.rpc("restore_conversation", {
    p_conversation_id: conversationId,
  });

  if (error) {
    console.error(`恢復對話失敗 (ID: ${conversationId}):`, error);
    throw new Error(error.message);
  }

  return data;
}

/* 回傳範例
{
  "success": true,
  "conversation_id": 51,
  "restored_by_role": "buyer",
  "restored_at": "2025-11-08T10:35:00+00:00"
}
*/
```

### 3. 刪除訊息

```javascript
/**
 * 刪除訊息（僅發送者可刪除）
 * @param {number} messageId - 訊息 ID
 * @returns {Promise<Object>} - 刪除結果
 */
export async function deleteMessage(messageId) {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  
  if (authError || !user) {
    throw new Error("使用者未登入，無法刪除訊息");
  }

  const { data, error } = await supabase.rpc("delete_message", {
    p_message_id: messageId,
  });

  if (error) {
    console.error(`刪除訊息失敗 (ID: ${messageId}):`, error);
    
    // 提供友善的錯誤訊息
    if (error.message.includes("只能刪除自己發送的訊息")) {
      throw new Error("您只能刪除自己發送的訊息");
    } else if (error.message.includes("訊息不存在或已被刪除")) {
      throw new Error("此訊息不存在或已被刪除");
    } else {
      throw new Error(error.message);
    }
  }

  return data;
}

/* 回傳範例
{
  "success": true,
  "message_id": 1001,
  "conversation_id": 51,
  "deleted_at": "2025-11-08T10:40:00+00:00"
}
*/
```

### 4. 查詢對話列表（含已刪除）

```javascript
/**
 * 獲取對話列表（可選擇是否包含已刪除的對話）
 * @param {object} options - 查詢選項
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數
 * @param {string} [options.role='all'] - 角色過濾
 * @param {boolean} [options.includeDeleted=false] - 是否包含已刪除的對話
 * @returns {Promise<Array>} - 對話列表
 */
export async function getMyConversations(options = {}) {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  
  if (authError || !user) {
    console.warn("getMyConversations: User not logged in.");
    return null;
  }

  const page = options.page || 1;
  const size = options.size || 20;
  const role = options.role || 'all';
  const includeDeleted = options.includeDeleted || false;

  const rpcParams = {
    p_page: page,
    p_size: size,
    p_role: role,
    p_include_deleted: includeDeleted,
  };

  const { data, error } = await supabase.rpc(
    "get_user_conversations",
    rpcParams,
  );

  if (error) {
    console.error("獲取對話列表失敗:", error);
    throw new Error(error.message);
  }

  return data.map((convo) => ({
    id: convo.conversation_id,
    item: {
      id: convo.item_id,
      title: convo.item_title || "物品已刪除",
      cover_image_url: convo.item_image_url,
    },
    other_user: {
      id: convo.other_user_id,
      nickname: convo.other_user_nickname || "未知使用者",
      profile_picture_url: convo.other_user_profile_picture,
    },
    last_message: convo.last_message,
    last_message_time: convo.last_message_time,
    unread_count: parseInt(convo.unread_count) || 0,
    created_at: convo.created_at,
    updated_at: convo.updated_at,
    is_deleted: convo.is_deleted, // 新增：標示是否已刪除
  }));
}
```

---

## 使用範例

### React 範例 1: 刪除對話

```jsx
import { deleteConversation } from './conversationAPI';

function ConversationListItem({ conversation }) {
  const [isDeleting, setIsDeleting] = useState(false);

  const handleDelete = async () => {
    // 顯示確認對話框
    const confirmed = window.confirm(
      '確定要刪除此對話嗎？\n（對方仍可看到此對話）'
    );
    
    if (!confirmed) return;

    setIsDeleting(true);
    try {
      await deleteConversation(conversation.id);
      
      // 顯示成功訊息
      showToast('對話已刪除', 'success');
      
      // 從列表中移除（或重新載入列表）
      refetchConversations();
    } catch (error) {
      showToast(error.message, 'error');
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className="conversation-item">
      <div className="conversation-info">
        {/* 對話內容 */}
      </div>
      <button 
        onClick={handleDelete}
        disabled={isDeleting}
        className="delete-button"
      >
        {isDeleting ? '刪除中...' : '刪除對話'}
      </button>
    </div>
  );
}
```

### React 範例 2: 刪除訊息

```jsx
import { deleteMessage } from './conversationAPI';

function MessageItem({ message, currentUserId }) {
  const [isDeleting, setIsDeleting] = useState(false);
  const isMine = message.sender.id === currentUserId;

  const handleDelete = async () => {
    const confirmed = window.confirm('確定要刪除此訊息嗎？');
    if (!confirmed) return;

    setIsDeleting(true);
    try {
      await deleteMessage(message.id);
      showToast('訊息已刪除', 'success');
      
      // 從訊息列表中移除
      removeMessageFromList(message.id);
    } catch (error) {
      if (error.message.includes('只能刪除自己發送的訊息')) {
        showToast('您無法刪除其他人的訊息', 'warning');
      } else {
        showToast(error.message, 'error');
      }
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className={`message ${isMine ? 'mine' : 'theirs'}`}>
      <div className="message-content">{message.content}</div>
      {isMine && (
        <button onClick={handleDelete} disabled={isDeleting}>
          刪除
        </button>
      )}
    </div>
  );
}
```

### React 範例 3: 撤銷刪除（含倒數計時）

```jsx
import { deleteConversation, restoreConversation } from './conversationAPI';

function ConversationListItem({ conversation }) {
  const [showUndo, setShowUndo] = useState(false);
  const [countdown, setCountdown] = useState(5);

  const handleDelete = async () => {
    try {
      await deleteConversation(conversation.id);
      
      // 顯示撤銷提示（5 秒倒數）
      setShowUndo(true);
      setCountdown(5);
      
      // 倒數計時
      const timer = setInterval(() => {
        setCountdown(prev => {
          if (prev <= 1) {
            clearInterval(timer);
            setShowUndo(false);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    } catch (error) {
      showToast(error.message, 'error');
    }
  };

  const handleUndo = async () => {
    try {
      await restoreConversation(conversation.id);
      setShowUndo(false);
      showToast('已恢復對話', 'success');
      refetchConversations();
    } catch (error) {
      showToast(error.message, 'error');
    }
  };

  if (showUndo) {
    return (
      <div className="undo-notification">
        <span>對話已刪除</span>
        <button onClick={handleUndo}>
          撤銷 ({countdown}s)
        </button>
      </div>
    );
  }

  return (
    <div className="conversation-item">
      {/* 對話內容 */}
      <button onClick={handleDelete}>刪除對話</button>
    </div>
  );
}
```

---

## UI/UX 建議

### 1. 刪除確認對話框

```jsx
// ✅ 推薦：清楚說明刪除的影響範圍
const confirmDelete = () => {
  return window.confirm(
    '確定要刪除此對話嗎？\n\n' +
    '• 對話將從您的列表中移除\n' +
    '• 對方仍然可以看到此對話\n' +
    '• 您可以在 5 秒內撤銷此操作'
  );
};

// ❌ 避免：訊息不夠清楚
const confirmDelete = () => {
  return window.confirm('確定要刪除嗎？');
};
```

### 2. 刪除後的視覺回饋

```jsx
// ✅ 推薦：使用淡出動畫
<motion.div
  initial={{ opacity: 1 }}
  exit={{ opacity: 0, x: -100 }}
  transition={{ duration: 0.3 }}
>
  {/* 對話項目 */}
</motion.div>

// ✅ 推薦：顯示 Toast 通知
showToast('對話已刪除', {
  duration: 3000,
  action: {
    label: '撤銷',
    onClick: handleUndo,
  },
});
```

### 3. 訊息刪除的顯示方式

```jsx
// ✅ 推薦：顯示「此訊息已被刪除」的佔位符
function MessageItem({ message }) {
  if (message.is_deleted) {
    return (
      <div className="message deleted">
        <span className="deleted-text">此訊息已被刪除</span>
      </div>
    );
  }
  
  return (
    <div className="message">
      {/* 正常訊息內容 */}
    </div>
  );
}

// ❌ 避免：直接移除訊息（會導致對話跳動）
```

### 4. 批次刪除

```jsx
function ConversationList({ conversations }) {
  const [selectedIds, setSelectedIds] = useState([]);

  const handleBatchDelete = async () => {
    const confirmed = window.confirm(
      `確定要刪除 ${selectedIds.length} 個對話嗎？`
    );
    
    if (!confirmed) return;

    try {
      await Promise.all(
        selectedIds.map(id => deleteConversation(id))
      );
      showToast('已刪除所選對話', 'success');
      setSelectedIds([]);
      refetchConversations();
    } catch (error) {
      showToast('部分對話刪除失敗', 'error');
    }
  };

  return (
    <div>
      {selectedIds.length > 0 && (
        <button onClick={handleBatchDelete}>
          刪除 {selectedIds.length} 個對話
        </button>
      )}
      {/* 對話列表 */}
    </div>
  );
}
```

---

## 注意事項

### ⚠️ 重要限制

1. **訊息刪除是永久的**
   - 訊息一旦刪除，無法恢復
   - 只有發送者可以刪除訊息
   - 刪除後雙方都看不到

2. **對話刪除是單方面的**
   - 刪除對話不影響對方
   - 對方仍可發送訊息
   - 如果對方發送新訊息，對話會重新出現在您的列表中

3. **自動清理機制**
   - 雙方都刪除的對話會在 30 天後永久刪除
   - 永久刪除後無法恢復
   - 清理任務由系統自動執行

### 🔒 權限控制

| 操作 | 誰可以執行 |
|-----|-----------|
| 刪除對話 | 對話參與者（買家或賣家） |
| 恢復對話 | 刪除操作的執行者 |
| 刪除訊息 | 訊息發送者 |
| 查看已刪除對話 | 需使用 `includeDeleted=true` 參數 |

### 💡 最佳實踐

1. **提供撤銷功能**
   ```javascript
   // ✅ 推薦：給予 5-10 秒的撤銷時間
   const UNDO_TIMEOUT = 5000;
   ```

2. **錯誤處理**
   ```javascript
   // ✅ 推薦：提供友善的錯誤訊息
   try {
     await deleteMessage(messageId);
   } catch (error) {
     if (error.message.includes('只能刪除自己發送的訊息')) {
       showToast('您無法刪除其他人的訊息', 'warning');
     } else {
       showToast('刪除失敗，請稍後再試', 'error');
     }
   }
   ```

3. **Realtime 更新**
   ```javascript
   // ✅ 推薦：監聽刪除事件
   supabase
     .channel('messages')
     .on('postgres_changes', {
       event: 'UPDATE',
       schema: 'public',
       table: 'conversation_messages',
       filter: `conversation_id=eq.${conversationId}`
     }, (payload) => {
       if (payload.new.deleted_at) {
         // 訊息被刪除，從 UI 移除
         removeMessageFromList(payload.new.id);
       }
     })
     .subscribe();
   ```

---

## 測試清單

### 功能測試

- [ ] **刪除對話**
  - [ ] 買家可以刪除對話
  - [ ] 賣家可以刪除對話
  - [ ] 刪除後自己的列表不顯示
  - [ ] 刪除後對方的列表仍顯示
  - [ ] 無法刪除不存在的對話
  - [ ] 無法刪除其他人的對話

- [ ] **恢復對話**
  - [ ] 可以恢復剛刪除的對話
  - [ ] 恢復後對話重新出現在列表中
  - [ ] 無法恢復未刪除的對話
  - [ ] 無法恢復其他人刪除的對話

- [ ] **刪除訊息**
  - [ ] 可以刪除自己發送的訊息
  - [ ] 無法刪除其他人的訊息
  - [ ] 刪除後雙方都看不到訊息
  - [ ] 無法刪除已刪除的訊息
  - [ ] 無法刪除不存在的訊息

### 邊界測試

- [ ] **併發測試**
  - [ ] 雙方同時刪除對話
  - [ ] 快速重複刪除操作
  - [ ] 刪除過程中收到新訊息

- [ ] **權限測試**
  - [ ] 未登入使用者無法刪除
  - [ ] 非參與者無法刪除對話
  - [ ] 非發送者無法刪除訊息

### UI/UX 測試

- [ ] **視覺回饋**
  - [ ] 刪除確認對話框顯示正確
  - [ ] 刪除成功後顯示 Toast
  - [ ] 撤銷按鈕在時限內可見
  - [ ] 倒數計時正確運作

- [ ] **錯誤處理**
  - [ ] 錯誤訊息清楚易懂
  - [ ] 網路錯誤有適當處理
  - [ ] Loading 狀態顯示正確

---

## 附錄

### A. 資料庫欄位說明

| 表格 | 欄位 | 類型 | 說明 |
|-----|------|------|------|
| `conversations` | `deleted_by_buyer_at` | TIMESTAMPTZ | 買家刪除時間 |
| `conversations` | `deleted_by_seller_at` | TIMESTAMPTZ | 賣家刪除時間 |
| `conversation_messages` | `deleted_at` | TIMESTAMPTZ | 訊息刪除時間 |
| `conversation_messages` | `deleted_by` | UUID | 刪除者 ID |

### B. RPC 函數列表

| 函數名稱 | 參數 | 回傳 | 說明 |
|---------|------|------|------|
| `delete_conversation` | `p_conversation_id` | JSONB | 刪除對話 |
| `restore_conversation` | `p_conversation_id` | JSONB | 恢復對話 |
| `delete_message` | `p_message_id` | JSONB | 刪除訊息 |
| `cleanup_deleted_conversations` | `p_days_threshold` | JSONB | 清理舊對話 |

### C. 相關文件

- `IMPROVEMENT_PLAN.md` - 改善計畫（任務 6）
- `TEMPLATE_soft_delete_implementation.sql` - Migration 範本
- `conversationAPI.js` - 前端 API 模組
- `FRONTEND_IMPACT_ASSESSMENT.md` - 前端影響評估

---

**文件版本**: 1.0  
**最後更新**: 2025-11-08  
**維護者**: Backend Team