-- =====================================================
-- 修正 conversation_messages 的 RLS 策略
-- =====================================================
-- 問題: 缺少 INSERT 策略,導致無法發送訊息
-- 錯誤: new row violates row-level security policy
-- =====================================================
-- 執行方式: 複製全部內容到 Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. 刪除所有現有的 conversation_messages RLS 策略
DROP POLICY IF EXISTS "Conversation participants can view messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Conversation participants can send messages" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "Users can update messages in their conversations" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_select_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_insert_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_update_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_delete_policy" ON public.conversation_messages;

-- 2. 建立新的 RLS 策略

-- 2.1 SELECT 策略: 對話參與者可以查看訊息
CREATE POLICY "conversation_messages_select_policy"
ON public.conversation_messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- 2.2 INSERT 策略: 對話參與者可以發送訊息
CREATE POLICY "conversation_messages_insert_policy"
ON public.conversation_messages
FOR INSERT
TO authenticated
WITH CHECK (
    -- 發送者必須是當前使用者
    sender_id = auth.uid()
    -- 且必須是對話的參與者
    AND EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- 2.3 UPDATE 策略: 對話參與者可以更新訊息 (例如標記為已讀)
CREATE POLICY "conversation_messages_update_policy"
ON public.conversation_messages
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- 2.4 DELETE 策略: 訊息發送者可以刪除自己的訊息
CREATE POLICY "conversation_messages_delete_policy"
ON public.conversation_messages
FOR DELETE
TO authenticated
USING (
    sender_id = auth.uid()
);

-- 3. 確保 RLS 已啟用
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

-- 4. 確保 authenticated 角色有基本權限
GRANT SELECT, INSERT, UPDATE ON public.conversation_messages TO authenticated;

-- =====================================================
-- 驗證 RLS 策略
-- =====================================================
DO $$
DECLARE
    v_select_count INT;
    v_insert_count INT;
    v_update_count INT;
    v_delete_count INT;
    v_rls_enabled BOOLEAN;
    v_policy_name TEXT;
BEGIN
    -- 檢查 RLS 是否啟用
    SELECT rowsecurity INTO v_rls_enabled
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = 'conversation_messages';

    -- 統計各類型策略數量
    SELECT
        COUNT(*) FILTER (WHERE cmd = 'SELECT'),
        COUNT(*) FILTER (WHERE cmd = 'INSERT'),
        COUNT(*) FILTER (WHERE cmd = 'UPDATE'),
        COUNT(*) FILTER (WHERE cmd = 'DELETE')
    INTO
        v_select_count,
        v_insert_count,
        v_update_count,
        v_delete_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'conversation_messages';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  RLS 策略修正結果';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'RLS 狀態: %', CASE WHEN v_rls_enabled THEN '✅ 已啟用' ELSE '❌ 未啟用' END;
    RAISE NOTICE '';
    RAISE NOTICE '策略統計:';
    RAISE NOTICE '  SELECT 策略: % 個 %', v_select_count, CASE WHEN v_select_count > 0 THEN '✅' ELSE '❌' END;
    RAISE NOTICE '  INSERT 策略: % 個 %', v_insert_count, CASE WHEN v_insert_count > 0 THEN '✅' ELSE '❌' END;
    RAISE NOTICE '  UPDATE 策略: % 個 %', v_update_count, CASE WHEN v_update_count > 0 THEN '✅' ELSE '❌' END;
    RAISE NOTICE '  DELETE 策略: % 個 %', v_delete_count, CASE WHEN v_delete_count > 0 THEN '✅' ELSE '❌' END;
    RAISE NOTICE '';

    IF v_rls_enabled AND v_select_count > 0 AND v_insert_count > 0 THEN
        RAISE NOTICE '========================================';
        RAISE NOTICE '✅ RLS 策略修正成功！';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE '下一步測試:';
        RAISE NOTICE '  1. 重新整理前端應用程式';
        RAISE NOTICE '  2. 點擊「聯絡賣家」建立對話';
        RAISE NOTICE '  3. 嘗試發送訊息';
        RAISE NOTICE '  4. 確認訊息成功發送並顯示';
        RAISE NOTICE '';
    ELSE
        RAISE WARNING '⚠️  RLS 策略可能未完全設定';
        RAISE WARNING '請檢查上方的策略統計';
    END IF;

    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '詳細策略列表:';
    RAISE NOTICE '';

    -- 顯示所有策略
    FOR v_policy_name IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'conversation_messages'
        ORDER BY cmd, policyname
    LOOP
        RAISE NOTICE '  - %', v_policy_name;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;

-- =====================================================
-- 說明
-- =====================================================
--
-- RLS 策略說明:
--
-- 1. SELECT (查看訊息):
--    - 只能查看自己參與的對話中的訊息
--    - 檢查: conversations 表中 buyer_id 或 seller_id 是當前使用者
--
-- 2. INSERT (發送訊息):
--    - sender_id 必須是當前使用者
--    - 必須是對話的參與者 (buyer 或 seller)
--    - 這防止了:
--      a) 冒充他人發送訊息
--      b) 向不相關的對話發送訊息
--
-- 3. UPDATE (更新訊息):
--    - 對話參與者可以更新訊息
--    - 主要用於標記訊息為已讀
--
-- 4. DELETE (刪除訊息):
--    - 只有訊息發送者可以刪除自己的訊息
--
-- =====================================================
