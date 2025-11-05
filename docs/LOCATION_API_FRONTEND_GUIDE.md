# 地點功能 API 快速參考（前端開發）

**更新日期**: 2025-11-06  
**版本**: v2.0 - 新增地點限制

---

## 🎯 重要變更

### ⚠️ 與舊版的差異

| 項目 | 舊版 | 新版 |
|------|------|------|
| 地點類型 | 家、公司、**其他** | 家、公司（移除"其他"） |
| 類型限制 | 無限制 | 每種類型只能一個 |
| 數量限制 | 無限制 | 最多 2 個地點 |
| 首次建立 | 可選任意類型 | **必須為"家"** |
| is_primary | 按類型獨立 | **全局只能一個** |

---

## 📝 API 使用指南

### Endpoint

```
POST https://your-project.supabase.co/functions/v1/save-location
```

### Headers

```http
Authorization: Bearer {USER_JWT_TOKEN}
Content-Type: application/json
```

---

## 🔄 使用場景

### 場景 1: 用戶首次建立地點（必須為"家"）

```typescript
// ✅ 正確
const response = await fetch('/functions/v1/save-location', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${userToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    latitude: 24.1817,
    longitude: 120.7344,
    type: '家',  // 必須為"家"
    // is_primary 可省略，會自動設為 true
  })
});

// ❌ 錯誤：首次不能建立"公司"
body: JSON.stringify({
  type: '公司',  // ❌ 會返回 400 錯誤
  ...
})
```

**回應**:
```json
{
  "success": true,
  "data": {
    "id": 123,
    "latitude": 24.1817,
    "longitude": 120.7344,
    "district": "台中市南屯區",
    "type": "家",
    "is_primary": true
  }
}
```

---

### 場景 2: 建立第二個地點（公司）

```typescript
// ✅ 建立公司地點，設為主要
const response = await fetch('/functions/v1/save-location', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${userToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    latitude: 24.2,
    longitude: 120.8,
    type: '公司',
    is_primary: true  // 會將"家"改為非主要
  })
});

// ✅ 建立公司地點，保持"家"為主要
body: JSON.stringify({
  latitude: 24.2,
  longitude: 120.8,
  type: '公司',
  is_primary: false  // "家"保持為主要地點
})

// ⚠️ 省略 is_primary（自動判斷）
body: JSON.stringify({
  latitude: 24.2,
  longitude: 120.8,
  type: '公司'
  // 如果用戶沒有主要地點，會自動設為 true
  // 否則設為 false
})
```

---

### 場景 3: 錯誤處理

```typescript
try {
  const response = await fetch('/functions/v1/save-location', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${userToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      latitude: 24.1817,
      longitude: 120.7344,
      type: '家'
    })
  });

  const data = await response.json();

  if (!response.ok) {
    // 處理各種錯誤
    switch (response.status) {
      case 400:
        // 可能的錯誤：
        // - "首次建立地點必須為「家」"
        // - "您已經有「家」類型的地點"
        // - "已達地點數量上限"
        // - "無效的地點類型（僅支援「家」和「公司」）"
        console.error('請求錯誤:', data.error);
        alert(data.error);
        break;
      
      case 401:
        console.error('未授權，請重新登入');
        // 導向登入頁
        break;
      
      case 500:
        console.error('伺服器錯誤:', data.error);
        alert('儲存失敗，請稍後再試');
        break;
    }
    return;
  }

  // 成功
  console.log('地點已儲存:', data.data);
  
} catch (error) {
  console.error('網路錯誤:', error);
  alert('網路連線失敗，請檢查您的網路');
}
```

---

## 🎨 UI/UX 建議

### 1. 首次建立地點時

```tsx
function CreateFirstLocation() {
  return (
    <form onSubmit={handleSubmit}>
      <h2>設定您的「家」位置</h2>
      <p className="hint">首次建立地點必須為「家」</p>
      
      {/* 隱藏類型選擇器，直接使用"家" */}
      <input type="hidden" name="type" value="家" />
      
      <MapPicker onLocationSelect={setCoordinates} />
      
      <button type="submit">儲存地點</button>
    </form>
  );
}
```

### 2. 建立第二個地點時

```tsx
function CreateSecondLocation({ existingLocations }) {
  const hasHome = existingLocations.some(loc => loc.type === '家');
  const hasCompany = existingLocations.some(loc => loc.type === '公司');
  
  // 已經有 2 個地點，不允許再建立
  if (hasHome && hasCompany) {
    return (
      <div className="alert">
        <p>您已建立「家」和「公司」兩個地點</p>
        <p>若要新增地點，請先刪除其中一個</p>
      </div>
    );
  }
  
  return (
    <form onSubmit={handleSubmit}>
      <h2>新增地點</h2>
      
      {/* 只顯示尚未建立的類型 */}
      <select name="type" required>
        {!hasHome && <option value="家">家</option>}
        {!hasCompany && <option value="公司">公司</option>}
      </select>
      
      <label>
        <input 
          type="checkbox" 
          name="is_primary" 
          defaultChecked={false}
        />
        設為主要地點
      </label>
      
      <MapPicker onLocationSelect={setCoordinates} />
      
      <button type="submit">儲存地點</button>
    </form>
  );
}
```

### 3. 顯示現有地點

```tsx
function LocationList({ locations }) {
  return (
    <div className="location-list">
      {locations.map(location => (
        <div key={location.id} className="location-card">
          <div className="location-header">
            <span className="location-type">{location.type}</span>
            {location.is_primary && (
              <span className="badge-primary">主要地點</span>
            )}
          </div>
          <p className="location-address">{location.district}</p>
          
          <div className="location-actions">
            {!location.is_primary && (
              <button onClick={() => setPrimary(location.id)}>
                設為主要
              </button>
            )}
            <button onClick={() => editLocation(location.id)}>
              編輯
            </button>
            <button onClick={() => deleteLocation(location.id)}>
              刪除
            </button>
          </div>
        </div>
      ))}
      
      {locations.length < 2 && (
        <button onClick={openCreateDialog} className="btn-add">
          + 新增地點
        </button>
      )}
    </div>
  );
}
```

---

## 📋 前端檢查清單

建立地點前，先檢查：

```typescript
async function canCreateLocation(userLocations: Location[], newType: string) {
  // 1. 檢查數量限制
  if (userLocations.length >= 2) {
    return {
      canCreate: false,
      reason: '已達地點數量上限（最多 2 個）'
    };
  }
  
  // 2. 檢查類型重複
  if (userLocations.some(loc => loc.type === newType)) {
    return {
      canCreate: false,
      reason: `您已經有「${newType}」類型的地點`
    };
  }
  
  // 3. 檢查首次建立
  if (userLocations.length === 0 && newType !== '家') {
    return {
      canCreate: false,
      reason: '首次建立地點必須為「家」'
    };
  }
  
  return { canCreate: true };
}

// 使用範例
const check = await canCreateLocation(userLocations, '公司');
if (!check.canCreate) {
  alert(check.reason);
  return;
}

// 繼續建立地點...
```

---

## 🔍 完整的錯誤訊息對照表

| HTTP 狀態 | 錯誤訊息 | 原因 | 解決方法 |
|-----------|---------|------|----------|
| 400 | "首次建立地點必須為「家」" | 用戶沒有地點，卻嘗試建立"公司" | 改為建立"家" |
| 400 | "您已經有「家」類型的地點" | 嘗試建立重複類型 | 只能建立另一種類型 |
| 400 | "已達地點數量上限" | 已有 2 個地點 | 刪除一個後再建立 |
| 400 | "無效的地點類型（僅支援「家」和「公司」）" | type 不是"家"或"公司" | 檢查參數 |
| 400 | "無效的座標格式" | 緯度或經度超出範圍 | 檢查座標值 |
| 401 | "Missing authorization header" | 未提供 JWT token | 加上 Authorization header |
| 401 | "Unauthorized" | JWT token 無效或過期 | 重新登入 |
| 500 | "地址解析失敗" | Google Maps API 錯誤 | 稍後重試 |
| 500 | "儲存地點失敗" | 資料庫錯誤 | 聯絡技術支援 |

---

## 🧪 測試用例

```typescript
// Test 1: 首次建立地點（必須為"家"）
test('First location must be home', async () => {
  const response = await createLocation({
    latitude: 24.1817,
    longitude: 120.7344,
    type: '家'
  });
  
  expect(response.success).toBe(true);
  expect(response.data.type).toBe('家');
  expect(response.data.is_primary).toBe(true);
});

// Test 2: 建立第二個地點
test('Can create second location (company)', async () => {
  // 先建立"家"
  await createLocation({ type: '家', lat: 24.1, lng: 120.7 });
  
  // 再建立"公司"
  const response = await createLocation({
    latitude: 24.2,
    longitude: 120.8,
    type: '公司',
    is_primary: false
  });
  
  expect(response.success).toBe(true);
  expect(response.data.type).toBe('公司');
});

// Test 3: 不能建立重複類型
test('Cannot create duplicate type', async () => {
  await createLocation({ type: '家', lat: 24.1, lng: 120.7 });
  
  const response = await createLocation({
    latitude: 24.15,
    longitude: 120.75,
    type: '家'  // 重複
  });
  
  expect(response.success).toBe(false);
  expect(response.error).toContain('已經有');
});

// Test 4: 不能超過 2 個地點
test('Cannot exceed 2 locations', async () => {
  await createLocation({ type: '家', lat: 24.1, lng: 120.7 });
  await createLocation({ type: '公司', lat: 24.2, lng: 120.8 });
  
  const response = await createLocation({
    latitude: 24.3,
    longitude: 120.9,
    type: '其他'  // 第 3 個
  });
  
  expect(response.success).toBe(false);
  expect(response.error).toContain('上限');
});
```

---

## 💡 常見問題

### Q1: 用戶已有"其他"類型的地點，現在會怎樣？

**A**: Migration 會自動處理：
- 如果沒有"家" → "其他"會改為"家"
- 如果已有"家" → "其他"會被刪除（若沒有被物品引用）

### Q2: is_primary 到底怎麼運作？

**A**: 簡單來說：
- 每位用戶**所有地點中**只能有一個 is_primary=true
- 首次建立時自動設為 true
- 建立第二個地點時，可以選擇是否設為主要
- 如果設為主要，第一個地點會自動改為非主要

### Q3: 前端需要做什麼調整？

**A**: 主要調整：
1. 移除"其他"選項的 UI
2. 首次建立時強制為"家"（隱藏選擇器）
3. 限制最多 2 個地點
4. 檢查重複類型
5. 更新錯誤訊息處理

### Q4: 如果用戶想要多個地點怎麼辦？

**A**: 根據新規則，每位用戶最多只能有 2 個地點（家和公司）。如果需要修改地點，請刪除舊地點後再建立新地點。

---

## 📞 技術支援

如有疑問，請查看：
- API 詳細文檔：`/supabase/functions/save-location/README.md`

