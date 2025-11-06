import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 追蹤 API (Following APIs)
// ===================================================================

/**
 * 【功能】取消追蹤指定的使用者 (前端 delete)
 * @param {string} followingUserId - 您要取消追蹤的使用者的 UUID
 * @returns {Promise<boolean>} - 回傳 true 表示成功
 */
export async function unfollowUser(followingUserId) {
    // 1. 獲取當前登入者 ID (追蹤者 ID)
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        throw new Error('使用者未登入，無法取消追蹤');
    }
    const followerId = user.id;

    // 2. 執行刪除操作
    //    RLS 策略會自動確保 follower_id === auth.uid()
    const { error } = await supabase
        .from('following')
        .delete()
        .match({
            follower_id: followerId, // 要刪除的記錄的 follower_id
            following_id: followingUserId // 要刪除的記錄的 following_id
        });

    // 3. 錯誤處理
    // 如果失敗（例如未登入、網路錯誤、或 RLS 阻止），則會拋出錯誤。它不會回傳 JSON 資料。
    if (error) {
        console.error(`Supabase 取消追蹤使用者 #${followingUserId} 失敗:`, error);
        throw new Error(error.message); // 將錯誤往上拋
    }

    // 4. 回傳成功
    console.log(`Successfully unfollowed user #${followingUserId}`);
    return true;
}

