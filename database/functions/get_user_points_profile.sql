-- ####################################################################
-- ### 獲取使用者點數詳情 (RPC)
-- ### 對應前端: getUserPointsProfile
-- ### 因尚未有複雜的等級計算邏輯，current_level_tier 和 trust_level_tier 暫時先寫死
-- ####################################################################

CREATE OR REPLACE FUNCTION public.get_user_points_profile()
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_profile profiles;
v_total_earned BIGINT;
v_total_spent BIGINT;
v_total_sales_points BIGINT;
BEGIN
    -- 1. 安全檢查
    IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. 獲取 Profile 基本資料
SELECT * INTO v_profile
FROM public.profiles
WHERE user_id = v_current_uid;

IF v_profile IS NULL THEN
    RAISE EXCEPTION '找不到使用者資料';
END IF;

  -- 3. 計算總賺取 (所有正數金額)
SELECT COALESCE(SUM(amount), 0) INTO v_total_earned
FROM public.point_logs
WHERE user_id = v_current_uid AND amount > 0;

-- 4. 計算總花費 (所有負數金額的絕對值)
SELECT ABS(COALESCE(SUM(amount), 0)) INTO v_total_spent
FROM public.point_logs
WHERE user_id = v_current_uid AND amount < 0;

-- 5. 計算總銷售額 (類型為 transaction_income 的總和)
SELECT COALESCE(SUM(amount), 0) INTO v_total_sales_points
FROM public.point_logs
WHERE user_id = v_current_uid AND type = 'transaction_income';

-- 6. 回傳組裝好的 JSON
RETURN json_build_object(
    'user_id', v_current_uid,
    'current_balance', v_profile.balance,
    'total_earned', v_total_earned,
    'total_spent', v_total_spent,
    'daily_streak', v_profile.consecutive_login_days,
    'last_signin_date', v_profile.last_login_date,
    'current_level_tier', 2, -- (暫時固定值)
    'trust_level_tier', 1,   -- (暫時固定值)
    'total_sales_points', v_total_sales_points,
    'created_at', v_profile.created_at,
    'updated_at', v_profile.updated_at
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;