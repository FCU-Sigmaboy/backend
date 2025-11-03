import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 取消收藏 API (Favorite APIs)
// ===================================================================

/**
 * 【功能】將指定物品從 "當前登入者" 的收藏中移除 (前端 delete)
 * @param {number} itemId - 您要取消收藏的物品 ID
 * @returns {Promise<boolean>} - 回傳 true 表示成功
 */
export async function removeFavoriteItem(itemId) {
    // 1. 獲取當前登入者 ID
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
        throw new Error('使用者未登入，無法取消收藏');
    }
    const userId = user.id;

    // 2. 執行刪除操作
    //    RLS 策略會自動確保 user_id === auth.uid()
    const { error } = await supabase
        .from('favorites')
        .delete()
        .match({
            user_id: userId, // 要刪除的記錄的 user_id
            item_id: itemId   // 要刪除的記錄的 item_id
        });

    // 3. 錯誤處理
    if (error) {
        console.error(`Supabase 取消收藏 #${itemId} 失敗:`, error);
        throw new Error(error.message); // 將錯誤往上拋
    }

    // 4. 回傳成功
    console.log(`Successfully removed item #${itemId} from favorites`);
    return true;
}