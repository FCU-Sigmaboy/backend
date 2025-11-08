# Conversation Messages 排序方式調查報告

## 📋 執行摘要

**調查日期**: 2025-01-XX  
**調查目標**: 調查 `conversation_messages` 相關 RPC 函數的排序方式  
**主要發現**: 訊息排序為 **降序 (DESC)** - 最新訊息在前

---

## 🔍 調查結果

### 1. 主要函數: `get_conversation_messages`

**函數簽名**:
```sql
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    sender_nickname VARCHAR(50),
    sender_profile_picture TEXT,
    content TEXT,
    sent_at TIMESTAMPTZ,
    is_read BOOLEAN,
    is_deleted BOOLEAN
)
```

**排序方式**:
```sql
ORDER BY cm.sent_at DESC
```

**說明**:
- ✅ **降序排列** (DESC)
- ✅ **最新的訊息排在最前面**
- ✅ **舊訊息排在後面**

---

## 📊 詳細分析

### 排序邏輯

```sql
SELECT
    cm.id AS message_id,
    cm.sender_id AS sender_id,
    u.nickname AS sender_nickname,
    u.profile_picture_url AS sender_profile_picture,
    cm.content AS content,
    cm.sent_at AS sent_at,
    cm.is_read AS is_read,
    (cm.deleted_at IS NOT NULL) AS is_deleted
FROM public.conversation_messages cm
LEFT JOIN public.users u ON cm.sender_id = u.id
WHERE cm.conversation_id = p_conversation_id
  AND (p_include_deleted = true OR cm.deleted_at IS NULL)
ORDER BY cm.sent_at DESC  -- ⭐ 關鍵: 降序排列
LIMIT p_size OFFSET v_offset;
```

### 排序鍵 (Sort Key)

- **欄位**: `sent_at` (TIMESTAMPTZ)
- **方向**: `DESC` (降序)
- **預設值**: `now()` (訊息建立時自動設定)

### 索引支援

檢查是否有相關索引:
```sql
-- 檢查 conversation_messages 的索引
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'conversation_messages'
  AND indexdef LIKE '%sent_at%';
```

**結果**: 
```
idx_conversation_messages_sent_at
CREATE INDEX idx_conversation_messages_sent_at 
ON public.conversation_messages USING btree (sent_at DESC)
```

✅ **有專門的索引支援降序排序**,查詢效能良好

---

## 🎯 使用場景分析

### 場景 1: 聊天室介面

**前端行為**:
```javascript
// 取得最新 50 則訊息
const { data } = await supabase.rpc('get_conversation_messages', {
    p_conversation_id: 21,
    p_page: 1,
    p_size: 50
});

// data[0] = 最新的訊息
// data[49] = 第 50 新的訊息
```

**顯示方式**:
- 前端可能需要 **反轉陣列** (`data.reverse()`) 來讓最舊的訊息在上方
- 或者使用 CSS `flex-direction: column-reverse` 來顯示

### 場景 2: 分頁載入

**第一頁** (p_page = 1):
```
返回: 訊息 #100, #99, #98, ..., #51  (最新的 50 則)
```

**第二頁** (p_page = 2):
```
返回: 訊息 #50, #49, #48, ..., #1  (接下來的 50 則)
```

**優點**:
- ✅ 預設載入最新訊息
- ✅ 符合一般聊天應用的使用習慣
- ✅ 減少不必要的資料載入

---

## 📝 相關函數

### 1. `send_message`

**排序**: N/A (單筆插入,返回新訊息)

```sql
CREATE OR REPLACE FUNCTION public.send_message(
    p_conversation_id BIGINT,
    p_content TEXT
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ
)
```

**說明**:
- 插入新訊息時,`sent_at` 自動設為 `now()`
- 返回單筆新訊息,無排序需求

### 2. Realtime 訂閱

**前端訂閱方式**:
```javascript
supabase
  .channel(`conversation:${conversationId}`)
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'conversation_messages',
      filter: `conversation_id=eq.${conversationId}`
    },
    (payload) => {
      // 收到新訊息: payload.new
      // 通常會 append 到訊息列表最下方
    }
  )
  .subscribe();
```

**說明**:
- 即時訊息透過 Supabase Realtime 推送
- 不受 RPC 函數排序影響
- 前端自行決定插入位置

---

## 🔄 排序方向比較

### 降序 (DESC) - 目前使用 ✅

**優點**:
- ✅ 預設載入最新訊息
- ✅ 符合「向上滑動載入更多」的 UX 模式
- ✅ 首次進入聊天室立即看到最新對話
- ✅ 減少初始載入時間

**缺點**:
- ⚠️ 前端需要反轉陣列或使用 CSS 技巧
- ⚠️ 分頁邏輯可能較不直觀

### 升序 (ASC) - 替代方案

**優點**:
- ✅ 前端直接使用,無需反轉
- ✅ 分頁邏輯直觀 (第 1 頁 = 最舊訊息)

**缺點**:
- ❌ 預設載入最舊訊息 (不符合聊天應用習慣)
- ❌ 需要計算總頁數才能跳到最新訊息
- ❌ 初次載入體驗差

---

## 💡 建議

### 1. 維持目前的降序排列

**理由**:
- 符合聊天應用的標準 UX
- 效能良好 (有索引支援)
- 前端處理簡單 (反轉或 CSS)

### 2. 前端處理建議

**選項 A: 反轉陣列**
```javascript
const messages = data.reverse(); // 最舊在前,最新在後
```

**選項 B: CSS 反轉**
```css
.message-container {
  display: flex;
  flex-direction: column-reverse;
}
```

**選項 C: 插入順序**
```javascript
messages.forEach(msg => {
  messageList.prepend(msg); // 在頂部插入
});
```

### 3. 分頁最佳實務

**初始載入**:
```javascript
// 載入最新 50 則訊息
const initialMessages = await getConversationMessages(conversationId, 1, 50);
```

**向上滑動載入更多**:
```javascript
let currentPage = 1;

onScrollToTop(() => {
  currentPage++;
  const olderMessages = await getConversationMessages(conversationId, currentPage, 50);
  // 插入到現有訊息的上方
});
```

---

## 🔧 自訂排序 (如需要)

如果需要改變排序方向,可以執行以下修正:

```sql
-- 修改為升序 (ASC)
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (...)
AS $$
BEGIN
    ...
    RETURN QUERY
    SELECT ...
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
      AND (p_include_deleted = true OR cm.deleted_at IS NULL)
    ORDER BY cm.sent_at ASC  -- 改為升序
    LIMIT p_size OFFSET v_offset;
END;
$$;
```

**⚠️ 注意**: 改變排序方向需要同步更新前端邏輯!

---

## 📈 效能考量

### 索引使用情況

```sql
-- 檢查查詢計畫
EXPLAIN ANALYZE
SELECT cm.id, cm.content, cm.sent_at
FROM conversation_messages cm
WHERE cm.conversation_id = 21
  AND cm.deleted_at IS NULL
ORDER BY cm.sent_at DESC
LIMIT 50;
```

**預期結果**:
```
Index Scan using idx_conversation_messages_sent_at
  Filter: (conversation_id = 21) AND (deleted_at IS NULL)
  Rows: 50
  Cost: ~0.42..8.44
```

✅ **效能良好** - 使用索引掃描

### 優化建議

1. **複合索引** (如訊息量很大):
```sql
CREATE INDEX idx_conversation_messages_conv_sent 
ON conversation_messages (conversation_id, sent_at DESC)
WHERE deleted_at IS NULL;
```

2. **分頁大小建議**:
- 建議: 20-50 則/頁
- 最大: 100 則/頁 (函數已限制)
- 原因: 平衡載入速度與使用體驗

---

## 🎓 總結

| 項目 | 值 |
|------|-----|
| **排序欄位** | `sent_at` (TIMESTAMPTZ) |
| **排序方向** | `DESC` (降序) |
| **最新訊息** | 在陣列的 `[0]` 位置 |
| **最舊訊息** | 在陣列的最後位置 |
| **索引支援** | ✅ 有 (`idx_conversation_messages_sent_at`) |
| **效能** | ✅ 良好 |
| **是否需要修改** | ❌ 不需要,目前設計合理 |

---

## 📚 相關檔案

- **RPC 函數定義**: `backend/supabase/migrations/20251108130000_fix_all_ambiguous_columns_messaging_jo.sql`
- **前端呼叫**: `backend/contracts/conversationAPI/conversationAPI.js`
- **資料表結構**: `backend/supabase/migrations/20251025092807_create_initial_schema.sql`

---

**報告產生日期**: 2025-01-XX  
**資料庫版本**: PostgreSQL 17.6.1  
**Supabase 專案**: rsubfpxltwkrdejnvzxw