import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 使用者 Profile API (User Profile APIs)
// ===================================================================

/**
 * 【功能】獲取 "當前登入者" 的完整 profile 和 "所有" 地址 (select)
 * (用於 "編輯個人檔案" 頁面)
 * @returns {Promise<object | null>} - 成功則回傳 profile 物件，未登入則回傳 null
 */
export async function getMyProfileForEdit() {
    // 1. 獲取當前登入的使用者
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        // 如果未登入，直接回傳 null 或根據您的應用邏輯處理
        console.log('getMyProfileForEdit: User not logged in.');
        return null;
    }

    // 2. 定義您要的 DTO (巢狀結構)
    //    我們查詢 'users' 表，並巢狀抓取關聯的 'profiles' 和 'locations'
    const selectQuery = `
    id,
    nickname,
    profile_picture_url,
    avg_rating,
    created_at,
    profiles (
      balance,
      carbon_saved_kg,
      updated_at
    ),
    locations (
      id,
      coordinates,
      type,
      is_primary,
      formatted_address,
      created_at,
      updated_at
    )
  `;

    // 3. 建立查詢
    const { data, error } = await supabase
        .from('users')
        .select(selectQuery)
        .eq('id', user.id) // 確保只抓 "我" 的
        .order('is_primary', { foreignTable: 'locations', ascending: false }) // locations 陣列排序
        .order('id', { foreignTable: 'locations', ascending: true })
        .single(); // 我們預期 "我" 只有一筆 users 紀錄

    // 4. 錯誤處理
    if (error) {
        // 如果 .single() 找不到資料 (code PGRST200)，可能是 users 或 profiles 尚未建立
        if (error.code === 'PGRST200') {
            console.warn(`getMyProfileForEdit: Profile data not found for user ${user.id}. Need initial setup?`);
            // 您可能需要根據使用者是否首次登入來處理這個情況
            // 這裡先回傳基礎的 users 資料
            return { id: user.id, nickname: user.email }; // 或是其他預設值
        }
        console.error('Supabase 獲取 MyProfile 失敗:', error);
        throw new Error(error.message);
    }

    // 5. 處理 profiles (1:1 關聯，但 select 可能回傳陣列)
    if (data && data.profiles && Array.isArray(data.profiles)) {
        data.profile_details = data.profiles[0] || null; // 解開陣列
        delete data.profiles; // 移除原始欄位
    } else if (data && data.profiles && typeof data.profiles === 'object') {
        // 如果 Supabase 正確回傳物件
        data.profile_details = data.profiles;
        delete data.profiles;
    } else if (data) {
        data.profile_details = null; // 確保有這個欄位
    }


    // 6. data 本身就是您要的巢狀 JSON，直接回傳
    return data;
}

/* data 範例
{
  "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "nickname": "Joseph",
  "profile_picture_url": "https://.../storage/.../joseph.jpg",
  "avg_rating": "4.80",
  "created_at": "2025-01-15T08:00:00.123+00:00",
  "profile_details": {
    "balance": 500,
    "carbon_saved_kg": "25.50",
    "updated_at": "2025-09-20T14:30:00.456+00:00"
  },
  "locations": [
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
    }
    // ... 其他地點
  ]
}
 */