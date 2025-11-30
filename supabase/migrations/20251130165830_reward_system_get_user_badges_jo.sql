-- RPC 1: get_user_badges_with_progress()
CREATE OR REPLACE FUNCTION public.get_user_badges_with_progress(p_user_id UUID DEFAULT NULL)
    RETURNS JSON
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_target_user_id UUID;
BEGIN
    v_target_user_id := COALESCE(p_user_id, auth.uid());

    IF v_target_user_id IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 確保進度是最新的
    PERFORM sync_all_badge_progress(v_target_user_id);

    RETURN json_build_object(
            'user_id', v_target_user_id,
            'earned_badges', (
                SELECT json_agg(
                               json_build_object(
                                       'badge_id', b.id,
                                       'name', b.name,
                                       'icon', b.icon,
                                       'description', b.description,
                                       'rarity', b.rarity,
                                       'category', b.category,
                                       'points_reward', b.points_reward,
                                       'earned_at', ub.earned_at
                               )
                               ORDER BY ub.earned_at DESC
                       )
                FROM public.user_badges ub
                         JOIN public.badges b ON ub.badge_id = b.id
                WHERE ub.user_id = v_target_user_id
            ),
            'in_progress_badges', (
                SELECT json_agg(
                               json_build_object(
                                       'badge_id', b.id,
                                       'name', b.name,
                                       'icon', b.icon,
                                       'description', b.description,
                                       'rarity', b.rarity,
                                       'category', b.category,
                                       'points_reward', b.points_reward,
                                       'current_value', p.current_value,
                                       'target_value', p.target_value,
                                       'percentage', p.percentage
                               )
                               ORDER BY p.percentage DESC, b.threshold_value
                       )
                FROM public.user_badge_progress p
                         JOIN public.badges b ON p.badge_id = b.id
                WHERE p.user_id = v_target_user_id
                  AND NOT EXISTS (
                    SELECT 1 FROM public.user_badges ub
                    WHERE ub.user_id = v_target_user_id AND ub.badge_id = b.id
                )
            )
           );
END;
$$;

-- RPC 2: manually_check_badges() (手動觸發檢查)
CREATE OR REPLACE FUNCTION public.manually_check_badges()
    RETURNS JSON
    LANGUAGE plpgsql
    SECURITY DEFINER
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    RETURN batch_check_and_award_badges(v_current_uid);
END;
$$;
