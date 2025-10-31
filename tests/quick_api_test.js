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
async function fetchSellerItems() {
  const { data, error } = await supabase
    .from('items')
    .select('id, title, user_id')
    .in('user_id', SELLER_IDS)
    .eq('listing_status', true)
    .limit(10);
  if (error || !data) {
    console.error('❌ 查詢賣家物品失敗:', error?.message);
    return [];
  }
  return data;
}

// ====== RPC 查詢物品距離 ======
async function fetchItemDistance(itemId) {
  const { data, error } = await supabase.rpc('get_item_details_with_location', {
    p_item_id: itemId,
  }).maybeSingle();
  if (error) {
    console.error('❌ RPC error:', error.message);
    return null;
  }
  return data;
}

// ====== 主流程 ======
(async () => {
  console.log('【步驟 1】登入買家...');
  const buyer = await loginBuyer();
  if (!buyer) return;
  console.log('✅ 買家:', buyer.email, buyer.id);

  console.log('【步驟 2】查詢指定賣家物品...');
  const items = await fetchSellerItems();
  if (!items.length) {
    console.log('❌ 無指定賣家物品可測試');
    return;
  }
  console.log('✅ 指定賣家物品：', items.map(i => i.title).join(', '));

  console.log('【步驟 3】依序查詢距離...');
  for (const item of items) {
    const result = await fetchItemDistance(item.id);
    console.log('---------------------------------------------');
    console.log(`物品: ${item.title} (ID: ${item.id})`);
    if (result && result.distance_km !== undefined) {
      console.log('distance_km:', result.distance_km);
    } else {
      console.log('無距離資訊（未登入或資料缺失）');
    }
  }
  console.log('=============================================');
  console.log('✅ 測試流程結束');
})();
