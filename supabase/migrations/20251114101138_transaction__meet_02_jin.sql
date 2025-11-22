-- =============================================
-- RPC 函式: V2 交易流程 (共 6 個函式)
-- =============================================

-- (此處省略您已有的 5 個 RPC 函式:
--   initiate_transaction,
--   get_my_transactions_by_status,
--   update_giver_note,
--   buyer_confirm_transaction,
--   cancel_transaction
--  )
-- ... existing functions ...


-- =============================================
-- API 6: (買家) 輸入代碼以完成交易
-- *** 已修正 v_item 變數類型和 SELECT INTO 語法 ***
-- =============================================
CREATE OR REPLACE FUNCTION public.finalize_transaction_with_code(
    p_transaction_id BIGINT,
    p_confirmation_code TEXT -- 買家輸入的 6 位數代碼
)
              RETURNS JSON
              AS $$
              DECLARE
              v_receiver_id UUID := auth.uid(); -- 買家 (我)
v_transaction transactions;
v_receiver_profile profiles;
v_title TEXT; -- *** 修正：儲存物品標題 ***
v_price INT;
v_carbon_value NUMERIC;
BEGIN
    -- 1. 驗證
    IF v_receiver_id IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

    -- 2. 鎖定交易紀錄
SELECT * INTO v_transaction FROM public.transactions WHERE id = p_transaction_id FOR UPDATE;

-- 3. 檢查交易
IF v_transaction IS NULL THEN RAISE EXCEPTION '交易不存在'; END IF;
IF v_transaction.receiver_id != v_receiver_id THEN RAISE EXCEPTION '您不是此交易的買家'; END IF;
IF v_transaction.transaction_status != 'pending' THEN RAISE EXCEPTION '此交易並非等待面交確認狀態'; END IF;

    -- 4. 核心檢查：驗證代碼
IF v_transaction.code != p_confirmation_code THEN
        RAISE EXCEPTION '確認碼錯誤';
END IF;

    -- 5. *** 修正：獲取物品價格、碳足跡和標題 ***
SELECT title, price, carbon_value
INTO v_title, v_price, v_carbon_value
FROM public.items
WHERE id = v_transaction.item_id;

IF v_title IS NULL THEN
        RAISE EXCEPTION '關聯物品不存在';
END IF;

    -- 6. 檢查買家點數
SELECT * INTO v_receiver_profile FROM public.profiles WHERE user_id = v_receiver_id;
IF v_receiver_profile.balance < v_price THEN
         RAISE EXCEPTION '點數餘額不足';
END IF;

    -- *** 確認所有檢查通過，開始執行原子性更新 ***

    -- 7. 扣除買家點數
UPDATE public.profiles
SET balance = balance - v_price,
    carbon_saved_kg = carbon_saved_kg + v_carbon_value, -- 碳足跡給買家
    updated_at = NOW()
WHERE user_id = v_receiver_id;
-- 8. (日誌) 新增買家點數支出紀錄
INSERT INTO public.point_logs (user_id, amount, "type", transaction_id, description)
VALUES (v_receiver_id, -v_price, 'transaction_expense', p_transaction_id, '索取物品：' || v_title); -- *** 修正 ***

-- 9. 增加賣家點數
UPDATE public.profiles
SET balance = balance + v_price,
    updated_at = NOW()
WHERE user_id = v_transaction.giver_id;
-- 10. (日誌) 新增賣家點數收入紀錄
INSERT INTO public.point_logs (user_id, amount, "type", transaction_id, description)
VALUES (v_transaction.giver_id, v_price, 'transaction_income', p_transaction_id, '售出物品：' || v_title); -- *** 修正 ***

-- 11. 關鍵：更新交易狀態為 "completed"
UPDATE public.transactions
SET
    transaction_status = 'completed',
    completed_at = NOW(),
    updated_at = NOW()
WHERE id = p_transaction_id
    RETURNING * INTO v_transaction;

-- 12. 回傳成功訊息
RETURN json_build_object(
          'success', true,
          'message', '交易完成',
          'transaction_id', v_transaction.id,
          'new_status', v_transaction.transaction_status,
          'new_balance', v_receiver_profile.balance - v_price -- 回傳更新後的點數
      );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;