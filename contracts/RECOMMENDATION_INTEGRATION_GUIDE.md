# 推薦系統整合指南
# Recommendation System Integration Guide

本指南說明如何將推薦系統整合到前端應用中。

## 📋 目錄

1. [快速開始](#快速開始)
2. [API 使用](#api-使用)
3. [前端整合](#前端整合)
4. [最佳實踐](#最佳實踐)
5. [故障排除](#故障排除)

---

## 快速開始

### 前置需求

- Supabase 專案已設置
- 資料庫遷移已執行
- Edge Functions 已部署

### 1. 執行資料庫遷移

```bash
# 本地開發
npx supabase db reset

# 生產環境
npx supabase db push
```

### 2. 部署 Edge Functions

```bash
# 部署推薦系統相關函數
npx supabase functions deploy get-recommendations --project-ref YOUR_PROJECT_REF
npx supabase functions deploy track-interaction --project-ref YOUR_PROJECT_REF
npx supabase functions deploy update-preferences --project-ref YOUR_PROJECT_REF
```

### 3. 驗證安裝

```bash
# 測試推薦 API
curl -i --location --request POST 'https://YOUR_PROJECT.supabase.co/functions/v1/get-recommendations' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"limit": 10}'
```

---

## API 使用

### 1. 獲取推薦物品

**端點**: `POST /functions/v1/get-recommendations`

**請求參數**:
```typescript
interface RecommendationRequest {
  limit?: number;           // 返回數量，預設 20
  offset?: number;          // 分頁偏移，預設 0
  algorithm?: 'hybrid' | 'content' | 'collaborative' | 'popular' | 'location';
  filter?: {
    main_category_id?: number;
    sub_category_id?: number;
    max_distance_km?: number;
    min_price?: number;
    max_price?: number;
  };
}
```

**範例**:
```javascript
const { data, error } = await supabase.functions.invoke('get-recommendations', {
  body: {
    limit: 20,
    algorithm: 'hybrid',
    filter: {
      main_category_id: 1,
      max_distance_km: 50
    }
  }
})

if (data?.success) {
  console.log('Recommended items:', data.data.items)
  console.log('Personalization level:', data.data.personalization_level)
}
```

### 2. 追蹤用戶互動

**端點**: `POST /functions/v1/track-interaction`

**互動類型**:
- `view`: 用戶查看物品詳情
- `click`: 用戶點擊物品
- `favorite`: 用戶收藏物品
- `unfavorite`: 用戶取消收藏
- `share`: 用戶分享物品
- `contact_seller`: 用戶聯繫賣家

**範例**:
```javascript
// 當用戶查看物品時
await supabase.functions.invoke('track-interaction', {
  body: {
    item_id: 123,
    interaction_type: 'view',
    metadata: {
      duration_seconds: 30,
      source: 'recommendation',
      position: 0
    }
  }
})

// 當用戶收藏物品時
await supabase.functions.invoke('track-interaction', {
  body: {
    item_id: 123,
    interaction_type: 'favorite',
    metadata: {
      from_recommendation: true
    }
  }
})
```

### 3. 更新用戶偏好

**端點**: `POST /functions/v1/update-preferences`

**範例**:
```javascript
// 強制重新計算偏好
await supabase.functions.invoke('update-preferences', {
  body: {
    force_recalculate: true
  }
})

// 更新手動設定的偏好
await supabase.functions.invoke('update-preferences', {
  body: {
    manual_preferences: {
      preferred_distance_km: 30,
      max_price_range: 10000,
      excluded_seller_ids: ['uuid-1', 'uuid-2']
    }
  }
})
```

---

## 前端整合

### Vue 3 範例

#### 1. 創建推薦服務

```typescript
// services/recommendationService.ts
import { supabase } from '@/supabase'

export interface RecommendationItem {
  item_id: number
  title: string
  description: string
  price: number
  condition: string
  image_urls: string[]
  distance_km?: number
  recommendation_score: number
  recommendation_reason: string
}

export const recommendationService = {
  // 獲取推薦物品
  async getRecommendations(params: {
    limit?: number
    offset?: number
    filter?: any
  } = {}): Promise<RecommendationItem[]> {
    const { data, error } = await supabase.functions.invoke('get-recommendations', {
      body: params
    })

    if (error) throw error
    return data?.data?.items || []
  },

  // 追蹤互動
  async trackInteraction(
    itemId: number,
    type: string,
    metadata: any = {}
  ): Promise<void> {
    await supabase.functions.invoke('track-interaction', {
      body: {
        item_id: itemId,
        interaction_type: type,
        metadata
      }
    })
  },

  // 更新偏好
  async updatePreferences(forceRecalculate: boolean = false): Promise<void> {
    await supabase.functions.invoke('update-preferences', {
      body: { force_recalculate: forceRecalculate }
    })
  }
}
```

#### 2. 創建推薦列表組件

```vue
<!-- components/RecommendationList.vue -->
<template>
  <div class="recommendation-list">
    <h2>為您推薦</h2>
    
    <div v-if="loading" class="loading">
      載入中...
    </div>
    
    <div v-else class="items-grid">
      <div
        v-for="(item, index) in items"
        :key="item.item_id"
        class="item-card"
        @click="handleItemClick(item, index)"
      >
        <img :src="item.image_urls[0]" :alt="item.title" />
        <h3>{{ item.title }}</h3>
        <p class="price">NT$ {{ item.price }}</p>
        <span class="badge">{{ getReasonText(item.recommendation_reason) }}</span>
      </div>
    </div>
    
    <button
      v-if="hasMore"
      @click="loadMore"
      class="load-more"
    >
      載入更多
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { recommendationService } from '@/services/recommendationService'
import type { RecommendationItem } from '@/services/recommendationService'

const items = ref<RecommendationItem[]>([])
const loading = ref(false)
const offset = ref(0)
const limit = 20
const hasMore = ref(true)

const loadRecommendations = async () => {
  loading.value = true
  try {
    const newItems = await recommendationService.getRecommendations({
      limit,
      offset: offset.value
    })
    
    if (newItems.length < limit) {
      hasMore.value = false
    }
    
    items.value.push(...newItems)
    offset.value += newItems.length
  } catch (error) {
    console.error('Failed to load recommendations:', error)
  } finally {
    loading.value = false
  }
}

const handleItemClick = async (item: RecommendationItem, index: number) => {
  // 追蹤點擊事件
  await recommendationService.trackInteraction(item.item_id, 'click', {
    source: 'recommendation_list',
    position: index,
    from_recommendation: true
  })
  
  // 導航到物品詳情頁
  // router.push(`/items/${item.item_id}`)
}

const loadMore = () => {
  loadRecommendations()
}

const getReasonText = (reason: string): string => {
  const reasonMap: Record<string, string> = {
    category_match: '類別匹配',
    price_match: '價格合適',
    location_near: '附近物品',
    popular: '熱門推薦',
    general: '推薦給您'
  }
  return reasonMap[reason] || '推薦'
}

onMounted(() => {
  loadRecommendations()
})
</script>

<style scoped>
.recommendation-list {
  padding: 20px;
}

.items-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 20px;
  margin: 20px 0;
}

.item-card {
  border: 1px solid #ddd;
  border-radius: 8px;
  padding: 15px;
  cursor: pointer;
  transition: transform 0.2s;
}

.item-card:hover {
  transform: translateY(-5px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.badge {
  background: #4CAF50;
  color: white;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
}

.load-more {
  margin: 20px auto;
  display: block;
  padding: 10px 30px;
  background: #2196F3;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}
</style>
```

#### 3. 在物品詳情頁追蹤互動

```vue
<!-- views/ItemDetail.vue -->
<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRoute } from 'vue-router'
import { recommendationService } from '@/services/recommendationService'

const route = useRoute()
const itemId = Number(route.params.id)
const viewStartTime = ref<number>(Date.now())

onMounted(() => {
  // 記錄查看事件
  recommendationService.trackInteraction(itemId, 'view', {
    source: route.query.from || 'direct'
  })
})

onBeforeUnmount(() => {
  // 記錄停留時間
  const durationSeconds = Math.floor((Date.now() - viewStartTime.value) / 1000)
  recommendationService.trackInteraction(itemId, 'view', {
    duration_seconds: durationSeconds,
    source: route.query.from || 'direct'
  })
})

const handleFavorite = async () => {
  await recommendationService.trackInteraction(itemId, 'favorite', {
    from_recommendation: route.query.from === 'recommendation'
  })
  // 更新 UI
}

const handleContactSeller = async () => {
  await recommendationService.trackInteraction(itemId, 'contact_seller')
  // 開啟聊天
}
</script>
```

### React 範例

```typescript
// hooks/useRecommendations.ts
import { useState, useEffect } from 'react'
import { recommendationService } from '../services/recommendationService'

export function useRecommendations(limit: number = 20) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(false)
  const [offset, setOffset] = useState(0)
  const [hasMore, setHasMore] = useState(true)

  const loadRecommendations = async () => {
    setLoading(true)
    try {
      const newItems = await recommendationService.getRecommendations({
        limit,
        offset
      })
      
      if (newItems.length < limit) {
        setHasMore(false)
      }
      
      setItems([...items, ...newItems])
      setOffset(offset + newItems.length)
    } catch (error) {
      console.error('Failed to load recommendations:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    loadRecommendations()
  }, [])

  return { items, loading, hasMore, loadMore: loadRecommendations }
}
```

---

## 最佳實踐

### 1. 互動追蹤

✅ **應該追蹤的互動**:
- 用戶查看物品詳情（記錄停留時間）
- 用戶點擊推薦物品
- 用戶收藏/取消收藏物品
- 用戶聯繫賣家
- 用戶分享物品

❌ **不需要追蹤的互動**:
- 單純的頁面滾動
- 圖片預覽
- UI 元素的 hover

### 2. 效能優化

```typescript
// 使用防抖避免過度追蹤
import { debounce } from 'lodash'

const trackView = debounce(async (itemId: number) => {
  await recommendationService.trackInteraction(itemId, 'view')
}, 1000)

// 使用批次請求
const trackMultipleViews = async (itemIds: number[]) => {
  await Promise.all(
    itemIds.map(id => 
      recommendationService.trackInteraction(id, 'view')
    )
  )
}
```

### 3. 錯誤處理

```typescript
try {
  const items = await recommendationService.getRecommendations()
  // 使用推薦結果
} catch (error) {
  console.error('Recommendation error:', error)
  // 降級到其他推薦策略（如熱門物品）
  const fallbackItems = await getFallbackItems()
}
```

### 4. 用戶隱私

```typescript
// 提供清除歷史的功能
const clearHistory = async () => {
  const { data: { user } } = await supabase.auth.getUser()
  
  if (user) {
    // 刪除互動記錄
    await supabase
      .from('user_interactions')
      .delete()
      .eq('user_id', user.id)
    
    // 重置偏好
    await supabase
      .from('user_preferences')
      .delete()
      .eq('user_id', user.id)
  }
}

// 提供退出個性化推薦的選項
const disablePersonalization = async () => {
  // 使用熱門推薦替代個性化推薦
  const items = await recommendationService.getRecommendations({
    algorithm: 'popular'
  })
}
```

---

## 故障排除

### 問題 1: 推薦結果為空

**可能原因**:
- 用戶沒有互動記錄
- 沒有可用的物品

**解決方案**:
```typescript
const items = await recommendationService.getRecommendations({
  algorithm: 'popular' // 降級到熱門推薦
})
```

### 問題 2: 推薦品質不佳

**可能原因**:
- 偏好資料不足
- 算法權重需要調整

**解決方案**:
1. 檢查用戶互動數量
2. 手動觸發偏好重新計算
3. 調整推薦算法權重

### 問題 3: API 回應緩慢

**可能原因**:
- 資料庫查詢未優化
- 缺少索引

**解決方案**:
1. 檢查資料庫索引
2. 使用快取
3. 限制返回欄位

```typescript
// 使用快取
const CACHE_KEY = 'recommendations'
const CACHE_TTL = 5 * 60 * 1000 // 5 分鐘

const getCachedRecommendations = async () => {
  const cached = localStorage.getItem(CACHE_KEY)
  if (cached) {
    const { data, timestamp } = JSON.parse(cached)
    if (Date.now() - timestamp < CACHE_TTL) {
      return data
    }
  }
  
  const items = await recommendationService.getRecommendations()
  localStorage.setItem(CACHE_KEY, JSON.stringify({
    data: items,
    timestamp: Date.now()
  }))
  
  return items
}
```

---

## 相關文檔

- [推薦系統提案](./USER_PREFERENCE_RECOMMENDATION_SYSTEM.md)
- [Edge Functions 文檔](../supabase/functions/README.md)
- [資料庫架構](../supabase/migrations/)
- [Supabase 官方文檔](https://supabase.com/docs)

---

**最後更新**: 2025-10-29
