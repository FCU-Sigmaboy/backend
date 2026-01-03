-- =============================================
-- 功能：獨立的註冊贈點機制 (Decoupled Version)
-- 策略：監聽 public.profiles 的新增事件，而非 auth.users
-- 優點：不需修改組員已寫好的 handle_new_user 函式
-- 類型：沿用現有的 'initial_gift'
-- 最後修改日期：2025-11-18
-- =============================================

-- 1. 建立獨立的贈點函式
CREATE OR REPLACE FUNCTION public.apply_welcome_reward()
              RETURNS TRIGGER AS $$
              DECLARE
              v_initial_points INTEGER := 500;
v_log_type TEXT := 'initial_gift';
BEGIN
-- 雖然組員的程式碼在建立 Profile 時可能將初始值設為 0，
-- 但本觸發器會在該筆資料插入後立即將 500 點補上去。

-- 更新剛剛建立好的 profile 餘額
UPDATE public.profiles
SET balance = balance + v_initial_points,
    updated_at = NOW()
WHERE user_id = NEW.user_id;

-- 寫入點數日誌 (使用現有的 initial_gift)
INSERT INTO public.point_logs (user_id, amount, "type", description, created_at)
VALUES (
           NEW.user_id,
           v_initial_points,
           v_log_type,
           '歡迎加入！註冊禮 500 點已自動入帳',
           NOW()
       );

RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 建立觸發器：監聽 public.profiles 的 INSERT
-- 當組員的 handle_new_user 執行完 INSERT profiles 後，此觸發器會緊接著啟動。
DROP TRIGGER IF EXISTS on_profile_created_reward ON public.profiles;

CREATE TRIGGER on_profile_created_reward
    AFTER INSERT ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.apply_welcome_reward();

DO $$
BEGIN
    RAISE NOTICE '✓ 獨立贈點機制已掛載成功。';
RAISE NOTICE '   - 類型：使用現有 initial_gift 類型';
RAISE NOTICE '   - 獎勵：500 點';
RAISE NOTICE '   - 觸發：public.profiles (AFTER INSERT)';
END $$;