-- =====================================================
-- 終極修正: 使用 OUT 參數解決 item_id 模糊問題
-- =====================================================
-- 錯誤碼: 42702
-- 錯誤訊息: column reference "item_id" is ambiguous
--
-- 根本原因:
--   RETURNS TABLE 的欄位名稱 (如 item_id) 會被引入函數作用域,
--   即使在 SELECT 中使用參數 p_item_id，PostgreSQL 仍會產生衝突。
--
-- 最終解決方案:
--   使用 OUT 參數代替 RETURNS TABLE，完全避免欄位名稱衝突
--
-- 執行方式:
--   1. 複製此檔案的全部內容
--   2. 前往 Supabase Dashboard > SQL Editor
--   3. 貼上並執行
--
-- 日期: 2025-01-XX
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_or_get_conversation(
    p_item_id BIGINT,
    OUT conversation_id BIGINT,
    OUT item_id BIGINT,
    OUT buyer_id UUID,
    OUT seller_id UUID,
    OUT created_at TIMESTAMPTZ,
    OUT updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_item_user_id UUID;
BEGIN
    -- 1. 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 2. 取得物品擁有者（只查詢上架中的物品）
    SELECT i.user_id INTO STRICT v_item_user_id
    FROM public.items i
    WHERE i.id = p_item_id
      AND i.listing_status = true;

    -- 3. 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話'
            USING HINT = '您不能對自己的商品發起對話',
                  ERRCODE = '23514';
    END IF;

    -- 4. 使用 UPSERT 確保原子性和併發安全
    --    利用 UNIQUE(item_id, buyer_id) 索引處理衝突
    INSERT INTO public.conversations
        (item_id, buyer_id, seller_id)
    VALUES
        (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET
        updated_at = now()
    RETURNING
        id,
        conversations.item_id,  -- 使用資料表限定名稱
        conversations.buyer_id,
        conversations.seller_id,
        conversations.created_at,
        conversations.updated_at
    INTO
        conversation_id,        -- OUT 參數
        item_id,                -- OUT 參數
        buyer_id,               -- OUT 參數
        seller_id,              -- OUT 參數
        created_at,             -- OUT 參數
        updated_at;             -- OUT 參數

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '物品不存在或已下架'
            USING HINT = '請確認物品 ID 是否正確且物品處於上架狀態',
                  ERRCODE = '22023';
    WHEN OTHERS THEN
        -- 記錄錯誤資訊並重新拋出
        RAISE NOTICE '建立對話時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

-- 更新函數說明
COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話，使用 UPSERT 搭配唯一索引確保原子性。

參數:
  - p_item_id: 物品 ID

返回 (OUT 參數):
  - conversation_id: 對話 ID
  - item_id: 物品 ID
  - buyer_id: 買家 ID
  - seller_id: 賣家 ID
  - created_at: 建立時間
  - updated_at: 更新時間

安全性:
  - 自動驗證使用者登入狀態
  - 防止對自己的物品發起對話
  - 只能對上架中的物品發起對話

併發安全:
  - 使用 UPSERT 機制，透過唯一索引避免重複建立

錯誤處理:
  - 42501: 使用者未登入
  - 23514: 嘗試與自己的物品建立對話
  - 22023: 物品不存在或已下架

修正歷史:
  - 2025-01-XX: 使用 OUT 參數代替 RETURNS TABLE，徹底解決 42702 錯誤';

-- =====================================================
-- 驗證修正結果
-- =====================================================
DO $$
DECLARE
    v_function_exists BOOLEAN;
    v_function_result TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證修正結果';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查函數是否存在
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname = 'create_or_get_conversation'
    ) INTO v_function_exists;

    IF v_function_exists THEN
        -- 檢查函數返回類型
        SELECT pg_get_function_result(p.oid) INTO v_function_result
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname = 'create_or_get_conversation';

        RAISE NOTICE '✅ 函數已成功更新';
        RAISE NOTICE '';
        RAISE NOTICE '函數名稱: create_or_get_conversation';
        RAISE NOTICE '返回類型: %', v_function_result;
        RAISE NOTICE '';

        IF v_function_result LIKE '%conversation_id bigint%OUT item_id bigint%' THEN
            RAISE NOTICE '✅ 使用 OUT 參數版本 (正確)';
        ELSIF v_function_result LIKE '%TABLE(%' THEN
            RAISE WARNING '⚠️  仍使用 TABLE 版本 (可能有問題)';
        END IF;

        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE '  下一步測試';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE '1. 清除瀏覽器快取 (Ctrl+Shift+Delete)';
        RAISE NOTICE '2. 重新整理應用程式';
        RAISE NOTICE '3. 登入並瀏覽物品頁面';
        RAISE NOTICE '4. 點擊「聯絡賣家」按鈕';
        RAISE NOTICE '5. 檢查 Console 是否還有 42702 錯誤';
        RAISE NOTICE '';
        RAISE NOTICE '預期結果:';
        RAISE NOTICE '  ✓ 無 42702 錯誤';
        RAISE NOTICE '  ✓ 無 "ambiguous" 訊息';
        RAISE NOTICE '  ✓ 成功建立對話';
        RAISE NOTICE '';
        RAISE NOTICE '========================================';

    ELSE
        RAISE WARNING '❌ 函數 create_or_get_conversation 不存在';
    END IF;
END $$;

-- =====================================================
-- 額外說明
-- =====================================================
--
-- 為什麼使用 OUT 參數？
-- -------------------------
--
-- 1. RETURNS TABLE 的問題:
--    RETURNS TABLE (item_id BIGINT, ...)
--    這會將 item_id 引入函數作用域，即使在 SELECT 中
--    使用 p_item_id，PostgreSQL 仍然會產生模糊性錯誤。
--
-- 2. OUT 參數的優勢:
--    - OUT 參數是直接賦值，不會產生作用域衝突
--    - 可以在 RETURNING INTO 中直接賦值給 OUT 參數
--    - 前端呼叫方式完全相同，無需修改
--
-- 3. 相容性:
--    - Supabase RPC 完全支援 OUT 參數
--    - 返回結果與 RETURNS TABLE 相同
--    - 前端 JavaScript 呼叫方式不變
--
-- =====================================================
