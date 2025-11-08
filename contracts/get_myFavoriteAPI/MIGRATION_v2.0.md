# Migration v2.0 更新說明 - get_myFavoriteAPI

## 📅 更新日期：2025-11-07

## ✅ 狀態：已符合 Migration v2.0 規範

---

## 🔄 變更摘要

此 API **已經**使用正確的架構，符合 Migration v2.0 的要求。

### 架構變更
- **變更前**：`items.location_id → locations.id`
- **變更後**：`items.user_id → locations.user_id (is_primary=true)`

### API 行為
- ✅ 自動使用買家（登入者）的主要地點計算距離
- ✅ 自動使用賣家的主要地點（透過 `items.user_id`）
- ✅ 不需要傳遞經緯度參數
- ✅ PostGIS 自動計算距離
- ✅ 包含收藏時間 (`favorited_at`)

---

## 📝 無需變更

### 函數簽章保持不變

```javascript
// v1.0 和 v2.0 的函數簽章相同
export async function getMyFavoriteItems(options = {}) {
  const rpcParams = {
    p_page: options.page || 1,
    p_size: options.size || 20,
    p_sort_by: options.sort_by || 'favorited_at',
    p_sort_direction: options.sort_direction || 'desc'
  };

  const { data, error } = await supabase.rpc('get_my_favorite_items', rpcParams);
  return data;
}
```

### 前端調用保持不變

```javascript
// 使用方式完全相同
const favorites = await getMyFavoriteItems({
  page: 1,
  size: 20,
  sort_by: 'favorited_at',
  sort_direction: 'desc'
});
```

---

## 🔍 內部實現變更

雖然前端 API 保持不變，但後端 RPC 函數已更新為 v2.0：

### 後端 SQL 變更（已完成）

#### Before (v1.0)
```sql
-- 使用 items.location_id 直接關聯
JOIN locations seller_loc ON items.location_id = seller_loc.id
```

#### After (v2.0)
```sql
-- 使用 items.user_id 關聯賣家的主要地點
JOIN locations seller_loc ON items.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = true
```

---

## 📊 回傳格式

完全相同，無變更：

```javascript
[
  {
    "item_id": 101,
    "title": "（全新）IKEA 檯燈",
    "image_url": "https://.../item101_cover.jpg",
    "price": 500,
    "distance_km": "1.254",  // 自動計算（買賣雙方主要地點）
    "formatted_address": "台中市西屯區福星路",
    "created_at": "2025-10-18T10:30:00.123+00:00",
    "updated_at": "2025-10-18T10:30:00.123+00:00",
    "favorites_count": 15,
    "favorited_at": "2025-10-19T08:00:00+00:00",  // 收藏時間
    "user": {
      "id": "a1b2c3d4-...",
      "nickname": "Joseph",
      "profile_picture_url": "https://.../joseph.jpg"
    }
  }
]
```

---

## ⚠️ 注意事項

### 使用者地點要求

如果使用者沒有設定任何地點：
- `distance_km` 將為 `null`
- 其他資訊正常顯示
- 不會拋出錯誤
- 仍可查看收藏列表

### 建議處理方式

```javascript
// 前端顯示邏輯
const favorites = await getMyFavoriteItems({ page: 1, size: 20 });

favorites.forEach(item => {
  if (item.distance_km !== null) {
    console.log(`距離: ${item.distance_km} 公里`);
  } else {
    console.log('距離: 未知（請設定您的地點）');
  }
});
```

### Vue 3 組件範例

```vue
<template>
  <div class="favorites-list">
    <div v-if="!hasUserLocation" class="info-banner">
      📍 <router-link to="/profile/locations">設定您的地點</router-link>
      以查看與物品的距離
    </div>

    <div v-for="item in favorites" :key="item.item_id" class="item-card">
      <h3>{{ item.title }}</h3>
      <p>價格: ${{ item.price }}</p>
      <p>地址: {{ item.formatted_address }}</p>
      
      <!-- 距離顯示 -->
      <p v-if="item.distance_km !== null">
        距離: {{ formatDistance(item.distance_km) }}
      </p>
      <p v-else class="no-distance">
        距離: 未知
      </p>

      <!-- 收藏時間 -->
      <p class="favorited-time">
        收藏於: {{ formatDate(item.favorited_at) }}
      </p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { getMyFavoriteItems } from '@/api/favorites';

const favorites = ref([]);
const hasUserLocation = ref(false);

onMounted(async () => {
  const result = await getMyFavoriteItems({ page: 1, size: 20 });
  favorites.value = result || [];
  
  // 檢查是否有任何物品有距離資訊
  hasUserLocation.value = favorites.value.some(item => item.distance_km !== null);
});

function formatDistance(km) {
  if (km === null) return '未知';
  if (km < 0.1) return `${(km * 1000).toFixed(0)} 公尺`;
  if (km < 1) return `${km.toFixed(2)} 公里`;
  return `${km.toFixed(1)} 公里`;
}

function formatDate(dateString) {
  const date = new Date(dateString);
  return date.toLocaleDateString('zh-TW', { 
    year: 'numeric', 
    month: 'long', 
    day: 'numeric' 
  });
}
</script>
```

---

## 📈 排序選項

支援多種排序方式：

```javascript
// 1. 依收藏時間排序（預設）
const favorites = await getMyFavoriteItems({
  sort_by: 'favorited_at',
  sort_direction: 'desc'
});

// 2. 依物品建立時間排序
const favorites = await getMyFavoriteItems({
  sort_by: 'created_at',
  sort_direction: 'desc'
});

// 3. 依距離排序（由近到遠）
const favorites = await getMyFavoriteItems({
  sort_by: 'distance',
  sort_direction: 'asc'
});

// 4. 依價格排序
const favorites = await getMyFavoriteItems({
  sort_by: 'price',
  sort_direction: 'asc'
});
```

---

## 🎯 Migration 檢查清單

- [x] 後端 RPC 已更新至 v2.0
- [x] 使用 `items.user_id` 關聯位置
- [x] 自動查詢主要地點 (is_primary=true)
- [x] 前端 API 無需修改
- [x] 回傳格式保持一致
- [x] 包含收藏時間欄位
- [x] 支援多種排序方式
- [x] 文件已更新

---

## 🔗 相關文件

- [MIGRATION_GUIDE_20251107.md](../../supabase/migrations/MIGRATION_GUIDE_20251107.md)
- [QUICK_REFERENCE.md](../../supabase/migrations/QUICK_REFERENCE.md)
- 相關 Migration:
  - `20251107000001_update_items_location_relationship_jo.sql`
  - `20251107000002_update_rpc_functions_use_user_location_jo.sql` ⭐ (包含 get_my_favorite_items v2.0)

---

## ✨ 優勢

1. **向後相容**：前端無需修改
2. **自動化**：系統自動處理位置關聯
3. **彈性**：使用者更改主要地點，距離自動更新
4. **完整資訊**：包含收藏時間，便於管理
5. **多樣排序**：支援距離、時間、價格等多種排序

---

## 🆚 與 searchItems 的差異

| 特性 | get_my_favorite_items | search_items |
|------|----------------------|--------------|
| 資料範圍 | 僅當前使用者的收藏 | 所有上架物品 |
| 必須登入 | ✅ 是 | ❌ 否（但登入才有距離） |
| 收藏時間 | ✅ 包含 | ❌ 無 |
| 篩選條件 | 較少（主要靠排序） | 豐富（分類、關鍵字等） |
| 預設排序 | favorited_at | created_at |

---

## 💡 最佳實踐

### 1. 前置檢查登入狀態
```javascript
export async function getMyFavoriteItems(options = {}) {
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    console.warn('getMyFavoriteItems: User not logged in.');
    return null;
  }
  // ... 繼續執行
}
```

### 2. 提示使用者設定地點
```javascript
const favorites = await getMyFavoriteItems();
const allMissingDistance = favorites?.every(item => item.distance_km === null);

if (allMissingDistance && favorites?.length > 0) {
  alert('設定您的地點以查看與物品的距離');
}
```

### 3. 分頁載入
```javascript
// 無限滾動或分頁載入
let currentPage = 1;

async function loadMoreFavorites() {
  const newItems = await getMyFavoriteItems({
    page: currentPage,
    size: 20
  });
  
  favorites.value.push(...newItems);
  currentPage++;
}
```

---

**結論**：此 API 已完全符合 Migration v2.0 規範，無需額外修改。✅