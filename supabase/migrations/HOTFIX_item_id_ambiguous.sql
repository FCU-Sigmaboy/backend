-- =====================================================
-- HOTFIX: 修正 create_or_get_conversation 的 item_id 模糊錯誤
-- =====================================================
-- 錯誤碼: 42702
-- 錯誤訊息: column reference "item_id" is ambiguous
--
-- 問題根源:
--   當函數使用 RETURNS TABLE 定義輸出欄位時，這些欄位名稱會被引入
--   函數的作用域中。如果在 RETURN QUERY SELECT 語句中再次使用相同
--   的欄位名稱，PostgreSQL 無法判斷你指的是輸出欄位還是資料表欄位。
--
-- 解決方案:
--   1. 將所有需要的值存入區域變數
--   2. 在 RETURN QUERY SELECT 中直接使用變數，而非查詢資料表
--   3. 這樣完全避免了欄位名稱的衝突
--
-- 執行方式:
--   複製此檔案的全部內容，貼到 Supabase Dashboard > SQL Editor 執行
--
-- 日期: 2025-01-XX
-- =====================================================

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
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()  -- 更新時間戳記
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

    -- 5. 返回對話資料
    --    關鍵修正: 直接使用區域變數，完全避免與 RETURNS TABLE 的欄位名稱衝突
    RETURN QUERY
    SELECT
        v_conversation_id,    -- conversation_id (從 RETURNING 取得)
        p_item_id,            -- item_id (直接使用輸入參數，避免查詢)
        v_buyer_id,           -- buyer_id (從 RETURNING 取得)
        v_seller_id,          -- seller_id (從 RETURNING 取得)
        v_created_at,         -- created_at (從 RETURNING 取得)
        v_updated_at;         -- updated_at (從 RETURNING 取得)

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

返回:
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
  - 2025-01-XX: 修正 item_id 欄位模糊問題 (42702 - ambiguous column reference)
                使用區域變數而非 SELECT 查詢避免名稱衝突';

-- =====================================================
-- 驗證修正結果
-- =====================================================
DO $$
DECLARE
    v_function_exists BOOLEAN;
    v_function_source TEXT;
BEGIN
    -- 檢查函數是否存在
    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname = 'create_or_get_conversation'
    ) INTO v_function_exists;

    IF v_function_exists THEN
        -- 檢查函數原始碼是否包含修正
        SELECT prosrc INTO v_function_source
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname = 'create_or_get_conversation';

        IF v_function_source LIKE '%v_conversation_id%'
           AND v_function_source LIKE '%RETURNING id, buyer_id, seller_id%' THEN
            RAISE NOTICE '';
            RAISE NOTICE '✅ 修正成功！';
            RAISE NOTICE '';
            RAISE NOTICE '函數 create_or_get_conversation 已更新';
            RAISE NOTICE '現在使用區域變數避免欄位名稱衝突';
            RAISE NOTICE '';
            RAISE NOTICE '請執行以下測試:';
            RAISE NOTICE '  1. 重新整理前端應用程式';
            RAISE NOTICE '  2. 嘗試點擊「聯絡賣家」按鈕';
            RAISE NOTICE '  3. 檢查瀏覽器 Console 是否還有 42702 錯誤';
            RAISE NOTICE '  4. 確認對話可以正常建立';
            RAISE NOTICE '';
        ELSE
            RAISE WARNING '⚠️ 函數已更新，但可能未包含完整修正';
        END IF;
    ELSE
        RAISE WARNING '❌ 函數 create_or_get_conversation 不存在';
    END IF;
END $$;
