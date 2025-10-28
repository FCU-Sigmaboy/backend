-- ####################################################################
-- ### 獲取購買確認畫面資料 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_item_for_purchase_confirmation(
    p_item_id BIGINT -- (必填) 要確認的物品 ID
)
              RETURNS JSON -- 回傳包含物品和使用者點數的 JSON 物件
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_item items;
v_profile profiles;
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. 查找物品資料
SELECT * INTO v_item FROM public.items WHERE id = p_item_id;
IF v_item IS NULL THEN
     RAISE EXCEPTION '物品不存在 (ID: %)', p_item_id;
END IF;
IF v_item.listing_status = FALSE THEN
     RAISE EXCEPTION '物品目前無法索取';
END IF;
IF v_item.user_id = v_current_uid THEN
     RAISE EXCEPTION '無法索取自己的物品';
END IF;

  -- 3. 查找當前使用者的 profile (點數)
SELECT * INTO v_profile FROM public.profiles WHERE user_id = v_current_uid;
IF v_profile IS NULL THEN
      -- 這通常不應發生，除非使用者資料不完整
      RAISE EXCEPTION '找不到使用者 Profile 資料';
END IF;

  -- 4. 組裝並回傳 DTO
RETURN json_build_object(
        'item', json_build_object(
                'id', v_item.id,
                'title', v_item.title,
                'cover_image_url', v_item.image_urls[1],
                'price', v_item.price
                ),
        'user', json_build_object(
                'balance', v_profile.balance
                )
       );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ####################################################################
-- ### 執行購買 (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.execute_purchase(
    p_item_id BIGINT -- (必填) 要購買的物品 ID
)
              RETURNS JSON -- 回傳交易結果
              AS $$
              DECLARE
              v_receiver_id UUID := auth.uid(); -- 買家 (當前登入者)
v_item items;
v_giver_id UUID;
v_receiver_profile profiles;
v_transaction_id BIGINT;
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_receiver_id IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. *** 關鍵：鎖定物品以防止併發問題 ***
  --    SELECT ... FOR UPDATE 會鎖定該行，直到交易完成
SELECT * INTO v_item FROM public.items WHERE id = p_item_id FOR UPDATE;

-- 3. 再次檢查物品狀態 (可能在確認畫面後被別人買走)
IF v_item IS NULL THEN
     RAISE EXCEPTION '物品不存在 (ID: %)', p_item_id;
END IF;
IF v_item.listing_status = FALSE THEN
     RAISE EXCEPTION '物品已被索取或下架';
END IF;
v_giver_id := v_item.user_id; -- 賣家 ID
IF v_giver_id = v_receiver_id THEN
     RAISE EXCEPTION '無法索取自己的物品';
END IF;

  -- 4. 檢查買家點數
SELECT * INTO v_receiver_profile FROM public.profiles WHERE user_id = v_receiver_id;
IF v_receiver_profile.balance < v_item.price THEN
     RAISE EXCEPTION '點數餘額不足';
END IF;

  -- *** 開始執行交易 ***

  -- 5. 更新物品狀態為 "已下架"
UPDATE public.items
SET listing_status = FALSE, updated_at = NOW()
WHERE id = p_item_id;

-- 6. 扣除買家點數
UPDATE public.profiles
SET balance = balance - v_item.price, updated_at = NOW()
WHERE user_id = v_receiver_id;

-- 7. 增加賣家點數
UPDATE public.profiles
SET balance = balance + v_item.price, updated_at = NOW()
WHERE user_id = v_giver_id;

-- 8. (可選) 更新碳排放量 (此處僅為範例，實際計算可能更複雜)
UPDATE public.profiles
SET carbon_saved_kg = carbon_saved_kg + COALESCE(v_item.carbon_value, 0), updated_at = NOW()
WHERE user_id = v_receiver_id; -- 或根據您的規則更新 giver

-- 9. 插入交易紀錄
INSERT INTO public.transactions (
    item_id, giver_id, receiver_id, points_amount, carbon_amount_kg, transaction_status, completed_at
)
    VALUES (
               p_item_id, v_giver_id, v_receiver_id, v_item.price, COALESCE(v_item.carbon_value, 0), '已完成', NOW()
           )
        RETURNING id INTO v_transaction_id;

-- 10. 回傳成功訊息和交易 ID
RETURN json_build_object(
        'success', true,
        'message', '索取成功',
        'transaction_id', v_transaction_id,
        'new_balance', v_receiver_profile.balance - v_item.price -- 回傳更新後的點數
       );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;