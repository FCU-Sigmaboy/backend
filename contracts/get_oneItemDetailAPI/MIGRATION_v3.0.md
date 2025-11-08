# Migration v3.0 更新說明 - get_oneItemDetailAPI

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
- ✅ 支援未登入用戶瀏覽基本資訊
- ✅ 隱私保護：未登入無法查看距離和座標
- ✅ PostGIS 精確距離計算
- ✅ 使用 JSONB 優化效能

---

## 📝 無需變更

### 函數簽章保持不變

```javascript
// v2.5 和 v3.0 的函數簽章相同
export async function getItemDetails(itemId) {
  // 1. 參數驗證
  if (!itemId || typeof itemId !== "number") {
    throw new Error("itemId 必須是有效的數字");
  }

  // 2. 檢查登入狀態
  const isLoggedIn = await checkUserAuthentication();

  // 3. 呼叫 RPC 函式（自動處理位置）
  const { data, error } = await supabase
    .rpc("get_item_details_with_location", {
      p_item_id: itemId,
    })
    .maybeSingle();

  // 4-7. 錯誤處理和資料後處理
  // ...
}
```

### 前端調用保持不變

```javascript
// 使用方式完全相同
const result = await getItemDetails(123);

if (result.success) {
  console.log("物品標題:", result.data.title);
  console.log("距離:", result.data.distance_km, "km");
  console.log("位置來源:", result.locationSource);
} else {
  console.error("錯誤:", result.message);
}
```

---

## 🔍 內部實現變更

雖然前端 API 保持不變，但後端 RPC 函數已更新為 v3.0：

### 後端 SQL 變更（已完成）

#### Before (v2.5)
```sql
-- 使用 items.location_id 直接關聯
JOIN locations seller_loc ON items.location_id = seller_loc.id
```

#### After (v3.0)
```sql
-- 使用 items.user_id 關聯賣家的主要地點
LEFT JOIN locations seller_loc ON items.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = true
```

---

## 📊 回傳格式

完全相同，無變更：

```javascript
{
  success: true,
  error: false,
  message: "物品詳情獲取成功",
  itemId: 123,
  locationSource: "database_primary",
  isAuthenticated: true,
  hasDistance: true,
  isOwner: false,
  data: {
    // 物品基本資訊（所有人可見）
    id: 123,
    title: "二手書桌",
    description: "九成新，自取",
    condition: "良好",
    listing_status: true,
    price: 500,
    carbon_value: 10.5,
    image_urls: ["https://..."],
    tags: ["書桌", "家具"],
    created_at: "2025-10-18T10:30:00.123+00:00",
    updated_at: "2025-10-18T10:30:00.123+00:00",

    // 距離計算（🔒 僅已登入且非擁有者可見）
    distance_km: 1.254,

    // 互動狀態
    is_favorited: false,
    is_owner: false,

    // 賣家地點資訊
    location: {
      id: 456,
      formatted_address: "台中市西屯區福星路",
      type: "家",
      coordinates: {  // 🔒 僅已登入且非擁有者可見
        type: "Point",
        coordinates: [120.123, 24.456]
      }
    },

    // 賣家資訊
    user: {
      id: "a1b2c3d4-...",
      nickname: "Joseph",
      profile_picture_url: "https://...",
      avg_rating: 4.8
    },

    // 分類資訊
    category: {
      sub_category_id: 1,
      sub_category_name: "桌子",
      main_category_id: 1,
      main_category_name: "家具",
      main_category_icon: "🪑",
      main_category_color: "#FF6B6B"
    },

    // 買家位置資訊（🔒 僅已登入且非擁有者可見）
    user_location: {
      has_location: true,
      source: "database_primary",
      coordinates: {
        type: "Point",
        coordinates: [120.678, 24.789]
      },
      message: "使用資料庫主要地點"
    }
  }
}
```

---

## 🔐 隱私保護機制

### 未登入用戶

```javascript
const result = await getItemDetails(123);

// ✅ 可見
result.data.title             // "二手書桌"
result.data.price             // 500
result.data.location.formatted_address  // "台中市西屯區福星路"
result.data.user.nickname     // "Joseph"

// 🔒 隱藏
result.data.distance_km       // null
result.data.location.coordinates  // null
result.data.user_location     // null
result.hasDistance           // false
result.isAuthenticated       // false
```

### 已登入用戶（非擁有者）

```javascript
const result = await getItemDetails(123);

// ✅ 完整資訊
result.data.distance_km       // 1.254
result.data.location.coordinates  // { type: "Point", coordinates: [...] }
result.data.user_location     // 完整位置資訊
result.hasDistance           // true
result.isAuthenticated       // true
```

### 已登入用戶（擁有者）

```javascript
const result = await getItemDetails(123);

// ✅ 可見基本資訊
result.data.title             // "二手書桌"
result.isOwner               // true

// 🔒 不顯示距離（沒有意義）
result.data.distance_km       // null
result.data.user_location     // null
result.hasDistance           // false
```

---

## 💡 前端最佳實踐

### 1. 統一的錯誤處理

```javascript
const result = await getItemDetails(itemId);

if (!result.success) {
  switch (result.code) {
    case "INVALID_PARAMETER":
      showError("參數錯誤，請檢查物品 ID");
      break;
    case "ITEM_NOT_FOUND":
      showError("物品不存在或已下架");
      router.push("/");
      break;
    case "INTERNAL_ERROR":
      showError("系統錯誤，請稍後再試");
      break;
    default:
      showError(result.message);
  }
  return;
}
```

### 2. 距離資訊顯示

```javascript
function renderDistance(result) {
  if (!result.isAuthenticated) {
    return `
      <div class="login-prompt">
        🔒 <a href="/login">登入</a> 以查看與您的距離
      </div>
    `;
  }

  if (result.isOwner) {
    return `<div class="owner-badge">這是您的物品</div>`;
  }

  if (!result.hasDistance || result.data.distance_km === null) {
    return `
      <div class="setup-location">
        📍 <a href="/profile/locations">設定您的地點</a> 以查看距離
      </div>
    `;
  }

  const km = result.data.distance_km;
  const distance = formatDistance(km);
  return `<div class="distance">📍 距離: ${distance}</div>`;
}

function formatDistance(km) {
  if (km < 0.1) return `${(km * 1000).toFixed(0)} 公尺`;
  if (km < 1) return `${km.toFixed(2)} 公里`;
  return `${km.toFixed(1)} 公里`;
}
```

### 3. Vue 3 組件完整範例

```vue
<template>
  <div v-if="loading" class="loading">載入中...</div>
  
  <div v-else-if="error" class="error">
    {{ errorMessage }}
  </div>

  <div v-else-if="item" class="item-detail">
    <!-- 物品資訊 -->
    <h1>{{ item.title }}</h1>
    <p class="price">${{ item.price }}</p>
    <p class="description">{{ item.description }}</p>

    <!-- 圖片輪播 -->
    <ImageCarousel :images="item.image_urls" />

    <!-- 賣家資訊 -->
    <div class="seller">
      <UserAvatar :url="item.user.profile_picture_url" />
      <span>{{ item.user.nickname }}</span>
      <span class="rating">⭐ {{ item.user.avg_rating }}</span>
    </div>

    <!-- 地點資訊 -->
    <div class="location">
      <p>📍 {{ item.location.formatted_address }}</p>
      
      <!-- 距離顯示（根據登入和擁有者狀態） -->
      <div v-if="!result.isOwner">
        <div v-if="!result.isAuthenticated" class="login-prompt">
          🔒 <router-link to="/login">登入</router-link> 以查看距離
        </div>
        <div v-else-if="item.distance_km !== null" class="distance">
          距離: {{ formatDistance(item.distance_km) }}
        </div>
        <div v-else class="setup-location">
          📍 <router-link to="/profile/locations">設定您的地點</router-link>
          以查看距離
        </div>
      </div>

      <!-- 地圖（僅已登入且非擁有者且有座標） -->
      <Map 
        v-if="showMap"
        :seller-location="item.location.coordinates"
        :buyer-location="item.user_location?.coordinates"
        :distance="item.distance_km"
      />
    </div>

    <!-- 操作按鈕 -->
    <div class="actions">
      <button v-if="result.isOwner" @click="editItem">編輯物品</button>
      <button v-else @click="toggleFavorite">
        {{ item.is_favorited ? '💖 已收藏' : '🤍 收藏' }}
      </button>
      <button @click="contactSeller">聯絡賣家</button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { getItemDetails } from '@/api/itemDetails';

const route = useRoute();
const itemId = Number(route.params.id);

const loading = ref(true);
const error = ref(false);
const errorMessage = ref('');
const result = ref(null);
const item = ref(null);

const showMap = computed(() => {
  return result.value?.isAuthenticated && 
         !result.value?.isOwner && 
         item.value?.location?.coordinates;
});

onMounted(async () => {
  try {
    loading.value = true;
    result.value = await getItemDetails(itemId);

    if (result.value.success) {
      item.value = result.value.data;
    } else {
      error.value = true;
      errorMessage.value = result.value.message;
    }
  } catch (err) {
    error.value = true;
    errorMessage.value = err.message;
  } finally {
    loading.value = false;
  }
});

function formatDistance(km) {
  if (km === null) return '未知';
  if (km < 0.1) return `${(km * 1000).toFixed(0)} 公尺`;
  if (km < 1) return `${km.toFixed(2)} 公里`;
  return `${km.toFixed(1)} 公里`;
}

function toggleFavorite() {
  // 實作收藏功能
}

function contactSeller() {
  // 實作聯絡賣家功能
}

function editItem() {
  // 實作編輯物品功能
}
</script>
```

---

## 🎯 Migration 檢查清單

- [x] 後端 RPC 已更新至 v3.0
- [x] 使用 `items.user_id` 關聯位置
- [x] 自動查詢主要地點 (is_primary=true)
- [x] 前端 API 無需修改
- [x] 回傳格式保持一致
- [x] 支援未登入用戶瀏覽
- [x] 完整的隱私保護機制
- [x] JSONB 優化效能
- [x] 文件已更新

---

## 📊 位置來源 (locationSource)

| 值 | 說明 | 何時出現 |
|---|------|---------|
| `database_primary` | 使用資料庫主要地點 | 使用者有設定 is_primary=true 的地點 |
| `database_fallback` | 使用資料庫次要地點 | 使用者沒有主要地點，使用最早建立的地點 |
| `none` | 無位置資訊 | 未登入或使用者未設定任何地點 |

---

## 🔗 相關文件

- [MIGRATION_GUIDE_20251107.md](../../supabase/migrations/MIGRATION_GUIDE_20251107.md)
- [QUICK_REFERENCE.md](../../supabase/migrations/QUICK_REFERENCE.md)
- [CHANGELOG_v2.5.md](./CHANGELOG_v2.5.md) - 前一版本更新記錄
- 相關 Migration:
  - `20251107000001_update_items_location_relationship_jo.sql`
  - `20251107000002_update_rpc_functions_use_user_location_jo.sql` ⭐ (包含 get_item_details_with_location v3.0)

---

## ✨ 優勢

1. **向後相容**：前端無需修改
2. **自動化**：系統自動處理位置關聯
3. **彈性**：使用者更改主要地點，距離自動更新
4. **隱私保護**：完善的權限控制機制
5. **效能優化**：使用 JSONB 和 CTE 提升查詢效率
6. **用戶友善**：未登入也能瀏覽物品基本資訊

---

## 🆚 與其他 API 的比較

| 特性 | get_item_details | search_items | get_my_favorite_items |
|------|-----------------|--------------|----------------------|
| 資料範圍 | 單一物品詳情 | 物品列表 | 收藏物品列表 |
| 必須登入 | ❌ 否（但影響資訊豐富度） | ❌ 否 | ✅ 是 |
| 距離計算 | ✅ 是（如已登入且非擁有者） | ✅ 是 | ✅ 是 |
| 完整資訊 | ✅ 最完整 | ⚠️ 摘要 | ⚠️ 摘要 |
| 隱私保護 | ✅ 最嚴格 | ✅ 是 | ✅ 是 |
| 效能優化 | ✅ JSONB | ✅ 索引 | ✅ 索引 |

---

## 🔧 除錯技巧

### 檢查位置來源

```javascript
const result = await getItemDetails(123);

console.log('位置來源:', result.locationSource);
console.log('是否已登入:', result.isAuthenticated);
console.log('是否有距離:', result.hasDistance);
console.log('是否為擁有者:', result.isOwner);

if (result.data.user_location) {
  console.log('買家位置訊息:', result.data.user_location.message);
}
```

### 常見問題排查

| 問題 | 可能原因 | 解決方法 |
|------|---------|---------|
| distance_km 為 null | 未登入或未設定地點 | 引導用戶登入並設定地點 |
| coordinates 為 null | 未登入或為擁有者 | 正常行為，隱私保護 |
| 物品不存在 | itemId 錯誤或已下架 | 檢查 itemId，重新導向首頁 |
| locationSource: 'none' | 使用者沒有地點 | 提示設定地點 |

---

**結論**：此 API 已完全符合 Migration v2.0 規範，提供完整的隱私保護和最佳的使用者體驗。✅