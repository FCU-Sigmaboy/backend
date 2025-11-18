-- =============================================
-- Migration: 為 profiles 表新增連續登入欄位
-- Created at: 2025-11-18 09:43:21 UTC
-- Description: 新增 consecutive_login_days 和 last_login_date 欄位以追蹤
--              使用者的連續登入天數和上次登入日期
-- =============================================

BEGIN;

ALTER TABLE public.profiles

    -- 目前的連續登入天數
    ADD COLUMN consecutive_login_days INT NOT NULL DEFAULT 0,

    -- 上次登入的日期 (以 UTC 為準)
    ADD COLUMN last_login_date DATE;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功為 profiles 表新增 consecutive_login_days 和 last_login_date 欄位';
END $$;