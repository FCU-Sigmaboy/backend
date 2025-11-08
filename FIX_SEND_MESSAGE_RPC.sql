-- =====================================================
-- 修正 send_message RPC 函數
-- =====================================================
-- 問題: 函數只返回 BIGINT (message_id)
--       但前端期望返回完整的訊息物件
-- 錯誤: Cannot read properties of undefined (reading 'message_id')
-- =====================================================

DROP FUNCTION IF EXISTS public.send_message(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.send_message(
    p_conversation_id BIGINT,
    p_content TEXT
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID;
    v_new_message_id BIGINT;
BEGIN
    -- 1. 取得當前使用者
    v_current_uid := auth.uid();

    -- 2. 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 3. 驗證訊息內容
    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空'
            USING HINT = '請輸入有效的訊息內容',
                  ERRCODE = '22023';
    END IF;

    -- 4. 驗證使用者是對話的參與者
    IF NOT EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = p_conversation_id
          AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '您不是此對話的參與者'
            USING HINT = '只有對話參與者可以發送訊息',
                  ERRCODE = '42501';
    END IF;

    -- 5. 插入新訊息
    INSERT INTO public.conversation_messages (
        conversation_id,
        sender_id,
        content
    )
    VALUES (
        p_conversation_id,
        v_current_uid,
        TRIM(p_content)
    )
    RETURNING id INTO v_new_message_id;

    -- 6. 更新對話的 updated_at 時間戳記
    UPDATE public.conversations
    SET updated_at = now()
    WHERE id = p_conversation_id;

    -- 7. 使用子查詢返回完整訊息資料 (避免名稱衝突)
    RETURN QUERY
    SELECT
        sub.message_id,
        sub.sender_id,
        sub.content,
        sub.is_read,
        sub.sent_at
    FROM (
        SELECT
            cm.id AS message_id,
            cm.sender_id AS sender_id,
            cm.content AS content,
            cm.is_read AS is_read,
            cm.sent_at AS sent_at
        FROM public.conversation_messages cm
        WHERE cm.id = v_new_message_id
    ) AS sub;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '發送訊息時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

COMMENT ON FUNCTION public.send_message(BIGINT, TEXT) IS
'發送訊息到指定對話 (返回完整訊息物件)';

-- 授予權限
GRANT EXECUTE ON FUNCTION public.send_message(BIGINT, TEXT) TO authenticated;

-- =====================================================
-- 驗證修正
-- =====================================================
DO $$
DECLARE
    v_return_type TEXT;
BEGIN
    SELECT pg_get_function_result(p.oid) INTO v_return_type
    FROM pg_proc p
    WHERE p.proname = 'send_message'
      AND p.pronamespace = 'public'::regnamespace;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ send_message 函數修正完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '函數返回類型: %', v_return_type;
    RAISE NOTICE '';

    IF v_return_type LIKE '%message_id bigint%' THEN
        RAISE NOTICE '✅ 返回完整訊息物件 (正確)';
        RAISE NOTICE '   包含: message_id, sender_id, content, is_read, sent_at';
    ELSE
        RAISE WARNING '⚠️  返回類型可能不正確';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  下一步測試';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. 重新整理前端應用程式';
    RAISE NOTICE '2. 在聊天室輸入訊息並發送';
    RAISE NOTICE '3. 確認訊息成功發送並顯示';
    RAISE NOTICE '4. 檢查 Console 不應出現錯誤';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '修正內容:';
    RAISE NOTICE '  ✅ 返回 TABLE 而非 BIGINT';
    RAISE NOTICE '  ✅ 包含前端需要的所有欄位';
    RAISE NOTICE '  ✅ 使用子查詢避免名稱衝突';
    RAISE NOTICE '  ✅ 自動更新對話時間戳記';
    RAISE NOTICE '  ✅ 驗證使用者權限';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
