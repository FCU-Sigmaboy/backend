import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取我的追蹤者列表 API (Get My Followers API)
// ===================================================================

/**
 * 【功能】獲取追蹤我的人列表 (RPC)
 * @param {Object} params - 查詢參數
 * @param {number} [params.page=1] - 頁碼，預設為 1
 * @param {number} [params.pageSize=20] - 每頁數量，預設為 20
 * @param {string} [params.sortBy='followed_at'] - 排序欄位 ('followed_at', 'nickname')
 * @param {string} [params.sortDirection='desc'] - 排序方向 ('asc', 'desc')
 * @param {string} [params.search=''] - 搜尋關鍵字（搜尋用戶名稱）
 * @returns {Promise<Array>} - 回傳追蹤者列表
 */
export async function getMyFollowers(params = {}) {
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
    const { data, error } = await supabase.rpc('get_my_followers', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error('獲取追蹤者列表失敗:', error);
        throw new Error(error.message);
    }

    // 5. 回傳資料
    return data || [];
}

/* 回傳 data 範例
[
  {
    "user_id": "488a4712-dd63-4938-9679-336f434ad263",
    "nickname": "Tao",
    "profile_picture_url": "https://example.com/avatar1.jpg",
    "followed_at": "2024-10-10T08:30:00Z",
    "is_following_back": true
  },
  {
    "user_id": "cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788",
    "nickname": "Yo",
    "profile_picture_url": "https://example.com/avatar2.jpg",
    "followed_at": "2024-10-15T10:20:00Z",
    "is_following_back": false
  }
]
*/
