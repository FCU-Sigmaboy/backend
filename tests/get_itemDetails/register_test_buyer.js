// =============================================
// 自動化註冊測試買家 Tao（簡化重構版）
// =============================================
import dotenv from 'dotenv';
dotenv.config({ path: '.env.local' });
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

const BUYER_EMAIL = 'tao_test@example.com';
const BUYER_PASSWORD = 'testpassword';
const BUYER_ID = '3ee322ff-f883-4d18-b5bd-0f6656488bb2';

console.log('=============================================');
console.log('Supabase URL:', supabaseUrl);
console.log('Supabase Key:', supabaseKey ? '已載入' : '未載入');
console.log('註冊買家 Email:', BUYER_EMAIL);
console.log('=============================================');

async function upsertUser(userId, nickname) {
  // upsert: 若已存在則不重複插入
  const { error } = await supabase
    .from('users')
    .upsert([{ id: userId, nickname }], { onConflict: ['id'] });
  if (error) {
    console.error('❌ upsert public.users 失敗:', error.message);
    return false;
  }
  console.log('✅ public.users upsert 成功');
  return true;
}

async function upsertLocation(userId) {
  const locationPayload = {
    user_id: userId,
    coordinates: 'SRID=4326;POINT(120.6493 24.1795)',
    type: '家',
    is_primary: true,
    formatted_address: '台中市西屯區'
  };
  // upsert: 根據 user_id + is_primary
  const { error } = await supabase
    .from('locations')
    .upsert([locationPayload], { onConflict: ['user_id', 'is_primary'] });
  if (error) {
    console.error('❌ upsert locations 失敗:', error.message);
    return false;
  }
  console.log('✅ locations upsert 成功');
  return true;
}

async function registerBuyer() {
  let userId = BUYER_ID;
  let nickname = BUYER_EMAIL.split('@')[0];
  let registered = false;
  // 註冊
  const { data, error } = await supabase.auth.signUp({
    email: BUYER_EMAIL,
    password: BUYER_PASSWORD
  });
  if (error) {
    if (error.message && error.message.includes('already registered')) {
      console.warn('⚠️ 帳號已註冊，直接使用 BUYER_ID');
      registered = true;
    } else {
      console.error('❌ 註冊失敗:', error.message);
      return;
    }
  } else {
    userId = data.user.id;
    nickname = data.user.email.split('@')[0];
    registered = true;
    console.log('✅ 註冊成功！用戶 ID:', userId);
  }
  // upsert users
  await upsertUser(userId, nickname);
  // upsert locations
  await upsertLocation(userId);
}

registerBuyer();
