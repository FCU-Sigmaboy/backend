-- =============================================
-- Migration: 修正 locations 表權限以支援 Edge Function
-- 日期: 2025-11-07
-- 說明:
--   1. 更新 locations 表的 RLS 政策
--   2. 允許 Service Role 繞過 RLS 進行 INSERT 操作
--   3. 確保 Edge Function 可以正常儲存地點資料
--   4. 保持用戶只能管理自己地點的安全性
-- =============================================

BEGIN;

-- =============================================
-- 步驟 1: 移除舊的 RLS 政策
-- =============================================

-- 刪除舊的 "Users can manage own locations" 政策(太寬鬆)
DROP POLICY IF EXISTS "Users can manage own locations" ON public.locations;

-- 刪除可能已存在的細分政策,以便重新建立
DROP POLICY IF EXISTS "Users can view own locations" ON public.locations;
DROP POLICY IF EXISTS "Users can insert own locations" ON public.locations;
DROP POLICY IF EXISTS "Users can update own locations" ON public.locations;
DROP POLICY IF EXISTS "Users can delete own locations" ON public.locations;

-- =============================================
-- 步驟 2: 建立細分的 RLS 政策
-- =============================================

-- 政策 1: 查詢 - 只能查看自己的地點
CREATE POLICY "Users can view own locations"
ON public.locations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- 政策 2: 插入 - 只能為自己建立地點
-- 注意:Service Role 會自動繞過 RLS,所以 Edge Function 可以正常運作
CREATE POLICY "Users can insert own locations"
ON public.locations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 政策 3: 更新 - 只能更新自己的地點
CREATE POLICY "Users can update own locations"
ON public.locations
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 政策 4: 刪除 - 只能刪除自己的地點
CREATE POLICY "Users can delete own locations"
ON public.locations
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- =============================================
-- 步驟 3: 授予必要的表格權限
-- =============================================

-- 確保 authenticated 角色有基本的 CRUD 權限
GRANT SELECT, INSERT, UPDATE, DELETE ON public.locations TO authenticated;

-- 確保 service_role 有完整權限(用於 Edge Function)
GRANT ALL ON public.locations TO service_role;

-- 確保序列權限
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO authenticated, service_role;

-- =============================================
-- 步驟 4: 驗證設定
-- =============================================

DO $$
DECLARE
    policy_count INT;
    rls_enabled BOOLEAN;
BEGIN
    -- 檢查 RLS 是否啟用
    SELECT relrowsecurity INTO rls_enabled
    FROM pg_class
    WHERE relname = 'locations' AND relnamespace = 'public'::regnamespace;

    IF NOT rls_enabled THEN
        RAISE WARNING 'RLS 未啟用於 locations 表!';
    ELSE
        RAISE NOTICE '✓ RLS 已啟用於 locations 表';
    END IF;

    -- 檢查政策數量
    SELECT COUNT(*) INTO policy_count
    FROM pg_policies
    WHERE tablename = 'locations' AND schemaname = 'public';

    RAISE NOTICE '✓ locations 表共有 % 個 RLS 政策', policy_count;

    IF policy_count < 4 THEN
        RAISE WARNING '政策數量少於預期(應該有 4 個)';
    END IF;
END $$;

-- =============================================
-- 步驟 5: 建立或替換測試函數
-- =============================================

-- 建立測試函數來驗證權限設定
CREATE OR REPLACE FUNCTION test_locations_permissions()
RETURNS TABLE (
    test_name TEXT,
    result TEXT,
    details TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    test_user_id UUID;
    test_location_id BIGINT;
BEGIN
    -- 測試 1: 檢查 RLS 是否啟用
    RETURN QUERY
    SELECT
        'RLS Status'::TEXT,
        CASE WHEN relrowsecurity THEN 'PASS' ELSE 'FAIL' END::TEXT,
        CASE WHEN relrowsecurity
            THEN 'RLS is enabled'
            ELSE 'RLS is NOT enabled'
        END::TEXT
    FROM pg_class
    WHERE relname = 'locations' AND relnamespace = 'public'::regnamespace;

    -- 測試 2: 檢查政策數量
    RETURN QUERY
    SELECT
        'Policy Count'::TEXT,
        CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        'Found ' || COUNT(*)::TEXT || ' policies (expected 4+)'::TEXT
    FROM pg_policies
    WHERE tablename = 'locations' AND schemaname = 'public';

    -- 測試 3: 檢查 authenticated 角色權限
    RETURN QUERY
    SELECT
        'Authenticated Role Permissions'::TEXT,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM information_schema.table_privileges
                WHERE table_name = 'locations'
                AND grantee = 'authenticated'
                AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
            ) THEN 'PASS'
            ELSE 'FAIL'
        END::TEXT,
        'Checking SELECT, INSERT, UPDATE, DELETE permissions'::TEXT;

    -- 測試 4: 檢查 service_role 權限
    RETURN QUERY
    SELECT
        'Service Role Permissions'::TEXT,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM information_schema.table_privileges
                WHERE table_name = 'locations'
                AND grantee = 'service_role'
            ) THEN 'PASS'
            ELSE 'FAIL'
        END::TEXT,
        'Checking service_role has permissions'::TEXT;

END;
$$;

COMMENT ON FUNCTION test_locations_permissions() IS
'測試 locations 表的權限設定是否正確';

COMMIT;

-- =============================================
-- 執行測試並顯示結果
-- =============================================

DO $$
DECLARE
    test_result RECORD;
    all_passed BOOLEAN := true;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════╗';
    RAISE NOTICE '║       Locations Table Permissions Test            ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════╣';

    FOR test_result IN
        SELECT * FROM test_locations_permissions()
    LOOP
        RAISE NOTICE '║ %-30s: %-4s ║', test_result.test_name, test_result.result;
        RAISE NOTICE '║   └─ %                                   ║', test_result.details;

        IF test_result.result != 'PASS' THEN
            all_passed := false;
        END IF;
    END LOOP;

    RAISE NOTICE '╠════════════════════════════════════════════════════╣';
    IF all_passed THEN
        RAISE NOTICE '║ 總體狀態: ✓ ALL TESTS PASSED                     ║';
    ELSE
        RAISE NOTICE '║ 總體狀態: ✗ SOME TESTS FAILED                    ║';
    END IF;
    RAISE NOTICE '╚════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;

-- =============================================
-- Migration 完成摘要
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '╔════════════════════════════════════════════════════╗';
    RAISE NOTICE '║   Migration 完成: 20251107100000                   ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ ✓ 移除舊的寬鬆政策                                ║';
    RAISE NOTICE '║ ✓ 建立 4 個細分的 RLS 政策:                       ║';
    RAISE NOTICE '║   - SELECT: 查看自己的地點                        ║';
    RAISE NOTICE '║   - INSERT: 建立自己的地點                        ║';
    RAISE NOTICE '║   - UPDATE: 更新自己的地點                        ║';
    RAISE NOTICE '║   - DELETE: 刪除自己的地點                        ║';
    RAISE NOTICE '║ ✓ 授予 authenticated 角色必要權限                 ║';
    RAISE NOTICE '║ ✓ 授予 service_role 完整權限                      ║';
    RAISE NOTICE '║ ✓ 建立測試函數                                    ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ Edge Function 支援:                                ║';
    RAISE NOTICE '║ - save-location 可以使用 Service Role Key         ║';
    RAISE NOTICE '║ - Service Role 會自動繞過 RLS                     ║';
    RAISE NOTICE '║ - 用戶資料安全性保持不變                          ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ 測試建議:                                          ║';
    RAISE NOTICE '║ 1. 測試 Edge Function:                             ║';
    RAISE NOTICE '║    curl -X POST .../save-location                  ║';
    RAISE NOTICE '║ 2. 檢查用戶權限:                                  ║';
    RAISE NOTICE '║    SELECT * FROM test_locations_permissions()      ║';
    RAISE NOTICE '║ 3. 驗證 RLS:                                       ║';
    RAISE NOTICE '║    以不同用戶身份測試 SELECT/INSERT/UPDATE        ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;

-- =============================================
-- 使用說明
-- =============================================

COMMENT ON TABLE public.locations IS
'用戶地點表 - 已更新 RLS 政策以支援 Edge Function
- RLS 已啟用,保護用戶資料
- Service Role 可繞過 RLS (用於 Edge Function)
- Authenticated 用戶只能管理自己的地點
- 支援 save-location Edge Function 操作';

-- =============================================
-- 手動測試指令
-- =============================================

/*
-- 測試 1: 檢查權限設定
SELECT * FROM test_locations_permissions();

-- 測試 2: 查看所有 RLS 政策
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'locations';

-- 測試 3: 檢查表格權限
SELECT
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'locations'
ORDER BY grantee, privilege_type;

-- 測試 4: 實際測試 INSERT(需要在 Edge Function 中執行)
-- 使用 Service Role Key 的客戶端應該可以成功執行
INSERT INTO locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES (
    'test-user-uuid',
    'POINT(120.7344 24.1817)',
    '家',
    true,
    '台中市南屯區'
);
*/
