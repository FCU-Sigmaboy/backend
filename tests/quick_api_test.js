// =============================================
// 測試場景：
//   買家：Tao (ID: 3ee322ff-f883-4d18-b5bd-0f6656488bb2)
//   賣家：
//     'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788',  // Yo
//     '7140056b-c71c-489f-8f57-2eeb1694713e',  // Lee
//     '9b900884-10cf-416c-bb5d-e577c4fbacba',  // Lin
//     'c8d6998b-79e3-4d56-a9ef-689eed9bd823',  // Liao
//     'e773c5f7-172c-4976-a7be-d537a7e6e71e'   // Chen（5 個）
//   目標：測試買家瀏覽各賣家物品時的距離計算
//   特點：RPC 函數自動使用資料庫位置，無需傳遞座標參數
// =============================================

import dotenv from 'dotenv';
dotenv.config({ path: '.env.local' });
import { createClient } from '@supabase/supabase-js';

// ====== 參數設定 ======
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

const BUYER_EMAIL = 'tao_test@example.com';
const BUYER_PASSWORD = 'testpassword';
const BUYER_ID = '3ee322ff-f883-4d18-b5bd-0f6656488bb2';
const SELLER_IDS = [
  'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', // Yo
  '7140056b-c71c-489f-8f57-2eeb1694713e', // Lee
  '9b900884-10cf-416c-bb5d-e577c4fbacba', // Lin
  'c8d6998b-79e3-4d56-a9ef-689eed9bd823', // Liao
  'e773c5f7-172c-4976-a7be-d537a7e6e71e'  // Chen
];

console.log('=============================================');
console.log('Supabase URL:', supabaseUrl);
console.log('Supabase Key:', supabaseKey ? '已載入' : '未載入');
console.log('買家 Email:', BUYER_EMAIL);
console.log('買家 ID:', BUYER_ID);
console.log('賣家 ID:', SELLER_IDS.join(', '));
console.log('=============================================');

// ====== 登入買家，取得 session ======
async function loginBuyer() {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: BUYER_EMAIL,
    password: BUYER_PASSWORD
  });
  if (error || !data?.session) {
    console.error('❌ 買家登入失敗:', error?.message);
    return null;
  }
  await supabase.auth.setSession({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token
  });
  console.log('✅ 買家登入成功，session 已設置');
  return data.user;
}

// ====== 查詢指定賣家物品 ======
async function fetchSellerItems(sellerId) {
  const { data, error } = await supabase
    .from('items')
    .select('id, title, user_id')
    .eq('user_id', sellerId)
    .eq('listing_status', true)
    .limit(5);
  if (error || !data) {
    console.error(`❌ 查詢賣家 ${sellerId} 物品失敗:`, error?.message);
    return [];
  }
  return data;
}

// ====== 呼叫 API 並顯示完整資料 ======
async function testGetItemDetails(itemId, session) {
  let headers = {};
  if (session) {
    headers = { Authorization: `Bearer ${session.access_token}` };
  }
  const { data, error } = await supabase
    .rpc('get_item_details_with_location', { p_item_id: itemId }, { headers });
  if (error) {
    console.error('❌ API 呼叫失敗:', error.message);
    return;
  }
  console.log('✅ 物品ID:', itemId);
  console.log('✅ API 回傳資料：', JSON.stringify(data, null, 2));
}

// ====== 主流程 ======
(async () => {
  // 登入買家
  const session = await loginBuyer();
  // 依序查詢每個賣家現有物品
  for (const sellerId of SELLER_IDS) {
    console.log(`--- 查詢賣家 ${sellerId} 物品 ---`);
    const items = await fetchSellerItems(sellerId);
    if (items.length === 0) {
      console.log('（無物品）');
      continue;
    }
    for (const item of items) {
      // 登入買家查詢
      console.log('--- 登入買家查詢 ---');
      await testGetItemDetails(item.id, session);
      // 未登入查詢
      console.log('--- 未登入查詢 ---');
      await testGetItemDetails(item.id, null);
    }
  }
})();
