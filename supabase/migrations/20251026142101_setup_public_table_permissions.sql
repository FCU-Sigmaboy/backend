-- supabase/migrations/[timestamp]_setup_public_table_permissions.sql

-- =============================================
-- 設定公開表的權限
-- 這些表不需要 RLS,任何人都可以讀取
-- =============================================

BEGIN;

-- 1. 停用不需要 RLS 的表
ALTER TABLE public.main_categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_categories DISABLE ROW LEVEL SECURITY;

-- 2. 授予讀取權限給 anon 和 authenticated 角色
GRANT SELECT ON public.main_categories TO anon, authenticated;
GRANT SELECT ON public.sub_categories TO anon, authenticated;

-- 3. 確保序列也有權限
GRANT USAGE, SELECT ON SEQUENCE main_categories_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE sub_categories_id_seq TO anon, authenticated;

COMMIT;

-- 驗證設定
SELECT
    tablename,
    CASE WHEN rowsecurity THEN '✗ RLS 已啟用' ELSE '✓ RLS 已停用' END AS status
FROM pg_tables
WHERE tablename IN ('main_categories', 'sub_categories')
  AND schemaname = 'public';
