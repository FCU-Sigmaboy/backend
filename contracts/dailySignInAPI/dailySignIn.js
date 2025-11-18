// 假設您已在 src/supabaseClient.js 初始化

/**
 * 【新功能】執行每日簽到 (RPC)
 * (呼叫 V3 版 RPC)
 * @returns {Promise<object>} - 回傳操作結果 (符合您要的 DTO)
 */
export async function dailySignIn() {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 呼叫 RPC 函式 (不需要參數)
    const { data, error } = await supabase.rpc('daily_check_in');

    // Debug log
    console.log('dailySignIn called');

    // 3. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error('Supabase 每日簽到失敗:', error);
        throw new Error(error.message);
    }

    // 4. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/**
 * 回傳 data 範例
 *
 * 情境 1：簽到成功 (連續第 8 天)
 * (昨日已簽到，連續天數 7 -> 8)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 5,
 *   "streak_day": 8,
 *   "next_reward": 6,
 *   "new_balance": 1005
 * }
 *
 *
 * 情境 2：簽到成功 (連續第 7 天 - 觸發獎勵)
 * (昨日已簽到，連續天數 6 -> 7)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 20,
 *   "streak_day": 7,
 *   "next_reward": 7,
 *   "new_balance": 1000
 * }
 *
 *
 * 情境 3：簽到成功 (連續第 3 天 - 觸發獎勵)
 * (昨日已簽到，連續天數 2 -> 3)
 * {
 *   "success": true,
 *   "message": "簽到成功！",
 *   "points_awarded": 10,
 *   "streak_day": 3,
 *   "next_reward": 4,
 *   "new_balance": 810
 * }
 */