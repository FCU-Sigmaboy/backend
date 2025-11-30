-- 徽章進度更新函式
-- 函式 1: update_badge_progress()

CREATE OR REPLACE FUNCTION public.update_badge_progress(
    p_user_id UUID,
    p_badge_id VARCHAR(50),
    p_current_value INTEGER
)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_target_value INTEGER;
BEGIN
    -- 取得徽章的目標值
    SELECT threshold_value INTO v_target_value
    FROM public.badges
    WHERE id = p_badge_id;

    IF v_target_value IS NULL THEN
        RAISE EXCEPTION '徽章不存在: %', p_badge_id;
    END IF;

    -- 更新或插入進度
    INSERT INTO public.user_badge_progress (user_id, badge_id, current_value, target_value)
    VALUES (p_user_id, p_badge_id, p_current_value, v_target_value)
    ON CONFLICT (user_id, badge_id) DO UPDATE
        SET current_value = EXCLUDED.current_value,
            last_updated_at = now();
END;
$$;

-- 函式 2: sync_all_badge_progress()
CREATE OR REPLACE FUNCTION public.sync_all_badge_progress(p_user_id UUID)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_profile profiles;
BEGIN
    -- 取得使用者統計資料
    SELECT * INTO v_profile
    FROM public.profiles
    WHERE user_id = p_user_id;

    IF v_profile IS NULL THEN
        RAISE EXCEPTION '找不到使用者 Profile';
    END IF;

    -- 同步連續簽到進度
    PERFORM update_badge_progress(p_user_id, badge_id, v_profile.consecutive_login_days)
    FROM badges WHERE category = 'streak';

    -- 同步賣家進度
    PERFORM update_badge_progress(p_user_id, badge_id, v_profile.total_sales_count)
    FROM badges WHERE category = 'transaction' AND id LIKE 'seller_%';

    -- 同步買家進度
    PERFORM update_badge_progress(p_user_id, badge_id, v_profile.total_purchase_count)
    FROM badges WHERE category = 'transaction' AND id LIKE 'buyer_%';

    -- 同步點數累積進度
    PERFORM update_badge_progress(p_user_id, badge_id, v_profile.total_points_earned)
    FROM badges WHERE category = 'points';

    -- 同步環保進度
    PERFORM update_badge_progress(p_user_id, badge_id, FLOOR(v_profile.carbon_saved_kg)::INTEGER)
    FROM badges WHERE category = 'carbon';

    -- 同步總交易進度
    PERFORM update_badge_progress(
            p_user_id,
            badge_id,
            v_profile.total_sales_count + v_profile.total_purchase_count
            )
    FROM badges WHERE id IN ('transaction_100', 'transaction_500');

    -- 同步首次交易進度
    IF v_profile.total_sales_count >= 1 THEN
        PERFORM update_badge_progress(p_user_id, 'first_sale', 1);
    END IF;

    IF v_profile.total_purchase_count >= 1 THEN
        PERFORM update_badge_progress(p_user_id, 'first_purchase', 1);
    END IF;
END;
$$;

-- 3.4 批次徽章檢查與授予
-- 函式: batch_check_and_award_badges()
CREATE OR REPLACE FUNCTION public.batch_check_and_award_badges(p_user_id UUID)
    RETURNS JSON
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_newly_earned badges[];
    v_badge badges;
    v_total_points_awarded INTEGER := 0;
BEGIN
    -- 1. 先同步所有徽章進度
    PERFORM sync_all_badge_progress(p_user_id);

    -- 2. 找出所有達成條件但未獲得的徽章
    FOR v_badge IN
        SELECT b.*
        FROM public.badges b
                 JOIN public.user_badge_progress p ON b.id = p.badge_id
        WHERE p.user_id = p_user_id
          AND p.current_value >= p.target_value
          AND NOT EXISTS (
            SELECT 1 FROM public.user_badges ub
            WHERE ub.user_id = p_user_id AND ub.badge_id = b.id
        )
        LOOP
            -- 授予徽章
            INSERT INTO public.user_badges (user_id, badge_id)
            VALUES (p_user_id, v_badge.id);

            -- 記錄到陣列
            v_newly_earned := array_append(v_newly_earned, v_badge);

            -- 累計點數獎勵
            v_total_points_awarded := v_total_points_awarded + v_badge.points_reward;
        END LOOP;

    -- 3. 批次發放點數獎勵
    IF v_total_points_awarded > 0 THEN
        INSERT INTO public.point_logs (user_id, amount, type, description)
        VALUES (
                   p_user_id,
                   v_total_points_awarded,
                   'quest_reward',
                   '獲得 ' || array_length(v_newly_earned, 1) || ' 個新徽章'
               );

        UPDATE public.profiles
        SET balance = balance + v_total_points_awarded,
            updated_at = now()
        WHERE user_id = p_user_id;
    END IF;

    -- 4. 回傳新獲得的徽章資訊
    RETURN json_build_object(
            'newly_earned_count', COALESCE(array_length(v_newly_earned, 1), 0),
            'total_points_awarded', v_total_points_awarded,
            'badges', (
                SELECT json_agg(
                               json_build_object(
                                       'badge_id', id,
                                       'name', name,
                                       'icon', icon,
                                       'description', description,
                                       'rarity', rarity,
                                       'points_reward', points_reward
                               )
                       )
                FROM unnest(v_newly_earned)
            )
           );
END;
$$;

-- 結束