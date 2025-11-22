-- =============================================
-- 推薦系統更新 v2.0
-- Update Recommendation System v2.0
-- 建立日期: 2025-11-22
-- =============================================
-- 
-- 根據專案最新狀態更新推薦系統：
-- 1. 修復位置系統變更（items 不再有 location_id）
-- 2. 整合評價系統數據（賣家信譽）
-- 3. 整合交易系統數據（成功交易記錄）
-- 4. 整合追蹤系統（社交推薦維度）
-- 5. 優化推薦算法權重
-- =============================================

BEGIN;

-- =============================================
-- 1. 更新 get_personalized_items 函數
-- =============================================
CREATE OR REPLACE FUNCTION get_personalized_items(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_filter JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    description TEXT,
    price INTEGER,
    condition VARCHAR(20),
    image_urls TEXT[],
    tags TEXT[],
    distance_km NUMERIC,
    recommendation_score NUMERIC,
    recommendation_reason VARCHAR(50),
    seller_id UUID,
    seller_nickname VARCHAR(50),
    seller_rating NUMERIC,
    seller_review_count BIGINT,
    is_following_seller BOOLEAN
) 
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_preferences RECORD;
    v_user_location GEOGRAPHY;
BEGIN
    -- 獲取用戶偏好
    SELECT * INTO v_user_preferences
    FROM user_preferences
    WHERE user_id = p_user_id;
    
    -- 獲取用戶主要位置（修復：使用 users 表的主要位置）
    SELECT coordinates INTO v_user_location
    FROM locations
    WHERE user_id = p_user_id AND is_primary = true
    LIMIT 1;
    
    -- 如果用戶沒有偏好記錄，返回熱門物品
    IF v_user_preferences IS NULL THEN
        RETURN QUERY
        SELECT 
            i.id AS item_id,
            i.title,
            i.description,
            i.price,
            i.condition,
            i.image_urls,
            i.tags,
            NULL::NUMERIC AS distance_km,
            50.0::NUMERIC AS recommendation_score,
            'popular'::VARCHAR(50) AS recommendation_reason,
            u.id AS seller_id,
            u.nickname AS seller_nickname,
            u.avg_rating AS seller_rating,
            COALESCE(review_counts.review_count, 0) AS seller_review_count,
            false AS is_following_seller
        FROM items i
        JOIN users u ON i.user_id = u.id
        LEFT JOIN (
            SELECT reviewed_user_id, COUNT(*) as review_count
            FROM ratings
            GROUP BY reviewed_user_id
        ) review_counts ON u.id = review_counts.reviewed_user_id
        WHERE i.listing_status = true
          AND i.user_id != p_user_id
        ORDER BY i.created_at DESC
        LIMIT p_limit
        OFFSET p_offset;
        RETURN;
    END IF;
    
    -- 個性化推薦查詢（已更新以適應新架構）
    RETURN QUERY
    WITH scored_items AS (
        SELECT 
            i.id,
            i.title,
            i.description,
            i.price,
            i.condition,
            i.image_urls,
            i.tags,
            -- 修復：使用賣家的主要位置計算距離
            CASE 
                WHEN v_user_location IS NOT NULL AND seller_location.coordinates IS NOT NULL THEN
                    ST_Distance(seller_location.coordinates, v_user_location) / 1000
                ELSE NULL
            END AS distance_km,
            -- 計算推薦分數（新增多個維度）
            (
                -- 類別匹配分數 (35分，降低權重以平衡其他因素)
                CASE 
                    WHEN i.sub_category_id = ANY(v_user_preferences.preferred_sub_categories) THEN 35
                    WHEN sc.main_category_id = ANY(v_user_preferences.preferred_main_categories) THEN 18
                    ELSE 0
                END +
                -- 價格匹配分數 (18分)
                CASE 
                    WHEN i.price BETWEEN v_user_preferences.min_price_range AND v_user_preferences.max_price_range THEN
                        18 * (1 - LEAST(ABS(i.price - v_user_preferences.avg_price_viewed) / NULLIF(v_user_preferences.avg_price_viewed, 0), 1))
                    ELSE 0
                END +
                -- 狀態匹配分數 (12分)
                CASE 
                    WHEN i.condition = ANY(v_user_preferences.preferred_conditions) THEN 12
                    ELSE 0
                END +
                -- 地理距離分數 (10分)
                CASE 
                    WHEN v_user_location IS NOT NULL AND seller_location.coordinates IS NOT NULL THEN
                        10 * GREATEST(0, 1 - LEAST(ST_Distance(seller_location.coordinates, v_user_location) / 1000 / NULLIF(v_user_preferences.preferred_distance_km, 0), 1))
                    ELSE 0
                END +
                -- 新鮮度分數 (8分)
                8 * GREATEST(0, 1 - LEAST(EXTRACT(EPOCH FROM (NOW() - i.created_at)) / (7 * 24 * 3600), 1)) +
                -- 賣家評分加成 (10分，新增：基於評價系統）
                CASE 
                    WHEN u.avg_rating IS NOT NULL THEN
                        (u.avg_rating / 5.0) * 10
                    ELSE 0
                END +
                -- 賣家交易成功數加成 (5分，新增：基於交易歷史）
                LEAST(COALESCE(seller_stats.completed_transactions, 0)::NUMERIC * 0.5, 5) +
                -- 社交推薦加成 (7分，新增：追蹤的賣家）
                CASE 
                    WHEN following_check.is_following THEN 7
                    ELSE 0
                END
            ) AS score,
            -- 推薦原因（擴展）
            CASE 
                WHEN following_check.is_following THEN 'following_seller'
                WHEN i.sub_category_id = ANY(v_user_preferences.preferred_sub_categories) THEN 'category_match'
                WHEN i.condition = ANY(v_user_preferences.preferred_conditions) THEN 'condition_match'
                WHEN v_user_location IS NOT NULL AND seller_location.coordinates IS NOT NULL 
                     AND ST_DWithin(seller_location.coordinates, v_user_location, v_user_preferences.preferred_distance_km * 1000) THEN 'location_near'
                WHEN u.avg_rating >= 4.0 THEN 'high_rated_seller'
                ELSE 'general'
            END AS reason,
            u.id AS seller_id,
            u.nickname AS seller_nickname,
            u.avg_rating AS seller_rating,
            COALESCE(review_counts.review_count, 0) AS seller_review_count,
            COALESCE(following_check.is_following, false) AS is_following_seller
        FROM items i
        JOIN sub_categories sc ON i.sub_category_id = sc.id
        JOIN users u ON i.user_id = u.id
        -- 修復：使用賣家的主要位置而非物品的 location_id
        LEFT JOIN locations seller_location ON seller_location.user_id = i.user_id AND seller_location.is_primary = true
        -- 新增：檢查是否追蹤賣家
        LEFT JOIN (
            SELECT following_id, true as is_following
            FROM following
            WHERE follower_id = p_user_id
        ) following_check ON following_check.following_id = i.user_id
        -- 新增：賣家統計（交易成功數）
        LEFT JOIN (
            SELECT seller_id, COUNT(*) as completed_transactions
            FROM transactions
            WHERE status = 'completed'
            GROUP BY seller_id
        ) seller_stats ON seller_stats.seller_id = i.user_id
        -- 新增：賣家評價數
        LEFT JOIN (
            SELECT reviewed_user_id, COUNT(*) as review_count
            FROM ratings
            GROUP BY reviewed_user_id
        ) review_counts ON review_counts.reviewed_user_id = i.user_id
        WHERE i.listing_status = true
          AND i.user_id != p_user_id
          AND i.user_id != ALL(COALESCE(v_user_preferences.excluded_seller_ids, ARRAY[]::UUID[]))
          -- 應用過濾條件
          AND (
            (p_filter->>'main_category_id') IS NULL OR
            sc.main_category_id = (p_filter->>'main_category_id')::INTEGER
          )
          AND (
            (p_filter->>'sub_category_id') IS NULL OR
            i.sub_category_id = (p_filter->>'sub_category_id')::INTEGER
          )
          AND (
            (p_filter->>'min_price') IS NULL OR
            i.price >= (p_filter->>'min_price')::INTEGER
          )
          AND (
            (p_filter->>'max_price') IS NULL OR
            i.price <= (p_filter->>'max_price')::INTEGER
          )
        ORDER BY score DESC, i.created_at DESC
        LIMIT p_limit
        OFFSET p_offset
    )
    SELECT 
        si.id AS item_id,
        si.title,
        si.description,
        si.price,
        si.condition,
        si.image_urls,
        si.tags,
        si.distance_km,
        si.score AS recommendation_score,
        si.reason AS recommendation_reason,
        si.seller_id,
        si.seller_nickname,
        si.seller_rating,
        si.seller_review_count,
        si.is_following_seller
    FROM scored_items si;
END;
$$;

COMMENT ON FUNCTION get_personalized_items IS 
'獲取個性化推薦物品 v2.0 - 已更新以適應新的位置系統，整合評價、交易和追蹤數據';

-- =============================================
-- 2. 新增：基於社交網絡的推薦函數
-- =============================================
CREATE OR REPLACE FUNCTION get_following_items(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    description TEXT,
    price INTEGER,
    condition VARCHAR(20),
    image_urls TEXT[],
    seller_id UUID,
    seller_nickname VARCHAR(50),
    seller_rating NUMERIC,
    created_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.id AS item_id,
        i.title,
        i.description,
        i.price,
        i.condition,
        i.image_urls,
        u.id AS seller_id,
        u.nickname AS seller_nickname,
        u.avg_rating AS seller_rating,
        i.created_at
    FROM items i
    JOIN users u ON i.user_id = u.id
    JOIN following f ON f.following_id = i.user_id
    WHERE f.follower_id = p_user_id
      AND i.listing_status = true
    ORDER BY i.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION get_following_items IS 
'獲取追蹤的賣家的最新物品 - 社交推薦';

-- =============================================
-- 3. 新增：基於高評價賣家的推薦函數
-- =============================================
CREATE OR REPLACE FUNCTION get_high_rated_seller_items(
    p_min_rating NUMERIC DEFAULT 4.0,
    p_min_reviews INTEGER DEFAULT 3,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    description TEXT,
    price INTEGER,
    condition VARCHAR(20),
    image_urls TEXT[],
    seller_id UUID,
    seller_nickname VARCHAR(50),
    seller_rating NUMERIC,
    review_count BIGINT
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.id AS item_id,
        i.title,
        i.description,
        i.price,
        i.condition,
        i.image_urls,
        u.id AS seller_id,
        u.nickname AS seller_nickname,
        u.avg_rating AS seller_rating,
        review_counts.review_count
    FROM items i
    JOIN users u ON i.user_id = u.id
    JOIN (
        SELECT reviewed_user_id, COUNT(*) as review_count, AVG(score) as avg_score
        FROM ratings
        GROUP BY reviewed_user_id
        HAVING COUNT(*) >= p_min_reviews AND AVG(score) >= p_min_rating
    ) review_counts ON review_counts.reviewed_user_id = u.id
    WHERE i.listing_status = true
    ORDER BY review_counts.avg_score DESC, review_counts.review_count DESC, i.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION get_high_rated_seller_items IS 
'獲取高評價賣家的物品 - 基於評價系統的推薦';

-- =============================================
-- 4. 更新 calculate_user_preferences 函數
--    新增：考慮交易成功的物品偏好
-- =============================================
CREATE OR REPLACE FUNCTION calculate_user_preferences(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_preferred_main_categories INTEGER[];
    v_preferred_sub_categories INTEGER[];
    v_avg_price NUMERIC;
    v_preferred_conditions VARCHAR(20)[];
    v_preferred_tags TEXT[];
    v_total_interactions INTEGER;
BEGIN
    -- 計算偏好的主分類（基於互動次數，加權交易成功）
    SELECT ARRAY_AGG(main_category_id ORDER BY weighted_count DESC)
    INTO v_preferred_main_categories
    FROM (
        SELECT 
            sc.main_category_id, 
            SUM(
                CASE 
                    WHEN ui.interaction_type = 'favorite' THEN 3
                    WHEN ui.interaction_type = 'contact_seller' THEN 2
                    ELSE 1
                END
            ) as weighted_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        JOIN sub_categories sc ON i.sub_category_id = sc.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
        GROUP BY sc.main_category_id
        ORDER BY weighted_count DESC
        LIMIT 5
    ) sub;
    
    -- 計算偏好的子分類（加權）
    SELECT ARRAY_AGG(sub_category_id ORDER BY weighted_count DESC)
    INTO v_preferred_sub_categories
    FROM (
        SELECT 
            i.sub_category_id,
            SUM(
                CASE 
                    WHEN ui.interaction_type = 'favorite' THEN 3
                    WHEN ui.interaction_type = 'contact_seller' THEN 2
                    ELSE 1
                END
            ) as weighted_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
        GROUP BY i.sub_category_id
        ORDER BY weighted_count DESC
        LIMIT 10
    ) sub;
    
    -- 計算平均瀏覽價格（包含已完成交易的物品，權重更高）
    SELECT 
        SUM(price * weight) / SUM(weight)
    INTO v_avg_price
    FROM (
        SELECT 
            i.price,
            CASE 
                WHEN t.status = 'completed' THEN 5
                WHEN ui.interaction_type = 'favorite' THEN 3
                WHEN ui.interaction_type = 'contact_seller' THEN 2
                ELSE 1
            END as weight
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        LEFT JOIN transactions t ON t.item_id = i.id AND t.buyer_id = p_user_id
        WHERE ui.user_id = p_user_id
          AND ui.interaction_type IN ('view', 'click', 'favorite')
          AND ui.created_at > NOW() - INTERVAL '90 days'
    ) weighted_prices;
    
    -- 計算偏好的物品狀態
    SELECT ARRAY_AGG(DISTINCT condition ORDER BY interaction_count DESC)
    INTO v_preferred_conditions
    FROM (
        SELECT i.condition, COUNT(*) AS interaction_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
        GROUP BY i.condition
        ORDER BY interaction_count DESC
        LIMIT 3
    ) sub;
    
    -- 計算偏好的標籤
    SELECT ARRAY_AGG(tag ORDER BY tag_count DESC)
    INTO v_preferred_tags
    FROM (
        SELECT UNNEST(i.tags) AS tag, COUNT(*) AS tag_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
          AND i.tags IS NOT NULL
        GROUP BY tag
        ORDER BY tag_count DESC
        LIMIT 10
    ) sub;
    
    -- 計算總互動次數
    SELECT COUNT(*)
    INTO v_total_interactions
    FROM user_interactions
    WHERE user_id = p_user_id;
    
    -- 插入或更新用戶偏好
    INSERT INTO user_preferences (
        user_id,
        preferred_main_categories,
        preferred_sub_categories,
        avg_price_viewed,
        min_price_range,
        max_price_range,
        preferred_conditions,
        preferred_tags,
        total_interactions,
        last_interaction_at,
        preference_score,
        updated_at
    ) VALUES (
        p_user_id,
        COALESCE(v_preferred_main_categories, ARRAY[]::INTEGER[]),
        COALESCE(v_preferred_sub_categories, ARRAY[]::INTEGER[]),
        COALESCE(v_avg_price, 0),
        GREATEST(COALESCE(v_avg_price * 0.5, 0)::INTEGER, 0),
        COALESCE((v_avg_price * 1.5)::INTEGER, 999999),
        COALESCE(v_preferred_conditions, ARRAY[]::VARCHAR[]),
        COALESCE(v_preferred_tags, ARRAY[]::TEXT[]),
        COALESCE(v_total_interactions, 0),
        NOW(),
        LEAST(COALESCE(v_total_interactions, 0) * 2, 100),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        preferred_main_categories = EXCLUDED.preferred_main_categories,
        preferred_sub_categories = EXCLUDED.preferred_sub_categories,
        avg_price_viewed = EXCLUDED.avg_price_viewed,
        min_price_range = EXCLUDED.min_price_range,
        max_price_range = EXCLUDED.max_price_range,
        preferred_conditions = EXCLUDED.preferred_conditions,
        preferred_tags = EXCLUDED.preferred_tags,
        total_interactions = EXCLUDED.total_interactions,
        last_interaction_at = EXCLUDED.last_interaction_at,
        preference_score = EXCLUDED.preference_score,
        updated_at = NOW();
END;
$$;

COMMENT ON FUNCTION calculate_user_preferences IS 
'計算並更新用戶偏好設定檔 v2.0 - 已更新以使用加權互動和交易數據';

COMMIT;

-- =============================================
-- Migration 完成通知
-- =============================================
DO $$
BEGIN
    RAISE NOTICE '╔════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║   推薦系統更新 v2.0 完成                               ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ ✓ 已修復位置系統變更                                  ║';
    RAISE NOTICE '║ ✓ 已整合評價系統（賣家信譽）                          ║';
    RAISE NOTICE '║ ✓ 已整合交易系統（成功交易記錄）                      ║';
    RAISE NOTICE '║ ✓ 已整合追蹤系統（社交推薦）                          ║';
    RAISE NOTICE '║ ✓ 新增社交推薦函數                                    ║';
    RAISE NOTICE '║ ✓ 新增高評價賣家推薦函數                              ║';
    RAISE NOTICE '║ ✓ 優化推薦算法權重                                    ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║ 新功能:                                                ║';
    RAISE NOTICE '║ - get_following_items() 追蹤賣家的物品                ║';
    RAISE NOTICE '║ - get_high_rated_seller_items() 高評價賣家物品        ║';
    RAISE NOTICE '║ - 推薦分數現包含社交和信譽維度                        ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════╝';
END $$;
