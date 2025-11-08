-- =====================================================
-- 🔥 最終修正: item_id 模糊錯誤 (42702)
-- =====================================================
-- 問題: OUT 參數不返回陣列,導致前端無法讀取 data[0]
-- 解決: 改用 RETURNS TABLE + 子查詢完全避免名稱衝突
-- =====================================================
-- 複製此檔案的全部內容，貼到 Supabase Dashboard > SQL Editor 執行
-- =====================================================

DROP FUNCTION IF EXISTS public.create_or_get_conversation(BIGINT);

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
    v_current_uid UUID;
    v_item_user_id UUID;
    v_existing_conv_id BIGINT;
BEGIN
    -- 1. 取得當前使用者 ID
    v_current_uid := auth.uid();

    -- 2. 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 3. 取得物品擁有者（只查詢上架中的物品）
    SELECT i.user_id INTO STRICT v_item_user_id
    FROM public.items i
    WHERE i.id = p_item_id
      AND i.listing_status = true;

    -- 4. 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話'
            USING HINT = '您不能對自己的商品發起對話',
                  ERRCODE = '23514';
    END IF;

    -- 5. 先檢查是否已存在對話
    SELECT c.id INTO v_existing_conv_id
    FROM public.conversations c
    WHERE c.item_id = p_item_id
      AND c.buyer_id = v_current_uid
    LIMIT 1;

    -- 6. 如果已存在，更新時間戳記
    IF v_existing_conv_id IS NOT NULL THEN
        UPDATE public.conversations
        SET updated_at = now()
        WHERE id = v_existing_conv_id;
    ELSE
        -- 7. 如果不存在，建立新對話
        INSERT INTO public.conversations (item_id, buyer_id, seller_id)
        VALUES (p_item_id, v_current_uid, v_item_user_id)
        RETURNING id INTO v_existing_conv_id;
    END IF;

    -- 8. 使用子查詢返回結果，完全避免名稱衝突
    -- 關鍵: 不在 RETURN QUERY 中直接使用欄位名稱
    RETURN QUERY
    SELECT
        sub.conversation_id,
        sub.item_id,
        sub.buyer_id,
        sub.seller_id,
        sub.created_at,
        sub.updated_at
    FROM (
        SELECT
            c.id AS conversation_id,
            c.item_id AS item_id,
            c.buyer_id AS buyer_id,
            c.seller_id AS seller_id,
            c.created_at AS created_at,
            c.updated_at AS updated_at
        FROM public.conversations c
        WHERE c.id = v_existing_conv_id
    ) AS sub;

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

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話 (使用子查詢避免 RETURNS TABLE 的名稱衝突)';

-- 授予權限
GRANT EXECUTE ON FUNCTION public.create_or_get_conversation(BIGINT) TO authenticated;

-- =====================================================
-- 驗證修正
-- =====================================================
DO $$
DECLARE
    v_result TEXT;
    v_source TEXT;
BEGIN
    SELECT
        pg_get_function_result(p.oid),
        prosrc
    INTO v_result, v_source
    FROM pg_proc p
    WHERE p.proname = 'create_or_get_conversation'
      AND p.pronamespace = 'public'::regnamespace;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ 修正完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '函數返回類型: %', v_result;
    RAISE NOTICE '';

    IF v_source LIKE '%FROM (%) AS sub%' AND v_source NOT LIKE '%ON CONFLICT%' THEN
        RAISE NOTICE '✅ 使用子查詢 + RETURNS TABLE 版本 (正確)';
        RAISE NOTICE '✅ 完全避免名稱衝突';
        RAISE NOTICE '✅ 返回陣列格式,前端可用 data[0]';
    ELSE
        RAISE WARNING '⚠️  可能未正確更新,請重新執行腳本';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  關鍵改進';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. 使用 RETURNS TABLE (前端需要陣列格式)';
    RAISE NOTICE '2. 不使用 ON CONFLICT (避免名稱衝突)';
    RAISE NOTICE '3. 使用子查詢 (SELECT ... FROM (...) AS sub)';
    RAISE NOTICE '4. 子查詢中使用 AS 別名';
    RAISE NOTICE '5. 外層 SELECT 只引用別名,不直接用欄位名';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  下一步測試步驟';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. 清除瀏覽器快取:';
    RAISE NOTICE '   - 按 Ctrl+Shift+Delete (Mac: Cmd+Shift+Delete)';
    RAISE NOTICE '   - 勾選「快取」並清除';
    RAISE NOTICE '   - 或直接使用無痕視窗測試';
    RAISE NOTICE '';
    RAISE NOTICE '2. 重新整理前端應用程式';
    RAISE NOTICE '';
    RAISE NOTICE '3. 登入並點擊「聯絡賣家」按鈕';
    RAISE NOTICE '';
    RAISE NOTICE '4. 檢查瀏覽器 Console:';
    RAISE NOTICE '   ✓ 不應出現 42702 錯誤';
    RAISE NOTICE '   ✓ 不應出現 "ambiguous" 訊息';
    RAISE NOTICE '   ✓ 不應出現 "Cannot read properties of undefined"';
    RAISE NOTICE '   ✓ 應該能成功建立對話並跳轉';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '技術說明:';
    RAISE NOTICE '  問題 1: ON CONFLICT 導致 42702 錯誤';
    RAISE NOTICE '  解決 1: 改用 SELECT + INSERT/UPDATE';
    RAISE NOTICE '';
    RAISE NOTICE '  問題 2: OUT 參數返回單一物件,非陣列';
    RAISE NOTICE '  解決 2: 改回 RETURNS TABLE';
    RAISE NOTICE '';
    RAISE NOTICE '  問題 3: RETURNS TABLE 欄位名稱衝突';
    RAISE NOTICE '  解決 3: 使用子查詢 + AS 別名隔離';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
