# 快速修正指南：item_id 模糊錯誤

## 🚨 問題症狀

前端 Console 出現錯誤：
```
Supabase 發起聊天失敗 (Item #70): 
{
  code: '42702',
  message: 'column reference "item_id" is ambiguous'
}
```

## ⚡ 快速修正步驟

### 步驟 1: 開啟 Supabase Dashboard

1. 前往 https://supabase.com/dashboard
2. 選擇您的專案
3. 點擊左側選單的 **SQL Editor**

### 步驟 2: 執行修正腳本

1. 點擊 **New query**
2. 複製以下完整腳本：

```sql
CREATE OR REPLACE FUNCTION public.create_or_get_conversation(
    p_item_id BIGINT
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    buyer_id UUID,
    seller_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_item_user_id UUID;
    v_conversation_id BIGINT;
    v_buyer_id UUID;
    v_seller_id UUID;
    v_created_at TIMESTAMPTZ;
    v_updated_at TIMESTAMPTZ;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 取得物品擁有者（只查詢上架中的物品）
    SELECT i.user_id INTO STRICT v_item_user_id
    FROM public.items i
    WHERE i.id = p_item_id
      AND i.listing_status = true;

    -- 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話'
            USING HINT = '您不能對自己的商品發起對話',
                  ERRCODE = '23514';
    END IF;

    -- 使用 UPSERT 確保原子性
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()
    RETURNING id, buyer_id, seller_id, created_at, updated_at
    INTO v_conversation_id, v_buyer_id, v_seller_id, v_created_at, v_updated_at;

    -- 返回對話資料（使用變數避免欄位名稱衝突）
    RETURN QUERY
    SELECT
        v_conversation_id,
        p_item_id,
        v_buyer_id,
        v_seller_id,
        v_created_at,
        v_updated_at;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '物品不存在或已下架'
            USING HINT = '請確認物品 ID 是否正確且物品處於上架狀態',
                  ERRCODE = '22023';
    WHEN OTHERS THEN
        RAISE NOTICE '建立對話時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;
```

3. 點擊 **Run** 或按 `Ctrl+Enter` (Mac: `Cmd+Enter`)
4. 確認看到 **Success** 訊息

### 步驟 3: 驗證修正

#### 方法 A: 使用 SQL 驗證

在 SQL Editor 執行：

```sql
SELECT 
    proname AS function_name,
    prosrc LIKE '%v_conversation_id%' AS has_fix
FROM pg_proc 
WHERE proname = 'create_or_get_conversation' 
  AND pronamespace = 'public'::regnamespace;
```

**預期結果**: `has_fix` 應該為 `true`

#### 方法 B: 前端測試

1. **清除瀏覽器快取**（重要！）
   - Chrome/Edge: `Ctrl+Shift+Delete` (Mac: `Cmd+Shift+Delete`)
   - 或直接無痕視窗測試
2. **重新整理應用程式**
3. **登入並瀏覽任一物品**
4. **點擊「聯絡賣家」**
5. **檢查 Console**：應該不再出現 42702 錯誤

## ✅ 修正成功指標

- [ ] SQL Editor 顯示 "Success. No rows returned"
- [ ] Console 不再出現 `42702` 錯誤
- [ ] Console 不再出現 "ambiguous" 訊息
- [ ] 可以成功發起對話
- [ ] 重複點擊「聯絡賣家」返回相同對話

## ❌ 如果還是失敗

### 1. 確認專案 ID

```sql
SELECT current_database();
```

確認是否為正確的專案。

### 2. 檢查權限

```sql
SELECT has_function_privilege('create_or_get_conversation(bigint)', 'execute');
```

應該返回 `true`。

### 3. 查看完整錯誤

開啟瀏覽器 Console，展開錯誤物件，檢查：
- `error.code`
- `error.message`
- `error.details`
- `error.hint`

### 4. 檢查資料庫日誌

在 Supabase Dashboard:
1. 前往 **Logs**
2. 選擇 **Postgres Logs**
3. 篩選時間範圍
4. 尋找相關錯誤訊息

## 🔧 替代方案：使用 CLI

如果 Dashboard 無法使用：

```bash
cd backend

# 建立新的 migration
cat > supabase/migrations/$(date +%Y%m%d%H%M%S)_fix_item_id_ambiguous.sql << 'EOF'
-- (貼上上面的完整 SQL 腳本)
EOF

# 套用 migration
supabase db reset
```

## 📚 更多資訊

完整技術文件請參考：
- `backend/docs/HOTFIX_item_id_ambiguous.md`
- `backend/supabase/migrations/HOTFIX_item_id_ambiguous.sql`

## 🆘 需要協助？

如果問題持續發生：

1. **收集資訊**：
   - 完整的錯誤訊息（截圖）
   - 瀏覽器 Console 日誌
   - Supabase Postgres Logs

2. **檢查項目**：
   - 使用者是否已登入？
   - 物品 ID 是否正確？
   - 物品是否處於上架狀態？
   - 是否嘗試對自己的物品發起對話？

3. **聯繫支援**：
   - 提供上述收集的資訊
   - 說明已執行的修正步驟

---

**最後更新**: 2025-01-XX  
**適用版本**: PostgreSQL 17.x, Supabase  
**預計修正時間**: < 5 分鐘