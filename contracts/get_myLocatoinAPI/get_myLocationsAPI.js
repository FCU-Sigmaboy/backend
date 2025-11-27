import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 我的地點 API (Location APIs)
// ===================================================================

/**
 * 【功能】獲取 "當前登入者" 儲存的所有 location
 * (用於刊登物品時的 "選擇地點" 下拉選單或列表)
 * @returns {Promise<Array<{id: number, coordinates: Object, type: string, is_primary: boolean}> | null>}
 *          回傳 location 陣列，未登入回傳 null
 *          - id: 地點 ID
 *          - coordinates: PostGIS 地理座標 (GeoJSON Point)
 *          - type: 地點類型 ('家', '公司', '其他')
 *          - is_primary: 是否為主要地點
 */
export async function getMyLocations() {
    // 1. "前置作業": 獲取當前登入的使用者
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('getMyLocations: User not logged in.');
        return null; // 未登入則不執行查詢
    }

    // 2. 前端 JSON 約定欄位 (v2.0 簡化版)
    const selectQuery = `
    id,
    coordinates,
    type,
    is_primary
  `;

    // 3. 建立查詢
    const { data, error } = await supabase
        .from('locations')
        .select(selectQuery)
        .eq('user_id', user.id) // <-- 關鍵篩選，只抓自己的
        .order('is_primary', { ascending: false }) // 主要地點排最前面
        .order('id', { ascending: true }); // 再用 ID 排序

    // 4. 錯誤處理
    if (error) {
        console.error('Supabase 獲取 "我的地點" 失敗:', error);
        throw new Error(error.message);
    }

    // 5. data 就是您要的 JSON 陣列
    return data;
}

/* data 範例 (v2.0 簡化版 - 前端 JSON 約定)
[
  {
    "id": 12,
    "coordinates": { "type": "Point", "coordinates": [120.645, 24.179] },
    "type": "家",
    "is_primary": true
  },
  {
    "id": 15,
    "coordinates": { "type": "Point", "coordinates": [120.670, 24.140] },
    "type": "公司",
    "is_primary": false
  },
  {
    "id": 42,
    "coordinates": { "type": "Point", "coordinates": [120.301, 22.639] },
    "type": "其他",
    "is_primary": false
  }
  // ... 其他屬於該使用者的地點
]

說明：
- 主要地點 (is_primary: true) 會排在最前面
- 用於前端下拉選單或地點選擇器
- 若需完整地址資訊，請從 coordinates 反查或使用其他 API
 */