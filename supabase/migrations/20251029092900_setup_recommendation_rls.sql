-- =============================================
-- 推薦系統 Row Level Security (RLS) 策略
-- Recommendation System RLS Policies
-- 建立日期: 2025-10-29
-- =============================================

-- =============================================
-- 1. user_interactions 表的 RLS 策略
-- =============================================

-- 啟用 RLS
ALTER TABLE public.user_interactions ENABLE ROW LEVEL SECURITY;

-- 用戶可以查看自己的互動記錄
CREATE POLICY "Users can view own interactions"
ON public.user_interactions FOR SELECT
USING (auth.uid() = user_id);

-- 用戶可以插入自己的互動記錄
CREATE POLICY "Users can insert own interactions"
ON public.user_interactions FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 用戶不能更新或刪除互動記錄（保持資料完整性）
-- 如需修改，應由管理員或系統服務執行

-- =============================================
-- 2. user_preferences 表的 RLS 策略
-- =============================================

-- 啟用 RLS
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- 用戶可以查看自己的偏好設定
CREATE POLICY "Users can view own preferences"
ON public.user_preferences FOR SELECT
USING (auth.uid() = user_id);

-- 用戶可以更新自己的偏好設定（某些欄位）
CREATE POLICY "Users can update own preferences"
ON public.user_preferences FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 系統服務可以插入偏好記錄
CREATE POLICY "Service role can insert preferences"
ON public.user_preferences FOR INSERT
WITH CHECK (auth.role() = 'service_role' OR auth.uid() = user_id);

-- =============================================
-- 3. recommendation_logs 表的 RLS 策略
-- =============================================

-- 啟用 RLS
ALTER TABLE public.recommendation_logs ENABLE ROW LEVEL SECURITY;

-- 用戶可以查看自己的推薦記錄
CREATE POLICY "Users can view own recommendation logs"
ON public.recommendation_logs FOR SELECT
USING (auth.uid() = user_id);

-- 只有系統服務可以插入推薦日誌
CREATE POLICY "Service role can insert logs"
ON public.recommendation_logs FOR INSERT
WITH CHECK (auth.role() = 'service_role');

-- 只有系統服務可以更新推薦日誌（用於追蹤點擊、收藏等）
CREATE POLICY "Service role can update logs"
ON public.recommendation_logs FOR UPDATE
USING (auth.role() = 'service_role');

-- =============================================
-- 4. item_similarity_cache 表的 RLS 策略
-- =============================================

-- 啟用 RLS
ALTER TABLE public.item_similarity_cache ENABLE ROW LEVEL SECURITY;

-- 所有已驗證用戶可以讀取相似度快取
CREATE POLICY "Authenticated users can view similarity cache"
ON public.item_similarity_cache FOR SELECT
USING (auth.role() = 'authenticated');

-- 只有系統服務可以寫入快取
CREATE POLICY "Service role can manage similarity cache"
ON public.item_similarity_cache FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');

-- =============================================
-- 5. 授予執行 RPC 函數的權限
-- =============================================

-- 授予已驗證用戶執行推薦函數的權限
GRANT EXECUTE ON FUNCTION get_personalized_items TO authenticated;
GRANT EXECUTE ON FUNCTION get_similar_items TO authenticated;
GRANT EXECUTE ON FUNCTION get_popular_items TO authenticated;
GRANT EXECUTE ON FUNCTION track_interaction TO authenticated;

-- 授予服務角色執行偏好計算函數的權限
GRANT EXECUTE ON FUNCTION calculate_user_preferences TO service_role;

-- 授予已驗證用戶執行偏好計算（用戶可以手動觸發更新自己的偏好）
GRANT EXECUTE ON FUNCTION calculate_user_preferences TO authenticated;

-- =============================================
-- 6. 授予表的基本權限
-- =============================================

-- user_interactions
GRANT SELECT, INSERT ON public.user_interactions TO authenticated;
GRANT ALL ON public.user_interactions TO service_role;

-- user_preferences
GRANT SELECT, UPDATE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;

-- recommendation_logs
GRANT SELECT ON public.recommendation_logs TO authenticated;
GRANT ALL ON public.recommendation_logs TO service_role;

-- item_similarity_cache
GRANT SELECT ON public.item_similarity_cache TO authenticated;
GRANT ALL ON public.item_similarity_cache TO service_role;

-- =============================================
-- 7. 授予序列的使用權限
-- =============================================

GRANT USAGE, SELECT ON SEQUENCE user_interactions_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE recommendation_logs_id_seq TO authenticated;

-- =============================================
-- 說明與註解
-- =============================================

-- RLS 策略說明:
-- 1. user_interactions: 用戶只能查看和插入自己的互動記錄，不能修改或刪除
-- 2. user_preferences: 用戶可以查看和更新自己的偏好，系統可以插入新記錄
-- 3. recommendation_logs: 用戶只能查看，只有系統服務可以寫入
-- 4. item_similarity_cache: 所有用戶可讀，只有系統可寫

COMMENT ON POLICY "Users can view own interactions" ON user_interactions IS '用戶只能查看自己的互動記錄';
COMMENT ON POLICY "Users can insert own interactions" ON user_interactions IS '用戶只能插入自己的互動記錄';
COMMENT ON POLICY "Users can view own preferences" ON user_preferences IS '用戶只能查看自己的偏好設定';
COMMENT ON POLICY "Users can update own preferences" ON user_preferences IS '用戶可以更新自己的偏好設定';
COMMENT ON POLICY "Service role can insert preferences" ON user_preferences IS '系統服務可以插入新的偏好記錄';
COMMENT ON POLICY "Users can view own recommendation logs" ON recommendation_logs IS '用戶可以查看自己的推薦記錄';
COMMENT ON POLICY "Service role can insert logs" ON recommendation_logs IS '只有系統服務可以插入推薦日誌';
COMMENT ON POLICY "Service role can update logs" ON recommendation_logs IS '只有系統服務可以更新推薦日誌';
COMMENT ON POLICY "Authenticated users can view similarity cache" ON item_similarity_cache IS '已驗證用戶可以查看相似度快取';
COMMENT ON POLICY "Service role can manage similarity cache" ON item_similarity_cache IS '只有系統服務可以管理相似度快取';
