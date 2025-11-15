-- =============================================
-- Migration: 開啟 Realtime (即時) 功能
-- 日期: 2025-11-14
-- 說明:
--   1. 將 'transactions' 表加入到 Supabase 的
--      'supabase_realtime' 廣播中，
--      這將允許前端 JS 訂閱此表的變更。
-- =============================================

BEGIN;

-- 將 'transactions' 資料表新增到 Supabase 的 Realtime 廣播
ALTER PUBLICATION supabase_realtime
ADD TABLE public.transactions;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功為 public.transactions 表開啟 Realtime 功能';
END $$;