# Messaging System v2 實施指南

## 📋 目錄

1. [快速開始](#快速開始)
2. [安裝步驟](#安裝步驟)
3. [數據遷移](#數據遷移)
4. [前端整合](#前端整合)
5. [測試驗證](#測試驗證)
6. [漸進式部署](#漸進式部署)
7. [監控與維護](#監控與維護)
8. [故障排除](#故障排除)

---

## 🚀 快速開始

### 前置需求

- PostgreSQL 14+
- Supabase CLI (可選)
- 現有的 v1 訊息系統正在運行
- Node.js 18+ (前端開發)

### 5 分鐘快速安裝

```bash
# 1. 進入專案目錄
cd backend/database/functions/Message_module

# 2. 執行 v2 安裝腳本
psql -U postgres -d your_database -f migrations/messaging_v2_complete.sql

# 3. 執行數據遷移 (可選)
psql -U postgres -d your_database -c "SELECT * FROM migrate_conversations_v1_to_v2(1000, 0);"

# 4. 驗證安裝
psql -U postgres -d your_database -c "SELECT * FROM verify_migration_v1_to_v2();"
```

---

## 📦 安裝步驟

### Step 1: 備份現有資料

```bash
# 備份 v1 資料表
pg_dump -U postgres -d your_database \
  -t conversations \
  -t conversation_messages \
  --data-only \
  > backup_messaging_v1_$(date +%Y%m%d).sql

# 驗證備份
ls -lh backup_messaging_v1_*.sql
```

### Step 2: 執行 v2 安裝腳本

```bash
# 使用 psql
psql -U postgres -d your_database -f migrations/messaging_v2_complete.sql

# 或使用 Supabase CLI
supabase db push
```

### Step 3: 驗證資料表建立

```sql
-- 檢查資料表是否存在
SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename LIKE '%_v2';

-- 預期輸出:
--  tablename
-- ------------------------
--  conversations_v2
--  conversation_messages_v2
--  conversation_items_v2
```

### Step 4: 驗證 RPC 函數

```sql
-- 檢查 v2 函數
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name LIKE '%_v2';

-- 預期至少包含:
-- - create_or_get_conversation_v2
-- - send_message_v2
-- - get_user_conversations_v2
-- - get_conversation_messages_v2
-- - mark_messages_as_read_v2
-- - get_conversation_items_v2
-- - toggle_conversation_archive_v2
```

---

## 🔄 數據遷移

### 選項 A: 完整遷移 (推薦用於小型資料庫)

```sql
-- 一次性遷移所有資料
SELECT * FROM migrate_conversations_v1_to_v2(10000, 0);

-- 查看結果
-- migrated_conversations | migrated_messages | errors
-- ----------------------|-------------------|--------
--                  1523 |              8945 | {}
```

### 選項 B: 批次遷移 (推薦用於大型資料庫)

```sql
-- 第一批 (0-1000)
SELECT * FROM migrate_conversations_v1_to_v2(1000, 0);

-- 第二批 (1000-2000)
SELECT * FROM migrate_conversations_v1_to_v2(1000, 1000);

-- 第三批 (2000-3000)
SELECT * FROM migrate_conversations_v1_to_v2(1000, 2000);

-- ... 持續直到所有資料遷移完成
```

### 選項 C: 使用腳本自動批次遷移

```bash
#!/bin/bash
# migrate_all.sh

BATCH_SIZE=1000
OFFSET=0
TOTAL=$(psql -U postgres -d your_database -t -c "SELECT COUNT(*) FROM conversations;")

echo "Total conversations to migrate: $TOTAL"

while [ $OFFSET -lt $TOTAL ]; do
    echo "Migrating batch: offset=$OFFSET, size=$BATCH_SIZE"
    
    psql -U postgres -d your_database -c \
        "SELECT * FROM migrate_conversations_v1_to_v2($BATCH_SIZE, $OFFSET);"
    
    OFFSET=$((OFFSET + BATCH_SIZE))
    
    # 避免過載,暫停 1 秒
    sleep 1
done

echo "Migration complete!"
```

### 驗證遷移結果

```sql
-- 執行驗證函數
SELECT * FROM verify_migration_v1_to_v2();

-- 預期所有 is_valid 欄位都是 true
-- check_name              | v1_count | v2_count | is_valid | message
-- ------------------------|----------|----------|----------|------------------
-- Conversation Count      |     1523 |     1450 | true     | v2 should have...
-- Message Count           |     8945 |     8945 | true     | Message counts...
-- Participant Order       |     NULL |        0 | true     | All conversations...
```

### 手動驗證關鍵數據

```sql
-- 檢查是否有遺漏的對話
SELECT COUNT(*) as missing_conversations
FROM public.conversations v1
WHERE NOT EXISTS (
    SELECT 1 
    FROM public.conversations_v2 v2
    WHERE (v2.participant_1_id = v1.buyer_id AND v2.participant_2_id = v1.seller_id)
       OR (v2.participant_1_id = v1.seller_id AND v2.participant_2_id = v1.buyer_id)
);

-- 檢查訊息數量
SELECT 
    'v1' as version,
    COUNT(*) as total_messages
FROM public.conversation_messages
UNION ALL
SELECT 
    'v2' as version,
    COUNT(*) as total_messages
FROM public.conversation_messages_v2;
```

---

## 💻 前端整合

### Step 1: 安裝依賴

```bash
npm install @supabase/supabase-js
```

### Step 2: 建立 v2 API 封裝

建立檔案 `lib/messaging-v2.ts`:

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export class MessagingV2 {
  /**
   * 建立或取得對話
   */
  static async createOrGetConversation(
    otherUserId: string,
    initialItemId?: number
  ) {
    const { data, error } = await supabase.rpc('create_or_get_conversation_v2', {
      p_other_user_id: otherUserId,
      p_initial_item_id: initialItemId || null,
    });

    if (error) throw error;
    return data[0];
  }

  /**
   * 發送訊息
   */
  static async sendMessage(
    conversationId: number,
    content: string,
    options?: {
      messageType?: 'text' | 'image' | 'item_reference';
      relatedItemId?: number;
    }
  ) {
    const { data, error } = await supabase.rpc('send_message_v2', {
      p_conversation_id: conversationId,
      p_content: content,
      p_message_type: options?.messageType || 'text',
      p_related_item_id: options?.relatedItemId || null,
    });

    if (error) throw error;
    return data[0];
  }

  /**
   * 查詢對話列表
   */
  static async getConversations(
    page: number = 1,
    pageSize: number = 20,
    includeArchived: boolean = false
  ) {
    const { data, error } = await supabase.rpc('get_user_conversations_v2', {
      p_page: page,
      p_size: pageSize,
      p_include_archived: includeArchived,
    });

    if (error) throw error;
    return data;
  }

  /**
   * 查詢對話訊息
   */
  static async getMessages(
    conversationId: number,
    page: number = 1,
    pageSize: number = 50
  ) {
    const { data, error } = await supabase.rpc('get_conversation_messages_v2', {
      p_conversation_id: conversationId,
      p_page: page,
      p_size: pageSize,
      p_include_deleted: false,
    });

    if (error) throw error;
    return data;
  }

  /**
   * 標記訊息為已讀
   */
  static async markAsRead(conversationId: number) {
    const { data, error } = await supabase.rpc('mark_messages_as_read_v2', {
      p_conversation_id: conversationId,
    });

    if (error) throw error;
    return data;
  }

  /**
   * 查詢對話中的商品
   */
  static async getConversationItems(conversationId: number) {
    const { data, error } = await supabase.rpc('get_conversation_items_v2', {
      p_conversation_id: conversationId,
    });

    if (error) throw error;
    return data;
  }

  /**
   * 歸檔對話
   */
  static async archiveConversation(
    conversationId: number,
    archived: boolean = true
  ) {
    const { data, error } = await supabase.rpc('toggle_conversation_archive_v2', {
      p_conversation_id: conversationId,
      p_archived: archived,
    });

    if (error) throw error;
    return data;
  }

  /**
   * Realtime 訂閱
   */
  static subscribeToMessages(
    conversationId: number,
    callback: (message: any) => void
  ) {
    return supabase
      .channel(`conversation_v2_${conversationId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'conversation_messages_v2',
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => callback(payload.new)
      )
      .subscribe();
  }
}
```

### Step 3: 建立功能開關

建立檔案 `config/features.ts`:

```typescript
export const FEATURES = {
  // 是否啟用 v2
  USE_MESSAGING_V2: process.env.NEXT_PUBLIC_USE_MESSAGING_V2 === 'true',
  
  // 漸進式推出百分比 (0-100)
  MESSAGING_V2_ROLLOUT_PERCENTAGE: parseInt(
    process.env.NEXT_PUBLIC_MESSAGING_V2_ROLLOUT || '0'
  ),
};
```

### Step 4: 建立適配器 (雙版本支援)

建立檔案 `lib/messaging-adapter.ts`:

```typescript
import { MessagingV1 } from './messaging-v1';
import { MessagingV2 } from './messaging-v2';
import { FEATURES } from '@/config/features';

export class MessagingAdapter {
  private static shouldUseV2(userId: string): boolean {
    if (!FEATURES.USE_MESSAGING_V2) return false;
    
    // 基於用戶 ID 的漸進式推出
    const hash = userId.split('').reduce((acc, char) => 
      acc + char.charCodeAt(0), 0
    );
    const percentage = hash % 100;
    
    return percentage < FEATURES.MESSAGING_V2_ROLLOUT_PERCENTAGE;
  }

  static async createConversation(
    userId: string,
    otherUserId: string,
    itemId?: number
  ) {
    if (this.shouldUseV2(userId)) {
      return MessagingV2.createOrGetConversation(otherUserId, itemId);
    } else {
      return MessagingV1.createOrGetConversation(otherUserId, itemId);
    }
  }

  static async sendMessage(
    userId: string,
    conversationId: number,
    content: string,
    options?: any
  ) {
    if (this.shouldUseV2(userId)) {
      return MessagingV2.sendMessage(conversationId, content, options);
    } else {
      return MessagingV1.sendMessage(conversationId, content);
    }
  }

  // ... 其他方法類似
}
```

### Step 5: 更新 UI 組件

```typescript
// components/ConversationList.tsx
import { useEffect, useState } from 'react';
import { MessagingV2 } from '@/lib/messaging-v2';

export function ConversationList() {
  const [conversations, setConversations] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadConversations();
  }, []);

  async function loadConversations() {
    try {
      const data = await MessagingV2.getConversations(1, 20);
      setConversations(data);
    } catch (error) {
      console.error('Failed to load conversations:', error);
    } finally {
      setLoading(false);
    }
  }

  if (loading) return <div>載入中...</div>;

  return (
    <div className="conversation-list">
      {conversations.map((conv) => (
        <div key={conv.conversation_id} className="conversation-item">
          <h3>{conv.other_user_name}</h3>
          {conv.initial_item_title && (
            <p>關於: {conv.initial_item_title}</p>
          )}
          <p>{conv.last_message_content}</p>
          {conv.unread_count > 0 && (
            <span className="badge">{conv.unread_count}</span>
          )}
        </div>
      ))}
    </div>
  );
}
```

---

## ✅ 測試驗證

### 單元測試

```sql
-- 測試 1: 建立對話
DO $$
DECLARE
    v_result RECORD;
    v_test_user_a UUID := '00000000-0000-0000-0000-000000000001';
    v_test_user_b UUID := '00000000-0000-0000-0000-000000000002';
BEGIN
    -- 設定測試用戶
    SET LOCAL "request.jwt.claims" = json_build_object('sub', v_test_user_a)::text;
    
    -- 建立對話
    SELECT * INTO v_result
    FROM create_or_get_conversation_v2(v_test_user_b, 123);
    
    ASSERT v_result.is_new = true, 'Should create new conversation';
    ASSERT v_result.conversation_id IS NOT NULL, 'Should return conversation_id';
    
    RAISE NOTICE 'Test 1 PASSED: Create conversation';
END $$;

-- 測試 2: 發送訊息
DO $$
DECLARE
    v_conv_id BIGINT;
    v_msg_result RECORD;
BEGIN
    -- 取得測試對話 ID
    SELECT conversation_id INTO v_conv_id
    FROM create_or_get_conversation_v2(
        '00000000-0000-0000-0000-000000000002',
        123
    );
    
    -- 發送訊息
    SELECT * INTO v_msg_result
    FROM send_message_v2(v_conv_id, 'Test message', 'text', NULL);
    
    ASSERT v_msg_result.message_id IS NOT NULL, 'Should return message_id';
    ASSERT v_msg_result.content = 'Test message', 'Content should match';
    
    RAISE NOTICE 'Test 2 PASSED: Send message';
END $$;
```

### 整合測試

```typescript
// __tests__/messaging-v2.test.ts
import { MessagingV2 } from '@/lib/messaging-v2';

describe('Messaging v2', () => {
  it('should create conversation', async () => {
    const result = await MessagingV2.createOrGetConversation(
      'test-user-id',
      123
    );
    
    expect(result.conversation_id).toBeDefined();
    expect(result.is_new).toBe(true);
  });

  it('should send message', async () => {
    const conv = await MessagingV2.createOrGetConversation('test-user-id', 123);
    
    const message = await MessagingV2.sendMessage(
      conv.conversation_id,
      'Hello!',
      { messageType: 'text' }
    );
    
    expect(message.message_id).toBeDefined();
    expect(message.content).toBe('Hello!');
  });

  it('should get conversations', async () => {
    const conversations = await MessagingV2.getConversations(1, 20);
    
    expect(Array.isArray(conversations)).toBe(true);
  });
});
```

### 效能測試

```sql
-- 測試查詢效能
EXPLAIN ANALYZE
SELECT * FROM get_user_conversations_v2(1, 20, false);

-- 預期執行時間應 < 50ms

-- 測試訊息查詢效能
EXPLAIN ANALYZE
SELECT * FROM get_conversation_messages_v2(1, 1, 50, false);

-- 預期執行時間應 < 100ms
```

---

## 📊 漸進式部署

### Week 1: 金絲雀部署 (5%)

```bash
# .env.production
NEXT_PUBLIC_USE_MESSAGING_V2=true
NEXT_PUBLIC_MESSAGING_V2_ROLLOUT=5
```

**監控指標**:
- 錯誤率 < 0.1%
- API 回應時間 < 200ms
- 無用戶投訴

### Week 2: 擴大範圍 (20%)

```bash
NEXT_PUBLIC_MESSAGING_V2_ROLLOUT=20
```

**監控指標**:
- 對話建立成功率 > 99%
- 訊息發送成功率 > 99.5%
- 已讀狀態更新正確率 > 99%

### Week 3: 半數用戶 (50%)

```bash
NEXT_PUBLIC_MESSAGING_V2_ROLLOUT=50
```

**驗證項目**:
- 資料庫負載是否正常
- 是否有異常的慢查詢
- 用戶回饋是否正面

### Week 4: 全面推出 (100%)

```bash
NEXT_PUBLIC_MESSAGING_V2_ROLLOUT=100
```

**最終檢查**:
- 所有功能正常運作
- 效能指標達標
- 無重大 bug

---

## 📈 監控與維護

### 建立監控儀表板

```sql
-- 建立監控視圖
CREATE OR REPLACE VIEW messaging_v2_dashboard AS
SELECT 
    'Total Conversations' as metric,
    COUNT(*)::TEXT as value,
    'count' as type
FROM public.conversations_v2
UNION ALL
SELECT 
    'Active Conversations (7d)',
    COUNT(*)::TEXT,
    'count'
FROM public.conversations_v2
WHERE last_message_at > now() - INTERVAL '7 days'
UNION ALL
SELECT 
    'Messages Today',
    COUNT(*)::TEXT,
    'count'
FROM public.conversation_messages_v2
WHERE created_at > CURRENT_DATE
UNION ALL
SELECT 
    'Avg Response Time (min)',
    ROUND(AVG(response_time))::TEXT,
    'duration'
FROM (
    SELECT 
        EXTRACT(EPOCH FROM (m2.created_at - m1.created_at)) / 60 as response_time
    FROM public.conversation_messages_v2 m1
    JOIN public.conversation_messages_v2 m2 
        ON m1.conversation_id = m2.conversation_id
        AND m2.id = (
            SELECT MIN(id) 
            FROM public.conversation_messages_v2 
            WHERE conversation_id = m1.conversation_id 
            AND id > m1.id 
            AND sender_id != m1.sender_id
        )
    WHERE m1.created_at > now() - INTERVAL '24 hours'
) response_times;

-- 查詢監控資料
SELECT * FROM messaging_v2_dashboard;
```

### 設定告警

```sql
-- 建立告警函數
CREATE OR REPLACE FUNCTION check_messaging_v2_health()
RETURNS TABLE(
    alert_type TEXT,
    severity TEXT,
    message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_error_rate NUMERIC;
    v_slow_queries INT;
BEGIN
    -- 檢查錯誤率
    -- ... 實作邏輯
    
    -- 檢查慢查詢
    -- ... 實作邏輯
    
    RETURN QUERY
    SELECT 'health_check'::TEXT, 'ok'::TEXT, 'System is healthy'::TEXT;
END;
$$;
```

---

## 🔧 故障排除

### 常見問題 1: 遷移失敗

**症狀**: `migrate_conversations_v1_to_v2` 回報錯誤

**解決方案**:
```sql
-- 檢查錯誤詳情
SELECT errors FROM migrate_conversations_v1_to_v2(10, 0);

-- 清理部分遷移的資料
TRUNCATE TABLE conversation_messages_v2;
TRUNCATE TABLE conversation_items_v2;
TRUNCATE TABLE conversations_v2 CASCADE;

-- 重新執行遷移
SELECT * FROM migrate_conversations_v1_to_v2(1000, 0);
```

### 常見問題 2: RPC 函數權限錯誤

**症狀**: `permission denied for function xxx_v2`

**解決方案**:
```sql
-- 授予執行權限
GRANT EXECUTE ON FUNCTION create_or_get_conversation_v2 TO authenticated;
GRANT EXECUTE ON FUNCTION send_message_v2 TO authenticated;
-- ... 其他函數
```

### 常見問題 3: 已讀狀態不正確

**症狀**: 訊息已讀狀態顯示錯誤

**解決方案**:
```sql
-- 檢查參與者順序
SELECT 
    id,
    participant_1_id,
    participant_2_id,
    participant_1_id < participant_2_id as order_correct
FROM conversations_v2
WHERE participant_1_id >= participant_2_id;

-- 如有錯誤,修正資料
-- (不應該發生,因為有 CHECK 約束)
```

### 常見問題 4: 效能下降

**症狀**: 查詢變慢

**解決方案**:
```sql
-- 重建索引
REINDEX TABLE conversations_v2;
REINDEX TABLE conversation_messages_v2;

-- 更新統計資訊
ANALYZE conversations_v2;
ANALYZE conversation_messages_v2;

-- 檢查索引使用情況
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename LIKE '%_v2'
ORDER BY idx_scan DESC;
```

---

## 📞 支援與資源

### 文件
- [完整設計文件](./角色互換改造方案_v2平滑過渡.md)
- [API 參考](./api-reference-v2.md)
- [遷移指南](./migration-guide-v2.md)

### 聯絡方式
- 技術支援: tech-support@example.com
- Bug 回報: GitHub Issues

### 版本歷史
- v2.0.0 (2024-01-XX): 初始發布
- v2.0.1 (TBD): Bug 修復與優化

---

**最後更新**: 2024-01-XX  
**文件版本**: 1.0.0