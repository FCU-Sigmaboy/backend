-- =============================================
-- 最終修復: get_user_conversations 的欄位歧義問題
-- =============================================
-- 問題: RETURNS TABLE 的欄位名稱與 SELECT 中的表格欄位產生歧義
-- 根本原因: PostgreSQL 在 RETURN QUERY SELECT 時,會將 RETURNS TABLE
--          的欄位名稱引入作用域,導致與實際表格欄位衝突
-- 解決方案: 使用 CTE (WITH) 先計算所有欄位,避免名稱衝突
-- 日期: 2025-11-09
-- 相關錯誤:
--   - column reference "conversation_id" is ambiguous (SQLSTATE 42702)
--   - column reference "item_id" is ambiguous (SQLSTATE 42702)
--   - structure of query does not match function result type
-- =============================================

CREATE OR REPLACE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_role TEXT DEFAULT 'all',
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    item_title TEXT,
    item_image_url TEXT,
    other_user_id UUID,
    other_user_nickname VARCHAR(50),
    other_user_profile_picture TEXT,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    unread_count BIGINT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    is_deleted BOOLEAN
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 驗證分頁參數
    IF p_page < 1 THEN
        RAISE EXCEPTION '頁碼必須大於 0';
    END IF;
    IF p_size < 1 OR p_size > 100 THEN
        RAISE EXCEPTION '每頁數量必須在 1 到 100 之間';
    END IF;

    -- 驗證 role 參數
    IF p_role NOT IN ('buyer', 'seller', 'all') THEN
        RAISE EXCEPTION 'role 參數必須是 buyer, seller 或 all';
    END IF;

    v_offset := (p_page - 1) * p_size;

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
            c.deleted_by_buyer_at,
            c.deleted_by_seller_at,
            i.title,
            i.image_urls,
            u_buyer.nickname AS buyer_nickname,
            u_buyer.profile_picture_url AS buyer_profile_picture,
            u_seller.nickname AS seller_nickname,
            u_seller.profile_picture_url AS seller_profile_picture
        FROM public.conversations c
        LEFT JOIN public.items i ON c.item_id = i.id
        LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
        LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
        WHERE
            -- 根據 role 參數過濾
            CASE
                WHEN p_role = 'buyer' THEN c.buyer_id = v_current_uid
                WHEN p_role = 'seller' THEN c.seller_id = v_current_uid
                ELSE (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
            END
            -- 過濾當前使用者已刪除的對話
            AND (
                p_include_deleted = true OR
                (c.buyer_id = v_current_uid AND c.deleted_by_buyer_at IS NULL) OR
                (c.seller_id = v_current_uid AND c.deleted_by_seller_at IS NULL)
            )
    ),
    last_messages AS (
        SELECT DISTINCT ON (cm.conversation_id)
            cm.conversation_id,
            cm.content,
            cm.sent_at
        FROM public.conversation_messages cm
        WHERE cm.deleted_at IS NULL
        ORDER BY cm.conversation_id, cm.sent_at DESC
    ),
    unread_counts AS (
        SELECT
            cm.conversation_id,
            COUNT(*) AS count
        FROM public.conversation_messages cm
        WHERE cm.sender_id != v_current_uid
          AND cm.is_read = false
          AND cm.deleted_at IS NULL
        GROUP BY cm.conversation_id
    )
    SELECT
        cd.id::BIGINT,
        cd.item_id::BIGINT,
        cd.title::TEXT,
        cd.image_urls[1]::TEXT,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_id
            ELSE cd.buyer_id
        END::UUID,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_nickname
            ELSE cd.buyer_nickname
        END::VARCHAR(50),
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_profile_picture
            ELSE cd.buyer_profile_picture
        END::TEXT,
        lm.content::TEXT,
        lm.sent_at::TIMESTAMPTZ,
        COALESCE(uc.count, 0)::BIGINT,
        cd.created_at::TIMESTAMPTZ,
        cd.updated_at::TIMESTAMPTZ,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN (cd.deleted_by_buyer_at IS NOT NULL)
            ELSE (cd.deleted_by_seller_at IS NOT NULL)
        END::BOOLEAN
    FROM conversation_data cd
    LEFT JOIN last_messages lm ON lm.conversation_id = cd.id
    LEFT JOIN unread_counts uc ON uc.conversation_id = cd.id
    ORDER BY cd.updated_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- 更新函數註解
-- =============================================

COMMENT ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) IS
'取得使用者的對話列表(支援軟刪除)。
修復: 使用 CTE 完全解決欄位名稱歧義問題 (PostgreSQL 42702)。
版本: 1.3 (2025-11-09)';

-- =============================================
-- 驗證修復
-- =============================================

DO $$
DECLARE
    v_function_def TEXT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  驗證 get_user_conversations 最終修復';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- 檢查函數是否存在
    SELECT pg_get_functiondef(p.oid) INTO v_function_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'get_user_conversations'
      AND pg_get_function_arguments(p.oid) LIKE '%p_include_deleted%';

    IF v_function_def IS NOT NULL THEN
        -- 檢查是否使用 CTE 方式
        IF v_function_def LIKE '%WITH conversation_data AS%' THEN
            RAISE NOTICE '✅ 函數已成功更新為 CTE 版本';
            RAISE NOTICE '';
            RAISE NOTICE '修復內容:';
            RAISE NOTICE '  - 使用 CTE (WITH) 預先計算所有欄位';
            RAISE NOTICE '  - 完全避免 RETURNS TABLE 與表格欄位的名稱衝突';
            RAISE NOTICE '  - 使用 DISTINCT ON 優化 last_message 查詢';
            RAISE NOTICE '  - 明確型別轉換確保欄位類型匹配';
            RAISE NOTICE '';
            RAISE NOTICE '📝 下一步:';
            RAISE NOTICE '  1. 重新測試前端 getMyConversations()';
            RAISE NOTICE '  2. 確認不再出現 400 Bad Request';
            RAISE NOTICE '  3. 確認不再出現 ambiguous 錯誤';
            RAISE NOTICE '  4. 檢查回傳資料格式是否正確';
        ELSE
            RAISE WARNING '⚠️ 函數已更新但可能未使用 CTE 方式';
        END IF;
    ELSE
        RAISE WARNING '⚠️ 找不到 get_user_conversations 函數';
    END IF;

    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;
