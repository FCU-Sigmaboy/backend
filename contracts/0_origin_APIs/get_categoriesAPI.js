import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取分類 API (Category APIs)
// ===================================================================

/**
 * 【功能】取所有主分類，以及它們各自巢狀的子分類
 * (用於首頁、篩選器、刊登時的選擇...等，使用前端 select() 實現)
 *
 * @returns {Promise<Array>}
 */
export async function getAllCategories() {

    // 1. 這是您的 DTO。
    //    我們查詢 'main_categories'，並要求它同時抓取
    //    所有關聯的 'sub_categories' (欄位名稱必須與資料表名稱匹配)
    const selectQuery = `
    id,
    name,
    sub_categories (
      id,
      name,
      default_carbon_value
    )
  `;

    // 2. 建立查詢
    const { data, error } = await supabase
        .from('main_categories')
        .select(selectQuery)
        .order('id', { ascending: true }) // 排序主分類
        .order('id', { foreignTable: 'sub_categories', ascending: true }); // 排序子分類

    // 3. 錯誤處理
    if (error) {
        console.error('Supabase 獲取分類失敗:', error);
        throw new Error(error.message);
    }

    // 4. data 本身就是您需要的巢狀 JSON 陣列，直接回傳
    return data;
}

/* data 範例
[
  {
    "id": 1,
    "name": "電子產品",
    "sub_categories": [
      {
        "id": 1,
        "name": "手機",
        "default_carbon_value": "5.20"
      },
      {
        "id": 2,
        "name": "筆記型電腦",
        "default_carbon_value": "8.50"
      }
    ]
  },
  {
    "id": 2,
    "name": "居家生活",
    "sub_categories": [
      {
        "id": 3,
        "name": "家具",
        "default_carbon_value": "15.00"
      },
      {
        "id": 4,
        "name": "廚房用品",
        "default_carbon_value": "3.10"
      }
    ]
  },
  {
    "id": 3,
    "name": "書籍文具",
    "sub_categories": [] // 如果某主分類下沒有子分類，會回傳空陣列
  }
]*/