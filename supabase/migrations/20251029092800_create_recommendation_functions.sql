-- =============================================
-- 推薦系統 RPC 函數
-- Recommendation System RPC Functions
-- 建立日期: 2025-10-29
-- =============================================

-- =============================================
-- 1. get_personalized_items - 獲取個性化推薦物品
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
    location_id BIGINT
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
    
    -- 獲取用戶主要位置
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
            i.location_id
        FROM items i
        JOIN users u ON i.user_id = u.id
        WHERE i.listing_status = true
          AND i.user_id != p_user_id
        ORDER BY i.created_at DESC
        LIMIT p_limit
        OFFSET p_offset;
        RETURN;
    END IF;
    
    -- 個性化推薦查詢
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
            i.location_id,
            CASE 
                WHEN v_user_location IS NOT NULL THEN
                    ST_Distance(l.coordinates, v_user_location) / 1000
                ELSE NULL
            END AS distance_km,
            -- 計算推薦分數
            (
                -- 類別匹配分數 (40分)
                CASE 
                    WHEN i.sub_category_id = ANY(v_user_preferences.preferred_sub_categories) THEN 40
                    WHEN sc.main_category_id = ANY(v_user_preferences.preferred_main_categories) THEN 20
                    ELSE 0
                END +
                -- 價格匹配分數 (20分)
                CASE 
                    WHEN i.price BETWEEN v_user_preferences.min_price_range AND v_user_preferences.max_price_range THEN
                        20 * (1 - LEAST(ABS(i.price - v_user_preferences.avg_price_viewed) / NULLIF(v_user_preferences.avg_price_viewed, 0), 1))
                    ELSE 0
                END +
                -- 狀態匹配分數 (15分)
                CASE 
                    WHEN i.condition = ANY(v_user_preferences.preferred_conditions) THEN 15
                    ELSE 0
                END +
                -- 地理距離分數 (10分)
                CASE 
                    WHEN v_user_location IS NOT NULL THEN
                        10 * GREATEST(0, 1 - LEAST(ST_Distance(l.coordinates, v_user_location) / 1000 / NULLIF(v_user_preferences.preferred_distance_km, 0), 1))
                    ELSE 0
                END +
                -- 新鮮度分數 (10分)
                10 * GREATEST(0, 1 - LEAST(EXTRACT(EPOCH FROM (NOW() - i.created_at)) / (7 * 24 * 3600), 1)) +
                -- 賣家評分加成 (5分)
                COALESCE(u.avg_rating, 0)
            ) AS score,
            CASE 
                WHEN i.sub_category_id = ANY(v_user_preferences.preferred_sub_categories) THEN 'category_match'
                WHEN i.condition = ANY(v_user_preferences.preferred_conditions) THEN 'condition_match'
                WHEN v_user_location IS NOT NULL AND ST_DWithin(l.coordinates, v_user_location, v_user_preferences.preferred_distance_km * 1000) THEN 'location_near'
                ELSE 'general'
            END AS reason,
            u.id AS seller_id,
            u.nickname AS seller_nickname,
            u.avg_rating AS seller_rating
        FROM items i
        JOIN sub_categories sc ON i.sub_category_id = sc.id
        JOIN locations l ON i.location_id = l.id
        JOIN users u ON i.user_id = u.id
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
        si.location_id
    FROM scored_items si;
END;
$$;

-- =============================================
-- 2. calculate_user_preferences - 計算用戶偏好
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
    -- 計算偏好的主分類（基於互動次數）
    SELECT ARRAY_AGG(main_category_id ORDER BY interaction_count DESC)
    INTO v_preferred_main_categories
    FROM (
        SELECT sc.main_category_id, COUNT(*) AS interaction_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        JOIN sub_categories sc ON i.sub_category_id = sc.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
        GROUP BY sc.main_category_id
        ORDER BY interaction_count DESC
        LIMIT 5
    ) sub;
    
    -- 計算偏好的子分類
    SELECT ARRAY_AGG(sub_category_id ORDER BY interaction_count DESC)
    INTO v_preferred_sub_categories
    FROM (
        SELECT i.sub_category_id, COUNT(*) AS interaction_count
        FROM user_interactions ui
        JOIN items i ON ui.item_id = i.id
        WHERE ui.user_id = p_user_id
          AND ui.created_at > NOW() - INTERVAL '90 days'
        GROUP BY i.sub_category_id
        ORDER BY interaction_count DESC
        LIMIT 10
    ) sub;
    
    -- 計算平均瀏覽價格
    SELECT AVG(i.price)
    INTO v_avg_price
    FROM user_interactions ui
    JOIN items i ON ui.item_id = i.id
    WHERE ui.user_id = p_user_id
      AND ui.interaction_type IN ('view', 'click')
      AND ui.created_at > NOW() - INTERVAL '90 days';
    
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
        LEAST(COALESCE(v_total_interactions, 0) * 2, 100),  -- 簡單的偏好完整度計算
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

-- =============================================
-- 3. get_similar_items - 獲取相似物品
-- =============================================
CREATE OR REPLACE FUNCTION get_similar_items(
    p_item_id BIGINT,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    price INTEGER,
    condition VARCHAR(20),
    image_urls TEXT[],
    similarity_score NUMERIC,
    similarity_reason VARCHAR(50)
) 
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_item RECORD;
BEGIN
    -- 獲取源物品資訊
    SELECT i.*, sc.main_category_id
    INTO v_source_item
    FROM items i
    JOIN sub_categories sc ON i.sub_category_id = sc.id
    WHERE i.id = p_item_id;
    
    IF v_source_item IS NULL THEN
        RETURN;
    END IF;
    
    -- 查找相似物品
    RETURN QUERY
    SELECT 
        i.id AS item_id,
        i.title,
        i.price,
        i.condition,
        i.image_urls,
        (
            -- 子分類相同 (50分)
            CASE WHEN i.sub_category_id = v_source_item.sub_category_id THEN 50 ELSE 0 END +
            -- 主分類相同 (20分)
            CASE WHEN sc.main_category_id = v_source_item.main_category_id THEN 20 ELSE 0 END +
            -- 價格相近 (20分)
            20 * GREATEST(0, 1 - ABS(i.price - v_source_item.price)::NUMERIC / NULLIF(v_source_item.price, 0)) +
            -- 狀態相同 (10分)
            CASE WHEN i.condition = v_source_item.condition THEN 10 ELSE 0 END
        ) AS similarity_score,
        CASE 
            WHEN i.sub_category_id = v_source_item.sub_category_id THEN 'same_subcategory'
            WHEN sc.main_category_id = v_source_item.main_category_id THEN 'same_category'
            ELSE 'similar_price'
        END AS similarity_reason
    FROM items i
    JOIN sub_categories sc ON i.sub_category_id = sc.id
    WHERE i.id != p_item_id
      AND i.listing_status = true
      AND (
        i.sub_category_id = v_source_item.sub_category_id OR
        sc.main_category_id = v_source_item.main_category_id OR
        ABS(i.price - v_source_item.price) <= v_source_item.price * 0.5
      )
    ORDER BY similarity_score DESC, i.created_at DESC
    LIMIT p_limit;
END;
$$;

-- =============================================
-- 4. track_interaction - 記錄用戶互動並更新偏好
-- =============================================
CREATE OR REPLACE FUNCTION track_interaction(
    p_user_id UUID,
    p_item_id BIGINT,
    p_interaction_type VARCHAR(20),
    p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- 插入互動記錄
    INSERT INTO user_interactions (
        user_id,
        item_id,
        interaction_type,
        interaction_metadata,
        created_at
    ) VALUES (
        p_user_id,
        p_item_id,
        p_interaction_type,
        p_metadata,
        NOW()
    );
    
    -- 如果是重要互動（收藏、點擊），則異步觸發偏好更新
    -- 這裡可以用 pg_notify 通知後台任務
    IF p_interaction_type IN ('favorite', 'click', 'contact_seller') THEN
        PERFORM pg_notify('preference_update', json_build_object(
            'user_id', p_user_id,
            'timestamp', NOW()
        )::text);
    END IF;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        -- 記錄錯誤但不中斷主流程
        RAISE WARNING 'Failed to track interaction: %', SQLERRM;
        RETURN FALSE;
END;
$$;

-- =============================================
-- 5. get_popular_items - 獲取熱門物品
-- =============================================
CREATE OR REPLACE FUNCTION get_popular_items(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_days INTEGER DEFAULT 7
)
RETURNS TABLE (
    item_id BIGINT,
    title VARCHAR(50),
    description TEXT,
    price INTEGER,
    condition VARCHAR(20),
    image_urls TEXT[],
    popularity_score NUMERIC,
    view_count BIGINT,
    favorite_count BIGINT
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
        (
            COALESCE(interaction_count.count, 0) * 1.0 +
            COALESCE(favorite_count.count, 0) * 2.0 +
            COALESCE(view_count.count, 0) * 0.5
        ) AS popularity_score,
        COALESCE(view_count.count, 0) AS view_count,
        COALESCE(favorite_count.count, 0) AS favorite_count
    FROM items i
    LEFT JOIN (
        SELECT item_id, COUNT(*) as count
        FROM user_interactions
        WHERE created_at > NOW() - INTERVAL '1 day' * p_days
        GROUP BY item_id
    ) interaction_count ON i.id = interaction_count.item_id
    LEFT JOIN (
        SELECT item_id, COUNT(*) as count
        FROM favorites
        WHERE created_at > NOW() - INTERVAL '1 day' * p_days
        GROUP BY item_id
    ) favorite_count ON i.id = favorite_count.item_id
    LEFT JOIN (
        SELECT item_id, COUNT(*) as count
        FROM user_interactions
        WHERE interaction_type = 'view' 
          AND created_at > NOW() - INTERVAL '1 day' * p_days
        GROUP BY item_id
    ) view_count ON i.id = view_count.item_id
    WHERE i.listing_status = true
    ORDER BY popularity_score DESC, i.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- =============================================
-- 註解說明
-- =============================================

COMMENT ON FUNCTION get_personalized_items IS '獲取個性化推薦物品 - 基於用戶偏好計算推薦分數';
COMMENT ON FUNCTION calculate_user_preferences IS '計算並更新用戶偏好設定檔 - 基於最近90天的互動記錄';
COMMENT ON FUNCTION get_similar_items IS '獲取相似物品 - 基於物品屬性的相似度計算';
COMMENT ON FUNCTION track_interaction IS '記錄用戶互動行為並觸發偏好更新通知';
COMMENT ON FUNCTION get_popular_items IS '獲取熱門物品 - 基於互動次數和收藏數計算熱門度';
