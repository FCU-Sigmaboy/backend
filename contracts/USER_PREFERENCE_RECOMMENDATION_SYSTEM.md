# 用戶喜好物品推薦系統方案
# User Preference-Based Item Recommendation System Proposal

**專案**: 生態交換平台 (Second-Hand Trading Platform)  
**日期**: 2025-10-29  
**版本**: 1.0.0  
**狀態**: 提案中 (Proposal)

---

## 📋 目錄 (Table of Contents)

1. [系統概述](#系統概述)
2. [業務目標](#業務目標)
3. [技術架構](#技術架構)
4. [資料庫設計](#資料庫設計)
5. [推薦算法](#推薦算法)
6. [API 設計](#api-設計)
7. [實作計劃](#實作計劃)
8. [效能考量](#效能考量)
9. [安全性與隱私](#安全性與隱私)
10. [測試策略](#測試策略)
11. [未來擴展](#未來擴展)

---

## 系統概述

### 目的
為生態交換平台建立一個基於 Supabase 服務的智能推薦系統，根據用戶的瀏覽歷史、收藏行為、交易記錄和互動模式，為用戶推薦最相關的二手物品。

### 核心特性
- 🎯 **個性化推薦**: 基於用戶行為的個性化物品推薦
- 📊 **多維度分析**: 結合類別偏好、價格範圍、地理位置等因素
- 🔄 **實時更新**: 隨用戶行為即時調整推薦結果
- 🚀 **高效能**: 利用 Supabase 的原生功能實現快速查詢
- 🔒 **隱私保護**: 遵循資料保護原則，用戶資料安全

---

## 業務目標

### 主要目標
1. **提升用戶參與度**: 增加用戶在平台上的活躍時間和互動頻率
2. **促進交易完成**: 通過精準推薦提高物品交易成功率
3. **改善用戶體驗**: 減少用戶搜尋時間，快速找到感興趣的物品
4. **增加平台黏性**: 透過個性化服務提升用戶忠誠度

### 成功指標 (KPIs)
- 推薦物品點擊率 (CTR) > 15%
- 推薦物品收藏率 > 8%
- 推薦物品交易轉換率 > 3%
- 用戶日均瀏覽物品數提升 30%
- 用戶平台停留時間增加 25%

---

## 技術架構

### 架構概覽

```
┌─────────────────────────────────────────────────────────┐
│                      前端應用層                          │
│          (Vue.js / React / Mobile App)                  │
└─────────────────┬───────────────────────────────────────┘
                  │
                  │ HTTPS / REST API
                  │
┌─────────────────▼───────────────────────────────────────┐
│                  Supabase API Gateway                    │
│  ┌─────────────────────────────────────────────────┐   │
│  │            Edge Functions Layer                  │   │
│  │  ┌─────────────────────────────────────────┐   │   │
│  │  │  get-recommendations                     │   │   │
│  │  │  track-user-interaction                  │   │   │
│  │  │  calculate-preference-scores             │   │   │
│  │  └─────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │         PostgreSQL Database Layer               │   │
│  │  ┌─────────────────────────────────────────┐   │   │
│  │  │  Tables:                                 │   │   │
│  │  │  - user_interactions (新增)              │   │   │
│  │  │  - user_preferences (新增)               │   │   │
│  │  │  - recommendation_logs (新增)            │   │   │
│  │  │  - items (現有)                          │   │   │
│  │  │  - favorites (現有)                      │   │   │
│  │  │  - transactions (現有)                   │   │   │
│  │  └─────────────────────────────────────────┘   │   │
│  │  ┌─────────────────────────────────────────┐   │   │
│  │  │  RPC Functions:                          │   │   │
│  │  │  - get_personalized_items()              │   │   │
│  │  │  - calculate_item_score()                │   │   │
│  │  │  - get_similar_items()                   │   │   │
│  │  │  - update_user_preferences()             │   │   │
│  │  └─────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │            Realtime Subscriptions                │   │
│  │    (即時推送新推薦物品給用戶)                    │   │
│  └─────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│              External Services (Optional)                │
│  - Cron Jobs (定期重新計算推薦)                          │
│  - Analytics (追蹤推薦效果)                              │
└──────────────────────────────────────────────────────────┘
```

### 技術棧
- **資料庫**: PostgreSQL (Supabase 托管)
- **後端邏輯**: Supabase Edge Functions (Deno)
- **即時通訊**: Supabase Realtime
- **身份驗證**: Supabase Auth
- **儲存**: Supabase Storage (物品圖片)
- **RLS**: Row Level Security (資料安全)

---

## 資料庫設計

### 新增表結構

#### 1. user_interactions (用戶互動記錄表)
記錄用戶與物品的所有互動行為，用於分析用戶偏好。

```sql
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

-- 索引優化
CREATE INDEX idx_user_interactions_user_id ON public.user_interactions(user_id);
CREATE INDEX idx_user_interactions_item_id ON public.user_interactions(item_id);
CREATE INDEX idx_user_interactions_type ON public.user_interactions(interaction_type);
CREATE INDEX idx_user_interactions_created_at ON public.user_interactions(created_at DESC);
CREATE INDEX idx_user_interactions_user_type ON public.user_interactions(user_id, interaction_type);
```

#### 2. user_preferences (用戶偏好設定檔表)
儲存經過計算和聚合的用戶偏好資料，用於快速推薦。

```sql
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

-- 索引
CREATE INDEX idx_user_preferences_categories ON public.user_preferences USING GIN(preferred_main_categories);
CREATE INDEX idx_user_preferences_sub_categories ON public.user_preferences USING GIN(preferred_sub_categories);
CREATE INDEX idx_user_preferences_updated ON public.user_preferences(updated_at DESC);
```

#### 3. recommendation_logs (推薦記錄表)
記錄推薦系統的輸出，用於追蹤效果和優化算法。

```sql
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

-- 索引
CREATE INDEX idx_recommendation_logs_user_id ON public.recommendation_logs(user_id);
CREATE INDEX idx_recommendation_logs_item_id ON public.recommendation_logs(item_id);
CREATE INDEX idx_recommendation_logs_created_at ON public.recommendation_logs(created_at DESC);
CREATE INDEX idx_recommendation_logs_score ON public.recommendation_logs(recommendation_score DESC);
```

#### 4. item_similarity_cache (物品相似度快取表) - 可選
預先計算物品之間的相似度，提升推薦速度。

```sql
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

-- 索引
CREATE INDEX idx_item_similarity_item_id ON public.item_similarity_cache(item_id);
CREATE INDEX idx_item_similarity_score ON public.item_similarity_cache(similarity_score DESC);
```

### 更新現有表

無需修改現有表結構，但需要確保以下表的資料完整性：
- `items`: 確保 `sub_category_id`, `price`, `condition`, `tags` 等欄位資料完整
- `favorites`: 用於協同過濾推薦
- `transactions`: 用於分析成功交易模式
- `locations`: 用於地理位置推薦

---

## 推薦算法

### 混合推薦策略
採用多種推薦算法的組合，根據不同場景動態調整權重。

#### 1. 基於內容的推薦 (Content-Based Filtering)

**原理**: 根據物品屬性與用戶偏好的匹配度推薦。

**評分計算**:
```javascript
// 偽代碼
function calculateContentScore(user_preferences, item) {
  let score = 0;
  
  // 類別匹配 (40% 權重)
  if (user_preferences.preferred_sub_categories.includes(item.sub_category_id)) {
    score += 40;
  } else if (user_preferences.preferred_main_categories.includes(item.main_category_id)) {
    score += 20;
  }
  
  // 價格匹配 (20% 權重)
  if (item.price >= user_preferences.min_price_range && 
      item.price <= user_preferences.max_price_range) {
    let price_diff_ratio = Math.abs(item.price - user_preferences.avg_price_viewed) / 
                           user_preferences.avg_price_viewed;
    score += 20 * (1 - Math.min(price_diff_ratio, 1));
  }
  
  // 物品狀態匹配 (15% 權重)
  if (user_preferences.preferred_conditions.includes(item.condition)) {
    score += 15;
  }
  
  // 標籤匹配 (15% 權重)
  let tag_overlap = intersection(user_preferences.preferred_tags, item.tags).length;
  score += 15 * (tag_overlap / Math.max(user_preferences.preferred_tags.length, 1));
  
  // 地理距離 (10% 權重)
  let distance = calculateDistance(user_location, item_location);
  if (distance <= user_preferences.preferred_distance_km) {
    score += 10 * (1 - distance / user_preferences.preferred_distance_km);
  }
  
  return score;
}
```

#### 2. 協同過濾推薦 (Collaborative Filtering)

**原理**: 基於「喜歡類似物品的用戶也喜歡...」的邏輯。

**實作方式**:
```sql
-- 找出與目標用戶有相似收藏行為的用戶
WITH similar_users AS (
    SELECT 
        f2.user_id AS similar_user_id,
        COUNT(*) AS common_favorites
    FROM favorites f1
    JOIN favorites f2 ON f1.item_id = f2.item_id AND f1.user_id != f2.user_id
    WHERE f1.user_id = :target_user_id
    GROUP BY f2.user_id
    HAVING COUNT(*) >= 3  -- 至少有 3 個共同收藏
    ORDER BY common_favorites DESC
    LIMIT 10
),
-- 推薦這些相似用戶收藏的物品
recommended_items AS (
    SELECT 
        f.item_id,
        COUNT(DISTINCT f.user_id) AS recommendation_strength,
        AVG(i.price) AS avg_price
    FROM favorites f
    JOIN similar_users su ON f.user_id = su.similar_user_id
    JOIN items i ON f.item_id = i.id
    WHERE f.item_id NOT IN (
        SELECT item_id FROM favorites WHERE user_id = :target_user_id
    )
    AND i.listing_status = true
    GROUP BY f.item_id
    ORDER BY recommendation_strength DESC
    LIMIT 20
)
SELECT * FROM recommended_items;
```

#### 3. 熱門度推薦 (Popularity-Based)

**原理**: 推薦近期熱門或高互動的物品，適合新用戶冷啟動。

```sql
-- 計算物品熱門度分數
SELECT 
    i.id,
    i.title,
    (
        COALESCE(interaction_count.count, 0) * 1.0 +
        COALESCE(favorite_count.count, 0) * 2.0 +
        COALESCE(view_count.count, 0) * 0.5
    ) AS popularity_score
FROM items i
LEFT JOIN (
    SELECT item_id, COUNT(*) as count
    FROM user_interactions
    WHERE created_at > NOW() - INTERVAL '7 days'
    GROUP BY item_id
) interaction_count ON i.id = interaction_count.item_id
LEFT JOIN (
    SELECT item_id, COUNT(*) as count
    FROM favorites
    WHERE created_at > NOW() - INTERVAL '7 days'
    GROUP BY item_id
) favorite_count ON i.id = favorite_count.item_id
LEFT JOIN (
    SELECT item_id, COUNT(*) as count
    FROM user_interactions
    WHERE interaction_type = 'view' 
      AND created_at > NOW() - INTERVAL '7 days'
    GROUP BY item_id
) view_count ON i.id = view_count.item_id
WHERE i.listing_status = true
ORDER BY popularity_score DESC;
```

#### 4. 地理位置推薦 (Location-Based)

**原理**: 優先推薦地理位置接近的物品，提高交易可行性。

```sql
-- 使用 PostGIS 計算距離並推薦
SELECT 
    i.*,
    ST_Distance(l1.coordinates, l2.coordinates) / 1000 AS distance_km
FROM items i
JOIN locations l1 ON i.location_id = l1.id
JOIN locations l2 ON l2.user_id = :target_user_id AND l2.is_primary = true
WHERE i.listing_status = true
  AND ST_DWithin(
    l1.coordinates, 
    l2.coordinates, 
    :max_distance_meters
  )
ORDER BY distance_km ASC
LIMIT 50;
```

### 推薦融合策略

最終推薦分數 = 加權組合多種算法的結果：

```javascript
final_score = (
  content_based_score * 0.40 +
  collaborative_score * 0.30 +
  popularity_score * 0.15 +
  location_score * 0.15
)
```

權重可根據用戶類型動態調整：
- **新用戶**: 提高熱門度和地理位置權重
- **活躍用戶**: 提高基於內容和協同過濾權重
- **低活躍用戶**: 平衡各種權重

---

## API 設計

### Edge Functions

#### 1. get-recommendations
取得個性化推薦物品列表。

**端點**: `POST /functions/v1/get-recommendations`

**Request**:
```typescript
interface RecommendationRequest {
  user_id?: string;  // 選填，未登入用戶則使用匿名推薦
  limit?: number;    // 返回數量，預設 20
  offset?: number;   // 分頁偏移，預設 0
  exclude_item_ids?: number[];  // 排除的物品 ID
  filter?: {
    main_category_id?: number;
    sub_category_id?: number;
    max_distance_km?: number;
    min_price?: number;
    max_price?: number;
    condition?: string[];
  };
  algorithm?: 'hybrid' | 'content' | 'collaborative' | 'popular' | 'location';  // 預設 hybrid
}
```

**Response**:
```typescript
interface RecommendationResponse {
  success: boolean;
  data: {
    items: Array<{
      id: number;
      title: string;
      description: string;
      price: number;
      condition: string;
      image_urls: string[];
      tags: string[];
      distance_km?: number;
      recommendation_score: number;
      recommendation_reason: string;
      seller: {
        id: string;
        nickname: string;
        avg_rating: number;
      };
    }>;
    total_count: number;
    algorithm_used: string;
    personalization_level: number;  // 個性化程度 0-100
  };
  error?: string;
}
```

**實作邏輯**:
```typescript
// supabase/functions/get-recommendations/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { user_id, limit = 20, offset = 0, filter, algorithm = 'hybrid' } = await req.json()
    
    // 初始化 Supabase 客戶端
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    
    // 如果有 user_id，獲取用戶偏好
    let userPreferences = null
    if (user_id) {
      const { data } = await supabaseClient
        .from('user_preferences')
        .select('*')
        .eq('user_id', user_id)
        .single()
      userPreferences = data
    }
    
    // 根據算法類型調用不同的推薦邏輯
    let recommendedItems = []
    
    if (algorithm === 'hybrid' || algorithm === 'content') {
      // 調用基於內容的 RPC 函數
      const { data } = await supabaseClient.rpc('get_personalized_items', {
        p_user_id: user_id,
        p_limit: limit,
        p_offset: offset,
        p_filter: filter
      })
      recommendedItems = data || []
    }
    
    // 記錄推薦日誌
    if (user_id && recommendedItems.length > 0) {
      const logs = recommendedItems.map((item, index) => ({
        user_id: user_id,
        item_id: item.id,
        recommendation_score: item.score,
        recommendation_reason: item.reason,
        position: offset + index,
        algorithm_version: 'v1.0'
      }))
      
      await supabaseClient
        .from('recommendation_logs')
        .insert(logs)
    }
    
    return new Response(
      JSON.stringify({
        success: true,
        data: {
          items: recommendedItems,
          total_count: recommendedItems.length,
          algorithm_used: algorithm,
          personalization_level: userPreferences ? 75 : 25
        }
      }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    )
  }
})
```

#### 2. track-user-interaction
追蹤用戶互動行為。

**端點**: `POST /functions/v1/track-user-interaction`

**Request**:
```typescript
interface InteractionRequest {
  user_id: string;
  item_id: number;
  interaction_type: 'view' | 'click' | 'favorite' | 'unfavorite' | 'share' | 'contact_seller';
  metadata?: {
    duration_seconds?: number;  // 停留時間
    source?: string;  // 來源：推薦、搜尋、分類瀏覽等
    position?: number;  // 在列表中的位置
  };
}
```

**Response**:
```typescript
interface InteractionResponse {
  success: boolean;
  message: string;
  should_update_preferences: boolean;  // 是否需要更新偏好設定檔
}
```

#### 3. update-user-preferences
更新用戶偏好設定檔（通常由排程任務觸發）。

**端點**: `POST /functions/v1/update-user-preferences`

**Request**:
```typescript
interface UpdatePreferencesRequest {
  user_id: string;
  force_recalculate?: boolean;  // 強制重新計算
}
```

### RPC Functions

#### 1. get_personalized_items
主要的推薦查詢函數。

```sql
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
    seller_rating NUMERIC
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
            50.0 AS recommendation_score,
            'popular' AS recommendation_reason,
            u.id AS seller_id,
            u.nickname AS seller_nickname,
            u.avg_rating AS seller_rating
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
                        10 * (1 - LEAST(ST_Distance(l.coordinates, v_user_location) / 1000 / NULLIF(v_user_preferences.preferred_distance_km, 0), 1))
                    ELSE 0
                END +
                -- 新鮮度分數 (10分)
                10 * (1 - LEAST(EXTRACT(EPOCH FROM (NOW() - i.created_at)) / (7 * 24 * 3600), 1)) +
                -- 賣家評分加成 (5分)
                u.avg_rating
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
          AND i.user_id != ALL(v_user_preferences.excluded_seller_ids)
          -- 應用過濾條件
          AND (
            (p_filter->>'main_category_id')::INTEGER IS NULL OR
            sc.main_category_id = (p_filter->>'main_category_id')::INTEGER
          )
          AND (
            (p_filter->>'sub_category_id')::INTEGER IS NULL OR
            i.sub_category_id = (p_filter->>'sub_category_id')::INTEGER
          )
          AND (
            (p_filter->>'min_price')::INTEGER IS NULL OR
            i.price >= (p_filter->>'min_price')::INTEGER
          )
          AND (
            (p_filter->>'max_price')::INTEGER IS NULL OR
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
        si.seller_rating
    FROM scored_items si;
END;
$$;
```

#### 2. calculate_user_preferences
計算和更新用戶偏好設定檔。

```sql
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
        GREATEST(COALESCE(v_avg_price * 0.5, 0), 0),
        COALESCE(v_avg_price * 1.5, 999999),
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
```

---

## 實作計劃

### 第一階段：基礎架構 (Week 1-2)

#### 任務清單
- [ ] **資料庫遷移**
  - [ ] 創建 `user_interactions` 表及索引
  - [ ] 創建 `user_preferences` 表及索引
  - [ ] 創建 `recommendation_logs` 表及索引
  - [ ] (選) 創建 `item_similarity_cache` 表及索引
  
- [ ] **RPC 函數開發**
  - [ ] 實作 `get_personalized_items()` 函數
  - [ ] 實作 `calculate_user_preferences()` 函數
  - [ ] 實作 `get_similar_items()` 函數
  
- [ ] **測試資料準備**
  - [ ] 生成測試用戶互動資料
  - [ ] 建立測試用戶偏好資料
  - [ ] 驗證查詢效能

#### 交付成果
- 完整的資料庫架構
- 可運行的 RPC 函數
- 測試資料集

### 第二階段：Edge Functions (Week 3-4)

#### 任務清單
- [ ] **Edge Function 開發**
  - [ ] 實作 `get-recommendations` 函數
  - [ ] 實作 `track-user-interaction` 函數
  - [ ] 實作 `update-user-preferences` 函數
  - [ ] 配置 CORS 和錯誤處理
  
- [ ] **API 測試**
  - [ ] 單元測試各個 Edge Function
  - [ ] 整合測試推薦流程
  - [ ] 效能測試和優化
  
- [ ] **文檔編寫**
  - [ ] API 使用文檔
  - [ ] 部署指南
  - [ ] 故障排除指南

#### 交付成果
- 完整的 Edge Functions
- API 文檔
- 測試報告

### 第三階段：前端整合 (Week 5-6)

#### 任務清單
- [ ] **前端元件開發**
  - [ ] 推薦物品列表元件
  - [ ] 互動追蹤埋點
  - [ ] 個性化設定頁面
  
- [ ] **用戶體驗優化**
  - [ ] 實作無限滾動載入
  - [ ] 添加載入骨架屏
  - [ ] 實作即時推薦更新
  
- [ ] **A/B 測試準備**
  - [ ] 實作多版本推薦算法切換
  - [ ] 埋入追蹤埋點
  - [ ] 準備分析儀表板

#### 交付成果
- 完整的前端推薦介面
- 用戶互動追蹤系統
- A/B 測試框架

### 第四階段：優化與上線 (Week 7-8)

#### 任務清單
- [ ] **效能優化**
  - [ ] 查詢優化和索引調整
  - [ ] 快取策略實作
  - [ ] CDN 配置
  
- [ ] **監控與告警**
  - [ ] 設置推薦系統監控
  - [ ] 配置異常告警
  - [ ] 實作日誌分析
  
- [ ] **上線準備**
  - [ ] 灰度發布計劃
  - [ ] 回滾方案準備
  - [ ] 用戶溝通材料

#### 交付成果
- 生產環境部署
- 監控儀表板
- 運維手冊

---

## 效能考量

### 查詢優化策略

#### 1. 索引優化
```sql
-- 複合索引加速常見查詢
CREATE INDEX idx_items_status_created 
ON items(listing_status, created_at DESC) 
WHERE listing_status = true;

CREATE INDEX idx_interactions_user_type_created 
ON user_interactions(user_id, interaction_type, created_at DESC);

-- 部分索引減少索引大小
CREATE INDEX idx_items_active 
ON items(id, sub_category_id, price, condition) 
WHERE listing_status = true;
```

#### 2. 查詢快取
- **應用層快取**: 使用 Redis 快取熱門推薦結果（TTL: 5分鐘）
- **資料庫快取**: 利用 PostgreSQL 的 `pg_prewarm` 預熱常用表
- **CDN 快取**: 快取物品圖片和靜態資源

#### 3. 分頁策略
- 使用 cursor-based pagination 而非 offset-based
- 每頁限制 20-50 個物品
- 預載入下一頁資料

#### 4. 資料庫連接池
```typescript
// 配置 Supabase 連接池
const supabase = createClient(url, key, {
  db: {
    schema: 'public',
  },
  auth: {
    persistSession: false
  },
  global: {
    headers: {
      'x-application-name': 'recommendation-system'
    }
  }
})
```

### 擴展性設計

#### 水平擴展
- Edge Functions 自動擴展（Supabase 托管）
- 資料庫讀取副本分離讀寫
- 使用 Supabase Realtime 減輕輪詢壓力

#### 垂直擴展
- 定期清理舊互動資料（保留 90 天）
- 分區表策略（按月分區 `user_interactions`）
- 歸檔歷史推薦日誌

```sql
-- 分區表範例
CREATE TABLE user_interactions_2025_10 
PARTITION OF user_interactions
FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
```

---

## 安全性與隱私

### Row Level Security (RLS) 策略

#### user_interactions 表
```sql
-- 用戶只能查看自己的互動記錄
CREATE POLICY "Users can view own interactions"
ON user_interactions FOR SELECT
USING (auth.uid() = user_id);

-- 用戶只能插入自己的互動記錄
CREATE POLICY "Users can insert own interactions"
ON user_interactions FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 啟用 RLS
ALTER TABLE user_interactions ENABLE ROW LEVEL SECURITY;
```

#### user_preferences 表
```sql
-- 用戶只能查看和修改自己的偏好
CREATE POLICY "Users can manage own preferences"
ON user_preferences FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
```

#### recommendation_logs 表
```sql
-- 只有系統服務可以寫入推薦日誌
CREATE POLICY "Service role can insert logs"
ON recommendation_logs FOR INSERT
WITH CHECK (auth.role() = 'service_role');

-- 用戶可以查看自己的推薦記錄
CREATE POLICY "Users can view own logs"
ON recommendation_logs FOR SELECT
USING (auth.uid() = user_id);

ALTER TABLE recommendation_logs ENABLE ROW LEVEL SECURITY;
```

### 隱私保護措施

1. **資料匿名化**
   - 不收集用戶真實姓名、地址等敏感資訊
   - 位置資訊僅用於距離計算，不顯示精確座標

2. **用戶控制權**
   - 提供「清除瀏覽歷史」功能
   - 允許用戶退出個性化推薦
   - 提供「不再推薦此類物品」選項

3. **資料保留政策**
   - 互動資料保留 90 天
   - 推薦日誌保留 30 天
   - 用戶刪除帳號時級聯刪除所有相關資料

4. **GDPR 合規**
   - 提供資料導出功能
   - 提供資料刪除功能
   - 明確的隱私政策和用戶同意

### API 安全

1. **速率限制**
```typescript
// Edge Function 中實作簡單的速率限制
const RATE_LIMIT = 100; // 每分鐘 100 次請求
const checkRateLimit = async (userId: string) => {
  const key = `rate_limit:${userId}`;
  const count = await redis.incr(key);
  if (count === 1) {
    await redis.expire(key, 60);
  }
  return count <= RATE_LIMIT;
};
```

2. **輸入驗證**
```typescript
// 驗證用戶輸入
function validateRecommendationRequest(req: RecommendationRequest) {
  if (req.limit && (req.limit < 1 || req.limit > 100)) {
    throw new Error('Limit must be between 1 and 100');
  }
  if (req.offset && req.offset < 0) {
    throw new Error('Offset must be non-negative');
  }
  // ... 更多驗證
}
```

3. **JWT 驗證**
```typescript
// 驗證用戶身份
const authHeader = req.headers.get('Authorization');
const token = authHeader?.replace('Bearer ', '');
const { data: { user }, error } = await supabase.auth.getUser(token);
if (error || !user) {
  throw new Error('Unauthorized');
}
```

---

## 測試策略

### 單元測試

#### 資料庫函數測試
```sql
-- 測試 get_personalized_items 函數
DO $$
DECLARE
    v_test_user_id UUID := 'test-user-uuid';
    v_result RECORD;
BEGIN
    -- 準備測試資料
    INSERT INTO user_preferences (user_id, preferred_sub_categories)
    VALUES (v_test_user_id, ARRAY[1, 2, 3]);
    
    -- 執行測試
    FOR v_result IN 
        SELECT * FROM get_personalized_items(v_test_user_id, 10, 0)
    LOOP
        -- 驗證結果
        ASSERT v_result.recommendation_score >= 0, 'Score should be non-negative';
        ASSERT v_result.item_id IS NOT NULL, 'Item ID should not be null';
    END LOOP;
    
    -- 清理測試資料
    DELETE FROM user_preferences WHERE user_id = v_test_user_id;
    
    RAISE NOTICE 'Test passed!';
END $$;
```

#### Edge Function 測試
```typescript
// tests/get-recommendations.test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("Get recommendations returns valid response", async () => {
  const response = await fetch("http://localhost:54321/functions/v1/get-recommendations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${TEST_JWT_TOKEN}`
    },
    body: JSON.stringify({
      user_id: "test-user-id",
      limit: 10
    })
  });
  
  const data = await response.json();
  assertEquals(data.success, true);
  assertEquals(Array.isArray(data.data.items), true);
});
```

### 整合測試

#### 端到端測試流程
1. 創建測試用戶
2. 模擬用戶互動（瀏覽、收藏物品）
3. 調用推薦 API
4. 驗證推薦結果的相關性
5. 追蹤互動行為
6. 驗證偏好設定檔更新

```typescript
// tests/e2e/recommendation-flow.test.ts
describe("Recommendation System E2E", () => {
  it("should provide personalized recommendations", async () => {
    // 1. 創建測試用戶和物品
    const user = await createTestUser();
    const items = await createTestItems(10);
    
    // 2. 模擬用戶互動
    await simulateUserInteractions(user.id, items.slice(0, 5));
    
    // 3. 等待偏好計算
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 4. 獲取推薦
    const recommendations = await getRecommendations(user.id);
    
    // 5. 驗證推薦品質
    expect(recommendations.length).toBeGreaterThan(0);
    expect(recommendations[0].recommendation_score).toBeGreaterThan(30);
    
    // 6. 清理測試資料
    await cleanupTestData(user.id);
  });
});
```

### 效能測試

#### 負載測試
```bash
# 使用 k6 進行負載測試
k6 run - <<EOF
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // 逐漸增加到 100 個用戶
    { duration: '5m', target: 100 },  // 維持 100 個用戶
    { duration: '2m', target: 0 },    // 逐漸減少到 0
  ],
};

export default function () {
  const res = http.post(
    'https://your-project.supabase.co/functions/v1/get-recommendations',
    JSON.stringify({ limit: 20 }),
    { headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ...' } }
  );
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
EOF
```

### A/B 測試

#### 實驗設計
- **對照組 (A)**: 隨機推薦（基於熱門度）
- **實驗組 (B)**: 個性化推薦（混合算法）

#### 評估指標
- 點擊率 (CTR)
- 收藏率
- 交易轉換率
- 用戶參與時間
- 用戶滿意度評分

---

## 未來擴展

### 短期優化 (3-6 個月)

#### 1. 深度學習推薦模型
- 使用 TensorFlow.js 或 ONNX Runtime 在 Edge Function 中運行輕量級模型
- 訓練序列推薦模型（RNN/LSTM）預測用戶下一步行為
- 實作 Wide & Deep 模型結合顯式和隱式特徵

#### 2. 圖片相似度推薦
- 使用 Supabase Storage 儲存物品圖片
- 整合圖片相似度計算服務（如 AWS Rekognition）
- 實作「找相似物品」功能

#### 3. 社交推薦
- 「你的朋友也喜歡」推薦
- 「同城熱門」推薦
- 追蹤用戶的動態推薦

### 中期目標 (6-12 個月)

#### 1. 實時推薦系統
- 使用 Supabase Realtime 訂閱物品更新
- 實作推播通知推薦新物品
- 動態調整推薦權重

#### 2. 多目標優化
- 平衡推薦的準確性和多樣性
- 考慮平台生態平衡（給新賣家更多曝光）
- 優化交易成功率和用戶滿意度

#### 3. 自動化 A/B 測試平台
- 實作自動化實驗管理系統
- 多臂老虎機 (Multi-Armed Bandit) 算法
- 實時效果評估和自動切換

### 長期願景 (12+ 個月)

#### 1. AI 驅動的對話式推薦
- 整合 ChatGPT API 實作對話式推薦
- 「幫我找一個適合送給朋友的禮物」
- 自然語言理解用戶需求

#### 2. 跨平台推薦生態
- 整合第三方平台資料（在用戶授權下）
- 建立開放 API 供第三方接入
- 打造推薦系統 SDK

#### 3. 可解釋性 AI
- 為每個推薦提供詳細解釋
- 「推薦這個是因為您最近瀏覽了...」
- 提升用戶信任度

---

## 附錄

### A. 參考資料

#### 推薦系統理論
- [Recommender Systems Handbook](https://www.springer.com/gp/book/9780387858203)
- [Deep Learning for Recommender Systems](https://arxiv.org/abs/1707.07435)
- [Collaborative Filtering for Implicit Feedback Datasets](http://yifanhu.net/PUB/cf.pdf)

#### Supabase 官方文檔
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase Database Functions](https://supabase.com/docs/guides/database/functions)
- [Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [PostGIS Extension](https://postgis.net/documentation/)

#### 最佳實踐
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [API Rate Limiting Best Practices](https://cloud.google.com/architecture/rate-limiting-strategies-techniques)

### B. 術語表

| 術語 | 說明 |
|------|------|
| CTR (Click-Through Rate) | 點擊率，推薦物品被點擊的比例 |
| Collaborative Filtering | 協同過濾，基於相似用戶行為的推薦 |
| Content-Based Filtering | 基於內容的推薦，匹配物品屬性與用戶偏好 |
| Cold Start | 冷啟動問題，新用戶或新物品缺乏歷史資料 |
| RLS (Row Level Security) | 行級安全策略，PostgreSQL 的資料安全機制 |
| Edge Functions | 邊緣函數，運行在靠近用戶的伺服器上的無伺服器函數 |
| RPC (Remote Procedure Call) | 遠程過程調用，在資料庫中執行的自定義函數 |

### C. 變更記錄

| 版本 | 日期 | 變更內容 | 作者 |
|------|------|----------|------|
| 1.0.0 | 2025-10-29 | 初始版本，完整提案 | 開發團隊 |

---

## 結論

本提案詳細描述了基於 Supabase 服務的用戶喜好物品推薦系統的完整設計方案。透過結合多種推薦算法、利用 Supabase 的原生功能（PostgreSQL、Edge Functions、RLS 等），我們可以實現一個高效、安全、可擴展的推薦系統。

### 核心優勢
✅ **完全基於 Supabase**: 無需額外的後端服務，降低維護成本  
✅ **漸進式實作**: 分階段推進，快速驗證和迭代  
✅ **隱私優先**: 遵循資料保護原則，用戶資料安全  
✅ **高效能**: 利用 PostgreSQL 的強大查詢能力和索引優化  
✅ **可擴展**: 設計考慮未來擴展需求，支持深度學習模型整合  

### 下一步行動
1. ✅ 審核和批准本提案
2. 🔄 啟動第一階段開發（資料庫架構）
3. 🔄 組建開發團隊和分配任務
4. 🔄 設置專案管理和追蹤工具

---

**提案結束**

如有任何問題或建議，請聯繫開發團隊。
