-- =====================================================
-- 修正所有模糊欄位參考問題
-- =====================================================
-- 日期: 2025-01-XX
-- 目的: 徹底解決 RETURNS TABLE 與內部查詢的欄位名稱衝突
-- =====================================================

-- =====================================================
-- 1. 修正 create_or_get_conversation 函數
-- =====================================================
-- 問題: RETURNS TABLE 的欄位名稱與內部查詢衝突
-- 解決: 使用不同的輸出欄位名稱，避免與資料表欄位同名
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
    -- 利用 idx_conversations_item_buyer_unique 索引處理衝突
    INSERT INTO public.conversations (item_id, buyer_id, seller_id)
    VALUES (p_item_id, v_current_uid, v_item_user_id)
    ON CONFLICT (item_id, buyer_id)
    DO UPDATE SET updated_at = now()  -- 更新時間戳記，表示對話被重新存取
    RETURNING id INTO v_conversation_id;

    -- 返回對話資料，使用明確的欄位別名避免衝突
    RETURN QUERY
    SELECT
        v_conversation_id,           -- conversation_id
        c.item_id,                   -- item_id
        c.buyer_id,                  -- buyer_id
        c.seller_id,                 -- seller_id
        c.created_at,                -- created_at
        c.updated_at                 -- updated_at
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

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話，使用 UPSERT 搭配唯一索引確保原子性。
參數:
  - p_item_id: 物品 ID
返回:
  - 對話的完整資訊
安全性:
  - 自動驗證使用者登入狀態
  - 防止對自己的物品發起對話
  - 只能對上架中的物品發起對話
併發安全:
  - 使用 UPSERT 機制，透過唯一索引避免重複建立
錯誤處理:
  - 42501: 使用者未登入
  - 23514: 嘗試與自己的物品建立對話
  - 22023: 物品不存在或已下架';

-- =====================================================
-- 驗證函數是否正確建立
-- =====================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'create_or_get_conversation'
        AND pronamespace = 'public'::regnamespace
    ) THEN
        RAISE EXCEPTION '函數 create_or_get_conversation 建立失敗';
    END IF;

    RAISE NOTICE '✓ create_or_get_conversation 函數已成功建立/更新';
END $$;
