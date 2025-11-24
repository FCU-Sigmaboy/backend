-- 1. 查找約束名稱 (可選，但推薦先運行這段來確認名稱)
-- SELECT conname FROM pg_constraint WHERE conrelid = 'public.transactions'::regclass AND contype = 'f';

-- 2. 移除 FOREIGN KEY 約束
-- (此動作不可逆，一旦執行，資料庫將不再自動執行完整性檢查)
ALTER TABLE public.transactions
    DROP CONSTRAINT transactions_item_id_fkey;

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功移除 transactions 表對 items 表的 FOREIGN KEY 約束。';
RAISE NOTICE '   現在可以 DELETE 已取消交易的 items 。';
END $$;


/*
-- ####################################################################
-- ### 恢復約束：transactions.item_id -> items.id
-- ####################################################################

-- 這是恢復被移除約束的命令
ALTER TABLE public.transactions
    ADD CONSTRAINT transactions_item_id_fkey
        FOREIGN KEY (item_id)
            REFERENCES public.items (id)
            ON DELETE RESTRICT; -- 恢復原有的 RESTRICT 行為

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功恢復 transactions 表對 items 表的 FOREIGN KEY 約束。';
RAISE NOTICE '   警告：如果存在任何已被刪除的物品但仍在 transactions 表中被引用，此命令將失敗。';
END $$;

 */