import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 我的地點 API (Location APIs)
// ===================================================================

/**
 * 【功能】獲取 "當前登入者" 儲存的所有 location
 * (用於刊登物品時的 "選擇地點" 下拉選單或列表)
 * @returns {Promise<Array | null>} - 回傳 location 陣列, 未登入回傳 null
 */
export async function getMyLocations() {
    // 1. "前置作業": 獲取當前登入的使用者
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        console.warn('getMyLocations: User not logged in.');
        return null; // 未登入則不執行查詢
    }

    // 2. 這是您要的 DTO (包含所有需要顯示的欄位)
    const selectQuery = `
    id,
    coordinates,
    type,
    is_primary,
    formatted_address,
    created_at,
    updated_at
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

/* data 範例
[
  {
    "id": 12,
    "coordinates": { "type": "Point", "coordinates": [120.645, 24.179] },
    "type": "家",
    "is_primary": true,
    "formatted_address": "台中市西屯區福星路123號",
    "created_at": "2025-01-20T10:00:00.789+00:00",
    "updated_at": "2025-09-15T11:00:00.000+00:00"
  },
  {
    "id": 15,
    "coordinates": { "type": "Point", "coordinates": [120.670, 24.140] },
    "type": "公司",
    "is_primary": false,
    "formatted_address": "台中市南屯區公益路二段51號",
    "created_at": "2025-03-10T09:00:00.000+00:00",
    "updated_at": "2025-03-10T09:00:00.000+00:00"
  },
  {
    "id": 42,
    "coordinates": { "type": "Point", "coordinates": [120.301, 22.639] },
    "type": "次要地點",
    "is_primary": false,
    "formatted_address": "高雄市左營區站前北路1號",
    "created_at": "2025-08-15T18:00:00.000+00:00",
    "updated_at": "2025-08-15T18:00:00.000+00:00"
  }
  // ... 其他屬於該使用者的地點
]
 */