import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取我追蹤的人列表 API (Get My Following API)
// ===================================================================

/**
 * 【功能】獲取我追蹤的人列表 (RPC)
 * @param {Object} params - 查詢參數
 * @param {number} [params.page=1] - 頁碼，預設為 1
 * @param {number} [params.pageSize=20] - 每頁數量，預設為 20
 * @param {string} [params.sortBy='followed_at'] - 排序欄位 ('followed_at', 'nickname')
 * @param {string} [params.sortDirection='desc'] - 排序方向 ('asc', 'desc')
 * @param {string} [params.search=''] - 搜尋關鍵字（搜尋用戶名稱）
 * @returns {Promise<Array>} - 回傳追蹤中的用戶列表
 */
export async function getMyFollowing(params = {}) {
    // 1. 設定預設參數
    const {
        page = 1,
        pageSize = 20,
        sortBy = 'followed_at',
        sortDirection = 'desc',
        search = ''
    } = params;

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_page: page,
        p_page_size: pageSize,
        p_sort_by: sortBy,
        p_sort_direction: sortDirection,
        p_search: search
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_my_following', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error('獲取追蹤中列表失敗:', error);
        throw new Error(error.message);
    }

    // 5. 回傳資料
    return data || [];
}

/* 回傳 data 範例
[
  {
    "user_id": "7140056b-c71c-489f-8f57-2eeb1694713e",
    "nickname": "Lee",
    "profile_picture_url": "https://example.com/avatar3.jpg",
    "followed_at": "2024-09-20T14:15:00Z"
  },
  {
    "user_id": "9b900884-10cf-416c-bb5d-e577c4fbacba",
    "nickname": "Lin",
    "profile_picture_url": "https://example.com/avatar4.jpg",
    "followed_at": "2024-09-25T16:45:00Z"
  }
]
*/
