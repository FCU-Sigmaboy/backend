// ===================================================================
// ### 使用者 PointsProfile API
// ### 對應 Supabase RPC 函式：get_user_points_profile
// ### 因尚未有複雜的等級計算邏輯，RPC 回傳的 current_level_tier 和 trust_level_tier 暫時先寫死
// ===================================================================

/**
 * 【新功能】獲取使用者點數詳情 (RPC)
 * 包含餘額、總賺取、總花費、連續登入天數等統計數據
 * @returns {Promise<object>} - User points profile object
 */
export async function getUserPointsProfile() {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_user_points_profile');

    // Debug log
    console.log('getUserPointsProfile called');

    // 3. 錯誤處理
    if (error) {
        console.error('Supabase 獲取點數詳情失敗:', error);
        throw new Error(error.message);
    }

    // 4. 回傳 RPC 回傳的 JSON 結果
    return data;
}
/**
 * 回傳 data 範例
 * {
 *   "user_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
 *   "current_balance": 500,
 *   "total_earned": 1200,
 *   "total_spent": 700,
 *   "daily_streak": 7,
 *   "last_signin_date": "2025-11-06",
 *   "current_level_tier": 2,             （暫時寫死）
 *   "trust_level_tier": 1,               （暫時寫死）
 *   "total_sales_points": 450,
 *   "created_at": "2025-01-01T00:00:00+00:00",
 *   "updated_at": "2025-11-06T12:30:00+00:00"
 * }
 */