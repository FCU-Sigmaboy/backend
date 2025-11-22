import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 更新個人 Profile API (User Profile APIs)
// ===================================================================

/**
 * 【功能】更新 "當前登入者" 的 Profile 和 Locations (RPC)
 * @param {object} userData - 只包含 "有變動" 的 users 欄位 (e.g., { nickname: '...', profile_picture_url: '...' })
 * @param {object} profileData - 只包含 "有變動" 的 profiles 欄位 (e.g., { balance: ... })
 * @param {Array<object>} locationsArray - **所有** locations 物件的陣列 (包含 id 給現有的, 不含 id 給新增的)
 * 每個物件應包含: id (可選), coordinates ({latitude, longitude}), type, is_primary, formatted_address
 * @returns {Promise<object>} - 回傳更新後的 profile 物件 (包含巢狀 locations)
 */
export async function updateMyProfile(userData, profileData, locationsArray) {

    // 1. 準備 RPC 參數
    const rpcParams = {
        p_user_data: userData,
        p_profile_data: profileData,
        p_locations_data: locationsArray.map(loc => ({
            ...loc,
            // 確保 coordinates 格式符合 RPC 預期
            coordinates: {
                latitude: loc.coordinates?.coordinates?.[1] || loc.coordinates?.latitude, // 兼容 GeoJSON 或 {lat, lon}
                longitude: loc.coordinates?.coordinates?.[0] || loc.coordinates?.longitude
            }
        }))
    };

    // 2. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('update_my_profile', rpcParams);

    if (error) {
        console.error('Supabase 更新 Profile 失敗:', error);
        throw new Error(error.message);
    }

    // 3. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/* data 範例
{
  "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "nickname": "Joseph (已更新)",
  "profile_picture_url": "https://.../new_avatar.jpg",
  "avg_rating": "4.80",
  "profile_details": {
    "balance": 600,
    "carbon_saved_kg": "25.50",
    "updated_at": "2025-10-19T05:57:00.123+00:00"
  },
  "locations": [
    {
      "id": 12,
      "user_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "coordinates": { "type": "Point", "coordinates": [120.646, 24.180] },
      "type": "家",
      "is_primary": true,
      "formatted_address": "台中市西屯區福星路 (新)",
      "created_at": "2025-01-20T10:00:00.789+00:00",
      "updated_at": "2025-10-19T05:57:00.123+00:00"
    },
    {
      "id": 15,
      "user_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "coordinates": { "type": "Point", "coordinates": [120.671, 24.141] },
      "type": "公司 (新址)",
      "is_primary": false,
      "formatted_address": "台中市南屯區公益路 (新)",
      "created_at": "2025-03-10T09:00:00.000+00:00",
      "updated_at": "2025-10-19T05:57:00.123+00:00"
    },
    {
      "id": 55, // 這是新插入的 ID
      "user_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
      "coordinates": { "type": "Point", "coordinates": [121.500, 25.050] },
      "type": "次要地點",
      "is_primary": false,
      "formatted_address": "台北市中山區新地址",
      "created_at": "2025-10-19T05:57:00.123+00:00",
      "updated_at": "2025-10-19T05:57:00.123+00:00"
    }
  ]
}
 */