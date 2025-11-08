# item_id 模糊錯誤修正總結

## 📋 問題概述

**錯誤訊息**:
```
code: '42702'
message: 'column reference "item_id" is ambiguous'
details: 'It could refer to either a PL/pgSQL variable or a table column.'
```

**影響功能**: 使用者點擊「聯絡賣家」按鈕時無法發起聊天

**影響範圍**: `create_or_get_conversation` RPC 函數

---

## 🔍 根本原因

PostgreSQL 的 `RETURNS TABLE` 會將輸出欄位名稱引入函數作用域，導致與 SQL 查詢中的資料表欄位名稱產生衝突。

### 錯誤的寫法 ❌

```sql
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,        -- 這個名稱被引入作用域
    ...
)
...
RETURN QUERY
SELECT
    c.id,
    c.item_id,             -- ❌ PostgreSQL 無法判斷是指：
                           --    1. RETURNS TABLE 的 item_id
                           --    2. conversations 表的 c.item_id
    ...
FROM conversations c;
```

---

## ✅ 解決方案

使用區域變數儲存所有返回值，避免直接在 `RETURN QUERY SELECT` 中查詢資料表。

### 正確的寫法 ✅

```sql
DECLARE
    v_conversation_id BIGINT;
    v_buyer_id UUID;
    v_seller_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
BEGIN
    -- 使用 RETURNING INTO 一次取得所有值
    INSERT INTO conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()
    RETURNING id, buyer_id, seller_id, created_at, updated_at
    INTO v_conversation_id, v_buyer_id, v_seller_id, v_created_at, v_updated_at;

    -- ✅ 直接返回變數，完全避免名稱衝突
    RETURN QUERY
    SELECT
        v_conversation_id,    -- conversation_id
        p_item_id,            -- item_id (使用輸入參數)
        v_buyer_id,           -- buyer_id
        v_seller_id,          -- seller_id
        v_created_at,         -- created_at
        v_updated_at;         -- updated_at
END;
```

---

## 🚀 快速修正步驟

### 步驟 1: 開啟 Supabase Dashboard

1. 前往 https://supabase.com/dashboard
2. 選擇您的專案 (rsubfpxltwkrdejnvzxw)
3. 點擊 **SQL Editor**

### 步驟 2: 執行修正腳本

1. 複製檔案內容: `backend/supabase/migrations/HOTFIX_item_id_ambiguous.sql`
2. 貼到 SQL Editor 並執行
3. 確認看到 "Success" 訊息

### 步驟 3: 驗證修正

1. 清除瀏覽器快取
2. 重新整理應用程式
3. 登入並點擊「聯絡賣家」
4. 確認 Console 不再出現 42702 錯誤

---

## 📁 相關檔案

| 檔案 | 用途 |
|------|------|
| `backend/supabase/migrations/HOTFIX_item_id_ambiguous.sql` | 修正腳本（可直接在 Dashboard 執行） |
| `backend/docs/HOTFIX_item_id_ambiguous.md` | 完整技術文件 |
| `backend/docs/QUICK_FIX_GUIDE.md` | 快速修正指南 |
| `backend/contracts/conversationAPI/conversationAPI.js` | 前端呼叫此 RPC 的位置 |

---

## 🧪 測試清單

修正後請驗證以下功能：

- [ ] 首次發起對話 → 建立新對話
- [ ] 重複發起對話 → 返回既有對話，更新 `updated_at`
- [ ] 未登入 → 顯示「使用者未登入」錯誤
- [ ] 對自己的物品 → 顯示「無法與自己的物品建立對話」
- [ ] 物品已下架 → 顯示「物品不存在或已下架」
- [ ] Console 無 42702 錯誤
- [ ] Console 無 "ambiguous" 訊息

---

## 💡 學習要點

### PostgreSQL 函數開發最佳實務

1. **避免名稱衝突**
   - RETURNS TABLE 的欄位名稱會被引入函數作用域
   - 使用變數返回值，避免在 RETURN QUERY SELECT 中使用相同名稱

2. **善用 RETURNING INTO**
   - 減少查詢次數，提升效能
   - 一次取得 INSERT/UPDATE 的所有結果

3. **命名慣例**
   - 變數: `v_` 前綴 (如 `v_conversation_id`)
   - 參數: `p_` 前綴 (如 `p_item_id`)
   - 避免與資料表欄位同名

4. **CTE 不是萬能解**
   - CTE 可以改善查詢結構，但無法解決 RETURNS TABLE 的名稱衝突
   - 根本解決方案是使用變數

---

## 📊 修正前後對比

### 修正前 ❌
```sql
-- 使用 CTE，但仍有名稱衝突
RETURN QUERY
WITH conversation_data AS (
    SELECT c.id, c.item_id, ...
    FROM conversations c
    WHERE c.id = v_conversation_id
)
SELECT cd.id, cd.item_id, ...  -- ❌ item_id 衝突
FROM conversation_data cd;
```

### 修正後 ✅
```sql
-- 使用變數，完全避免衝突
RETURN QUERY
SELECT
    v_conversation_id,  -- ✅ 使用變數
    p_item_id,          -- ✅ 使用參數
    v_buyer_id,         -- ✅ 使用變數
    ...
```

---

## 🔗 參考資源

- [PostgreSQL Error Codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
- [PL/pgSQL Functions](https://www.postgresql.org/docs/current/plpgsql-control-structures.html)
- [Supabase Database Functions](https://supabase.com/docs/guides/database/functions)
- [PostgreSQL RETURNING Clause](https://www.postgresql.org/docs/current/dml-returning.html)

---

## 📞 支援

如果問題持續發生，請檢查：

1. **函數是否正確更新**
   ```sql
   SELECT prosrc FROM pg_proc 
   WHERE proname = 'create_or_get_conversation';
   ```

2. **權限是否正確**
   ```sql
   SELECT has_function_privilege(
       'create_or_get_conversation(bigint)', 
       'execute'
   );
   ```

3. **收集錯誤資訊**
   - 瀏覽器 Console 完整錯誤
   - Supabase Dashboard > Logs > Postgres Logs
   - 使用者登入狀態
   - 物品 ID 和狀態

---

**修正日期**: 2025-01-XX  
**PostgreSQL 版本**: 17.6.1  
**Supabase 專案**: rsubfpxltwkrdejnvzxw  
**預計修正時間**: < 5 分鐘