-- =============================================
-- Migration: 系統贈點 200000 點給所有使用者
-- 日期: 2025-11-14
-- 說明:
--   1. 建立一個 RPC 函式 `grant_initial_points_to_all_users`
--   2. 執行該函式，為所有使用者更新 'balance' 並新增 'point_logs'
-- =============================================

BEGIN;

-- 步驟 1: 建立用於執行贈點的 RPC 函式
CREATE OR REPLACE FUNCTION public.grant_initial_points_to_all_users(
    p_amount INT,
    p_log_type TEXT,
    p_description TEXT
)
              RETURNS JSON
              AS $$
              DECLARE
              updated_user_ids UUID[];
v_user_id UUID;
BEGIN
    -- 步驟 1a: 更新 'profiles' 表中所有使用者的 'balance'
    -- (使用 p_amount，而不是寫死的 200000，這樣函式未來可以重用)
    WITH updated_users AS (
    UPDATE public.profiles
    SET balance = p_amount,
        updated_at = NOW()
    -- (可選) 如果您只想給 'balance' 為 0 的人，可以取消註解下一行
    -- WHERE balance = 0
    RETURNING user_id -- 回傳所有被更新的使用者 ID
  )
SELECT array_agg(user_id) INTO updated_user_ids FROM updated_users;

-- 步驟 1b: (日誌) 為每一位被更新的使用者插入 'point_logs'
-- 使用 UNNEST 將 ID 陣列展開為資料列
INSERT INTO public.point_logs (user_id, amount, "type", description)
SELECT
    uid,
    p_amount,
    p_log_type,
    p_description
FROM unnest(updated_user_ids) AS uid;

-- 步驟 1c: 回傳成功訊息
RETURN json_build_object(
      'success', true,
      'message', '系統贈點完成',
      'users_affected_count', array_length(updated_user_ids, 1)
  );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- (使用 SECURITY DEFINER 確保此函式有權限更新所有 profiles 和 logs)


-- 步驟 2: (可選 - 僅供測試) 呼叫函式
-- SELECT public.grant_initial_points_to_all_users(
--     200000,                  -- p_amount: 點數
--     'initial_gift',          -- p_log_type: 日誌類型 (請確保 'initial_gift' 在您的 CHECK 約束中)
--     '開站活動 - 系統贈點'   -- p_description: 描述
-- );


COMMIT;

DO $$
BEGIN
    RAISE NOTICE '✓ 已成功建立 `grant_initial_points_to_all_users` 函式。';
RAISE NOTICE '!! 請手動執行 SELECT public.grant_initial_points_to_all_users(...) 來完成贈點 !!';
END $$;