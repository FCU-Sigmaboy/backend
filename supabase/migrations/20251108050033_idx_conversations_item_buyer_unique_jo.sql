-- =============================================
-- Migration: 建立唯一索引以防止重複對話
-- 檔案: 20251108050033_idx_conversations_item_buyer_unique_jo.sql
-- 建立日期: 2025-11-08
-- 目標: 解決高併發下可能產生的重複對話問題 (Race Condition)
-- =============================================

-- =============================================
-- 1. 建立唯一索引 (item_id, buyer_id)
-- =============================================
-- 說明：
-- - 確保同一物品、同一買家只能有一個對話
-- - 提供資料庫層級的唯一性保證
-- - 自動提升查詢效能（透過索引加速查找）
-- - 配合 ON CONFLICT 語句實現安全的 UPSERT 操作

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_item_buyer_unique
ON public.conversations(item_id, buyer_id);

-- =============================================
-- 2. 建立效能索引（可選但建議）
-- =============================================
-- 說明：
-- - 加速買家查詢自己的對話列表
-- - 加速賣家查詢自己的對話列表

-- 買家查詢索引
CREATE INDEX IF NOT EXISTS idx_conversations_buyer_updated
ON public.conversations(buyer_id, updated_at DESC);

-- 賣家查詢索引
CREATE INDEX IF NOT EXISTS idx_conversations_seller_updated
ON public.conversations(seller_id, updated_at DESC);

-- =============================================
-- 3. 優化 create_or_get_conversation 函數
-- =============================================
-- 說明：
-- - 使用 INSERT ... ON CONFLICT 處理併發插入
-- - 利用新建立的唯一索引實現原子性操作
-- - 避免 Race Condition 導致的重複資料

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

    -- 返回對話資訊
    RETURN QUERY
    SELECT
        c.id,
        c.item_id,
        c.buyer_id,
        c.seller_id,
        c.created_at,
        c.updated_at
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

-- =============================================
-- 4. 新增輔助函數：批次取得對話（防止 N+1 查詢）
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

    RETURN QUERY
    SELECT
        c.id,
        c.item_id,
        c.buyer_id,
        c.seller_id,
        c.created_at,
        c.updated_at,
        i.title,
        i.image_urls[1]
    FROM public.conversations c
    LEFT JOIN public.items i ON c.item_id = i.id
    WHERE c.id = ANY(p_conversation_ids)
      AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid);
END;
$$;

-- =============================================
-- 5. 加入註解說明
-- =============================================

COMMENT ON INDEX idx_conversations_item_buyer_unique IS
'唯一索引：確保同一物品、同一買家只能有一個對話，防止併發情況下的重複建立';

COMMENT ON INDEX idx_conversations_buyer_updated IS
'效能索引：加速買家查詢自己的對話列表（依更新時間排序）';

COMMENT ON INDEX idx_conversations_seller_updated IS
'效能索引：加速賣家查詢自己的對話列表（依更新時間排序）';

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話，使用 UPSERT 搭配唯一索引確保原子性，避免 Race Condition';

COMMENT ON FUNCTION public.get_conversations_by_ids(BIGINT[]) IS
'批次取得對話資訊，避免 N+1 查詢問題';

-- =============================================
-- 6. 權限設定
-- =============================================

-- 允許已驗證使用者執行函數
GRANT EXECUTE ON FUNCTION public.create_or_get_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversations_by_ids(BIGINT[]) TO authenticated;

-- =============================================
-- 7. 資料清理（僅在初次執行時）
-- =============================================
-- 說明：
-- - 檢查並移除可能存在的重複對話
-- - 保留最早建立的對話
-- - 執行後會輸出清理統計

DO $$
DECLARE
    v_deleted_count INT;
BEGIN
    -- 刪除重複的對話（保留 id 最小的）
    WITH duplicates AS (
        SELECT
            id,
            ROW_NUMBER() OVER (
                PARTITION BY item_id, buyer_id
                ORDER BY id ASC
            ) as rn
        FROM public.conversations
    )
    DELETE FROM public.conversations
    WHERE id IN (
        SELECT id FROM duplicates WHERE rn > 1
    );

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    IF v_deleted_count > 0 THEN
        RAISE NOTICE '🧹 清理了 % 筆重複對話', v_deleted_count;
    ELSE
        RAISE NOTICE '✓ 沒有發現重複對話';
    END IF;
END $$;

-- =============================================
-- 8. 驗證與統計
-- =============================================

DO $$
DECLARE
    v_total_conversations INT;
    v_total_indexes INT;
BEGIN
    -- 統計對話總數
    SELECT COUNT(*) INTO v_total_conversations FROM public.conversations;

    -- 統計索引數量
    SELECT COUNT(*) INTO v_total_indexes
    FROM pg_indexes
    WHERE tablename = 'conversations'
      AND indexname LIKE 'idx_conversations_%';

    RAISE NOTICE '========================================';
    RAISE NOTICE '✓ Migration 執行成功！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 統計資訊:';
    RAISE NOTICE '  - 對話總數: %', v_total_conversations;
    RAISE NOTICE '  - 索引數量: %', v_total_indexes;
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎯 已完成項目:';
    RAISE NOTICE '  1. ✓ 建立唯一索引 (item_id, buyer_id)';
    RAISE NOTICE '  2. ✓ 建立效能索引 (buyer/seller)';
    RAISE NOTICE '  3. ✓ 優化 create_or_get_conversation';
    RAISE NOTICE '  4. ✓ 新增批次查詢函數';
    RAISE NOTICE '  5. ✓ 清理重複資料';
    RAISE NOTICE '========================================';
    RAISE NOTICE '💡 建議:';
    RAISE NOTICE '  - 後端程式碼可使用 ON CONFLICT 處理插入';
    RAISE NOTICE '  - 高併發場景下索引會自動保證唯一性';
    RAISE NOTICE '  - 定期監控索引使用率與查詢效能';
    RAISE NOTICE '========================================';
END $$;
