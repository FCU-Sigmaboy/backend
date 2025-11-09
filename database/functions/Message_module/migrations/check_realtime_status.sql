-- 快速檢查 Realtime 狀態

SELECT '=== Realtime 配置檢查 ===' AS info;

-- 1. 檢查 REPLICA IDENTITY
SELECT
    '1. REPLICA IDENTITY' AS check_type,
    tablename,
    CASE relreplident
        WHEN 'd' THEN '❌ DEFAULT (需要改為 FULL)'
        WHEN 'n' THEN '❌ NOTHING (需要改為 FULL)'
        WHEN 'f' THEN '✅ FULL'
        WHEN 'i' THEN '⚠️  INDEX'
    END AS status
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
ORDER BY c.relname;

-- 2. 檢查 Publication
SELECT
    '2. Publication' AS check_type,
    tablename,
    CASE
        WHEN pubname = 'supabase_realtime' THEN '✅ 已加入'
        ELSE '❌ 未加入'
    END AS status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
UNION ALL
SELECT
    '2. Publication' AS check_type,
    t.table_name AS tablename,
    '❌ 未加入' AS status
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_name IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
  AND NOT EXISTS (
      SELECT 1 FROM pg_publication_tables p
      WHERE p.tablename = t.table_name
      AND p.pubname = 'supabase_realtime'
  )
ORDER BY tablename;

-- 3. 檢查 RLS 狀態
SELECT
    '3. RLS 狀態' AS check_type,
    tablename,
    CASE
        WHEN rowsecurity THEN '✅ 已啟用'
        ELSE '❌ 未啟用'
    END AS status
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
ORDER BY tablename;

-- 4. 檢查 RLS 策略
SELECT
    '4. RLS 策略' AS check_type,
    tablename,
    COUNT(*) || ' 條策略' AS status
FROM pg_policies
WHERE tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
GROUP BY tablename
ORDER BY tablename;

-- 總結
SELECT '=== 總結 ===' AS info;

DO $$
DECLARE
    v_replica_ok BOOLEAN;
    v_publication_ok BOOLEAN;
    v_rls_ok BOOLEAN;
BEGIN
    -- 檢查 REPLICA IDENTITY
    SELECT COUNT(*) = 3 INTO v_replica_ok
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
      AND c.relreplident = 'f';

    -- 檢查 Publication
    SELECT COUNT(*) = 3 INTO v_publication_ok
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2');

    -- 檢查 RLS
    SELECT COUNT(*) = 3 INTO v_rls_ok
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN ('conversations_v2', 'conversation_messages_v2', 'conversation_items_v2')
      AND rowsecurity = true;

    IF v_replica_ok AND v_publication_ok AND v_rls_ok THEN
        RAISE NOTICE '✅ Realtime 已完全配置!';
        RAISE NOTICE '   可以開始使用 subscribeToMessages() 訂閱即時訊息';
    ELSE
        RAISE NOTICE '❌ Realtime 配置不完整:';
        IF NOT v_replica_ok THEN
            RAISE NOTICE '   - REPLICA IDENTITY 需要設為 FULL';
        END IF;
        IF NOT v_publication_ok THEN
            RAISE NOTICE '   - 表未加入 supabase_realtime publication';
        END IF;
        IF NOT v_rls_ok THEN
            RAISE NOTICE '   - RLS 未啟用';
        END IF;
        RAISE NOTICE '   請執行 enable_realtime.sql 修正';
    END IF;
END $$;
