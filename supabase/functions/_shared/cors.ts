/**
 * CORS (Cross-Origin Resource Sharing) 配置
 * 
 * 這個檔案定義了 Edge Functions 的 CORS headers，
 * 允許前端應用從不同的網域存取 API。
 */

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
}
