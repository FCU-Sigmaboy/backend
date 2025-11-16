-- ####################################################################
-- ### 建立評價 (RPC)
-- ### Author: Chris
-- ### Date: 2025-11-06
-- ####################################################################

CREATE OR REPLACE FUNCTION public.create_review(
    p_transaction_id BIGINT,                     -- 交易 ID
    p_score SMALLINT,                            -- 評分 (1-5)
    p_comment TEXT DEFAULT NULL                  -- 評論內容（選填）
)
RETURNS TABLE (
    review_id BIGINT,
    transaction_id BIGINT,
    reviewer_id UUID,
    reviewed_user_id UUID,
    score SMALLINT,
    comment TEXT,
    created_at TIMESTAMPTZ,
    message TEXT
)
AS $$
DECLARE
    v_current_user_id UUID := auth.uid();        -- 當前登入用戶 ID
    v_transaction RECORD;                        -- 交易記錄
    v_reviewed_user_id UUID;                     -- 被評價者 ID
    v_new_review_id BIGINT;                      -- 新建立的評價 ID
    v_existing_review_count INT;                 -- 已存在的評價數量
BEGIN
    -- 1. 安全檢查：確認使用者已登入
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION '使用者未登入，無法建立評價';
    END IF;

    -- 2. 驗證評分範圍
    IF p_score < 1 OR p_score > 5 THEN
        RAISE EXCEPTION '評分必須在 1-5 之間';
    END IF;

    -- 3. 查詢交易記錄並驗證
    SELECT
        t.id,
        t.giver_id,
        t.receiver_id,
        t.transaction_status,
        t.item_id
    INTO v_transaction
    FROM public.transactions t
    WHERE t.id = p_transaction_id;

    -- 檢查交易是否存在
    IF NOT FOUND THEN
        RAISE EXCEPTION '交易不存在（ID: %）', p_transaction_id;
    END IF;

    -- 4. 驗證交易狀態必須是 completed
    IF v_transaction.transaction_status != 'completed' THEN
        RAISE EXCEPTION '只有已完成的交易才能建立評價（當前狀態: %）', v_transaction.transaction_status;
    END IF;

    -- 5. 驗證評價者是否為交易參與者
    IF v_current_user_id != v_transaction.giver_id AND v_current_user_id != v_transaction.receiver_id THEN
        RAISE EXCEPTION '您不是此交易的參與者，無法建立評價';
    END IF;

    -- 6. 判斷被評價者（交易的另一方）
    IF v_current_user_id = v_transaction.giver_id THEN
        v_reviewed_user_id := v_transaction.receiver_id;
    ELSE
        v_reviewed_user_id := v_transaction.giver_id;
    END IF;

    -- 7. 檢查是否已經評價過
    SELECT COUNT(*)
    INTO v_existing_review_count
    FROM public.ratings r
    WHERE r.transaction_id = p_transaction_id
      AND r.reviewer_id = v_current_user_id;

    IF v_existing_review_count > 0 THEN
        RAISE EXCEPTION '您已經對此交易建立過評價，無法重複評價';
    END IF;

    -- 8. 插入評價記錄
    INSERT INTO public.ratings (
        transaction_id,
        reviewer_id,
        reviewed_user_id,
        score,
        comment,
        created_at
    )
    VALUES (
        p_transaction_id,
        v_current_user_id,
        v_reviewed_user_id,
        p_score,
        p_comment,
        now()
    )
    RETURNING id INTO v_new_review_id;

    -- 9. 更新被評價者的平均評分
    UPDATE public.users
    SET avg_rating = COALESCE(
        (SELECT ROUND(AVG(r.score)::numeric, 2)
         FROM public.ratings r
         WHERE r.reviewed_user_id = v_reviewed_user_id),
        0.00  -- 沒有評價時設為 0.00
    ),
    updated_at = now()
    WHERE id = v_reviewed_user_id;

    -- 10. 回傳建立的評價資訊
    RETURN QUERY
    SELECT
        r.id AS review_id,
        r.transaction_id,
        r.reviewer_id,
        r.reviewed_user_id,
        r.score,
        r.comment,
        r.created_at,
        '評價建立成功'::TEXT AS message
    FROM public.ratings r
    WHERE r.id = v_new_review_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 設定函式註解
COMMENT ON FUNCTION public.create_review IS '建立評價功能：只有交易狀態為 completed 的交易參與者才能建立評價，每個交易每個評價者只能評價一次';
