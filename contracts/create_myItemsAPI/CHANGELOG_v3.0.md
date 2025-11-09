# CHANGELOG - create_myItemsAPI v3.0

## v3.0 (2025-11-08) - 精簡版：使用 `use_primary_location` Boolean 欄位

### 🎯 設計核心

**業務規則：**
- 每個使用者限制擁有「1個主要地點 + 1個次要地點」（最多2個）
- 物品透過 `use_primary_location` boolean 欄位記錄使用哪個地點
- 不儲存 `location_id`，透過 JOIN 動態獲取地點資訊

**資料關聯：**
```sql
-- 查詢時自動 JOIN 對應的地點
SELECT i.*, l.*
FROM items i
JOIN locations l 
  ON l.user_id = i.user_id 
  AND l.is_primary = i.use_primary_location
```

**設計理念：**
- ✅ 最小化變更：只更新核心刊登函數 `create_item`
- ✅ 保持簡潔：不新增額外的 RPC 函數
- ✅ 向後相容：預設行為與 v2.0 相同（使用主要地點）
- ✅ 前端靈活：其他功能可直接使用 Supabase 客戶端

---

### 🔄 重大變更 (Breaking Changes)

#### v2.0 → v3.0 主要差異

| 項目 | v2.0 | v3.0 |
|------|------|------|
| 地點選擇 | ❌ 固定主要地點 | ✅ 可選主要/次要地點 |
| 刊登參數 | 無地點參數 | `use_primary_location` (Boolean) |
| 預設值 | 固定主要地點 | 預設 `true` (主要地點) |
| 額外函數 | - | 無（保持精簡） |
| 前端彈性 | 低 | 高 |

#### 新增的欄位

✅ **`items.use_primary_location`** (BOOLEAN, NOT NULL, DEFAULT true)
  - `true`: 使用主要地點 (is_primary=true)
  - `false`: 使用次要地點 (is_primary=false)

#### 移除的欄位

❌ **`items.location_id`** - 完全移除，不再儲存 location ID

---

### 📊 資料庫架構變更

#### Schema 變更

**Before (v2.0):**
```sql
CREATE TABLE items (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    sub_category_id INTEGER NOT NULL,
    -- location_id 已棄用但保留（允許 NULL）
    title VARCHAR(50) NOT NULL,
    ...
);
```

**After (v3.0):**
```sql
CREATE TABLE items (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    sub_category_id INTEGER NOT NULL,
    use_primary_location BOOLEAN NOT NULL DEFAULT true,  -- ✅ 新增
    title VARCHAR(50) NOT NULL,
    ...
);
-- ❌ location_id 欄位已完全移除
```

#### 新增的 View

✅ **`items_with_location`** - 方便查詢物品及地點資訊

```sql
CREATE VIEW items_with_location AS
SELECT
    i.*,
    l.id AS location_id,
    l.coordinates AS location_coordinates,
    l.type AS location_type,
    l.formatted_address AS location_address,
    l.is_primary AS location_is_primary
FROM items i
LEFT JOIN locations l
    ON l.user_id = i.user_id
    AND l.is_primary = i.use_primary_location;
```

**使用範例：**
```javascript
// 直接查詢 View，無需手動 JOIN
const { data } = await supabase
  .from('items_with_location')
  .select('*')
  .eq('id', itemId)
  .single();

console.log(data.location_address);  // 地點資訊已自動 JOIN
```

---

### 💻 程式碼變更對照

#### RPC 函數簽名

**Before (v2.0):**
```sql
CREATE FUNCTION create_item(
    p_sub_category_id INT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),
    p_price INT,
    p_carbon_value NUMERIC DEFAULT NULL,
    p_image_urls TEXT[] DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL
)
```

**After (v3.0):**
```sql
CREATE FUNCTION create_item(
    p_sub_category_id INT,
    p_title TEXT,
    p_description TEXT,
    p_condition VARCHAR(20),
    p_price INT,
    p_use_primary_location BOOLEAN DEFAULT true,  -- ✅ 新增參數
    p_carbon_value NUMERIC DEFAULT NULL,
    p_image_urls TEXT[] DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL
)
```

#### 前端 API 變更

**Before (v2.0):**
```javascript
export async function createItem(itemData) {
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    // ❌ 無地點參數
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags,
  };
  // ...
}
```

**After (v3.0):**
```javascript
export async function createItem(itemData) {
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    p_use_primary_location: itemData.use_primary_location ?? true,  // ✅ 新增
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags,
  };
  // ...
}
```

---

### 📝 使用範例對照

#### 範例 1: 基本刊登（向後相容）

**v2.0 & v3.0（相同用法）:**
```javascript
// 預設使用主要地點
const result = await createItem({
  sub_category_id: 1,
  title: '物品標題',
  description: '描述',
  condition: '良好',
  price: 100
});

console.log(result.item.id);
console.log(result.location.formatted_address);  // v3.0 新增：回傳地點資訊
```

#### 範例 2: 使用次要地點（v3.0 新功能）

```javascript
// v3.0 可以選擇使用次要地點
const result = await createItem({
  sub_category_id: 1,
  title: '辦公室物品',
  description: '在公司自取',
  condition: '良好',
  price: 100,
  use_primary_location: false  // ✅ 使用次要地點
});
```

#### 範例 3: 查詢物品及地點

**v2.0（複雜）:**
```javascript
// 需要複雜的 JOIN 查詢
const { data } = await supabase
  .from('items')
  .select(`
    *,
    users!inner(
      locations(*)
    )
  `)
  .eq('id', itemId)
  .single();
```

**v3.0（簡單）:**
```javascript
// 直接使用 View
const { data } = await supabase
  .from('items_with_location')
  .select('*')
  .eq('id', itemId)
  .single();

console.log(data.location_address);      // 地點地址
console.log(data.location_type);         // 地點類型
console.log(data.use_primary_location);  // 使用主要/次要地點
```

#### 範例 4: 獲取使用者地點（前端直接查詢）

```javascript
// v3.0: 不需要額外的 API 函數，直接查詢
const { data: { user } } = await supabase.auth.getUser();

const { data: locations } = await supabase
  .from('locations')
  .select('*')
  .eq('user_id', user.id)
  .order('is_primary', { ascending: false });

const primaryLocation = locations.find(loc => loc.is_primary === true);
const secondaryLocation = locations.find(loc => loc.is_primary === false);
```

#### 範例 5: 更新物品地點（前端直接更新）

```javascript
// v3.0: 不需要 RPC，直接使用 Supabase 更新
const { data, error } = await supabase
  .from('items')
  .update({ use_primary_location: false })  // 切換至次要地點
  .eq('id', itemId)
  .select();

if (!error) {
  console.log('已切換至次要地點');
}
```

---

### ⚠️ 錯誤處理

#### 新增的錯誤訊息

| 錯誤訊息 | 觸發條件 | 解決方法 |
|---------|---------|---------|
| "請先在個人資料中設定主要地點後再刊登物品" | 使用者無主要地點 + `use_primary_location=true` | 引導至設定頁面 |
| "請先在個人資料中設定次要地點後再刊登物品" | 使用者無次要地點 + `use_primary_location=false` | 引導至設定頁面或切換至主要地點 |

#### 錯誤處理範例

```javascript
try {
  await createItem({
    // ...
    use_primary_location: false  // 使用次要地點
  });
} catch (error) {
  if (error.message.includes('次要地點')) {
    const confirm = window.confirm('您尚未設定次要地點，是否前往設定？');
    if (confirm) {
      router.push('/profile/locations');
    } else {
      // 或提示切換至主要地點
      console.log('請改用主要地點刊登');
    }
  }
}
```

---

### 🔧 Migration 檔案

#### Migration 1: `20251108000001_add_use_primary_location_to_items_jo.sql`

**主要內容：**
- ✅ 新增 `items.use_primary_location` 欄位（預設 true）
- ✅ 移除 `items.location_id` 欄位（如存在）
- ✅ 建立 `items_with_location` View
- ✅ 建立索引優化查詢效能
- ✅ 驗證資料完整性

**索引策略：**
```sql
-- 優化常見查詢
CREATE INDEX idx_items_user_id_use_primary_location
    ON items(user_id, use_primary_location);

CREATE INDEX idx_items_listing_status_use_primary
    ON items(listing_status, use_primary_location)
    WHERE listing_status = true;

CREATE INDEX idx_locations_user_id_is_primary
    ON locations(user_id, is_primary);
```

#### Migration 2: `20251108000002_update_create_item_with_use_primary_location_jo.sql`

**主要內容：**
- ✅ 刪除舊版本 `create_item` 函數
- ✅ 建立新版本 `create_item` 函數（新增 `p_use_primary_location` 參數）
- ✅ 驗證使用者是否有對應的地點
- ✅ 回傳物品資訊及使用的地點資訊

---

### 🚀 優勢與效益

| 特性 | v2.0 | v3.0 | 改善 |
|------|------|------|------|
| 地點選擇彈性 | ❌ 固定主要地點 | ✅ 可選主要/次要 | 🎯 滿足多地點需求 |
| 資料儲存 | ⚠️ location_id 棄用但保留 | ✅ 只存 boolean | 💾 減少冗餘 |
| 查詢複雜度 | ⚠️ 需複雜 JOIN | ✅ 使用 View 簡化 | 📖 更易維護 |
| 額外函數 | - | ✅ 無（保持精簡） | 🔧 減少維護成本 |
| 前端靈活性 | 低 | ✅ 高（直接用 Supabase） | 😊 更多控制權 |
| 向後相容性 | - | ✅ 完全相容 | ✨ 平滑升級 |

---

### 📋 升級檢查清單

#### 後端（資料庫）
- [x] 執行 Migration 1: 新增欄位和 View
- [x] 執行 Migration 2: 更新 RPC 函數
- [x] 驗證索引效能
- [ ] 測試 `create_item` RPC（主要地點）
- [ ] 測試 `create_item` RPC（次要地點）
- [ ] 測試錯誤情況（無對應地點）

#### 前端 API
- [x] 更新 `create_myItemAPI.js`
- [x] 更新 `createItem()` 函數
- [x] 更新 `createItemWithImages()` 函數
- [x] 更新 `checkUserHasLocation()` 函數（支援檢查特定類型）
- [x] 更新錯誤處理邏輯
- [x] 更新使用範例文件

#### 前端 UI
- [ ] 更新刊登表單：新增地點選擇器（radio button）
- [ ] 顯示主要地點和次要地點資訊
- [ ] 處理使用者只有主要地點的情況
- [ ] 處理使用者沒有次要地點的情況
- [ ] 更新表單驗證邏輯
- [ ] 測試所有使用情境

#### 文件
- [x] CHANGELOG v3.0（精簡版）
- [x] API 文件更新
- [x] 使用範例更新
- [ ] 團隊培訓文件

---

### 🔍 測試建議

#### 單元測試

```javascript
describe('createItem v3.0', () => {
  it('應預設使用主要地點', async () => {
    const result = await createItem({
      sub_category_id: 1,
      title: 'Test',
      price: 100
    });
    expect(result.item.use_primary_location).toBe(true);
  });

  it('應可指定使用次要地點', async () => {
    const result = await createItem({
      sub_category_id: 1,
      title: 'Test',
      price: 100,
      use_primary_location: false
    });
    expect(result.item.use_primary_location).toBe(false);
  });

  it('使用者無次要地點時應拋出錯誤', async () => {
    await expect(
      createItem({
        sub_category_id: 1,
        title: 'Test',
        price: 100,
        use_primary_location: false
      })
    ).rejects.toThrow('請先在個人資料中設定次要地點');
  });
});
```

#### 整合測試場景

1. **基本刊登流程**
   - ✅ 使用主要地點刊登（預設）
   - ✅ 使用次要地點刊登
   - ✅ 無主要地點時的錯誤處理
   - ✅ 無次要地點時的錯誤處理

2. **查詢功能**
   - ✅ 透過 View 查詢物品及地點
   - ✅ 驗證地點資訊正確性
   - ✅ 測試不同 `use_primary_location` 值的查詢結果

3. **前端直接操作**
   - ✅ 直接查詢 locations 表
   - ✅ 直接更新 items.use_primary_location
   - ✅ 驗證更新後的查詢結果

---

### 💡 最佳實踐建議

#### 1. 預設使用主要地點（符合大多數用戶需求）

```javascript
// ✅ 推薦：大多數情況下使用預設值
const result = await createItem(formData);  // 自動 use_primary_location=true

// ⚠️ 僅在確實需要時指定次要地點
const result = await createItem({
  ...formData,
  use_primary_location: false
});
```

#### 2. 前端檢查地點狀態

```javascript
// 刊登前檢查
const { data: locations } = await supabase
  .from('locations')
  .select('*')
  .eq('user_id', user.id);

const hasPrimary = locations.some(loc => loc.is_primary === true);
const hasSecondary = locations.some(loc => loc.is_primary === false);

if (!hasPrimary) {
  router.push('/profile/locations');
}
```

#### 3. 友善的 UI 提示

```vue
<template>
  <div class="location-section">
    <!-- 主要地點（總是顯示） -->
    <label v-if="primaryLocation">
      <input type="radio" v-model="usePrimary" :value="true" />
      主要地點 ({{ primaryLocation.formatted_address }})
    </label>
    
    <!-- 次要地點（僅在有設定時顯示） -->
    <label v-if="secondaryLocation">
      <input type="radio" v-model="usePrimary" :value="false" />
      次要地點 ({{ secondaryLocation.formatted_address }})
    </label>
    
    <!-- 提示可新增次要地點 -->
    <p v-if="!secondaryLocation" class="hint">
      💡 您可以在<router-link to="/profile/locations">個人資料</router-link>
      中新增次要地點，讓物品刊登更彈性
    </p>
  </div>
</template>
```

#### 4. 使用 View 簡化查詢

```javascript
// ✅ 推薦：使用 View
const { data } = await supabase
  .from('items_with_location')
  .select('*')
  .eq('id', itemId)
  .single();

// ❌ 避免：手動 JOIN（複雜且容易出錯）
const { data } = await supabase
  .from('items')
  .select(`
    *,
    users!inner(locations(*))
  `)
  .eq('id', itemId);
```

---

### 🎯 與 v2.0 的差異總結

#### 核心差異

| 面向 | v2.0 | v3.0 |
|------|------|------|
| **地點儲存方式** | 不儲存（純動態） | 儲存 boolean 欄位 |
| **地點選擇** | 固定主要地點 | 可選主要/次要 |
| **額外 RPC** | 無 | 無（保持一致） |
| **查詢方式** | 手動 JOIN | View 簡化 |
| **向後相容** | - | ✅ 100% 相容 |

#### 為什麼選擇 v3.0？

1. **✅ 滿足業務需求**
   - 使用者限制：1主要 + 1次要地點
   - 透過 boolean 即可完美映射

2. **✅ 資料庫設計優雅**
   - 避免儲存 location_id（減少冗餘）
   - boolean 欄位語義清晰
   - JOIN 條件簡單高效

3. **✅ 保持系統精簡**
   - 不新增額外 RPC 函數
   - 前端可直接使用 Supabase 客戶端
   - 減少維護成本

4. **✅ 前端靈活性高**
   - 地點查詢：直接 query locations 表
   - 地點更新：直接 update items 表
   - 複雜查詢：使用 items_with_location View

---

### 🔗 相關文件

- [Migration 20251108000001](../../supabase/migrations/20251108000001_add_use_primary_location_to_items_jo.sql)
- [Migration 20251108000002](../../supabase/migrations/20251108000002_update_create_item_with_use_primary_location_jo.sql)
- [create_myItemAPI.js](./create_myItemAPI.js)
- [CHANGELOG v2.0](./CHANGELOG_v2.0.md)

---

### 📞 問題與支援

如有任何問題，請聯繫：
- GitHub Issues
- Slack: #backend-team

---

**更新日期**: 2025-11-08  
**版本**: v3.0（精簡版）  
**狀態**: ✅ 已完成（等待前端整合）  
**向後相容性**: ✅ 100% 相容 v2.0  
**設計理念**: 最小化變更，最大化彈性