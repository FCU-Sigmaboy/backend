/**
 * Supabase Client 配置
 *
 * 這個檔案初始化 Supabase 客戶端，供整個應用程式使用。
 * 使用環境變數來管理 API 金鑰，確保安全性。
 */
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// 驗證環境變數是否存在
if (!supabaseUrl || !supabaseAnonKey) {
  console.error('缺少必要的 Supabase 環境變數！')
  console.error('請確認 .env.staging 檔案中包含 VITE_SUPABASE_URL 和 VITE_SUPABASE_ANON_KEY')
}

/**
 * Supabase 客戶端實例
 *
 * 這個客戶端會自動處理：
 * - 認證狀態管理
 * - API 請求的 Authorization header
 * - 自動重試失敗的請求
 */
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
})
