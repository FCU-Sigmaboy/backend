-- =============================================
-- RPC 函式: V2 交易流程 (共 5 個函式)
-- =============================================

-- =============================================
-- API 1: (賣家) 發起交易要約
-- =============================================
CREATE OR REPLACE FUNCTION public.initiate_transaction(
    p_item_id BIGINT,
    p_receiver_id UUID -- 買家的 ID (從 chat 紀錄中可知)
)
              RETURNS JSON -- 回傳新建立的交易 ID 和 確認碼
              AS $$
              DECLARE
              v_giver_id UUID := auth.uid(); -- 賣家 (我)
v_item items;
v_transaction transactions;
v_new_code TEXT;
BEGIN
    -- 1. 驗證
    IF v_giver_id IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

SELECT * INTO v_item FROM public.items WHERE id = p_item_id FOR UPDATE; -- 鎖定物品

IF v_item IS NULL THEN RAISE EXCEPTION '物品不存在'; END IF;
IF v_item.listing_status = false THEN RAISE EXCEPTION '物品已下架或已售出'; END IF;
IF v_item.user_id != v_giver_id THEN RAISE EXCEPTION '您不是此物品的擁有者'; END IF;
IF v_giver_id = p_receiver_id THEN RAISE EXCEPTION '無法與自己交易'; END IF;

  -- 2. 生成 6 位數確認碼
v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');

  -- 3. (交易 1) 更新物品為 "下架" (鎖定)
UPDATE public.items
SET listing_status = FALSE, updated_at = NOW()
WHERE id = p_item_id;

-- 4. (交易 2) 插入新的 "confirming" 交易
INSERT INTO public.transactions (
    item_id, giver_id, receiver_id,
    points_amount, carbon_amount_kg,
    transaction_status, code
)
VALUES (
           p_item_id, v_giver_id, p_receiver_id,
           v_item.price, v_item.carbon_value,
           'confirming', v_new_code -- *** 關鍵：狀態設為 "confirming" ***
       )
-- 處理萬一物品已被提出交易但取消後的狀況
ON CONFLICT (item_id) DO UPDATE
SET
    transaction_status = 'confirming',
    giver_id = v_giver_id,
    receiver_id = p_receiver_id,
    code = v_new_code,
    giver_note = NULL, -- 重置備註
    receiver_note = NULL, -- 重置備註
    updated_at = NOW()
    RETURNING * INTO v_transaction;

RETURN json_build_object(
      'transaction_id', v_transaction.id,
      'status', v_transaction.transaction_status,
      'code', v_transaction.code
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ####################################################################
-- ### API 2: (共用) 查詢 "我的" 交易列表 (依狀態和角色)
-- ### *** 已修正 42804 錯誤 (other_user_nickname 類型) ***
-- ####################################################################

-- 步驟 1: (必須) 刪除舊函式，因為我們要變更 "回傳類型"
DROP FUNCTION IF EXISTS public.get_my_transactions_by_status(TEXT, TEXT);

-- 步驟 2: 建立新函式 (已修正 other_user_nickname 類型)
CREATE OR REPLACE FUNCTION public.get_my_transactions_by_status(
    p_status TEXT, -- 參數類型 TEXT 是正確的 (因為欄位是 VARCHAR)
    p_role TEXT -- 'giver' (賣家) 或 'receiver' (買家)
)
              RETURNS TABLE (
    -- 交易資訊
    transaction_id BIGINT,
    code TEXT,
    giver_note TEXT,
    receiver_note TEXT,
    -- 物品資訊
    item_id BIGINT,
    item_title VARCHAR(50),
              item_image_url TEXT,
              item_price INT,
              -- 另一方使用者資訊
              other_user_id UUID,
              other_user_nickname VARCHAR(50) -- *** 修正：從 TEXT 改為 VARCHAR(50) ***
              )
              LANGUAGE plpgsql STABLE SECURITY DEFINER
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
BEGIN
    IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

IF p_role = 'giver' THEN
    -- 我是賣家 (Giver)，對方是買家 (Receiver)
    RETURN QUERY
SELECT
    t.id, t.code, t.giver_note, t.receiver_note,
    i.id, i.title, i.image_urls[1], i.price,
    u.id, u.nickname
FROM public.transactions t
         LEFT JOIN public.items i ON t.item_id = i.id
         LEFT JOIN public.users u ON t.receiver_id = u.id -- 抓取買家資訊
WHERE t.giver_id = v_current_uid
  AND t.transaction_status = p_status
ORDER BY t.updated_at DESC;

ELSIF p_role = 'receiver' THEN
    -- 我是買家 (Receiver)，對方是賣家 (Giver)
    RETURN QUERY
SELECT
    t.id, t.code, t.giver_note, t.receiver_note,
    i.id, i.title, i.image_urls[1], i.price,
    u.id, u.nickname
FROM public.transactions t
         LEFT JOIN public.items i ON t.item_id = i.id
         LEFT JOIN public.users u ON t.giver_id = u.id -- 抓取賣家資訊
WHERE t.receiver_id = v_current_uid
  AND t.transaction_status = p_status
ORDER BY t.updated_at DESC;
END IF;
END;
$$;


-- =============================================
-- API 3: (賣家) 更新 Giver 備註
-- =============================================
CREATE OR REPLACE FUNCTION public.update_giver_note(
    p_transaction_id BIGINT,
    p_note TEXT
)
              RETURNS JSON
              AS $$
              DECLARE
              v_giver_id UUID := auth.uid();
v_transaction transactions;
BEGIN
    IF v_giver_id IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

UPDATE public.transactions
SET giver_note = p_note, updated_at = NOW()
WHERE id = p_transaction_id
  AND giver_id = v_giver_id -- 安全檢查
  AND transaction_status = 'confirming' -- 只能在確認中修改
    RETURNING * INTO v_transaction;

IF v_transaction IS NULL THEN
    RAISE EXCEPTION '找不到交易，或您無權限，或交易已不在確認狀態';
END IF;

RETURN json_build_object('success', true, 'giver_note', v_transaction.giver_note);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================
-- API 4: (買家) 確認交易並更新 Receiver 備註
-- =============================================
CREATE OR REPLACE FUNCTION public.buyer_confirm_transaction(
    p_transaction_id BIGINT,
    p_note TEXT
)
              RETURNS JSON
              AS $$
              DECLARE
              v_receiver_id UUID := auth.uid();
v_transaction transactions;
BEGIN
    IF v_receiver_id IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

UPDATE public.transactions
SET
    receiver_note = p_note,
    transaction_status = 'pending', -- *** 關鍵：狀態推進到 "pending" ***
    updated_at = NOW()
WHERE id = p_transaction_id
  AND receiver_id = v_receiver_id -- 安全檢查
  AND transaction_status = 'confirming' -- 只能在確認中推進
    RETURNING * INTO v_transaction;

IF v_transaction IS NULL THEN
    RAISE EXCEPTION '找不到交易，或您無權限，或交易已不在確認狀態';
END IF;

RETURN json_build_object(
      'success', true,
      'new_status', v_transaction.transaction_status,
      'receiver_note', v_transaction.receiver_note
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================
-- API 5: (共用) 取消交易
-- =============================================
CREATE OR REPLACE FUNCTION public.cancel_transaction(
    p_transaction_id BIGINT
)
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_transaction transactions;
v_item items;
BEGIN
    IF v_current_uid IS NULL THEN RAISE EXCEPTION '使用者未登入'; END IF;

  -- 1. 鎖定交易
SELECT * INTO v_transaction
FROM public.transactions
WHERE id = p_transaction_id FOR UPDATE;

-- 2. 驗證
IF v_transaction IS NULL THEN RAISE EXCEPTION '交易不存在'; END IF;
IF v_transaction.giver_id != v_current_uid AND v_transaction.receiver_id != v_current_uid THEN
    RAISE EXCEPTION '您不是此交易的參與者';
END IF;
IF v_transaction.transaction_status NOT IN ('confirming', 'pending') THEN
    RAISE EXCEPTION '此交易狀態無法被取消';
END IF;

  -- 3. (交易 1) 更新交易狀態為 "cancelled"
UPDATE public.transactions
SET transaction_status = 'cancelled', updated_at = NOW()
WHERE id = p_transaction_id;

-- 4. (交易 2) 將物品重新上架
UPDATE public.items
SET listing_status = TRUE, updated_at = NOW()
WHERE id = v_transaction.item_id;

RETURN json_build_object('success', true, 'new_status', 'cancelled');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;