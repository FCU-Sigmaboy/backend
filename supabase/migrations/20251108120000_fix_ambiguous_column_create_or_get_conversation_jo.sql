-- =============================================
-- 修復: create_or_get_conversation 和 get_conversations_by_ids 的歧義性欄位參照
-- =============================================
-- 問題: RETURNS TABLE 的欄位名稱與 SELECT 語句中的欄位名稱衝突，導致 PostgreSQL 42702 錯誤
-- 解決: 使用 AS 子句明確指定欄位別名
-- 日期: 2025-11-08
-- 相關錯誤: column reference "item_id" is ambiguous
-- =============================================

-- 1. 修復 create_or_get_conversation 函數
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
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 取得物品擁有者（只查詢上架中的物品）
    SELECT user_id INTO STRICT v_item_user_id
    FROM public.items
    WHERE id = p_item_id
      AND listing_status = true;

    -- 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話'
            USING HINT = '您不能對自己的商品發起對話',
                  ERRCODE = '23514';
    END IF;

    -- 使用 UPSERT 確保原子性
    -- 利用 idx_conversations_item_buyer_unique 索引處理衝突
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()  -- 更新時間戳記，表示對話被重新存取
    RETURNING id INTO v_conversation_id;

    -- 返回對話資訊（使用 AS 明確指定別名以避免歧義）
    RETURN QUERY
    SELECT
        c.id AS conversation_id,
        c.item_id AS item_id,
        c.buyer_id AS buyer_id,
        c.seller_id AS seller_id,
        c.created_at AS created_at,
        c.updated_at AS updated_at
    FROM public.conversations c
    WHERE c.id = v_conversation_id;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '物品不存在或已下架'
            USING HINT = '請確認物品 ID 是否正確且物品處於上架狀態',
                  ERRCODE = '22023';
    WHEN OTHERS THEN
        -- 記錄錯誤並重新拋出
        RAISE NOTICE '建立對話時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

-- 2. 修復 get_conversations_by_ids 函數
CREATE OR REPLACE FUNCTION public.get_conversations_by_ids(
    p_conversation_ids BIGINT[]
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    buyer_id UUID,
    seller_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    item_title TEXT,
    item_image_url TEXT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 返回對話列表（使用 AS 明確指定別名以避免歧義）
    RETURN QUERY
    SELECT
        c.id AS conversation_id,
        c.item_id AS item_id,
        c.buyer_id AS buyer_id,
        c.seller_id AS seller_id,
        c.created_at AS created_at,
        c.updated_at AS updated_at,
        i.title AS item_title,
        i.image_urls[1] AS item_image_url
    FROM public.conversations c
    LEFT JOIN public.items i ON c.item_id = i.id
    WHERE c.id = ANY(p_conversation_ids)
      AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid);
END;
$$;

-- =============================================
-- 3. 確保權限設定正確
-- =============================================

GRANT EXECUTE ON FUNCTION public.create_or_get_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversations_by_ids(BIGINT[]) TO authenticated;

-- =============================================
-- 4. 更新函數註解
-- =============================================

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話，使用 UPSERT 搭配唯一索引確保原子性，避免 Race Condition。
修復: 使用 AS 子句解決欄位名稱歧義問題 (PostgreSQL 42702 錯誤)。
版本: 1.1 (2025-11-08)';

COMMENT ON FUNCTION public.get_conversations_by_ids(BIGINT[]) IS
'批次取得對話資訊，防止 N+1 查詢問題。
修復: 使用 AS 子句解決欄位名稱歧義問題 (PostgreSQL 42702 錯誤)。
版本: 1.1 (2025-11-08)';

-- =============================================
-- 5. 驗證修復
-- =============================================

DO $$
DECLARE
    v_test_result RECORD;
BEGIN
    -- 測試函數簽名是否正確
    SELECT
        p.proname AS function_name,
        pg_get_function_result(p.oid) AS return_type
    INTO v_test_result
    FROM pg_proc p
    WHERE p.proname = 'create_or_get_conversation';

    IF v_test_result.function_name IS NOT NULL THEN
        RAISE NOTICE '✅ create_or_get_conversation 函數已成功更新';
        RAISE NOTICE '   回傳類型: %', v_test_result.return_type;
    ELSE
        RAISE WARNING '⚠️ create_or_get_conversation 函數未找到';
    END IF;

    SELECT
        p.proname AS function_name,
        pg_get_function_result(p.oid) AS return_type
    INTO v_test_result
    FROM pg_proc p
    WHERE p.proname = 'get_conversations_by_ids';

    IF v_test_result.function_name IS NOT NULL THEN
        RAISE NOTICE '✅ get_conversations_by_ids 函數已成功更新';
        RAISE NOTICE '   回傳類型: %', v_test_result.return_type;
    ELSE
        RAISE WARNING '⚠️ get_conversations_by_ids 函數未找到';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '🎉 Migration 完成！';
    RAISE NOTICE '📝 請測試以下功能：';
    RAISE NOTICE '   1. 點擊「聯絡賣家」按鈕';
    RAISE NOTICE '   2. 檢查是否還有 400 Bad Request 錯誤';
    RAISE NOTICE '   3. 確認對話可以正常建立';
END $$;

