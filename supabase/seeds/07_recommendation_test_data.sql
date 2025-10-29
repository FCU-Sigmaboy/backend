-- =============================================
-- 推薦系統測試種子資料
-- Recommendation System Test Seed Data
-- 建立日期: 2025-10-29
-- =============================================

-- 注意：此檔案僅用於測試和開發環境
-- 在生產環境中不應執行此種子資料

-- =============================================
-- 1. 插入測試用戶互動記錄
-- =============================================

-- 假設已有一些測試用戶和物品
-- 這裡為前 3 個用戶生成互動記錄

DO $$
DECLARE
    v_user_id UUID;
    v_item_id BIGINT;
    v_interaction_types TEXT[] := ARRAY['view', 'click', 'favorite', 'share'];
    v_interaction_type TEXT;
    v_count INTEGER := 0;
BEGIN
    -- 為每個用戶生成 20-50 個隨機互動記錄
    FOR v_user_id IN (SELECT id FROM users LIMIT 3)
    LOOP
        -- 隨機生成 20-50 個互動
        v_count := 20 + floor(random() * 31)::INTEGER;
        
        FOR i IN 1..v_count
        LOOP
            -- 隨機選擇一個物品
            SELECT id INTO v_item_id
            FROM items
            WHERE listing_status = true
              AND user_id != v_user_id
            ORDER BY random()
            LIMIT 1;
            
            -- 隨機選擇互動類型
            v_interaction_type := v_interaction_types[1 + floor(random() * array_length(v_interaction_types, 1))::INTEGER];
            
            -- 插入互動記錄
            INSERT INTO user_interactions (
                user_id,
                item_id,
                interaction_type,
                interaction_metadata,
                created_at
            ) VALUES (
                v_user_id,
                v_item_id,
                v_interaction_type,
                jsonb_build_object(
                    'duration_seconds', floor(random() * 120)::INTEGER,
                    'source', 'test_seed',
                    'position', floor(random() * 20)::INTEGER
                ),
                NOW() - (random() * INTERVAL '60 days')
            );
        END LOOP;
        
        RAISE NOTICE 'Generated % interactions for user %', v_count, v_user_id;
    END LOOP;
END $$;

-- =============================================
-- 2. 為測試用戶計算偏好設定檔
-- =============================================

DO $$
DECLARE
    v_user_id UUID;
    v_function_exists BOOLEAN;
BEGIN
    -- Check if calculate_user_preferences function exists
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'calculate_user_preferences'
    ) INTO v_function_exists;
    
    IF NOT v_function_exists THEN
        RAISE WARNING 'calculate_user_preferences function does not exist, skipping preference calculation';
        RETURN;
    END IF;
    
    FOR v_user_id IN (SELECT DISTINCT user_id FROM user_interactions LIMIT 3)
    LOOP
        BEGIN
            PERFORM calculate_user_preferences(v_user_id);
            RAISE NOTICE 'Calculated preferences for user %', v_user_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Failed to calculate preferences for user %: %', v_user_id, SQLERRM;
        END;
    END LOOP;
END $$;

-- =============================================
-- 3. 生成物品相似度快取（選填）
-- =============================================

-- 為前 20 個物品計算相似度
DO $$
DECLARE
    v_item_id BIGINT;
    v_similar_items RECORD;
    v_function_exists BOOLEAN;
    v_count INTEGER := 0;
BEGIN
    -- Check if get_similar_items function exists
    SELECT EXISTS (
        SELECT 1 FROM pg_proc 
        WHERE proname = 'get_similar_items'
    ) INTO v_function_exists;
    
    IF NOT v_function_exists THEN
        RAISE WARNING 'get_similar_items function does not exist, skipping similarity cache generation';
        RETURN;
    END IF;
    
    FOR v_item_id IN (SELECT id FROM items WHERE listing_status = true LIMIT 20)
    LOOP
        BEGIN
            -- 使用 get_similar_items 函數找相似物品
            FOR v_similar_items IN 
                SELECT * FROM get_similar_items(v_item_id, 5)
            LOOP
                v_count := v_count + 1;
                -- 插入快取
                INSERT INTO item_similarity_cache (
                    item_id,
                    similar_item_id,
                    similarity_score,
                    similarity_type,
                    calculated_at
                ) VALUES (
                    v_item_id,
                    v_similar_items.item_id,
                    v_similar_items.similarity_score,
                    v_similar_items.similarity_reason,
                    NOW()
                )
                ON CONFLICT (item_id, similar_item_id, similarity_type) 
                DO UPDATE SET
                    similarity_score = EXCLUDED.similarity_score,
                    calculated_at = EXCLUDED.calculated_at;
            END LOOP;
            
            RAISE NOTICE 'Cached similarity for item %', v_item_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Failed to cache similarity for item %: %', v_item_id, SQLERRM;
        END;
    END LOOP;
    
    IF v_count > 0 THEN
        RAISE NOTICE 'Generated % similarity cache entries', v_count;
    ELSE
        RAISE WARNING 'No similarity cache entries generated';
    END IF;
END $$;

-- =============================================
-- 4. 插入一些測試推薦日誌
-- =============================================

DO $$
DECLARE
    v_user_id UUID;
    v_item_id BIGINT;
    v_count INTEGER := 0;
BEGIN
    -- 為每個有偏好的用戶生成推薦日誌
    FOR v_user_id IN (SELECT user_id FROM user_preferences LIMIT 3)
    LOOP
        -- 為該用戶生成 10 個推薦記錄
        FOR v_count IN 1..10
        LOOP
            -- 隨機選擇一個物品
            SELECT id INTO v_item_id
            FROM items
            WHERE listing_status = true
              AND user_id != v_user_id
            ORDER BY random()
            LIMIT 1;
            
            -- 插入推薦日誌
            INSERT INTO recommendation_logs (
                user_id,
                item_id,
                recommendation_score,
                recommendation_reason,
                algorithm_version,
                position,
                was_clicked,
                was_favorited,
                created_at
            ) VALUES (
                v_user_id,
                v_item_id,
                50 + random() * 50, -- 隨機分數 50-100
                (ARRAY['category_match', 'price_match', 'location_near', 'popular'])[1 + floor(random() * 4)::INTEGER],
                'v1.0',
                v_count - 1,
                random() > 0.8, -- 20% 機率被點擊
                random() > 0.9, -- 10% 機率被收藏
                NOW() - (random() * INTERVAL '7 days')
            );
        END LOOP;
        
        RAISE NOTICE 'Generated recommendation logs for user %', v_user_id;
    END LOOP;
END $$;

-- =============================================
-- 5. 驗證資料
-- =============================================

-- 統計資訊
DO $$
DECLARE
    v_interaction_count INTEGER;
    v_preference_count INTEGER;
    v_cache_count INTEGER;
    v_log_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_interaction_count FROM user_interactions;
    SELECT COUNT(*) INTO v_preference_count FROM user_preferences;
    SELECT COUNT(*) INTO v_cache_count FROM item_similarity_cache;
    SELECT COUNT(*) INTO v_log_count FROM recommendation_logs;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Seed Data Summary:';
    RAISE NOTICE 'User Interactions: %', v_interaction_count;
    RAISE NOTICE 'User Preferences: %', v_preference_count;
    RAISE NOTICE 'Item Similarity Cache: %', v_cache_count;
    RAISE NOTICE 'Recommendation Logs: %', v_log_count;
    RAISE NOTICE '========================================';
END $$;

-- =============================================
-- 測試查詢範例
-- =============================================

-- 查看某個用戶的偏好
-- SELECT * FROM user_preferences LIMIT 1;

-- 查看某個用戶的互動記錄
-- SELECT ui.*, i.title 
-- FROM user_interactions ui
-- JOIN items i ON ui.item_id = i.id
-- WHERE ui.user_id = (SELECT user_id FROM user_preferences LIMIT 1)
-- ORDER BY ui.created_at DESC
-- LIMIT 10;

-- 測試個性化推薦
-- SELECT * FROM get_personalized_items(
--     (SELECT user_id FROM user_preferences LIMIT 1),
--     10,
--     0,
--     '{}'::JSONB
-- );

-- 測試熱門物品
-- SELECT * FROM get_popular_items(10, 0, 7);

-- 測試相似物品
-- SELECT * FROM get_similar_items(
--     (SELECT id FROM items WHERE listing_status = true LIMIT 1),
--     5
-- );
