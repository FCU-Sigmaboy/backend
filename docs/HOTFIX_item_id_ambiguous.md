# HOTFIX: 修正 item_id 模糊錯誤 (42702)

## 問題描述

當使用者點擊「聯絡賣家」按鈕發起聊天時，前端收到以下錯誤：

```
Supabase 發起聊天失敗 (Item #70): 
{
  code: '42702',
  details: 'It could refer to either a PL/pgSQL variable or a table column.',
  hint: null,
  message: 'column reference "item_id" is ambiguous'
}
```

## 錯誤分析

### 根本原因

PostgreSQL 錯誤碼 `42702` 表示「欄位參考模糊不清」。這個錯誤發生在 `create_or_get_conversation` RPC 函數中。

問題出在 PostgreSQL 的作用域規則：

1. **RETURNS TABLE 定義的欄位名稱會被引入函數作用域**
   ```sql
   RETURNS TABLE (
       conversation_id BIGINT,
       item_id BIGINT,        -- 這個名稱被引入作用域
       buyer_id UUID,
       ...
   )
   ```

2. **在 RETURN QUERY SELECT 中使用相同名稱時產生衝突**
   ```sql
   RETURN QUERY
   SELECT
       c.id,
       c.item_id,     -- ❌ PostgreSQL 無法判斷這是指：
                      --    1. RETURNS TABLE 的輸出欄位 item_id？
                      --    2. conversations 資料表的欄位 c.item_id？
       ...
   FROM conversations c
   WHERE c.id = v_conversation_id;
   ```

### 為什麼之前的 CTE 方案無效

即使使用 CTE (Common Table Expression)，只要 SELECT 語句中的欄位名稱與 RETURNS TABLE 定義的名稱相同，衝突依然存在：

```sql
-- ❌ 這樣還是會有問題
RETURN QUERY
WITH conversation_data AS (...)
SELECT
    cd.id,
    cd.item_id,      -- 依然與 RETURNS TABLE 的 item_id 衝突
    ...
FROM conversation_data cd;
```

## 解決方案

### 核心思路

**完全避免在 RETURN QUERY SELECT 中使用與 RETURNS TABLE 相同的欄位名稱。**

改用區域變數儲存所有需要的值，然後直接返回這些變數。

### 修正後的程式碼

```sql
DECLARE
    v_current_uid UUID := auth.uid();
    v_item_user_id UUID;
    v_conversation_id BIGINT;
    v_buyer_id UUID;
    v_seller_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
BEGIN
    -- ... 驗證邏輯 ...

    -- 使用 RETURNING 一次取得所有需要的值
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()
    RETURNING
        id,
        buyer_id,
        seller_id,
        created_at,
        updated_at
    INTO
        v_conversation_id,
        v_buyer_id,
        v_seller_id,
        v_created_at,
        v_updated_at;

    -- ✅ 直接使用變數，完全避免欄位名稱衝突
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

### 關鍵改進點

1. **使用 RETURNING INTO**：一次取得 INSERT/UPDATE 的所有結果
2. **直接返回變數**：RETURN QUERY SELECT 只使用變數，不查詢資料表
3. **item_id 使用輸入參數**：`p_item_id` 本來就是已知值，無需再查詢

## 執行修正

### 方法 1: 使用 Supabase Dashboard（推薦）

1. 登入 Supabase Dashboard
2. 前往 **SQL Editor**
3. 開啟新的查詢
4. 複製 `backend/supabase/migrations/HOTFIX_item_id_ambiguous.sql` 的全部內容
5. 貼上並執行
6. 檢查執行結果訊息

### 方法 2: 使用 Supabase CLI

```bash
cd backend
supabase db reset  # 重置並重新套用所有 migrations
```

## 驗證修正

### 1. 檢查函數是否更新

在 SQL Editor 執行：

```sql
SELECT prosrc 
FROM pg_proc 
WHERE proname = 'create_or_get_conversation' 
  AND pronamespace = 'public'::regnamespace;
```

確認函數原始碼包含 `v_conversation_id` 等變數。

### 2. 測試功能

1. **重新整理前端應用程式**（清除快取）
2. **登入並瀏覽任一物品頁面**
3. **點擊「聯絡賣家」按鈕**
4. **檢查 Console**：
   - ✅ 應該不再出現 `42702` 錯誤
   - ✅ 應該不再出現 "ambiguous" 訊息
   - ✅ 應該看到成功的 RPC 回應

### 3. 預期行為

- **首次發起對話**：建立新的對話記錄
- **重複發起對話**：返回既有對話，並更新 `updated_at`
- **錯誤處理**：
  - 未登入 → `使用者未登入`
  - 自己的物品 → `無法與自己的物品建立對話`
  - 物品不存在 → `物品不存在或已下架`

## 相關檔案

- **修正腳本**: `backend/supabase/migrations/HOTFIX_item_id_ambiguous.sql`
- **函數定義**: `backend/supabase/migrations/20251029091800_setup_messaging_feature.sql`
- **前端呼叫**: `backend/contracts/conversationAPI/conversationAPI.js`

## 學習要點

### PostgreSQL 函數開發最佳實務

1. **避免 RETURNS TABLE 欄位名稱與內部查詢衝突**
   - 使用不同的欄位名稱（如加上前綴）
   - 或使用變數返回值（推薦）

2. **善用 RETURNING INTO**
   - 減少查詢次數
   - 獲取剛插入/更新的完整資料

3. **明確的作用域管理**
   - 所有變數使用 `v_` 前綴
   - 所有參數使用 `p_` 前綴
   - 避免命名衝突

4. **型別明確性**
   - 雖然 PostgreSQL 可以自動推斷型別
   - 但明確指定可避免隱藏的型別轉換問題

## 參考資源

- [PostgreSQL Error Codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)
- [PL/pgSQL Functions - Returning from a Function](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-STATEMENTS-RETURNING)
- [Supabase Database Functions](https://supabase.com/docs/guides/database/functions)

## 修正時間

- **發現時間**: 2025-01-XX
- **修正時間**: 2025-01-XX
- **影響範圍**: `create_or_get_conversation` RPC 函數
- **影響功能**: 發起聊天、聯絡賣家