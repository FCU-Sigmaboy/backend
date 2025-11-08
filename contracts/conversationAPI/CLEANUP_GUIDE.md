# 刪除棄用函數操作指南

## 📋 概述

本指南說明如何安全地刪除 `conversations` 和 `conversation_messages` 相關的棄用 RPC 函數。

**相關文件:**
- 評估報告: `DEPRECATED_FUNCTIONS_EVALUATION.md`
- 清理 Migration: `20251109000000_cleanup_deprecated_functions_jo.sql`

---

## ⚠️ 執行前檢查清單

在執行清理 migration 之前，請確認以下事項：

### 1. 資料庫備份 ✅
```bash
# 使用 Supabase CLI 備份資料庫
supabase db dump -f backup_before_cleanup_$(date +%Y%m%d).sql

# 或使用 PostgreSQL pg_dump
pg_dump -h <host> -U <user> -d <database> > backup.sql
```

### 2. 前端程式碼已更新 ✅

確認前端程式碼不再使用舊版本函數簽名：

**已棄用的呼叫方式:**
```typescript
// ❌ 不要再使用
await supabase.rpc('get_user_conversations', {
  p_page: 1,
  p_size: 20
});

await supabase.rpc('get_conversation_messages', {
  p_conversation_id: id,
  p_page: 1,
  p_size: 50
});
```

**新版本呼叫方式:**
```typescript
// ✅ 使用新版本（向後相容）
await supabase.rpc('get_user_conversations', {
  p_page: 1,
  p_size: 20,
  p_role: 'all',              // 可選，預設 'all'
  p_include_deleted: false    // 可選，預設 false
});

await supabase.rpc('get_conversation_messages', {
  p_conversation_id: id,
  p_page: 1,
  p_size: 50,
  p_include_deleted: false    // 可選，預設 false
});
```

### 3. 測試環境驗證 ✅

建議先在開發/測試環境執行，確認無誤後再部署到生產環境。

---

## 🚀 執行步驟

### 方法 1: 使用 Supabase CLI (推薦)

```bash
# 1. 確保 CLI 已安裝並登入
supabase login

# 2. 連結到您的專案
supabase link --project-ref <your-project-ref>

# 3. 應用 migration
supabase db push

# 4. 或者單獨執行這個 migration
supabase db push --include-all
```

### 方法 2: 使用 Supabase Dashboard

1. 登入 [Supabase Dashboard](https://app.supabase.com/)
2. 選擇您的專案
3. 前往 **SQL Editor**
4. 複製 `20251109000000_cleanup_deprecated_functions_jo.sql` 的內容
5. 貼上並執行

### 方法 3: 使用 PostgreSQL 客戶端

```bash
# 使用 psql
psql -h <host> -U <user> -d <database> -f backend/supabase/migrations/20251109000000_cleanup_deprecated_functions_jo.sql

# 或使用環境變數
psql $DATABASE_URL -f backend/supabase/migrations/20251109000000_cleanup_deprecated_functions_jo.sql
```

---

## 📊 Migration 執行內容

### 會執行的操作:

1. **刪除舊版本函數** ✂️
   - `get_user_conversations(INT, INT)`
   - `get_conversation_messages(BIGINT, INT, INT)`

2. **改進觸發器函數** 🔧
   - `update_conversation_timestamp()` - 新增軟刪除支援

3. **優化現有函數** ⚡
   - `mark_messages_as_read()` - 忽略已刪除訊息
   - `get_unread_message_count()` - 忽略已刪除訊息和對話

4. **建立管理工具** 🛠️
   - `conversation_functions_inventory` - 函數清單視圖
   - `check_conversation_data_integrity()` - 資料完整性檢查函數

---

## ✅ 執行後驗證

### 1. 檢查函數清單

執行以下 SQL 查詢，確認所有函數都已正確更新：

```sql
-- 查看所有對話相關函數
SELECT * FROM public.conversation_functions_inventory
ORDER BY function_name;
```

**預期結果:** 應該看到 12 個函數，且沒有舊版本簽名

### 2. 檢查資料完整性

```sql
-- 執行完整性檢查
SELECT * FROM public.check_conversation_data_integrity();
```

**預期結果:**
```
check_name                      | status    | details
--------------------------------|-----------|---------------------------
孤立訊息檢查                     | ✅ 通過   | 發現 0 筆孤立訊息
已刪除對話中的未刪除訊息          | ✅ 通過   | 發現 0 筆未刪除訊息...
重複對話檢查                     | ✅ 通過   | 發現 0 組重複對話
軟刪除對話統計                   | 📊 資訊   | X 筆對話被至少一方刪除
軟刪除訊息統計                   | 📊 資訊   | X 筆訊息被刪除
```

### 3. 測試函數功能

```sql
-- 測試取得對話列表（新參數）
SELECT * FROM public.get_user_conversations(
    p_page := 1,
    p_size := 10,
    p_role := 'all',
    p_include_deleted := false
);

-- 測試標記已讀
SELECT * FROM public.mark_messages_as_read(p_conversation_id := 1);

-- 測試未讀數量
SELECT * FROM public.get_unread_message_count();
```

---

## 🔍 故障排除

### 問題 1: Migration 執行失敗

**錯誤訊息:**
```
ERROR: function "get_user_conversations(integer, integer)" does not exist
```

**解決方法:**
這是正常的，表示舊函數已經在之前的 migration 中被刪除了。Migration 會自動處理這種情況。

### 問題 2: 權限錯誤

**錯誤訊息:**
```
ERROR: permission denied for function ...
```

**解決方法:**
```sql
-- 手動授予權限
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_message_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_conversation_data_integrity() TO authenticated;
```

### 問題 3: 前端出現 400 錯誤

**可能原因:**
- 前端仍在使用舊版本函數簽名
- 參數名稱不正確

**解決方法:**
```typescript
// 檢查前端程式碼，確保使用正確的參數名稱
const { data, error } = await supabase.rpc('get_user_conversations', {
  p_page: 1,        // ✅ 正確
  p_size: 20,       // ✅ 正確
  p_role: 'all',    // ✅ 正確（新增）
  p_include_deleted: false  // ✅ 正確（新增）
});

if (error) {
  console.error('詳細錯誤:', error);
}
```

---

## 📈 效能監控

執行清理後，建議監控以下指標：

### 1. 查詢效能

```sql
-- 檢查慢查詢
SELECT
    calls,
    total_time,
    mean_time,
    query
FROM pg_stat_statements
WHERE query LIKE '%conversation%'
ORDER BY mean_time DESC
LIMIT 10;
```

### 2. 索引使用率

```sql
-- 檢查索引效能
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename IN ('conversations', 'conversation_messages')
ORDER BY idx_scan DESC;
```

### 3. 軟刪除資料量

```sql
-- 監控軟刪除資料增長
SELECT
    '對話' as type,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE deleted_by_buyer_at IS NOT NULL OR deleted_by_seller_at IS NOT NULL) as soft_deleted,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deleted_by_buyer_at IS NOT NULL OR deleted_by_seller_at IS NOT NULL) / NULLIF(COUNT(*), 0), 2) as deleted_percentage
FROM public.conversations
UNION ALL
SELECT
    '訊息' as type,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) as soft_deleted,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) / NULLIF(COUNT(*), 0), 2) as deleted_percentage
FROM public.conversation_messages;
```

---

## 🧹 定期維護

### 設定自動清理任務

建議每月執行一次清理，刪除雙方都已刪除超過 30 天的對話：

#### 方法 1: 使用 Supabase Edge Function (推薦)

```typescript
// supabase/functions/cleanup-conversations/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  const { data, error } = await supabaseClient.rpc('cleanup_deleted_conversations', {
    p_days_threshold: 30
  })

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }

  return new Response(JSON.stringify(data), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

然後使用 Supabase 的 Cron Job 功能定期執行。

#### 方法 2: 使用 pg_cron (如果可用)

```sql
-- 每月 1 號凌晨 2 點執行清理
SELECT cron.schedule(
    'cleanup-deleted-conversations',
    '0 2 1 * *',
    $$
    SELECT public.cleanup_deleted_conversations(30);
    $$
);
```

---

## 📝 回滾計畫

如果需要回滾此 migration，請執行以下步驟：

### 1. 恢復舊版本函數

```sql
-- 恢復 get_user_conversations(INT, INT)
CREATE OR REPLACE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    -- ... (完整定義請參考 20251029091800_setup_messaging_feature.sql)
)
LANGUAGE plpgsql STABLE
AS $$
-- ... 函數體
$$;

-- 恢復 get_conversation_messages(BIGINT, INT, INT)
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50
)
RETURNS TABLE (
    -- ... (完整定義請參考 20251029091800_setup_messaging_feature.sql)
)
LANGUAGE plpgsql STABLE
AS $$
-- ... 函數體
$$;
```

### 2. 從備份恢復（最安全）

```bash
# 恢復整個資料庫
psql $DATABASE_URL < backup_before_cleanup_YYYYMMDD.sql
```

---

## 🎯 檢查清單

執行後請確認以下項目：

### 資料庫層級
- [ ] Migration 執行成功，無錯誤訊息
- [ ] 舊版本函數已被刪除
- [ ] 新版本函數運作正常
- [ ] 資料完整性檢查通過
- [ ] 權限設定正確

### 應用程式層級
- [ ] 前端可以正常取得對話列表
- [ ] 前端可以正常取得訊息列表
- [ ] 發送訊息功能正常
- [ ] 標記已讀功能正常
- [ ] 未讀數量顯示正確
- [ ] 軟刪除功能正常（如已實作）

### 效能與監控
- [ ] 查詢效能符合預期
- [ ] 索引使用率正常
- [ ] 已設定定期清理任務（可選）
- [ ] 已建立監控告警（可選）

---

## 📚 相關資源

- **評估報告:** `DEPRECATED_FUNCTIONS_EVALUATION.md`
- **清理 Migration:** `20251109000000_cleanup_deprecated_functions_jo.sql`
- **原始設定:** `20251029091800_setup_messaging_feature.sql`
- **軟刪除功能:** `20251108052733_feature_conversation_soft_delete_jo.sql`
- **最終修復:** `20251108130000_fix_all_ambiguous_columns_messaging_jo.sql`

---

## 💡 最佳實踐建議

1. **總是先在測試環境執行** - 確保沒有未預期的問題
2. **執行前備份資料庫** - 萬一需要回滾可以快速恢復
3. **分批部署** - 先部署資料庫，確認無誤後再部署前端
4. **監控錯誤率** - 部署後密切關注應用程式錯誤日誌
5. **設定定期清理** - 避免軟刪除資料無限增長

---

## 🆘 需要協助？

如果遇到問題，請聯絡：

- **Backend Team** - 資料庫相關問題
- **Frontend Team** - 前端整合問題
- **DevOps Team** - 部署與基礎設施問題

---

**文件版本:** 1.0  
**最後更新:** 2024-11-09  
**維護者:** Backend Team