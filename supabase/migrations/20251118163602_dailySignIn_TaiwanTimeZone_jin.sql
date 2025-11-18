-- =============================================
-- API: 每日簽到 (RPC)
-- 對應前端: dailySignIn
-- 功能: 使用者每日簽到以獲取點數獎勵
-- (V3 版 - 按照前端提供的獎勵規則)
-- =============================================

CREATE OR REPLACE FUNCTION public.daily_check_in()
              RETURNS JSON
              AS $$
              DECLARE
              v_current_uid UUID := auth.uid();
v_profile profiles;
-- 以 台灣 的 "日期" 為準
v_today DATE := (NOW() AT TIME ZONE 'Asia/Taipei')::DATE;

v_points_awarded INT := 0;
v_streak_day INT;
v_next_reward_days INT := 0; -- 距離下次獎勵的天數
v_next_milestone INT;
v_message TEXT;
v_new_balance INT;
BEGIN
    -- 1. 驗證
    IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. 鎖定使用者的 profile 紀錄
SELECT * INTO v_profile
FROM public.profiles
WHERE user_id = v_current_uid FOR UPDATE;

IF v_profile IS NULL THEN
    RAISE EXCEPTION '找不到使用者 Profile 資料';
END IF;

  -- 3. 核心檢查：判斷連續狀態

IF v_profile.last_login_date = v_today THEN
    -- === 情況 A: 今天已經簽到過了 ===
    v_message := '您今天已經簽到過了';
v_points_awarded := 0;
v_streak_day := v_profile.consecutive_login_days;

ELSIF v_profile.last_login_date = (v_today - 1) THEN
    -- === 情況 B: 連續登入！ ===
    v_streak_day := v_profile.consecutive_login_days + 1;
v_message := '簽到成功！';

ELSE
    -- === 情況 C: 連續中斷或首次簽到 ===
    v_streak_day := 1;
v_message := '簽到成功！';
END IF;

  -- 4. *** 核心：套用您在前端 JS 中定義的獎勵規則 ***
v_points_awarded := CASE v_streak_day
      WHEN 3 THEN 10
      WHEN 7 THEN 20
      WHEN 14 THEN 30
      WHEN 30 THEN 50
      WHEN 100 THEN 200
      ELSE 5 -- 預設獎勵 (包含 day 1, 2, 4, 5, 6 等)
  END;

  -- 5. *** 核心：計算 next_reward (距離下個里程碑的天數) ***
v_next_milestone := CASE
      WHEN v_streak_day < 3 THEN 3
      WHEN v_streak_day < 7 THEN 7
      WHEN v_streak_day < 14 THEN 14
      WHEN v_streak_day < 30 THEN 30
      WHEN v_streak_day < 100 THEN 100
      ELSE 0 -- 100 天是最後一個里程碑
  END;

IF v_next_milestone > 0 THEN
    v_next_reward_days := v_next_milestone - v_streak_day;
ELSE
    v_next_reward_days := 0; -- 已達成所有
END IF;

  -- 6. 如果是「重複簽到」，則重置獎勵為 0
IF v_profile.last_login_date = v_today THEN
    v_points_awarded := 0;

RETURN json_build_object(
        'success', false,
        'message', v_message,
        'points_awarded', v_points_awarded,
        'streak_day', v_streak_day,
        'next_reward', v_next_reward_days
    );
END IF;

  -- 7. *** 執行原子性更新 ***

  -- (交易 1) 更新 profiles: 點數、連續天數、上次登入日期
UPDATE public.profiles
SET
    balance = balance + v_points_awarded,
    consecutive_login_days = v_streak_day,
    last_login_date = v_today,
    updated_at = NOW()
WHERE user_id = v_current_uid
    RETURNING balance INTO v_new_balance;

-- (交易 2) 插入 point_logs 日誌
INSERT INTO public.point_logs (user_id, amount, "type", description, created_at)
VALUES (v_current_uid, v_points_awarded, 'daily_login', v_message || ' (連續 ' || v_streak_day || ' 天)', NOW());

-- (可選) 在這裡呼叫 `check_point_achievements(v_current_uid)` 來檢查累計成就

-- 8. 回傳成功 DTO
RETURN json_build_object(
      'success', true,
      'message', v_message,
      'points_awarded', v_points_awarded,
      'streak_day', v_streak_day,
      'next_reward', v_next_reward_days,
      'new_balance', v_new_balance
  );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;