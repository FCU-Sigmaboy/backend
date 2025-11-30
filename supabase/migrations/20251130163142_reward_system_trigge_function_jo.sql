-- 統計欄位自動更新機制
-- Trigger 1: 更新銷售/購買統計並檢查徽章
-- 合併統計更新和徽章檢查，確保執行順序正確
CREATE OR REPLACE FUNCTION update_transaction_stats()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    -- 只在交易完成時更新統計
    IF NEW.transaction_status = 'completed' AND
       (OLD.transaction_status IS NULL OR OLD.transaction_status != 'completed') THEN

        -- 步驟 1: 更新賣家統計
        UPDATE public.profiles
        SET total_sales_count = total_sales_count + 1,
            updated_at = now()
        WHERE user_id = NEW.giver_id;

        -- 步驟 2: 更新買家統計
        UPDATE public.profiles
        SET total_purchase_count = total_purchase_count + 1,
            updated_at = now()
        WHERE user_id = NEW.receiver_id;

        -- 步驟 3: 統計更新後，檢查並授予徽章
        -- 注意: 此為同步執行，會影響交易完成時間
        -- 但確保徽章即時授予並使用最新的統計數據
        -- 性能影響: 約 31 個徽章檢查 + 可能的授予操作
        PERFORM batch_check_and_award_badges(NEW.giver_id);
        PERFORM batch_check_and_award_badges(NEW.receiver_id);

    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_transaction_stats
    AFTER UPDATE ON public.transactions
    FOR EACH ROW
EXECUTE FUNCTION update_transaction_stats();

-- Trigger 2: 更新點數累積統計
CREATE OR REPLACE FUNCTION update_points_earned_stats()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    -- 只計算賣出收入
    IF NEW.type = 'transaction_income' AND NEW.amount > 0 THEN
        UPDATE public.profiles
        SET total_points_earned = total_points_earned + NEW.amount,
            updated_at = now()
        WHERE user_id = NEW.user_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_points_earned
    AFTER INSERT ON public.point_logs
    FOR EACH ROW
EXECUTE FUNCTION update_points_earned_stats();

