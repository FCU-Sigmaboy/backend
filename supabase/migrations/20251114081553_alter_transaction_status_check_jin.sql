-- 步驟 1: 變更 CHECK 約束
-- (PostgreSQL 自動命名的約束名稱通常是 [table]_[column]_check)
-- (如果 "transactions_transaction_status_check" 不起作用，您可能需要去資料庫設定中查找確切名稱)
ALTER TABLE public.transactions
    DROP CONSTRAINT IF EXISTS transactions_transaction_status_check;

-- 步驟 2: 新增一個新的、包含 'confirming' 的 CHECK 約束
ALTER TABLE public.transactions
    ADD CONSTRAINT transactions_transaction_status_check
        CHECK (transaction_status IN (
                                      'pending',
                                      'confirmed',
                                      'in_progress',
                                      'completed',
                                      'cancelled',
                                      'confirming' -- <<< 加上這個新的狀態
            ));

-- (可選) 註解
-- COMMENT ON CONSTRAINT transactions_transaction_status_check ON public.transactions IS '確保交易狀態必須是預定義的值之一 (V2 流程)';