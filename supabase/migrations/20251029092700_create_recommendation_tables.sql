-- =============================================
-- 用戶喜好物品推薦系統 - 資料庫架構
-- User Preference-Based Recommendation System
-- 建立日期: 2025-10-29
-- =============================================

-- =============================================
-- 1. user_interactions (用戶互動記錄表)
-- =============================================
CREATE TABLE public.user_interactions (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    item_id BIGINT NOT NULL,
    interaction_type VARCHAR(20) NOT NULL CHECK (
        interaction_type IN ('view', 'click', 'favorite', 'unfavorite', 'share', 'search', 'contact_seller')
    ),
    interaction_metadata JSONB DEFAULT '{}',  -- 額外資訊，如停留時間、來源等
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE
);

-- 建立索引優化查詢效能
CREATE INDEX idx_user_interactions_user_id ON public.user_interactions(user_id);
CREATE INDEX idx_user_interactions_item_id ON public.user_interactions(item_id);
CREATE INDEX idx_user_interactions_type ON public.user_interactions(interaction_type);
CREATE INDEX idx_user_interactions_created_at ON public.user_interactions(created_at DESC);
CREATE INDEX idx_user_interactions_user_type ON public.user_interactions(user_id, interaction_type);

-- =============================================
-- 2. user_preferences (用戶偏好設定檔表)
-- =============================================
CREATE TABLE public.user_preferences (
    user_id UUID PRIMARY KEY,
    
    -- 類別偏好 (從 main_categories 和 sub_categories 計算)
    preferred_main_categories INTEGER[] DEFAULT ARRAY[]::INTEGER[],  -- 主分類 ID 陣列，按偏好排序
    preferred_sub_categories INTEGER[] DEFAULT ARRAY[]::INTEGER[],   -- 子分類 ID 陣列，按偏好排序
    
    -- 價格偏好
    avg_price_viewed NUMERIC(10, 2) DEFAULT 0,
    min_price_range INTEGER DEFAULT 0,
    max_price_range INTEGER DEFAULT 999999,
    
    -- 地理偏好
    preferred_distance_km INTEGER DEFAULT 50,  -- 偏好的物品距離（公里）
    preferred_locations GEOGRAPHY(Point, 4326)[] DEFAULT ARRAY[]::GEOGRAPHY[],
    
    -- 物品狀態偏好
    preferred_conditions VARCHAR(20)[] DEFAULT ARRAY[]::VARCHAR[],  -- ['全新', '近全新', '良好']
    
    -- 其他偏好
    preferred_tags TEXT[] DEFAULT ARRAY[]::TEXT[],  -- 偏好的標籤
    excluded_seller_ids UUID[] DEFAULT ARRAY[]::UUID[],  -- 不想看到的賣家
    
    -- 統計資訊
    total_interactions INTEGER DEFAULT 0,
    last_interaction_at TIMESTAMPTZ,
    preference_score NUMERIC(5, 2) DEFAULT 0.00,  -- 偏好完整度評分 (0-100)
    
    -- 時間戳記
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- 建立索引
CREATE INDEX idx_user_preferences_categories ON public.user_preferences USING GIN(preferred_main_categories);
CREATE INDEX idx_user_preferences_sub_categories ON public.user_preferences USING GIN(preferred_sub_categories);
CREATE INDEX idx_user_preferences_updated ON public.user_preferences(updated_at DESC);

-- 建立 updated_at 自動更新觸發器
CREATE TRIGGER trigger_user_preferences_updated_at
    BEFORE UPDATE ON public.user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 3. recommendation_logs (推薦記錄表)
-- =============================================
CREATE TABLE public.recommendation_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    item_id BIGINT NOT NULL,
    recommendation_score NUMERIC(5, 2) NOT NULL,  -- 推薦分數 (0-100)
    recommendation_reason VARCHAR(50),  -- 推薦原因: 'category_match', 'price_match', 'location_near', etc.
    algorithm_version VARCHAR(20) DEFAULT 'v1.0',
    position INTEGER,  -- 在推薦列表中的位置
    was_clicked BOOLEAN DEFAULT false,
    was_favorited BOOLEAN DEFAULT false,
    was_transacted BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE
);

-- 建立索引
CREATE INDEX idx_recommendation_logs_user_id ON public.recommendation_logs(user_id);
CREATE INDEX idx_recommendation_logs_item_id ON public.recommendation_logs(item_id);
CREATE INDEX idx_recommendation_logs_created_at ON public.recommendation_logs(created_at DESC);
CREATE INDEX idx_recommendation_logs_score ON public.recommendation_logs(recommendation_score DESC);

-- =============================================
-- 4. item_similarity_cache (物品相似度快取表)
-- =============================================
CREATE TABLE public.item_similarity_cache (
    item_id BIGINT NOT NULL,
    similar_item_id BIGINT NOT NULL,
    similarity_score NUMERIC(5, 2) NOT NULL,  -- 相似度分數 (0-100)
    similarity_type VARCHAR(30) NOT NULL,  -- 'category', 'price', 'tags', 'combined'
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    PRIMARY KEY (item_id, similar_item_id, similarity_type),
    FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE,
    FOREIGN KEY (similar_item_id) REFERENCES public.items(id) ON DELETE CASCADE
);

-- 建立索引
CREATE INDEX idx_item_similarity_item_id ON public.item_similarity_cache(item_id);
CREATE INDEX idx_item_similarity_score ON public.item_similarity_cache(similarity_score DESC);

-- =============================================
-- 5. 額外索引優化 (針對現有表)
-- =============================================

-- 優化物品查詢（結合上架狀態和創建時間）
CREATE INDEX IF NOT EXISTS idx_items_status_created 
ON public.items(listing_status, created_at DESC) 
WHERE listing_status = true;

-- 優化物品查詢（包含常用欄位）
CREATE INDEX IF NOT EXISTS idx_items_active 
ON public.items(id, sub_category_id, price, condition) 
WHERE listing_status = true;

-- =============================================
-- 說明與註解
-- =============================================

-- user_interactions: 記錄所有用戶與物品的互動行為
-- user_preferences: 經過計算和聚合的用戶偏好資料，用於快速推薦
-- recommendation_logs: 追蹤推薦系統輸出，用於效果分析和算法優化
-- item_similarity_cache: 預計算物品相似度，加速相似物品推薦

COMMENT ON TABLE public.user_interactions IS '用戶互動記錄表 - 追蹤所有用戶與物品的互動行為';
COMMENT ON TABLE public.user_preferences IS '用戶偏好設定檔表 - 儲存經過計算的用戶偏好資料';
COMMENT ON TABLE public.recommendation_logs IS '推薦記錄表 - 記錄推薦系統輸出用於追蹤效果';
COMMENT ON TABLE public.item_similarity_cache IS '物品相似度快取表 - 預計算物品之間的相似度';
