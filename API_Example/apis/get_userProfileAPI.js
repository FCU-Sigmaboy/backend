import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 使用者的公開 Profile API (User Profile APIs)
// ===================================================================

/**
 * 【功能】獲取單一使用者的公開 profile 頁面資料 (RPC)
 * @param {string} userId - 您要查看的使用者的 UUID
 * @returns {Promise<object | null>} - 成功則回傳 profile 物件，找不到則回傳 null
 */
export async function getPublicUserProfile(userId) {
    // 1. 準備 RPC 參數
    const rpcParams = {
        p_user_id: userId
    };

    // 2. 呼叫 RPC 函式
    const { data, error } = await supabase
        .rpc('get_public_user_profile', rpcParams)
        .single(); // <-- 因為我們預期只回傳一個 JSON 物件

    // 3. 錯誤處理
    if (error) {
        // 如果 .single() 找不到資料 (code PGRST200)，回傳 null 代表使用者不存在
        if (error.code === 'PGRST200') {
            console.warn(`Profile for user #${userId} not found.`);
            return null;
        }
        // 其他錯誤則拋出
        console.error(`Supabase 獲取 Profile #${userId} 失敗:`, error);
        throw new Error(error.message);
    }

    // 4. 回傳 RPC 回傳的 JSON 物件
    return data;
}

/* data 範例
{
  "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "nickname": "Joseph",
  "profile_picture_url": "https://.../storage/.../joseph.jpg",
  "avg_rating": 4.80,
  "created_at": "2025-01-15T08:00:00.123+00:00",
  "formatted_address": "台中市西屯區福星路123號",
  "following_count": 100,
  "followers_count": 80
}
 */