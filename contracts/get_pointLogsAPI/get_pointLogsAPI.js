// ===================================================================
// ### 點數/日誌 API (Point Log APIs)
// ===================================================================

/**
 * 【新功能】查詢 "當前登入者" 的點數變動紀錄 (RPC 版)
 * @param {object} options - 分頁與篩選選項
 * @param {number} [options.page=1] - 頁碼
 * @param {number} [options.size=20] - 每頁筆數
 * @param {string} [options.logType] - 篩選日誌類型 (e.g., 'transaction_income')
 * @returns {Promise<Array | null>} - 回傳點數日誌陣列, 未登入回傳 null
 */
export async function getPointLogs(options = {}) {
    // 1. 獲取當前登入者
    const {data: {user}} = await supabase.auth.getUser();
    if (!user) {
        console.warn('getPointLogs: User not logged in.');
        return null;
    }

    // 2. 準備 RPC 參數 (欄位名需匹配 RPC 函式)
    const rpcParams = {
        p_page: options.page || 1,
        p_size: options.size || 20,
        p_log_type: options.logType || null
    };

    // 3. 呼叫 RPC
    const {data, error} = await supabase.rpc('get_point_logs', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error('Supabase 獲取點數日誌失敗:', error);
        throw new Error(error.message);
    }

    // 5. 回傳
    return data;
}

/**
 * 回傳 data 範例:
 [
 {
 "amount": 20,
 "type": "daily_login",
 "description": "每日簽到獎勵 (連續 8 天)",
 "created_at": "2025-11-14T08:00:00+00:00",
 "transaction_id": null
 },
 {
 "amount": -500,
 "type": "transaction_expense",
 "description": "支付 (託管) 物品：IKEA 檯燈",
 "created_at": "2025-11-13T15:30:00+00:00",
 "transaction_id": 105
 },
 {
 "amount": 500,
 "type": "transaction_income",
 "description": "售出物品：二手登山背包",
 "created_at": "2025-11-10T10:00:00+00:00",
 "transaction_id": 101
 },
 {
 "amount": 20000,
 "type": "initial_gift",
 "description": "新使用者/資料同步 - 初始點數",
 "created_at": "2025-11-01T00:00:00+00:00",
 "transaction_id": null
 }
 ]
 */

