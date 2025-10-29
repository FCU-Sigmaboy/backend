/**
 * CORS (Cross-Origin Resource Sharing) 配置
 *
 * 這個檔案定義了 Edge Functions 的 CORS headers，
 * 允許前端應用從不同的網域存取 API。
 *
 * 在生產環境中，建議將 Access-Control-Allow-Origin 限制為特定網域，
 * 而不是使用 '*' (允許所有網域)。
 */

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // 生產環境建議改為具體的網域，例如：'https://yourdomain.com'
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
}

/**
 * 生產環境範例：
 *
 * export const corsHeaders = {
 *   'Access-Control-Allow-Origin': 'https://yourdomain.com',
 *   'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
 *   'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
 * }
 */
