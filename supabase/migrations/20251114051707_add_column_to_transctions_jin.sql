-- =============================================
-- Migration: 更新 transactions 表
-- 日期: 2025-11-14
-- 說明:
--   1. 新增 code 欄位，用於買家輸入的 6 位數確認碼
--   2. 新增 giver_note 欄位，供賣家備註
--   3. 新增 receiver_note 欄位，供買家備註
-- =============================================

BEGIN; -- (可選) 在事務中執行

ALTER TABLE public.transactions

    -- 新增 6 位數確認碼欄位
    -- 使用 TEXT 類型以支援前導零 (e.g., "001234")
    -- CHECK 約束確保它必須是 6 位數字
    ADD COLUMN code TEXT CHECK (code IS NULL OR code ~ '^[0-9]{6}$'),

    -- 新增賣家備註
    ADD COLUMN giver_note TEXT NULL,

    -- 新增買家備註
    ADD COLUMN receiver_note TEXT NULL;

COMMIT; -- (可選) 提交事務

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功為 transactions 表新增 code, giver_note, receiver_note 欄位';
END $$;