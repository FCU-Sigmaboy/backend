-- 徽章系統性能優化索引
-- 目的: 優化 batch_check_and_award_badges() 的查詢性能
-- 預期效果: 減少 50-70% 的徽章檢查時間

-- ============================================
-- 1. 優化徽章進度查詢
-- ============================================
-- 用於快速找出已達成條件的徽章
-- 在 batch_check_and_award_badges 中的關鍵查詢:
-- WHERE p.current_value >= p.target_value AND NOT EXISTS (...)
CREATE INDEX IF NOT EXISTS idx_user_badge_progress_achievable
    ON public.user_badge_progress(user_id, badge_id, current_value, target_value)
    WHERE current_value >= target_value;

-- 用於一般的徽章進度查詢（按用戶查詢）
CREATE INDEX IF NOT EXISTS idx_user_badge_progress_user_lookup
    ON public.user_badge_progress(user_id, badge_id);

-- ============================================
-- 2. 優化已獲得徽章查詢
-- ============================================
-- 用於檢查用戶是否已獲得某徽章（NOT EXISTS 子查詢）
CREATE INDEX IF NOT EXISTS idx_user_badges_user_badge_lookup
    ON public.user_badges(user_id, badge_id);

-- 用於按獲得時間排序的查詢（如最近獲得的徽章）
CREATE INDEX IF NOT EXISTS idx_user_badges_earned_at
    ON public.user_badges(user_id, earned_at DESC);

-- ============================================
-- 3. 優化徽章主表查詢
-- ============================================
-- 用於 sync_all_badge_progress 中按類別查詢徽章
CREATE INDEX IF NOT EXISTS idx_badges_category
    ON public.badges(category);

-- 用於同時按類別和 ID 前綴查詢（如 seller_%, buyer_%）
CREATE INDEX IF NOT EXISTS idx_badges_category_id_pattern
    ON public.badges(category, id);

-- ============================================
-- 4. 優化統計資料查詢
-- ============================================
-- profiles 表的 user_id 應該已經是 PRIMARY KEY
-- 但確保有複合索引用於統計欄位查詢
CREATE INDEX IF NOT EXISTS idx_profiles_transaction_stats
    ON public.profiles(user_id, total_sales_count, total_purchase_count);

CREATE INDEX IF NOT EXISTS idx_profiles_points_stats
    ON public.profiles(user_id, total_points_earned);

CREATE INDEX IF NOT EXISTS idx_profiles_streak_stats
    ON public.profiles(user_id, consecutive_login_days);

-- ============================================
-- 5. 優化點數記錄查詢
-- ============================================
-- 用於查詢特定類型的點數記錄（如簽到、交易收入）
CREATE INDEX IF NOT EXISTS idx_point_logs_user_type
    ON public.point_logs(user_id, type, created_at DESC);

-- ============================================
-- 分析說明
-- ============================================
-- COMMENT ON INDEX idx_user_badge_progress_achievable IS
--   '優化徽章授予查詢: 快速找出已達成但未獲得的徽章';
--
-- COMMENT ON INDEX idx_user_badges_user_badge_lookup IS
--   '優化重複檢查: 快速判斷用戶是否已擁有特定徽章';

-- ============================================
-- 驗證與測試
-- ============================================
-- 執行後可使用以下查詢驗證索引是否被使用:
--
-- EXPLAIN ANALYZE
-- SELECT b.*
-- FROM public.badges b
-- JOIN public.user_badge_progress p ON b.id = p.badge_id
-- WHERE p.user_id = 'some-uuid'
--   AND p.current_value >= p.target_value
--   AND NOT EXISTS (
--     SELECT 1 FROM public.user_badges ub
--     WHERE ub.user_id = p.user_id AND ub.badge_id = b.id
--   );
--
-- 應該看到使用 Index Scan 而非 Seq Scan

