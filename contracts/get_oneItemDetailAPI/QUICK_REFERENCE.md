# 快速使用指南 - getItemDetails API v2.5

## 🚀 快速開始

### 基本用法

```javascript
import { getItemDetails } from '@/api/itemDetails';

// 獲取物品詳情（自動處理位置和權限）
const result = await getItemDetails(123);

if (result.success) {
  const item = result.data;
  console.log(item.title, item.price, item.distance_km);
}
```

---

## 📋 常見場景

### 1. 顯示物品詳情頁

```javascript
const loadItem = async (itemId) => {
  const result = await getItemDetails(itemId);
  
  if (!result.success) {
    // 處理錯誤
    showError(result.message);
    return;
  }
  
  // 設置數據
  item.value = result.data;
  isOwner.value = result.isOwner;
  canShowDistance.value = result.hasDistance;
};
```

### 2. 條件顯示距離

```vue
<template>
  <div class="item-detail">
    <!-- 基本資訊（所有人可見） -->
    <h1>{{ item.title }}</h1>
    <p>{{ item.description }}</p>
    <p>價格：${{ item.price }}</p>
    <p>地點：{{ item.location.formatted_address }}</p>
    
    <!-- 距離資訊（條件顯示） -->
    <div class="distance-info">
      <!-- 擁有者 -->
      <div v-if="result.isOwner" class="owner-badge">
        🏷️ 這是您的物品
      </div>
      
      <!-- 已登入用戶 -->
      <div v-else-if="result.isAuthenticated">
        <div v-if="item.distance_km !== null" class="distance">
          📍 距離：{{ formatDistance(item.distance_km) }}
        </div>
        <div v-else class="no-location">
          ⚠️ <router-link to="/profile/locations">設定您的地點</router-link> 以查看距離
        </div>
      </div>
      
      <!-- 未登入用戶 -->
      <div v-else class="login-prompt">
        🔒 <router-link to="/login">登入</router-link> 以查看距離
      </div>
    </div>
    
    <!-- 地圖（已登入且非擁有者） -->
    <div v-if="result.isAuthenticated && !result.isOwner && item.location.coordinates">
      <Map :coordinates="item.location.coordinates.coordinates" />
    </div>
  </div>
</template>
```

### 3. 距離格式化

```javascript
const formatDistance = (km) => {
  if (km === null) return '未知';
  if (km < 0.1) return `${Math.round(km * 1000)} 公尺`;
  if (km < 1) return `${km.toFixed(2)} 公里`;
  return `${km.toFixed(1)} 公里`;
};
```

### 4. 錯誤處理

```javascript
const result = await getItemDetails(itemId);

if (!result.success) {
  switch (result.code) {
    case 'INVALID_PARAMETER':
      // 參數錯誤（通常是開發錯誤）
      console.error('無效的物品 ID');
      router.push('/');
      break;
      
    case 'ITEM_NOT_FOUND':
      // 物品不存在或已下架
      showNotification('此物品不存在或已下架');
      router.push('/items');
      break;
      
    case 'INTERNAL_ERROR':
      // 系統錯誤
      showNotification('載入失敗，請稍後再試');
      break;
      
    default:
      showNotification('發生未知錯誤');
  }
}
```

---

## 🎨 UI 設計建議

### 距離顯示的三種狀態

```vue
<!-- 1. 未登入 -->
<div class="distance-locked">
  🔒 登入以查看距離
</div>

<!-- 2. 已登入但無地點 -->
<div class="distance-setup">
  📍 設定您的地點以查看距離
</div>

<!-- 3. 已登入且有距離 -->
<div class="distance-show">
  📍 距離您 {{ distance }} 公里
</div>
```

### 地圖顯示邏輯

```javascript
const shouldShowMap = computed(() => {
  return result.isAuthenticated 
    && !result.isOwner 
    && item.location.coordinates !== null;
});
```

---

## 📊 回應資料結構

### 成功回應

```javascript
{
  success: true,
  error: false,
  message: "物品詳情獲取成功",
  itemId: 123,
  locationSource: "database_primary",  // 或 "database_fallback", "none"
  isAuthenticated: true,
  hasDistance: true,
  isOwner: false,
  data: {
    // 物品基本資訊
    id: 123,
    title: "二手腳踏車",
    description: "...",
    price: 500,
    distance_km: 2.5,  // 或 null（未登入/擁有者/無地點）
    
    // 位置資訊
    location: {
      formatted_address: "台中市西屯區...",
      coordinates: {  // 或 null（未登入/擁有者）
        type: "Point",
        coordinates: [120.123, 24.456]
      }
    },
    
    // 用戶位置（僅已登入且非擁有者）
    user_location: {  // 或 null
      has_location: true,
      source: "database_primary",
      message: "使用您的主要地點"
    },
    
    // 其他欄位...
  }
}
```

### 失敗回應

```javascript
{
  success: false,
  error: true,
  code: "ITEM_NOT_FOUND",
  message: "物品不存在或已下架",
  itemId: 123,
  data: null
}
```

---

## 🔐 隱私保護規則

| 欄位 | 未登入 | 已登入（非擁有者） | 擁有者 |
|-----|-------|-----------------|--------|
| 基本資訊 | ✅ | ✅ | ✅ |
| 文字地址 | ✅ | ✅ | ✅ |
| 精確座標 | ❌ | ✅ | ❌ |
| distance_km | ❌ | ✅ | ❌ |
| user_location | ❌ | ✅ | ❌ |
| is_favorited | ❌ | ✅ | ✅ |
| is_owner | false | false | true |

---

## 💡 最佳實踐

### 1. 載入狀態管理

```javascript
const isLoading = ref(false);

const loadItem = async (itemId) => {
  isLoading.value = true;
  try {
    const result = await getItemDetails(itemId);
    // 處理結果...
  } finally {
    isLoading.value = false;
  }
};
```

### 2. 快取策略

```javascript
// 使用 Vue 3 的 computed 搭配 cache
const itemCache = new Map();

const getCachedItem = async (itemId) => {
  if (itemCache.has(itemId)) {
    return itemCache.get(itemId);
  }
  
  const result = await getItemDetails(itemId);
  if (result.success) {
    itemCache.set(itemId, result);
  }
  return result;
};
```

### 3. 提示用戶設定地點

```javascript
const checkUserLocation = async () => {
  const result = await getItemDetails(itemId);
  
  if (result.isAuthenticated && !result.hasDistance) {
    // 顯示提示：設定地點以查看距離
    showLocationSetupPrompt();
  }
};
```

### 4. SEO 優化（SSR）

```javascript
// Nuxt 3 範例
export default defineComponent({
  async asyncData({ params }) {
    const result = await getItemDetails(params.id);
    return {
      item: result.data,
      seoTitle: result.data?.title,
      seoDescription: result.data?.description,
    };
  }
});
```

---

## 🐛 常見問題

### Q: 為什麼距離顯示為 null？

**A:** 可能的原因：
1. 用戶未登入
2. 用戶是物品擁有者
3. 用戶未設定地點
4. 賣家未設定地點

### Q: 如何判斷用戶需要設定地點？

**A:** 檢查條件：
```javascript
const needsLocation = result.isAuthenticated 
  && !result.isOwner 
  && !result.hasDistance;
```

### Q: 座標格式是什麼？

**A:** GeoJSON Point 格式：
```javascript
{
  type: "Point",
  coordinates: [經度, 緯度]  // 注意順序！
}
```

### Q: 如何處理過時的函數調用？

**A:** 替換方案：
```javascript
// ❌ 舊方式
await getItemDetailsPublic(id);
await getItemDetailsWithDatabaseLocation(id);

// ✅ 新方式（統一）
await getItemDetails(id);
```

---

## 🔗 相關連結

- [完整 API 文檔](get_ItemDetailsAPI.js)
- [版本更新日誌](./CHANGELOG_v2.5.md)
- [RPC 函數文檔](../database/functions/get_oneItemDetail%20(RPC)_optimized.sql)

