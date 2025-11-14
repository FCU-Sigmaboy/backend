-- 配合前端 update_toggleItemStatusAPI.js 的內含兩個 API:
--    relist_item(p_item_id BIGINT) RETURNS JSON
--    unlist_item(p_item_id BIGINT) RETURNS JSON



-- =============================================
-- API 7: (賣家) 重新上架物品
-- =============================================
CREATE OR REPLACE FUNCTION public.relist_item(
    p_item_id BIGINT
)
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_item items;
v_active_transaction_exists BOOLEAN;
BEGIN
    -- 1. 驗證
    IF v_current_uid IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

  -- 2. 鎖定物品
SELECT * INTO v_item FROM public.items WHERE id = p_item_id FOR UPDATE;

-- 3. 檢查權限和狀態
IF v_item IS NULL THEN RAISE EXCEPTION '物品不存在'; END IF;
IF v_item.user_id != v_current_uid THEN RAISE EXCEPTION '您不是此物品的擁有者'; END IF;
IF v_item.listing_status = TRUE THEN RAISE EXCEPTION '物品已經是上架狀態'; END IF;

  -- 4. *** 核心檢查 (您的邏輯) ***
  --    檢查是否存在 "非 'cancelled'" 狀態的交易
SELECT EXISTS (
    SELECT 1 FROM public.transactions t
    WHERE t.item_id = p_item_id
      AND t.transaction_status != 'cancelled'
) INTO v_active_transaction_exists;

-- 5. 如果存在 'confirming', 'pending', 或 'completed' 的交易，則禁止
IF v_active_transaction_exists THEN
    RAISE EXCEPTION '此物品已綁定於一個進行中或已完成的交易，無法重新上架';
END IF;

  -- 6. *** 執行重新上架 ***
  --    (只有在物品是 'cancelled' 或從未有過交易時，才能執行到這一步)
UPDATE public.items
SET
    listing_status = TRUE,
    updated_at = NOW()
WHERE id = p_item_id
    RETURNING * INTO v_item;

-- 7. 回傳成功訊息
RETURN json_build_object(
      'success', true,
      'message', '物品已重新上架',
      'item_id', v_item.id,
      'new_listing_status', v_item.listing_status
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================
-- API 8: (賣家) 安全下架物品
-- =============================================
CREATE OR REPLACE FUNCTION public.unlist_item(
    p_item_id BIGINT
)
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_item items;
v_active_transaction_exists BOOLEAN;
BEGIN
    -- 1. 驗證
    IF v_current_uid IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

  -- 2. 鎖定物品
SELECT * INTO v_item FROM public.items WHERE id = p_item_id FOR UPDATE;

-- 3. 檢查權限和狀態
IF v_item IS NULL THEN RAISE EXCEPTION '物品不存在'; END IF;
IF v_item.user_id != v_current_uid THEN RAISE EXCEPTION '您不是此物品的擁有者'; END IF;
IF v_item.listing_status = FALSE THEN RAISE EXCEPTION '物品已經是下架狀態'; END IF;

  -- 4. *** 核心檢查 (下架邏輯) ***
  --    檢查是否存在 "進行中" 的交易 ('confirming' 或 'pending')
SELECT EXISTS (
    SELECT 1 FROM public.transactions t
    WHERE t.item_id = p_item_id
      AND t.transaction_status IN ('confirming', 'pending')
) INTO v_active_transaction_exists;

-- 5. 如果存在進行中的交易，則禁止
IF v_active_transaction_exists THEN
    RAISE EXCEPTION '物品正在交易中，無法下架。請先取消該筆交易。';
END IF;

  -- 6. *** 執行下架 ***
  --    (只有在物品是 'completed', 'cancelled' 或從未有過交易時)
UPDATE public.items
SET
    listing_status = FALSE,
    updated_at = NOW()
WHERE id = p_item_id
    RETURNING * INTO v_item;

-- 7. 回傳成功訊息
RETURN json_build_object(
      'success', true,
      'message', '物品已下架',
      'item_id', v_item.id,
      'new_listing_status', v_item.listing_status
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;