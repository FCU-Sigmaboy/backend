-- =============================================
-- 最終修復: create_or_get_conversation 的欄位歧義問題
-- =============================================
-- 問題: RETURNS TABLE 的欄位名稱與 SELECT 中的表格欄位產生歧義
-- 根本原因: PostgreSQL 在 RETURN QUERY SELECT 時,會將 RETURNS TABLE
--          的欄位名稱引入作用域,導致與實際表格欄位衝突
-- 解決方案: 使用 CTE (WITH) 先查詢資料,再進行型別轉換返回
-- 日期: 2025-11-09
-- 相關錯誤: column reference "item_id" is ambiguous (SQLSTATE 42702)
-- =============================================

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

    -- 使用 CTE 避免欄位名稱衝突
    RETURN QUERY
    WITH conversation_data AS (
        SELECT
            c.id,
            c.item_id,
            c.buyer_id,
            c.seller_id,
            c.created_at,
            c.updated_at
        FROM public.conversations c
        WHERE c.id = v_conversation_id
    )
    SELECT
        cd.id::BIGINT,
        cd.item_id::BIGINT,
        cd.buyer_id::UUID,
        cd.seller_id::UUID,
        cd.created_at::TIMESTAMPTZ,
        cd.updated_at::TIMESTAMPTZ
    FROM conversation_data cd;

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

-- =============================================
-- 同時修復 get_conversations_by_ids 函數
-- =============================================

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

    -- 使用 CTE 避免欄位名稱衝突
    RETURN QUERY
    WITH conversation_data AS (
        SELECT
            c.id,
            c.item_id,
            c.buyer_id,
            c.seller_id,
            c.created_at,
            c.updated_at,
            i.title,
            i.image_urls
        FROM public.conversations c
        LEFT JOIN public.items i ON c.item_id = i.id
        WHERE c.id = ANY(p_conversation_ids)
          AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
    )
    SELECT
        cd.id::BIGINT,
        cd.item_id::BIGINT,
        cd.buyer_id::UUID,
        cd.seller_id::UUID,
        cd.created_at::TIMESTAMPTZ,
        cd.updated_at::TIMESTAMPTZ,
        cd.title::TEXT,
        cd.image_urls[1]::TEXT
    FROM conversation_data cd;
END;
$$;

-- =============================================
-- 確保權限設定正確
-- =============================================

GRANT EXECUTE ON FUNCTION public.create_or_get_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversations_by_ids(BIGINT[]) TO authenticated;

-- =============================================
-- 更新函數註解
-- =============================================

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話，使用 UPSERT 搭配唯一索引確保原子性。
修復: 使用 CTE 完全解決欄位名稱歧義問題 (PostgreSQL 42702)。
版本: 1.2 (2025-11-09)';

COMMENT ON FUNCTION public.get_conversations_by_ids(BIGINT[]) IS
'批次取得對話資訊，防止 N+1 查詢問題。
修復: 使用 CTE 完全解決欄位名稱歧義問題 (PostgreSQL 42702)。
版本: 1.2 (2025-11-09)';

-- =============================================
-- 驗證修復
-- =============================================

DO $$
DECLARE
    v_function_def TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證 create_or_get_conversation 修復';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查 create_or_get_conversation
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'create_or_get_conversation'
      AND pg_get_function_arguments(p.oid) = 'p_item_id bigint';

    IF v_function_def IS NOT NULL THEN
        IF v_function_def LIKE '%WITH conversation_data AS%' THEN
            RAISE NOTICE '✅ create_or_get_conversation 已更新為 CTE 版本';
        ELSE
            RAISE WARNING '⚠️ create_or_get_conversation 存在但可能未使用 CTE';
        END IF;
    ELSE
        RAISE WARNING '⚠️ 找不到 create_or_get_conversation 函數';
    END IF;

    -- 檢查 get_conversations_by_ids
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'get_conversations_by_ids';

    IF v_function_def IS NOT NULL THEN
        IF v_function_def LIKE '%WITH conversation_data AS%' THEN
            RAISE NOTICE '✅ get_conversations_by_ids 已更新為 CTE 版本';
        ELSE
            RAISE WARNING '⚠️ get_conversations_by_ids 存在但可能未使用 CTE';
        END IF;
    ELSE
        RAISE WARNING '⚠️ 找不到 get_conversations_by_ids 函數';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎉 Migration 完成！';
    RAISE NOTICE '';
    RAISE NOTICE '📝 下一步:';
    RAISE NOTICE '  1. 測試點擊「聯絡賣家」按鈕';
    RAISE NOTICE '  2. 確認不再出現 400 Bad Request';
    RAISE NOTICE '  3. 確認對話可以正常建立';
    RAISE NOTICE '  4. 檢查前端 console 不再有 ambiguous 錯誤';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;
