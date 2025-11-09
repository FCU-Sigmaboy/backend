# Supabase Realtime 設置指南 - Messaging System v2

## 📋 目錄

1. [啟用 Realtime](#啟用-realtime)
2. [驗證配置](#驗證配置)
3. [前端使用](#前端使用)
4. [測試 Realtime](#測試-realtime)
5. [常見問題](#常見問題)

---

## 🚀 啟用 Realtime

### 步驟 1: 執行 SQL 腳本

1. **登入 Supabase Dashboard**
   - 前往 https://supabase.com/dashboard
   - 選擇你的專案

2. **打開 SQL Editor**
   - 點選左側的 **SQL Editor**
   - 點選 **New query**

3. **執行 Realtime 啟用腳本**
   - 複製 `migrations/enable_realtime.sql` 的內容
   - 貼到 SQL Editor
   - 點選 **Run**

4. **確認成功**
   應該會看到:
   ```
   ✅ conversations_v2: 已啟用
   ✅ conversation_messages_v2: 已啟用
   ✅ conversation_items_v2: 已啟用
   ✅ 所有表都已成功啟用 Realtime!
   ```

### 步驟 2: 在 Dashboard 中驗證 (可選)

1. 前往 **Database** → **Replication**
2. 檢查 `supabase_realtime` publication 是否包含:
   - `public.conversations_v2`
   - `public.conversation_messages_v2`
   - `public.conversation_items_v2`

---

## ✅ 驗證配置

### 方法 1: SQL 查詢驗證

在 SQL Editor 中執行:

```sql
-- 檢查 REPLICA IDENTITY
SELECT
    schemaname,
    tablename,
    CASE relreplident
        WHEN 'd' THEN 'DEFAULT'
        WHEN 'n' THEN 'NOTHING'
        WHEN 'f' THEN 'FULL'
        WHEN 'i' THEN 'INDEX'
    END AS replica_identity
FROM pg_class
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
WHERE schemaname = 'public'
  AND tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2');

-- 檢查 Publication
SELECT
    schemaname,
    tablename,
    pubname
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename LIKE '%_v2';

-- 檢查 RLS 策略
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies
WHERE tablename LIKE '%_v2'
ORDER BY tablename, policyname;
```

### 方法 2: 前端測試連接

創建一個測試檔案 `test-realtime.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Realtime Test</title>
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
</head>
<body>
    <h1>Supabase Realtime 測試</h1>
    <div id="status">正在連接...</div>
    <div id="messages"></div>

    <script>
        const supabase = window.supabase.createClient(
            'YOUR_SUPABASE_URL',
            'YOUR_SUPABASE_ANON_KEY'
        );

        const messagesDiv = document.getElementById('messages');
        const statusDiv = document.getElementById('status');

        // 訂閱訊息表的 INSERT 事件
        const subscription = supabase
            .channel('test_channel')
            .on('postgres_changes', {
                event: 'INSERT',
                schema: 'public',
                table: 'conversation_messages_v2'
            }, (payload) => {
                console.log('New message:', payload);
                const p = document.createElement('p');
                p.textContent = `新訊息: ${JSON.stringify(payload.new)}`;
                messagesDiv.appendChild(p);
            })
            .subscribe((status) => {
                console.log('Subscription status:', status);
                statusDiv.textContent = `連接狀態: ${status}`;
            });

        // 測試: 5秒後取消訂閱
        setTimeout(() => {
            subscription.unsubscribe();
            statusDiv.textContent += ' (已取消訂閱)';
        }, 30000);
    </script>
</body>
</html>
```

---

## 💻 前端使用

### 1. 訂閱新訊息 (已實現)

使用 `conversationAPI_v2.js` 中的 `subscribeToMessages()`:

```javascript
import { subscribeToMessages } from './conversationAPI_v2.js';

// 在 Vue 組件中
export default {
  data() {
    return {
      subscription: null,
      messages: []
    };
  },
  
  mounted() {
    // 訂閱對話 ID 為 456 的新訊息
    this.subscription = subscribeToMessages(456, (newMessage) => {
      console.log('收到新訊息:', newMessage);
      
      // 將新訊息加入列表
      this.messages.push({
        message_id: newMessage.id,
        sender_id: newMessage.sender_id,
        content: newMessage.content,
        created_at: newMessage.created_at,
        // ...其他欄位
      });
      
      // 播放通知音效
      this.playNotificationSound();
      
      // 顯示通知
      this.$notify({
        title: '新訊息',
        message: newMessage.content,
        type: 'info'
      });
    });
  },
  
  beforeUnmount() {
    // 組件銷毀時取消訂閱
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
  }
};
```

### 2. 訂閱對話列表更新

```javascript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

export function subscribeToConversationUpdates(userId, callback) {
  return supabase
    .channel('my_conversations')
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversations_v2',
      filter: `participant_1_id=eq.${userId}`
    }, (payload) => {
      callback(payload.new);
    })
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversations_v2',
      filter: `participant_2_id=eq.${userId}`
    }, (payload) => {
      callback(payload.new);
    })
    .subscribe();
}
```

### 3. 訂閱已讀狀態更新

```javascript
export function subscribeToReadStatus(conversationId, callback) {
  return supabase
    .channel(`conversation_${conversationId}_read`)
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'conversation_messages_v2',
      filter: `conversation_id=eq.${conversationId}`
    }, (payload) => {
      // 只處理已讀狀態變更
      if (payload.new.read_by_participant_1 !== payload.old.read_by_participant_1 ||
          payload.new.read_by_participant_2 !== payload.old.read_by_participant_2) {
        callback(payload.new);
      }
    })
    .subscribe();
}
```

### 4. 完整的訊息頁面範例

```vue
<template>
  <div class="messages-page">
    <div class="message-list">
      <div v-for="msg in messages" :key="msg.message_id">
        {{ msg.content }}
        <span v-if="msg.is_read">✓✓</span>
        <span v-else>✓</span>
      </div>
    </div>
    <input v-model="newMessage" @keyup.enter="sendMessage" />
  </div>
</template>

<script>
import { subscribeToMessages, sendMessage, markAsRead } from '@/api/conversationAPI_v2.js';

export default {
  name: 'MessagesPage',
  props: {
    conversationId: {
      type: Number,
      required: true
    }
  },
  
  data() {
    return {
      messages: [],
      newMessage: '',
      messageSubscription: null,
      readStatusSubscription: null
    };
  },
  
  mounted() {
    this.setupRealtimeSubscriptions();
  },
  
  beforeUnmount() {
    this.cleanupSubscriptions();
  },
  
  methods: {
    setupRealtimeSubscriptions() {
      // 訂閱新訊息
      this.messageSubscription = subscribeToMessages(
        this.conversationId,
        (newMessage) => {
          this.handleNewMessage(newMessage);
        }
      );
      
      // 訂閱已讀狀態
      this.readStatusSubscription = subscribeToReadStatus(
        this.conversationId,
        (updatedMessage) => {
          this.updateMessageReadStatus(updatedMessage);
        }
      );
    },
    
    cleanupSubscriptions() {
      if (this.messageSubscription) {
        this.messageSubscription.unsubscribe();
      }
      if (this.readStatusSubscription) {
        this.readStatusSubscription.unsubscribe();
      }
    },
    
    handleNewMessage(newMessage) {
      // 加入訊息列表
      this.messages.push({
        message_id: newMessage.id,
        content: newMessage.content,
        sender_id: newMessage.sender_id,
        is_mine: newMessage.sender_id === this.$store.state.user.id,
        is_read: false,
        created_at: newMessage.created_at
      });
      
      // 如果不是自己發的訊息,標記為已讀
      if (newMessage.sender_id !== this.$store.state.user.id) {
        markAsRead(this.conversationId, newMessage.id);
      }
      
      // 滾動到底部
      this.$nextTick(() => {
        this.scrollToBottom();
      });
    },
    
    updateMessageReadStatus(updatedMessage) {
      const msg = this.messages.find(m => m.message_id === updatedMessage.id);
      if (msg) {
        msg.is_read = updatedMessage.read_by_participant_1 && 
                      updatedMessage.read_by_participant_2;
      }
    },
    
    async sendMessage() {
      if (!this.newMessage.trim()) return;
      
      try {
        await sendMessage(this.conversationId, this.newMessage);
        this.newMessage = '';
      } catch (error) {
        console.error('Failed to send message:', error);
        this.$notify.error('發送失敗');
      }
    },
    
    scrollToBottom() {
      const container = this.$el.querySelector('.message-list');
      container.scrollTop = container.scrollHeight;
    }
  }
};
</script>
```

---

## 🧪 測試 Realtime

### 測試步驟 1: 基本連接測試

1. 打開瀏覽器開發者工具 (F12)
2. 進入訊息頁面
3. 查看 Console,應該會看到:
   ```
   Subscription status: SUBSCRIBED
   ```

### 測試步驟 2: 雙瀏覽器測試

1. **瀏覽器 A**: 登入用戶 A,進入對話頁面
2. **瀏覽器 B**: 登入用戶 B,進入同一個對話
3. **在瀏覽器 A** 發送訊息
4. **在瀏覽器 B** 應該會立即看到新訊息出現

### 測試步驟 3: 已讀狀態測試

1. 用戶 A 發送訊息 → 應該顯示單勾 ✓
2. 用戶 B 打開對話 → 自動標記為已讀
3. 用戶 A 的訊息應該變成雙勾 ✓✓

### 測試步驟 4: SQL 手動插入測試

在 SQL Editor 中執行:

```sql
-- 插入測試訊息
INSERT INTO public.conversation_messages_v2 (
    conversation_id,
    sender_id,
    content,
    message_type
) VALUES (
    1,  -- 替換為實際的 conversation_id
    auth.uid(),
    'Realtime 測試訊息',
    'text'
);
```

前端應該會立即顯示這則訊息。

---

## ❓ 常見問題

### Q1: 訂閱一直顯示 "CHANNEL_ERROR"

**可能原因:**
- 表未加入 `supabase_realtime` publication
- RLS 策略阻止了訂閱
- 用戶未登入

**解決方法:**
```javascript
// 檢查用戶登入狀態
const { data: { user } } = await supabase.auth.getUser();
console.log('Current user:', user);

// 檢查訂閱狀態
subscription.on('system', (state) => {
  console.log('System state:', state);
});
```

### Q2: 收不到 Realtime 事件

**檢查清單:**
- [ ] 表是否已加入 publication
- [ ] REPLICA IDENTITY 是否設為 FULL
- [ ] RLS 策略是否允許 SELECT
- [ ] Filter 條件是否正確
- [ ] 用戶是否有權限查看該資料

**除錯代碼:**
```javascript
const subscription = supabase
  .channel('debug_channel')
  .on('postgres_changes', {
    event: '*',  // 訂閱所有事件
    schema: 'public',
    table: 'conversation_messages_v2'
  }, (payload) => {
    console.log('Received event:', payload);
  })
  .subscribe((status, err) => {
    console.log('Status:', status);
    if (err) console.error('Error:', err);
  });
```

### Q3: 訂閱太多導致效能問題

**最佳實踐:**
```javascript
// ❌ 不好: 為每個對話創建一個 channel
conversations.forEach(conv => {
  supabase.channel(`conv_${conv.id}`).subscribe();
});

// ✅ 好: 使用單一 channel 訂閱多個 filter
const subscription = supabase
  .channel('all_my_conversations')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'conversation_messages_v2',
    filter: `conversation_id=in.(${conversationIds.join(',')})`
  }, callback)
  .subscribe();
```

### Q4: 如何在開發環境關閉 Realtime

**方法 1: 環境變數控制**
```javascript
const ENABLE_REALTIME = process.env.VUE_APP_ENABLE_REALTIME === 'true';

if (ENABLE_REALTIME) {
  this.subscription = subscribeToMessages(conversationId, callback);
} else {
  // 使用輪詢代替
  this.pollingInterval = setInterval(() => {
    this.fetchMessages();
  }, 3000);
}
```

**方法 2: 從 Dashboard 關閉**
1. 前往 **Database** → **Replication**
2. 編輯 `supabase_realtime` publication
3. 移除對應的表

### Q5: Realtime 訂閱數量限制

**Supabase 限制:**
- Free tier: 每個專案最多 **200 個並發連接**
- Pro tier: 每個專案最多 **500 個並發連接**

**優化建議:**
- 使用單一 channel 訂閱多個 filter
- 不使用時及時 `unsubscribe()`
- 頁面不可見時暫停訂閱

```javascript
// 頁面可見性 API
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    // 頁面隱藏,取消訂閱
    this.subscription?.unsubscribe();
  } else {
    // 頁面顯示,重新訂閱
    this.setupRealtimeSubscriptions();
  }
});
```

---

## 📚 參考資料

- [Supabase Realtime 官方文檔](https://supabase.com/docs/guides/realtime)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [Supabase RLS 策略](https://supabase.com/docs/guides/auth/row-level-security)

---

## 🎯 下一步

1. ✅ 執行 `enable_realtime.sql`
2. ✅ 驗證配置
3. ✅ 在前端實現訂閱
4. ✅ 測試雙瀏覽器通信
5. ✅ 優化效能和用戶體驗

**Happy Coding! 🚀**