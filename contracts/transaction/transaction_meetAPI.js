/**
 * 【新功能】(API 6 - 買家) 輸入代碼以完成交易 (RPC)
 * @param {number} transactionId - 交易 ID
 * @param {string} code - 賣家提供的 6 位數代碼
 * @returns {Promise<object>} - 回傳 { success: true, message: '交易完成', ... }
 */
export async function finalizeTransactionWithCode(transactionId, code) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_transaction_id: transactionId,
        p_confirmation_code: code
    };

    // 3. 呼叫 RPC
    const { data, error } = await supabase.rpc('finalize_transaction_with_code', rpcParams);

    // 4. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error(`Supabase 完成交易 #${transactionId} 失敗:`, error);
        throw new Error(error.message); // (例如 "確認碼錯誤")
    }
    return data;
}