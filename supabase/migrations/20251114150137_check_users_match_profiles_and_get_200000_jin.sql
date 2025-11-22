-- =============================================
-- Migration: 同步 Users 到 Profiles 並給予初始點數
-- 日期: 2025-11-14
-- 說明:
--   1. 找出在 'users' 表中存在，但在 'profiles' 表中缺失的使用者
--   2. 為這些使用者在 'profiles' 表中建立紀錄
--   3. 給予他們 20000 點初始點數
--   4. 在 'point_logs' 中新增日誌
-- =============================================

DO $$
    DECLARE
  -- ########## 設定參數 ##########
  v_initial_balance INT := 20000; -- 您指定的點數
v_log_type TEXT := 'initial_gift'; -- 日誌類型 (請確保 'initial_gift' 在您的 CHECK 約束中)
v_description TEXT := '新使用者/資料同步 - 初始點數';
  -- ############################

v_missing_user RECORD;
v_user_count INT := 0;
BEGIN
    -- 1. 迴圈遍歷所有 "遺失" profile 的使用者
    FOR v_missing_user IN
SELECT u.id
FROM public.users u
         LEFT JOIN public.profiles p ON u.id = p.user_id
WHERE p.user_id IS NULL -- <<< 關鍵：只抓 "users" 有 "profiles" 沒有的
    LOOP
-- 2. (原子操作) 插入 Profile 並賦予點數
BEGIN
INSERT INTO public.profiles (user_id, balance, created_at, updated_at)
VALUES (v_missing_user.id, v_initial_balance, NOW(), NOW());

-- 3. (原子操作) 插入點數日誌
INSERT INTO public.point_logs (user_id, amount, "type", description, created_at)
VALUES (v_missing_user.id, v_initial_balance, v_log_type, v_description, NOW());

RAISE NOTICE '已為使用者 % 新增 profile 並給予 % 點', v_missing_user.id, v_initial_balance;
v_user_count := v_user_count + 1;

EXCEPTION
      -- 如果在為某個使用者插入時發生錯誤 (例如 CHECK 約束失敗)
      -- 則回滾該使用者的操作，並記錄錯誤，然後繼續下一個
      WHEN OTHERS THEN
        RAISE WARNING '為使用者 % 新增 profile 時失敗: %', v_missing_user.id, SQLERRM;
END;
END LOOP;

RAISE NOTICE '✓ 資料同步完成，共處理了 % 位使用者。', v_user_count;
END $$;